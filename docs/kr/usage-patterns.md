# 사용 패턴 (Usage Patterns)

이 가이드는 올바른 통신 규칙과 고급 제로 할당(Zero-allocation) 풀링 워크플로우를 설명합니다.

## 네트워크 계약 정의

서버와 클라이언트 모두 접근 가능한 공유 경로에 정의를 배치합니다.

```luau
-- ReplicatedStorage/Network.luau
local Snap = require(game:GetService("ReplicatedStorage").Packages.Snap)

local CombatChannel = Snap.channel("Combat", {
	Strike = Snap.event(Snap.struct({
		targetId = Snap.uint32,
		damage = Snap.uint16,
	}), "Unreliable"),

	RequestHeal = Snap.request(
		Snap.uint32, -- 필요한 마나
		Snap.bool    -- 성공 여부
	),
})

return CombatChannel
```

## 이벤트 전송

이벤트는 처리량이 높은 동기화 루프를 지원합니다.

### 클라이언트에서 서버로
```luau
local CombatChannel = require(ReplicatedStorage.Network)

CombatChannel.Strike:send({
	targetId = 9921,
	damage = 25,
})
```

### 서버에서 클라이언트로
```luau
local CombatChannel = require(ReplicatedStorage.Network)

CombatChannel.Strike:listen(function(player: Player, data)
	print(`{player.Name} 가 공격을 수행했습니다. 데미지: {data.damage}`)
end)
```

## 양방향 RPC (요청)

요청은 코루틴 Yield를 통해 스레드 진행을 안전하게 차단(Block)합니다.

### 클라이언트 실행
```luau
task.spawn(function()
	local success, result = CombatChannel.RequestHeal:request(50)
	if success then
		print("치유 실행됨:", result)
	end
end)
```

### 서버 실행
```luau
CombatChannel.RequestHeal:handle(function(player: Player, mana: number): boolean
	if player:GetAttribute("Mana") >= mana then
		player:SetAttribute("Mana", player:GetAttribute("Mana") - mana)
		return true
	end
	return false
end)
```

## 내부 데이터 가변성 (풀링)

명시적 풀링을 구현하여 게임 루프 내에서 지속적인 테이블 재구성을 방지합니다:

```luau
local VectorSchema = Snap.struct({ x = Snap.float32, y = Snap.float32 })
local cachedOutput = { x = 0, y = 0 }

-- 가비지 컬렉션(GC) 스파이크를 발생시키지 않고 실행됩니다.
local result, nextOffset = VectorSchema.read(sourceBuffer, 0, cachedOutput)
```
