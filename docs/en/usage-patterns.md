# Usage Patterns

This guide illustrates proper communication conventions and advanced zero-allocation pooling workflows.

## Defining the Network Contract

Place definitions in a shared path accessible to both peers.

```luau
-- ReplicatedStorage/Network.luau
local Snap = require(game:GetService("ReplicatedStorage").Packages.Snap)

local CombatChannel = Snap.channel("Combat", {
	Strike = Snap.event(Snap.struct({
		targetId = Snap.uint32,
		damage = Snap.uint16,
	}), "Unreliable"),

	RequestHeal = Snap.request(
		Snap.uint32, -- Required mana
		Snap.bool    -- Success status
	),
})

return CombatChannel
```

## Event Transmission

Events facilitate high-throughput synchronization loops.

### Client to Server
```luau
local CombatChannel = require(ReplicatedStorage.Network)

CombatChannel.Strike:send({
	targetId = 9921,
	damage = 25,
})
```

### Server to Client
```luau
local CombatChannel = require(ReplicatedStorage.Network)

CombatChannel.Strike:listen(function(player: Player, data)
	print(`{player.Name} executed a strike. Damage: {data.damage}`)
end)
```

## Bidirectional RPC (Requests)

Requests block thread progression safely via coroutine yields.

### Client Execution
```luau
task.spawn(function()
	local success, result = CombatChannel.RequestHeal:request(50)
	if success then
		print("Heal executed:", result)
	end
end)
```

### Server Execution
```luau
CombatChannel.RequestHeal:handle(function(player: Player, mana: number): boolean
	if player:GetAttribute("Mana") >= mana then
		player:SetAttribute("Mana", player:GetAttribute("Mana") - mana)
		return true
	end
	return false
end)
```

## In-Place Data Mutability (Pooling)

Avoid continuous table reconstruction inside game loops by implementing explicit pooling:

```luau
local VectorSchema = Snap.struct({ x = Snap.float32, y = Snap.float32 })
local cachedOutput = { x = 0, y = 0 }

-- Executes without triggering Garbage Collection spikes
local result, nextOffset = VectorSchema.read(sourceBuffer, 0, cachedOutput)
```
