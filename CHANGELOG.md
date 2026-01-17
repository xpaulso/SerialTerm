# Changelog

All notable changes to SerialTerm will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.3.0] - 2026-01-16

### Added
- Scrollback buffer with up to 1000 lines of history
- Scroll navigation to view terminal history
- Auto-scroll to bottom on new output

### Changed
- Updated Zig build for compatibility with Zig 0.14

## [0.2.1] - 2026-01-14

### Added
- Dynamic terminal sizing with visual size indicator
- Live preview for appearance settings

### Fixed
- Settings crash caused by AppState dependency

## [0.2.0] - 2026-01-14

### Added
- Custom app icon with serial port connector design
- Session management features
  - Session logs
  - Connection profiles
  - History view

## [0.1.0] - 2026-01-13

### Added
- Initial release
- Native serial port support via macOS IOKit
- File transfer protocols (XMODEM, YMODEM, ZMODEM) with auto-start detection
- Modern SwiftUI terminal interface
- Command mode with picocom-style escape sequences (Ctrl+A)
- Hot-plug detection for serial devices
- Customizable appearance with preset themes (Dracula, Monokai, Solarized, etc.)
- Session logging with custom or auto-generated names

[0.3.0]: https://github.com/xpaulso/SerialTerm/releases/tag/v0.3.0
[0.2.1]: https://github.com/xpaulso/SerialTerm/releases/tag/v0.2.1
[0.2.0]: https://github.com/xpaulso/SerialTerm/releases/tag/v0.2.0
[0.1.0]: https://github.com/xpaulso/SerialTerm/releases/tag/v0.1.0
