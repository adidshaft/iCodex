import Foundation
import Network

/// Detect the device's current WiFi IP address and derive subnets to scan.
enum WiFiHelper {

    /// Returns the device's WiFi IPv4 address, or nil if not on WiFi.
    static func getWiFiIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            // Only IPv4 (AF_INET), only en0 (WiFi on iOS)
            guard addrFamily == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname, socklen_t(hostname.count),
                nil, 0, NI_NUMERICHOST
            )
            address = String(cString: hostname)
            break
        }
        return address
    }

    /// Extract the /24 subnet prefix from an IP (e.g. "10.0.1.42" → "10.0.1").
    static func subnetPrefix(from ip: String) -> String? {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return parts[0...2].joined(separator: ".")
    }

    /// Build a smart list of subnets to scan, prioritizing the device's actual WiFi subnet.
    static func subnetsToScan(currentHost: String? = nil) -> [String] {
        var subnets: [String] = [] // ordered — device subnet first

        // 1. Device's actual WiFi subnet (most likely to contain the Mac)
        if let wifiIP = getWiFiIPAddress(), let subnet = subnetPrefix(from: wifiIP) {
            subnets.append(subnet)
        }

        // 2. Subnet derived from the configured host (if different)
        if let host = currentHost, let subnet = subnetPrefix(from: host), !subnets.contains(subnet) {
            subnets.append(subnet)
        }

        // 3. Common home subnets as fallback (only if not already covered)
        for common in ["192.168.1", "192.168.0", "10.0.0", "10.0.1", "172.20.10"] {
            if !subnets.contains(common) {
                subnets.append(common)
            }
        }

        return subnets
    }
}
