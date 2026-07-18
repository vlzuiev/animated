import AppKit
import AVFoundation

/// Menu-visible progress of the lock screen install pipeline.
final class InstallStatus: ObservableObject {
    static let shared = InstallStatus()
    @Published var text: String?

    @MainActor
    static func set(_ text: String?) {
        shared.text = text
    }
}

/// Puts the user's video on the real lock screen by swapping it into the
/// slot of a downloaded Apple aerial wallpaper (macOS 26 stores those in the
/// user's home folder). The system then plays it on the lock screen itself.
final class LockScreenInstaller {
    static let shared = LockScreenInstaller()

    enum InstallError: LocalizedError {
        case noAerialDownloaded
        case sourceIsSlot

        var errorDescription: String? {
            switch self {
            case .noAerialDownloaded:
                return "No Apple aerial wallpaper is downloaded. Open System Settings → Wallpaper and download one aerial first."
            case .sourceIsSlot:
                return "Choose your own video first (menu → Choose Video…) before applying to the lock screen."
            }
        }
    }

    private let fm = FileManager.default

    private var home: URL { fm.homeDirectoryForCurrentUser }
    private var aerialVideosDir: URL {
        home.appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials/videos")
    }
    private var backupDir: URL {
        home.appendingPathComponent("Library/Application Support/Animated/backups")
    }

    /// Deletes leftover export files from interrupted or failed installs.
    /// Safe while no export is running — installs are user-serial.
    func cleanUpTempExports() {
        guard let files = try? fm.contentsOfDirectory(
            at: fm.temporaryDirectory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("animated-lockscreen-") {
            try? fm.removeItem(at: file)
        }
    }

    /// The aerial video file we hijack (the first downloaded .mov).
    func findSlot() throws -> URL {
        let movs = (try? fm.contentsOfDirectory(at: aerialVideosDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "mov" } ?? []
        guard let slot = movs.first else { throw InstallError.noAerialDownloaded }
        return slot
    }

    func backupURL(for slot: URL) -> URL {
        backupDir.appendingPathComponent(slot.deletingPathExtension().lastPathComponent + ".original.mov")
    }

    /// Full pipeline: convert → backup original (once) → atomic swap → reload renderer.
    /// Returns true when this was the very first install (one-time
    /// System Settings selection still needed).
    @discardableResult
    func install(videoURL: URL) async throws -> Bool {
        let slot = try findSlot()
        guard videoURL != slot else { throw InstallError.sourceIsSlot }
        defer { Task { await InstallStatus.set(nil) } }

        // Sweep debris from earlier interrupted/failed exports before
        // starting a new one — otherwise temp files pile up forever.
        cleanUpTempExports()

        // 1. Prepare the slot file: tiled, audio-free .mov. Passthrough keeps
        //    the original encoding (fast, ~seconds); the renderer accepts
        //    H.264 and HEVC alike (verified). Re-encode only if passthrough
        //    itself fails on an exotic source.
        await InstallStatus.set("Preparing lock screen…")
        let converted: URL
        do {
            converted = try await exportSlotVideo(source: videoURL, preset: AVAssetExportPresetPassthrough)
        } catch {
            await InstallStatus.set("Converting for lock screen…")
            converted = try await exportSlotVideo(source: videoURL, preset: AVAssetExportPresetHEVCHighestQuality)
        }
        await InstallStatus.set("Installing…")

        // 2. Keep Apple's original safe. Only ever written once — later
        //    installs must not overwrite the true original with our video.
        let backup = backupURL(for: slot)
        let firstInstall = !fm.fileExists(atPath: backup.path)
        if firstInstall {
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
            try fm.copyItem(at: slot, to: backup)
        }

        // 3. Swap: replace the aerial file in one atomic step.
        _ = try fm.replaceItemAt(slot, withItemAt: converted)

        // 4. Give the lock screen a matching still so it never flashes a
        //    stale image (or black) before playback starts.
        await refreshPoster(from: videoURL)

        // 5. Make the system pick up the new file — but never mid-lock, that
        //    blanks the running animation; the unlock reset covers it then.
        if !LockScreenRefresher.shared.isCurrentlyLocked {
            reloadWallpaperRenderer()
        }
        return firstInstall
    }

    /// Writes the video's first frame as the lock screen still
    /// (`/Library/Caches/Desktop Pictures/<user-UUID>/lockscreen.png`).
    func refreshPoster(from videoURL: URL) async {
        guard let uuid = Self.userGeneratedUID() else { return }
        let posterDir = URL(fileURLWithPath: "/Library/Caches/Desktop Pictures/\(uuid)")
        guard fm.fileExists(atPath: posterDir.path) else { return }

        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: videoURL))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        guard let (frame, _) = try? await generator.image(at: .zero),
              let png = NSBitmapImageRep(cgImage: frame).representation(using: .png, properties: [:])
        else { return }

        let poster = posterDir.appendingPathComponent("lockscreen.png")
        let tmp = posterDir.appendingPathComponent("lockscreen.tmp.png")
        try? png.write(to: tmp)
        _ = try? fm.replaceItemAt(poster, withItemAt: tmp)
    }

    /// The per-user directory ID macOS uses for the lock screen cache.
    private static func userGeneratedUID() -> String? {
        let dscl = Process()
        dscl.executableURL = URL(fileURLWithPath: "/usr/bin/dscl")
        dscl.arguments = [".", "-read", "/Users/\(NSUserName())", "GeneratedUID"]
        let pipe = Pipe()
        dscl.standardOutput = pipe
        try? dscl.run()
        dscl.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.split(separator: " ").last.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Puts Apple's original video back and reloads.
    func restoreOriginal() throws {
        let slot = try findSlot()
        let backup = backupURL(for: slot)
        guard fm.fileExists(atPath: backup.path) else { return }
        // Copy (not move) so the backup survives for future installs.
        let tmp = slot.deletingLastPathComponent().appendingPathComponent("animated-restore.tmp.mov")
        try? fm.removeItem(at: tmp)
        try fm.copyItem(at: backup, to: tmp)
        _ = try fm.replaceItemAt(slot, withItemAt: tmp)
        reloadWallpaperRenderer()
    }

    /// True while our video (not Apple's) sits in the slot.
    var isInstalled: Bool {
        guard let slot = try? findSlot() else { return false }
        return fm.fileExists(atPath: backupURL(for: slot).path)
    }

    private func exportSlotVideo(source: URL, preset: String) async throws -> URL {
        let asset = AVURLAsset(url: source)

        // Aerial files are video-only — the system renderer chokes on audio
        // tracks, so build a composition containing just the video.
        let composition = AVMutableComposition()
        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw NSError(domain: "Animated", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "This file has no video track. Try an MP4 or MOV file."
            ])
        }
        let duration = try await asset.load(.duration)
        guard duration.seconds > 0.1 else {
            throw NSError(domain: "Animated", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "This video is too short to use."
            ])
        }
        // Apple's aerials run ~5 minutes and the renderer misbehaves once a
        // video ends (black screen on the next lock). Tile short clips up to
        // ~3 minutes so the end is never reached in practice.
        let target = CMTime(seconds: 180, preferredTimescale: 600)
        var cursor = CMTime.zero
        repeat {
            try videoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration), of: sourceVideo, at: cursor
            )
            cursor = cursor + duration
        } while cursor < target
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: preset
        ) else {
            throw NSError(domain: "Animated", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "This video can't be converted. Try an MP4 or MOV file."
            ])
        }
        // moov atom up front, like Apple's own aerial files.
        session.shouldOptimizeForNetworkUse = true
        let out = fm.temporaryDirectory.appendingPathComponent("animated-lockscreen-\(UUID().uuidString).mov")
        let progressTask = Task {
            for await state in session.states(updateInterval: 1) {
                if case .exporting(let progress) = state {
                    await InstallStatus.set(
                        "Converting for lock screen… \(Int(progress.fractionCompleted * 100)) %"
                    )
                }
            }
        }
        defer { progressTask.cancel() }
        try await session.export(to: out, as: .mov)
        return out
    }

    /// Unlock-time reset: restart only the (wedge-prone) renderer extension.
    /// Leaving WallpaperAgent alive makes the restart much faster, which
    /// matters when the user relocks within a second or two.
    func resetRenderer() {
        kill("WallpaperAerialsExtension")
    }

    /// Install-time reset: full restart of both processes so the new file is
    /// picked up everywhere (desktop still, settings thumbnail, lock screen).
    private func reloadWallpaperRenderer() {
        kill("WallpaperAerialsExtension")
        kill("WallpaperAgent")
    }

    private func kill(_ processName: String) {
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        kill.arguments = [processName]
        try? kill.run()
        kill.waitUntilExit()
    }

    /// Opens System Settings on the Wallpaper pane for the one-time selection.
    static func openWallpaperSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
