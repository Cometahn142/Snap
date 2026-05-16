# Specification: The Snap Protocol

A formal description of the wire format and data types.

## 1. Wire Format Specification

Snap frames differ in structure depending on the active **Mode**.

### 1.1 Snap Mode (Optimized)
| Field | Size | Description |
| :--- | :--- | :--- |
| `WireID` | 1 byte | Channel identifier. |
| `PacketID` | 1 byte | Packet identifier. |
| `Payload` | Variable | Raw data. **Length prefix is omitted** for fixed-size schemas. |

### 1.2 Safe Mode (Validated)
| Field | Size | Description |
| :--- | :--- | :--- |
| `WireID` | 1 byte | Channel identifier. |
| `PacketID` | 1 byte | Packet identifier. |
| `Length` | 2 bytes | Payload size in bytes. |
| `Payload` | Variable | Raw data. |

## 2. Built-in Data Types

Snap provides 33 primitive and complex data types in the `DataTypes/` directory.

### Primitives
- **Integers**: `uint8`, `uint16`, `uint32`, `int8`, `int16`, `int32`.
- **Varints**: `uvarint` (LEB128), `varint` (Zig-Zag + LEB128).
- **Floats**: `float32`, `float64`.
- **Atoms**: `bool`, `char`, `string`, `null`, `auto`, `unknown`.
- **Roblox**: `inst` (ref), `vector2`, `vector3`, `color3`, `cframe`, `ray`, `brickcolor`, `datetime`.

### Higher-Order Types
- **`Snap.struct(fields)`**: Sequential concatenation of fields.
- **`Snap.array(type)`**: Length-prefixed sequence of a single type.
- **`Snap.bitarray`**: Boolean array packed into bit-fields.
- **`Snap.map(key, value)`**: Key-value pairs.
- **`Snap.optional(inner)`**: Nullable wrapper.
- **`Snap.flags(names)`**: Bit-packed dictionary.

## 3. Complexity & Constraints

| Target | Constraint | Description |
| :--- | :--- | :--- |
| **Channels** | 256 | Limited by 1-byte `WireID`. |
| **Packets** | 256 | Limited by 1-byte `PacketID` per channel. |
| **References** | 255 | Max unique Instances per frame. |
| **Pre-ready Queue**| 512 KB | Memory limit for joining players. |
| **Handshake** | 15s | Timeout for `ready` signal. |

## 4. Execution Complexity

| Logic | Time Complexity | Notes |
| :--- | :--- | :--- |
| `Frame.encode` | $O(S)$ | $S$ is the serialized size. |
| `Signify:Fire` | $O(L)$ | $L$ is the number of active connections. |
| `Varint:read` | $O(1)$ | Max 5 bytes per number. |
| `Refs:push` | $O(1)$ | Hash-map indexing. |

---
[Back to README](../README.md)
