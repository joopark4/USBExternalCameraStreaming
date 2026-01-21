import SwiftUI
import LiveStreamingCore

// MARK: - Supporting Types
// AvailableFont와 TextOverlayColor는 LiveStreamingCore 모듈에서 제공됨

/// 텍스트 오버레이 고급 설정 팝업
struct TextOverlaySettingsView: View {
    @ObservedObject var viewModel: MainViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 텍스트 입력 영역
                VStack(alignment: .leading, spacing: 12) {
                    Text(NSLocalizedString("text_input", comment: "텍스트 입력"))
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("송출할 텍스트를 입력하세요", text: $viewModel.editingTextSettings.text, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                }
                .padding()
                .background(Color(.systemGray6))
                
                ScrollView {
                    VStack(spacing: 20) {
                        // 텍스트 히스토리
                        if !viewModel.textHistory.isEmpty {
                            historySection
                        }
                        
                        // 미리보기
                        previewSection
                        
                        // 폰트 설정
                        fontSection
                        
                        // 색상 설정
                        colorSection
                        
                        // 크기 설정
                        sizeSection
                    }
                    .padding()
                }
            }
            .navigationTitle("텍스트 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") {
                        viewModel.cancelTextSettings()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("적용") {
                        viewModel.applyTextSettings()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    // MARK: - 텍스트 히스토리 섹션
    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("recent_texts", comment: "최근 사용한 텍스트"))
                .font(.headline)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(viewModel.textHistory.prefix(6)) { item in
                    Button(action: {
                        viewModel.selectTextFromHistory(item)
                    }) {
                        Text(item.text)
                            .font(.caption)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.systemGray5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(viewModel.editingTextSettings.text == item.text ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 미리보기 섹션
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("미리보기")
                .font(.headline)
                .foregroundColor(.primary)
            
            ZStack {
                Rectangle()
                    .fill(Color.black)
                    .aspectRatio(16/9, contentMode: .fit)
                    .cornerRadius(12)
                
                if !viewModel.editingTextSettings.text.isEmpty {
                    Text(viewModel.editingTextSettings.text)
                        .font(fontForPreview(viewModel.editingTextSettings))
                        .foregroundColor(viewModel.editingTextSettings.textColor)
                        .shadow(color: .black, radius: 1, x: 1, y: 1)
                        .shadow(color: .black, radius: 1, x: -1, y: -1)
                        .shadow(color: .black, radius: 1, x: 1, y: -1)
                        .shadow(color: .black, radius: 1, x: -1, y: 1)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .frame(height: 180)
        }
    }
    
    // MARK: - 폰트 섹션
    private var fontSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("폰트")
                .font(.headline)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(AvailableFont.allCases, id: \.rawValue) { font in
                    Button(action: {
                        viewModel.editingTextSettings.fontName = font.rawValue
                    }) {
                        Text(font.displayName)
                            .font(font.previewFont)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(viewModel.editingTextSettings.fontName == font.rawValue ? Color.blue.opacity(0.2) : Color(.systemGray5))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(viewModel.editingTextSettings.fontName == font.rawValue ? Color.blue : Color.clear, lineWidth: 2)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 색상 섹션
    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("텍스트 색상")
                .font(.headline)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(TextOverlayColor.allCases, id: \.rawValue) { colorOption in
                    Button(action: {
                        viewModel.editingTextSettings.textColor = colorOption.color
                    }) {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(colorOption.color)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle()
                                        .stroke(viewModel.editingTextSettings.textColor == colorOption.color ? Color.primary : Color.clear, lineWidth: 3)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(Color(.systemGray4), lineWidth: 1)
                                )
                            
                            Text(colorOption.displayName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    // MARK: - 크기 섹션
    private var sizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("폰트 크기")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(Int(viewModel.editingTextSettings.fontSize))pt")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Slider(
                value: $viewModel.editingTextSettings.fontSize,
                in: 12...48,
                step: 2
            ) {
                Text("폰트 크기")
            }
            .tint(.blue)
            
            // 사이즈 프리셋 버튼들
            HStack(spacing: 8) {
                ForEach([16, 24, 32, 40], id: \.self) { size in
                    Button("\(size)pt") {
                        viewModel.editingTextSettings.fontSize = CGFloat(size)
                    }
                    .font(.caption)
                    .foregroundColor(viewModel.editingTextSettings.fontSize == CGFloat(size) ? .white : .blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(viewModel.editingTextSettings.fontSize == CGFloat(size) ? Color.blue : Color.blue.opacity(0.1))
                    )
                    .buttonStyle(.plain)
                }
                
                Spacer()
            }
        }
    }
    
    /// 미리보기용 폰트 생성 (크기 제한 포함)
    private func fontForPreview(_ settings: TextOverlaySettings) -> Font {
        let previewSize = min(settings.fontSize, 32) // 미리보기에서는 최대 32pt로 제한
        
        switch settings.fontName {
        case "System":
            return .system(size: previewSize, weight: .medium)
        case "System Bold":
            return .system(size: previewSize, weight: .bold)
        case "Helvetica":
            return .custom("Helvetica", size: previewSize)
        case "Helvetica Bold":
            return .custom("Helvetica-Bold", size: previewSize)
        case "Arial":
            return .custom("Arial", size: previewSize)
        case "Arial Bold":
            return .custom("Arial-BoldMT", size: previewSize)
        default:
            return .system(size: previewSize, weight: .medium)
        }
    }
} 