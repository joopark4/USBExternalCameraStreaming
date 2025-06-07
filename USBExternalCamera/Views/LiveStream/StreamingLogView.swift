//
//  StreamingLogView.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI

// MARK: - Streaming Log View

/// 스트리밍 로그 뷰어
struct StreamingLogView: View {
    
    // MARK: - Properties
    
    /// 로깅 매니저
    @ObservedObject private var logger = StreamingLogger.shared
    
    /// 선택된 로그 레벨 필터
    @State private var selectedLogLevel: StreamingLogger.LogLevel = .debug
    
    /// 선택된 카테고리 필터
    @State private var selectedCategory: StreamingLogger.LogCategory? = nil
    
    /// 검색 텍스트
    @State private var searchText: String = ""
    
    /// 자동 스크롤 여부
    @State private var autoScroll: Bool = true
    
    /// 로그 공유 시트 표시 여부
    @State private var showingShareSheet: Bool = false
    
    /// 필터된 로그들
    private var filteredLogs: [StreamingLogger.LogEntry] {
        var logs = logger.logEntries
        
        // 로그 레벨 필터링
        logs = logger.getFilteredLogs(minLevel: selectedLogLevel)
        
        // 카테고리 필터링
        if let category = selectedCategory {
            logs = logs.filter { $0.category == category }
        }
        
        // 검색 텍스트 필터링
        if !searchText.isEmpty {
            logs = logs.filter { 
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.function.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return logs
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 필터 섹션
                filterSection
                
                Divider()
                
                // 로그 리스트
                logListSection
            }
            .navigationTitle("🔍 스트리밍 로그")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    // 자동 스크롤 토글
                    Button(action: { autoScroll.toggle() }) {
                        Image(systemName: autoScroll ? "arrow.down.circle.fill" : "arrow.down.circle")
                            .foregroundColor(autoScroll ? .blue : .gray)
                    }
                    
                    // 로그 공유
                    Button(action: { showingShareSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    
                    // 로그 초기화
                    Button(action: { logger.clearLogs() }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: [logger.exportLogs()])
            }
        }
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        VStack(spacing: 12) {
            // 검색바
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("로그 검색...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button("Clear") {
                        searchText = ""
                    }
                    .foregroundColor(.blue)
                }
            }
            
            // 필터 버튼들
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // 로그 레벨 필터
                    Menu {
                        ForEach(StreamingLogger.LogLevel.allCases, id: \.self) { level in
                            Button(level.rawValue) {
                                selectedLogLevel = level
                            }
                        }
                    } label: {
                        HStack {
                            Text(NSLocalizedString("level_label", comment: "레벨: ") + "\(selectedLogLevel.rawValue)")
                            Image(systemName: "chevron.down")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // 카테고리 필터
                    Menu {
                        Button(NSLocalizedString("all_categories", comment: "전체")) {
                            selectedCategory = nil
                        }
                        
                        ForEach(StreamingLogger.LogCategory.allCases, id: \.self) { category in
                            Button(category.rawValue) {
                                selectedCategory = category
                            }
                        }
                    } label: {
                        HStack {
                            Text(NSLocalizedString("category_label", comment: "카테고리: ") + "\(selectedCategory?.rawValue ?? NSLocalizedString("all_categories", comment: "전체"))")
                            Image(systemName: "chevron.down")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // 통계 정보
                    HStack {
                        Image(systemName: "chart.bar")
                        Text("\(filteredLogs.count)/\(logger.logEntries.count)")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Log List Section
    
    private var logListSection: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                List {
                    ForEach(filteredLogs, id: \.id) { entry in
                        LogEntryRow(entry: entry)
                            .id(entry.id)
                    }
                }
                .listStyle(PlainListStyle())
                .onChange(of: filteredLogs.count) { _ in
                    if autoScroll && !filteredLogs.isEmpty {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(filteredLogs.last?.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    if autoScroll && !filteredLogs.isEmpty {
                        proxy.scrollTo(filteredLogs.last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Log Entry Row

struct LogEntryRow: View {
    let entry: StreamingLogger.LogEntry
    
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 메인 로그 라인
            HStack(alignment: .top, spacing: 8) {
                // 타임스탬프
                Text(timeString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)
                
                // 레벨 아이콘
                Text(levelIcon)
                    .font(.caption)
                    .frame(width: 20)
                
                // 카테고리
                Text(entry.category.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(categoryColor.opacity(0.2))
                    .cornerRadius(4)
                
                // 메시지
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.message)
                        .font(.caption)
                        .foregroundColor(levelColor)
                        .lineLimit(isExpanded ? nil : 3)
                    
                    if isExpanded {
                        Text("\(entry.function) (\(fileName):\(entry.line))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: entry.timestamp)
    }
    
    private var levelIcon: String {
        switch entry.level {
        case .debug: return "🔍"
        case .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🔥"
        }
    }
    
    private var levelColor: Color {
        switch entry.level {
        case .debug: return .secondary
        case .info: return .primary
        case .warning: return .orange
        case .error: return .red
        case .critical: return .red
        }
    }
    
    private var categoryColor: Color {
        switch entry.category {
        case .streaming: return .blue
        case .network: return .green
        case .audio: return .purple
        case .video: return .orange
        case .connection: return .cyan
        case .performance: return .yellow
        case .ui: return .pink
        case .system: return .gray
        }
    }
    
    private var fileName: String {
        URL(fileURLWithPath: entry.file).lastPathComponent
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Preview

#Preview {
    StreamingLogView()
} 