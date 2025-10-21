import SwiftUI
import AVFoundation

extension LiveStreamView {
    // MARK: - Error Card
    
    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                
                Text(NSLocalizedString("error_occurred", comment: "오류 발생"))
                    .font(.headline)
                    .foregroundColor(.red)
                
                Spacer()
                
                Button("복구 옵션") {
                    showingRecoveryOptions = true
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            if case .error(let error) = viewModel.status {
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
    
}
