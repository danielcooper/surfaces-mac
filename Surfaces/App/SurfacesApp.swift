import SwiftUI

@main
struct SurfacesApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environment(model)
        } label: {
            Image(systemName: "rectangle.on.rectangle")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
