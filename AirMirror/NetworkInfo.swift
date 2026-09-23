import Foundation
import Darwin

enum NetworkInfo {
    static func ipv4Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(first) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP,
                  (flags & IFF_LOOPBACK) != IFF_LOOPBACK,
                  let sa = current.pointee.ifa_addr,
                  sa.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sa,
                socklen_t(sa.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if result == 0 {
                let ip = String(cString: hostname)
                if !ip.hasPrefix("169.254."), !addresses.contains(ip) {
                    addresses.append(ip)
                }
            }
        }
        return addresses
    }

    static func primaryAddress() -> String {
        ipv4Addresses().first ?? "未连接局域网"
    }
}
