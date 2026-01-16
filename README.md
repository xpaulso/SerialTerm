# SerialTerm

A modern macOS terminal application with native serial port support, inspired by [Ghostty](https://github.com/ghostty-org/ghostty).

## Features

- **Native Serial Port Support**: Direct connection to serial devices via macOS IOKit
- **File Transfer Protocols**: XMODEM, YMODEM, and ZMODEM with auto-start detection
- **Modern UI**: Minimal, terminal-focused SwiftUI interface with dynamic sizing indicator
- **Command Mode**: picocom-style escape sequences (Ctrl+A) for in-session commands
- **Hot-plug Detection**: Automatic detection of connected/disconnected serial devices
- **Customizable Appearance**: Fonts, colors, and preset themes (Dracula, Monokai, Solarized, etc.) with live preview
- **Session Management**: History tracking, saved connection profiles, and session logging
- **Session Logging**: Record sessions with custom or auto-generated names
- **Dynamic Terminal Sizing**: Automatic terminal resize with visual size indicator

## Installation

### Download

Download the latest release from the [Releases page](https://github.com/xpaulso/SerialTerm/releases):

- [SerialTerm v0.2.1](https://github.com/xpaulso/SerialTerm/releases/tag/v0.2.1) - Latest

Open the DMG file and drag SerialTerm to your Applications folder.

## Requirements (for building from source)

- macOS 14.0 or later
- Zig 0.13.0 or later
- Xcode 15.0 or later

## Building

### Quick Start

```bash
# Clone the repository
git clone https://github.com/xpaulso/SerialTerm.git
cd SerialTerm

# Build the application
make build

# Run the application
make run
```

### Build Targets

```bash
make help          # Show all available targets
make build         # Build the complete application
make build-zig     # Build only the Zig library
make build-swift   # Build only the Swift app
make test          # Run all tests
make clean         # Clean build artifacts
make package       # Create DMG installer
make install       # Install to /Applications
```

## Usage

### Connecting to a Serial Port

1. Launch SerialTerm
2. Click "Connect" or use the Serial menu
3. Select your serial port from the list
4. Configure baud rate and other settings
5. Click "Connect"

### Command Mode (Ctrl+A)

Press `Ctrl+A` to enter command mode, then:

| Key | Action |
|-----|--------|
| `Q` | Quit/Disconnect |
| `B` | Send Break |
| `D` | Toggle DTR |
| `R` | Toggle RTS |
| `X` | Upload via XMODEM |
| `Y` | Upload via YMODEM |
| `Z` | Upload via ZMODEM |
| `E` | Toggle Local Echo |
| `C` | Clear Screen |
| `S` | Port Settings |
| `H` or `?` | Show Help |
| `Ctrl+A` | Send literal Ctrl+A |

### File Transfers

#### Sending Files
1. Press `Ctrl+A`, then `Z` (for ZMODEM) or use Transfer menu
2. Select the file to send
3. The transfer will begin automatically

#### Receiving Files
- **ZMODEM**: Auto-detects incoming transfers
- **XMODEM/YMODEM**: Press `Ctrl+A`, then `R` to start receiving

## Configuration

### Serial Port Settings

| Setting | Options |
|---------|---------|
| Baud Rate | 300 - 921600 |
| Data Bits | 5, 6, 7, 8 |
| Parity | None, Odd, Even |
| Stop Bits | 1, 2 |
| Flow Control | None, RTS/CTS, XON/XOFF |

### Presets

- **Default**: 115200 8N1
- **Arduino**: 9600 8N1
- **Cisco Console**: 9600 8N1
- **High Speed**: 921600 8N1 with hardware flow control

## Architecture

```
SerialTerm/
├── src/                    # Zig source code
│   ├── serial/            # Serial port abstraction
│   │   ├── Port.zig       # Port I/O operations
│   │   ├── Config.zig     # Configuration types
│   │   └── c_api.zig      # C API for Swift bridging
│   └── transfer/          # File transfer protocols
│       ├── xmodem.zig     # XMODEM implementation
│       ├── ymodem.zig     # YMODEM implementation
│       ├── zmodem.zig     # ZMODEM implementation
│       └── common.zig     # Shared utilities (CRC, etc.)
├── include/               # C headers for bridging
├── macos/                 # Swift/SwiftUI application
│   └── SerialTerm/
│       ├── App/           # Application entry and state
│       ├── Features/      # Feature modules
│       │   ├── Terminal/  # Terminal view
│       │   ├── SerialPort/# Port management
│       │   ├── Transfer/  # File transfer UI
│       │   └── CommandMode/# Escape sequences
│       └── Ghostty/       # Serial connection wrapper
└── tests/                 # Test files
```

## Acknowledgments

- [Ghostty](https://github.com/ghostty-org/ghostty) - Inspiration for architecture and UI design
- [picocom](https://github.com/npat-efault/picocom) - Command mode escape sequence design
- [lrzsz](https://github.com/tobyzxj/lrzsz) - Reference for ZMODEM implementation

## License

MIT License - See LICENSE file for details.
