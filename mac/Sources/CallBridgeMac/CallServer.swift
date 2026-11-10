import Foundation
import Network

final class CallServer {
    enum State {
        case ready
        case failed(String)
    }

    var onState: ((State) -> Void)?
    var onEvent: ((IncomingEvent) -> Void)?

    private let port: UInt16
    private let secret: String?
    private var listener: NWListener?

    init(port: UInt16, secret: String?) {
        self.port = port
        self.secret = secret
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                print("CallBridge listening on port \(self.port)")
                self.onState?(.ready)
            case .failed(let error):
                let message: String
                if error == .posix(.EADDRINUSE) {
                    message = "Port \(self.port) is already in use"
                } else {
                    message = error.localizedDescription
                }
                print("Server failed: \(message)")
                self.onState?(.failed(message))
            default:
                break
            }
        }
        listener.start(queue: .main)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: .main)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, _ in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = HTTPRequest.parse(buffer) {
                let response = self.route(request)
                self.send(response, on: connection)
            } else if isComplete || buffer.count > 1_048_576 {
                self.send(HTTPResponse(status: "400 Bad Request", body: "{\"ok\":false}"), on: connection)
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func route(_ request: HTTPRequest) -> HTTPResponse {
        if let secret, request.header("X-CallBridge-Secret") != secret {
            appLog("Rejected request with missing/wrong secret from \(request.path)")
            return HTTPResponse(status: "401 Unauthorized", body: "{\"ok\":false}")
        }
        guard request.method == "POST", request.path == "/call" else {
            return HTTPResponse(status: "404 Not Found", body: "{\"ok\":false}")
        }
        guard let call = IncomingEvent.from(jsonData: request.body), !call.event.isEmpty else {
            return HTTPResponse(status: "400 Bad Request", body: "{\"ok\":false}")
        }
        let detail = [call.caller, call.number].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
        let source = call.device.isEmpty ? "unknown device" : call.device
        appLog("\(call.event) from \(source)\(detail.isEmpty ? "" : " (\(detail))")")
        onEvent?(call)
        Notifier.handle(call)
        return HTTPResponse(status: "200 OK", body: "{\"ok\":true}")
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

func appLog(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    print("[\(formatter.string(from: Date()))] \(message)")
}

struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }

    /// Returns nil while the request is still incomplete.
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }

        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }

        let parts = lines.removeFirst().split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let rawPath = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        // Reject paths before parsing the body to avoid buffering abuse.
        let path = String(rawPath.split(separator: "?").first ?? Substring(rawPath))
        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        guard contentLength >= 0, contentLength <= 1_048_576 else { return nil }

        let totalNeeded = headerEnd.upperBound + contentLength
        guard data.count >= totalNeeded else { return nil }

        let body = data.subdata(in: headerEnd.upperBound..<totalNeeded)
        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}

struct HTTPResponse {
    let status: String
    let body: String

    func serialized() -> Data {
        var out = "HTTP/1.1 \(status)\r\n"
        out += "Content-Type: application/json\r\n"
        out += "Content-Length: \(body.utf8.count)\r\n"
        out += "Connection: close\r\n\r\n"
        out += body
        return Data(out.utf8)
    }
}
