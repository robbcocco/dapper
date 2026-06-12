import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    DriveDetectorPlugin.register(
      with: flutterViewController.registrar(forPlugin: "DriveDetectorPlugin"))
    MtpPlugin.register(
      with: flutterViewController.registrar(forPlugin: "MtpPlugin"))

    super.awakeFromNib()
  }
}
