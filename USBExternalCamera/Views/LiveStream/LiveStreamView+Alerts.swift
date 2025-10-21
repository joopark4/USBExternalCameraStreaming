import SwiftUI
import AVFoundation

extension LiveStreamView {
    // MARK: - Alert Buttons
    
    @ViewBuilder
    private var alertButtons: some View {
        Button("확인") {
            connectionTestResult = ""
        }
        
        if !connectionTestResult.isEmpty && connectionTestResult.contains("실패") {
            Button("설정 확인") {
                // 설정 화면으로 이동하는 로직 추가 가능
            }
        }
    }
    
    @ViewBuilder
    private var recoveryActionButtons: some View {
        Button("재시도") {
            Task {
                await performRealConnectionTest()
            }
        }
        
        Button("설정 확인") {
            // 설정 화면으로 이동
        }
        
        Button("취소", role: .cancel) { }
    }
    
}
