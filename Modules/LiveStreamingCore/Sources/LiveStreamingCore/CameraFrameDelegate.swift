import AVFoundation

public protocol CameraFrameDelegate: AnyObject {
    func didReceiveVideoFrame(_ sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection)
}
