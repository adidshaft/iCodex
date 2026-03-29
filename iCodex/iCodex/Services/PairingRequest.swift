import Foundation

struct PairingRequest: Identifiable, Equatable {
    let id = UUID()
    let host: String
    let port: Int
    let passcode: String

    var displayHost: String {
        "\(host):\(port)"
    }

    static func from(scannedValue: String) -> PairingRequest? {
        guard let url = URL(string: scannedValue) else { return nil }
        return from(url: url)
    }

    static func from(url: URL) -> PairingRequest? {
        guard let scheme = url.scheme?.lowercased(), scheme == "icodex" else {
            return nil
        }

        let route = (url.host ?? "").lowercased()
        let path = url.path.lowercased()
        guard route == "pair" || path == "/pair" else {
            return nil
        }

        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let host = components.queryItemValue(named: "host")?.trimmingCharacters(in: .whitespacesAndNewlines),
            !host.isEmpty,
            let passcode = components.queryItemValue(named: "passcode")?.filter(\.isNumber),
            passcode.count == 6
        else {
            return nil
        }

        let port = Int(components.queryItemValue(named: "port") ?? "") ?? 8642
        guard (1...65535).contains(port) else { return nil }

        return PairingRequest(host: host, port: port, passcode: passcode)
    }
}

private extension URLComponents {
    func queryItemValue(named name: String) -> String? {
        queryItems?.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.value
    }
}
