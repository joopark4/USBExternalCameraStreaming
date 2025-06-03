import SwiftUI
import AVFoundation

/// 카메라 프리뷰를 표시하는 UIViewRepresentable
/// - AVCaptureSession의 출력을 SwiftUI 뷰로 표시
/// - 가로 방향으로 고정된 카메라 프리뷰 제공
struct CameraPreviewView: UIViewRepresentable {
    /// 표시할 카메라 세션
    /// - AVCaptureSession 인스턴스를 통해 카메라 출력을 받아옴
    let session: AVCaptureSession
    
    /// AVCaptureVideoPreviewLayer를 사용하는 커스텀 UIView
    /// - 카메라 프리뷰를 표시하기 위한 UIView 서브클래스
    class PreviewView: UIView {
        /// 레이어 클래스를 AVCaptureVideoPreviewLayer로 지정
        /// - 카메라 프리뷰를 표시하기 위한 특수 레이어 사용
        override class var layerClass: AnyClass {
            return AVCaptureVideoPreviewLayer.self
        }
        
        /// 비디오 프리뷰 레이어 접근자
        /// - UIView의 layer를 AVCaptureVideoPreviewLayer로 캐스팅
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }
        
        /// 뷰 크기 변경 시 프리뷰 레이어 크기 조정
        /// - 뷰의 bounds가 변경될 때마다 프리뷰 레이어의 크기도 함께 조정
        override func layoutSubviews() {
            super.layoutSubviews()
            videoPreviewLayer.frame = bounds
        }
    }
    
    /// UIView 생성
    /// - 카메라 프리뷰를 표시할 UIView 인스턴스 생성
    /// - 프리뷰 레이어 설정 및 가로 방향 고정
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        
        let previewLayer = view.videoPreviewLayer
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspect
        
        // 가로 방향으로 고정
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }
        
        return view
    }
    
    /// UIView 업데이트
    /// - 화면 회전 등으로 인한 방향 변경 시 호출
    /// - 가로 방향 유지를 위해 프리뷰 레이어 방향 재설정
    func updateUIView(_ uiView: PreviewView, context: Context) {
        let previewLayer = uiView.videoPreviewLayer
        // 가로 방향 유지
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .landscapeRight
        }
    }
} 