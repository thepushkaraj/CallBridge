import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Everything a phone needs to reach this Mac. Encoded as JSON into the pairing QR code.
struct PairingPayload {
    static let appTag = "callbridge"
    static let version = 1

    let host: String
    let port: UInt16
    let secret: String?

    var jsonString: String {
        var dict: [String: Any] = [
            "app": Self.appTag,
            "v": Self.version,
            "host": host,
            "port": Int(port),
        ]
        if let secret, !secret.isEmpty {
            dict["secret"] = secret
        }
        guard JSONSerialization.isValidJSONObject(dict) else { return "" }
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Tolerant reader: unknown fields are ignored; a payload is valid when it
    /// carries the CallBridge tag (or omits it), a host, and a port.
    static func from(jsonString: String) -> PairingPayload? {
        guard
            let data = jsonString.data(using: .utf8),
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            (obj["app"] as? String).map({ $0 == appTag }) ?? true,
            let host = obj["host"] as? String, !host.isEmpty,
            let portNumber = obj["port"] as? NSNumber,
            portNumber.uint16Value > 0
        else { return nil }

        let secret = (obj["secret"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return PairingPayload(host: host, port: portNumber.uint16Value, secret: secret)
    }
}

enum NetworkAddresses {
    /// This machine's usable IPv4 addresses, best candidate (e.g. Wi-Fi) first.
    static func preferredIPv4Addresses() -> [String] {
        var found: [(name: String, address: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next

            guard
                let addr = interface.ifa_addr,
                addr.pointee.sa_family == UInt8(AF_INET),
                interface.ifa_flags & UInt32(IFF_UP) != 0,
                interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                let name = interface.ifa_name.flatMap({ String(cString: $0) })
            else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }

            let address = String(cString: host)
            if !address.isEmpty, !found.contains(where: { $0.address == address }) {
                found.append((name, address))
            }
        }

        let excludedPrefixes = ["lo", "utun", "awdl", "llw", "bridge", "ap", "demux", "inpod", "stf"]
        return found
            .filter { name, _ in !excludedPrefixes.contains { name.hasPrefix($0) } }
            .sorted { score($0.name) < score($1.name) }
            .map(\.address)
    }

    private static func score(_ name: String) -> Int {
        switch name {
        case "en0": return 0
        case let n where n.hasPrefix("en"): return 1
        default: return 2
        }
    }
}

enum QRCode {
    /// High-contrast QR image (black on white, generous quiet zone) that stays scannable in any appearance.
    static func image(for string: String, moduleScale: CGFloat = 12) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: moduleScale, y: moduleScale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }

        let quiet: CGFloat = 32
        let size = NSSize(width: CGFloat(cgImage.width) + quiet * 2, height: CGFloat(cgImage.height) + quiet * 2)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
        let qrImage = NSImage(
            cgImage: cgImage,
            size: NSSize(width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        )
        qrImage.draw(in: NSRect(x: quiet, y: quiet, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        image.unlockFocus()
        return image
    }
}
