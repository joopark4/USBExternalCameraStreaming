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
                    
                    // 구분선
                    Divider()
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                    
                    // 오픈소스 라이선스 버튼
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