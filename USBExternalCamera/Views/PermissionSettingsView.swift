import SwiftUI

/// 권한 설정 화면
struct PermissionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: PermissionViewModel
    
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
                        status: viewModel.permissionStatusText(viewModel.cameraStatus)
                    ) {
                        Task {
                            await viewModel.requestCameraPermission()
                        }
                    }
                    
                    PermissionRow(
                        icon: "mic",
                        title: NSLocalizedString("permission_microphone", comment: ""),
                        status: viewModel.permissionStatusText(viewModel.microphoneStatus)
                    ) {
                        Task {
                            await viewModel.requestMicrophonePermission()
                        }
                    }
                    
                    PermissionRow(
                        icon: "photo.on.rectangle",
                        title: NSLocalizedString("permission_photo_library", comment: ""),
                        status: viewModel.permissionStatusText(viewModel.photoLibraryStatus)
                    ) {
                        Task {
                            await viewModel.requestPhotoLibraryPermission()
                        }
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
    }
}

/// 권한 설정 행을 표시하는 뷰
struct PermissionRow: View {
    let icon: String
    let title: String
    let status: String
    let action: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.headline)
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: action) {
                Text(NSLocalizedString("permissions_request", comment: ""))
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

#Preview {
    PermissionSettingsView(viewModel: PermissionViewModel(permissionManager: PermissionManager()))
} 