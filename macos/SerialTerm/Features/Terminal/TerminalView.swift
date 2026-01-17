import SwiftUI
import AppKit

/// A terminal view that displays serial output and handles keyboard input
struct TerminalView: NSViewRepresentable {
    @Binding var output: [UInt8]
    var onInput: (Data) -> Void
    var onSizeChange: ((Int, Int) -> Void)?
    @ObservedObject var appearanceManager = AppearanceManager.shared

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput)
    }

    func makeNSView(context: Context) -> TerminalNSView {
        let view = TerminalNSView()
        view.onInput = onInput
        view.onSizeChange = onSizeChange
        view.applyAppearance(appearanceManager.settings)
        context.coordinator.setupKeyMonitor(for: view)

        // Ensure the view becomes first responder when it appears
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
            view.window?.makeKey()
        }
        return view
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {
        nsView.processOutput(output)
        nsView.applyAppearance(appearanceManager.settings)
        nsView.onSizeChange = onSizeChange
        context.coordinator.onInput = onInput
    }

    class Coordinator {
        var onInput: (Data) -> Void
        var keyMonitor: Any?
        weak var terminalView: TerminalNSView?

        init(onInput: @escaping (Data) -> Void) {
            self.onInput = onInput
        }

        func setupKeyMonitor(for view: TerminalNSView) {
            self.terminalView = view

            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self = self else {
                    return event
                }

                // Check if we have a valid terminal view and window
                guard let termView = self.terminalView,
                      let window = termView.window else {
                    return event
                }

                // Only handle if this window is key and has no sheet
                guard window.isKeyWindow, window.attachedSheet == nil else {
                    return event
                }

                // Don't intercept if a text field has focus
                if let responder = window.firstResponder,
                   responder is NSTextField || responder is NSTextView || responder is NSSearchField {
                    return event
                }

                if self.handleKeyEvent(event) {
                    return nil
                }
                return event
            }
        }

        func handleKeyEvent(_ event: NSEvent) -> Bool {
            var data: Data?

            if event.modifierFlags.contains(.control),
               let characters = event.characters,
               let char = characters.first,
               let asciiValue = char.asciiValue,
               asciiValue >= 0x40 && asciiValue <= 0x7F {
                data = Data([asciiValue & 0x1F])
            }

            if data == nil {
                switch event.keyCode {
                case 36: data = Data([0x0D])
                case 51: data = Data([0x7F])
                case 53: data = Data([0x1B])
                case 123: data = Data([0x1B, 0x5B, 0x44])
                case 124: data = Data([0x1B, 0x5B, 0x43])
                case 125: data = Data([0x1B, 0x5B, 0x42])
                case 126: data = Data([0x1B, 0x5B, 0x41])
                case 48: data = Data([0x09])
                default:
                    if let characters = event.characters,
                       let charData = characters.data(using: .utf8) {
                        data = charData
                    }
                }
            }

            if let data = data {
                onInput(data)
                return true
            }
            return false
        }

        deinit {
            if let monitor = keyMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

// MARK: - ANSI Colors

struct ANSIColors {
    // Standard 16 colors
    static let black = NSColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let red = NSColor(red: 0.8, green: 0, blue: 0, alpha: 1)
    static let green = NSColor(red: 0, green: 0.8, blue: 0, alpha: 1)
    static let yellow = NSColor(red: 0.8, green: 0.8, blue: 0, alpha: 1)
    static let blue = NSColor(red: 0, green: 0, blue: 0.8, alpha: 1)
    static let magenta = NSColor(red: 0.8, green: 0, blue: 0.8, alpha: 1)
    static let cyan = NSColor(red: 0, green: 0.8, blue: 0.8, alpha: 1)
    static let white = NSColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 1)

    // Bright colors
    static let brightBlack = NSColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
    static let brightRed = NSColor(red: 1, green: 0, blue: 0, alpha: 1)
    static let brightGreen = NSColor(red: 0, green: 1, blue: 0, alpha: 1)
    static let brightYellow = NSColor(red: 1, green: 1, blue: 0, alpha: 1)
    static let brightBlue = NSColor(red: 0.4, green: 0.4, blue: 1, alpha: 1)
    static let brightMagenta = NSColor(red: 1, green: 0, blue: 1, alpha: 1)
    static let brightCyan = NSColor(red: 0, green: 1, blue: 1, alpha: 1)
    static let brightWhite = NSColor(red: 1, green: 1, blue: 1, alpha: 1)

    static let standardColors: [NSColor] = [
        black, red, green, yellow, blue, magenta, cyan, white,
        brightBlack, brightRed, brightGreen, brightYellow, brightBlue, brightMagenta, brightCyan, brightWhite
    ]

    static func color256(_ index: Int) -> NSColor {
        if index < 16 {
            return standardColors[index]
        } else if index < 232 {
            // 216 color cube (6x6x6)
            let i = index - 16
            let r = CGFloat((i / 36) % 6) / 5.0
            let g = CGFloat((i / 6) % 6) / 5.0
            let b = CGFloat(i % 6) / 5.0
            return NSColor(red: r, green: g, blue: b, alpha: 1)
        } else {
            // Grayscale (24 shades)
            let gray = CGFloat(index - 232) / 23.0
            return NSColor(white: gray, alpha: 1)
        }
    }
}

// MARK: - Terminal Cell

struct TerminalCell {
    var character: Character = " "
    var foreground: NSColor? = nil  // nil means use terminal default
    var background: NSColor? = nil  // nil means use terminal default (transparent)
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var inverse: Bool = false
    var dim: Bool = false
}

// MARK: - Terminal Buffer

class TerminalBuffer {
    var rows: Int
    var cols: Int
    var cursorRow: Int = 0
    var cursorCol: Int = 0
    var grid: [[TerminalCell]]
    var scrollback: [[TerminalCell]] = []
    let maxScrollback = 1000

    // Scroll region
    var scrollTop: Int = 0
    var scrollBottom: Int

    // Current attributes (nil = use terminal default)
    var currentForeground: NSColor? = nil
    var currentBackground: NSColor? = nil
    var currentBold = false
    var currentItalic = false
    var currentUnderline = false
    var currentInverse = false
    var currentDim = false

    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
        self.scrollBottom = rows - 1
        self.grid = Array(repeating: Array(repeating: TerminalCell(), count: cols), count: rows)
    }

    func resize(newRows: Int, newCols: Int) {
        var newGrid = Array(repeating: Array(repeating: TerminalCell(), count: newCols), count: newRows)
        for row in 0..<min(rows, newRows) {
            for col in 0..<min(cols, newCols) {
                newGrid[row][col] = grid[row][col]
            }
        }
        rows = newRows
        cols = newCols
        grid = newGrid
        cursorRow = min(cursorRow, rows - 1)
        cursorCol = min(cursorCol, cols - 1)
        scrollTop = 0
        scrollBottom = rows - 1
    }

    func putChar(_ char: Character) {
        if cursorCol >= cols {
            cursorCol = 0
            newLine()
        }
        var cell = TerminalCell()
        cell.character = char
        cell.foreground = currentForeground
        cell.background = currentBackground
        cell.bold = currentBold
        cell.italic = currentItalic
        cell.underline = currentUnderline
        cell.inverse = currentInverse
        cell.dim = currentDim
        grid[cursorRow][cursorCol] = cell
        cursorCol += 1
    }

    func newLine() {
        if cursorRow == scrollBottom {
            scrollUp()
        } else if cursorRow < rows - 1 {
            cursorRow += 1
        }
    }

    func carriageReturn() {
        cursorCol = 0
    }

    func scrollUp() {
        if scrollback.count >= maxScrollback {
            scrollback.removeFirst()
        }
        scrollback.append(grid[scrollTop])

        for i in scrollTop..<scrollBottom {
            grid[i] = grid[i + 1]
        }
        grid[scrollBottom] = Array(repeating: TerminalCell(), count: cols)
    }

    func scrollDown() {
        for i in stride(from: scrollBottom, to: scrollTop, by: -1) {
            grid[i] = grid[i - 1]
        }
        grid[scrollTop] = Array(repeating: TerminalCell(), count: cols)
    }

    func setScrollRegion(top: Int, bottom: Int) {
        scrollTop = max(0, min(top, rows - 1))
        scrollBottom = max(scrollTop, min(bottom, rows - 1))
    }

    func moveCursor(row: Int, col: Int) {
        cursorRow = max(0, min(row, rows - 1))
        cursorCol = max(0, min(col, cols - 1))
    }

    func moveCursorUp(_ n: Int = 1) {
        cursorRow = max(scrollTop, cursorRow - n)
    }

    func moveCursorDown(_ n: Int = 1) {
        cursorRow = min(scrollBottom, cursorRow + n)
    }

    func moveCursorForward(_ n: Int = 1) {
        cursorCol = min(cols - 1, cursorCol + n)
    }

    func moveCursorBackward(_ n: Int = 1) {
        cursorCol = max(0, cursorCol - n)
    }

    func clearScreen(mode: Int = 2) {
        switch mode {
        case 0:
            clearToEndOfLine()
            for row in (cursorRow + 1)..<rows {
                grid[row] = Array(repeating: TerminalCell(), count: cols)
            }
        case 1:
            for col in 0..<cursorCol {
                grid[cursorRow][col] = TerminalCell()
            }
            for row in 0..<cursorRow {
                grid[row] = Array(repeating: TerminalCell(), count: cols)
            }
        case 2, 3:
            grid = Array(repeating: Array(repeating: TerminalCell(), count: cols), count: rows)
            if mode == 3 {
                scrollback.removeAll()
            }
        default:
            break
        }
    }

    func clearLine(mode: Int = 0) {
        switch mode {
        case 0:
            clearToEndOfLine()
        case 1:
            for col in 0...cursorCol {
                grid[cursorRow][col] = TerminalCell()
            }
        case 2:
            grid[cursorRow] = Array(repeating: TerminalCell(), count: cols)
        default:
            break
        }
    }

    func clearToEndOfLine() {
        for col in cursorCol..<cols {
            grid[cursorRow][col] = TerminalCell()
        }
    }

    func backspace() {
        if cursorCol > 0 {
            cursorCol -= 1
        }
    }

    func tab() {
        let tabStop = ((cursorCol / 8) + 1) * 8
        cursorCol = min(tabStop, cols - 1)
    }

    func insertLines(_ n: Int) {
        let count = min(n, scrollBottom - cursorRow + 1)
        for _ in 0..<count {
            grid.remove(at: scrollBottom)
            grid.insert(Array(repeating: TerminalCell(), count: cols), at: cursorRow)
        }
    }

    func deleteLines(_ n: Int) {
        let count = min(n, scrollBottom - cursorRow + 1)
        for _ in 0..<count {
            grid.remove(at: cursorRow)
            grid.insert(Array(repeating: TerminalCell(), count: cols), at: scrollBottom)
        }
    }

    func deleteChars(_ n: Int) {
        let count = min(n, cols - cursorCol)
        for _ in 0..<count {
            grid[cursorRow].remove(at: cursorCol)
            grid[cursorRow].append(TerminalCell())
        }
    }

    func insertChars(_ n: Int) {
        let count = min(n, cols - cursorCol)
        for _ in 0..<count {
            grid[cursorRow].insert(TerminalCell(), at: cursorCol)
            grid[cursorRow].removeLast()
        }
    }

    func resetAttributes() {
        currentForeground = nil  // Use terminal default
        currentBackground = nil  // Use terminal default (transparent)
        currentBold = false
        currentItalic = false
        currentUnderline = false
        currentInverse = false
        currentDim = false
    }
}

// MARK: - Terminal NSView

class TerminalNSView: NSView {
    var onInput: ((Data) -> Void)?
    var onSizeChange: ((Int, Int) -> Void)?

    private var scrollView: NSScrollView!
    private var contentView: TerminalContentView!

    var mainBuffer: TerminalBuffer!
    var altBuffer: TerminalBuffer!
    var currentBuffer: TerminalBuffer!
    var useAltBuffer = false

    private var processedLength = 0
    private var parseState: ParseState = .normal
    private var csiParams: [Int] = []
    private var currentParam = 0
    private var hasParam = false
    private var isPrivateSequence = false
    private var privateMarker: Character = " "

    // Cursor state
    var cursorVisible = true
    private var savedCursorRow = 0
    private var savedCursorCol = 0

    private enum ParseState {
        case normal
        case escape
        case csi
        case osc
    }

    private let defaultRows = 24
    private let defaultCols = 80
    var terminalFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    var foregroundColor = NSColor.white
    var backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
    var cursorColor = NSColor.green

    var charWidth: CGFloat = 7.8
    var charHeight: CGFloat = 16.0

    /// Apply appearance settings from AppearanceManager
    func applyAppearance(_ settings: AppearanceSettings) {
        let newFont = settings.font
        let newForeground = settings.nsForegroundColor
        let newBackground = settings.nsBackgroundColor
        let newCursor = settings.nsCursorColor

        // Check if anything changed
        let fontChanged = terminalFont != newFont
        let colorsChanged = foregroundColor != newForeground ||
                           backgroundColor != newBackground ||
                           cursorColor != newCursor

        if fontChanged || colorsChanged {
            terminalFont = newFont
            foregroundColor = newForeground
            backgroundColor = newBackground
            cursorColor = newCursor

            // Update font metrics if font changed
            if fontChanged {
                let testString = "M" as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: terminalFont]
                let size = testString.size(withAttributes: attrs)
                charWidth = size.width
                charHeight = size.height
            }

            // Update scroll view background
            scrollView?.backgroundColor = backgroundColor

            // Trigger redraw - cell colors are resolved at draw time
            contentView?.setNeedsDisplay(contentView?.bounds ?? .zero)

            // Resize if font changed
            if fontChanged {
                needsLayout = true
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        let testString = "M" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: terminalFont]
        let size = testString.size(withAttributes: attrs)
        charWidth = size.width
        charHeight = size.height

        mainBuffer = TerminalBuffer(rows: defaultRows, cols: defaultCols)
        altBuffer = TerminalBuffer(rows: defaultRows, cols: defaultCols)
        currentBuffer = mainBuffer

        scrollView = NSScrollView(frame: bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor

        contentView = TerminalContentView(frame: scrollView.contentView.bounds)
        contentView.terminalView = self
        contentView.autoresizingMask = [.width, .height]

        scrollView.documentView = contentView
        addSubview(scrollView)

        wantsLayer = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.cornerRadius = 6
    }

    override func updateLayer() {
        super.updateLayer()
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    override var acceptsFirstResponder: Bool { true }

    private var windowObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // Remove old observer
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }

        guard let window = self.window else { return }

        // Observe when window becomes key to restore focus
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.window?.makeFirstResponder(self)
        }

        // Initial focus
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // When clicked, ensure we become first responder
        window?.makeFirstResponder(self)
    }

    override func removeFromSuperview() {
        if let observer = windowObserver {
            NotificationCenter.default.removeObserver(observer)
            windowObserver = nil
        }
        super.removeFromSuperview()
    }

    func processOutput(_ bytes: [UInt8]) {
        guard bytes.count > processedLength else { return }
        let newBytes = Array(bytes[processedLength...])
        processedLength = bytes.count

        for byte in newBytes {
            processByte(byte)
        }
        updateDisplay()
    }

    private func processByte(_ byte: UInt8) {
        switch parseState {
        case .normal: processNormalByte(byte)
        case .escape: processEscapeByte(byte)
        case .csi: processCSIByte(byte)
        case .osc: processOSCByte(byte)
        }
    }

    private func processNormalByte(_ byte: UInt8) {
        switch byte {
        case 0x07: NSSound.beep()
        case 0x08: currentBuffer.backspace()
        case 0x09: currentBuffer.tab()
        case 0x0A: currentBuffer.newLine()
        case 0x0D: currentBuffer.carriageReturn()
        case 0x1B: parseState = .escape
        case 0x20...0x7E: currentBuffer.putChar(Character(UnicodeScalar(byte)))
        case 0x80...0xFF: currentBuffer.putChar(Character(UnicodeScalar(byte)))
        default: break
        }
    }

    private func processEscapeByte(_ byte: UInt8) {
        switch byte {
        case 0x5B: // '['
            parseState = .csi
            csiParams = []
            currentParam = 0
            hasParam = false
            isPrivateSequence = false
            privateMarker = " "
        case 0x5D: parseState = .osc
        case 0x37: // '7' - Save cursor
            savedCursorRow = currentBuffer.cursorRow
            savedCursorCol = currentBuffer.cursorCol
            parseState = .normal
        case 0x38: // '8' - Restore cursor
            currentBuffer.moveCursor(row: savedCursorRow, col: savedCursorCol)
            parseState = .normal
        case 0x44: currentBuffer.newLine(); parseState = .normal
        case 0x45: currentBuffer.carriageReturn(); currentBuffer.newLine(); parseState = .normal
        case 0x4D: // 'M' - Reverse Index
            if currentBuffer.cursorRow == currentBuffer.scrollTop {
                currentBuffer.scrollDown()
            } else {
                currentBuffer.moveCursorUp()
            }
            parseState = .normal
        default: parseState = .normal
        }
    }

    private func processCSIByte(_ byte: UInt8) {
        switch byte {
        case 0x30...0x39:
            currentParam = currentParam * 10 + Int(byte - 0x30)
            hasParam = true
        case 0x3B:
            csiParams.append(hasParam ? currentParam : 0)
            currentParam = 0
            hasParam = false
        case 0x3F, 0x3E, 0x3C, 0x21:
            isPrivateSequence = true
            privateMarker = Character(UnicodeScalar(byte))
        case 0x40...0x7E:
            if hasParam { csiParams.append(currentParam) }
            handleCSICommand(byte)
            parseState = .normal
        default: break
        }
    }

    private func processOSCByte(_ byte: UInt8) {
        if byte == 0x07 || byte == 0x1B {
            parseState = .normal
        }
    }

    private func handleCSICommand(_ cmd: UInt8) {
        let p1 = csiParams.count > 0 ? csiParams[0] : 0
        let p2 = csiParams.count > 1 ? csiParams[1] : 0

        switch cmd {
        case 0x41: currentBuffer.moveCursorUp(max(1, p1))
        case 0x42: currentBuffer.moveCursorDown(max(1, p1))
        case 0x43: currentBuffer.moveCursorForward(max(1, p1))
        case 0x44: currentBuffer.moveCursorBackward(max(1, p1))
        case 0x45: // 'E' - Cursor Next Line
            currentBuffer.cursorCol = 0
            currentBuffer.moveCursorDown(max(1, p1))
        case 0x46: // 'F' - Cursor Previous Line
            currentBuffer.cursorCol = 0
            currentBuffer.moveCursorUp(max(1, p1))
        case 0x47, 0x60: // 'G', '`' - Cursor Character Absolute
            currentBuffer.cursorCol = max(0, min(p1 - 1, currentBuffer.cols - 1))
        case 0x48, 0x66: // 'H', 'f'
            currentBuffer.moveCursor(row: max(1, p1) - 1, col: max(1, p2) - 1)
        case 0x4A: currentBuffer.clearScreen(mode: p1)
        case 0x4B: currentBuffer.clearLine(mode: p1)
        case 0x4C: currentBuffer.insertLines(max(1, p1))
        case 0x4D: currentBuffer.deleteLines(max(1, p1))
        case 0x50: currentBuffer.deleteChars(max(1, p1))
        case 0x40: currentBuffer.insertChars(max(1, p1))
        case 0x63: handleDeviceAttributes()
        case 0x64: // 'd' - Line Position Absolute
            currentBuffer.cursorRow = max(0, min(p1 - 1, currentBuffer.rows - 1))
        case 0x68: if isPrivateSequence { handlePrivateMode(p1, set: true) }
        case 0x6C: if isPrivateSequence { handlePrivateMode(p1, set: false) }
        case 0x6D: handleSGR()
        case 0x6E: handleDeviceStatusReport(p1)
        case 0x72: // 'r' - Set Scrolling Region
            let top = max(1, p1) - 1
            let bottom = (p2 == 0 ? currentBuffer.rows : p2) - 1
            currentBuffer.setScrollRegion(top: top, bottom: bottom)
            currentBuffer.moveCursor(row: 0, col: 0)
        case 0x73: // 's' - Save cursor
            savedCursorRow = currentBuffer.cursorRow
            savedCursorCol = currentBuffer.cursorCol
        case 0x74: handleWindowManipulation(p1)
        case 0x75: // 'u' - Restore cursor
            currentBuffer.moveCursor(row: savedCursorRow, col: savedCursorCol)
        default: break
        }
    }

    private func handleSGR() {
        if csiParams.isEmpty {
            currentBuffer.resetAttributes()
            return
        }

        var i = 0
        while i < csiParams.count {
            let param = csiParams[i]
            switch param {
            case 0: currentBuffer.resetAttributes()
            case 1: currentBuffer.currentBold = true
            case 2: currentBuffer.currentDim = true
            case 3: currentBuffer.currentItalic = true
            case 4: currentBuffer.currentUnderline = true
            case 7: currentBuffer.currentInverse = true
            case 22: currentBuffer.currentBold = false; currentBuffer.currentDim = false
            case 23: currentBuffer.currentItalic = false
            case 24: currentBuffer.currentUnderline = false
            case 27: currentBuffer.currentInverse = false
            case 30...37: currentBuffer.currentForeground = ANSIColors.standardColors[param - 30]
            case 38: // Extended foreground
                if i + 2 < csiParams.count && csiParams[i + 1] == 5 {
                    currentBuffer.currentForeground = ANSIColors.color256(csiParams[i + 2])
                    i += 2
                } else if i + 4 < csiParams.count && csiParams[i + 1] == 2 {
                    currentBuffer.currentForeground = NSColor(
                        red: CGFloat(csiParams[i + 2]) / 255,
                        green: CGFloat(csiParams[i + 3]) / 255,
                        blue: CGFloat(csiParams[i + 4]) / 255,
                        alpha: 1
                    )
                    i += 4
                }
            case 39: currentBuffer.currentForeground = nil  // Default foreground
            case 40...47: currentBuffer.currentBackground = ANSIColors.standardColors[param - 40]
            case 48: // Extended background
                if i + 2 < csiParams.count && csiParams[i + 1] == 5 {
                    currentBuffer.currentBackground = ANSIColors.color256(csiParams[i + 2])
                    i += 2
                } else if i + 4 < csiParams.count && csiParams[i + 1] == 2 {
                    currentBuffer.currentBackground = NSColor(
                        red: CGFloat(csiParams[i + 2]) / 255,
                        green: CGFloat(csiParams[i + 3]) / 255,
                        blue: CGFloat(csiParams[i + 4]) / 255,
                        alpha: 1
                    )
                    i += 4
                }
            case 49: currentBuffer.currentBackground = nil  // Default background
            case 90...97: currentBuffer.currentForeground = ANSIColors.standardColors[param - 90 + 8]
            case 100...107: currentBuffer.currentBackground = ANSIColors.standardColors[param - 100 + 8]
            default: break
            }
            i += 1
        }
    }

    private func handleDeviceAttributes() {
        if isPrivateSequence && privateMarker == ">" {
            sendResponse("\u{1B}[>1;10;0c")
        } else {
            sendResponse("\u{1B}[?62;1;2;6;7;8;9c")
        }
    }

    private func handleDeviceStatusReport(_ param: Int) {
        switch param {
        case 5: sendResponse("\u{1B}[0n")
        case 6: sendResponse("\u{1B}[\(currentBuffer.cursorRow + 1);\(currentBuffer.cursorCol + 1)R")
        default: break
        }
    }

    private func handlePrivateMode(_ mode: Int, set: Bool) {
        switch mode {
        case 1: break // Application cursor keys (TODO)
        case 7: break // Autowrap (TODO)
        case 25: cursorVisible = set
        case 1049:
            if set {
                useAltBuffer = true
                altBuffer.clearScreen(mode: 2)
                currentBuffer = altBuffer
            } else {
                useAltBuffer = false
                currentBuffer = mainBuffer
            }
        default: break
        }
    }

    private func handleWindowManipulation(_ param: Int) {
        switch param {
        case 18: sendResponse("\u{1B}[8;\(currentBuffer.rows);\(currentBuffer.cols)t")
        case 19: sendResponse("\u{1B}[9;\(currentBuffer.rows);\(currentBuffer.cols)t")
        default: break
        }
    }

    private func sendResponse(_ response: String) {
        if let data = response.data(using: .utf8) {
            onInput?(data)
        }
    }

    private func updateDisplay() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.updateContentSize()
            self.contentView.setNeedsDisplay(self.contentView.bounds)
            // Auto-scroll to bottom
            self.scrollToBottom()
        }
    }

    private func updateContentSize() {
        let scrollbackLines = currentBuffer.scrollback.count
        let totalLines = scrollbackLines + currentBuffer.rows
        let newHeight = CGFloat(totalLines) * charHeight + 16
        let newWidth = CGFloat(currentBuffer.cols) * charWidth + 16
        contentView.frame = CGRect(x: 0, y: 0, width: newWidth, height: newHeight)
    }

    func scrollToBottom() {
        let scrollbackLines = currentBuffer.scrollback.count
        let totalHeight = CGFloat(scrollbackLines + currentBuffer.rows) * charHeight + 16
        let visibleHeight = scrollView.contentView.bounds.height
        let scrollPoint = NSPoint(x: 0, y: max(0, totalHeight - visibleHeight))
        scrollView.contentView.scroll(to: scrollPoint)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func clear() {
        currentBuffer.clearScreen(mode: 2)
        processedLength = 0
        updateDisplay()
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds.insetBy(dx: 1, dy: 1)

        let viewSize = bounds.size
        let newCols = max(80, Int((viewSize.width - 16) / charWidth))
        let newRows = max(24, Int((viewSize.height - 16) / charHeight))

        if newCols != currentBuffer.cols || newRows != currentBuffer.rows {
            mainBuffer.resize(newRows: newRows, newCols: newCols)
            altBuffer.resize(newRows: newRows, newCols: newCols)

            // Notify about size change
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onSizeChange?(self.currentBuffer.cols, self.currentBuffer.rows)
            }
        }

        updateContentSize()
    }
}

// MARK: - Terminal Content View (Custom Drawing)

class TerminalContentView: NSView {
    weak var terminalView: TerminalNSView?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        // Forward focus to parent terminal view
        terminalView?.window?.makeFirstResponder(terminalView)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = terminalView else { return }
        let buffer = tv.useAltBuffer ? tv.altBuffer : tv.mainBuffer
        guard let buffer = buffer else { return }

        // Draw background
        tv.backgroundColor.setFill()
        dirtyRect.fill()

        let font = tv.terminalFont
        let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)

        let scrollbackCount = buffer.scrollback.count

        // Helper to draw a cell
        func drawCell(_ cell: TerminalCell, at row: Int, col: Int) {
            let x = CGFloat(col) * tv.charWidth + 8
            let y = CGFloat(row) * tv.charHeight + 8
            let cellRect = CGRect(x: x, y: y, width: tv.charWidth, height: tv.charHeight)

            // Skip if outside dirty rect
            guard cellRect.intersects(dirtyRect) else { return }

            // Resolve colors - nil means use terminal default
            var bgColor = cell.background ?? NSColor.clear
            var fgColor = cell.foreground ?? tv.foregroundColor

            if cell.inverse {
                let resolvedBg = cell.background ?? tv.backgroundColor
                bgColor = fgColor
                fgColor = resolvedBg
            }

            if cell.dim {
                fgColor = fgColor.withAlphaComponent(0.5)
            }

            if bgColor != NSColor.clear {
                bgColor.setFill()
                cellRect.fill()
            }

            // Draw character
            if cell.character != " " {
                var cellFont = font
                if cell.bold { cellFont = boldFont }
                if cell.italic { cellFont = italicFont }

                var attrs: [NSAttributedString.Key: Any] = [
                    .font: cellFont,
                    .foregroundColor: fgColor
                ]

                if cell.underline {
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }

                let str = String(cell.character)
                str.draw(at: CGPoint(x: x, y: y), withAttributes: attrs)
            }
        }

        // Draw scrollback lines first
        for (scrollRow, line) in buffer.scrollback.enumerated() {
            for (col, cell) in line.enumerated() {
                drawCell(cell, at: scrollRow, col: col)
            }
        }

        // Draw current grid (below scrollback)
        for row in 0..<buffer.rows {
            for col in 0..<buffer.cols {
                let cell = buffer.grid[row][col]
                drawCell(cell, at: scrollbackCount + row, col: col)
            }
        }

        // Draw cursor (adjusted for scrollback offset)
        if tv.cursorVisible {
            let cursorX = CGFloat(buffer.cursorCol) * tv.charWidth + 8
            let cursorY = CGFloat(scrollbackCount + buffer.cursorRow) * tv.charHeight + 8
            let cursorRect = CGRect(x: cursorX, y: cursorY, width: tv.charWidth, height: tv.charHeight)

            tv.cursorColor.withAlphaComponent(0.7).setFill()
            cursorRect.fill()
        }
    }
}

#Preview {
    TerminalView(output: .constant([UInt8]("Hello, World!\r\n".utf8)), onInput: { _ in })
        .frame(width: 600, height: 400)
}
