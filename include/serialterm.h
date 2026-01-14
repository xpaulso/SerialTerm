#ifndef SERIALTERM_H
#define SERIALTERM_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Types
// ============================================================================

/// Opaque handle to a serial port
typedef void* SerialPortHandle;

/// Error codes
typedef enum {
    SERIAL_SUCCESS = 0,
    SERIAL_ERROR_OPEN_FAILED = -1,
    SERIAL_ERROR_CONFIG_FAILED = -2,
    SERIAL_ERROR_NOT_A_TERMINAL = -3,
    SERIAL_ERROR_INVALID_BAUD = -4,
    SERIAL_ERROR_READ_ERROR = -5,
    SERIAL_ERROR_WRITE_ERROR = -6,
    SERIAL_ERROR_TIMEOUT = -7,
    SERIAL_ERROR_PORT_CLOSED = -8,
    SERIAL_ERROR_INVALID_HANDLE = -9,
    SERIAL_ERROR_OUT_OF_MEMORY = -10,
} SerialError;

/// Parity modes
typedef enum {
    SERIAL_PARITY_NONE = 0,
    SERIAL_PARITY_ODD = 1,
    SERIAL_PARITY_EVEN = 2,
} SerialParity;

/// Flow control modes
typedef enum {
    SERIAL_FLOW_NONE = 0,
    SERIAL_FLOW_HARDWARE = 1,  // RTS/CTS
    SERIAL_FLOW_SOFTWARE = 2,  // XON/XOFF
} SerialFlowControl;

/// Line ending modes
typedef enum {
    SERIAL_LINE_CR = 0,
    SERIAL_LINE_LF = 1,
    SERIAL_LINE_CRLF = 2,
} SerialLineEnding;

/// Serial port configuration
typedef struct {
    uint32_t baud_rate;        // e.g., 115200
    uint8_t data_bits;         // 5, 6, 7, or 8
    uint8_t parity;            // SerialParity
    uint8_t stop_bits;         // 1 or 2
    uint8_t flow_control;      // SerialFlowControl
    bool local_echo;
    uint8_t line_ending;       // SerialLineEnding
} SerialConfig;

/// Modem status lines
typedef struct {
    bool dtr;  // Data Terminal Ready
    bool rts;  // Request To Send
    bool cts;  // Clear To Send
    bool dsr;  // Data Set Ready
    bool dcd;  // Data Carrier Detect
    bool ri;   // Ring Indicator
} ModemStatus;

// ============================================================================
// Configuration Defaults
// ============================================================================

/// Default configuration (115200 8N1, no flow control)
static inline SerialConfig serial_config_default(void) {
    return (SerialConfig){
        .baud_rate = 115200,
        .data_bits = 8,
        .parity = SERIAL_PARITY_NONE,
        .stop_bits = 1,
        .flow_control = SERIAL_FLOW_NONE,
        .local_echo = false,
        .line_ending = SERIAL_LINE_CR,
    };
}

/// Arduino default configuration (9600 8N1)
static inline SerialConfig serial_config_arduino(void) {
    return (SerialConfig){
        .baud_rate = 9600,
        .data_bits = 8,
        .parity = SERIAL_PARITY_NONE,
        .stop_bits = 1,
        .flow_control = SERIAL_FLOW_NONE,
        .local_echo = false,
        .line_ending = SERIAL_LINE_CR,
    };
}

// ============================================================================
// Port Management
// ============================================================================

/**
 * Opens a serial port with the specified configuration.
 *
 * @param path Path to the serial device (e.g., "/dev/cu.usbserial-0001")
 * @param config Pointer to configuration structure
 * @param handle_out Pointer to receive the port handle
 * @return SERIAL_SUCCESS on success, error code on failure
 */
SerialError serial_open(const char* path, const SerialConfig* config, SerialPortHandle* handle_out);

/**
 * Closes a serial port and releases resources.
 *
 * @param handle The port handle to close
 */
void serial_close(SerialPortHandle handle);

// ============================================================================
// Data Transfer
// ============================================================================

/**
 * Reads data from the serial port.
 *
 * @param handle The port handle
 * @param buffer Buffer to receive data
 * @param buffer_len Size of the buffer
 * @param bytes_read Pointer to receive number of bytes read
 * @return SERIAL_SUCCESS on success, error code on failure
 */
SerialError serial_read(SerialPortHandle handle, uint8_t* buffer, size_t buffer_len, size_t* bytes_read);

/**
 * Writes data to the serial port.
 *
 * @param handle The port handle
 * @param data Data to write
 * @param data_len Number of bytes to write
 * @param bytes_written Pointer to receive number of bytes written
 * @return SERIAL_SUCCESS on success, error code on failure
 */
SerialError serial_write(SerialPortHandle handle, const uint8_t* data, size_t data_len, size_t* bytes_written);

/**
 * Writes all data to the serial port, handling partial writes.
 *
 * @param handle The port handle
 * @param data Data to write
 * @param data_len Number of bytes to write
 * @return SERIAL_SUCCESS on success, error code on failure
 */
SerialError serial_write_all(SerialPortHandle handle, const uint8_t* data, size_t data_len);

// ============================================================================
// Control Signals
// ============================================================================

/**
 * Sends a break signal on the serial line.
 *
 * @param handle The port handle
 * @return SERIAL_SUCCESS on success, error code on failure
 */
SerialError serial_send_break(SerialPortHandle handle);

/**
 * Sets the DTR (Data Terminal Ready) line.
 *
 * @param handle The port handle
 * @param state true to assert DTR, false to deassert
 * @return SERIAL_SUCCESS on success, error code on failure
 */
SerialError serial_set_dtr(SerialPortHandle handle, bool state);

/**
 * Sets the RTS (Request To Send) line.
 *
 * @param handle The port handle
 * @param state true to assert RTS, false to deassert
 * @return SERIAL_SUCCESS on success, error code on failure
 */
SerialError serial_set_rts(SerialPortHandle handle, bool state);

/**
 * Gets the current modem status lines.
 *
 * @param handle The port handle
 * @param status Pointer to receive modem status
 * @return SERIAL_SUCCESS on success, error code on failure
 */
SerialError serial_get_modem_status(SerialPortHandle handle, ModemStatus* status);

// ============================================================================
// Buffer Control
// ============================================================================

/**
 * Flushes the input buffer (discards unread data).
 *
 * @param handle The port handle
 * @return SERIAL_SUCCESS on success, error code on failure
 */
SerialError serial_flush_input(SerialPortHandle handle);

/**
 * Flushes the output buffer (waits for data to be sent).
 *
 * @param handle The port handle
 * @return SERIAL_SUCCESS on success, error code on failure
 */
SerialError serial_flush_output(SerialPortHandle handle);

/**
 * Flushes both input and output buffers.
 *
 * @param handle The port handle
 * @return SERIAL_SUCCESS on success, error code on failure
 */
SerialError serial_flush(SerialPortHandle handle);

/**
 * Returns the number of bytes available to read.
 *
 * @param handle The port handle
 * @return Number of bytes available, or 0 on error
 */
int serial_bytes_available(SerialPortHandle handle);

/**
 * Waits for data to become available.
 *
 * @param handle The port handle
 * @param timeout_ms Timeout in milliseconds
 * @return true if data is available, false on timeout or error
 */
bool serial_wait_for_data(SerialPortHandle handle, uint32_t timeout_ms);

/**
 * Gets the underlying file descriptor (for use with select/poll).
 *
 * @param handle The port handle
 * @return File descriptor, or -1 on error
 */
int serial_get_fd(SerialPortHandle handle);

// ============================================================================
// Port Enumeration
// ============================================================================

/**
 * Callback for port enumeration.
 *
 * @param path Path to the serial device
 * @param context User-provided context pointer
 */
typedef void (*SerialEnumCallback)(const char* path, void* context);

/**
 * Enumerates available serial ports.
 *
 * @param callback Function to call for each port found
 * @param context User context passed to callback
 * @return SERIAL_SUCCESS on success, error code on failure
 */
SerialError serial_enumerate_ports(SerialEnumCallback callback, void* context);

#ifdef __cplusplus
}
#endif

#endif // SERIALTERM_H
