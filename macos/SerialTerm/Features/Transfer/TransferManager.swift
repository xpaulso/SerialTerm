import Foundation

/// Manages file transfer protocols
class TransferManager: ObservableObject {
    @Published var isActive = false
    @Published var progress: Double = 0
    @Published var bytesTransferred: Int = 0
    @Published var totalBytes: Int = 0
    @Published var currentProtocol: TransferProtocol = .xmodem
    @Published var direction: TransferDirection = .send
    @Published var fileName: String = ""
    @Published var errorMessage: String?

    enum TransferProtocol: String, CaseIterable, Identifiable {
        case xmodem = "XMODEM"
        case xmodemCRC = "XMODEM-CRC"
        case xmodem1K = "XMODEM-1K"
        case ymodem = "YMODEM"
        case zmodem = "ZMODEM"

        var id: String { rawValue }
    }

    enum TransferDirection {
        case send
        case receive
    }

    private var sendCallback: ((Data) -> Void)?
    private var transferData: Data?
    private var receivedData = Data()

    func startSend(
        protocol transferProtocol: TransferProtocol,
        fileName: String,
        data: Data,
        sendCallback: @escaping (Data) -> Void
    ) {
        self.currentProtocol = transferProtocol
        self.direction = .send
        self.fileName = fileName
        self.transferData = data
        self.totalBytes = data.count
        self.bytesTransferred = 0
        self.progress = 0
        self.isActive = true
        self.sendCallback = sendCallback
        self.errorMessage = nil

        // Start the transfer based on protocol
        switch transferProtocol {
        case .xmodem, .xmodemCRC, .xmodem1K:
            // Wait for receiver to send NAK or 'C'
            break
        case .ymodem:
            // Wait for receiver to send 'C'
            break
        case .zmodem:
            // Send ZRQINIT
            sendZModemInit()
        }
    }

    func startReceive(
        protocol transferProtocol: TransferProtocol,
        sendCallback: @escaping (Data) -> Void
    ) {
        self.currentProtocol = transferProtocol
        self.direction = .receive
        self.fileName = ""
        self.totalBytes = 0
        self.bytesTransferred = 0
        self.progress = 0
        self.isActive = true
        self.sendCallback = sendCallback
        self.receivedData = Data()
        self.errorMessage = nil

        // Start the receive based on protocol
        switch transferProtocol {
        case .xmodem, .xmodemCRC, .xmodem1K:
            // Send 'C' for CRC mode or NAK for checksum
            sendCallback(Data([0x43])) // 'C'
        case .ymodem:
            // Send 'C' to start
            sendCallback(Data([0x43]))
        case .zmodem:
            // Send ZRINIT
            sendZRINIT()
        }
    }

    func processReceivedData(_ data: Data) {
        guard isActive else { return }

        // Process based on protocol (simplified)
        // In a full implementation, this would handle the protocol state machine

        // For demo, just track progress
        bytesTransferred += data.count
        if totalBytes > 0 {
            progress = Double(bytesTransferred) / Double(totalBytes)
        }
    }

    func cancel() {
        guard isActive else { return }

        // Send cancel sequence
        switch currentProtocol {
        case .xmodem, .xmodemCRC, .xmodem1K, .ymodem:
            // Send CAN CAN CAN
            sendCallback?(Data([0x18, 0x18, 0x18]))
        case .zmodem:
            // Send ZCAN sequence
            let zcan = Data([0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08, 0x08])
            sendCallback?(zcan)
        }

        isActive = false
        errorMessage = "Transfer cancelled"
    }

    func complete(with data: Data? = nil) {
        isActive = false
        progress = 1.0

        if let data = data {
            receivedData = data
        }
    }

    func getReceivedData() -> Data {
        return receivedData
    }

    // MARK: - ZMODEM Helpers

    private func sendZModemInit() {
        // Send rz\r**\x18B... ZRQINIT header
        let init_seq = "rz\r**\u{18}B0000000000000000\r\n\u{11}"
        if let data = init_seq.data(using: .ascii) {
            sendCallback?(data)
        }
    }

    private func sendZRINIT() {
        // Send ZRINIT frame
        // Format: ZPAD ZPAD ZDLE ZHEX type(2) data(8) crc(4) CR LF XON
        let frame = "**\u{18}B0100000000007c5b\r\n\u{11}"
        if let data = frame.data(using: .ascii) {
            sendCallback?(data)
        }
    }

    // MARK: - Static Detection

    static func detectZModemAutoStart(_ bytes: [UInt8]) -> Bool {
        // Look for "rz\r" or ZRQINIT pattern "**\x18B"
        let data = Data(bytes)
        if let str = String(data: data, encoding: .ascii) {
            if str.contains("rz\r") || str.contains("**\u{18}B") {
                return true
            }
        }
        return false
    }
}
