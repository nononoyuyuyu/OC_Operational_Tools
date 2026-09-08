import Flutter
import UIKit
import BackgroundTasks
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var runtime: OcoRuntime?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "OcoRuntime") {
      runtime = OcoRuntime(messenger: registrar.messenger())
    }
  }
}

private final class OcoRuntime {
  private let channel: FlutterMethodChannel
  private var background: UIBackgroundTaskIdentifier = .invalid
  private var tasks: [String: String] = [:]
  private var continued: [String: BGTask] = [:]
  private var registered = Set<String>()
  private var observers: [NSObjectProtocol] = []
  private var lastProgress = Date.distantPast
  private var notificationsAsked = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "jp.nononoyuyuyu.open_campus_organizer/runtime", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return result(nil) }
      let args = call.arguments as? [String: Any] ?? [:]
      switch call.method {
      case "configure": result(nil)
      case "begin":
        let id = args["id"] as? String ?? "task"
        let title = args["title"] as? String ?? "Open Campus Organizer"
        self.tasks[id] = title
        if !self.notificationsAsked {
          self.notificationsAsked = true
          UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            if !granted { DispatchQueue.main.async { self.channel.invokeMethod("notificationsDenied", arguments: nil) } }
          }
        }
        self.begin(id: id, title: title)
        result(nil)
      case "progress":
        let id = args["id"] as? String ?? "task"
        let message = args["message"] as? String ?? "処理中"
        let done = (args["done"] as? NSNumber)?.int64Value ?? 0
        let total = (args["total"] as? NSNumber)?.int64Value ?? 0
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let task = self.continued[id] as? BGContinuedProcessingTask {
          task.progress.totalUnitCount = max(total, done + 1)
          task.progress.completedUnitCount = done
          task.updateTitle(self.tasks[id] ?? "Open Campus Organizer", subtitle: message)
        }
        #endif
        if UIApplication.shared.applicationState != .active && Date().timeIntervalSince(self.lastProgress) > 10 {
          self.lastProgress = Date()
          self.notify(id: "progress", title: self.tasks[id] ?? "Open Campus Organizer",
                      message: total > 0 ? "\(message) · \(done) / \(total)" : message)
        }
        result(nil)
      case "finish":
        let id = args["id"] as? String ?? "task"
        let title = self.tasks.removeValue(forKey: id) ?? "Open Campus Organizer"
        self.continued.removeValue(forKey: id)?.setTaskCompleted(success: args["failed"] as? Bool != true)
        self.notify(id: id, title: title, message: args["message"] as? String ?? "処理が終了しました。")
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["oco.progress"])
        if self.tasks.isEmpty { self.endBackground() }
        result(nil)
      case "exit": self.endBackground(); result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
      self?.channel.invokeMethod("background", arguments: nil)
    })
    observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      self?.channel.invokeMethod("foreground", arguments: nil)
    })
  }

  private func begin(id: String, title: String) {
    #if compiler(>=6.2)
    if #available(iOS 26.0, *), UIApplication.shared.applicationState == .active {
      guard let bundle = Bundle.main.bundleIdentifier else { return }
      let identifier = "\(bundle).processing.\(id)"
      if !registered.contains(identifier) {
        let accepted = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { [weak self] task in
          guard let self = self, let processing = task as? BGContinuedProcessingTask else { task.setTaskCompleted(success: false); return }
          guard self.tasks[id] != nil else { task.setTaskCompleted(success: true); return }
          self.continued[id] = processing
          processing.progress.totalUnitCount = 1
          processing.expirationHandler = { [weak self] in
            DispatchQueue.main.async {
              self?.channel.invokeMethod("suspend", arguments: nil)
              self?.continued.removeValue(forKey: id)?.setTaskCompleted(success: false)
            }
          }
        }
        if accepted { registered.insert(identifier) }
      }
      if registered.contains(identifier) {
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: "準備中")
        request.strategy = .fail
        do { try BGTaskScheduler.shared.submit(request); return } catch { /* 短時間の継続へ切り替える。 */ }
      }
    }
    #endif
    if background == .invalid {
      background = UIApplication.shared.beginBackgroundTask(withName: "Open Campus Organizer") { [weak self] in
        self?.channel.invokeMethod("suspend", arguments: nil)
        self?.notify(id: "paused", title: "処理を保存しました", message: "アプリを開くと再開します。")
        self?.endBackground()
      }
    }
  }
  private func endBackground() {
    if background != .invalid { UIApplication.shared.endBackgroundTask(background); background = .invalid }
  }
  private func notify(id: String, title: String, message: String) {
    let content = UNMutableNotificationContent()
    content.title = title; content.body = message
    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "oco.\(id)", content: content, trigger: nil))
  }
  deinit {
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    endBackground()
  }
}
