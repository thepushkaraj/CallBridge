// CI tool: signs an update archive with the Ed25519 release key.
//
// Usage: swift sign_update.swift <key-base64> <file>
// Prints the base64 signature to stdout. The key arrives from the
// RELEASE_SIGNING_KEY secret (raw 32-byte Curve25519 key, base64).
// Verification happens in the app: UpdateCenter.isValidSignature.

import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 3 else {
    FileHandle.standardError.write("usage: sign_update.swift <key-base64> <file>\n".data(using: .utf8)!)
    exit(2)
}

let keyBase64 = args[1]
let filePath = args[2]

guard let keyData = Data(base64Encoded: keyBase64) else {
    FileHandle.standardError.write("key is not valid base64\n".data(using: .utf8)!)
    exit(2)
}

do {
    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: keyData)
    let archive = try Data(contentsOf: URL(fileURLWithPath: filePath))
    let signature = try privateKey.signature(for: archive)
    print(Data(signature).base64EncodedString())
} catch {
    FileHandle.standardError.write("signing failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
