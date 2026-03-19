# 📱 USB External Camera Streaming for iOS

<div align="center">

![iOS](https://img.shields.io/badge/iOS-17.0+-blue.svg?style=flat&logo=ios)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg?style=flat&logo=swift)
![Xcode](https://img.shields.io/badge/Xcode-16.3+-blue.svg?style=flat&logo=xcode)
![HaishinKit](https://img.shields.io/badge/HaishinKit-2.0.8-red.svg?style=flat)

**Professional live streaming app with USB external camera support and real-time RTMP streaming**

[한국어](README.ko.md) | English

</div>

## 🎥 Overview

USB External Camera is a professional iOS application that enables iPad-optimized live streaming using UVC-compatible USB external cameras. Built with HaishinKit 2.0.8, it provides real-time RTMP streaming to YouTube Live with 480p/720p/1080p presets, screen-capture based compositing (camera + UI), and stability-focused frame pipeline controls.

### 💡 Development Motivation

This project was initiated to enable **flexible shooting and monitoring from various angles in mobile environments** using external cameras. Traditional mobile streaming is limited to built-in camera positions, but by leveraging USB external cameras, users can achieve professional-grade streaming setups with multiple camera angles, remote positioning, and enhanced video quality - all while maintaining the portability and convenience of iPad devices.

### ✨ Key Highlights

- 📹 **Screen Capture Streaming** - Stream camera preview + UI overlay simultaneously
- 🔌 **USB Camera Support** - Full support for UVC-compatible external cameras
- 📡 **Real-time RTMP** - Professional streaming with HaishinKit 2.0.8
- 🎛️ **Advanced Controls** - Video/audio quality, resolution, bitrate settings
- 🎚️ **YouTube Presets** - 480p / 720p / 1080p quick presets with manual override
- 📊 **Live Statistics** - Real-time monitoring of streaming performance
- 🎬 **Integrated YouTube Studio** - Built-in YouTube Studio WebView for direct stream management
- ⌨️ **Smart Keyboard Handling** - Optimized keyboard input for WebView interactions
- 🌍 **Multi-language** - Korean and English support

## 🚀 Features

### Core Streaming Features
- ✅ Real-time RTMP streaming to YouTube Live
- ✅ Screen capture streaming (camera + UI overlay)
- ✅ USB external camera integration with AVFoundation
- ✅ Hardware-accelerated H.264 video encoding
- ✅ Real-time audio mixing and processing with AAC encoding
- ✅ Mic permission/audio-session preflight before live start (prevents audio 0 kbps cases)
- ✅ Frame backpressure control in screen-capture pipeline (reduced buffering/stutter)
- 🚧 Microphone mute toggle is currently under development (temporarily disabled in UI)

### Video & Audio
- 🎬 **Resolutions**: 480p (848×480), 720p (1280×720), 1080p (1920×1080)
- 🎵 **Audio**: AAC encoding with configurable bitrates
- 📏 **Frame Rate**: 24/30/60 selectable in UI (effective capture is currently capped to 30fps, and 1080p is optimized to 24fps)
- 🔧 **Bitrate Control**: Configurable 500-10000 kbps (video), 64-256 kbps (audio)

### Advanced Features
- 📈 Real-time streaming statistics and monitoring
- 🔄 Automatic reconnection and error recovery
- ⚙️ YouTube Live optimized presets (480p/720p/1080p)
- 🎯 Network quality monitoring and bitrate adjustment
- 🛡️ Black-frame mitigation with UI-only fallback and stale-frame reuse
- 📱 iOS device orientation support
- ⚡ Performance optimization for iPad devices
- 🎬 **YouTube Studio Integration** - Native WebView with desktop browser compatibility
- ⌨️ **Enhanced Keyboard Support** - Custom keyboard accessory for better WebView interaction
- 📱 **Adaptive Layout** - Responsive layout for different screen sizes and orientations

## 📋 Requirements

- **iOS**: 17.0 or later
- **Xcode**: 16.3 or later
- **Development Host**: Apple Silicon Mac recommended and officially supported for local builds and simulator validation
- **Device**: iPad with USB-C port (iPhone not officially supported - not tested due to lack of test device)
- **Camera**: UVC-compatible USB external camera
- **Microphone**: Mic permission required for audio track output
- **Network**: Stable upload bandwidth (recommended: 3+ Mbps for 480p, 6+ Mbps for 720p, 10+ Mbps for 1080p)
- **Orientation**: **Landscape mode** (Portrait mode under development) - Currently optimized for landscape orientation

> **Policy Note**: Intel Mac development environments are not officially supported. Simulator validation is based on Apple Silicon Macs, and this project intentionally excludes the `x86_64` iOS Simulator architecture.

### 📷 Tested External Cameras

**Professional Cameras**
- ✅ **Sony a7M4** - DSLR/Mirrorless camera with UVC support
  - Supports up to 720p via USB-C
  - Excellent low-light performance
  - Professional video quality

**Webcams**  
- ✅ **Logitech C922x Pro** - Professional streaming webcam
  - Native 720p support at 30fps
  - Built-in stereo microphones
  - Auto-focus and light correction

> **Note**: Any UVC-compatible camera should work. The cameras listed above have been specifically tested and verified to work well with this app.

### 📱 Tested iPad Devices

**iPad Pro Models**
- ✅ **iPad Pro 12.9-inch (4th generation)** - 2020 model
  - **Chip**: A12Z Bionic (8-core with Neural Engine)
  - **USB Port**: USB-C with high-speed data transfer
  - **Memory**: 6GB RAM
  - **Display**: 12.9-inch Liquid Retina with ProMotion (120Hz)
  - **Performance**: Excellent streaming performance with hardware acceleration
  - **Power**: Can power most webcams directly, may need powered hub for professional cameras

> **Note**: While this app is optimized for iPad Pro models with USB-C ports, it should work on any iPad with USB-C running iOS 17.0 or later. Performance may vary depending on device capabilities.

## 🛠 Installation

### Clone and Build

```bash
# Clone the repository
git clone <repository-url>
cd USBExternalCamera-iOS

# Open in Xcode
open USBExternalCamera.xcodeproj

# Build and run on your device
# Note: A physical device is required for camera functionality
# Note: Intel Mac simulator builds are not supported by project policy
```

### Dependencies

The project uses Swift Package Manager with the following dependencies:

- [LiveStreamingCore](https://github.com/joopark4/LiveStreamingCore) (1.0.0) - Reusable RTMP streaming module
- [HaishinKit](https://github.com/HaishinKit/HaishinKit.swift) (2.0.8) - RTMP streaming engine
- [Logboard](https://github.com/shogo4405/Logboard) (2.5.0) - Advanced logging

All dependencies are managed automatically by Xcode.

### LiveStreamingCore Module

The **[LiveStreamingCore](https://github.com/joopark4/LiveStreamingCore)** is a separate Swift Package that provides reusable RTMP streaming functionality:

**Features:**
- RTMP streaming functionality based on HaishinKit
- YouTube Live optimized presets and settings
- Streaming statistics and diagnostics
- Text overlay support
- Connection management and error handling

**Installation via SPM:**
```swift
.package(url: "https://github.com/joopark4/LiveStreamingCore.git", from: "1.0.0")
```

See [LiveStreamingCore Repository](https://github.com/joopark4/LiveStreamingCore) for detailed usage instructions.

## 🎯 Quick Start

### 1. Hardware Setup
1. Connect a UVC-compatible USB camera to your iPad
2. Use a USB-C hub or direct USB-C connection
3. Grant camera and microphone permissions when prompted

### 2. Configure Streaming
1. Open the app and navigate to **Live Stream Settings**
2. Set your RTMP URL and stream key:
   ```
   RTMP URL: rtmp://a.rtmp.youtube.com/live2/
   Stream Key: [Your YouTube stream key]
   ```
3. Choose your streaming quality preset:
   - **480p**: Best for limited bandwidth or older devices
   - **720p**: Recommended for most streaming scenarios
   - **1080p**: Use on high-performance iPads + stable uplink (recommended bitrate range: 4500-9000 kbps)

### 3. Start Streaming
1. Select your USB camera from the camera list
2. Tap **Start Screen Capture Streaming**
3. Check stream status from the sidebar state and the YouTube Studio panel

### YouTube Live Setup
1. Go to [YouTube Studio](https://studio.youtube.com)
2. Click **Create** → **Go Live**
3. Copy your **Stream Key** from the Stream tab
4. Use `rtmp://a.rtmp.youtube.com/live2/` as RTMP URL

### 🎬 YouTube Studio Integration

The app features a built-in **YouTube Studio WebView** that allows you to manage your streams directly without switching apps:

**Key Features:**
- **Desktop Browser Compatibility** - Uses Safari 17.1 User-Agent for full feature access
- **Full YouTube Studio Access** - All features available including stream management, analytics, chat
- **Optimized Layout** - Maximized WebView space for better usability
- **Smart Keyboard Handling** - Custom keyboard accessory prevents layout issues
- **Persistent Login** - Login state is maintained across app sessions

**Layout Options:**
- **Wide Screens (iPad/Mac)**: Camera preview (45%) + YouTube Studio (55%) side-by-side
- **Narrow Screens (iPhone)**: Camera preview (35%) + YouTube Studio (60%) stacked vertically

**WebView Enhancements:**
- Modern User-Agent string for compatibility with latest YouTube Studio features
- Enhanced JavaScript capabilities for full functionality
- Automatic data persistence for login sessions
- Improved keyboard input handling with custom accessory view

## 🏗 Architecture

The app follows MVVM architecture with SwiftUI and modular design:

```
USBExternalCamera-iOS/
├── USBExternalCamera/           # Main App
│   ├── Views/                   # SwiftUI Views
│   │   ├── LiveStream/         # Streaming UI
│   │   ├── Camera/             # Camera selection and preview
│   │   └── Settings/           # Configuration views
│   ├── ViewModels/             # MVVM ViewModels
│   ├── Models/                 # Data models
│   ├── Managers/               # System managers
│   └── Utils/                  # Utilities and extensions
│
└── [External Package: LiveStreamingCore]
    # https://github.com/joopark4/LiveStreamingCore
    └── Sources/
        └── LiveStreamingCore/
            ├── Models/              # StreamStats, ConnectionInfo, etc.
            ├── LiveStreaming/
            │   ├── Managers/        # HaishinKitManager
            │   ├── Types/           # StreamingModels, Validation
            │   └── Utilities/       # Helpers
            └── ...
```

### Key Components

- **HaishinKitManager**: Core streaming engine wrapper (in LiveStreamingCore module)
- **CameraViewModel**: USB camera management
- **LiveStreamViewModel**: Streaming state management
- **LoggingManager**: Centralized logging system (in LiveStreamingCore module)
- **LiveStreamSettingsModel**: SwiftData-based persistent settings (in LiveStreamingCore module)

## 🎬 Streaming Quality Presets

| Preset | Resolution | Video Bitrate | Audio Bitrate | Frame Rate |
|--------|------------|---------------|---------------|------------|
| Low (480p) | 480p | 1.5 Mbps | 128 kbps | 30 fps |
| Standard (720p) | 720p | 2.5 Mbps | 128 kbps | 30 fps |
| Full HD (1080p) | 1080p | 4.5 Mbps (recommended 4.5-9.0 Mbps) | 128 kbps | 30 fps target (24 fps capture optimized) |


## 🐛 Troubleshooting

### Common Issues

**Camera not detected**
- Ensure USB camera is UVC-compatible
- Check USB-C hub or direct connection
- Grant camera permissions in iOS Settings
- Note: iPhone support not officially tested due to lack of test device

**Camera power issues / Insufficient power**
- Some cameras (especially professional cameras like Sony a7M4) may require more power than iPad can provide
- Use a **powered USB-C hub** that connects to external power source
- Connect both the camera and power supply to the powered hub
- Ensure the hub supports sufficient power delivery for your camera model
- Check camera's power indicator lights to confirm adequate power supply

**RTMP connection failed**
- Verify RTMP URL and stream key
- Check network connectivity
- Ensure firewall allows RTMP traffic

**YouTube Studio WebView Issues**
- **"Outdated browser" message**: Fixed with Safari 17.1 User-Agent (automatic)
- **Login not working**: Clear WebView data in iOS Settings > Safari > Advanced > Website Data
- **Keyboard covering content**: Custom keyboard accessory automatically handles this
- **Layout freezing**: Adaptive layout prevents UI disruption during keyboard events
- **Features not working**: All desktop YouTube Studio features are supported with enhanced WebView

**Frame drops during streaming**
- Lower bitrate settings (use 480p for better stability)
- Switch to more stable network connection
- Close other apps to free memory and CPU resources
- For 1080p, start around 6000-6800 kbps and increase gradually based on YouTube health
- If buffering persists, switch to 720p preset before increasing bitrate again

**Black screen on YouTube output**
- Confirm camera preview is visible in-app before pressing Start
- Keep microphone permission enabled (audio track initialization is part of startup preflight)
- Reconnect camera/hub if preview freezes; powered USB-C hubs are recommended for high-power devices
- Stop/Start streaming once after changing major settings (resolution/bitrate)

**YouTube warning: low current bitrate / audio 0 kbps**
- Verify upload bandwidth with sustained tests (instant peak speed is not enough)
- Ensure audio bitrate is set to at least **128 kbps**
- Allow microphone permission in iPad Settings > Privacy & Security > Microphone
- If video is stable but health warning remains, lower video bitrate first, then retest

**Performance optimization**
- 1080p is supported; screen-capture pipeline uses 24fps capture optimization to reduce buffering
- 480p recommended for slower devices or limited bandwidth
- Hardware acceleration is automatically enabled when available

**Portrait mode / UI layout issues**
- This app currently supports **landscape mode only**
- Portrait mode may cause UI layout problems (portrait mode support is under development)
- For now, rotate your iPad to landscape orientation before using the app
- Streaming performance is currently optimized for landscape orientation

### Debug Logs

Use Xcode console with these filters:
```
🎥        # All streaming logs
[RTMP]    # RTMP connection logs
[CAMERA]  # Camera system logs
```

## 🔧 Development

### Building from Source

```bash
# Ensure you have Xcode 16.3+
xcode-select --install

# Clone and setup
git clone <repository-url>
cd USBExternalCamera-iOS

# Open project
open USBExternalCamera.xcodeproj
```

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftUI for all new UI components
- Implement proper error handling with async/await
- Add comprehensive logging for debugging

### Testing

```bash
# Build for device
xcodebuild -scheme USBExternalCamera -destination 'platform=iOS,name=Your-Device'

# Note: Physical device required for camera functionality
# Simulator testing is limited to UI components only
# Note: Intel Mac simulator validation is not supported
```

### 🚧 Future Development Plans

- **Portrait Mode Support**: Currently under development to support both landscape and portrait orientations
- **Enhanced UI Layouts**: Improved responsive design for different screen orientations
- **Additional Camera Features**: More camera controls and settings
- **Performance Improvements**: Continued optimization for various iPad models

## 📖 Documentation

### Project Documentation
- [LiveStreamingCore Repository](https://github.com/joopark4/LiveStreamingCore) - Reusable streaming module (separate GitHub repository)

### External References
- [HaishinKit Documentation](https://github.com/HaishinKit/HaishinKit.swift)
- [YouTube Live Streaming API](https://developers.google.com/youtube/v3/live)
- [AVFoundation Guide](https://developer.apple.com/documentation/avfoundation)
- [Apple - Support external cameras in your iPadOS app (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10106/)
  - Apple's official guide for USB Video Class (UVC) external camera support on iPad
- [Apple - Still and Video Media Capture](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/04_MediaCapture.html)
  - Detailed guide for media capture using AVFoundation

## 🙏 Acknowledgments

- [HaishinKit](https://github.com/HaishinKit/HaishinKit.swift) - Excellent RTMP streaming framework
- [YouTube Live API](https://developers.google.com/youtube/v3/live) - Live streaming platform
- Apple's [AVFoundation](https://developer.apple.com/documentation/avfoundation) - Camera and media framework

## ⚠️ Disclaimer

This project is currently in development and may have incomplete documentation or unverified issues. We appreciate your understanding as we continue to improve the app and its documentation. If you encounter any problems or have suggestions, please feel free to open an issue or contribute to the project.

**Known limitations:**
- Not all camera models and configurations have been tested
- Some edge cases and compatibility issues may exist
- Documentation may be incomplete in certain areas
- iPhone support is not officially verified due to lack of test devices

Thank you for your patience and support! 🙏

---

<div align="center">

Made with ❤️ for iOS streaming

</div> 
