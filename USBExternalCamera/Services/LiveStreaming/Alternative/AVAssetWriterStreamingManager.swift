import Foundation
import AVFoundation
import VideoToolbox
import Network
import os.log

/// AVAssetWriter 기반 스트리밍 매니저 (HLS 방식)
/// 
/// **HaishinKit 우회 전략:**
/// - AVAssetWriter로 직접 H.264/AAC 파일 생성
/// - HLS 세그먼트 방식으로 실시간 스트리밍
/// - CDN 업로드를 통한 안정적인 라이브 스트리밍
@MainActor
public class AVAssetWriterStreamingManager: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    private let logger = Logger(subsystem: "USBExternalCamera.AVAssetWriter", category: "streaming")
    
    /// AVAssetWriter 인스턴스
    private var assetWriter: AVAssetWriter?
    
    /// 비디오 입력
    private var videoInput: AVAssetWriterInput?
    
    /// 오디오 입력
    private var audioInput: AVAssetWriterInput?
    
    /// 현재 세그먼트 인덱스
    private var segmentIndex = 0
    
    /// 세그먼트 지속 시간 (초)
    private let segmentDuration: TimeInterval = 6.0
    
    /// 스트리밍 상태
    @Published var isStreaming = false
    @Published var connectionStatus = NSLocalizedString("waiting", comment: "대기 중")
    @Published var segmentCount = 0
    @Published var totalDataWritten: Int64 = 0
    
    // 설정
    private var currentSettings: USBExternalCamera.LiveStreamSettings?
    private var outputDirectory: URL?
    
    // MARK: - Public Methods
    
    /// HLS 스트리밍 시작
    public func startHLSStreaming(with settings: USBExternalCamera.LiveStreamSettings) async throws {
        logger.info("🎬 HLS 스트리밍 시작")
        
        currentSettings = settings
        
        // 1. 출력 디렉토리 설정
        setupOutputDirectory()
        
        // 2. 첫 번째 세그먼트 시작
        try await startNewSegment()
        
        isStreaming = true
        connectionStatus = NSLocalizedString("hls_segment_creating", comment: "HLS 세그먼트 생성 중")
        
        // 3. 세그먼트 로테이션 타이머 시작
        startSegmentRotationTimer()
        
        logger.info("✅ HLS 스트리밍 시작 완료")
    }
    
    /// HLS 스트리밍 중지
    public func stopHLSStreaming() async {
        logger.info("🛑 HLS 스트리밍 중지")
        
        // 1. 현재 세그먼트 완료
        await finishCurrentSegment()
        
        // 2. 상태 업데이트
        isStreaming = false
        connectionStatus = NSLocalizedString("stopped", comment: "중지됨")
        
        logger.info("✅ HLS 스트리밍 중지 완료")
    }
    
    /// 비디오 프레임 추가 (외부에서 호출)
    public func appendVideoFrame(_ sampleBuffer: CMSampleBuffer) async {
        guard isStreaming,
              let videoInput = videoInput,
              videoInput.isReadyForMoreMediaData else {
            return
        }
        
        let success = videoInput.append(sampleBuffer)
        if success {
            totalDataWritten += Int64(CMSampleBufferGetTotalSampleSize(sampleBuffer))
        } else {
            logger.warning("비디오 프레임 추가 실패")
        }
    }
    
    /// 오디오 프레임 추가 (외부에서 호출)
    public func appendAudioFrame(_ sampleBuffer: CMSampleBuffer) async {
        guard isStreaming,
              let audioInput = audioInput,
              audioInput.isReadyForMoreMediaData else {
            return
        }
        
        let success = audioInput.append(sampleBuffer)
        if !success {
            logger.warning("오디오 프레임 추가 실패")
        }
    }
    
    // MARK: - Private Methods
    
    /// 출력 디렉토리 설정
    private func setupOutputDirectory() {
        let tempDir = FileManager.default.temporaryDirectory
        outputDirectory = tempDir.appendingPathComponent("HLSSegments")
        
        if let outputDir = outputDirectory {
            try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }
    }
    
    /// 새 세그먼트 시작
    private func startNewSegment() async throws {
        guard let settings = currentSettings,
              let outputDir = outputDirectory else {
            throw AVAssetWriterStreamingError.setupFailed(NSLocalizedString("streaming_settings_unavailable", comment: "스트리밍 설정을 사용할 수 없습니다"))
        }
        
        // 현재 세그먼트 파일 경로
        let segmentFileName = String(format: "segment_%06d.mp4", segmentIndex)
        let segmentURL = outputDir.appendingPathComponent(segmentFileName)
        
        logger.info("📝 새 세그먼트 시작: \(segmentFileName)")
        
        // 기존 AssetWriter 정리
        if let writer = assetWriter {
            if writer.status == .writing {
                await writer.finishWriting()
            }
        }
        
        // 새 AVAssetWriter 생성
        assetWriter = try AVAssetWriter(outputURL: segmentURL, fileType: .mp4)
        
        guard let writer = assetWriter else {
            throw AVAssetWriterStreamingError.setupFailed(NSLocalizedString("initialization_failed_detailed", comment: "초기화 실패: %@"))
        }
        
        // 비디오 입력 설정
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: settings.videoWidth,
            AVVideoHeightKey: settings.videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: settings.videoBitrate * 1000,
                AVVideoMaxKeyFrameIntervalKey: 30,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
            ]
        ]
        
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput?.expectsMediaDataInRealTime = true
        
        if let videoInput = videoInput, writer.canAdd(videoInput) {
            writer.add(videoInput)
        }
        
        // 오디오 입력 설정
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: settings.audioBitrate * 1000
        ]
        
        audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput?.expectsMediaDataInRealTime = true
        
        if let audioInput = audioInput, writer.canAdd(audioInput) {
            writer.add(audioInput)
        }
        
        // 쓰기 시작
        let success = writer.startWriting()
        if success {
            writer.startSession(atSourceTime: CMTime.zero)
            segmentCount += 1
            logger.info("✅ 세그먼트 \(self.segmentIndex) 쓰기 시작")
        } else {
            throw AVAssetWriterStreamingError.setupFailed(String(format: NSLocalizedString("initialization_failed_detailed", comment: "초기화 실패: %@"), writer.error?.localizedDescription ?? "Unknown"))
        }
    }
    
    /// 현재 세그먼트 완료
    private func finishCurrentSegment() async {
        guard let writer = assetWriter else { return }
        
        if writer.status == .writing {
            logger.info("📝 세그먼트 \(self.segmentIndex) 완료 중...")
            
            videoInput?.markAsFinished()
            audioInput?.markAsFinished()
            
            await writer.finishWriting()
            
            if writer.status == .completed {
                logger.info("✅ 세그먼트 \(self.segmentIndex) 완료")
                
                // 완료된 세그먼트를 서버로 업로드 (실제 구현 필요)
                await uploadSegmentToServer(segmentIndex: segmentIndex)
                
                segmentIndex += 1
            } else {
                logger.error("❌ 세그먼트 \(self.segmentIndex) 완료 실패: \(writer.error?.localizedDescription ?? "Unknown")")
            }
        }
    }
    
    /// 세그먼트 로테이션 타이머
    private func startSegmentRotationTimer() {
        Timer.scheduledTimer(withTimeInterval: segmentDuration, repeats: true) { [weak self] timer in
            guard let self = self, self.isStreaming else {
                timer.invalidate()
                return
            }
            
            Task { @MainActor in
                await self.rotateSegment()
            }
        }
    }
    
    /// 세그먼트 로테이션 (새 세그먼트로 전환)
    private func rotateSegment() async {
        logger.info("🔄 세그먼트 로테이션 시작")
        
        // 1. 현재 세그먼트 완료
        await finishCurrentSegment()
        
        // 2. 새 세그먼트 시작
        do {
            try await startNewSegment()
        } catch {
            logger.error("❌ 새 세그먼트 시작 실패: \(error)")
        }
    }
    
    /// 세그먼트를 서버로 업로드
    private func uploadSegmentToServer(segmentIndex: Int) async {
        logger.info("📤 세그먼트 \(segmentIndex) 서버 업로드 시뮬레이션")
        
        // 실제 구현에서는:
        // 1. HTTP POST로 세그먼트 파일 업로드
        // 2. M3U8 playlist 업데이트
        // 3. CDN 캐시 무효화
        
        // 현재는 시뮬레이션만
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5초
        
        logger.info("✅ 세그먼트 \(segmentIndex) 업로드 완료")
    }
}

// MARK: - HLS Streaming Errors

enum AVAssetWriterStreamingError: Error, LocalizedError {
    case setupFailed(String)
    case uploadFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .setupFailed(let message):
            return String(format: NSLocalizedString("streaming_setup_failed_detailed", comment: "스트리밍 설정 실패: %@"), message)
        case .uploadFailed(let message):
            return String(format: NSLocalizedString("upload_failed_detailed", comment: "업로드 실패: %@"), message)
        }
    }
} 