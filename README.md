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

USB External Camera is a professional iOS application that enables iPad-optimized live streaming using UVC-compatible USB external cameras. Built with HaishinKit 2.0.8, it provides real-time RTMP streaming to YouTube Live with performance-optimized 480p/720p quality presets designed specifically for iPad devices.

### 💡 Development Motivation

This project was initiated to enable **flexible shooting and monitoring from various angles in mobile environments** using external cameras. Traditional mobile streaming is limited to built-in camera positions, but by leveraging USB external cameras, users can achieve professional-grade streaming setups with multiple camera angles, remote positioning, and enhanced video quality - all while maintaining the portability and convenience of iPad devices.

### ✨ Key Highlights

- 📹 **Screen Capture Streaming** - Stream camera preview + UI overlay simultaneously
- 🔌 **USB Camera Support** - Full support for UVC-compatible external cameras
- 📡 **Real-time RTMP** - Professional streaming with HaishinKit 2.0.8
- 🎛️ **Advanced Controls** - Video/audio quality, resolution, bitrate settings
- 📊 **Live Statistics** - Real-time monitoring of streaming performance
- 🌍 **Multi-language** - Korean and English support

## 🚀 Features

### Core Streaming Features
- ✅ Real-time RTMP streaming to YouTube Live
- ✅ Screen capture streaming (camera + UI overlay)
- ✅ USB external camera integration with AVFoundation
- ✅ Hardware-accelerated H.264 video encoding
- ✅ Real-time audio mixing and processing with AAC encoding

### Video & Audio
- 🎬 **Resolutions**: 480p, 720p support
- 🎵 **Audio**: AAC encoding with configurable bitrates
- 📏 **Frame Rate**: 30fps
- 🔧 **Bitrate Control**: Configurable bitrate settings

### Advanced Features
- 📈 Real-time streaming statistics and monitoring
- 🔄 Automatic reconnection and error recovery
- ⚙️ YouTube Live optimized presets (480p/720p)
- 🎯 Network quality monitoring and bitrate adjustment
- 📱 iOS device orientation support
- ⚡ Performance optimization for iPad devices

## 📋 Requirements

- **iOS**: 17.0 or later
- **Xcode**: 16.3 or later
- **Device**: iPad with USB-C port (iPhone not officially supported - not tested due to lack of test device)
- **Camera**: UVC-compatible USB external camera
- **Network**: Stable internet connection (minimum 2-5 Mbps upload for 480p/720p)
- **Orientation**: **Landscape mode** (Portrait mode under development) - Currently optimized for landscape orientation

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
# Note: Simulator is not supported for camera functionality
```

### Dependencies

The project uses Swift Package Manager with the following dependencies:

- [HaishinKit](https://github.com/HaishinKit/HaishinKit.swift) (2.0.8) - RTMP streaming engine
- [Inject](https://github.com/krzysztofzablocki/Inject) (1.5.2) - Development hot reload
- [Logboard](https://github.com/shogo4405/Logboard) (2.5.0) - Advanced logging

All dependencies are managed automatically by Xcode.

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

### 3. Start Streaming
1. Select your USB camera from the camera list
2. Tap **Start Screen Capture Streaming**
3. Monitor real-time statistics in the streaming view

### YouTube Live Setup
1. Go to [YouTube Studio](https://studio.youtube.com)
2. Click **Create** → **Go Live**
3. Copy your **Stream Key** from the Stream tab
4. Use `rtmp://a.rtmp.youtube.com/live2/` as RTMP URL

## 🏗 Architecture

The app follows MVVM architecture with SwiftUI:

```
USBExternalCamera/
├── Views/                    # SwiftUI Views
│   ├── LiveStream/          # Streaming UI
│   ├── Camera/              # Camera selection and preview
│   └── Settings/            # Configuration views
├── ViewModels/              # MVVM ViewModels
├── Services/                # Business logic
│   └── LiveStreaming/       # Streaming services
├── Models/                  # Data models
├── Managers/                # System managers
└── Utils/                   # Utilities and extensions
```

### Key Components

- **HaishinKitManager**: Core streaming engine wrapper
- **CameraViewModel**: USB camera management
- **LiveStreamViewModel**: Streaming state management
- **LoggingManager**: Centralized logging system

## 🎬 Streaming Quality Presets

| Preset | Resolution | Video Bitrate | Audio Bitrate | Frame Rate |
|--------|------------|---------------|---------------|------------|
| Low (480p) | 480p | 1.5 Mbps | 128 kbps | 30 fps |
| Standard (720p) | 720p | 2.5 Mbps | 128 kbps | 30 fps |


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

**Frame drops during streaming**
- Lower bitrate settings (use 480p for better stability)
- Switch to more stable network connection
- Close other apps to free memory and CPU resources
- Use 720p maximum for optimal performance on iPad devices

**Performance optimization**
- 1080p settings are automatically downscaled to 720p
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
```

### 🚧 Future Development Plans

- **Portrait Mode Support**: Currently under development to support both landscape and portrait orientations
- **Enhanced UI Layouts**: Improved responsive design for different screen orientations
- **Additional Camera Features**: More camera controls and settings
- **Performance Improvements**: Continued optimization for various iPad models

## 📖 Documentation

- [HaishinKit Documentation](https://github.com/HaishinKit/HaishinKit.swift)
- [YouTube Live Streaming API](https://developers.google.com/youtube/v3/live)
- [AVFoundation Guide](https://developer.apple.com/documentation/avfoundation)
- [Apple - Support external cameras in your iPadOS app (WWDC23)](https://developer.apple.com/videos/play/wwdc2023/10106/)
  - iPad에서 USB Video Class (UVC) 외부 카메라 지원에 대한 Apple 공식 가이드
- [Apple - Still and Video Media Capture](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/AVFoundationPG/Articles/04_MediaCapture.html)
  - AVFoundation을 사용한 미디어 캡처에 대한 상세 가이드

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
