# Snap

Snap is a binary networking library for Roblox (Luau). It is meant for projects
that want clearer network contracts, smaller payloads, and fewer surprises than
table-heavy remote code usually brings.

The core idea is simple: define your network surface once through explicit
schemas, then use the same namespace contract on the server and the client.

## Why use Snap

- Binary payloads are typically smaller and more predictable than plain table remotes
- Schemas make serialization rules explicit
- Namespaces keep packet and invoke definitions organized
- Matching definitions on both peers lead to deterministic runtime behavior

## Installation

```toml
[dependencies]
Snap = "cometahn142/snap@^0.1"
```

## Quick Example

```luau
local Snap = require(Packages.Snap)

local Combat = Snap.defineNamespace("Combat", function(p)
	return {
		Hit = p.packet(Snap.struct({
			TargetId = Snap.uint32,
			Damage = Snap.uint16,
		})),
		RequestState = p.invoke(Snap.null, Snap.string),
	}
end)
```

## Documentation

- [Installation](./docs/installation.md)
- [Usage Patterns](./docs/usage-patterns.md)
- [Snap API](./docs/snap.md)

## License

MIT. See `LICENSE`.
