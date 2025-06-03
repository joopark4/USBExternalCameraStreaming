import SwiftUI

/// 권한 설정 화면
struct PermissionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PermissionViewModel
    
    init(viewModel: PermissionViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? PermissionViewModel(permissionManager: PermissionManager()))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 0) {
                    PermissionRow(
                        icon: "camera",
                        title: "카메라",
                        status: viewModel.permissionStatusText(viewModel.cameraStatus)
                    ) {
                        Task {
                            await viewModel.requestCameraPermission()
                        }
                    }
                    
                    PermissionRow(
                        icon: "mic",
                        title: "마이크",
                        status: viewModel.permissionStatusText(viewModel.microphoneStatus)
                    ) {
                        Task {
                            await viewModel.requestMicrophonePermission()
                        }
                    }
                    
                    PermissionRow(
                        icon: "photo.on.rectangle",
                        title: "사진첩",
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
            .navigationTitle("권한 설정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") {
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
                Text("권한 요청")
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
    PermissionSettingsView()
} 