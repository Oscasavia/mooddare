import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var videoExport: AVAssetExportSession?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let editor = FlutterMethodChannel(name: "mooddare/video_edit", binaryMessenger: controller.binaryMessenger)
      editor.setMethodCallHandler { [weak self] call, result in
        guard call.method == "export" else { result(FlutterMethodNotImplemented); return }
        self?.exportVideo(call, result: result)
      }
      let settings = FlutterMethodChannel(name: "mooddare/settings", binaryMessenger: controller.binaryMessenger)
      settings.setMethodCallHandler { call, result in
        switch call.method {
        case "version":
          let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
          let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
          result("\(version) (\(build))")
        case "notifications":
          let destination: String
          if #available(iOS 16.0, *) { destination = UIApplication.openNotificationSettingsURLString }
          else { destination = UIApplication.openSettingsURLString }
          guard let url = URL(string: destination) else { result(FlutterError(code: "unavailable", message: "Settings unavailable", details: nil)); return }
          UIApplication.shared.open(url) { opened in
            result(opened ? nil : FlutterError(code: "unavailable", message: "Settings unavailable", details: nil))
          }
        case "openUrl":
          guard let value = call.arguments as? String, let url = URL(string: value),
                ["https", "mailto"].contains(url.scheme ?? "") else {
            result(FlutterError(code: "invalid-url", message: "Unsupported link", details: nil)); return
          }
          UIApplication.shared.open(url) { opened in
            result(opened ? nil : FlutterError(code: "unavailable", message: "No app available", details: nil))
          }
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  private func exportVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard videoExport == nil else { result(FlutterError(code: "busy", message: "Video export in progress", details: nil)); return }
    guard let args = call.arguments as? [String: Any],
      let input = args["input"] as? String, let output = args["output"] as? String,
      let startMs = args["startMs"] as? NSNumber, let endMs = args["endMs"] as? NSNumber,
      input != output, !FileManager.default.fileExists(atPath: output),
      startMs.doubleValue >= 0, endMs.doubleValue > startMs.doubleValue else {
      result(FlutterError(code: "invalid-video", message: "Invalid video range", details: nil)); return
    }
    let destination = URL(fileURLWithPath: output).standardizedFileURL
    let roots = [NSTemporaryDirectory(), NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? ""]
    guard roots.contains(where: { !$0.isEmpty && destination.path.hasPrefix(URL(fileURLWithPath: $0).standardizedFileURL.path + "/") }) else {
      result(FlutterError(code: "invalid-output", message: "Invalid output location", details: nil)); return
    }
    let asset = AVURLAsset(url: URL(fileURLWithPath: input))
    let start = CMTime(value: startMs.int64Value, timescale: 1000)
    let end = CMTimeMinimum(CMTime(value: endMs.int64Value, timescale: 1000), asset.duration)
    guard end > start, endMs.doubleValue <= CMTimeGetSeconds(asset.duration) * 1000 + 100,
      let source = asset.tracks(withMediaType: .video).first else {
      result(FlutterError(code: "invalid-video", message: "Video unavailable", details: nil)); return
    }
    let composition = AVMutableComposition()
    let range = CMTimeRange(start: start, end: end)
    do {
      guard let video = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw NSError(domain: "video", code: 1) }
      try video.insertTimeRange(range, of: source, at: .zero)
      video.preferredTransform = source.preferredTransform
      if args["muted"] as? Bool != true {
        for track in asset.tracks(withMediaType: .audio) {
          let overlap = CMTimeRangeGetIntersection(range, otherRange: track.timeRange)
          if overlap.duration > .zero {
            let audio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            try audio?.insertTimeRange(overlap, of: track, at: CMTimeSubtract(overlap.start, start))
          }
        }
      }
      guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { throw NSError(domain: "video", code: 2) }
      session.outputURL = destination
      session.outputFileType = .mp4
      session.shouldOptimizeForNetworkUse = true
      videoExport = session
      session.exportAsynchronously { [weak self] in
        DispatchQueue.main.async {
          self?.videoExport = nil
          if session.status == .completed { result(output) }
          else {
            try? FileManager.default.removeItem(at: destination)
            result(FlutterError(code: "export", message: "Could not export this video", details: nil))
          }
        }
      }
    } catch {
      try? FileManager.default.removeItem(at: destination)
      result(FlutterError(code: "export", message: "Could not edit this video", details: nil))
    }
  }

}
