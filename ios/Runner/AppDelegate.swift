import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "idea_vault_auto_cloud_backup_periodic",
      frequency: NSNumber(value: 24 * 60 * 60)
    )
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
