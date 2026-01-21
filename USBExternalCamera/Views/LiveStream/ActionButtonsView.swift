import SwiftUI

/// 설정 화면 하단의 액션 버튼들
struct ActionButtonsView: View {
    @ObservedObject var viewModel: LiveStreamViewModel
    @Binding var showResetAlert: Bool

    var body: some View {
        VStack(spacing: 12) {
            // 연결 테스트 버튼
            Button(action: {
                Task {
                    await viewModel.testConnection()
                }
            }) {
                HStack {
                    Image(systemName: "network")
                    Text(NSLocalizedString("test_connection", comment: "연결 테스트"))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(viewModel.isLoading || !isValidConfiguration)

            // 설정 초기화 버튼
            Button(action: {
                showResetAlert = true
            }) {
                HStack {
                    Image(systemName: "arrow.counterclockwise")
                    Text(NSLocalizedString("reset_to_defaults", comment: "기본값으로 재설정"))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.1))
                .foregroundColor(.red)
                .cornerRadius(10)
            }

            // 설정 정보
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
                Text(NSLocalizedString("settings_info", comment: "이 설정은 YouTube Live에 최적화되어 있습니다"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    private var isValidConfiguration: Bool {
        !viewModel.settings.rtmpURL.isEmpty && !viewModel.settings.streamKey.isEmpty
    }
}