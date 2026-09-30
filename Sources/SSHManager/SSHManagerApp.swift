import SwiftUI

@main
struct SSHManagerApp: App {
    @StateObject private var appModel = AppModel()
    @StateObject private var settings = SettingsStore()
    @StateObject private var runner = ForwardRunner()

    var body: some Scene {
        WindowGroup("SSH Manager") {
            ContentView()
                .environmentObject(appModel)
                .environmentObject(settings)
                .environmentObject(runner)
                .frame(minWidth: 960, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新建主机") {
                    NotificationCenter.default.post(name: .sshmNewHost, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
                .frame(width: 440, height: 200)
        }
    }
}

extension Notification.Name {
    static let sshmNewHost = Notification.Name("com.sshmanager.newHost")
}
