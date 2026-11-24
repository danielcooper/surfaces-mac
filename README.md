# Surfaces for Mac

Your [Surfaces](https://surfaces.coops.dev) screens on your Mac's desktop.

Surfaces lets an agent build a UI (a *surface*) and render it to *screens*. This
menu bar app signs in to your Surfaces account and shows those screens on your
desktop, keeping them up to date as your agent changes them.

![Surfaces icon](Surfaces/Media.xcassets/AppIcon.appiconset/icon_256.png)

## Features

- **Desktop widgets of any size.** Put any screen on your desktop in a borderless
  window, as many as you like. Set an exact size in Settings, or turn on
  **Arrange widgets** and drag them around and resize them from the corner. They sit
  behind your windows and desktop icons, ignore clicks, and stay put on every Space.
  Corner radius, opacity, shadow, and fit or fill are per widget.
- **Wallpaper.** Make a screen your desktop picture, on every display or just one.
  It updates whenever the screen changes. Turn it off and your previous wallpaper
  comes back.
- **Stays current.** Checks the screens you use every minute (or every 30 seconds
  to 15 minutes), after waking from sleep, and on demand. Unchanged images cost
  almost nothing: the server answers `304 Not Modified`. The latest images are
  cached on disk, so everything appears straight away at login.
- **Read-only sign-in.** The app signs in with OAuth (the system's web sign-in
  sheet) and can only see your screens and their images. It never sees your
  password. Its refresh token is kept in your Keychain, and signing out revokes it.

Requires macOS 15 or later.

## Download

Get the latest `Surfaces-<version>.zip` from Releases, unzip it and move
**Surfaces.app** to Applications.

### Opening it the first time

Builds aren't signed with an Apple Developer ID or notarised, so macOS blocks the
first launch:

1. Open Surfaces. macOS says it can't verify the developer; click **Done**.
2. Open **System Settings → Privacy & Security**, scroll down, and click **Open
   Anyway** next to the message about Surfaces.
3. Confirm with your password. After that it opens normally.

Alternatively, in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Surfaces.app
```

Because builds aren't signed with a fixed identity, macOS may ask again for access
to the Keychain item after an update. Click **Always Allow**.

## Using it

- Click the **Surfaces** icon in the menu bar and **Sign in to Surfaces…**.
  Approve "Surfaces for Mac" on the page that opens.
- **Widgets → Add** puts a screen on your desktop. Toggle **Arrange widgets** to
  move and resize them; turn it off when you're done.
- **Settings → Widgets** sets each widget's exact size in points, how the image
  fits, corner radius, opacity and shadow. **Match screen shape** keeps the width
  and sets the height to the screen's aspect ratio.
- **Wallpaper** picks a screen for your desktop picture. In **Settings →
  Wallpaper** choose which displays and whether the image fits or fills.
- For the sharpest result, make the screen the same shape and size as where it's
  shown. On your account page, the MacBook presets match the built-in displays.

On recent macOS the desktop picture is per Space; Surfaces applies the wallpaper to
each Space as you switch to it.

## Building

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen)
from `project.yml`, like Wreckingball and RLG. See Wreckingball's build notes.

```bash
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Surfaces.xcodeproj -scheme Surfaces -configuration Debug -derivedDataPath build -allowProvisioningUpdates build
```

Tests: replace `build` with `test`. `ServerIntegrationTests` also runs against a
real Surfaces server when given one (see the comment in that file).

App icon: `swiftc -O Tools/MakeIcon.swift -o /tmp/makeicon && /tmp/makeicon Surfaces/Media.xcassets/AppIcon.appiconset`

Logs: `log show --last 5m --predicate 'subsystem == "coops.surfaces"'`

Releases: bump `MARKETING_VERSION` in `project.yml`, commit, push, then
`git tag vX.Y.Z && git push origin vX.Y.Z`. CI builds, tests and publishes the zip.
