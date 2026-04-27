# Snap

Snap is a performance-oriented, strongly typed network framework optimized for Roblox Luau implementations.

## Key Architecture Goals

* **Strict Serialization Rules:** Binary payloads reduce operational overhead compared to raw tables.
* **Consolidated APIs:** Streamlined channel definitions simplify cross-environment bindings.
* **Memory Stability:** Native support for table pooling restricts transient heap allocations.

## Wally Integration

Add the following specification into your manifest:

```toml
[dependencies]
Snap = "cometahn142/snap@^0.3.0"
```

## Implementation Outline

```luau
local Snap = require(Packages.Snap)

local GameChannel = Snap.channel("GameChannel", {
	Telemetry = Snap.event(Snap.struct({
		tick = Snap.uint32,
		position = Snap.vector3
	}), "Unreliable")
})
```

## Comprehensive Documentation

* [Installation](./docs/installation.md)
* [Snap API Definitions](./docs/snap.md)
* [Workflow Usage Patterns](./docs/usage-patterns.md)

## License

MIT. View the `LICENSE` registry for complete guidelines.
