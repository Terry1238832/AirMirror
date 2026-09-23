import Foundation
import os

struct ReceiverEvent: Equatable {
    enum Kind: Equatable {
        case started
        case advertising
        case connected(client: String)
        case disconnected
        case pin(String)
        case failed(String)
        case log(String)
        case exited(Int32)
    }

    let kind: Kind
}

final class ReceiverEngine {
    private let logger = Logger(subsystem: "com.liangyu.airmirror", category: "engine")
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    var onEvent: ((ReceiverEvent) -> Void)?

    var isRunning: Bool { process?.isRunning == true }

    func start(name: String, requirePin: Bool, deviceMAC: String, quality: StreamQuality, fps: StreamFPS, videoSocket: String) throws {
        stop()

        guard let executable = EngineLocator.find() else {
            throw EngineError.missingBinary
        }

        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = EngineLocator.supportDirectory

        var arguments = [
            "-n", name,
            "-nh",
            "-vsync", "no",
            "-nohold",
            "-s", quality.sizeArgument,
            "-fps", String(fps.rawValue),
            "-vd", "vtdec",
            "-vs", "fakesink",
            "-as", "osxaudiosink",
            "-m", deviceMAC,
            "-reset", "0"
        ]
        if requirePin {
            arguments.append("-pin")
        }
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        let extraPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/Library/Frameworks/GStreamer.framework/Commands"
        ]
        let path = ((environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init) + extraPaths)
            .reduce(into: [String]()) { result, item in
                if !result.contains(item) { result.append(item) }
            }
            .joined(separator: ":")
        environment["PATH"] = path
        environment["HOME"] = NSHomeDirectory()
        let rc = EngineLocator.supportDirectory.appendingPathComponent("uxplayrc")
        if !FileManager.default.fileExists(atPath: rc.path) {
            try? "# 镜投 runtime config\n".write(to: rc, atomically: true, encoding: .utf8)
        }
        environment["UXPLAYRC"] = rc.path
        let bundledPlugins = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/gstreamer")
        if FileManager.default.fileExists(atPath: bundledPlugins.path) {
            environment["GST_PLUGIN_PATH"] = bundledPlugins.path
            environment["GST_PLUGIN_SYSTEM_PATH"] = ""
            environment["GST_PLUGIN_SYSTEM_PATH_1_0"] = ""
            environment["GST_REGISTRY_FORK"] = "no"
            let registry = EngineLocator.supportDirectory.appendingPathComponent("gstreamer-1.0-registry.bin")
            environment["GST_REGISTRY"] = registry.path
        } else {
            let brewPrefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
            let pluginPath = "\(brewPrefix)/lib/gstreamer-1.0"
            if FileManager.default.fileExists(atPath: pluginPath) {
                environment["GST_PLUGIN_PATH"] = pluginPath
            }
            let libPath = "\(brewPrefix)/lib"
            if FileManager.default.fileExists(atPath: libPath) {
                environment["DYLD_FALLBACK_LIBRARY_PATH"] = libPath
            }
        }
        environment["LANG"] = "en_US.UTF-8"
        environment["AIRMIRROR_VIDEO_SOCK"] = videoSocket
        process.environment = environment

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.standardInput = FileHandle.nullDevice

        attach(pipe: outputPipe, isError: false)
        attach(pipe: errorPipe, isError: true)

        process.terminationHandler = { [weak self] finished in
            let code = finished.terminationStatus
            DispatchQueue.main.async {
                self?.onEvent?(.init(kind: .exited(code)))
            }
        }

        try process.run()
        self.process = process
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        onEvent?(.init(kind: .started))
        logger.info("uxplay started \(quality.rawValue) \(fps.rawValue)fps: \(executable.path, privacy: .public)")
    }

    func stop() {
        guard let process else { return }
        process.terminationHandler = nil
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        self.process = nil
        outputPipe = nil
        errorPipe = nil
        stdoutBuffer = ""
        stderrBuffer = ""
    }

    private func attach(pipe: Pipe, isError: Bool) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.consume(chunk, isError: isError)
            }
        }
    }

    private func consume(_ chunk: String, isError: Bool) {
        if isError {
            stderrBuffer += chunk
            emitLines(from: &stderrBuffer)
        } else {
            stdoutBuffer += chunk
            emitLines(from: &stdoutBuffer)
        }
    }

    private func emitLines(from buffer: inout String) {
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(..<range.upperBound)
            guard !line.isEmpty else { continue }
            interpret(line)
        }
    }

    private func interpret(_ line: String) {
        onEvent?(.init(kind: .log(line)))
        logger.debug("uxplay: \(line, privacy: .public)")

        let lower = line.lowercased()

        if lower.contains("initialized server socket") {
            onEvent?(.init(kind: .advertising))
        }

        if let client = parseClient(from: line) {
            onEvent?(.init(kind: .connected(client: client)))
        }

        if lower.contains("lost connection with client") ||
            lower.contains("tcp socket was closed by client") ||
            lower.contains("video stream is stopping") ||
            lower.contains("video window closed by user") {
            onEvent?(.init(kind: .disconnected))
        }

        if let pin = parsePin(from: line) {
            onEvent?(.init(kind: .pin(pin)))
        }

        if lower.contains("could not initialize dnssd") ||
            (lower.contains("gstreamer") && lower.contains("error")) {
            onEvent?(.init(kind: .failed(line)))
        }
    }

    private func parseClient(from line: String) -> String? {
        if let regex = try? NSRegularExpression(pattern: #"connection request from (.+) \((.+)\) with deviceID"#),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
           let nameRange = Range(match.range(at: 1), in: line) {
            let name = String(line[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }
        return nil
    }

    private func parsePin(from line: String) -> String? {
        let regex = try? NSRegularExpression(pattern: #"PIN\s*=\s*\"?(\d{4})\"?"#)
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        if let match = regex?.firstMatch(in: line, range: range),
           let pinRange = Range(match.range(at: 1), in: line) {
            return String(line[pinRange])
        }
        return nil
    }
}

enum EngineError: LocalizedError {
    case missingBinary

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            return "还没有投屏引擎。请先运行 AirMirror/build.sh 完成安装。"
        }
    }
}
