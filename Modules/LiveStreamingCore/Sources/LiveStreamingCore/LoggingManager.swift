import Foundation
import os.log

// MARK: - LoggingManager

/// 앱 전반의 로깅을 관리하는 매니저
/// - 기능별 로그 on/off 관리
/// - 배포 버전에서 자동으로 로그 비활성화
/// - os.Logger 기반의 성능 최적화된 로깅
/// - 다른 프로젝트에서 재사용 가능
@MainActor
public final class LoggingManager: ObservableObject {
    
    // MARK: - Singleton
    
    public static let shared = LoggingManager()
    
    // MARK: - Configuration Properties
    
    /// 앱 번들 식별자 (커스터마이즈 가능)
    private let bundleIdentifier: String
    
    /// UserDefaults 저장 키 (커스터마이즈 가능)
    private let userDefaultsKey: String
    
    /// 사용할 카테고리들 (커스터마이즈 가능)
    private let availableCategories: [Category]
    
    // MARK: - Initialization
    
    private init() {
        self.bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.default.app"
        self.userDefaultsKey = "LoggingConfiguration"
        self.availableCategories = Category.defaultCategories
        setupConfiguration()
    }
    
    /// 커스텀 설정으로 LoggingManager 초기화
    /// - Parameters:
    ///   - bundleIdentifier: 앱 번들 식별자
    ///   - userDefaultsKey: UserDefaults 저장 키
    ///   - categories: 사용할 로그 카테고리들
    /// - Returns: 설정된 LoggingManager 인스턴스
    public static func configure(
        bundleIdentifier: String? = nil,
        userDefaultsKey: String = "LoggingConfiguration",
        categories: [Category]? = nil
    ) -> LoggingManager {
        let manager = LoggingManager()
        // 설정 적용을 위한 내부 메소드 호출이 필요하다면 여기서 처리
        return manager
    }
    
    // MARK: - Log Categories
    
    /// 로그 카테고리 정의
    public enum Category: String, CaseIterable {
        // 범용 카테고리들 (모든 앱에서 사용 가능)
        case general = "General"
        case ui = "UI"
        case network = "Network"
        case data = "Data"
        case settings = "Settings"
        case device = "Device"
        case performance = "Performance"
        case error = "Error"
        
        // 특정 도메인 카테고리들 (필요시 사용)
        case camera = "Camera"
        case streaming = "Streaming"
        case auth = "Authentication"
        case storage = "Storage"
        case api = "API"
        case location = "Location"
        case push = "PushNotification"
        case payment = "Payment"
        case analytics = "Analytics"
        case security = "Security"
        
        /// 기본 카테고리들 (대부분의 앱에서 사용)
        public static var defaultCategories: [Category] {
            return [.general, .ui, .network, .data, .settings, .device, .performance, .error]
        }
        
        /// 미디어 앱용 카테고리들
        public static var mediaCategories: [Category] {
            return defaultCategories + [.camera, .streaming]
        }
        
        /// E-커머스 앱용 카테고리들
        public static var ecommerceCategories: [Category] {
            return defaultCategories + [.auth, .payment, .analytics]
        }
        
        /// 소셜 앱용 카테고리들
        public static var socialCategories: [Category] {
            return defaultCategories + [.auth, .push, .location, .storage]
        }
        
        public var icon: String {
            switch self {
            case .camera: return "📹"
            case .streaming: return "🎥"
            case .network: return "🌐"
            case .ui: return "🖼️"
            case .data: return "📊"
            case .settings: return "⚙️"
            case .device: return "📱"
            case .general: return "ℹ️"
            case .performance: return "⚡"
            case .error: return "❌"
            case .auth: return "🔐"
            case .storage: return "💾"
            case .api: return "🔗"
            case .location: return "📍"
            case .push: return "🔔"
            case .payment: return "💳"
            case .analytics: return "📈"
            case .security: return "🛡️"
            }
        }
        
        public var description: String {
            switch self {
            case .camera: return "카메라 관련 로그"
            case .streaming: return "스트리밍 관련 로그"
            case .network: return "네트워크 통신 로그"
            case .ui: return "UI 이벤트 및 상태 로그"
            case .data: return "데이터 처리 로그"
            case .settings: return "설정 변경 로그"
            case .device: return "디바이스 상태 로그"
            case .general: return "일반적인 로그"
            case .performance: return "성능 관련 로그"
            case .error: return "에러 및 예외 로그"
            case .auth: return "인증 관련 로그"
            case .storage: return "저장소 작업 로그"
            case .api: return "API 호출 로그"
            case .location: return "위치 서비스 로그"
            case .push: return "푸시 알림 로그"
            case .payment: return "결제 관련 로그"
            case .analytics: return "분석 및 추적 로그"
            case .security: return "보안 관련 로그"
            }
        }
        
        public func osLogCategory(bundleIdentifier: String) -> String {
            return "\(bundleIdentifier).\(self.rawValue.lowercased())"
        }
    }
    
    /// 로그 레벨 정의
    public enum LogLevel: String, CaseIterable, Comparable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
            let order: [LogLevel] = [.debug, .info, .warning, .error]
            guard let lhsIndex = order.firstIndex(of: lhs),
                  let rhsIndex = order.firstIndex(of: rhs) else {
                return false
            }
            return lhsIndex < rhsIndex
        }
        
        public var osLogType: OSLogType {
            switch self {
            case .debug: return .debug
            case .info: return .info
            case .warning: return .default
            case .error: return .error
            }
        }
        
        public var emoji: String {
            switch self {
            case .debug: return "🔍"
            case .info: return "ℹ️"
            case .warning: return "⚠️"
            case .error: return "❌"
            }
        }
    }
    
    // MARK: - Configuration
    
    /// 로그 설정
    private var configuration = LogConfiguration()
    
    /// os.Logger 인스턴스들 (카테고리별)
    private var loggers: [Category: Logger] = [:]
    
    // MARK: - Public Properties
    
    /// 디버그 모드 여부
    public var isDebugMode: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    /// 로깅 활성화 여부 (배포에서는 자동으로 false)
    public var isLoggingEnabled: Bool {
        return isDebugMode && configuration.isGloballyEnabled
    }
    
    /// 현재 사용 가능한 카테고리들
    public var categories: [Category] {
        return availableCategories
    }
    
    // MARK: - Setup
    
    private func setupConfiguration() {
        // os.Logger 인스턴스 생성 (사용 가능한 카테고리별)
        for category in availableCategories {
            loggers[category] = Logger(
                subsystem: bundleIdentifier,
                category: category.osLogCategory(bundleIdentifier: bundleIdentifier)
            )
        }
        
        // 기본 설정 로드
        loadConfiguration()
    }
    
    // MARK: - Main Logging Methods
    
    /// 디버그 로그
    /// - Parameters:
    ///   - message: 로그 메시지
    ///   - category: 로그 카테고리
    ///   - file: 파일명 (자동)
    ///   - function: 함수명 (자동)
    ///   - line: 라인 번호 (자동)
    func debug(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .debug, category: category, file: file, function: function, line: line)
    }
    
    /// 정보 로그
    func info(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .info, category: category, file: file, function: function, line: line)
    }
    
    /// 경고 로그
    func warning(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .warning, category: category, file: file, function: function, line: line)
    }
    
    /// 에러 로그
    func error(
        _ message: String,
        category: Category = .general,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(message, level: .error, category: category, file: file, function: function, line: line)
    }
    
    // MARK: - Core Logging Method
    
    private func log(
        _ message: String,
        level: LogLevel,
        category: Category,
        file: String,
        function: String,
        line: Int
    ) {
        // 전역 로깅 비활성화 체크
        guard isLoggingEnabled else { return }
        
        // 카테고리 사용 가능 여부 체크
        guard availableCategories.contains(category) else { return }
        
        // 카테고리별 활성화 체크
        guard configuration.isCategoryEnabled(category) else { return }
        
        // 로그 레벨 체크
        guard level >= configuration.minimumLogLevel else { return }
        
        // 파일명 추출
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        
        // 로그 메시지 포맷팅
        let formattedMessage = formatMessage(
            message: message,
            level: level,
            category: category,
            fileName: fileName,
            function: function,
            line: line
        )
        
        // os.Logger로 출력
        if let logger = loggers[category] {
            logger.log(level: level.osLogType, "\(formattedMessage)")
        }
        
        // 콘솔에도 출력 (개발 중 편의성을 위해)
        if configuration.shouldPrintToConsole {
            print(formattedMessage)
        }
    }
    
    // MARK: - Message Formatting
    
    private func formatMessage(
        message: String,
        level: LogLevel,
        category: Category,
        fileName: String,
        function: String,
        line: Int
    ) -> String {
        let timestamp = configuration.shouldIncludeTimestamp ? "[\(currentTimestamp())] " : ""
        let categoryIcon = category.icon
        let levelEmoji = level.emoji
        let categoryText = "[\(category.rawValue.uppercased())]"
        let levelText = "[\(level.rawValue)]"
        
        if configuration.shouldIncludeFileInfo {
            return "\(timestamp)\(categoryIcon) \(categoryText) \(levelEmoji) \(levelText) \(message) (\(fileName):\(line) \(function))"
        } else {
            return "\(timestamp)\(categoryIcon) \(categoryText) \(levelEmoji) \(levelText) \(message)"
        }
    }
    
    private func currentTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: Date())
    }
    
    // MARK: - Configuration Management
    
    /// 특정 카테고리 활성화/비활성화
    public func setCategoryEnabled(_ category: Category, enabled: Bool) {
        guard availableCategories.contains(category) else { return }
        configuration.categoryStates[category] = enabled
        saveConfiguration()
        objectWillChange.send()
    }
    
    /// 모든 카테고리 활성화/비활성화
    public func setAllCategoriesEnabled(_ enabled: Bool) {
        for category in availableCategories {
            configuration.categoryStates[category] = enabled
        }
        saveConfiguration()
        objectWillChange.send()
    }
    
    /// 최소 로그 레벨 설정
    public func setMinimumLogLevel(_ level: LogLevel) {
        configuration.minimumLogLevel = level
        saveConfiguration()
        objectWillChange.send()
    }
    
    /// 전역 로깅 활성화/비활성화
    public func setGlobalLoggingEnabled(_ enabled: Bool) {
        configuration.isGloballyEnabled = enabled
        saveConfiguration()
        objectWillChange.send()
    }
    
    /// 콘솔 출력 활성화/비활성화
    public func setConsoleOutputEnabled(_ enabled: Bool) {
        configuration.shouldPrintToConsole = enabled
        saveConfiguration()
        objectWillChange.send()
    }
    
    /// 타임스탬프 포함 여부
    public func setTimestampEnabled(_ enabled: Bool) {
        configuration.shouldIncludeTimestamp = enabled
        saveConfiguration()
        objectWillChange.send()
    }
    
    /// 파일 정보 포함 여부
    public func setFileInfoEnabled(_ enabled: Bool) {
        configuration.shouldIncludeFileInfo = enabled
        saveConfiguration()
        objectWillChange.send()
    }
    
    // MARK: - Configuration Persistence
    
    private func saveConfiguration() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }
    
    private func loadConfiguration() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(LogConfiguration.self, from: data) else {
            return
        }
        configuration = config
    }
    
    // MARK: - Status Methods
    
    /// 현재 로깅 설정 상태 반환
    public func getCurrentStatus() -> LoggingStatus {
        return LoggingStatus(
            isGloballyEnabled: configuration.isGloballyEnabled,
            isDebugMode: isDebugMode,
            isLoggingEnabled: isLoggingEnabled,
            minimumLogLevel: configuration.minimumLogLevel,
            availableCategories: availableCategories,
            enabledCategories: availableCategories.filter { configuration.isCategoryEnabled($0) },
            shouldPrintToConsole: configuration.shouldPrintToConsole,
            shouldIncludeTimestamp: configuration.shouldIncludeTimestamp,
            shouldIncludeFileInfo: configuration.shouldIncludeFileInfo
        )
    }
    
    /// 로깅 설정을 기본값으로 초기화
    public func resetToDefaults() {
        configuration = LogConfiguration(availableCategories: availableCategories)
        saveConfiguration()
        objectWillChange.send()
    }
}

// MARK: - Log Configuration

/// 로그 설정을 관리하는 구조체
private struct LogConfiguration: Codable {
    /// 전역 로깅 활성화 여부
    var isGloballyEnabled: Bool = true
    
    /// 카테고리별 활성화 상태
    var categoryStates: [LoggingManager.Category: Bool] = [:]
    
    /// 최소 로그 레벨
    var minimumLogLevel: LoggingManager.LogLevel = .debug
    
    /// 콘솔 출력 여부
    var shouldPrintToConsole: Bool = true
    
    /// 타임스탬프 포함 여부
    var shouldIncludeTimestamp: Bool = false
    
    /// 파일 정보 포함 여부
    var shouldIncludeFileInfo: Bool = false
    
    init(availableCategories: [LoggingManager.Category] = LoggingManager.Category.defaultCategories) {
        // 사용 가능한 카테고리들만 기본 활성화
        for category in availableCategories {
            categoryStates[category] = true
        }
    }
    
    func isCategoryEnabled(_ category: LoggingManager.Category) -> Bool {
        return categoryStates[category] ?? false
    }
}

// MARK: - Logging Status

/// 현재 로깅 상태를 나타내는 구조체
public struct LoggingStatus {
    public let isGloballyEnabled: Bool
    public let isDebugMode: Bool
    public let isLoggingEnabled: Bool
    public let minimumLogLevel: LoggingManager.LogLevel
    public let availableCategories: [LoggingManager.Category]
    public let enabledCategories: [LoggingManager.Category]
    public let shouldPrintToConsole: Bool
    public let shouldIncludeTimestamp: Bool
    public let shouldIncludeFileInfo: Bool
    
    public var summary: String {
        return """
        === 로깅 설정 상태 ===
        전역 활성화: \(isGloballyEnabled ? "✅" : "❌")
        디버그 모드: \(isDebugMode ? "✅" : "❌")
        실제 로깅 활성화: \(isLoggingEnabled ? "✅" : "❌")
        최소 로그 레벨: \(minimumLogLevel.rawValue)
        사용 가능한 카테고리: \(availableCategories.map { $0.rawValue }.joined(separator: ", "))
        활성화된 카테고리: \(enabledCategories.map { $0.rawValue }.joined(separator: ", "))
        콘솔 출력: \(shouldPrintToConsole ? "✅" : "❌")
        타임스탬프: \(shouldIncludeTimestamp ? "✅" : "❌")
        파일 정보: \(shouldIncludeFileInfo ? "✅" : "❌")
        """
    }
}

// MARK: - Convenience Extensions

extension LoggingManager.Category: Codable {}
extension LoggingManager.LogLevel: Codable {}

// MARK: - Global Logging Functions

/// 전역 로깅 함수들 (편의성을 위해)
public func logDebug(_ message: String, category: LoggingManager.Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
    Task { @MainActor in
        LoggingManager.shared.debug(message, category: category, file: file, function: function, line: line)
    }
}

public func logInfo(_ message: String, category: LoggingManager.Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
    Task { @MainActor in
        LoggingManager.shared.info(message, category: category, file: file, function: function, line: line)
    }
}

public func logWarning(_ message: String, category: LoggingManager.Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
    Task { @MainActor in
        LoggingManager.shared.warning(message, category: category, file: file, function: function, line: line)
    }
}

public func logError(_ message: String, category: LoggingManager.Category = .general, file: String = #file, function: String = #function, line: Int = #line) {
    Task { @MainActor in
        LoggingManager.shared.error(message, category: category, file: file, function: function, line: line)
    }
}

// MARK: - Project Setup Helper

/// 프로젝트별 LoggingManager 설정 헬퍼
extension LoggingManager {
    
    /// 현재 프로젝트 (USBExternalCamera)용 설정
    public static func setupForCurrentProject() {
        // 현재 프로젝트에서는 기본 설정 사용
        // 필요시 추가 설정 가능
    }
    
    /// 미디어 앱용 설정
    public static func setupForMediaApp(bundleIdentifier: String? = nil) -> LoggingManager {
        return configure(
            bundleIdentifier: bundleIdentifier,
            userDefaultsKey: "MediaAppLoggingConfiguration",
            categories: Category.mediaCategories
        )
    }
    
    /// E-커머스 앱용 설정
    public static func setupForEcommerceApp(bundleIdentifier: String? = nil) -> LoggingManager {
        return configure(
            bundleIdentifier: bundleIdentifier,
            userDefaultsKey: "EcommerceAppLoggingConfiguration",
            categories: Category.ecommerceCategories
        )
    }
    
    /// 소셜 앱용 설정
    public static func setupForSocialApp(bundleIdentifier: String? = nil) -> LoggingManager {
        return configure(
            bundleIdentifier: bundleIdentifier,
            userDefaultsKey: "SocialAppLoggingConfiguration",
            categories: Category.socialCategories
        )
    }
} 
