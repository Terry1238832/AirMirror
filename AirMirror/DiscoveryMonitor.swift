import Foundation
import Network

@MainActor
final class DiscoveryMonitor: ObservableObject {
    @Published private(set) var isVisibleOnLan = false

    private var browser: NWBrowser?
    private var expectedName = ""

    func start(lookingFor name: String) {
        stop()
        expectedName = name
        isVisibleOnLan = false

        let expected = expectedName
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_airplay._tcp", domain: "local.")
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.stateUpdateHandler = { _ in }
        browser.browseResultsChangedHandler = { results, _ in
            let visible = results.contains { result in
                if case let .service(serviceName, type, _, _) = result.endpoint {
                    return type.contains("airplay") && serviceName == expected
                }
                return false
            }
            Task { @MainActor [weak self] in
                self?.isVisibleOnLan = visible
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isVisibleOnLan = false
    }
}
