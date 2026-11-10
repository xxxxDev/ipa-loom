import Foundation
import Security

// Project service with an installation-specific account; never accepts a password in argv or environment.
let service = "io.ipaloom.file-keyring.v1"
let account = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : ""
guard account.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil else { exit(1) }
let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                          kSecAttrService as String: service,
                          kSecAttrAccount as String: account,
                          kSecAttrSynchronizable as String: false]
func fail(_ status: OSStatus) -> Never {
    // Numeric status only: no credentials or account names in logs.
    FileHandle.standardError.write(Data("Keychain status: \(status)\n".utf8))
    exit(status == errSecItemNotFound ? 44 : 1)
}
let action = CommandLine.arguments.dropFirst().first ?? ""
switch action {
case "get":
    var q = query
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(q as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { fail(status) }
    FileHandle.standardOutput.write(data)
case "add":
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard data.count >= 12 && data.count <= 4096 else { fail(errSecParam) }
    var q = query
    q[kSecValueData as String] = data
    q[kSecAttrLabel as String] = "IPA Loom encrypted session passphrase"
    let status = SecItemAdd(q as CFDictionary, nil)
    guard status == errSecSuccess else { fail(status) } // Never overwrite an existing item.
case "delete":
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { fail(status) }
default:
    fail(errSecParam)
}
