import AVFoundation
import AVKit
import Flutter
import UIKit

/// UIView whose backing layer is an AVPlayerLayer (required for system PiP).
final class PlayerHostView: UIView {
  override class var layerClass: AnyClass { AVPlayerLayer.self }
  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

final class PlayerPlatformView: NSObject, FlutterPlatformView {
  let host: PlayerHostView
  init(frame: CGRect, plugin: NativePipPlugin) {
    host = PlayerHostView(frame: frame)
    host.backgroundColor = .black
    super.init()
    plugin.attach(host)
  }
  func view() -> UIView { host }
}

final class PlayerViewFactory: NSObject, FlutterPlatformViewFactory {
  weak var plugin: NativePipPlugin?
  init(plugin: NativePipPlugin) { self.plugin = plugin }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    PlayerPlatformView(frame: frame, plugin: plugin!)
  }
}

public class NativePipPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, AVPictureInPictureControllerDelegate {
  private let player = AVPlayer()
  private var sink: FlutterEventSink?
  private var timeObserver: Any?
  private var statusObs: NSKeyValueObservation?
  private var endObserver: NSObjectProtocol?
  private var pip: AVPictureInPictureController?
  private weak var host: PlayerHostView?
  private var pendingStartMs: Double = 0

  public static func register(with registrar: FlutterPluginRegistrar) {
    let inst = NativePipPlugin()
    let ch = FlutterMethodChannel(name: "iptv/avplayer", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(inst, channel: ch)
    let ev = FlutterEventChannel(name: "iptv/avplayer/events", binaryMessenger: registrar.messenger())
    ev.setStreamHandler(inst)
    registrar.register(PlayerViewFactory(plugin: inst), withId: "iptv/avplayer_view")
  }

  override init() {
    super.init()
    player.appliesMediaSelectionCriteriaAutomatically = false
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] _ in
      self?.tick()
    }
  }

  // MARK: view + PiP

  func attach(_ view: PlayerHostView) {
    host = view
    view.playerLayer.player = player
    view.playerLayer.videoGravity = .resizeAspect
    if AVPictureInPictureController.isPictureInPictureSupported() {
      let c = AVPictureInPictureController(playerLayer: view.playerLayer)
      c?.delegate = self
      if #available(iOS 14.2, *) { c?.canStartPictureInPictureAutomaticallyFromInline = true }
      pip = c
    }
  }

  public func pictureInPictureControllerDidStartPictureInPicture(_ c: AVPictureInPictureController) {
    send(["type": "pip", "active": true])
  }

  public func pictureInPictureControllerDidStopPictureInPicture(_ c: AVPictureInPictureController) {
    send(["type": "pip", "active": false])
  }

  public func pictureInPictureController(_ c: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
    send(["type": "pip", "active": false, "error": error.localizedDescription])
  }

  public func pictureInPictureController(_ c: AVPictureInPictureController,
                                         restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
    completionHandler(true)
  }

  // MARK: events

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func send(_ m: [String: Any]) {
    if Thread.isMainThread { sink?(m) } else { DispatchQueue.main.async { [weak self] in self?.sink?(m) } }
  }

  private func ms(_ t: CMTime) -> Double {
    let s = CMTimeGetSeconds(t)
    return s.isFinite ? s * 1000 : 0
  }

  private func tick() {
    guard let item = player.currentItem else { return }
    send([
      "type": "tick",
      "pos": ms(player.currentTime()),
      "dur": ms(item.duration),
      "playing": player.timeControlStatus == .playing,
      "buffering": player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
    ])
  }

  // MARK: methods

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "open":
      guard let s = args["url"] as? String, let url = URL(string: s) else {
        result(FlutterError(code: "url", message: "bad url", details: nil)); return
      }
      open(url, startMs: (args["start"] as? NSNumber)?.doubleValue ?? 0)
      result(nil)
    case "play": player.play(); result(nil)
    case "pause": player.pause(); result(nil)
    case "seek":
      let t = (args["ms"] as? NSNumber)?.doubleValue ?? 0
      player.seek(to: CMTime(seconds: t / 1000, preferredTimescale: 600))
      result(nil)
    case "tracks": result(tracks())
    case "selectAudio": select(.audible, index: (args["index"] as? NSNumber)?.intValue ?? -1); result(nil)
    case "selectSub": select(.legible, index: (args["index"] as? NSNumber)?.intValue ?? -1); result(nil)
    case "pipSupported": result(AVPictureInPictureController.isPictureInPictureSupported())
    case "startPip": pip?.startPictureInPicture(); result(nil)
    case "stopPip": pip?.stopPictureInPicture(); result(nil)
    case "dispose":
      pip?.stopPictureInPicture()
      player.pause()
      clearItem()
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func clearItem() {
    statusObs?.invalidate()
    statusObs = nil
    if let o = endObserver { NotificationCenter.default.removeObserver(o) }
    endObserver = nil
    player.replaceCurrentItem(with: nil)
  }

  private func open(_ url: URL, startMs: Double) {
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    try? AVAudioSession.sharedInstance().setActive(true)
    clearItem()
    pendingStartMs = startMs
    let item = AVPlayerItem(url: url)
    statusObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
      DispatchQueue.main.async {
        guard let self = self else { return }
        switch it.status {
        case .readyToPlay:
          if self.pendingStartMs > 0 {
            self.player.seek(to: CMTime(seconds: self.pendingStartMs / 1000, preferredTimescale: 600))
            self.pendingStartMs = 0
          }
          self.send(["type": "ready"])
        case .failed:
          self.send(["type": "error", "message": it.error?.localizedDescription ?? "failed"])
        default: break
        }
      }
    }
    endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
      self?.send(["type": "completed"])
    }
    player.replaceCurrentItem(with: item)
    player.play()
  }

  private func group(_ c: AVMediaCharacteristic) -> AVMediaSelectionGroup? {
    player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: c)
  }

  private func options(_ c: AVMediaCharacteristic) -> [[String: Any]] {
    guard let g = group(c) else { return [] }
    return g.options.enumerated().map { i, o in
      ["id": "\(i)", "label": o.displayName, "lang": o.extendedLanguageTag ?? o.locale?.identifier ?? ""]
    }
  }

  private func selectedIndex(_ c: AVMediaCharacteristic) -> Int {
    guard let item = player.currentItem, let g = group(c),
          let sel = item.currentMediaSelection.selectedMediaOption(in: g) else { return -1 }
    return g.options.firstIndex(of: sel) ?? -1
  }

  private func tracks() -> [String: Any] {
    [
      "audio": options(.audible),
      "subs": options(.legible),
      "audioSel": selectedIndex(.audible),
      "subSel": selectedIndex(.legible),
    ]
  }

  private func select(_ c: AVMediaCharacteristic, index: Int) {
    guard let item = player.currentItem, let g = group(c) else { return }
    if index >= 0 && index < g.options.count {
      item.select(g.options[index], in: g)
    } else if g.allowsEmptySelection {
      item.select(nil, in: g)
    }
  }
}
