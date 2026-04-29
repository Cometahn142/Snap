# Snap API Reference

The public API of Snap focuses on robust type definition, optimized serialization, and low-overhead throughput.

## Core Methods

### `Snap.channel(name: string, definition: table)`
Registers a distinct communication domain between the server and the client.
- `name`: The global identifier of the channel.
- `definition`: A dictionary containing packet entries created by `Snap.event` and `Snap.request`.

### `Snap.event(schema: DataType, reliability: string?)`
Defines a unidirectional network event payload.
- `schema`: The expected `DataType` schema validation rules.
- `reliability`: Networking standard; either `"Reliable"` or `"Unreliable"`. Defaults to `"Reliable"`.

### `Snap.request(requestSchema: DataType, responseSchema: DataType)`
Defines a bidirectional, yielding RPC interface.
- `requestSchema`: The payload schema that the client/server sends.
- `responseSchema`: The payload schema that the responding peer returns.

## Built-in Data Types

Snap provides optimized internal primitives and combinators for network encoding:

### Primitive / Numeric Types
- Integers: `uint8`, `uint16`, `uint32`, `int8`, `int16`, `int32`.
- Variable-length Integers: `uvarint`, `varint`.
- Decimals: `float32`, `float64`.
- Common: `bool`, `char`, `string`, `null`, `auto`, `unknown`, `inst` (Roblox Instance).

### Roblox Engine Types
- `vector3`, `vector3int16`, `color3`, `color3b`, `cframe`.

### Combinators
- `struct(fields: table)` - A strictly keyed map.
- `array(elementType: DataType)` - An ordered list.
- `map(keyType, valueType)` - A typed dictionary.
- `optional(innerType)` - A nullable pointer.
- `flags(names: table)` - A bitpacked set of boolean toggles.

## Memory Management: Table Pooling

To mitigate garbage collection overhead during continuous transmission loops, Snap supports optional Table Pooling.

Both `struct` and `array` expose an extended `read` signature:
`read(buffer: buffer, offset: number, target: table?) -> (table, number)`

Supplying an existing array or map to the `target` parameter overrides default allocations, pushing deserialized state into the reused memory directly.
