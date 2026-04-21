//
//  USBExternalCameraTests.swift
//  USBExternalCameraTests
//
//  Created by EUN YEON on 5/25/25.
//

import Testing
import CoreGraphics
import LiveStreamingCore
@testable import USBExternalCamera

struct USBExternalCameraTests {

    @MainActor
    @Test func getOptimalCaptureSizeKeepsPresetPortraitTarget() async throws {
        let previewView = CameraPreviewUIView(frame: .zero)

        previewView.setStreamingTargetSize(CGSize(width: 720, height: 1280))

        #expect(previewView.getOptimalCaptureSize() == CGSize(width: 720, height: 1280))
    }

    @MainActor
    @Test func getOptimalCaptureSizeAlignsCustomTargetToMultiplesOf16() async throws {
        let previewView = CameraPreviewUIView(frame: .zero)

        previewView.setStreamingTargetSize(CGSize(width: 721, height: 1281))

        #expect(previewView.getOptimalCaptureSize() == CGSize(width: 736, height: 1296))
    }

    @MainActor
    @Test func calculateCameraPreviewRectUsesPortraitAspectRatio() async throws {
        let previewView = CameraPreviewUIView(frame: .zero)
        var settings = LiveStreamSettings()
        settings.streamOrientation = .portrait
        settings.videoWidth = 720
        settings.videoHeight = 1280
        previewView.streamingSettings = settings

        let rect = previewView.calculateCameraPreviewRect(in: CGSize(width: 1000, height: 1000))

        #expect(abs(rect.width - 562.5) < 0.001)
        #expect(abs(rect.height - 1000) < 0.001)
        #expect(abs(rect.minX - 218.75) < 0.001)
        #expect(abs(rect.minY) < 0.001)
    }

}
