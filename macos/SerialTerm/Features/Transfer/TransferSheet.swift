import SwiftUI
import UniformTypeIdentifiers

struct TransferSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var selectedProtocol: TransferManager.TransferProtocol = .zmodem
    @State private var direction: TransferManager.TransferDirection = .send
    @State private var selectedFileURL: URL?
    @State private var fileData: Data?
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider()

            // Content
            VStack(spacing: 20) {
                // Direction
                Picker("Direction", selection: $direction) {
                    Label("Send", systemImage: "arrow.up.doc").tag(TransferManager.TransferDirection.send)
                    Label("Receive", systemImage: "arrow.down.doc").tag(TransferManager.TransferDirection.receive)
                }
                .pickerStyle(.segmented)

                // Protocol selection
                VStack(alignment: .leading, spacing: 8) {
                    Text("Protocol")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Protocol", selection: $selectedProtocol) {
                        ForEach(TransferManager.TransferProtocol.allCases) { proto in
                            Text(proto.rawValue).tag(proto)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // File selection (for send)
                if direction == .send {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("File")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            if let url = selectedFileURL {
                                Text(url.lastPathComponent)
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                if let data = fileData {
                                    Text("(\(formatBytes(data.count)))")
                                        .foregroundColor(.secondary)
                                }
                            } else {
                                Text("No file selected")
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Button("Browse...") {
                                showFilePicker = true
                            }
                        }
                    }
                }

                // Protocol info
                protocolInfoView
            }
            .padding()

            Divider()

            // Actions
            actionButtons
        }
        .frame(width: 400, height: direction == .send ? 350 : 280)
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedFileURL = url
                    // Read file data
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        fileData = try? Data(contentsOf: url)
                    }
                }
            case .failure:
                break
            }
        }
    }

    private var headerView: some View {
        HStack {
            Text("File Transfer")
                .font(.headline)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .padding()
    }

    private var protocolInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("About \(selectedProtocol.rawValue)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            Text(protocolDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private var protocolDescription: String {
        switch selectedProtocol {
        case .xmodem:
            return "Original XMODEM with checksum. 128-byte blocks. Good compatibility but slow."
        case .xmodemCRC:
            return "XMODEM with CRC-16 error checking. More reliable than checksum mode."
        case .xmodem1K:
            return "XMODEM with 1024-byte blocks. Faster for large files."
        case .ymodem:
            return "Batch transfer protocol. Transfers filename and size. 1K blocks with CRC."
        case .zmodem:
            return "Recommended. Auto-start, streaming, crash recovery. Best performance."
        }
    }

    private var actionButtons: some View {
        HStack {
            Spacer()

            Button(direction == .send ? "Send" : "Receive") {
                startTransfer()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .disabled(direction == .send && fileData == nil)
        }
        .padding()
    }

    private func startTransfer() {
        // Update app state with transfer info
        appState.activeTransfer = TransferState(
            direction: direction == .send ? .send : .receive,
            protocolType: mapProtocol(selectedProtocol),
            fileName: selectedFileURL?.lastPathComponent ?? "",
            progress: 0,
            bytesTransferred: 0,
            totalBytes: fileData?.count ?? 0,
            isActive: true
        )

        // Start the actual transfer
        // This would integrate with the TransferManager
    }

    private func mapProtocol(_ proto: TransferManager.TransferProtocol) -> TransferState.TransferProtocol {
        switch proto {
        case .xmodem, .xmodemCRC, .xmodem1K:
            return .xmodem
        case .ymodem:
            return .ymodem
        case .zmodem:
            return .zmodem
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

#Preview {
    TransferSheet()
        .environmentObject(AppState())
}
