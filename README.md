# Snap

**Snap** is a high-performance networking framework for Luau/Roblox, built on the principles of binary serialization and deferred task batching.

## Documentation (Diátaxis Standard)

- **[Tutorial](docs/tutorial.md)**: A step-by-step lesson for getting started with Snap.
- **[Recipes](docs/recipes.md)**: Practical guides for common real-world networking tasks.
- **[Concepts](docs/concepts.md)**: Deep dive into the architecture and philosophies behind Snap.
- **[Specification](docs/specification.md)**: Formal technical specification, protocol bit-maps, and API reference.

---

## Technical Highlights

- **Binary Efficiency**: Zero-overhead serialization using Luau `buffer`.
- **Hybrid Support**: Native `Instance` referencing via sidecar tables.
- **Anti-Cheat**: Integrated `Guard` system for flood and malformed frame protection.
- **Resilient Lifecycle**: `Pre-ready` packet queueing prevents loading-phase data loss.

---

## Minimal Example

```luau
-- Define
local Net = Snap.define("Ping", { Signal = Snap.event(Snap.u8, "Reliable") })

-- Server
Snap.channel("Ping", Net).Signal:listen(print)

-- Client
Snap.channel("Ping", Net).Signal:send(1)
```

*Engineered for scale. Built for Roblox.*