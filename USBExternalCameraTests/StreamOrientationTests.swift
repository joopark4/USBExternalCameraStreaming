//
//  StreamOrientationTests.swift
//  USBExternalCameraTests
//
//  HaishinKit 2.2.5 마이그레이션 + 세로 송출 모드 도입 이후 orientation
//  정규화 로직이 조용히 깨지지 않는지 확인하기 위한 단위 테스트.
//

import Testing
import CoreGraphics
import LiveStreamingCore

struct StreamOrientationTests {

    // MARK: - LiveStreamSettings.setStreamOrientation

    @Test func setStreamOrientationPortraitSwapsLandscapeDimensions() async throws {
        var settings = LiveStreamSettings()
        settings.videoWidth = 1920
        settings.videoHeight = 1080
        settings.streamOrientation = .landscape

        settings.setStreamOrientation(.portrait)

        #expect(settings.streamOrientation == .portrait)
        #expect(settings.videoWidth == 1080)
        #expect(settings.videoHeight == 1920)
    }

    @Test func setStreamOrientationLandscapeSwapsPortraitDimensions() async throws {
        var settings = LiveStreamSettings()
        settings.videoWidth = 1080
        settings.videoHeight = 1920
        settings.streamOrientation = .portrait

        settings.setStreamOrientation(.landscape)

        #expect(settings.streamOrientation == .landscape)
        #expect(settings.videoWidth == 1920)
        #expect(settings.videoHeight == 1080)
    }

    @Test func setStreamOrientationIsNoOpWhenAlreadyMatching() async throws {
        var settings = LiveStreamSettings()
        settings.videoWidth = 1920
        settings.videoHeight = 1080
        settings.streamOrientation = .landscape

        settings.setStreamOrientation(.landscape)

        #expect(settings.videoWidth == 1920)
        #expect(settings.videoHeight == 1080)
    }

    // MARK: - normalizeVideoDimensionsForOrientation

    @Test func normalizeVideoDimensionsRewritesMismatchedDimensions() async throws {
        // `streamOrientation` 과 width/height 가 다르면 정규화 시 swap.
        var settings = LiveStreamSettings()
        settings.streamOrientation = .portrait
        settings.videoWidth = 1920
        settings.videoHeight = 1080

        settings.normalizeVideoDimensionsForOrientation()

        #expect(settings.videoWidth == 1080)
        #expect(settings.videoHeight == 1920)
    }

    @Test func normalizeVideoDimensionsLeavesCorrectDimensionsAlone() async throws {
        var settings = LiveStreamSettings()
        settings.streamOrientation = .portrait
        settings.videoWidth = 1080
        settings.videoHeight = 1920

        settings.normalizeVideoDimensionsForOrientation()

        #expect(settings.videoWidth == 1080)
        #expect(settings.videoHeight == 1920)
    }

    // MARK: - Aspect ratio

    @Test func landscapeAspectRatioIs16Over9() async throws {
        var settings = LiveStreamSettings()
        settings.streamOrientation = .landscape
        settings.videoWidth = 1920
        settings.videoHeight = 1080

        let ratio = settings.streamAspectRatio
        #expect(abs(ratio - (16.0 / 9.0)) < 0.001)
    }

    @Test func portraitAspectRatioIs9Over16() async throws {
        var settings = LiveStreamSettings()
        settings.streamOrientation = .portrait
        settings.videoWidth = 1080
        settings.videoHeight = 1920

        let ratio = settings.streamAspectRatio
        #expect(abs(ratio - (9.0 / 16.0)) < 0.001)
    }
}
