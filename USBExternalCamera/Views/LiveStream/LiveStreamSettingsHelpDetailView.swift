import SwiftUI

// MARK: - Help Detail View

/// 해상도 선택 버튼
struct ResolutionButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    
    init(title: String, subtitle: String, isSelected: Bool, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
    }
    
    var body: some View {
        Button(action: isEnabled ? action : {}) {
            VStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isEnabled ? (isSelected ? .white : .primary) : .gray)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(isEnabled ? (isSelected ? .white.opacity(0.8) : .secondary) : .gray.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                isEnabled ? 
                    (isSelected ? Color.accentColor : Color(UIColor.secondarySystemGroupedBackground)) :
                    Color.gray.opacity(0.1)
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isEnabled ? (isSelected ? Color.clear : Color.gray.opacity(0.3)) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
    }
}

/// 프레임률 선택 버튼
struct FrameRateButton: View {
    let title: String
    let frameRate: Int
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(buttonTextColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(buttonBackground)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(buttonBorderColor, lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isEnabled)
    }
    
    private var buttonTextColor: Color {
        if !isEnabled {
            return .gray
        } else if isSelected {
            return .white
        } else {
            return .primary
        }
    }
    
    private var buttonBackground: Color {
        if !isEnabled {
            return Color.gray.opacity(0.1)
        } else if isSelected {
            return Color.accentColor
        } else {
            return Color(UIColor.secondarySystemGroupedBackground)
        }
    }
    
    private var buttonBorderColor: Color {
        if !isEnabled {
            return Color.gray.opacity(0.2)
        } else if isSelected {
            return Color.clear
        } else {
            return Color.gray.opacity(0.3)
        }
    }
}

struct HelpDetailView: View {
    let topic: String
    let viewModel: LiveStreamViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    let helpContent = getHelpContentFor(topic)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(helpContent.title)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text(helpContent.description)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    if !helpContent.recommendedValues.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(NSLocalizedString("recommended_settings_help", comment: "권장 설정"))
                                .font(.headline)
                                .foregroundColor(.green)
                            
                            ForEach(helpContent.recommendedValues, id: \.self) { value in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text(value)
                                        .font(.body)
                                }
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle(NSLocalizedString("help", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("done", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func getHelpContentFor(_ topic: String) -> (title: String, description: String, recommendedValues: [String]) {
        switch topic {
        case "rtmpURL":
            return (
                title: "RTMP 서버 URL",
                description: "RTMP 스트리밍을 위한 서버 URL입니다. 유튜브 스트리밍을 위해서는 이 URL을 사용해야 합니다.",
                recommendedValues: [
                    "rtmp://a.rtmp.youtube.com/live2/"
                ]
            )
        case "streamKey":
            return (
                title: "스트림 키",
                description: "스트림을 식별하는 고유한 키입니다. 유튜브 스트리밍을 위해서는 이 키를 사용해야 합니다.",
                recommendedValues: []
            )
        default:
            return (
                title: "설정 도움말",
                description: "이 설정에 대한 자세한 정보가 필요합니다.",
                recommendedValues: []
            )
        }
    }
}
