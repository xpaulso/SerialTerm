import SwiftUI
import AppKit

/// A terminal view that displays serial output and handles keyboard input
struct TerminalView: NSViewRepresentable {
    @Binding var output: [UInt8]
    var onInput: (Data) -> Void

    func makeNSView(context: Context) -> TerminalNSView {
        let view = TerminalNSView()
        view.onInput = onInput
        return view
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {
        nsView.appendOutput(output)
    }
}

/// Custom NSView for terminal rendering
class TerminalNSView: NSView {
    var onInput: ((Data) -> Void)?

    private var textStorage = NSTextStorage()
    private var layoutManager = NSLayoutManager()
    private var textContainer: NSTextContainer!
    private var scrollView: NSScrollView!
    private var textView: NSTextView!

    private var displayedLength = 0
    private let maxBufferSize = 100_000 // Max characters to keep

    // Terminal colors
    private var foregroundColor = NSColor.textColor
    private var backgroundColor = NSColor.textBackgroundColor

    // Font
    private var terminalFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Create text container
        textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false

        // Setup layout manager
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)

        // Create scroll view
        scrollView = NSScrollView(frame: bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor

        // Create text view
        textView = NSTextView(frame: scrollView.contentView.bounds, textContainer: textContainer)
        textView.autoresizingMask = [.width]
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = terminalFont
        textView.textColor = foregroundColor
        textView.backgroundColor = backgroundColor
        textView.drawsBackground = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false

        // Configure for terminal-like behavior
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.allowsUndo = false

        scrollView.documentView = textView
        addSubview(scrollView)

        // Make first responder for key events
        wantsLayer = true
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.characters else {
            super.keyDown(with: event)
            return
        }

        // Handle special keys
        var data: Data?

        switch event.keyCode {
        case 36: // Return
            data = Data([0x0D])
        case 51: // Backspace
            data = Data([0x7F])
        case 53: // Escape
            data = Data([0x1B])
        case 123: // Left arrow
            data = Data([0x1B, 0x5B, 0x44])
        case 124: // Right arrow
            data = Data([0x1B, 0x5B, 0x43])
        case 125: // Down arrow
            data = Data([0x1B, 0x5B, 0x42])
        case 126: // Up arrow
            data = Data([0x1B, 0x5B, 0x41])
        case 48: // Tab
            data = Data([0x09])
        default:
            // Regular characters
            if let charData = characters.data(using: .utf8) {
                data = charData
            }
        }

        // Handle control characters
        if event.modifierFlags.contains(.control), let char = characters.first {
            if let asciiValue = char.asciiValue, asciiValue >= 0x40 && asciiValue <= 0x7F {
                data = Data([asciiValue & 0x1F])
            }
        }

        if let data = data {
            onInput?(data)
        }
    }

    func appendOutput(_ bytes: [UInt8]) {
        guard bytes.count > displayedLength else { return }

        let newBytes = Array(bytes[displayedLength...])
        displayedLength = bytes.count

        // Process bytes for display (handle control characters)
        let processedString = processBytes(newBytes)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            let attrs: [NSAttributedString.Key: Any] = [
                .font: self.terminalFont,
                .foregroundColor: self.foregroundColor
            ]

            let attributedString = NSAttributedString(string: processedString, attributes: attrs)
            self.textStorage.append(attributedString)

            // Trim buffer if too large
            if self.textStorage.length > self.maxBufferSize {
                let trimLength = self.textStorage.length - self.maxBufferSize / 2
                self.textStorage.deleteCharacters(in: NSRange(location: 0, length: trimLength))
            }

            // Scroll to bottom
            self.textView.scrollToEndOfDocument(nil)
        }
    }

    private func processBytes(_ bytes: [UInt8]) -> String {
        var result = ""
        var i = 0

        while i < bytes.count {
            let byte = bytes[i]

            switch byte {
            case 0x07: // Bell
                NSSound.beep()
            case 0x08: // Backspace
                if !result.isEmpty {
                    result.removeLast()
                }
            case 0x09: // Tab
                result.append("\t")
            case 0x0A: // Line feed
                result.append("\n")
            case 0x0D: // Carriage return
                // Check if followed by LF
                if i + 1 < bytes.count && bytes[i + 1] == 0x0A {
                    result.append("\n")
                    i += 1
                } else {
                    result.append("\r")
                }
            case 0x1B: // Escape sequence
                // Skip ANSI escape sequences for now (simplified)
                if i + 1 < bytes.count && bytes[i + 1] == 0x5B {
                    // CSI sequence - skip until we find the final byte
                    i += 2
                    while i < bytes.count && bytes[i] < 0x40 {
                        i += 1
                    }
                }
            case 0x20...0x7E: // Printable ASCII
                result.append(Character(UnicodeScalar(byte)))
            case 0x80...0xFF: // Extended/UTF-8
                // Try to decode as UTF-8
                result.append(Character(UnicodeScalar(byte)))
            default:
                break
            }

            i += 1
        }

        return result
    }

    func clear() {
        textStorage.setAttributedString(NSAttributedString())
        displayedLength = 0
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
    }
}

#Preview {
    TerminalView(output: .constant([UInt8]("Hello, World!\r\n".utf8)), onInput: { _ in })
        .frame(width: 600, height: 400)
}
