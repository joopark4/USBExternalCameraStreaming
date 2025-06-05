import SwiftUI

// MARK: - LoggingSettingsView

/// 로깅 설정을 관리하는 View
/// - 개발 중에만 접근 가능한 로그 설정 화면
/// - 각 카테고리별 on/off 관리
/// - 로그 레벨 및 기타 옵션 설정
struct LoggingSettingsView: View {
    
    // MARK: - Properties
    
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var loggingManager = LoggingManager.shared
    @State private var status: LoggingStatus
    
    init() {
        let initialStatus = LoggingManager.shared.getCurrentStatus()
        _status = State(initialValue: initialStatus)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            List {
                globalSettingsSection
                categorySettingsSection  
                logLevelSection
                outputOptionsSection
                currentStatusSection
            }
            .navigationTitle("로깅 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("기본값으로 초기화") {
                        Task { @MainActor in
                            loggingManager.resetToDefaults()
                            refreshStatus()
                        }
                    }
                    .foregroundColor(.red)
                }
            }
        }
        .onAppear {
            refreshStatus()
        }
    }
    
    // MARK: - Global Settings Section
    
    private var globalSettingsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("🚀 글로벌 로깅 설정")
                        .font(.headline)
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("디버그 모드:")
                        Spacer()
                        Text(status.isDebugMode ? "✅ 활성화" : "❌ 비활성화")
                            .foregroundColor(status.isDebugMode ? .green : .red)
                    }
                    .font(.caption)
                    
                    HStack {
                        Text("배포 버전:")
                        Spacer()
                        Text(status.isDebugMode ? "❌ 아니오" : "✅ 예")
                            .foregroundColor(status.isDebugMode ? .orange : .blue)
                    }
                    .font(.caption)
                    
                    if !status.isDebugMode {
                        Text("⚠️ 배포 버전에서는 모든 로그가 자동으로 비활성화됩니다")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("전역 설정")
        }
    }
    
    // MARK: - Category Settings Section
    
    private var categorySettingsSection: some View {
        Section {
            ForEach(status.availableCategories, id: \.self) { category in
                categoryRow(for: category)
            }
            
            if status.availableCategories.count > 1 {
                HStack {
                    Button("모두 활성화") {
                        Task { @MainActor in
                            loggingManager.setAllCategoriesEnabled(true)
                            refreshStatus()
                        }
                    }
                    .foregroundColor(.green)
                    
                    Spacer()
                    
                    Button("모두 비활성화") {
                        Task { @MainActor in
                            loggingManager.setAllCategoriesEnabled(false)
                            refreshStatus()
                        }
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("카테고리별 설정 (\(status.availableCategories.count)개)")
        } footer: {
            Text("특정 기능의 로그만 선택적으로 활성화할 수 있습니다.")
        }
    }
    
    private func categoryRow(for category: LoggingManager.Category) -> some View {
        HStack(spacing: 12) {
            // 카테고리 아이콘
            Text(category.icon)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(category.rawValue)
                    .font(.headline)
                
                Text(category.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: Binding(
                get: { status.enabledCategories.contains(category) },
                set: { newValue in
                    Task { @MainActor in
                        loggingManager.setCategoryEnabled(category, enabled: newValue)
                        refreshStatus()
                    }
                }
            ))
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Log Level Section
    
    private var logLevelSection: some View {
        Section {
            Picker("로그 레벨", selection: Binding(
                get: { status.minimumLogLevel },
                set: { newLevel in
                    Task { @MainActor in
                        loggingManager.setMinimumLogLevel(newLevel)
                        refreshStatus()
                    }
                }
            )) {
                ForEach(LoggingManager.LogLevel.allCases, id: \.self) { level in
                    HStack {
                        Text(level.emoji)
                        Text(level.rawValue)
                    }
                    .tag(level)
                }
            }
            .pickerStyle(.segmented)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("로그 레벨 설명:")
                    .font(.caption)
                    .fontWeight(.medium)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("🔍 DEBUG: 개발 중 상세 정보")
                    Text("ℹ️ INFO: 일반적인 정보")
                    Text("⚠️ WARNING: 주의가 필요한 상황")
                    Text("❌ ERROR: 오류 및 예외 상황")
                }
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        } header: {
            Text("최소 로그 레벨")
        } footer: {
            Text("선택한 레벨 이상의 로그만 출력됩니다.")
        }
    }
    
    // MARK: - Output Options Section
    
    private var outputOptionsSection: some View {
        Section {
            Toggle("콘솔 출력", isOn: Binding(
                get: { status.shouldPrintToConsole },
                set: { newValue in
                    Task { @MainActor in
                        loggingManager.setConsoleOutputEnabled(newValue)
                        refreshStatus()
                    }
                }
            ))
            
            Toggle("타임스탬프 포함", isOn: Binding(
                get: { status.shouldIncludeTimestamp },
                set: { newValue in
                    Task { @MainActor in
                        loggingManager.setTimestampEnabled(newValue)
                        refreshStatus()
                    }
                }
            ))
            
            Toggle("파일 정보 포함", isOn: Binding(
                get: { status.shouldIncludeFileInfo },
                set: { newValue in
                    Task { @MainActor in
                        loggingManager.setFileInfoEnabled(newValue)
                        refreshStatus()
                    }
                }
            ))
        } header: {
            Text("출력 옵션")
        } footer: {
            Text("로그 메시지에 포함할 추가 정보를 선택하세요.")
        }
    }
    
    // MARK: - Current Status Section
    
    private var currentStatusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("현재 상태")
                    .font(.headline)
                
                Text(status.summary)
                    .font(.system(.caption, design: .monospaced))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
            }
        } header: {
            Text("현재 설정 상태")
        }
    }
    
    // MARK: - Helper Methods
    
    private func refreshStatus() {
        Task { @MainActor in
            status = loggingManager.getCurrentStatus()
        }
    }
}

// MARK: - Preview

#Preview {
    LoggingSettingsView()
} 