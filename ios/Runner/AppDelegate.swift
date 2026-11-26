import CommonCrypto
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "WaffrPbkdf2") {
      Pbkdf2Channel.register(messenger: registrar.messenger())
    }
  }
}

/// PBKDF2-HMAC-SHA256 with CommonCrypto, over the exact bytes Dart sends.
///
/// Must give the same bytes as the app's Dart implementation
/// (lib/core/security/pbkdf2.dart); RunnerTests checks the shared vectors.
enum Pbkdf2Native {
  static let maxIterations = 10_000_000
  static let maxPasswordBytes = 1024

  enum Failure: Error {
    case badInput(String)
    case status(Int32)
  }

  static func derive(password: [UInt8], salt: [UInt8], iterations: Int, length: Int) throws -> [UInt8] {
    guard (1...maxIterations).contains(iterations) else { throw Failure.badInput("iterations") }
    guard (1...64).contains(salt.count) else { throw Failure.badInput("salt") }
    guard password.count <= maxPasswordBytes else { throw Failure.badInput("password") }
    guard (1...64).contains(length) else { throw Failure.badInput("length") }

    // An HMAC key shorter than the 64-byte block is padded with zeros, so an
    // empty password is the same key as 64 zero bytes. CommonCrypto may
    // refuse a zero-length password; this gives the identical result.
    var key = password.isEmpty ? [UInt8](repeating: 0, count: 64) : password
    var saltBytes = salt
    var out = [UInt8](repeating: 0, count: length)
    defer {
      for index in key.indices { key[index] = 0 }
    }
    let status = key.withUnsafeBufferPointer { keyBuffer in
      saltBytes.withUnsafeMutableBufferPointer { saltBuffer in
        out.withUnsafeMutableBufferPointer { outBuffer in
          keyBuffer.baseAddress!.withMemoryRebound(to: Int8.self, capacity: keyBuffer.count) { keyPointer in
            CCKeyDerivationPBKDF(
              CCPBKDFAlgorithm(kCCPBKDF2),
              keyPointer,
              keyBuffer.count,
              saltBuffer.baseAddress,
              saltBuffer.count,
              CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
              UInt32(iterations),
              outBuffer.baseAddress,
              outBuffer.count
            )
          }
        }
      }
    }
    guard status == Int32(kCCSuccess) else { throw Failure.status(status) }
    return out
  }
}

/// The "waffr/pbkdf2" method channel. Work runs off the main thread; the
/// reply goes back on main. Inputs and outputs are never logged.
enum Pbkdf2Channel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "waffr/pbkdf2", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "derive":
        derive(call.arguments, result: result)
      case "info":
        result(info())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func derive(_ arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let password = args["password"] as? FlutterStandardTypedData,
      let salt = args["salt"] as? FlutterStandardTypedData,
      let iterations = (args["iterations"] as? NSNumber)?.intValue,
      let length = (args["length"] as? NSNumber)?.intValue
    else {
      result(FlutterError(code: "bad_arguments", message: "pbkdf2 arguments", details: nil))
      return
    }
    var passwordBytes = [UInt8](password.data)
    let saltBytes = [UInt8](salt.data)
    DispatchQueue.global(qos: .userInitiated).async {
      defer {
        for index in passwordBytes.indices { passwordBytes[index] = 0 }
      }
      do {
        let derived = try Pbkdf2Native.derive(
          password: passwordBytes, salt: saltBytes, iterations: iterations, length: length)
        let reply = FlutterStandardTypedData(bytes: Data(derived))
        DispatchQueue.main.async { result(reply) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "pbkdf2_failed", message: String(describing: type(of: error)), details: nil))
        }
      }
    }
  }

  private static func info() -> [String: Any] {
    var system = utsname()
    uname(&system)
    let machine = withUnsafeBytes(of: &system.machine) { buffer in
      String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
    let bundle = Bundle.main.infoDictionary ?? [:]
    return [
      "platform": "ios",
      "implementation": "CommonCrypto CCKeyDerivationPBKDF",
      "model": machine,
      "os_version": UIDevice.current.systemVersion,
      "app_version": "\(bundle["CFBundleShortVersionString"] ?? "?")+\(bundle["CFBundleVersion"] ?? "?")",
      "cpu_count": ProcessInfo.processInfo.activeProcessorCount,
    ]
  }
}
