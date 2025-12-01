//
//  KeychainTokenStore.swift
//  Kinchaku
//
//  Created by Eric Masiello on 9/5/25.
//

import Foundation
import Security

struct KeychainTokenStore {
  let service: String;
  let account: String
  
  func save(_ token: String) {
    let data = Data(token.utf8)
    let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                               kSecAttrService as String: service,
                               kSecAttrAccount as String: account]
    let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status != errSecSuccess {
      var add = base; add[kSecValueData as String] = data
      SecItemAdd(add as CFDictionary, nil)
    }
  }

  func read() -> String? {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: service,
                            kSecAttrAccount as String: account,
                            kSecReturnData as String: true,
                            kSecMatchLimit as String: kSecMatchLimitOne]
    var item: CFTypeRef?
    guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
          let data = item as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func delete() {
    let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                            kSecAttrService as String: service,
                            kSecAttrAccount as String: account]
    SecItemDelete(q as CFDictionary)
  }
}
