# Changelog

Notable changes to Surfaces for Mac. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and version numbers follow [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-11-25

First release: sign in to your Surfaces account from the menu bar and put your screens on the
desktop, as widgets of any size or as the wallpaper, kept up to date as your agent changes them.

### Added

- **Sign in to Surfaces** from the menu bar, through the system's web sign-in sheet (OAuth
  authorization code with PKCE). The app can only see your screens and their images, never your
  password. Its refresh token is kept in the Keychain and rotates on every use; signing out
  revokes it on the server.
- **Desktop widgets of any size.** Any number of borderless windows, each showing one screen.
  **Arrange widgets** lets you drag them into place and resize them from the corner; Settings
  sets an exact width and height, fit or fill, corner radius, opacity and shadow, and can match a
  widget to its screen's shape. Otherwise they sit behind your windows and desktop icons, ignore
  clicks and stay put on every Space.
- **Wallpaper.** Make a screen your desktop picture on every display or just one. It changes when
  the screen does and is applied to each Space as you switch to it. Turning it off brings back
  your previous wallpaper.
- **Stays current.** Checks the screens in use every minute (30 seconds to 15 minutes), after
  waking from sleep, and on demand. Unchanged images cost almost nothing (the server answers
  `304 Not Modified`), and the latest images are cached on disk so everything appears straight
  away at login.
- **Launch at login**, and a server setting for using your own Surfaces server.

[0.1.0]: https://github.com/danielcooper/surfaces-mac/releases/tag/v0.1.0
