local _, UUF = ...

local playerClass = select(2, UnitClass("player"))
local GROUP_FRIENDLY_SPELL_BY_CLASS = {
	EVOKER = 361469,
	ROGUE = 36554,
}

local groupFriendlySpell = GROUP_FRIENDLY_SPELL_BY_CLASS[playerClass]

local function Describe(value)
	if UUF:IsSecretValue(value) then return "<secret>" end
	if value == nil then return "nil" end
	return tostring(value)
end

local function SafeUnitName(unit)
	local name = UnitName(unit)
	if UUF:IsSecretValue(name) then return "<secret-name>" end
	return name or "?"
end

SLASH_UUFRANGECHECK1 = "/uufrangecheck"
SlashCmdList["UUFRANGECHECK"] = function()
	local RangeDB = UUF.db and UUF.db.profile and UUF.db.profile.General and UUF.db.profile.General.Range
	UUF:PrettyPrint(string.format(
		"|cFF78DCE8RangeCheck|r enabled=%s inAlpha=%s outAlpha=%s class=%s spell=%s",
		Describe(RangeDB and RangeDB.Enabled),
		Describe(RangeDB and RangeDB.InRange),
		Describe(RangeDB and RangeDB.OutOfRange),
		Describe(playerClass),
		Describe(groupFriendlySpell)
	))

	for index = 1, UUF.MAX_PARTY_FRAMES do
		local unit = "party" .. index
		local frame = UUF["PARTY" .. index]
		if frame and UnitExists(unit) then
			local inRange, checked = UnitInRange(unit)
			local visible = UnitIsVisible(unit)
			local phase = UnitPhaseReason and UnitPhaseReason(unit)
			local connected = UnitIsConnected(unit)
			local dead = UnitIsDeadOrGhost(unit)
			local spellRange
			if groupFriendlySpell and C_Spell and C_Spell.IsSpellInRange then
				spellRange = C_Spell.IsSpellInRange(groupFriendlySpell, unit)
			end

			local registered = UUF.RangeEvtFrames
				and UUF.RangeEvtFrames[unit]
				and UUF.RangeEvtFrames[unit][frame]
				and true or false

			UUF:PrettyPrint(string.format(
				"|cFF78DCE8RangeCheck|r %s %s alpha=%.3f reg=%s bound=%s | UnitInRange=%s checked=%s visible=%s phase=%s connected=%s dead=%s spellRange=%s",
				unit,
				SafeUnitName(unit),
				frame:GetAlpha() or -1,
				Describe(registered),
				Describe(frame.UUFRangeUnit),
				Describe(inRange),
				Describe(checked),
				Describe(visible),
				Describe(phase),
				Describe(connected),
				Describe(dead),
				Describe(spellRange)
			))
		end
	end
end
