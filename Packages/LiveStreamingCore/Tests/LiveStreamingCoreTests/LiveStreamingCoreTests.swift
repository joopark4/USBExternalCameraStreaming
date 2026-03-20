import XCTest
@testable import LiveStreamingCore

final class LiveStreamingCoreTests: XCTestCase {
    func testDefaultSettingsUseLandscapeOrientation() {
        let settings = LiveStreamSettings()

        XCTAssertEqual(settings.streamOrientation, .landscape)
        XCTAssertEqual(settings.videoWidth, 1920)
        XCTAssertEqual(settings.videoHeight, 1080)
    }

    func testSetStreamOrientationSwapsOnlyDimensions() {
        var settings = LiveStreamSettings()
        settings.videoWidth = 1280
        settings.videoHeight = 720
        settings.videoBitrate = 2500
        settings.audioBitrate = 160
        settings.frameRate = 60

        settings.setStreamOrientation(.portrait)

        XCTAssertEqual(settings.streamOrientation, .portrait)
        XCTAssertEqual(settings.videoWidth, 720)
        XCTAssertEqual(settings.videoHeight, 1280)
        XCTAssertEqual(settings.videoBitrate, 2500)
        XCTAssertEqual(settings.audioBitrate, 160)
        XCTAssertEqual(settings.frameRate, 60)
    }

    func testApplyResolutionClassUsesCurrentOrientation() {
        var settings = LiveStreamSettings()
        settings.streamOrientation = .portrait

        settings.applyResolutionClass(.p1080)

        XCTAssertEqual(settings.videoWidth, 1080)
        XCTAssertEqual(settings.videoHeight, 1920)
        XCTAssertEqual(settings.normalizedResolutionClass, .p1080)
    }

    func testYouTubePresetSettingsFollowOrientation() {
        let landscape = YouTubeLivePreset.hd720p.settings(for: .landscape)
        let portrait = YouTubeLivePreset.hd720p.settings(for: .portrait)

        XCTAssertEqual(landscape.width, 1280)
        XCTAssertEqual(landscape.height, 720)
        XCTAssertEqual(portrait.width, 720)
        XCTAssertEqual(portrait.height, 1280)
    }

    func testDetectYouTubePresetNormalizesPortraitResolution() {
        var settings = LiveStreamSettings()
        settings.streamOrientation = .portrait
        settings.videoWidth = 720
        settings.videoHeight = 1280
        settings.frameRate = 30
        settings.videoBitrate = 3000

        XCTAssertEqual(settings.detectYouTubePreset(), .hd720p)
    }

    func testRecommendedVideoBitrateNormalizesPortraitResolution() {
        var settings = LiveStreamSettings()
        settings.streamOrientation = .portrait
        settings.videoWidth = 720
        settings.videoHeight = 1280

        XCTAssertEqual(settings.recommendedVideoBitrate, 2500)
    }

    func testResolutionDescriptorTreatsPortraitAsSameClass() {
        let landscape = StreamResolutionDescriptor(width: 1280, height: 720)
        let portrait = StreamResolutionDescriptor(width: 720, height: 1280)

        XCTAssertEqual(landscape.resolutionClass, .p720)
        XCTAssertEqual(portrait.resolutionClass, .p720)
    }

    func testLiveStreamSettingsDecodeInfersOrientationWhenMissing() throws {
        let json = """
        {
          "videoWidth": 720,
          "videoHeight": 1280,
          "videoBitrate": 2500,
          "audioBitrate": 128,
          "frameRate": 30
        }
        """

        let settings = try JSONDecoder().decode(LiveStreamSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.streamOrientation, .portrait)
        XCTAssertEqual(settings.normalizedResolutionClass, .p720)
    }

    func testNormalizedVideoDimensionsFollowStreamOrientation() {
        var settings = LiveStreamSettings()
        settings.streamOrientation = .portrait
        settings.videoWidth = 1920
        settings.videoHeight = 1080

        XCTAssertEqual(settings.streamAspectRatio, 1080.0 / 1920.0, accuracy: 0.0001)

        settings.normalizeVideoDimensionsForOrientation()

        XCTAssertEqual(settings.videoWidth, 1080)
        XCTAssertEqual(settings.videoHeight, 1920)
    }

    func testResolutionDescriptorUsesNormalizedDimensions() {
        var settings = LiveStreamSettings()
        settings.streamOrientation = .portrait
        settings.videoWidth = 1280
        settings.videoHeight = 720

        XCTAssertEqual(settings.resolutionDescriptor.width, 720)
        XCTAssertEqual(settings.resolutionDescriptor.height, 1280)
        XCTAssertEqual(settings.normalizedResolutionClass, .p720)
    }

    func testLiveStreamSettingsModelExportImportPreservesOrientation() {
        let source = LiveStreamSettingsModel()
        source.videoWidth = 1080
        source.videoHeight = 1920
        source.streamOrientation = .portrait

        let json = source.exportToJSON()

        let target = LiveStreamSettingsModel()
        XCTAssertTrue(target.importFromJSON(json))
        XCTAssertEqual(target.streamOrientation, .portrait)
        XCTAssertEqual(target.videoWidth, 1080)
        XCTAssertEqual(target.videoHeight, 1920)
    }

    func testLiveStreamSettingsModelImportInfersOrientationWhenMissing() {
        let json = """
        {
          "streamTitle": "Test",
          "rtmpURL": "rtmp://a.rtmp.youtube.com/live2",
          "streamKey": "stream-key",
          "videoBitrate": 2500,
          "videoWidth": 720,
          "videoHeight": 1280,
          "frameRate": 30,
          "keyframeInterval": 2,
          "videoEncoder": "H.264",
          "audioBitrate": 128,
          "audioEncoder": "AAC",
          "autoReconnect": true,
          "isEnabled": true,
          "bufferSize": 3,
          "connectionTimeout": 30,
          "exportedAt": "2026-03-19T00:00:00Z"
        }
        """

        let model = LiveStreamSettingsModel()
        XCTAssertTrue(model.importFromJSON(json))
        XCTAssertEqual(model.streamOrientation, .portrait)
    }
    
    func testApplyYouTubePresetKeepsSelectedOrientation() {
        var settings = LiveStreamSettings()
        settings.streamOrientation = .portrait

        settings.applyYouTubeLivePreset(.fhd1080p)

        XCTAssertEqual(settings.videoWidth, 1080)
        XCTAssertEqual(settings.videoHeight, 1920)
        XCTAssertEqual(settings.frameRate, 30)
        XCTAssertEqual(settings.videoBitrate, 4500)
    }
}
