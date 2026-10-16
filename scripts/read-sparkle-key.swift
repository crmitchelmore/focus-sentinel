import Foundation
import Security

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: read-sparkle-key.swift <account>\n".utf8))
    exit(2)
}

// A release must fail rather than wait for a keychain dialog on an unattended runner.
let interactionStatus = SecKeychainSetUserInteractionAllowed(false)
guard interactionStatus == errSecSuccess else {
    FileHandle.standardError.write(
        Data("FAIL cannot disable keychain interaction (OSStatus \(interactionStatus))\n".utf8)
    )
    exit(1)
}

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "https://sparkle-project.org",
    kSecAttrAccount as String: CommandLine.arguments[1],
    kSecAttrProtocol as String: kSecAttrProtocolSSH,
    kSecReturnData as String: true,
    kSecMatchLimit as String: kSecMatchLimitOne
]
var item: CFTypeRef?
let status = SecItemCopyMatching(query as CFDictionary, &item)
guard status == errSecSuccess else {
    let reason = SecCopyErrorMessageString(status, nil) as String? ?? "unknown keychain error"
    FileHandle.standardError.write(
        Data("FAIL cannot read the existing Sparkle key (OSStatus \(status)): \(reason)\n".utf8)
    )
    exit(1)
}
guard let encoded = item as? Data,
      let decoded = Data(base64Encoded: encoded),
      [32, 64, 96].contains(decoded.count) else {
    FileHandle.standardError.write(Data("FAIL the existing Sparkle key has an invalid format\n".utf8))
    exit(1)
}
FileHandle.standardOutput.write(encoded)
