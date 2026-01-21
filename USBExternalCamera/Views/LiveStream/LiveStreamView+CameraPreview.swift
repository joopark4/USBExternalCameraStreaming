import SwiftUI
import AVFoundation

extension LiveStreamView {
    // MARK: - Camera Preview Section
    
    var cameraPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("camera_preview", comment: "카메라 프리뷰"))
                .font(.headline)
            
            Rectangle()
                .fill(Color.black)
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.white.opacity(0.6))
                        
                        Text(NSLocalizedString("camera_preview", comment: "카메라 프리뷰"))
                            .foregroundColor(.white.opacity(0.8))
                            .font(.caption)
                    }
                )
                .cornerRadius(12)
        }
    }
    
}
