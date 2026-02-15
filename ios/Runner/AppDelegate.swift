import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Register for remote notifications
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }

    application.registerForRemoteNotifications()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle background location updates
  override func applicationDidEnterBackground(_ application: UIApplication) {
    // Keep location updates running in background
  }

  // Handle app returning to foreground
  override func applicationWillEnterForeground(_ application: UIApplication) {
    // Location tracking continues automatically
  }
}
