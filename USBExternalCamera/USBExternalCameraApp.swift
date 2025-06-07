//
//  USBExternalCameraApp.swift
//  USBExternalCamera
//
//  Created by EUN YEON on 5/25/25.
//

import SwiftUI
import SwiftData
import AVFoundation

@main
struct USBExternalCameraApp: App {
    /// SwiftData ModelContainer 
    /// 라이브 스트리밍 설정을 저장하기 위한 데이터 컨테이너
    let modelContainer: ModelContainer
    
    init() {
        // 디바이스 방향 변경 알림 활성화
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        
        // SwiftData ModelContainer 초기화
        do {
            modelContainer = try ModelContainer(for: LiveStreamSettingsModel.self)
        } catch {
            fatalError(String(format: NSLocalizedString("swiftdata_init_failed", comment: ""), error.localizedDescription))
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
        }
    }
}
