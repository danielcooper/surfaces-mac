# Changelog

Notable changes to Surfaces for Mac. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and version numbers follow [semantic versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-11-24

### Added

- **Sign in to Surfaces** with OAuth (authorization code + PKCE) through the system's web
  sign-in sheet, with read-only access to your screens. The refresh token is kept in the
  Keychain and rotates on every use; signing out revokes it.
- **Desktop widgets:** any number of borderless windows, each showing one screen at any size.
  Arrange mode to drag and resize them; exact sizes, fit or fill, corner radius, opacity and
  shadow in Settings. They sit behind windows and desktop icons on every Space.
- **Wallpaper:** a screen as the desktop picture on every display or one, updated when the
  screen changes and applied to each Space; the previous wallpaper comes back when turned off.
- Checks for new images every 30 seconds to 15 minutes using ETags, after waking, and on
  demand, with an on-disk cache for instant start-up. Launch at login.
