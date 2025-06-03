//
//  USBExternalCameraApp.swift
//  USBExternalCamera
//
//  Created by BYEONG JOO KIM on 5/25/25.
//

import SwiftUI
import AVFoundation

@main
struct USBExternalCameraApp: App {
    init() {
        // 디바이스 방향 변경 알림 활성화
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
