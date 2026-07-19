import AppKit
import AVFoundation

/// Plays a muted, looping video in a borderless window that sits just below
/// the desktop icons on every screen — the standard "live wallpaper" technique.
final class WallpaperController {
    static let shared = WallpaperController()

    private var windows: [NSWindow] = []
    private var players: [AVQueuePlayer] = []
    private var loopers: [AVPlayerLooper] = []
    private var currentVideoURL: URL?
    private var userPaused = false
    private var observersInstalled = false

    func start(videoURL: URL) {
        currentVideoURL = videoURL
        userPaused = false
        installObserversIfNeeded()
        tearDownWindows()
        for screen in NSScreen.screens {
            let window = makeDesktopWindow(for: screen)
            attachPlayer(to: window, videoURL: videoURL)
            window.orderFront(nil)
        }
    }

    func pause() {
        userPaused = true
        players.forEach { $0.pause() }
    }

    func resume() {
        userPaused = false
        players.forEach { $0.play() }
    }

    /// Full stop (Use Apple Background) — forgets the video entirely.
    func stop() {
        currentVideoURL = nil
        tearDownWindows()
    }

    private func tearDownWindows() {
        players.forEach { $0.pause() }
        windows.forEach { $0.orderOut(nil) }
        windows = []
        players = []
        loopers = []
    }

    /// Login transitions, wake from sleep, and display changes can silently
    /// swallow playback (the classic symptom: static wallpaper after reboot
    /// until something pokes the player). Re-kick it on every such event.
    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.autoResume()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.autoResume()
        }
        // Screens appear/disappear (login, monitors plugged in): rebuild.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.rebuildForScreenChange()
        }
    }

    private func autoResume() {
        guard !userPaused else { return }
        if windows.isEmpty, let url = currentVideoURL {
            start(videoURL: url)
            return
        }
        players.forEach { $0.play() }
    }

    private func rebuildForScreenChange() {
        guard let url = currentVideoURL, !userPaused else { return }
        start(videoURL: url)
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
