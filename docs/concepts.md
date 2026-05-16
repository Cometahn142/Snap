# Concepts: The Architecture of Snap

Snap is a high-performance networking engine built on two distinct operation modes and advanced binary encoding strategies.

## 1. Dual-Mode Execution

Snap operates in either **Safe** or **Snap** (Fast) mode, configurable in `Settings.luau`. This allows developers to prioritize robustness during development and raw speed in production.

### Safe Mode
- **Robustness**: Utilizes `xpcall` for error isolation during serialization.
- **Validation**: Performs strict frame length checks to detect malformed data.
- **Tracking**: Enables real-time bandwidth and packet frequency monitoring.

### Snap Mode (Production)
- **Zero-Overhead Serialization**: Removes error handling and validation from the hot path.
- **Metadata Omission**: If a packet's size is constant, Snap **omits the length prefix entirely**. The protocol relies on the static definition to advance the buffer cursor, saving 1-3 bytes per packet.
- **Native Optimization**: All core loops are compiled with Luau's `--!native` flag.

## 2. Advanced Integer Encoding

Snap employs two primary strategies to minimize integer footprint:

- **Varints (LEB128)**: Small numbers (e.g., ID 1-127) are encoded as a single byte. Larger numbers grow dynamically, using the Most Significant Bit (MSB) as a continuation flag.
- **Zig-Zag Encoding**: For signed integers (`int8`, `int16`, etc.), Snap maps them to unsigned integers ($2n$ for $n \ge 0$, and $-2n-1$ for $n < 0$). This ensures that small negative numbers (like -1 or -2) are encoded into 1-2 bytes instead of the full width.

## 3. Resilience and Resource Management

### The Pre-ready Queue
Roblox networking is lossy during the `DataModel` initialization phase. Snap manages this through a state-aware buffer:
- **Handshake**: Servers queue all data for joining players until a `ready` signal is received from the client.
- **Memory Limit**: To prevent memory exhaustion from malicious or hanging clients, Snap caps this queue at **512KB** per player.
- **Timeout**: Queues are forcibly dropped after **15 seconds** if no handshake occurs.

### Buffer Recycling
The `BufferWriter` maintains a retained capacity of **64KB**. If a frame requires more (e.g., a massive inventory sync), the buffer expands but is automatically reclaimed down to 64KB after the flush to keep the memory footprint predictable.

---
[Next: Tutorial](tutorial.md)
