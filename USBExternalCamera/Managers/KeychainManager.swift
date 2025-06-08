import Foundation
import Security

/// 민감한 데이터를 iOS Keychain에 안전하게 저장하는 매니저
final class KeychainManager {
    
    // MARK: - Constants
    
    private enum Constants {
        static let service = "com.usb-external-camera.keychain"
        static let streamKeyAccount = "stream_key"
    }
    
    // MARK: - Singleton
    
    static let shared = KeychainManager()
    
    private init() {}
    
    // MARK: - Stream Key Management
    
    /// 스트림 키를 Keychain에 저장
    /// - Parameter streamKey: 저장할 스트림 키
    /// - Returns: 저장 성공 여부
    func saveStreamKey(_ streamKey: String) -> Bool {
        guard !streamKey.isEmpty else { return false }
        
        let data = Data(streamKey.utf8)
        
        // 기존 항목 삭제
        deleteStreamKey()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: Constants.streamKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Keychain에서 스트림 키 로드
    /// - Returns: 저장된 스트림 키 (없으면 nil)
    func loadStreamKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: Constants.streamKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let streamKey = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return streamKey
    }
    
    /// 스트림 키 삭제
    /// - Returns: 삭제 성공 여부
    @discardableResult
    func deleteStreamKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: Constants.streamKeyAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Generic Keychain Operations
    
    /// 일반 문자열 데이터를 Keychain에 저장
    /// - Parameters:
    ///   - value: 저장할 값
    ///   - account: 계정 식별자
    /// - Returns: 저장 성공 여부
    func saveString(_ value: String, forAccount account: String) -> Bool {
        guard !value.isEmpty else { return false }
        
        let data = Data(value.utf8)
        
        // 기존 항목 삭제
        deleteString(forAccount: account)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    /// Keychain에서 문자열 데이터 로드
    /// - Parameter account: 계정 식별자
    /// - Returns: 저장된 값 (없으면 nil)
    func loadString(forAccount account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    /// 문자열 데이터 삭제
    /// - Parameter account: 계정 식별자
    /// - Returns: 삭제 성공 여부
    @discardableResult
    func deleteString(forAccount account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    // MARK: - Utility Methods
    
    /// 모든 저장된 데이터 삭제 (앱 삭제 시 호출)
    func clearAll() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.service
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
    
    /// Keychain 오류를 사용자 친화적 메시지로 변환
    /// - Parameter status: OSStatus 오류 코드
    /// - Returns: 사용자 친화적 오류 메시지
    func errorMessage(for status: OSStatus) -> String {
        switch status {
        case errSecSuccess:
            return "성공"
        case errSecItemNotFound:
            return "항목을 찾을 수 없음"
        case errSecDuplicateItem:
            return "중복된 항목"
        case errSecAuthFailed:
            return "인증 실패"
        case errSecUserCanceled:
            return "사용자 취소"
        case errSecNotAvailable:
            return "Keychain을 사용할 수 없음"
        default:
            return "알 수 없는 오류 (코드: \(status))"
        }
    }
} 