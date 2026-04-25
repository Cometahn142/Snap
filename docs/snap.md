# Snap

This page summarizes the main public API exposed by the module.

## Core API

- `Snap.defineNamespace(name, builder)`
- `Snap.serialize(schema, value)`
- `Snap.deserialize(schema, buffer, refs?)`

These are the three entry points most users interact with directly.

## Built-in Data Types

### Numeric

- `uint8`, `uint16`, `uint32`
- `int8`, `int16`, `int32`
- `uvarint`, `varint`
- `float32`, `float64`

### Primitive

- `bool`
- `char`
- `string`
- `null`
- `auto`
- `unknown`
- `inst`

### Roblox-specific

- `vector3`
- `vector3int16`
- `color3`
- `color3b`
- `cframe`

### Combinators

- `struct(fields)`
- `array(elementType)`
- `map(keyType, valueType)`
- `optional(innerType)`
- `flags(names)`

## Namespace Builder

Inside `defineNamespace`, the builder receives:

- `p.packet(schema, reliability?)`
- `p.invoke(requestSchema, responseSchema)`

## Runtime Handles

### Packet

- `send(value)` on the client
- `sendTo(player, value)` on the server
- `sendToAll(value)`
- `sendToAllExcept(player, value)`
- `sendToList(players, value)`
- `listen(callback)` -> `unlisten()`

### Invoke

- `invoke(...) -> (ok, resultOrError)`
- `handle(callback)` -> `unbind()`

## Related Docs

- [Installation](./installation.md)
- [Usage Patterns](./usage-patterns.md)

## License

MIT. See `LICENSE`.
