# Usage Patterns

This page focuses on how Snap is normally used in real projects.

## Defining a shared namespace

The most important rule with Snap is that both peers must define the same
namespace using the same name and the same keys.

```luau
local Snap = require(Packages.Snap)

local Chat = Snap.defineNamespace("Chat", function(p)
	return {
		Message = p.packet(Snap.string),
		Ping = p.invoke(Snap.null, Snap.uint32),
	}
end)
```

Think of this as the network contract for that feature.

## Sending packets

On the client:

```luau
Chat.Message:send("hello")
```

On the server:

```luau
Chat.Message:sendTo(player, "welcome")
Chat.Message:sendToAll("server restart soon")
```

Use packets for one-way communication.

## Using invokes

Invokes are useful when one side needs a direct response.

```luau
local ok, result = Chat.Ping:invoke(player, nil)
if ok then
	print(result)
end
```

Use invokes when the request naturally expects a reply.

## Modeling data with schemas

Prefer explicit schemas over loosely typed payloads:

```luau
local HitSchema = Snap.struct({
	TargetId = Snap.uint32,
	Damage = Snap.uint16,
})
```

This keeps your network surface easier to audit and evolve.

## Standalone serialization

If you need to encode data outside remotes, use `serialize` and `deserialize`.

```luau
local b, refs = Snap.serialize(HitSchema, {
	TargetId = 10,
	Damage = 25,
})

local value = Snap.deserialize(HitSchema, b, refs)
```

## Practical Advice

- Keep namespace names stable.
- Avoid changing keys casually once the contract is in use.
- Prefer explicit structs for long-lived features.
- Keep shared definitions in one place to avoid drift.

## Next

- [Installation](./installation.md)
- [Snap API](./snap.md)

## License

MIT. See `LICENSE`.
