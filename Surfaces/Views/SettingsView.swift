import AuthenticationServices
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            WidgetSettings().tabItem { Label("Widgets", systemImage: "rectangle.on.rectangle") }
            WallpaperSettings().tabItem { Label("Wallpaper", systemImage: "photo") }
        }
        .frame(width: 520)
        .padding()
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var server = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Account") {
                LabeledContent("Server", value: OAuthConfig.origin(model.settings.serverURL))
                if model.signedIn {
                    LabeledContent("Status", value: "Signed in")
                    Button("Sign Out") { Task { await model.signOut() } }
                } else {
                    LabeledContent("Status", value: "Signed out")
                    Button("Sign In…") { Task { await model.signIn(using: webAuthenticationSession) } }
                        .disabled(model.signingIn)
                }
                Text("Surfaces for Mac can see your screens and their images, and nothing else. Manage screens on your account page.")
                    .font(.caption).foregroundStyle(.secondary)
                Link("Open your account page", destination: model.settings.serverURL)
            }
            Section("Updates") {
                Picker("Check for new images", selection: $model.settings.refreshSeconds) {
                    ForEach(AppSettings.refreshChoices, id: \.self) { seconds in
                        Text(seconds < 60 ? "Every \(Int(seconds)) seconds" : seconds == 60 ? "Every minute" : "Every \(Int(seconds / 60)) minutes")
                            .tag(seconds)
                    }
                }
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            }
            Section("Advanced") {
                HStack {
                    TextField("Server URL", text: $server, prompt: Text(AppSettings.defaultServer.absoluteString))
                    Button("Use") {
                        if let url = URL(string: server.trimmingCharacters(in: .whitespaces)), url.scheme?.hasPrefix("http") == true, url.host != nil {
                            model.settings.serverURL = url
                        }
                    }
                }
                Text("Only change this to use your own Surfaces server. You'll need to sign in again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { server = model.settings.serverURL.absoluteString }
    }
}

private struct WidgetSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            if model.settings.widgets.isEmpty {
                Text("No widgets yet. Add one from the menu bar, or below.").foregroundStyle(.secondary)
            }
            ForEach($model.settings.widgets) { $widget in
                Section(widget.screenID) {
                    WidgetEditor(widget: $widget)
                }
            }
            Section {
                Toggle("Arrange widgets on the desktop", isOn: $model.arranging)
                Menu("Add Widget") {
                    ForEach(model.screens) { screen in
                        Button("\(screen.id)  (\(screen.sizeLabel))") { model.addWidget(for: screen) }
                    }
                }
                .disabled(model.screens.isEmpty)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 420)
    }
}

/// Edits one widget: which screen, exact size, and how it looks.
private struct WidgetEditor: View {
    @Binding var widget: WidgetConfig
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker("Screen", selection: $widget.screenID) {
            ForEach(model.screens) { Text($0.id).tag($0.id) }
            if model.screen(widget.screenID) == nil { Text(widget.screenID).tag(widget.screenID) }
        }
        LabeledContent("Size") {
            HStack {
                TextField("Width", value: sizeBinding(\.width), format: .number.precision(.fractionLength(0)))
                    .frame(width: 70)
                Text("×")
                TextField("Height", value: sizeBinding(\.height), format: .number.precision(.fractionLength(0)))
                    .frame(width: 70)
                Text("points").foregroundStyle(.secondary)
                if let screen = model.screen(widget.screenID) {
                    Button("Match screen shape") {
                        widget.frame.size.height = (widget.width / screen.aspectRatio).rounded()
                        // Keep the top edge in place.
                        widget.y = widget.y + widget.height - widget.frame.height
                    }
                    .help("Keep the width and set the height to the screen's aspect ratio (\(screen.sizeLabel))")
                }
            }
        }
        if let screen = model.screen(widget.screenID), abs(screen.aspectRatio - widget.width / widget.height) > 0.02 {
            Text("The screen renders at \(screen.sizeLabel). For the sharpest image, give the widget the same shape, or change the screen's size on your account page.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Picker("Image", selection: $widget.fit) {
            ForEach(ImageFit.allCases) { Text($0.label).tag($0) }
        }
        LabeledContent("Corner radius") {
            Slider(value: $widget.cornerRadius, in: 0...40)
        }
        LabeledContent("Opacity") {
            Slider(value: $widget.opacity, in: 0.2...1)
        }
        Toggle("Shadow", isOn: $widget.shadow)
        Button("Remove Widget", role: .destructive) { model.removeWidget(widget.id) }
    }

    /// Edits width or height while keeping the widget's top-left corner in place.
    private func sizeBinding(_ key: WritableKeyPath<WidgetConfig, Double>) -> Binding<Double> {
        Binding(
            get: { widget[keyPath: key] },
            set: { value in
                let top = widget.y + widget.height
                var updated = widget
                var frame = updated.frame
                if key == \WidgetConfig.width { frame.size.width = value } else { frame.size.height = value }
                updated.frame = frame
                updated.y = top - updated.height
                widget = updated
            }
        )
    }
}

private struct WallpaperSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Picker("Show", selection: Binding(get: { model.settings.wallpaper.screenID }, set: { model.setWallpaper(screenID: $0) })) {
                Text("Off (your usual wallpaper)").tag(String?.none)
                ForEach(model.screens) { Text("\($0.id)  (\($0.sizeLabel))").tag(String?.some($0.id)) }
            }
            Picker("On", selection: Binding(
                get: { model.settings.wallpaper.displayName },
                set: { model.settings.wallpaper.displayName = $0 }
            )) {
                Text("All displays").tag(String?.none)
                ForEach(WallpaperManager.displayNames(), id: \.self) { Text($0).tag(String?.some($0)) }
            }
            Picker("Image", selection: Binding(get: { model.settings.wallpaper.fit }, set: { model.settings.wallpaper.fit = $0 })) {
                ForEach(ImageFit.allCases) { Text($0.label).tag($0) }
            }
            Text("For a sharp wallpaper, make the screen the size of your display: on your account page, choose the MacBook preset that matches, or your display's resolution. When you turn this off, your previous wallpaper comes back.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}
