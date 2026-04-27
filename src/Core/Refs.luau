--!strict
--!native
--!optimize 2

export type RefList = { any }

local Refs = {}

local MAX_REFS_PER_FRAME = 255

Refs.MAX_REFS_PER_FRAME = MAX_REFS_PER_FRAME

local currentWriteList: RefList? = nil
local currentWriteLookup: { [any]: number } | nil = nil
local currentRead: RefList? = nil

function Refs.beginWrite(list: RefList, lookup: { [any]: number })
	currentWriteList = list
	currentWriteLookup = lookup
end

function Refs.endWrite()
	currentWriteList = nil
	currentWriteLookup = nil
end

function Refs.push(value: any): number
	local list = currentWriteList
	local lookup = currentWriteLookup
	if not list or not lookup then
		error("[Snap] Refs.push called outside of write context", 2)
	end

	local existing = lookup[value]
	if existing then
		return existing
	end

	local index = #list + 1
	if index > MAX_REFS_PER_FRAME then
		error(
			string.format(
				"[Snap] Reference limit exceeded (%d per frame)",
				MAX_REFS_PER_FRAME
			),
			2
		)
	end

	list[index] = value
	lookup[value] = index
	return index
end

function Refs.beginRead(list: RefList?)
	currentRead = list
end

function Refs.endRead()
	currentRead = nil
end

function Refs.get(index: number): any
	local list = currentRead
	if not list then
		return nil
	end
	return list[index]
end

return Refs





