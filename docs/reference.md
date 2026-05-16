# Appendix A. Reference Manual

This manual provides the formal specification for all Snap API methods.

## A.1 The `Snap` Namespace

### `Snap.define(name, definition)`
Creates a new channel interface contract.
- **`name`**: Unique project-wide identifier.
- **`definition`**: Map of event/request definitions.

### `Snap.channel(name, definition): Channel`
Binds a definition to the current runtime. Automatically resolves to Server or Client side using `RunService`.

---

## A.2 Event Interface

### `Event:send(value)`
(Client) Queues data for the server.

### `Event:sendTo(player, value)`
(Server) Queues data for a specific client.

### `Event:sendToAll(value)`
(Server) Broadcasts data to all connected clients.

### `Event:sendToAllExcept(excluded, value)`
(Server) Broadcasts to all except one client.

### `Event:sendToList(players, value)`
(Server) Broadcasts to a specific list of clients.

### `Event:listen(callback)`
Registers a listener for incoming packets.

---

## A.3 Request Interface

### `Request:request(value): (boolean, any)`
(Client/Server) Transmits a request and yields for a response. Returns `ok` and the result.

### `Request:handle(callback: (Player?, Req) -> Res)`
Sets the handler for incoming requests. Only one handler is permitted per request.

---

## A.4 Internal Primitives

### `Snap.serialize(schema, value): (buffer, {any}?)`
Manually serializes a value using a Snap DataType.

### `Snap.deserialize(schema, buffer, refs?): T`
Manually deserializes a buffer back into a Luau value.

---

## A.5 System Constants

- **`MAX_CHANNELS`**: 256.
- **`MAX_REFS_PER_FRAME`**: 255.
- **`READY_TIMEOUT`**: 15 seconds.
- **`PREREADY_LIMIT`**: 512 KB per player.
