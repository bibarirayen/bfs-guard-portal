import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Enable background location updates
    if #available(iOS 9.0, *) {
      application.registerForRemoteNotifications()
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Handle background location updates
  override func applicationDidEnterBackground(_ application: UIApplication) {
    // Keep location updates running in background
    // The actual location tracking is handled by geolocator plugin
  }

  // Handle app returning to foreground
  override func applicationWillEnterForeground(_ application: UIApplication) {
    // Location tracking continues automatically
  }
}
