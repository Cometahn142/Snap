# Tutorial: Implementation Guide

This tutorial covers the implementation of a structured combat and inventory system.

## 1. Defining Complex Structures

Snap provides `Snap.struct` and `Snap.array` to define nested data without the overhead of table serialization.

```luau
-- Shared/Protocol.luau
local Snap = require(Packages.Snap)

local ItemType = Snap.struct({
    Id = Snap.uint16,
    Count = Snap.uint8,
    Quality = Snap.uint8
})

return Snap.define("Game", {
    -- Sends an array of items (e.g., loot drop)
    LootDrop = Snap.event(Snap.array(ItemType), "Reliable"),
    
    -- Requesting character stats
    GetStats = Snap.request(Snap.none, Snap.struct({
        Level = Snap.uint16,
        XP = Snap.uint32,
        Health = Snap.float32
    }))
})
```

## 2. Server Logic: Handling Structured Data

The server binds the definition and processes incoming requests.

```luau
local Protocol = require(Shared.Protocol)
local Bridge = Snap.channel("Game", Protocol)

Bridge.GetStats:handle(function(player)
    return {
        Level = 50,
        XP = 12500,
        Health = 100.0
    }
end)

-- Dropping loot for a player
local loot = {
    { Id = 1, Count = 1, Quality = 100 },
    { Id = 5, Count = 10, Quality = 10 }
}
Bridge.LootDrop:sendTo(player, loot)
```

## 3. Client Logic: Receiving and Displaying

The client receives the data as a native table, decoded from the binary stream.

```luau
local Bridge = Snap.channel("Game", Protocol)

Bridge.LootDrop:listen(function(items)
    for _, item in items do
        print("Dropped Item ID:", item.Id, "Quality:", item.Quality)
    end
end)
```

## 4. Manual Serialization (Advanced)

If you need to store data in a database or external service, you can use Snap's internal serializers directly.

```luau
local buffer, refs = Snap.serialize(ItemType, { Id = 10, Count = 1, Quality = 50 })
-- 'buffer' contains the binary data, 'refs' contains any instance references.
```

---
[Next: Recipes](recipes.md)
