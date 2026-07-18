import SwiftUI
import ServiceManagement

@main
struct AnimatedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var stats = ResourceMonitor.shared
    @ObservedObject private var install = InstallStatus.shared

    var body: some Scene {
        MenuBarExtra("Animated", systemImage: "sparkle") {
            menuContent
        }
    }

    @ViewBuilder
    private var menuContent: some View {
        if let progress = install.text {
            Label(progress, systemImage: "lock.rectangle")
            Divider()
        }
        Label(stats.cpuText, systemImage: "cpu")
        Label(stats.memoryText, systemImage: "memorychip")
        Label(stats.cacheText, systemImage: "internaldrive")
        Divider()
        Button {
            AppDelegate.chooseVideo()
        } label: {
            Label("Choose Video…", systemImage: "film")
        }
        Divider()
        Button {
            AppDelegate.useAppleBackground()
        } label: {
            Label("Use Apple Background", systemImage: "apple.logo")
        }
        Divider()
        Button {
            WallpaperController.shared.pause()
        } label: {
            Label("Pause", systemImage: "pause.fill")
        }
        Button {
            WallpaperController.shared.resume()
        } label: {
            Label("Resume", systemImage: "play.fill")
        }
        Divider()
        Toggle(isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enable in
                if enable {
                    try? SMAppService.mainApp.register()
                } else {
                    try? SMAppService.mainApp.unregister()
                }
            }
        )) {
            Label("Start at Login", systemImage: "sunrise")
        }
        Divider()
        Button {
            NSApp.terminate(nil)
        } label: {
            Label("Quit", systemImage: "power")
        }
        .keyboardShortcut("q")
    }
}
