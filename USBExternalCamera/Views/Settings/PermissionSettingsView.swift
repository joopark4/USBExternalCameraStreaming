import SwiftUI

/// 권한 설정 화면
struct PermissionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PermissionViewModel
    @State private var showingOpenSourceLicenses = false

    init(viewModel: PermissionViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    PermissionRow(
                        icon: "camera",
                        title: NSLocalizedString("permission_camera", comment: ""),
                        status: viewModel.cameraStatus
                    ) {
                        Task { await viewModel.requestCameraPermission() }
                    }

                    PermissionRow(
                        icon: "mic",
                        title: NSLocalizedString("permission_microphone", comment: ""),
                        status: viewModel.microphoneStatus
                    ) {
                        Task { await viewModel.requestMicrophonePermission() }
                    }

                    Divider()
                        .padding(.horizontal)
                        .padding(.vertical, 12)

                    OpenSourceButton {
                        showingOpenSourceLicenses = true
                    }
                }
                .padding(.vertical)
            }
            .scrollDisabled(true)
            .navigationTitle(NSLocalizedString("permissions_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(NSLocalizedString("close", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingOpenSourceLicenses) {
            OpenSourceLicensesView()
        }
    }
}

/// 단일 권한 항목 행. `PermissionStatus` 만 받고 표시 텍스트 / 액션 라벨 / 비활성 여부를
/// 모두 자체 파생합니다 — 호출처가 status / actionTitle / isActionEnabled 를 따로
/// 전달할 때 발생하던 invariant 일치 부담을 제거합니다.
struct PermissionRow: View {
    let icon: String
    let title: String
    let status: PermissionStatus
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(statusText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: action) {
                Text(actionTitle)
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .disabled(status == .authorized)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var statusText: String {
        switch status {
        case .notDetermined: return NSLocalizedString("permission_status_not_determined", comment: "")
        case .restricted:    return NSLocalizedString("permission_status_restricted", comment: "")
        case .denied:        return NSLocalizedString("permission_status_denied", comment: "")
        case .authorized:    return NSLocalizedString("permission_status_authorized", comment: "")
        }
    }

    private var actionTitle: String {
        switch status {
        case .notDetermined:        return NSLocalizedString("permissions_request", comment: "")
        case .denied, .restricted:  return NSLocalizedString("permissions_open_settings", comment: "")
        case .authorized:           return NSLocalizedString("permission_status_authorized", comment: "")
        }
    }
}

/// 오픈소스 라이선스 버튼
struct OpenSourceButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "doc.text")
                    .frame(width: 24)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("오픈소스 라이선스")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("사용된 오픈소스 라이브러리 정보")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PermissionSettingsView(viewModel: PermissionViewModel(permissionManager: PermissionManager()))
}
