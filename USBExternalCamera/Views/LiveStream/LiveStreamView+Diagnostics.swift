import SwiftUI
import AVFoundation

extension LiveStreamView {
// MARK: - Diagnostics Report View

/// 진단 보고서를 표시하는 시트 뷰
struct DiagnosticsReportView: View {
    let report: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(report)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(8)
                }
                .padding()
            }
            .navigationTitle("진단 보고서")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("공유") {
                        shareReport()
                    }
                }
            }
        }
    }
    
    private func shareReport() {
        let activityController = UIActivityViewController(
            activityItems: [report],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.rootViewController?.present(activityController, animated: true)
        }
    }
} 
}
