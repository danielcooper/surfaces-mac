import AuthenticationServices
import SwiftUI

/// The window that opens from the menu bar icon.
struct MenuView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Surfaces").font(.headline)
                Spacer()
                Text(OAuthConfig.origin(model.settings.serverURL).replacingOccurrences(of: "https://", with: ""))
                    .font(.caption).foregroundStyle(.secondary)
            }

            if !model.signedIn {
                Text("Sign in to show your Surfaces screens as desktop widgets or as your wallpaper.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await model.signIn(using: webAuthenticationSession) }
                } label: {
                    Label("Sign in to Surfaces…", systemImage: "person.crop.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.signingIn)
            } else {
                widgetSection
                Divider()
                wallpaperSection
            }

            if let problem = model.problem {
                Text(problem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                if let updated = model.lastUpdated {
                    Text("Updated \(updated, style: .relative) ago").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Check for new images now")
                .disabled(!model.signedIn)
                Button {
                    NSApp.activate()
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit Surfaces")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 320)
    }

    private var widgetSection: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Widgets").font(.subheadline.bold())
                Spacer()
                Menu {
                    ForEach(model.screens) { screen in
                        Button("\(screen.id)  (\(screen.sizeLabel))") { model.addWidget(for: screen) }
                    }
                    if model.screens.isEmpty { Text("No screens yet") }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            if model.settings.widgets.isEmpty {
                Text("Add a widget to put a screen on your desktop.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(model.settings.widgets) { widget in
                    HStack {
                        Image(systemName: "rectangle.inset.filled")
                        Text(widget.screenID)
                        Spacer()
                        Text("\(Int(widget.width))×\(Int(widget.height))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Button {
                            model.removeWidget(widget.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .help("Remove this widget")
                    }
                }
                Toggle("Arrange widgets (drag to move, corner to resize)", isOn: $model.arranging)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
    }

    private var wallpaperSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wallpaper").font(.subheadline.bold())
            Picker("Show", selection: Binding(
                get: { model.settings.wallpaper.screenID },
                set: { model.setWallpaper(screenID: $0) }
            )) {
                Text("Off").tag(String?.none)
                ForEach(model.screens) { screen in
                    Text("\(screen.id)  (\(screen.sizeLabel))").tag(String?.some(screen.id))
                }
            }
            .labelsHidden()
        }
    }
}
