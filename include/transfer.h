#ifndef TRANSFER_H
#define TRANSFER_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Types
// ============================================================================

/// Transfer protocol type
typedef enum {
    TRANSFER_XMODEM = 0,
    TRANSFER_XMODEM_CRC = 1,
    TRANSFER_XMODEM_1K = 2,
    TRANSFER_YMODEM = 3,
    TRANSFER_ZMODEM = 4,
} TransferProtocol;

/// Transfer direction
typedef enum {
    TRANSFER_SEND = 0,
    TRANSFER_RECEIVE = 1,
} TransferDirection;

/// Transfer state
typedef enum {
    TRANSFER_STATE_IDLE = 0,
    TRANSFER_STATE_STARTING = 1,
    TRANSFER_STATE_TRANSFERRING = 2,
    TRANSFER_STATE_COMPLETING = 3,
    TRANSFER_STATE_COMPLETED = 4,
    TRANSFER_STATE_CANCELLED = 5,
    TRANSFER_STATE_FAILED = 6,
} TransferState;

/// Transfer progress information
typedef struct {
    TransferState state;
    uint64_t bytes_transferred;
    uint64_t total_bytes;
    uint32_t current_block;
    uint32_t total_blocks;
    uint32_t error_count;
    const char* file_name;
} TransferProgress;

/// Transfer event type
typedef enum {
    TRANSFER_EVENT_STARTED = 0,
    TRANSFER_EVENT_PROGRESS = 1,
    TRANSFER_EVENT_SEND_DATA = 2,
    TRANSFER_EVENT_COMPLETED = 3,
    TRANSFER_EVENT_FAILED = 4,
    TRANSFER_EVENT_CANCELLED = 5,
} TransferEventType;

/// Transfer event data
typedef struct {
    TransferEventType type;
    union {
        struct {
            const char* file_name;
            uint64_t file_size;
        } started;
        TransferProgress progress;
        struct {
            const uint8_t* data;
            size_t length;
        } send_data;
        const char* error_message;
    } data;
} TransferEvent;

/// Callback for transfer events
typedef void (*TransferEventCallback)(const TransferEvent* event, void* context);

/// Opaque handle to a transfer session
typedef void* TransferHandle;

// ============================================================================
// Transfer Management
// ============================================================================

/**
 * Creates a new transfer session.
 *
 * @param protocol The transfer protocol to use
 * @param callback Event callback function
 * @param context User context passed to callback
 * @return Transfer handle, or NULL on failure
 */
TransferHandle transfer_create(TransferProtocol protocol, TransferEventCallback callback, void* context);

/**
 * Destroys a transfer session and frees resources.
 *
 * @param handle The transfer handle
 */
void transfer_destroy(TransferHandle handle);

/**
 * Starts sending a file.
 *
 * @param handle The transfer handle
 * @param file_name Name of the file (for YMODEM/ZMODEM)
 * @param data Pointer to file data
 * @param data_len Length of file data
 * @return true on success, false on failure
 */
bool transfer_start_send(TransferHandle handle, const char* file_name, const uint8_t* data, size_t data_len);

/**
 * Starts receiving a file.
 *
 * @param handle The transfer handle
 * @return true on success, false on failure
 */
bool transfer_start_receive(TransferHandle handle);

/**
 * Processes received data from serial port.
 *
 * @param handle The transfer handle
 * @param data Received data
 * @param data_len Length of received data
 */
void transfer_process_data(TransferHandle handle, const uint8_t* data, size_t data_len);

/**
 * Cancels the current transfer.
 *
 * @param handle The transfer handle
 */
void transfer_cancel(TransferHandle handle);

/**
 * Checks if the transfer is active.
 *
 * @param handle The transfer handle
 * @return true if transfer is in progress
 */
bool transfer_is_active(TransferHandle handle);

/**
 * Gets the received data buffer (for receive operations).
 *
 * @param handle The transfer handle
 * @param length Pointer to receive data length
 * @return Pointer to received data, or NULL if none
 */
const uint8_t* transfer_get_received_data(TransferHandle handle, size_t* length);

/**
 * Gets the received file name (for YMODEM/ZMODEM).
 *
 * @param handle The transfer handle
 * @return File name string, or NULL if not available
 */
const char* transfer_get_file_name(TransferHandle handle);

// ============================================================================
// ZMODEM Auto-Start Detection
// ============================================================================

/**
 * Checks if data contains ZMODEM auto-start sequence.
 *
 * @param data Data to check
 * @param data_len Length of data
 * @return true if ZMODEM auto-start detected
 */
bool transfer_detect_zmodem_autostart(const uint8_t* data, size_t data_len);

#ifdef __cplusplus
}
#endif

#endif // TRANSFER_H
