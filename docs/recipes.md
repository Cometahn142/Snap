# Recipes: High-Performance Patterns

Efficient solutions for complex Roblox networking scenarios.

## 1. Bit-level Flags (`Snap.bitarray`)

When you have many boolean toggles (e.g., Quest progress, Achievement unlocks), use `Snap.bitarray` to pack 8 flags into a single byte.

```luau
-- Definition
AchievementSync = Snap.event(Snap.bitarray, "Reliable")

-- Usage (Server)
local achievements = { true, false, true, true, false, false, false, true }
Bridge.AchievementSync:sendTo(player, achievements)
```

## 2. Dynamic Data Mapping (`Snap.map`)

Synchronize dictionaries where keys and values are of a specific type.

```luau
-- Definition
PriceUpdate = Snap.event(Snap.map(Snap.uint16, Snap.uint32), "Reliable")

-- Usage
local prices = {
    [101] = 500,
    [102] = 1200
}
Bridge.PriceUpdate:sendToAll(prices)
```

## 3. Handling Nullable Values (`Snap.optional`)

Use `Snap.optional` to handle fields that may be `nil` without breaking the serialization.

```luau
-- Definition
UpdateTarget = Snap.event(Snap.optional(Snap.ref), "Reliable")

-- Usage
Bridge.UpdateTarget:sendTo(player, workspace.Enemy) -- Sends instance
Bridge.UpdateTarget:sendTo(player, nil)             -- Sends null flag (1 byte)
```

## 4. Performance: Early Flush vs. Batching

By default, Snap waits for the end of the frame. For high-latency-sensitive actions (like a parry or dodge), you can force a flush.

```luau
Bridge.ParrySuccessful:send(1.0)

-- Snap.Settings.EARLY_FLUSH_ENABLED must be true in Settings.luau
-- Or call it manually:
Snap.Server.requestEarlyFlush() 
```

## 5. Security: Handling Violations

The `Guard` system provides hooks to detect and log malicious activity.

```luau
-- In your server init
game:GetService("LogService").MessageOut:Connect(function(message, messageType)
    if message:find("[Snap][Guard]") then
        -- Handle/log violation
    end
end)
```

---
[Next: Specification](specification.md)
