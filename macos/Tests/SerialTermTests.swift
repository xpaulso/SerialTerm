import XCTest
@testable import SerialTerm

final class SerialTermTests: XCTestCase {

    // MARK: - SerialPortConfig Tests

    func testSerialPortConfigDefaults() {
        let config = SerialPortConfig()

        XCTAssertEqual(config.baudRate, .b115200)
        XCTAssertEqual(config.dataBits, .eight)
        XCTAssertEqual(config.parity, .none)
        XCTAssertEqual(config.stopBits, .one)
        XCTAssertEqual(config.flowControl, .none)
        XCTAssertFalse(config.localEcho)
    }

    func testSerialPortConfigSummary() {
        let config = SerialPortConfig()
        XCTAssertEqual(config.summary, "115200 8N1")

        let arduinoConfig = SerialPortConfig.arduino
        XCTAssertEqual(arduinoConfig.summary, "9600 8N1")
    }

    func testSerialPortConfigPresets() {
        XCTAssertEqual(SerialPortConfig.arduino.baudRate, .b9600)
        XCTAssertEqual(SerialPortConfig.ciscoConsole.baudRate, .b9600)
        XCTAssertEqual(SerialPortConfig.highSpeed.baudRate, .b921600)
        XCTAssertEqual(SerialPortConfig.highSpeed.flowControl, .hardware)
    }

    // MARK: - CommandModeHandler Tests

    func testCommandModeEscapeSequence() {
        let handler = CommandModeHandler()

        // First Ctrl+A enters command mode
        let (consumed1, command1) = handler.processKey(0x01)
        XCTAssertTrue(consumed1)
        XCTAssertNil(command1)
        XCTAssertTrue(handler.isInCommandMode)

        // Second key executes command
        let (consumed2, command2) = handler.processKey(UInt8(ascii: "q"))
        XCTAssertTrue(consumed2)
        XCTAssertEqual(command2, .quit)
        XCTAssertFalse(handler.isInCommandMode)
    }

    func testCommandModeDoubleEscape() {
        let handler = CommandModeHandler()

        // First Ctrl+A
        _ = handler.processKey(0x01)
        XCTAssertTrue(handler.isInCommandMode)

        // Second Ctrl+A sends literal
        let (consumed, command) = handler.processKey(0x01)
        XCTAssertTrue(consumed)
        XCTAssertEqual(command, .sendEscape)
    }

    func testCommandModeCommands() {
        let handler = CommandModeHandler()

        let testCases: [(UInt8, CommandModeHandler.Command)] = [
            (UInt8(ascii: "q"), .quit),
            (UInt8(ascii: "Q"), .quit),
            (UInt8(ascii: "b"), .sendBreak),
            (UInt8(ascii: "d"), .toggleDTR),
            (UInt8(ascii: "r"), .toggleRTS),
            (UInt8(ascii: "x"), .uploadXMODEM),
            (UInt8(ascii: "y"), .uploadYMODEM),
            (UInt8(ascii: "z"), .uploadZMODEM),
            (UInt8(ascii: "e"), .toggleLocalEcho),
            (UInt8(ascii: "c"), .clearScreen),
            (UInt8(ascii: "h"), .showHelp),
        ]

        for (key, expectedCommand) in testCases {
            handler.reset()

            _ = handler.processKey(0x01) // Enter command mode
            let (_, command) = handler.processKey(key)

            XCTAssertEqual(command, expectedCommand, "Key \(key) should trigger \(expectedCommand)")
        }
    }

    func testNormalKeyNotConsumed() {
        let handler = CommandModeHandler()

        // Regular key should not be consumed
        let (consumed, command) = handler.processKey(UInt8(ascii: "a"))
        XCTAssertFalse(consumed)
        XCTAssertNil(command)
        XCTAssertFalse(handler.isInCommandMode)
    }

    // MARK: - TransferManager Tests

    func testZModemAutoStartDetection() {
        // Valid ZMODEM sequences
        XCTAssertTrue(TransferManager.detectZModemAutoStart([UInt8]("rz\r".utf8)))
        XCTAssertTrue(TransferManager.detectZModemAutoStart([UInt8]("**\u{18}B".utf8)))

        // Invalid sequences
        XCTAssertFalse(TransferManager.detectZModemAutoStart([UInt8]("hello".utf8)))
        XCTAssertFalse(TransferManager.detectZModemAutoStart([]))
    }

    // MARK: - LineEnding Tests

    func testLineEndingBytes() {
        XCTAssertEqual(SerialPortConfig.LineEnding.cr.bytes, Data([0x0D]))
        XCTAssertEqual(SerialPortConfig.LineEnding.lf.bytes, Data([0x0A]))
        XCTAssertEqual(SerialPortConfig.LineEnding.crlf.bytes, Data([0x0D, 0x0A]))
    }
}
