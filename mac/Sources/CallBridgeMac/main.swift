import Foundation

setbuf(stdout, nil)

var port: UInt16 = 8765
var secret: String?

var args = CommandLine.arguments.dropFirst().makeIterator()
while let arg = args.next() {
    switch arg {
    case "--port":
        if let value = args.next(), let parsed = UInt16(value) {
            port = parsed
        } else {
            print("Usage: callbridge [--port <number>] [--secret <shared-secret>]")
            exit(2)
        }
    case "--secret":
        if let value = args.next() {
            secret = value
        } else {
            print("Usage: callbridge [--port <number>] [--secret <shared-secret>]")
            exit(2)
        }
    case "--help", "-h":
        print("""
        CallBridge - show a macOS notification when your Android phone rings

        Usage: callbridge [--port <number>] [--secret <shared-secret>]

          --port    TCP port to listen on (default: 8765)
          --secret  Require this shared secret in the X-CallBridge-Secret header
        """)
        exit(0)
    default:
        print("Unknown argument: \(arg). Try --help.")
        exit(2)
    }
}

let server = CallServer(port: port, secret: secret)
do {
    try server.start()
} catch {
    print("Failed to start server on port \(port): \(error)")
    print("Is another process using the port?")
    exit(1)
}

withExtendedLifetime(server) {
    RunLoop.main.run()
}
