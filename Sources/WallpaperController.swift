import AppKit
import AVFoundation

/// Plays a muted, looping video in a borderless window that sits just below
/// the desktop icons on every screen — the standard "live wallpaper" technique.
final class WallpaperController {
    static let shared = WallpaperController()

    private var windows: [NSWindow] = []
    private var players: [AVQueuePlayer] = []
    private var loopers: [AVPlayerLooper] = []

    func start(videoURL: URL) {
        stop()
        for screen in NSScreen.screens {
            let window = makeDesktopWindow(for: screen)
            attachPlayer(to: window, videoURL: videoURL)
            window.orderFront(nil)
        }
    }

    func pause() {
        players.forEach { $0.pause() }
    }

    func resume() {
        players.forEach { $0.play() }
    }

    func stop() {
        players.forEach { $0.pause() }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        players = []
        loopers = []
    }

    private func makeDesktopWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // One step below the desktop icons: video shows behind icons,
        // above the system wallpaper picture.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        // Stay put on every Space and during Mission Control.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        windows.append(window)
        return window
    }

    private func attachPlayer(to window: NSWindow, videoURL: URL) {
        let player = AVQueuePlayer()
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false

        let item = AVPlayerItem(url: videoURL)
        let looper = AVPlayerLooper(player: player, templateItem: item)

        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspectFill

        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        playerLayer.frame = contentView.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        contentView.layer?.addSublayer(playerLayer)

        player.play()
        players.append(player)
        loopers.append(looper)
    }
}
