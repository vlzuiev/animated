import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let videoPathKey = "videoPath"
    private static let appleBackgroundKey = "useAppleBackground"
    private static let installedLockScreenKey = "installedLockScreenPath"

    func applicationDidFinishLaunching(_ notification: Notification) {
        ResourceMonitor.shared.start()
        LockScreenRefresher.shared.start()
        // A previous instance may have been quit mid-export; sweep its debris.
        LockScreenInstaller.shared.cleanUpTempExports()
        // User explicitly chose the plain Apple background — stay idle.
        guard !UserDefaults.standard.bool(forKey: Self.appleBackgroundKey) else { return }
        // No video chosen yet — stay idle until the user picks one.
        guard let video = Self.currentVideoURL() else { return }
        WallpaperController.shared.start(videoURL: video)
        Self.installToLockScreenIfNeeded(videoURL: video)
    }

    /// The user's chosen video, or nil when none is set.
    static func currentVideoURL() -> URL? {
        guard let saved = UserDefaults.standard.string(forKey: videoPathKey),
              FileManager.default.fileExists(atPath: saved) else { return nil }
        return URL(fileURLWithPath: saved)
    }

    /// Skips the (slow) convert-and-swap when this video is already installed.
    private static func installToLockScreenIfNeeded(videoURL: URL) {
        guard UserDefaults.standard.string(forKey: installedLockScreenKey) != videoURL.path else {
            // Already installed — still refresh the poster so the lock
            // screen's still image always matches the current video.
            Task { await LockScreenInstaller.shared.refreshPoster(from: videoURL) }
            return
        }
        installToLockScreen(videoURL: videoURL)
    }

    /// Stops the animation everywhere and hands both surfaces back to Apple.
    static func useAppleBackground() {
        WallpaperController.shared.stop()
        do {
            try LockScreenInstaller.shared.restoreOriginal()
        } catch {
            Task { await alert(title: "Couldn't restore lock screen", text: error.localizedDescription, button: "OK") }
        }
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: appleBackgroundKey)
        defaults.removeObject(forKey: videoPathKey)
        defaults.removeObject(forKey: installedLockScreenKey)
    }

    /// Runs automatically after every video choice — desktop is already
    /// switched; this brings the lock screen along.
    private static func installToLockScreen(videoURL: URL) {
        Task {
            do {
                let firstInstall = try await LockScreenInstaller.shared.install(videoURL: videoURL)
                UserDefaults.standard.set(videoURL.path, forKey: installedLockScreenKey)
                if firstInstall {
                    await alert(
                        title: "One-time lock screen setup",
                        text: "In System Settings → Wallpaper, select the “Tahoe Day” aerial — it is now secretly your video. From now on, every video you choose applies to the lock screen automatically. Lock with Ctrl+Cmd+Q and wake the Mac to see it.",
                        button: "Open Wallpaper Settings"
                    )
                    LockScreenInstaller.openWallpaperSettings()
                }
            } catch {
                await alert(title: "Lock screen not updated", text: error.localizedDescription, button: "OK")
            }
        }
    }

    @MainActor
    private static func alert(title: String, text: String, button: String) async {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: button)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    static func chooseVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a video (MP4/MOV) for your animated wallpaper"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: videoPathKey)
        UserDefaults.standard.set(false, forKey: appleBackgroundKey)
        WallpaperController.shared.start(videoURL: url)
        installToLockScreenIfNeeded(videoURL: url)
    }
}
