import Flutter
import UIKit
import Vision
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Show deadline reminders while the app is in the foreground.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KeeprReceiptOcr") {
      ReceiptOcr.register(with: registrar.messenger())
    }
  }
}

/// On-device receipt text recognition with Apple Vision. Returns one entry
/// per recognised line with a normalised bounding box (origin top-left).
enum ReceiptOcr {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "io.keepr.app/ocr", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "recognizeText" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let bytes = args["bytes"] as? FlutterStandardTypedData,
        let image = UIImage(data: bytes.data),
        let cgImage = image.cgImage
      else {
        result(FlutterError(code: "bad_image", message: "The image could not be decoded.", details: nil))
        return
      }
      let orientation = CGImagePropertyOrientation(image.imageOrientation)
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          let lines = try recognize(cgImage, orientation: orientation, level: .accurate)
          DispatchQueue.main.async { result(lines) }
        } catch {
          // Some simulators lack the accurate model; the fast one still works.
          do {
            let lines = try recognize(cgImage, orientation: orientation, level: .fast)
            DispatchQueue.main.async { result(lines) }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "ocr_failed", message: error.localizedDescription, details: nil))
            }
          }
        }
      }
    }
  }

  private static func recognize(
    _ cgImage: CGImage,
    orientation: CGImagePropertyOrientation,
    level: VNRequestTextRecognitionLevel
  ) throws -> [[String: Any]] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = level
    request.usesLanguageCorrection = true
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
    try handler.perform([request])
    let observations = request.results ?? []
    return observations.compactMap { observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      let box = observation.boundingBox  // normalised, origin bottom-left
      return [
        "text": candidate.string,
        "confidence": Double(candidate.confidence),
        "left": Double(box.minX),
        "top": Double(1 - box.maxY),
        "width": Double(box.width),
        "height": Double(box.height),
      ]
    }
  }
}

extension CGImagePropertyOrientation {
  init(_ orientation: UIImage.Orientation) {
    switch orientation {
    case .up: self = .up
    case .upMirrored: self = .upMirrored
    case .down: self = .down
    case .downMirrored: self = .downMirrored
    case .left: self = .left
    case .leftMirrored: self = .leftMirrored
    case .right: self = .right
    case .rightMirrored: self = .rightMirrored
    @unknown default: self = .up
    }
  }
}
