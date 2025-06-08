import AVFoundation
import Network
import os.log

/// AVPlayer 확장 - 스트리밍 최적화 (FastPix, YouTube 등의 패턴 적용)
extension AVPlayer {
    
    /// 네트워크 상태에 따른 자동 품질 조정
    func optimizeForNetworkConditions() {
        // 현재 네트워크 상태 확인
        let monitor = NWPathMonitor()
        let queue = DispatchQueue.global(qos: .utility)
        
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.adjustPlaybackForPath(path)
            }
        }
        monitor.start(queue: queue)
    }
    
    private func adjustPlaybackForPath(_ path: NWPath) {
        guard path.status == .satisfied else {
            // 네트워크 연결 없음 - 재생 일시정지
            pause()
            return
        }
        
        // 네트워크 타입에 따른 최적화
        if path.usesInterfaceType(.cellular) {
            optimizeForCellular()
        } else if path.usesInterfaceType(.wifi) {
            optimizeForWiFi()
        }
    }
    
    /// 셀룰러 네트워크 최적화 (데이터 절약)
    private func optimizeForCellular() {
        // 버퍼링 최소화
        currentItem?.preferredForwardBufferDuration = 2.0
        
        // 자동 대기 비활성화 (빠른 시작)
        automaticallyWaitsToMinimizeStalling = false
        
        os_log("Optimized player for cellular network", log: .default, type: .info)
    }
    
    /// WiFi 네트워크 최적화 (고품질)
    private func optimizeForWiFi() {
        // 더 긴 버퍼링으로 안정성 확보
        currentItem?.preferredForwardBufferDuration = 10.0
        
        // 자동 최적화 활성화
        automaticallyWaitsToMinimizeStalling = true
        
        os_log("Optimized player for WiFi network", log: .default, type: .info)
    }
    
    /// 스트리밍 에러 복구 (Twitch, YouTube 패턴)
    func handleStreamingError(_ error: Error) {
        let nsError = error as NSError
        
        switch nsError.code {
        case AVError.contentIsNotAuthorized.rawValue:
            os_log("Content authorization error", log: .default, type: .error)
            // 인증 재시도 로직
            
        case AVError.noLongerPlayable.rawValue:
            os_log("Content no longer playable", log: .default, type: .error)
            // 콘텐츠 새로고침
            
        case AVError.mediaServicesWereReset.rawValue:
            os_log("Media services reset - attempting recovery", log: .default, type: .fault)
            attemptMediaServicesRecovery()
            
        default:
            os_log("Unhandled streaming error: %@ (code: %d)", 
                   log: .default, type: .error, error.localizedDescription, nsError.code)
        }
    }
    
    /// 미디어 서비스 복구 시도
    private func attemptMediaServicesRecovery() {
        // 현재 아이템과 시간 저장
        let currentTime = self.currentTime()
        let currentItem = self.currentItem
        
        // 플레이어 리셋
        replaceCurrentItem(with: nil)
        
        // 잠깐 대기 후 복구
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.replaceCurrentItem(with: currentItem)
            self.seek(to: currentTime)
            self.play()
            
            os_log("Media services recovery completed", log: .default, type: .info)
        }
    }
    
    /// HLS 스트림 최적화 (FastPix 패턴)
    func optimizeForHLS() {
        // HLS 특화 설정
        if let playerItem = currentItem {
            // 빠른 시작을 위한 설정
            playerItem.preferredForwardBufferDuration = 3.0
            
            // HLS 세그먼트 프리로딩 활성화
            if #available(iOS 15.0, *) {
                playerItem.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
            }
        }
        
        // 적응형 스트리밍 최적화
        automaticallyWaitsToMinimizeStalling = false
        
        os_log("Player optimized for HLS streaming", log: .default, type: .info)
    }
    
    /// 라이브 스트림 최적화 (Twitch 패턴)
    func optimizeForLiveStream() {
        // 라이브 스트림은 낮은 지연시간이 중요
        currentItem?.preferredForwardBufferDuration = 1.0
        
        // 즉시 재생 시작
        automaticallyWaitsToMinimizeStalling = false
        
        // 라이브 엣지에 가깝게 유지
        if let duration = currentItem?.duration,
           duration.isValid && !duration.isIndefinite {
            let liveEdge = CMTime(seconds: duration.seconds - 2.0, preferredTimescale: 1)
            seek(to: liveEdge)
        }
        
        os_log("Player optimized for live streaming", log: .default, type: .info)
    }
}

/// AVPlayerItem 확장 - 추가 최적화
extension AVPlayerItem {
    
    /// 네트워크 품질에 따른 동적 버퍼 조정
    func adjustBufferForQuality(_ quality: StreamQuality) {
        switch quality {
        case .low:
            preferredForwardBufferDuration = 1.0
            
        case .medium:
            preferredForwardBufferDuration = 3.0
            
        case .high:
            preferredForwardBufferDuration = 5.0
            
        case .auto:
            // 자동 조정 - 현재 네트워크 상태 기반
            preferredForwardBufferDuration = 3.0
        }
    }
}

enum StreamQuality {
    case low, medium, high, auto
} 