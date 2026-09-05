local _, UUF = ...

local OriginalUpdateRangeAlpha = UUF.UpdateRangeAlpha
local playerClass = select(2, UnitClass("player"))

local GROUP_FRIENDLY_SPELL_BY_CLASS = {
	EVOKER = 361469,
	ROGUE = 36554,
}

local GROUP_REZ_SPELL_BY_CLASS = {
	DRUID = 20484,
	PRIEST = 2006,
	PALADIN = 461622,
	SHAMAN = 2008,
	MONK = 115178,
	DEATHKNIGHT = 61999,
	WARLOCK = 20707,
	EVOKER = 361227,
}

local groupFriendlySpell = GROUP_FRIENDLY_SPELL_BY_CLASS[playerClass]
local groupRezSpell = GROUP_REZ_SPELL_BY_CLASS[playerClass]

local function IsGroupRangeUnit(unit)
	return type(unit) == "string" and (unit:match("^party%d+$") ~= nil or unit:match("^raid%d+$") ~= nil)
end

local function ApplyBoolean(frame, value, inAlpha, outAlpha)
	if UUF:IsSecretValue(value) then
		frame:SetAlphaFromBoolean(value, inAlpha, outAlpha)
		return
	end
	frame:SetAlpha(value and inAlpha or outAlpha)
end

local function ApplyNativeGroupRange(frame, unit, inAlpha, outAlpha)
	local inRange, checked = UnitInRange(unit)

	-- Match EllesmereUI's conservative handling: only trust UnitInRange when
	-- BOTH values are readable and Blizzard confirms the check was valid.
	-- A secret inRange value can still represent an unchecked result, so feeding
	-- it straight into SetAlphaFromBoolean can leave a nearby member faded.
	if not UUF:IsSecretValue(inRange) and not UUF:IsSecretValue(checked) and checked then
		frame:SetAlpha(inRange and inAlpha or outAlpha)
		return
	end

	-- Secret or uncheckable UnitInRange result: fall back to visibility. This is
	-- coarser than cast range, but avoids false out-of-range fades during the
	-- restricted/secret state seen in party instances. If visibility itself is
	-- secret, fail open to in-range rather than dimming a potentially nearby unit.
	local visible = UnitIsVisible(unit)
	if UUF:IsSecretValue(visible) then
		frame:SetAlpha(inAlpha)
		return
	end
	frame:SetAlpha(visible and inAlpha or outAlpha)
end

local function UpdateGroupRangeAlpha(frame, unit, inAlpha, outAlpha)
	if not unit or not UnitExists(unit) or unit == "player" then
		frame:SetAlpha(inAlpha)
		return
	end

	if UnitPhaseReason and UnitPhaseReason(unit) then
		frame:SetAlpha(outAlpha)
		return
	end

	local connected = UnitIsConnected(unit)
	if not UUF:IsSecretValue(connected) and connected == false then
		frame:SetAlpha(outAlpha)
		return
	end

	if UnitIsDeadOrGhost(unit) then
		if groupRezSpell and C_Spell and C_Spell.IsSpellInRange then
			local rezRange = C_Spell.IsSpellInRange(groupRezSpell, unit)
			if UUF:IsSecretValue(rezRange) then
				frame:SetAlphaFromBoolean(rezRange, inAlpha, outAlpha)
				return
			elseif rezRange ~= nil then
				frame:SetAlpha(rezRange and inAlpha or outAlpha)
				return
			end
		end
		ApplyNativeGroupRange(frame, unit, inAlpha, outAlpha)
		return
	end

	if groupFriendlySpell and C_Spell and C_Spell.IsSpellInRange then
		local spellRange = C_Spell.IsSpellInRange(groupFriendlySpell, unit)
		if UUF:IsSecretValue(spellRange) then
			frame:SetAlphaFromBoolean(spellRange, inAlpha, outAlpha)
			return
		elseif spellRange ~= nil then
			frame:SetAlpha(spellRange and inAlpha or outAlpha)
			return
		end
	end

	ApplyNativeGroupRange(frame, unit, inAlpha, outAlpha)
end

function UUF:UpdateRangeAlpha(frame, unit)
	if not IsGroupRangeUnit(unit) then
		return OriginalUpdateRangeAlpha(self, frame, unit)
	end

	local RangeDB = UUF.db and UUF.db.profile and UUF.db.profile.General and UUF.db.profile.General.Range
	if not RangeDB or not RangeDB.Enabled then
		frame:SetAlpha(1)
		return
	end

	local inAlpha = RangeDB.InRange or 1
	local outAlpha = RangeDB.OutOfRange or 0.5
	UpdateGroupRangeAlpha(frame, unit, inAlpha, outAlpha)
end

local refreshGeneration = 0
local function RefreshRegisteredGroupFrames()
	for unit, frames in pairs(UUF.RangeEvtFrames or {}) do
		if IsGroupRangeUnit(unit) then
			for frame in pairs(frames) do
				if frame and frame:IsVisible() then UUF:UpdateRangeAlpha(frame, unit) end
			end
		end
	end
end

local function QueueGroupRangeSettle()
	refreshGeneration = refreshGeneration + 1
	local generation = refreshGeneration
	for _, delay in ipairs({0, 0.25, 1.0}) do
		C_Timer.After(delay, function()
			if generation ~= refreshGeneration then return end
			RefreshRegisteredGroupFrames()
		end)
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", QueueGroupRangeSettle)
