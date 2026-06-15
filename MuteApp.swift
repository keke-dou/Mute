import SwiftUI
import SwiftData
import UIKit

@main
struct MuteApp: App {
    init() {
        // 禁用自动锁屏
        UIApplication.shared.isIdleTimerDisabled = true
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Track.self)
    }
}