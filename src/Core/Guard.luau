--!strict
--!native
--!optimize 2

local Settings = require(script.Parent.Parent.Settings)

export type PlayerGuardState = {
	windowStart: number,
	packetCount: number,
	invokeCount: number,
	byteCount: number,
	pendingInvokes: number,
	violations: number,
}

export type ViolationKind =
	"frameTooLarge"
	| "packetRate"
	| "invokeRate"
	| "pendingInvokes"
	| "malformedFrame"
	| "unknownPacket"

local GUARD = Settings.GUARD
local ENABLED = GUARD.ENABLED
local MAX_FRAME_BYTES = GUARD.MAX_FRAME_BYTES
local MAX_PACKETS_PER_SECOND = GUARD.MAX_PACKETS_PER_SECOND
local MAX_INVOKES_PER_SECOND = GUARD.MAX_INVOKES_PER_SECOND
local MAX_PENDING_INVOKES = GUARD.MAX_PENDING_INVOKES
local KICK_ON_REPEATED = GUARD.KICK_ON_REPEATED_VIOLATIONS
local VIOLATION_KICK_THRESHOLD = GUARD.VIOLATION_KICK_THRESHOLD

local Guard = {}

Guard.ENABLED = ENABLED
Guard.MAX_PENDING_INVOKES = MAX_PENDING_INVOKES

local function createState(): PlayerGuardState
	return {
		windowStart = os.clock(),
		packetCount = 0,
		invokeCount = 0,
		byteCount = 0,
		pendingInvokes = 0,
		violations = 0,
	}
end

Guard.createState = createState

local function maybeResetWindow(state: PlayerGuardState, now: number)
	if now - state.windowStart >= 1 then
		state.windowStart = now
		state.packetCount = 0
		state.invokeCount = 0
		state.byteCount = 0
	end
end

local function report(
	player: Player?,
	namespace: string,
	kind: ViolationKind,
	detail: string?,
	state: PlayerGuardState?
)
	local who = if player then player.Name else "local"
	warn(
		string.format(
			"[Snap][Guard] '%s' violation in '%s' from %s%s",
			kind,
			namespace,
			who,
			if detail then ": " .. detail else ""
		)
	)

	if not state then
		return
	end

	state.violations += 1

	if KICK_ON_REPEATED and player and state.violations >= VIOLATION_KICK_THRESHOLD then
		player:Kick(
			string.format(
				"[Snap] Network violations exceeded threshold (%d)",
				VIOLATION_KICK_THRESHOLD
			)
		)
	end
end

Guard.report = report

function Guard.checkFrame(
	state: PlayerGuardState,
	frame: any,
	player: Player?,
	namespace: string
): (boolean, number)
	if type(frame) ~= "buffer" then
		if not ENABLED then
			return true, 0
		end
		report(player, namespace, "malformedFrame", "non-buffer frame", state)
		return false, 0
	end

	local length = buffer.len(frame)

	if not ENABLED then
		return true, length
	end

	if length > MAX_FRAME_BYTES then
		report(
			player,
			namespace,
			"frameTooLarge",
			string.format("%d > %d", length, MAX_FRAME_BYTES),
			state
		)
		return false, length
	end

	local now = os.clock()
	if now - state.windowStart >= 1 then
		state.windowStart = now
		state.packetCount = 0
		state.invokeCount = 0
		state.byteCount = 0
	end

	state.byteCount += length

	return true, length
end

function Guard.accountPacket(
	state: PlayerGuardState,
	player: Player?,
	namespace: string
): boolean
	if not ENABLED then
		return true
	end

	state.packetCount += 1

	if state.packetCount > MAX_PACKETS_PER_SECOND then
		report(
			player,
			namespace,
			"packetRate",
			string.format(
				"%d > %d / s",
				state.packetCount,
				MAX_PACKETS_PER_SECOND
			),
			state
		)
		return false
	end

	return true
end

function Guard.accountInvoke(
	state: PlayerGuardState,
	player: Player?,
	namespace: string
): boolean
	if not ENABLED then
		return true
	end

	state.invokeCount += 1

	if state.invokeCount > MAX_INVOKES_PER_SECOND then
		report(
			player,
			namespace,
			"invokeRate",
			string.format(
				"%d > %d / s",
				state.invokeCount,
				MAX_INVOKES_PER_SECOND
			),
			state
		)
		return false
	end

	return true
end

function Guard.canAllocatePending(
	state: PlayerGuardState,
	player: Player?,
	namespace: string
): boolean
	if not ENABLED then
		return true
	end

	if state.pendingInvokes >= MAX_PENDING_INVOKES then
		report(
			player,
			namespace,
			"pendingInvokes",
			string.format(
				"%d >= %d",
				state.pendingInvokes,
				MAX_PENDING_INVOKES
			),
			state
		)
		return false
	end

	return true
end

return Guard
