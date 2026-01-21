import SwiftUI
import AVFoundation
import LiveStreamingCore

extension LiveStreamView {
    // MARK: - Helper Methods
    
    func toggleStreaming() {
        Task {
            // 화면 캡처 스트리밍 토글
            viewModel.toggleScreenCaptureStreaming()
        }
    }
    
    func testConnection() {
        Task {
            await viewModel.testConnection()
            connectionTestResult = viewModel.connectionTestResult
            showingConnectionTest = true
        }
    }

    
    var streamingButtonText: String {
        if viewModel.isLoading {
            return "처리 중..."
        }
        return viewModel.streamingButtonText
    }
    
    var streamingButtonColor: Color {
        if viewModel.isLoading {
            return .gray
        }
        return viewModel.streamingButtonColor
    }
    
    var resolutionText: String {
        return "\(viewModel.settings.videoWidth)×\(viewModel.settings.videoHeight)"
    }
    
    func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }

    

    

    
    /// 실제 HaishinKit을 사용한 RTMP 연결 테스트
    func performRealConnectionTest() async {
        logger.info("🧪 실제 RTMP 연결 테스트 시작", category: .connection)
        
        // HaishinKitManager 인스턴스 생성
        let haishinKitManager = HaishinKitManager()
        
        // 현재 설정 사용
        let settings = viewModel.settings
        
        // 설정 정보 로그
        logger.info("🔧 테스트 설정:", category: .connection)
        logger.info("📍 RTMP URL: \(settings.rtmpURL)", category: .connection)
        logger.info("🔑 Stream Key: [보안상 로그에 출력하지 않음]", category: .connection)
        logger.info("🎥 Video: \(settings.videoWidth)x\(settings.videoHeight) @ \(settings.videoBitrate)kbps", category: .connection)
        logger.info("🎵 Audio: \(settings.audioBitrate)kbps", category: .connection)
        
        // 실제 연결 테스트 수행
        let result = await haishinKitManager.testConnection(to: settings)
        
        // 결과 로그
        if result.isSuccessful {
            logger.info("✅ 실제 RTMP 연결 테스트 성공", category: .connection)
            logger.info("⏱️ 응답 시간: \(result.latency)ms", category: .performance)
            logger.info("📶 네트워크 품질: \(result.networkQuality.displayName)", category: .network)
        } else {
            logger.error("❌ 실제 RTMP 연결 테스트 실패", category: .connection)
            logger.error("💬 오류 메시지: \(result.message)", category: .connection)
        }
        
        // UI에 결과 표시
        await MainActor.run {
            connectionTestResult = result.message
            showingConnectionTest = true
        }
    }
    
    /// 빠른 연결 상태 확인
    func performQuickCheck() {
        logger.info("⚡ 빠른 연결 상태 확인 시작", category: .connection)
        
        // 현재 viewModel 사용해서 빠른 진단 수행
        let result = viewModel.quickConnectionCheck()
        
        quickCheckResult = result
        showingQuickCheck = true
        
        logger.info("⚡ 빠른 진단 완료", category: .connection)
    }
    
    /// RTMP 연결 테스트 (HaishinKit 매니저 사용)
    func testRTMPConnection() async {
        logger.info("🧪 [RTMP] HaishinKit RTMP 연결 테스트 시작", category: .connection)
        
        guard viewModel.liveStreamService is HaishinKitManager else {
            connectionTestResult = "❌ HaishinKit 매니저가 초기화되지 않았습니다."
            await MainActor.run {
                showingConnectionTest = true
            }
            logger.error("❌ [RTMP] HaishinKit 매니저 없음", category: .connection)
            return
        }
        
        // HaishinKit 매니저의 연결 테스트 실행
        await viewModel.testConnection()
        let result = viewModel.connectionTestResult
        
        logger.info("🧪 [RTMP] 테스트 결과: \(result)", category: .connection)
        
        await MainActor.run {
            connectionTestResult = result
            showingConnectionTest = true
        }
    }
    

    
    /// 🩺 빠른 스트리밍 진단 (새로운 메서드)
    func performQuickDiagnosis() async {
        logger.info("🩺 빠른 스트리밍 진단 시작", category: .connection)
        
        // HaishinKitManager의 진단 기능 사용
        if let haishinKitManager = viewModel.liveStreamService as? HaishinKitManager {
            let (score, status, issues) = haishinKitManager.quickHealthCheck()
            
            var result = "🩺 빠른 진단 결과\n\n"
            result += "📊 종합 점수: \(score)점 (상태: \(status))\n\n"
            
            if issues.isEmpty {
                result += "✅ 발견된 문제 없음\n"
                result += "스트리밍 환경이 정상입니다."
            } else {
                result += "⚠️ 발견된 문제들:\n"
                for issue in issues {
                    result += "• \(issue)\n"
                }
                
                result += "\n💡 권장사항:\n"
                if issues.contains(where: { $0.contains("스트리밍이 시작되지 않음") }) {
                    result += "• YouTube Studio에서 라이브 스트리밍을 시작하세요\n"
                }
                if issues.contains(where: { $0.contains("RTMP 연결") }) {
                    result += "• 스트림 키와 RTMP URL을 확인하세요\n"
                }
                if issues.contains(where: { $0.contains("화면 캡처") }) {
                    result += "• 화면 캡처 모드가 활성화되었는지 확인하세요\n"
                }
                if issues.contains(where: { $0.contains("재연결") }) {
                    result += "• 잠시 후 다시 시도하거나 수동으로 재시작하세요\n"
                }
            }
            
            await MainActor.run {
                quickCheckResult = result
                showingQuickCheck = true
            }
        } else {
            await MainActor.run {
                quickCheckResult = "❌ HaishinKitManager를 찾을 수 없습니다."
                showingQuickCheck = true
            }
        }
        
        logger.info("🩺 빠른 스트리밍 진단 완료", category: .connection)
    }
    
    /// 🔍 종합 스트리밍 진단 (새로운 메서드)
    func performFullDiagnostics() async {
        logger.info("🔍 종합 스트리밍 진단 시작", category: .connection)
        
        // HaishinKitManager의 종합 진단 기능 사용
        if let haishinKitManager = viewModel.liveStreamService as? HaishinKitManager {
            // 종합 진단 실행
            let report = await haishinKitManager.performComprehensiveStreamingDiagnosis()
            
            // 사용자 친화적인 보고서 생성
            var userFriendlyReport = """
            🔍 HaishinKit 스트리밍 종합 진단 결과
            
            📊 종합 점수: \(report.overallScore)점/100점 (등급: \(report.overallGrade))
            
            💡 평가: \(report.getRecommendation())
            
            ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            
            📋 세부 진단 결과:
            
            1️⃣ 설정 검증: \(report.configValidation.isValid ? "✅ 통과" : "❌ 실패")
            \(report.configValidation.summary)
            
            2️⃣ MediaMixer: \(report.mediaMixerStatus.isValid ? "✅ 통과" : "❌ 실패")
            \(report.mediaMixerStatus.summary)
            
            3️⃣ RTMPStream: \(report.rtmpStreamStatus.isValid ? "✅ 통과" : "❌ 실패")
            \(report.rtmpStreamStatus.summary)
            
            4️⃣ 화면 캡처: \(report.screenCaptureStatus.isValid ? "✅ 통과" : "❌ 실패")
            \(report.screenCaptureStatus.summary)
            
            5️⃣ 네트워크: \(report.networkStatus.isValid ? "✅ 통과" : "❌ 실패")
            \(report.networkStatus.summary)
            
            6️⃣ 디바이스: \(report.deviceStatus.isValid ? "✅ 통과" : "❌ 실패")
            \(report.deviceStatus.summary)
            
            7️⃣ 데이터 흐름: \(report.dataFlowStatus.isValid ? "✅ 통과" : "❌ 실패")
            \(report.dataFlowStatus.summary)
            
            """
            
            // 문제가 있는 항목들의 상세 정보 추가
            let allIssues = [
                report.configValidation.issues,
                report.mediaMixerStatus.issues,
                report.rtmpStreamStatus.issues,
                report.screenCaptureStatus.issues,
                report.networkStatus.issues,
                report.deviceStatus.issues,
                report.dataFlowStatus.issues
            ].flatMap { $0 }
            
            if !allIssues.isEmpty {
                userFriendlyReport += "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
                userFriendlyReport += "\n⚠️ 발견된 문제점들:\n"
                for issue in allIssues {
                    userFriendlyReport += "• \(issue)\n"
                }
            }
            
            // 해결 가이드 추가
            let troubleshootingGuide = await haishinKitManager.generateTroubleshootingGuide()
            userFriendlyReport += "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
            userFriendlyReport += "\n\(troubleshootingGuide)"
            
            await MainActor.run {
                diagnosticsReport = userFriendlyReport
                showingDiagnostics = true
            }
        } else {
            await MainActor.run {
                diagnosticsReport = "❌ HaishinKitManager를 찾을 수 없습니다."
                showingDiagnostics = true
            }
        }
        
        logger.info("🔍 종합 스트리밍 진단 완료", category: .connection)
    }
    
    // MARK: - Helper Properties

    var statusColor: Color {
        if viewModel.isScreenCaptureStreaming {
            return .green
        }

        // StatusColorMappable 프로토콜 활용
        struct Helper: StatusColorMappable {}
        let helper = Helper()

        // connected와 streaming 상태 모두 green으로 표시하여 일관성 유지
        if viewModel.status == .connected || viewModel.status == .streaming {
            return .green
        }

        return helper.colorForStatus(viewModel.status)
    }
    
    var statusText: String {
        if viewModel.isScreenCaptureStreaming {
            return "화면 캡처 스트리밍 중"
        }
        
        // HaishinKitManager의 연결 상태 메시지 표시
        if let haishinKitManager = viewModel.liveStreamService as? HaishinKitManager {
            return viewModel.statusMessage.isEmpty ? haishinKitManager.connectionStatus : viewModel.statusMessage
        }
        return viewModel.statusMessage.isEmpty ? "준비됨" : viewModel.statusMessage
    }
}
