import Foundation
import Combine
import AudioToolbox
import UIKit
import UserNotifications

final class FocusTimerManager: ObservableObject {
    @Published private(set) var remainingTime: Int = 25 * 60
    @Published private(set) var isActive: Bool = false
    @Published var durationMinutes: Int = 25 {
        didSet {
            if !isActive {
                remainingTime = durationMinutes * 60
            }
        }
    }

    private var initialDuration: Int = 25
    private var timer: Timer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var endDate: Date?

    var totalSeconds: Int {
        durationMinutes * 60
    }

    var timeDisplay: String {
        let minutes = remainingTime / 60
        let seconds = remainingTime % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(totalSeconds - remainingTime) / Double(totalSeconds)
    }

    func setDuration(minutes: Int) {
        initialDuration = minutes
        if !isActive {
            durationMinutes = minutes
            remainingTime = minutes * 60
        } else {
            durationMinutes = minutes
            pause()
            remainingTime = minutes * 60
        }
    }

    func start() {
        guard !isActive else { return }
        isActive = true
        remainingTime = remainingTime == 0 ? totalSeconds : remainingTime

        // 开始后台任务
        startBackgroundTask()

        timer?.invalidate()
        // 记录结束时间以便在被挂起后仍能正确计算剩余时间
        endDate = Date().addingTimeInterval(TimeInterval(remainingTime))
        scheduleCompletionNotification()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func startBackgroundTask() {
        // 如果已经有后台任务，先结束它
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }

        // 请求新的后台任务时间
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // 后台时间即将用完，结束任务
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    func pause() {
        guard isActive else { return }
        isActive = false
        timer?.invalidate()
        timer = nil
        // 结束后台任务
        endBackgroundTask()
        // 取消通知并保留剩余时间
        cancelCompletionNotification()
        endDate = nil
    }

    func reset() {
        isActive = false
        timer?.invalidate()
        timer = nil
        remainingTime = initialDuration * 60
        // 结束后台任务
        endBackgroundTask()
        cancelCompletionNotification()
        endDate = nil
    }

    private func tick() {
        // 如果有结束时间，优先根据结束时间计算剩余时间（更可靠，即使应用被挂起）
        if let end = endDate {
            let newRemaining = Int(max(0, round(end.timeIntervalSinceNow)))
            remainingTime = newRemaining
            if remainingTime <= 0 {
                complete()
            }
            return
        }

        guard remainingTime > 0 else {
            complete()
            return
        }

        remainingTime -= 1

        if remainingTime == 0 {
            complete()
        }
    }

    private func complete() {
        isActive = false
        timer?.invalidate()
        timer = nil

        AudioServicesPlaySystemSound(1007)
        
        remainingTime = initialDuration * 60
        
        // 结束后台任务
        endBackgroundTask()
        cancelCompletionNotification()
        endDate = nil
    }

    private func scheduleCompletionNotification() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            if settings.authorizationStatus != .authorized {
                center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
            }

            guard let self = self, let end = self.endDate else { return }
            let interval = max(1, end.timeIntervalSinceNow)

            let content = UNMutableNotificationContent()
            content.title = "专注完成"
            content.body = "您的专注时间已结束。"
            content.sound = .default

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(identifier: "FocusComplete", content: content, trigger: trigger)

            center.add(request) { error in
                if let error = error {
                    print("Failed to schedule notification: \(error)")
                }
            }
        }
    }

    private func cancelCompletionNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["FocusComplete"])
    }
}