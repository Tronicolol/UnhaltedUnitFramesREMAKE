local _, UUF = ...
local oUF = UUF.oUF

local TypedDebuffTypes = {
	Magic = oUF.Enum.DispelType.Magic,
	Curse = oUF.Enum.DispelType.Curse,
	Disease = oUF.Enum.DispelType.Disease,
	Poison = oUF.Enum.DispelType.Poison,
	Bleed = oUF.Enum.DispelType.Bleed,
}

local TypedDebuffColorCurve = C_CurveUtil.CreateColorCurve()
TypedDebuffColorCurve:SetType(Enum.LuaCurveType.Step)
for _, dispelIndex in pairs(TypedDebuffTypes) do
	local color = oUF.colors.dispel[dispelIndex]
	if color then TypedDebuffColorCurve:AddPoint(dispelIndex, color) end
end

local function StyleAuras(_, button, unit, auraType, restyle, auraDB)
	if not button or not unit or not auraType then return end
	local unitFrame = button:GetParent() and button:GetParent():GetParent()
	local AurasDB = UUF:GetUnitDB(unitFrame, unit).Auras
	if not AurasDB then return end
	local AuraDB = auraDB and AurasDB[auraDB] or auraType == "HELPFUL" and AurasDB.Buffs or AurasDB.Debuffs
	if not AuraDB then return end

	if not restyle then
		local buttonBorder = CreateFrame("Frame", nil, button, "BackdropTemplate")
		buttonBorder:SetAllPoints()
		buttonBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1, insets = {left = 0, right = 0, top = 0, bottom = 0} })
		buttonBorder:SetBackdropBorderColor(0, 0, 0, 1)
	end

	if button.Icon then button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
	if button.Cooldown then
		button.Cooldown:SetDrawEdge(false)
		button.Cooldown:SetReverse(true)
		UUF:ApplyCooldownText(button.Cooldown, nil, unit, unitFrame)
	end
	if button.Count then
		if AuraDB.Count.HideStacks then
			button.Count:Hide()
		else
			local FontsDB = UUF.db.profile.General.Fonts
			button.Count:ClearAllPoints()
			button.Count:SetFont(UUF.Media.Font, AuraDB.Count.FontSize, FontsDB.FontFlag)
			button.Count:SetPoint(AuraDB.Count.Layout[1], button, AuraDB.Count.Layout[2], AuraDB.Count.Layout[3], AuraDB.Count.Layout[4])
			if FontsDB.Shadow.Enabled then
				button.Count:SetShadowColor(FontsDB.Shadow.Colour[1], FontsDB.Shadow.Colour[2], FontsDB.Shadow.Colour[3], FontsDB.Shadow.Colour[4])
				button.Count:SetShadowOffset(FontsDB.Shadow.XPos, FontsDB.Shadow.YPos)
			else
				button.Count:SetShadowColor(0, 0, 0, 0)
				button.Count:SetShadowOffset(0, 0)
			end
			button.Count:SetTextColor(unpack(AuraDB.Count.Colour))
			button.Count:Show()
		end
	end
	if not restyle and button.Overlay then
		button.Overlay:SetTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\AuraOverlay.png")
		button.Overlay:ClearAllPoints()
		button.Overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
		button.Overlay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		button.Overlay:SetTexCoord(0, 1, 0, 1)
	end
end


-- Midnight 12.1 compatibility for Player/Target/Boss auras.
-- Blizzard can make aura payloads secret in combat, so these units use the
-- native AuraContainer instead of the legacy oUF UNIT_AURA/GetAuraSlots path.
local managedAuraSupport
local ManagedAuraDurationFormatter = C_StringUtil.CreateNumericRuleFormatter()

local function RefreshManagedAuraDurationFormatter()
	local CooldownTextDB = UUF.db.profile.General.CooldownText
	for _, breakpoint in ipairs(CooldownTextDB.CooldownBreakpoints) do
		if breakpoint.displayStyle == "secondsOnly" then breakpoint.min = 1 end
	end
	ManagedAuraDurationFormatter:SetBreakpoints(CooldownTextDB.CooldownBreakpoints)
end

local function UsesMidnightManagedAuras(unit)
	if type(unit) ~= "string" then return false end
	if unit == "party" or unit == "partyplayer" then return true end
	if unit:match("^boss%d+$") or unit:match("^party%d+$") or unit:match("^raid%d+$") then return true end
	return unit == "player"
		or unit == "target"
		or unit == "targettarget"
		or unit == "pet"
		or unit == "focus"
		or unit == "focustarget"
end

local function GetManagedAuraUnitToken(unitFrame, unit)
	if unit == "partyplayer" then return "player" end
	if unit == "party" then
		local frameUnit = unitFrame and unitFrame.unit
		if not frameUnit and unitFrame and unitFrame.GetAttribute then
			frameUnit = unitFrame:GetAttribute("unit")
		end
		if frameUnit == "player" or (type(frameUnit) == "string" and frameUnit:match("^party%d+$")) then
			return frameUnit
		end
	end
	return unit
end

-- Group configuration reuses the live Party/Raid/Boss frames with their secure
-- unit attribute cleared. Real AuraContainers must stay fully suspended for the
-- whole preview session; hiding them only from CreateTestAuras is not enough,
-- because other GUI refresh paths can call UpdateUnitAuras afterwards.
local function IsGroupAuraPreviewActive(unitFrame, unit)
	if unitFrame and unitFrame.UUFTestModeActive then return true end
	if type(unit) ~= "string" then return false end

	if (unit == "party" or unit == "partyplayer" or unit:match("^party%d+$")) and UUF.PARTY_TEST_MODE then
		return true
	end
	if (unit == "raid" or unit:match("^raid%d+$")) and UUF.RAID_TEST_MODE then
		return true
	end
	if unit:match("^boss%d*$") and UUF.BOSS_TEST_MODE then
		return true
	end

	return false
end

local function SuspendRealAurasForGroupPreview(unitFrame)
	if not unitFrame then return end

	local function SuspendManaged(container)
		if not container then return end
		if container.SetEnabled then pcall(container.SetEnabled, container, false) end
		pcall(container.Hide, container)
	end

	SuspendManaged(unitFrame.UUFManagedTargetBuffs)
	SuspendManaged(unitFrame.UUFManagedTargetDebuffs)
	SuspendManaged(unitFrame.UUFManagedTargetDebuffsClip)
	SuspendManaged(unitFrame.UUFManagedPartyRaidCustomAuras)

	if unitFrame:IsElementEnabled("Auras") then unitFrame:DisableElement("Auras") end
	if unitFrame:IsElementEnabled("CustomAuras") then unitFrame:DisableElement("CustomAuras") end

	-- When the explicit aura-preview toggle is OFF, hide legacy containers too.
	-- When it is ON, CreateTestAuras owns these containers and paints fake icons.
	if not UUF.AURA_TEST_MODE then
		if unitFrame.BuffContainer then unitFrame.BuffContainer:Hide() end
		if unitFrame.DebuffContainer then unitFrame.DebuffContainer:Hide() end
		if unitFrame.CustomAuraContainer then unitFrame.CustomAuraContainer:Hide() end
	end

	if unitFrame.PrivateAuraContainer then unitFrame.PrivateAuraContainer:Hide() end
end

-- Party/Raid managed aura safety. Blizzard can stop delivering reliable aura
-- information for group units that are disconnected, phased, or outside local
-- render visibility. Keep the managed containers parked on the engine's null
-- unit while that data is unavailable so stale/degraded aura results can never
-- remain visible. A lightweight roster/visibility sweep restores and reparses
-- them when the unit becomes observable again.
local GROUP_AURA_NO_UNIT = "none"

local function GetManagedGroupAuraToken(unitFrame, unit)
	local token = GetManagedAuraUnitToken(unitFrame, unit)
	if token == "player" and (unit == "party" or unit == "partyplayer") then return token end
	if type(token) == "string" and (token:match("^party%d+$") or token:match("^raid%d+$")) then
		return token
	end
end

local function IsManagedGroupAuraUnitObservable(unit)
	if type(unit) ~= "string" then return false end

	local okExists, exists = pcall(UnitExists, unit)
	if not okExists or UUF:IsSecretValue(exists) or not exists then return false end

	-- The local player is always safe to keep bound in the Party "show player" slot.
	local okSelf, isSelf = pcall(UnitIsUnit, unit, "player")
	if okSelf and not UUF:IsSecretValue(isSelf) and isSelf then return true end

	local okConnected, connected = pcall(UnitIsConnected, unit)
	if not okConnected or UUF:IsSecretValue(connected) or connected == false then return false end

	local okVisible, visible = pcall(UnitIsVisible, unit)
	if not okVisible or UUF:IsSecretValue(visible) or visible == false then return false end

	if UnitPhaseReason then
		local okPhase, phaseReason = pcall(UnitPhaseReason, unit)
		if not okPhase or UUF:IsSecretValue(phaseReason) then return false end
		if phaseReason then return false end
	end

	return true
end

local function ParkManagedGroupAuraContainers(unitFrame)
	if not unitFrame then return end

	local function Park(container)
		if not container then return end
		if container.SetEnabled then pcall(container.SetEnabled, container, false) end
		if container.SetUnit then pcall(container.SetUnit, container, GROUP_AURA_NO_UNIT) end
		pcall(container.Hide, container)
	end

	Park(unitFrame.UUFManagedTargetBuffs)
	Park(unitFrame.UUFManagedTargetDebuffs)
	Park(unitFrame.UUFManagedPartyRaidCustomAuras)
	if unitFrame.UUFManagedTargetDebuffsClip then pcall(unitFrame.UUFManagedTargetDebuffsClip.Hide, unitFrame.UUFManagedTargetDebuffsClip) end
end

local function IsBossManagedAuraUnit(unit)
	return type(unit) == "string" and unit:match("^boss%d+$") ~= nil
end

local function GetBossPandemicSettings(DebuffsDB)
	DebuffsDB.PandemicGlow = DebuffsDB.PandemicGlow or {}
	local settings = DebuffsDB.PandemicGlow

	if settings.Enabled == nil then settings.Enabled = false end

	local legacyTypes = {
		BLIZZARD = "BUTTON",
		BORDER = "BUTTON",
		PULSE = "BUTTON",
		TRIPLE = "PROC",
	}
	settings.Type = legacyTypes[settings.Type] or settings.Type or "BUTTON"

	local validTypes = {
		PIXEL = true,
		AUTOCAST = true,
		BUTTON = true,
		PROC = true,
	}
	if not validTypes[settings.Type] then settings.Type = "BUTTON" end

	if type(settings.Colour) ~= "table" then settings.Colour = {1, 0.82, 0, 1} end
	for index = 1, 4 do
		if type(settings.Colour[index]) ~= "number" then
			settings.Colour[index] = index == 2 and 0.82 or (index == 3 and 0 or 1)
		end
	end

	return settings
end

local function GetBossDebuffFilterSettings(DebuffsDB)
	DebuffsDB.BossDebuffFilter = DebuffsDB.BossDebuffFilter or {}
	local settings = DebuffsDB.BossDebuffFilter

	-- Boss debuffs use a source-focused model:
	--   * OnlyMyDebuffs ON: every displayed debuff must be player-applied.
	--   * OnlyWhitelist ON: every displayed debuff must be whitelisted.
	--   * Both ON: intersection -> only player-applied debuffs that are whitelisted.
	--   * Both OFF: player-applied debuffs + whitelist exceptions.
	-- Keep the hidden legacy OnlyShowPlayer value aligned so fallback paths
	-- never broaden the Boss debuff pool unexpectedly.
	DebuffsDB.OnlyShowPlayer = true

	if settings.OnlyMyDebuffs == nil then
		settings.OnlyMyDebuffs = false
	end
	if settings.OnlyWhitelist == nil then
		local previous = DebuffsDB.PandemicGlow
		settings.OnlyWhitelist = previous and previous.OnlyWhitelist == true or false
	end
	if settings.Whitelist == nil then
		local previous = DebuffsDB.PandemicGlow
		settings.Whitelist = previous and previous.Whitelist or ""
	end
	if settings.Blacklist == nil then
		local previous = DebuffsDB.PandemicGlow
		settings.Blacklist = previous and previous.Blacklist or ""
	end
	if type(settings.Whitelist) ~= "string" then settings.Whitelist = "" end
	if type(settings.Blacklist) ~= "string" then settings.Blacklist = "" end

	return settings
end

local function ParsePandemicSpellIDs(value)
	local spellIDs = {}
	local ordered = {}

	for token in tostring(value or ""):gmatch("%d+") do
		local spellID = tonumber(token)
		if spellID and spellID > 0 and not spellIDs[spellID] then
			spellIDs[spellID] = true
			ordered[#ordered + 1] = spellID
		end
	end

	table.sort(ordered)
	return spellIDs, ordered
end

local function PandemicSpellIDSignature(value)
	local _, ordered = ParsePandemicSpellIDs(value)
	for index, spellID in ipairs(ordered) do
		ordered[index] = tostring(spellID)
	end
	return table.concat(ordered, ",")
end


local ManagedTypedDispelTypes = {
	Magic = true,
	Curse = true,
	Disease = true,
	Poison = true,
	Bleed = true,
}

local function IsUnifiedManagedAuraUnit(unitFrame, unit)
	if unitFrame and unitFrame.isAugmentationRaidFrame then return true end
	if unit == "party" or unit == "partyplayer" then return true end
	if type(unit) ~= "string" then return false end
	if unit:match("^party%d+$") or unit:match("^raid%d+$") then return true end
	-- Boss keeps its dedicated debuff filtering/pandemic path.
	if unit:match("^boss%d+$") then return false end
	return unit == "player"
		or unit == "target"
		or unit == "targettarget"
		or unit == "pet"
		or unit == "focus"
		or unit == "focustarget"
end

local function IsEnemyDebuffFilterUnit(unit)
	return unit == "target"
		or unit == "targettarget"
		or unit == "focus"
		or unit == "focustarget"
end

local function GetEnemyDebuffFilterSettings(DebuffsDB)
	DebuffsDB.EnemyDebuffFilter = DebuffsDB.EnemyDebuffFilter or {}
	local settings = DebuffsDB.EnemyDebuffFilter

	-- Enemy-oriented frames use the same source semantics as Boss debuffs:
	--   * OnlyMyDebuffs ON: every displayed debuff must be player-applied.
	--   * OnlyWhitelist ON: every displayed debuff must be whitelisted.
	--   * Both ON: intersection -> only player-applied + whitelisted debuffs.
	--   * Both OFF: player-applied debuffs + whitelist exceptions from any source.
	-- Default OnlyMyDebuffs to true because these frames are primarily used to
	-- track the player's own offensive debuffs.
	if settings.OnlyMyDebuffs == nil then settings.OnlyMyDebuffs = true end
	if settings.OnlyWhitelist == nil then settings.OnlyWhitelist = false end

	return settings
end

local function NormalizeUnifiedAuraFilterSettings(AuraDB)
	if not AuraDB then return end
	AuraDB.Filters = AuraDB.Filters or {}

	-- Migrate the old per-frame filter model the first time this profile uses the
	-- managed filter engine. Existing advanced selections keep working, and the old
	-- "Only Show Player" shortcut becomes the equivalent Player=All selection.
	if AuraDB.UseBlizzardCategoryFilters == nil then
		local hadAdvancedSelection = false
		for _, enabled in pairs(AuraDB.Filters) do
			if enabled == true then
				hadAdvancedSelection = true
				break
			end
		end
		if AuraDB.OnlyShowPlayer == true then
			-- The legacy shortcut overrode every advanced filter. Preserve that exact
			-- behavior on migration instead of accidentally keeping old Others rules.
			AuraDB.Filters = { Player = true }
			hadAdvancedSelection = true
		end
		AuraDB.UseBlizzardCategoryFilters = hadAdvancedSelection
	end

	if type(AuraDB.Whitelist) ~= "string" then AuraDB.Whitelist = "" end
	-- Source filtering is now represented by the Player/Others dropdowns.
	AuraDB.OnlyShowPlayer = false
	-- Old profiles may still contain the removed boolean legacy blacklist.
	if type(AuraDB.Blacklist) ~= "string" then AuraDB.Blacklist = "" end
end

local function CopySpellIDMap(source)
	local copy = {}
	for spellID in pairs(source or {}) do copy[spellID] = true end
	return copy
end

local function MergeSpellIDMaps(first, second)
	local merged = CopySpellIDMap(first)
	for spellID in pairs(second or {}) do merged[spellID] = true end
	return merged
end

local function HasSpellIDs(map)
	return map and next(map) ~= nil
end

local function BuildCandidateFilters(includeSpellIDs, excludeSpellIDs, includeDispelTypes)
	local filters
	if HasSpellIDs(includeSpellIDs) or HasSpellIDs(excludeSpellIDs) or includeDispelTypes then
		filters = {}
		if HasSpellIDs(includeSpellIDs) then filters.includeSpellIDs = includeSpellIDs end
		if HasSpellIDs(excludeSpellIDs) then filters.excludeSpellIDs = excludeSpellIDs end
		if includeDispelTypes then filters.includeDispelTypes = includeDispelTypes end
	end
	return filters
end

local function PartyRaidAuraFilterSignature(AuraDB)
	NormalizeUnifiedAuraFilterSettings(AuraDB)
	local parts = {
		tostring(AuraDB.UseBlizzardCategoryFilters == true),
		PandemicSpellIDSignature(AuraDB.Whitelist),
		PandemicSpellIDSignature(AuraDB.Blacklist),
	}

	local keys = {}
	for key in pairs(AuraDB.Filters or {}) do keys[#keys + 1] = key end
	table.sort(keys)
	for _, key in ipairs(keys) do
		parts[#parts + 1] = key .. "=" .. tostring(AuraDB.Filters[key] == true)
	end
	return table.concat(parts, ";")
end

local PartyRaidPlayerFilterClasses = {
	{ key = "CrowdControlPlayer", token = "CROWD_CONTROL" },
	{ key = "BigDefensivePlayer", token = "BIG_DEFENSIVE" },
	{ key = "ExternalDefensivePlayer", token = "EXTERNAL_DEFENSIVE" },
	{ key = "RaidInCombatPlayer", token = "RAID_IN_COMBAT" },
	{ key = "CancelablePlayer", token = "CANCELABLE", negate = "!CANCELABLE" },
	{ key = "NotCancelablePlayer", token = "!CANCELABLE", negate = "CANCELABLE" },
	{ key = "RaidPlayer", token = "RAID" },
}

local PartyRaidOtherFilterClasses = {
	{ key = "CrowdControl", token = "CROWD_CONTROL" },
	{ key = "BigDefensive", token = "BIG_DEFENSIVE" },
	{ key = "ExternalDefensive", token = "EXTERNAL_DEFENSIVE" },
	{ key = "RaidInCombat", token = "RAID_IN_COMBAT" },
	{ key = "Cancelable", token = "CANCELABLE", negate = "!CANCELABLE" },
	{ key = "NotCancelable", token = "!CANCELABLE", negate = "CANCELABLE" },
	{ key = "Raid", token = "RAID" },
}

local function InvertAuraFilterToken(token)
	if not token or token == "" then return nil end
	return token:sub(1, 1) == "!" and token:sub(2) or "!" .. token
end

-- Party/Raid Custom acts as an extraction layer, matching Blizzard's raid-frame
-- treatment of special aura groups: dropdown categories selected in Custom are
-- removed from the normal Buffs/Debuffs pool for that same aura source.
-- This intentionally applies only to the Player/Others Blizzard-category
-- dropdowns. Custom's own manual Whitelist/Blacklist IDs do not extract from
-- the normal container; category placement does, and therefore wins there.
local function GetPartyRaidCustomCategoryExtraction(CustomDB, auraType)
	local extraction = {
		Player = { all = false, excludeTokens = {} },
		Others = { all = false, excludeTokens = {} },
	}

	if not CustomDB or CustomDB.Enabled ~= true then return extraction end
	local customAuraType = CustomDB.Type == "Debuffs" and "HARMFUL" or "HELPFUL"
	if customAuraType ~= auraType then return extraction end

	NormalizeUnifiedAuraFilterSettings(CustomDB)
	if CustomDB.UseBlizzardCategoryFilters ~= true then return extraction end

	local filters = CustomDB.Filters or {}
	extraction.Player.all = filters.Player == true
	extraction.Others.all = filters.Others == true

	local function Collect(source, classes)
		local seen = {}
		for _, class in ipairs(classes) do
			if filters[class.key] then
				local exclusion = class.negate or InvertAuraFilterToken(class.token)
				if exclusion and not seen[exclusion] then
					seen[exclusion] = true
					source.excludeTokens[#source.excludeTokens + 1] = exclusion
				end
			end
		end
	end

	Collect(extraction.Player, PartyRaidPlayerFilterClasses)
	Collect(extraction.Others, PartyRaidOtherFilterClasses)
	return extraction
end

local function PartyRaidCustomCategoryExtractionSignature(CustomDB, auraType)
	local extraction = GetPartyRaidCustomCategoryExtraction(CustomDB, auraType)
	return table.concat({
		tostring(extraction.Player.all),
		table.concat(extraction.Player.excludeTokens, ","),
		tostring(extraction.Others.all),
		table.concat(extraction.Others.excludeTokens, ","),
	}, ";")
end

local function AppendFilterToken(parts, token)
	if token and token ~= "" then parts[#parts + 1] = token end
end

local function BuildPartyRaidAuraGroups(AuraDB, auraType, CustomDB)
	NormalizeUnifiedAuraFilterSettings(AuraDB)
	local filters = AuraDB.Filters or {}
	local whitelistMap = ParsePandemicSpellIDs(AuraDB.Whitelist)
	local blacklistMap = ParsePandemicSpellIDs(AuraDB.Blacklist)
	local effectiveWhitelistMap = CopySpellIDMap(whitelistMap)
	for spellID in pairs(blacklistMap) do effectiveWhitelistMap[spellID] = nil end
	local hasWhitelist = HasSpellIDs(effectiveWhitelistMap)
	local categoryMode = AuraDB.UseBlizzardCategoryFilters == true
	local customExtraction = GetPartyRaidCustomCategoryExtraction(CustomDB, auraType)
	local groups = {}
	local seenGroups = {}

	-- Party/Raid performance matters much more than saving a few instructions
	-- while building the configuration. Keep one AuraGroup for each *distinct*
	-- Blizzard query, because every AddAuraGroup owns a separate frame provider
	-- and every aura update is evaluated against every registered group.
	local function StableTableSignature(value)
		if type(value) ~= "table" then return tostring(value) end
		local keys = {}
		for key in pairs(value) do keys[#keys + 1] = key end
		table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
		local parts = {}
		for _, key in ipairs(keys) do
			parts[#parts + 1] = tostring(key) .. "=" .. StableTableSignature(value[key])
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end

	local function AddGroup(key, filterString, candidateFilters)
		local signature = tostring(filterString) .. "|" .. StableTableSignature(candidateFilters)
		if seenGroups[signature] then return end
		seenGroups[signature] = true
		groups[#groups + 1] = {
			key = key,
			filterString = filterString,
			candidateFilters = candidateFilters,
		}
	end

	local function ExtractionsEqual(first, second)
		if first.all ~= second.all then return false end
		local firstTokens = first.excludeTokens or {}
		local secondTokens = second.excludeTokens or {}
		if #firstTokens ~= #secondTokens then return false end
		for index = 1, #firstTokens do
			if firstTokens[index] ~= secondTokens[index] then return false end
		end
		return true
	end

	local function BuildSourceFilter(sourceToken, extraction, extraToken, priorExclusions)
		local parts = { auraType }
		AppendFilterToken(parts, sourceToken)
		for _, exclusion in ipairs(extraction.excludeTokens or {}) do AppendFilterToken(parts, exclusion) end
		for _, exclusion in ipairs(priorExclusions or {}) do AppendFilterToken(parts, exclusion) end
		AppendFilterToken(parts, extraToken)
		return table.concat(parts, "|")
	end

	local function GetSelectedClasses(classList)
		local selected = {}
		for _, class in ipairs(classList) do
			if filters[class.key] then selected[#selected + 1] = class end
		end
		return selected
	end

	local function SelectedClassesEqual(first, second)
		if #first ~= #second then return false end
		for index = 1, #first do
			if first[index].token ~= second[index].token or first[index].negate ~= second[index].negate then
				return false
			end
		end
		return true
	end

	-- Default mode normally needs one unfiltered Blizzard aura pool. If Custom
	-- extracts categories, source splitting is only required when Player/Others
	-- have different extraction rules. Identical rules can use one source-neutral
	-- group instead of two providers.
	if not categoryMode then
		local playerExtraction = customExtraction.Player
		local otherExtraction = customExtraction.Others
		local hasPlayerExtraction = playerExtraction.all or #playerExtraction.excludeTokens > 0
		local hasOtherExtraction = otherExtraction.all or #otherExtraction.excludeTokens > 0

		if not hasPlayerExtraction and not hasOtherExtraction then
			AddGroup("Default", auraType, BuildCandidateFilters(nil, blacklistMap, nil))
			return groups
		end

		if ExtractionsEqual(playerExtraction, otherExtraction) then
			if not playerExtraction.all then
				AddGroup(
					"DefaultAllSources",
					BuildSourceFilter(nil, playerExtraction),
					BuildCandidateFilters(nil, blacklistMap, nil)
				)
			end
			return groups
		end

		if not playerExtraction.all then
			AddGroup(
				"DefaultPlayer",
				BuildSourceFilter("PLAYER", playerExtraction),
				BuildCandidateFilters(nil, blacklistMap, nil)
			)
		end
		if not otherExtraction.all then
			AddGroup(
				"DefaultOthers",
				BuildSourceFilter("!PLAYER", otherExtraction),
				BuildCandidateFilters(nil, blacklistMap, nil)
			)
		end
		return groups
	end

	-- Whitelist is an explicit manual inclusion source. Custom category
	-- extraction still has placement priority, but identical Player/Others
	-- extraction can share one source-neutral whitelist group.
	if hasWhitelist then
		local playerExtraction = customExtraction.Player
		local otherExtraction = customExtraction.Others
		if ExtractionsEqual(playerExtraction, otherExtraction) then
			if not playerExtraction.all then
				AddGroup(
					"WhitelistAllSources",
					BuildSourceFilter(nil, playerExtraction),
					BuildCandidateFilters(effectiveWhitelistMap, nil, nil)
				)
			end
		else
			if not playerExtraction.all then
				AddGroup(
					"WhitelistPlayer",
					BuildSourceFilter("PLAYER", playerExtraction),
					BuildCandidateFilters(effectiveWhitelistMap, nil, nil)
				)
			end
			if not otherExtraction.all then
				AddGroup(
					"WhitelistOthers",
					BuildSourceFilter("!PLAYER", otherExtraction),
					BuildCandidateFilters(effectiveWhitelistMap, nil, nil)
				)
			end
		end
	end

	-- Prevent category groups from duplicating manually whitelisted spells and
	-- always remove blacklisted spells.
	local categoryExcludeMap = MergeSpellIDMaps(blacklistMap, whitelistMap)

	local function AddSourceGroups(sourceKey, sourceToken, selectedClasses, allSelected, extraction)
		if extraction.all then return end

		if allSelected then
			AddGroup(
				sourceKey .. "All",
				BuildSourceFilter(sourceToken, extraction),
				BuildCandidateFilters(nil, categoryExcludeMap, nil)
			)
			return
		end

		local priorExclusions = {}
		local function BuildFilter(extraToken)
			return BuildSourceFilter(sourceToken, extraction, extraToken, priorExclusions)
		end

		if auraType == "HARMFUL" and filters.RaidPlayerDispellable then
			AddGroup(sourceKey .. "PlayerDispellable", BuildFilter("RAID"), BuildCandidateFilters(nil, categoryExcludeMap, nil))
			priorExclusions[#priorExclusions + 1] = "!RAID"
		end

		for _, class in ipairs(selectedClasses) do
			AddGroup(sourceKey .. class.key, BuildFilter(class.token), BuildCandidateFilters(nil, categoryExcludeMap, nil))
			priorExclusions[#priorExclusions + 1] = class.negate or InvertAuraFilterToken(class.token)
		end

		if auraType == "HARMFUL" and filters.Typed then
			AddGroup(sourceKey .. "Typed", BuildFilter(nil), BuildCandidateFilters(nil, categoryExcludeMap, ManagedTypedDispelTypes))
		end
	end

	local playerClasses = GetSelectedClasses(PartyRaidPlayerFilterClasses)
	local otherClasses = GetSelectedClasses(PartyRaidOtherFilterClasses)
	local playerAll = filters.Player == true
	local otherAll = filters.Others == true
	local canMergeSources = playerAll == otherAll
		and ExtractionsEqual(customExtraction.Player, customExtraction.Others)
		and SelectedClassesEqual(playerClasses, otherClasses)

	if canMergeSources then
		-- If both dropdowns express the same union, PLAYER + !PLAYER is exactly
		-- one source-neutral Blizzard query. This is the common raid-healing case
		-- (for example Big Defensive + External on both sources) and halves the
		-- number of AuraGroups/providers for that container.
		AddSourceGroups("AllSources", nil, playerClasses, playerAll, customExtraction.Player)
	else
		AddSourceGroups("Player", "PLAYER", playerClasses, playerAll, customExtraction.Player)
		AddSourceGroups("Others", "!PLAYER", otherClasses, otherAll, customExtraction.Others)
	end

	return groups
end

local function BuildEnemyDebuffAuraGroups(DebuffsDB, CustomDB)
	NormalizeUnifiedAuraFilterSettings(DebuffsDB)
	local settings = GetEnemyDebuffFilterSettings(DebuffsDB)
	local whitelistMap = ParsePandemicSpellIDs(DebuffsDB.Whitelist)
	local blacklistMap = ParsePandemicSpellIDs(DebuffsDB.Blacklist)
	local effectiveWhitelistMap = CopySpellIDMap(whitelistMap)
	for spellID in pairs(blacklistMap) do effectiveWhitelistMap[spellID] = nil end

	local hasWhitelist = HasSpellIDs(effectiveWhitelistMap)
	local onlyMyDebuffs = settings.OnlyMyDebuffs == true
	local onlyWhitelist = settings.OnlyWhitelist == true
	local customExtraction = GetPartyRaidCustomCategoryExtraction(CustomDB, "HARMFUL")
	local groups = {}

	local function AddGroup(key, filterString, candidateFilters)
		groups[#groups + 1] = {
			key = key,
			filterString = filterString,
			candidateFilters = candidateFilters,
		}
	end

	local function ExtractionsEqual(first, second)
		if first.all ~= second.all then return false end
		local firstTokens = first.excludeTokens or {}
		local secondTokens = second.excludeTokens or {}
		if #firstTokens ~= #secondTokens then return false end
		for index = 1, #firstTokens do
			if firstTokens[index] ~= secondTokens[index] then return false end
		end
		return true
	end

	local function BuildSourceFilter(sourceToken, extraction)
		local parts = { "HARMFUL" }
		AppendFilterToken(parts, sourceToken)
		for _, exclusion in ipairs(extraction.excludeTokens or {}) do
			AppendFilterToken(parts, exclusion)
		end
		return table.concat(parts, "|")
	end

	local function AddWhitelistGroups(playerOnly)
		if not hasWhitelist then return end

		local playerExtraction = customExtraction.Player
		local otherExtraction = customExtraction.Others
		if playerOnly then
			if not playerExtraction.all then
				AddGroup(
					"PlayerWhitelist",
					BuildSourceFilter("PLAYER", playerExtraction),
					BuildCandidateFilters(effectiveWhitelistMap, nil, nil)
				)
			end
			return
		end

		if ExtractionsEqual(playerExtraction, otherExtraction) then
			if not playerExtraction.all then
				AddGroup(
					"WhitelistAllSources",
					BuildSourceFilter(nil, playerExtraction),
					BuildCandidateFilters(effectiveWhitelistMap, nil, nil)
				)
			end
			return
		end

		if not playerExtraction.all then
			AddGroup(
				"WhitelistPlayer",
				BuildSourceFilter("PLAYER", playerExtraction),
				BuildCandidateFilters(effectiveWhitelistMap, nil, nil)
			)
		end
		if not otherExtraction.all then
			AddGroup(
				"WhitelistOthers",
				BuildSourceFilter("!PLAYER", otherExtraction),
				BuildCandidateFilters(effectiveWhitelistMap, nil, nil)
			)
		end
	end

	if onlyMyDebuffs and onlyWhitelist then
		AddWhitelistGroups(true)
	elseif onlyMyDebuffs then
		if not customExtraction.Player.all then
			AddGroup(
				"PlayerOnly",
				BuildSourceFilter("PLAYER", customExtraction.Player),
				BuildCandidateFilters(nil, blacklistMap, nil)
			)
		end
	elseif onlyWhitelist then
		AddWhitelistGroups(false)
	else
		-- Normal source-focused mode: all player debuffs plus explicit whitelist
		-- exceptions from any source. Blacklist always wins, and Custom category
		-- extraction retains placement priority so the same aura is not duplicated.
		AddWhitelistGroups(false)

		if not customExtraction.Player.all then
			local playerExcludeMap = MergeSpellIDMaps(whitelistMap, blacklistMap)
			AddGroup(
				"Player",
				BuildSourceFilter("PLAYER", customExtraction.Player),
				BuildCandidateFilters(nil, playerExcludeMap, nil)
			)
		end
	end

	return groups
end

local function SetPandemicTextureColour(texture, colour)
	if not texture then return end
	texture:SetDesaturated(true)
	-- Keep colour alpha out of VertexColor. Alpha animations below already use
	-- the configured alpha; applying it here as well makes the glow multiply
	-- its opacity and look washed out.
	texture:SetVertexColor(colour[1], colour[2], colour[3], 1)
end

local function CreatePandemicPulse(texture, minAlpha, maxAlpha, duration, delay)
	local animation = texture:CreateAnimationGroup()
	animation:SetLooping("REPEAT")

	local fadeIn = animation:CreateAnimation("Alpha")
	fadeIn:SetFromAlpha(minAlpha)
	fadeIn:SetToAlpha(maxAlpha)
	fadeIn:SetDuration(duration)
	fadeIn:SetOrder(1)
	if delay and delay > 0 then fadeIn:SetStartDelay(delay) end
	if fadeIn.SetSmoothing then fadeIn:SetSmoothing("IN_OUT") end

	local fadeOut = animation:CreateAnimation("Alpha")
	fadeOut:SetFromAlpha(maxAlpha)
	fadeOut:SetToAlpha(minAlpha)
	fadeOut:SetDuration(duration)
	fadeOut:SetOrder(2)
	if fadeOut.SetSmoothing then fadeOut:SetSmoothing("IN_OUT") end

	animation:Play()
	return animation
end

local function CreatePandemicGlowBounds(region, iconSize)
	iconSize = tonumber(iconSize) or 16
	local glowSize = iconSize * 1.4

	local bounds = CreateFrame("Frame", nil, region)
	bounds:SetSize(glowSize, glowSize)
	bounds:SetPoint("CENTER", region, "CENTER", 0, 0)
	bounds:EnableMouse(false)

	return bounds, glowSize
end

local function CreateManagedPixelGlow(region, colour, iconSize)
	local bounds, glowSize = CreatePandemicGlowBounds(region, iconSize)
	local thickness = math.max(math.min(math.floor(glowSize * 0.08 + 0.5), 3), 1)
	local lineLength = math.max(math.floor(glowSize * 0.28 + 0.5), 4)

	local points = {
		{"TOPLEFT", lineLength, thickness},
		{"TOP", lineLength, thickness},
		{"TOPRIGHT", lineLength, thickness},
		{"RIGHT", thickness, lineLength},
		{"BOTTOMRIGHT", lineLength, thickness},
		{"BOTTOM", lineLength, thickness},
		{"BOTTOMLEFT", lineLength, thickness},
		{"LEFT", thickness, lineLength},
	}

	for index, point in ipairs(points) do
		local line = bounds:CreateTexture(nil, "OVERLAY", nil, 7)
		line:SetColorTexture(colour[1], colour[2], colour[3], 1)
		line:SetBlendMode("ADD")
		line:SetSize(point[2], point[3])
		line:SetPoint(point[1], bounds, point[1], 0, 0)
		CreatePandemicPulse(line, 0.20 * colour[4], colour[4], 0.45, (index - 1) * 0.055)
	end
end

local function CreateManagedAutocastGlow(region, colour, iconSize)
	local bounds = CreatePandemicGlowBounds(region, iconSize)
	local sparkSize = math.max((tonumber(iconSize) or 16) * 0.20, 6)
	local inset = sparkSize * 0.5
	local positions = {
		{"TOPLEFT", inset, -inset}, {"TOP", 0, -inset}, {"TOPRIGHT", -inset, -inset},
		{"RIGHT", -inset, 0}, {"BOTTOMRIGHT", -inset, inset}, {"BOTTOM", 0, inset},
		{"BOTTOMLEFT", inset, inset}, {"LEFT", inset, 0},
	}

	for index, point in ipairs(positions) do
		local spark = bounds:CreateTexture(nil, "OVERLAY", nil, 7)
		spark:SetTexture("Interface\\Artifacts\\Artifacts")
		spark:SetTexCoord(0.8115234375, 0.9169921875, 0.8798828125, 0.9853515625)
		SetPandemicTextureColour(spark, colour)
		spark:SetBlendMode("ADD")
		spark:SetSize(sparkSize, sparkSize)
		spark:SetPoint(point[1], bounds, point[1], point[2], point[3])

		local animation = spark:CreateAnimationGroup()
		animation:SetLooping("REPEAT")

		local fadeIn = animation:CreateAnimation("Alpha")
		fadeIn:SetFromAlpha(0.12 * colour[4])
		fadeIn:SetToAlpha(colour[4])
		fadeIn:SetDuration(0.45)
		fadeIn:SetOrder(1)
		fadeIn:SetStartDelay((index - 1) * 0.065)
		if fadeIn.SetSmoothing then fadeIn:SetSmoothing("IN_OUT") end

		local fadeOut = animation:CreateAnimation("Alpha")
		fadeOut:SetFromAlpha(colour[4])
		fadeOut:SetToAlpha(0.12 * colour[4])
		fadeOut:SetDuration(0.45)
		fadeOut:SetOrder(2)
		if fadeOut.SetSmoothing then fadeOut:SetSmoothing("IN_OUT") end

		animation:Play()
	end
end

local function CreateManagedButtonGlow(region, colour, iconSize)
	local bounds, glowSize = CreatePandemicGlowBounds(region, iconSize)
	local antsSize = glowSize * 0.85

	-- Keep the outer glow stable. The previous FIX pulsed these two layers every
	-- 0.42s, which made the effect look artificially accelerated compared with
	-- the reference Button Glow.
	local outer = bounds:CreateTexture(nil, "ARTWORK", nil, 5)
	outer:SetAllPoints(bounds)
	outer:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
	outer:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
	SetPandemicTextureColour(outer, colour)
	outer:SetBlendMode("ADD")
	outer:SetAlpha(0.85 * colour[4])

	local outerOver = bounds:CreateTexture(nil, "ARTWORK", nil, 6)
	outerOver:SetAllPoints(bounds)
	outerOver:SetTexture("Interface\\SpellActivationOverlay\\IconAlert")
	outerOver:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)
	SetPandemicTextureColour(outerOver, colour)
	outerOver:SetBlendMode("ADD")
	outerOver:SetAlpha(0.55 * colour[4])

	local ants = bounds:CreateTexture(nil, "OVERLAY", nil, 7)
	ants:SetSize(antsSize, antsSize)
	ants:SetPoint("CENTER", bounds, "CENTER", 0, 0)
	ants:SetTexture("Interface\\SpellActivationOverlay\\IconAlertAnts")
	SetPandemicTextureColour(ants, colour)
	ants:SetAlpha(colour[4])
	ants:SetBlendMode("ADD")

	local animation = ants:CreateAnimationGroup()
	animation:SetLooping("REPEAT")
	local flipbook = animation:CreateAnimation("FlipBook")
	-- FIX7: slower than FIX6 (0.22s) so it no longer looks unnaturally fast.
	flipbook:SetDuration(0.45)
	flipbook:SetOrder(1)
	flipbook:SetFlipBookRows(5)
	flipbook:SetFlipBookColumns(5)
	flipbook:SetFlipBookFrames(22)
	flipbook:SetFlipBookFrameWidth(48)
	flipbook:SetFlipBookFrameHeight(48)
	animation:Play()
end

local function CreateManagedProcGlow(region, colour, iconSize)
	local bounds = CreatePandemicGlowBounds(region, iconSize)
	local loop = bounds:CreateTexture(nil, "OVERLAY", nil, 7)
	loop:SetAllPoints(bounds)
	loop:SetAtlas("UI-HUD-ActionBar-Proc-Loop-Flipbook")
	SetPandemicTextureColour(loop, colour)
	loop:SetAlpha(colour[4])
	loop:SetBlendMode("ADD")

	local animation = loop:CreateAnimationGroup()
	animation:SetLooping("REPEAT")
	animation:SetToFinalAlpha(true)

	local flipbook = animation:CreateAnimation("FlipBook")
	flipbook:SetDuration(1)
	flipbook:SetOrder(0)
	flipbook:SetFlipBookRows(6)
	flipbook:SetFlipBookColumns(5)
	flipbook:SetFlipBookFrames(30)
	flipbook:SetFlipBookFrameWidth(0)
	flipbook:SetFlipBookFrameHeight(0)

	animation:Play()
end

local function CreateManagedPandemicRegion(button, unitFrame, pandemicSettings, iconSize)
	if not button or not button.AddPandemicRegion then return end

	pandemicSettings = pandemicSettings or {}
	local glowType = pandemicSettings.Type or "BUTTON"
	local colour = pandemicSettings.Colour or {1, 0.82, 0, 1}

	-- AuraButton in 12.1 forbids addon script execution on itself and descendants.
	-- Pandemic visuals therefore use only textures + native AnimationGroups: no
	-- OnUpdate/OnShow/OnHide handlers. Blizzard controls the holder visibility.
	iconSize = tonumber(iconSize) or 16
	local region = CreateFrame("Frame", nil, button)
	-- Keep Blizzard's Pandemic-controlled holder tied to the icon itself. Glow
	-- textures may extend beyond it using the known configured icon size.
	region:SetAllPoints(button)
	region:EnableMouse(false)

	if region.SetFrameLevel and button.GetFrameLevel then
		region:SetFrameLevel(button:GetFrameLevel() + 8)
	end

	if glowType == "PIXEL" then
		CreateManagedPixelGlow(region, colour, iconSize)
	elseif glowType == "AUTOCAST" then
		CreateManagedAutocastGlow(region, colour, iconSize)
	elseif glowType == "PROC" then
		CreateManagedProcGlow(region, colour, iconSize)
	else
		CreateManagedButtonGlow(region, colour, iconSize)
	end

	local bound, bindError = pcall(button.AddPandemicRegion, button, region)
	if bound then
		button.UUFPandemicRegion = region
		button.UUFPandemicGlowType = glowType
	else
		unitFrame.UUFManagedAuraLastError = tostring(bindError)
		region:Hide()
	end
end

local function HasManagedAuraContainers()
	if managedAuraSupport == true then return true end

	if C_AddOns and C_AddOns.LoadAddOn then
		pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer")
	end

	local ok, probe = pcall(CreateFrame, "AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
	local supported = ok and probe and type(probe.AddAuraGroup) == "function"

	if probe then
		pcall(probe.SetEnabled, probe, false)
		pcall(probe.Hide, probe)
	end

	-- Un fallo puede ser transitorio; solo cacheamos el éxito.
	if supported then managedAuraSupport = true end
	return supported and true or false
end

local function GetManagedAuraSort(sorting)
	local sortMethod
	local sortDirection

	if AuraContainerSortMethod then
		if sorting == "DURATION" or sorting == "DURATION_REVERSED" then
			sortMethod = AuraContainerSortMethod.ExpirationOnly
		else
			sortMethod = AuraContainerSortMethod.Default
		end
	end

	if AuraContainerSortDirection then
		if sorting == "BLIZZARD_REVERSED" or sorting == "DURATION_REVERSED" then
			sortDirection = AuraContainerSortDirection.Reverse
		else
			sortDirection = AuraContainerSortDirection.Normal
		end
	end

	return sortMethod, sortDirection
end


-- Party/Raid AuraGroups are intentionally persistent. Blizzard allocates AuraButtons
-- in batches per AddAuraGroup(), so rebuilding containers or declaring a new semantic
-- key for every filter permutation permanently grows the session allocation. Reuse a
-- small set of positional group slots instead: mutate their filter/candidates/layout,
-- park unused slots at maxFrameCount=0, and only AddAuraGroup when the active config
-- genuinely needs more simultaneous groups than this container has ever needed.
local function StableManagedAuraValueSignature(value)
	if type(value) ~= "table" then return tostring(value) end
	local keys = {}
	for key in pairs(value) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = tostring(key) .. "=" .. StableManagedAuraValueSignature(value[key])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function ApplyPartyRaidAuraGroupSlots(container, unitFrame, prefix, definitions, AuraDB, initializeFrame)
	if not container then return nil, nil, false end
	definitions = definitions or {}

	local state = container.UUFPartyRaidGroupSlots
	if not state then
		state = {
			keys = {},
			filterSignatures = {},
			candidateSignatures = {},
			layoutSignatures = {},
			sortSignatures = {},
			maxCounts = {},
		}
		container.UUFPartyRaidGroupSlots = state
	end

	local spacing = AuraDB.Layout and AuraDB.Layout[5] or 0
	local sortMethod, sortDirection = GetManagedAuraSort(AuraDB.Sorting)
	local layout = {
		elementWidth = AuraDB.Size,
		elementHeight = AuraDB.Size,
		elementSpacing = spacing,
		lineSpacing = spacing,
	}
	local layoutSignature = StableManagedAuraValueSignature(layout)
	local sortSignature = tostring(sortMethod) .. "|" .. tostring(sortDirection)
	local maxFrameCount = math.max(tonumber(AuraDB.Num) or 0, 0)

	-- Num=0 is a true off state: do not eagerly declare any new AuraGroup. Existing
	-- slots are parked below, so toggling back on can reuse them without allocation.
	if maxFrameCount <= 0 then
		definitions = {}
	end

	local definitionParts = {
		tostring(maxFrameCount),
		layoutSignature,
		sortSignature,
	}
	for index, definition in ipairs(definitions) do
		definitionParts[#definitionParts + 1] = table.concat({
			tostring(index),
			tostring(definition.filterString),
			StableManagedAuraValueSignature(definition.candidateFilters),
		}, "~")
	end
	local applySignature = table.concat(definitionParts, "|")

	if state.applySignature == applySignature then
		return state.activeKeys or {}, state.keys, true
	end

	local function RecordError(context, err)
		unitFrame.UUFManagedAuraLastError = context .. ": " .. tostring(err)
	end

	local function Call(methodName, ...)
		local method = container[methodName]
		if type(method) ~= "function" then
			RecordError(methodName, "missing AuraContainer method")
			return false
		end
		local ok, err = pcall(method, container, ...)
		if not ok then RecordError(methodName, err) end
		return ok
	end

	local activeKeys = {}
	for index, definition in ipairs(definitions) do
		local groupKey = state.keys[index]
		local filterSignature = tostring(definition.filterString)
		local candidateSignature = StableManagedAuraValueSignature(definition.candidateFilters)

		if not groupKey then
			groupKey = prefix .. "_Slot" .. tostring(index)
			local options = {
				maxFrameCount = maxFrameCount,
				initializeFrame = initializeFrame,
				layout = layout,
				sortMethod = sortMethod,
				sortDirection = sortDirection,
				candidateFilters = definition.candidateFilters,
			}
			local ok, err = pcall(container.AddAuraGroup, container, groupKey, definition.filterString, options)
			if not ok then
				RecordError("AddAuraGroup(" .. groupKey .. ")", err)
				return nil, state.keys, false
			end
			state.keys[index] = groupKey
			state.filterSignatures[index] = filterSignature
			state.candidateSignatures[index] = candidateSignature
			state.layoutSignatures[index] = layoutSignature
			state.sortSignatures[index] = sortSignature
			state.maxCounts[index] = maxFrameCount
		else
			local filterChanged = state.filterSignatures[index] ~= filterSignature
			local candidatesChanged = state.candidateSignatures[index] ~= candidateSignature
			local layoutChanged = state.layoutSignatures[index] ~= layoutSignature
			local sortChanged = state.sortSignatures[index] ~= sortSignature
			local maxChanged = state.maxCounts[index] ~= maxFrameCount

			-- Park before changing selection semantics so a live group never briefly
			-- renders the old query under the new configuration.
			if (filterChanged or candidatesChanged) and state.maxCounts[index] ~= 0 then
				if not Call("SetAuraGroupMaxFrameCount", groupKey, 0) then return nil, state.keys, false end
				state.maxCounts[index] = 0
				maxChanged = maxFrameCount ~= 0
			end

			if filterChanged then
				if not Call("SetAuraGroupFilterString", groupKey, definition.filterString) then return nil, state.keys, false end
				state.filterSignatures[index] = filterSignature
			end
			if candidatesChanged then
				if not Call("SetAuraGroupCandidateFilters", groupKey, definition.candidateFilters) then return nil, state.keys, false end
				state.candidateSignatures[index] = candidateSignature
			end
			if layoutChanged then
				if not Call("SetAuraGroupLayout", groupKey, layout) then return nil, state.keys, false end
				state.layoutSignatures[index] = layoutSignature
			end
			if sortChanged then
				if not Call("SetAuraGroupSortMethod", groupKey, sortMethod, sortDirection) then return nil, state.keys, false end
				state.sortSignatures[index] = sortSignature
			end
			if maxChanged or state.maxCounts[index] ~= maxFrameCount then
				if not Call("SetAuraGroupMaxFrameCount", groupKey, maxFrameCount) then return nil, state.keys, false end
				state.maxCounts[index] = maxFrameCount
			end
		end

		activeKeys[#activeKeys + 1] = groupKey
	end

	-- Groups cannot be removed. Any previously declared slot beyond the current
	-- active definition count is retained but contributes zero aura work/output.
	for index = #definitions + 1, #state.keys do
		local groupKey = state.keys[index]
		if state.maxCounts[index] ~= 0 then
			if not Call("SetAuraGroupMaxFrameCount", groupKey, 0) then return nil, state.keys, false end
			state.maxCounts[index] = 0
		end
	end

	state.activeKeys = activeKeys
	state.applySignature = applySignature
	return activeKeys, state.keys, true
end

-- Midnight 12.1: SetUnit("target") no detecta por sí solo que el token "target"
-- ahora apunta a otra unidad. Hay que forzar UpdateAllAuras al cambiar de target.
local function RefreshManagedAuraContainer(container, forceRescan)
	if not container then return end

	if forceRescan then
		pcall(container.Hide, container)
		pcall(container.Show, container)
	end

	pcall(container.UpdateAllAuras, container)
end

function UUF:RefreshMidnightManagedAuras(unitFrame, unit, forceRescan)
	if not unitFrame then return end
	if IsGroupAuraPreviewActive(unitFrame, unit) then
		SuspendRealAurasForGroupPreview(unitFrame)
		return
	end

	-- Si todavía no se pudo crear el contenedor, reintentamos ahora.
	if unit and (not unitFrame.UUFManagedTargetBuffs or not unitFrame.UUFManagedTargetDebuffs) then
		UUF:UpdateUnitAuras(unitFrame, unit)
	end

	RefreshManagedAuraContainer(unitFrame.UUFManagedTargetBuffs, forceRescan)
	RefreshManagedAuraContainer(unitFrame.UUFManagedTargetDebuffs, forceRescan)
	RefreshManagedAuraContainer(unitFrame.UUFManagedPartyRaidCustomAuras, forceRescan)
end

-- AuraContainer keeps the unit TOKEN, not the occupant identity. In Party/Raid a
-- roster change can replace the player behind the same token (for example party2)
-- without SetUnit seeing a different string. If the new member is not locally
-- observable yet, the container can otherwise keep buttons parsed for the previous
-- occupant until a later UNIT_AURA arrives. Force a real null -> unit rebind only
-- when the occupant GUID changes. Blizzard's AuraContainer null token is "none".
local MANAGED_AURA_NO_UNIT = "none"

local function HardRebindManagedAuraContainer(container, unit)
	if not container or not container.SetUnit then return end

	-- Clear the previous occupant first. UpdateAllAuras on the null binding makes
	-- stale buttons disappear even when the replacement unit cannot provide aura
	-- data yet (common immediately after a distant member joins).
	pcall(container.SetUnit, container, MANAGED_AURA_NO_UNIT)
	if container.UpdateAllAuras then pcall(container.UpdateAllAuras, container) end

	if unit and UnitExists(unit) then
		pcall(container.SetUnit, container, unit)
		if container.UpdateAllAuras then pcall(container.UpdateAllAuras, container) end
	end
end

local function RefreshManagedGroupOccupant(unitFrame, unit)
	if not unitFrame or type(unit) ~= "string" then return end
	if IsGroupAuraPreviewActive(unitFrame, unit) then
		SuspendRealAurasForGroupPreview(unitFrame)
		return
	end

	local isPartyUnit = unit:match("^party%d+$") ~= nil
	local isRaidUnit = unit:match("^raid%d+$") ~= nil
	if not isPartyUnit and not isRaidUnit then return end

	local okExists, exists = pcall(UnitExists, unit)
	if not okExists or UUF:IsSecretValue(exists) then exists = false end
	local guid
	if exists then
		local okGUID, value = pcall(UnitGUID, unit)
		if okGUID and not UUF:IsSecretValue(value) then guid = value end
	end
	local occupantKey = guid or false
	local observable = IsManagedGroupAuraUnitObservable(unit)

	if unitFrame.UUFManagedAuraOccupantUnit == unit
		and unitFrame.UUFManagedAuraOccupantGUID == occupantKey
		and unitFrame.UUFManagedAuraObservable == observable then
		return
	end

	local occupantChanged = unitFrame.UUFManagedAuraOccupantUnit ~= unit
		or unitFrame.UUFManagedAuraOccupantGUID ~= occupantKey
	local becameObservable = unitFrame.UUFManagedAuraObservable == false and observable

	unitFrame.UUFManagedAuraOccupantUnit = unit
	unitFrame.UUFManagedAuraOccupantGUID = occupantKey
	unitFrame.UUFManagedAuraObservable = observable

	-- Fail closed while the unit cannot provide trustworthy aura data. Merely
	-- hiding is not enough: leave the engine bound to "none" so no degraded or
	-- stale parse can continue in the background.
	if not observable then
		ParkManagedGroupAuraContainers(unitFrame)
		return
	end

	-- Re-apply current settings first. This also re-enables only the aura types
	-- that are actually configured. On a visibility regain this is the one full
	-- reparse needed to replace any state from before the ghosted interval.
	UUF:UpdateUnitAuras(unitFrame, unit)

	-- A roster occupant change behind the same partyX/raidX token needs a true
	-- null -> unit rebind. A simple visibility regain was already reparsed above.
	if occupantChanged and not becameObservable then
		HardRebindManagedAuraContainer(unitFrame.UUFManagedTargetBuffs, unit)
		HardRebindManagedAuraContainer(unitFrame.UUFManagedTargetDebuffs, unit)
		HardRebindManagedAuraContainer(unitFrame.UUFManagedPartyRaidCustomAuras, unit)
	end
end

local function RefreshManagedGroupRosterAuras()
	for _, frame in ipairs(UUF.PARTY_FRAMES or {}) do
		if frame and not frame.isTestFrame then
			local unit = (frame.GetAttribute and frame:GetAttribute("unit")) or frame.unit
			if type(unit) == "string" and unit:match("^party%d+$") then
				RefreshManagedGroupOccupant(frame, unit)
			end
		end
	end

	for _, frame in ipairs(UUF.RAID_FRAMES or {}) do
		if frame and not frame.isTestFrame then
			local unit = frame.GetAttribute and frame:GetAttribute("unit")
			if type(unit) == "string" and unit:match("^raid%d+$") then
				RefreshManagedGroupOccupant(frame, unit)
			end
		end
	end
end

-- UNIT_AURA has no guaranteed edge when a member crosses local render/phase
-- visibility. Sweep only the small Party/Raid frame set once per second; the
-- per-frame state guard above makes the steady-state pass read-only.
local managedGroupAuraVisibilityTicker = C_Timer.NewTicker(1.0, RefreshManagedGroupRosterAuras)

local managedAuraRetargetFrame = CreateFrame("Frame")
managedAuraRetargetFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
managedAuraRetargetFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
managedAuraRetargetFrame:RegisterUnitEvent("UNIT_AURA", "player")
managedAuraRetargetFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
managedAuraRetargetFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
managedAuraRetargetFrame:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
managedAuraRetargetFrame:RegisterUnitEvent("UNIT_PET", "player")
managedAuraRetargetFrame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
managedAuraRetargetFrame:SetScript("OnEvent", function(_, event, unitToken)
	local function RefreshFrame(frame, unit, force)
		if frame then UUF:RefreshMidnightManagedAuras(frame, unit, force) end
	end

	if event == "PLAYER_ENTERING_WORLD" then
		C_Timer.After(0, function()
			RefreshFrame(UUF.PLAYER, "player", true)
			RefreshFrame(UUF.TARGET, "target", true)
			RefreshFrame(UUF.TARGETTARGET, "targettarget", true)
			RefreshFrame(UUF.PET, "pet", true)
			RefreshFrame(UUF.FOCUS, "focus", true)
			RefreshFrame(UUF.FOCUSTARGET, "focustarget", true)
			RefreshManagedGroupRosterAuras()
		end)
		return
	end

	if event == "GROUP_ROSTER_UPDATE" then
		-- Secure headers and party tokens may settle over more than one frame. The
		-- GUID guard makes the second pass free unless an occupant really changed.
		C_Timer.After(0, RefreshManagedGroupRosterAuras)
		C_Timer.After(0.25, RefreshManagedGroupRosterAuras)
		return
	end

	if event == "UNIT_AURA" then
		-- AuraContainers consume normal UNIT_AURA incrementally themselves. Keep the
		-- existing player refresh as a compatibility nudge without adding full-rescan
		-- handlers to every unit frame.
		if unitToken == "player" then RefreshFrame(UUF.PLAYER, "player", false) end
		return
	end

	if event == "PLAYER_TARGET_CHANGED" then
		RefreshFrame(UUF.TARGET, "target", true)
		RefreshFrame(UUF.TARGETTARGET, "targettarget", true)
		return
	end

	if event == "PLAYER_FOCUS_CHANGED" then
		RefreshFrame(UUF.FOCUS, "focus", true)
		RefreshFrame(UUF.FOCUSTARGET, "focustarget", true)
		return
	end

	if event == "UNIT_TARGET" then
		if unitToken == "target" then
			RefreshFrame(UUF.TARGETTARGET, "targettarget", true)
		elseif unitToken == "focus" then
			RefreshFrame(UUF.FOCUSTARGET, "focustarget", true)
		end
		return
	end

	if event == "UNIT_PET" then
		if unitToken == "player" then RefreshFrame(UUF.PET, "pet", true) end
		return
	end

	if event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT" then
		C_Timer.After(0, function()
			for index, frame in ipairs(UUF.BOSS_FRAMES or {}) do
				local unit = "boss" .. index
				if frame and UnitExists(unit) then
					UUF:RefreshMidnightManagedAuras(frame, unit, true)
				end
			end
		end)
	end
end)

local function RegisterManagedAuraButton(unitFrame, storageKey, button)
	if not unitFrame or not button then return end

	local buttons = unitFrame[storageKey]
	if not buttons then
		buttons = setmetatable({}, { __mode = "k" })
		unitFrame[storageKey] = buttons
	end

	buttons[button] = true
end

local function CreateManagedAuraDurationText(button, cooldown, unitFrame, unit)
	-- AuraContainer 12.1: el swipe y el texto de duración son bindings distintos.
	-- Ocultamos únicamente el contador interno del CooldownFrame y registramos
	-- un FontString explícito con AuraButton:SetDurationText().
	if cooldown.SetHideCountdownNumbers then
		cooldown:SetHideCountdownNumbers(true)
	end

	local durationText = cooldown:CreateFontString(nil, "OVERLAY")
	button.UUFDurationText = durationText

	RefreshManagedAuraDurationFormatter()
	UUF:ApplyCooldownText(cooldown, durationText, unit, unitFrame, true)

	if button.SetDurationText then
		local ok = pcall(button.SetDurationText, button, durationText, {
			textFormatter = ManagedAuraDurationFormatter,
		})
		if not ok and cooldown.SetHideCountdownNumbers then
			-- Fallback: si el cliente rechaza SetDurationText, no perdemos
			-- por completo el contador nativo del CooldownFrame.
			cooldown:SetHideCountdownNumbers(false)
		end
	end
end

local function CreateManagedBuffButton(button, unitFrame, unit, BuffsDB)
	local size = BuffsDB.Size or 16
	button:SetSize(size, size)
	if button.SetClipsChildren then button:SetClipsChildren(false) end

	if button.SetTooltipAnchorPoint then
		button:SetTooltipAnchorPoint("ANCHOR_CURSOR", 0, 0)
	end

	local icon = button:CreateTexture(nil, "BORDER")
	icon:SetAllPoints()
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.Icon = icon
	if button.SetIcon then button:SetIcon(icon) end

	local cooldown = CreateFrame("Cooldown", "$parentCooldown", button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:SetDrawEdge(false)
	cooldown:SetReverse(true)

	-- Midnight 12.1: keep native countdown text available through expiration.
	-- The actual number format is still controlled by UUF Cooldown Text Breakpoints.
	if cooldown.SetMinimumCountdownDuration then
		cooldown:SetMinimumCountdownDuration(0)
	end
	if cooldown.SetCountdownMillisecondsThreshold then
		cooldown:SetCountdownMillisecondsThreshold(0)
	end

	button.Cooldown = cooldown
	if button.SetDurationCooldown then button:SetDurationCooldown(cooldown) end

	CreateManagedAuraDurationText(button, cooldown, unitFrame, unit)
	RegisterManagedAuraButton(unitFrame, "UUFManagedBuffButtons", button)

	-- Keep stack text above the Cooldown child frame. FontStrings created
	-- directly on the AuraButton sit in the parent's region layer and can be
	-- covered by child frames; Blizzard's native stack binding still works with
	-- a FontString parented to an owned carrier frame.
	local countCarrier = CreateFrame("Frame", nil, button)
	countCarrier:SetAllPoints(button)
	countCarrier:SetFrameLevel(cooldown:GetFrameLevel() + 2)
	if countCarrier.SetClipsChildren then countCarrier:SetClipsChildren(false) end
	countCarrier:EnableMouse(false)
	button.UUFCountCarrier = countCarrier

	local count = countCarrier:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.Count = count

	if BuffsDB.Count then
		local FontsDB = UUF.db.profile.General.Fonts
		count:ClearAllPoints()
		count:SetFont(UUF.Media.Font, BuffsDB.Count.FontSize, FontsDB.FontFlag)
		count:SetPoint(BuffsDB.Count.Layout[1], button, BuffsDB.Count.Layout[2], BuffsDB.Count.Layout[3], BuffsDB.Count.Layout[4])
		if FontsDB.Shadow.Enabled then
			count:SetShadowColor(unpack(FontsDB.Shadow.Colour))
			count:SetShadowOffset(FontsDB.Shadow.XPos, FontsDB.Shadow.YPos)
		else
			count:SetShadowColor(0, 0, 0, 0)
			count:SetShadowOffset(0, 0)
		end
		count:SetTextColor(unpack(BuffsDB.Count.Colour))
	end

	-- AuraButton owns the application-count value and visibility in 12.1.
	-- Bind only after styling, and never force Show/Hide after the binding.
	if BuffsDB.Count and not BuffsDB.Count.HideStacks and button.SetApplicationCount then
		button:SetApplicationCount(count, {})
	else
		count:Hide()
	end

	local borderSize = 1

	local borderTop = button:CreateTexture(nil, "OVERLAY", nil, 7)
	borderTop:SetTexture("Interface\\Buttons\\WHITE8X8")
	borderTop:SetVertexColor(0, 0, 0, 1)
	borderTop:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	borderTop:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
	borderTop:SetHeight(borderSize)

	local borderBottom = button:CreateTexture(nil, "OVERLAY", nil, 7)
	borderBottom:SetTexture("Interface\\Buttons\\WHITE8X8")
	borderBottom:SetVertexColor(0, 0, 0, 1)
	borderBottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
	borderBottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
	borderBottom:SetHeight(borderSize)

	local borderLeft = button:CreateTexture(nil, "OVERLAY", nil, 7)
	borderLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
	borderLeft:SetVertexColor(0, 0, 0, 1)
	borderLeft:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	borderLeft:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
	borderLeft:SetWidth(borderSize)

	local borderRight = button:CreateTexture(nil, "OVERLAY", nil, 7)
	borderRight:SetTexture("Interface\\Buttons\\WHITE8X8")
	borderRight:SetVertexColor(0, 0, 0, 1)
	borderRight:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
	borderRight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
	borderRight:SetWidth(borderSize)

	button.UUFBorder = { borderTop, borderBottom, borderLeft, borderRight }
end

local function ManagedCooldownTextSignature(unitFrame, unit)
	local globalCooldownDB = UUF.db.profile.General.CooldownText
	local styleDB = globalCooldownDB

	if globalCooldownDB.Advanced and unit then
		local unitDB = UUF:GetUnitDB(unitFrame, unit)
		if unitDB and unitDB.Auras and unitDB.Auras.AuraDuration then
			styleDB = unitDB.Auras.AuraDuration
		end
	end

	local fontsDB = UUF.db.profile.General.Fonts
	local shadow = fontsDB.Shadow or {}
	local layout = styleDB.Layout or {}

	local parts = {
		tostring(globalCooldownDB.Advanced),
		tostring(styleDB.FontSize),
		tostring(styleDB.ScaleByIconSize),
		tostring(layout[1]),
		tostring(layout[2]),
		tostring(layout[3]),
		tostring(layout[4]),
		tostring(fontsDB.Font),
		tostring(fontsDB.FontFlag),
		tostring(shadow.Enabled),
		tostring(shadow.XPos),
		tostring(shadow.YPos),
	}

	if shadow.Colour then
		for i = 1, 4 do
			parts[#parts + 1] = tostring(shadow.Colour[i])
		end
	end

	-- Los breakpoints son globales incluso cuando el estilo visual es Advanced.
	for _, breakpoint in ipairs(globalCooldownDB.CooldownBreakpoints or {}) do
		parts[#parts + 1] = tostring(breakpoint.threshold)
		parts[#parts + 1] = tostring(breakpoint.displayStyle)
		parts[#parts + 1] = tostring(breakpoint.step)
		parts[#parts + 1] = tostring(breakpoint.rounding)
		parts[#parts + 1] = tostring(breakpoint.min)
		parts[#parts + 1] = tostring(breakpoint.format)
		if breakpoint.color then
			for i = 1, 4 do
				parts[#parts + 1] = tostring(breakpoint.color[i])
			end
		end
	end

	return table.concat(parts, "|")
end

local function ManagedAuraCountSignature(AuraDB)
	local countDB = AuraDB and AuraDB.Count or {}
	local layout = countDB.Layout or {}
	local colour = countDB.Colour or {}
	local fontsDB = UUF.db.profile.General.Fonts or {}
	local shadow = fontsDB.Shadow or {}
	local shadowColour = shadow.Colour or {}

	return table.concat({
		tostring(countDB.HideStacks),
		tostring(countDB.FontSize),
		tostring(layout[1]),
		tostring(layout[2]),
		tostring(layout[3]),
		tostring(layout[4]),
		tostring(colour[1]),
		tostring(colour[2]),
		tostring(colour[3]),
		tostring(colour[4]),
		tostring(fontsDB.Font),
		tostring(fontsDB.FontFlag),
		tostring(shadow.Enabled),
		tostring(shadow.XPos),
		tostring(shadow.YPos),
		tostring(shadowColour[1]),
		tostring(shadowColour[2]),
		tostring(shadowColour[3]),
		tostring(shadowColour[4]),
	}, ":")
end

local function ManagedTargetBuffSignature(BuffsDB, unitFrame, unit, AurasDB)
	local isPartyRaid = IsUnifiedManagedAuraUnit(unitFrame, unit)
	if isPartyRaid then
		-- Party/Raid filter/layout/count changes are runtime-mutated on persistent
		-- group slots. Rebuild only when the AuraButton initializer itself changes.
		return table.concat({
			tostring(BuffsDB.Size),
			ManagedAuraCountSignature(BuffsDB),
			ManagedCooldownTextSignature(unitFrame, unit),
		}, "|")
	end

	return table.concat({
		tostring(BuffsDB.Enabled),
		tostring(BuffsDB.Size),
		tostring(BuffsDB.Num),
		tostring(BuffsDB.Wrap),
		tostring(BuffsDB.Layout and BuffsDB.Layout[1]),
		tostring(BuffsDB.Layout and BuffsDB.Layout[2]),
		tostring(BuffsDB.Layout and BuffsDB.Layout[3]),
		tostring(BuffsDB.Layout and BuffsDB.Layout[4]),
		tostring(BuffsDB.Layout and BuffsDB.Layout[5]),
		tostring(BuffsDB.GrowthDirection),
		tostring(BuffsDB.WrapDirection),
		tostring(BuffsDB.Sorting),
		ManagedAuraCountSignature(BuffsDB),
		ManagedCooldownTextSignature(unitFrame, unit),
	}, "|")
end

local function UpdateManagedTargetBuffs(unitFrame, unit, AurasDB, BuffsDB, anchorParent)
	if not UsesMidnightManagedAuras(unit) then return false end
	if not HasManagedAuraContainers() then return true end

	local isPartyRaid = IsUnifiedManagedAuraUnit(unitFrame, unit)
	local signature = ManagedTargetBuffSignature(BuffsDB, unitFrame, unit, AurasDB)
	local container = unitFrame.UUFManagedTargetBuffs

	if container and unitFrame.UUFManagedTargetBuffsSignature ~= signature then
		if InCombatLockdown() then return true end
		pcall(container.SetEnabled, container, false)
		pcall(container.Hide, container)
		container = nil
		unitFrame.UUFManagedTargetBuffs = nil
		unitFrame.UUFManagedBuffButtons = nil
		unitFrame.UUFManagedBuffGroupKeys = nil
		unitFrame.UUFManagedBuffDeclaredGroupKeys = nil
	end

	if not BuffsDB.Enabled then
		if container then
			pcall(container.SetEnabled, container, false)
			pcall(container.Hide, container)
		end
		return true
	end

	local perRow = BuffsDB.Wrap or 4
	local spacing = BuffsDB.Layout[5] or 0
	local width = math.max((BuffsDB.Size + spacing) * perRow - spacing, BuffsDB.Size)
	local rows = math.max(math.ceil(BuffsDB.Num / perRow), 1)
	local height = math.max((BuffsDB.Size + spacing) * rows - spacing, BuffsDB.Size)

	if not container then
		local ok, created = pcall(CreateFrame, "AuraContainer", nil, unitFrame, "CustomAuraContainerTemplate")
		if not ok or not created then
			unitFrame.UUFManagedAuraLastError = tostring(created)
			return true
		end
		container = created

		container:SetPoint(BuffsDB.Layout[1], anchorParent, BuffsDB.Layout[2], BuffsDB.Layout[3], BuffsDB.Layout[4])
		container:SetSize(width, height)
		container:SetFrameStrata(AurasDB.FrameStrata)
		if container.SetClipsChildren then container:SetClipsChildren(false) end

		if container.SetFlowLayoutAnchorPoint then
			container:SetFlowLayoutAnchorPoint(BuffsDB.Layout[1])
		end
		if container.SetFlowLayoutAxis and AnchorUtil and AnchorUtil.FlowLayoutAxis then
			container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
		end
		if container.SetFlowLayoutMaximumLineSize then
			container:SetFlowLayoutMaximumLineSize(width)
		end
		if container.SetFlowLayoutGrowthDirection then
			local growthX = BuffsDB.GrowthDirection == "LEFT" and -1 or 1
			local growthY = BuffsDB.WrapDirection == "DOWN" and -1 or 1
			container:SetFlowLayoutGrowthDirection(growthX, growthY)
		end
		if container.SetFlowLayoutPadding then
			container:SetFlowLayoutPadding(0, 0, 0, 0)
		end

		if not isPartyRaid then
			local sortMethod, sortDirection = GetManagedAuraSort(BuffsDB.Sorting)
			local options = {
				maxFrameCount = BuffsDB.Num,
				initializeFrame = function(button)
					CreateManagedBuffButton(button, unitFrame, unit, BuffsDB)
				end,
				layout = {
					elementWidth = BuffsDB.Size,
					elementHeight = BuffsDB.Size,
					elementSpacing = spacing,
					lineSpacing = spacing,
				},
				sortMethod = sortMethod,
				sortDirection = sortDirection,
			}
			local groupKey = "UUFManagedTargetBuffs_1_Default"
			local filterString = BuffsDB.OnlyShowPlayer and "HELPFUL|PLAYER" or "HELPFUL"
			local added, addError = pcall(container.AddAuraGroup, container, groupKey, filterString, options)
			if not added then
				unitFrame.UUFManagedAuraLastError = tostring(addError)
				pcall(container.SetEnabled, container, false)
				pcall(container.Hide, container)
				return true
			end
			unitFrame.UUFManagedBuffGroupKeys = { groupKey }
		end

		unitFrame.UUFManagedTargetBuffs = container
		unitFrame.UUFManagedTargetBuffsSignature = signature
	else
		if not InCombatLockdown() then
			container:ClearAllPoints()
			container:SetPoint(BuffsDB.Layout[1], anchorParent, BuffsDB.Layout[2], BuffsDB.Layout[3], BuffsDB.Layout[4])
			container:SetSize(width, height)
			container:SetFrameStrata(AurasDB.FrameStrata)
			if container.SetFlowLayoutAnchorPoint then container:SetFlowLayoutAnchorPoint(BuffsDB.Layout[1]) end
			if container.SetFlowLayoutMaximumLineSize then container:SetFlowLayoutMaximumLineSize(width) end
			if container.SetFlowLayoutGrowthDirection then
				local growthX = BuffsDB.GrowthDirection == "LEFT" and -1 or 1
				local growthY = BuffsDB.WrapDirection == "DOWN" and -1 or 1
				container:SetFlowLayoutGrowthDirection(growthX, growthY)
			end
		end
	end

	if isPartyRaid then
		local definitions = BuildPartyRaidAuraGroups(BuffsDB, "HELPFUL", AurasDB.Custom)
		local activeKeys, declaredKeys, applied = ApplyPartyRaidAuraGroupSlots(
			container,
			unitFrame,
			"UUFManagedTargetBuffs",
			definitions,
			BuffsDB,
			function(button)
				CreateManagedBuffButton(button, unitFrame, unit, BuffsDB)
			end
		)
		if not applied then return true end
		unitFrame.UUFManagedBuffGroupKeys = activeKeys
		unitFrame.UUFManagedBuffDeclaredGroupKeys = declaredKeys

		if #activeKeys == 0 or (tonumber(BuffsDB.Num) or 0) <= 0 then
			pcall(container.SetEnabled, container, false)
			pcall(container.Hide, container)
			return true
		end
	else
		local currentBuffFilter = BuffsDB.OnlyShowPlayer and "HELPFUL|PLAYER" or "HELPFUL"
		local groupKey = unitFrame.UUFManagedBuffGroupKeys and unitFrame.UUFManagedBuffGroupKeys[1]
		if groupKey and container.SetAuraGroupFilterString then
			local ok, err = pcall(container.SetAuraGroupFilterString, container, groupKey, currentBuffFilter)
			if not ok then unitFrame.UUFManagedAuraLastError = tostring(err) end
		end
		unitFrame.UUFManagedBuffFilter = currentBuffFilter
	end

	if container.SetUnit then pcall(container.SetUnit, container, GetManagedAuraUnitToken(unitFrame, unit)) end
	if container.SetEnabled then pcall(container.SetEnabled, container, true) end
	container:Show()
	RefreshManagedAuraContainer(container, false)
	return true
end

local function CreateManagedDebuffButton(button, unitFrame, unit, DebuffsDB, enablePandemic)
	local size = DebuffsDB.Size or 16
	button:SetSize(size, size)
	if button.SetClipsChildren then button:SetClipsChildren(false) end

	if button.SetTooltipAnchorPoint then
		button:SetTooltipAnchorPoint("ANCHOR_CURSOR", 0, 0)
	end

	local icon = button:CreateTexture(nil, "BORDER")
	icon:SetAllPoints()
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	button.Icon = icon
	if button.SetIcon then button:SetIcon(icon) end

	local cooldown = CreateFrame("Cooldown", "$parentCooldown", button, "CooldownFrameTemplate")
	cooldown:SetAllPoints()
	cooldown:SetDrawEdge(false)
	cooldown:SetReverse(true)

	-- Midnight 12.1: keep native countdown text available through expiration.
	-- The actual number format is still controlled by UUF Cooldown Text Breakpoints.
	if cooldown.SetMinimumCountdownDuration then
		cooldown:SetMinimumCountdownDuration(0)
	end
	if cooldown.SetCountdownMillisecondsThreshold then
		cooldown:SetCountdownMillisecondsThreshold(0)
	end

	button.Cooldown = cooldown
	if button.SetDurationCooldown then button:SetDurationCooldown(cooldown) end

	CreateManagedAuraDurationText(button, cooldown, unitFrame, unit)
	RegisterManagedAuraButton(unitFrame, "UUFManagedDebuffButtons", button)

	-- Same carrier strategy as buffs: the native application-count binding
	-- owns the value, while our child frame guarantees the text draws above the
	-- cooldown swipe and other button regions.
	local countCarrier = CreateFrame("Frame", nil, button)
	countCarrier:SetAllPoints(button)
	countCarrier:SetFrameLevel(cooldown:GetFrameLevel() + 2)
	if countCarrier.SetClipsChildren then countCarrier:SetClipsChildren(false) end
	countCarrier:EnableMouse(false)
	button.UUFCountCarrier = countCarrier

	local count = countCarrier:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.Count = count

	if DebuffsDB.Count then
		local FontsDB = UUF.db.profile.General.Fonts
		count:ClearAllPoints()
		count:SetFont(UUF.Media.Font, DebuffsDB.Count.FontSize, FontsDB.FontFlag)
		count:SetPoint(DebuffsDB.Count.Layout[1], button, DebuffsDB.Count.Layout[2], DebuffsDB.Count.Layout[3], DebuffsDB.Count.Layout[4])
		if FontsDB.Shadow.Enabled then
			count:SetShadowColor(unpack(FontsDB.Shadow.Colour))
			count:SetShadowOffset(FontsDB.Shadow.XPos, FontsDB.Shadow.YPos)
		else
			count:SetShadowColor(0, 0, 0, 0)
			count:SetShadowOffset(0, 0)
		end
		count:SetTextColor(unpack(DebuffsDB.Count.Colour))
	end

	-- Same lifecycle as buffs: once registered, Blizzard controls the live
	-- application-count text and its visibility.
	if DebuffsDB.Count and not DebuffsDB.Count.HideStacks and button.SetApplicationCount then
		button:SetApplicationCount(count, {})
	else
		count:Hide()
	end

	local borderSize = 1

	local borderTop = button:CreateTexture(nil, "OVERLAY", nil, 7)
	borderTop:SetTexture("Interface\\Buttons\\WHITE8X8")
	borderTop:SetVertexColor(0, 0, 0, 1)
	borderTop:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	borderTop:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
	borderTop:SetHeight(borderSize)

	local borderBottom = button:CreateTexture(nil, "OVERLAY", nil, 7)
	borderBottom:SetTexture("Interface\\Buttons\\WHITE8X8")
	borderBottom:SetVertexColor(0, 0, 0, 1)
	borderBottom:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
	borderBottom:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
	borderBottom:SetHeight(borderSize)

	local borderLeft = button:CreateTexture(nil, "OVERLAY", nil, 7)
	borderLeft:SetTexture("Interface\\Buttons\\WHITE8X8")
	borderLeft:SetVertexColor(0, 0, 0, 1)
	borderLeft:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
	borderLeft:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
	borderLeft:SetWidth(borderSize)

	local borderRight = button:CreateTexture(nil, "OVERLAY", nil, 7)
	borderRight:SetTexture("Interface\\Buttons\\WHITE8X8")
	borderRight:SetVertexColor(0, 0, 0, 1)
	borderRight:SetPoint("TOPRIGHT", button, "TOPRIGHT", 0, 0)
	borderRight:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
	borderRight:SetWidth(borderSize)

	button.UUFBorder = { borderTop, borderBottom, borderLeft, borderRight }

	if DebuffsDB.ShowType and button.AddDispelTypeTexture and Enum.CustomAuraButtonDispelTypeTextureStyle then
		local overlay = button:CreateTexture(nil, "OVERLAY")
		overlay:SetTexture("Interface\\AddOns\\UnhaltedUnitFrames\\Media\\Textures\\AuraOverlay.png")
		overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
		overlay:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		overlay:SetTexCoord(0, 1, 0, 1)
		button.Overlay = overlay

		pcall(button.AddDispelTypeTexture, button, overlay, {
			style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
			showWhenHarmful = true,
		})
	end

	if enablePandemic then
		CreateManagedPandemicRegion(button, unitFrame, GetBossPandemicSettings(DebuffsDB), size)
	end
end

local function ManagedTargetDebuffSignature(DebuffsDB, unitFrame, unit, AurasDB)
	local isPartyRaid = IsUnifiedManagedAuraUnit(unitFrame, unit)
	if isPartyRaid then
		-- Same persistent-slot rule as buffs: only initializer-affecting options
		-- require a fresh container/button batch.
		return table.concat({
			tostring(DebuffsDB.Size),
			tostring(DebuffsDB.ShowType),
			ManagedAuraCountSignature(DebuffsDB),
			ManagedCooldownTextSignature(unitFrame, unit),
		}, "|")
	end

	local pandemic = IsBossManagedAuraUnit(unit) and GetBossPandemicSettings(DebuffsDB) or {
		Enabled = false,
	}
	local bossFilter = IsBossManagedAuraUnit(unit) and GetBossDebuffFilterSettings(DebuffsDB) or {
		OnlyMyDebuffs = false,
		OnlyWhitelist = false,
		Whitelist = "",
		Blacklist = "",
	}

	return table.concat({
		tostring(DebuffsDB.Enabled),
		tostring(DebuffsDB.Size),
		tostring(DebuffsDB.Num),
		tostring(DebuffsDB.Wrap),
		tostring(DebuffsDB.Layout and DebuffsDB.Layout[1]),
		tostring(DebuffsDB.Layout and DebuffsDB.Layout[2]),
		tostring(DebuffsDB.Layout and DebuffsDB.Layout[3]),
		tostring(DebuffsDB.Layout and DebuffsDB.Layout[4]),
		tostring(DebuffsDB.Layout and DebuffsDB.Layout[5]),
		tostring(DebuffsDB.GrowthDirection),
		tostring(DebuffsDB.WrapDirection),
		tostring(DebuffsDB.Sorting),
		tostring(DebuffsDB.ShowType),
		ManagedAuraCountSignature(DebuffsDB),
		tostring(pandemic.Enabled),
		tostring(pandemic.Type),
		tostring(pandemic.Colour and pandemic.Colour[1]),
		tostring(pandemic.Colour and pandemic.Colour[2]),
		tostring(pandemic.Colour and pandemic.Colour[3]),
		tostring(pandemic.Colour and pandemic.Colour[4]),
		tostring(bossFilter.OnlyMyDebuffs),
		tostring(bossFilter.OnlyWhitelist),
		PandemicSpellIDSignature(bossFilter.Whitelist),
		PandemicSpellIDSignature(bossFilter.Blacklist),
		ManagedCooldownTextSignature(unitFrame, unit),
	}, "|")
end

local function UpdateManagedTargetDebuffs(unitFrame, unit, AurasDB, DebuffsDB, anchorParent)
	if not UsesMidnightManagedAuras(unit) then return false end
	if not HasManagedAuraContainers() then return true end

	local isPartyRaid = IsUnifiedManagedAuraUnit(unitFrame, unit)
	local isEnemyDebuffUnit = IsEnemyDebuffFilterUnit(unit)
	local isBoss = IsBossManagedAuraUnit(unit)
	local pandemic = isBoss and GetBossPandemicSettings(DebuffsDB) or {
		Enabled = false,
	}
	local bossFilter = isBoss and GetBossDebuffFilterSettings(DebuffsDB) or {
		OnlyMyDebuffs = false,
		OnlyWhitelist = false,
		Whitelist = "",
		Blacklist = "",
	}
	local pandemicEnabled = isBoss and pandemic.Enabled == true
	local onlyMyDebuffs = isBoss and bossFilter.OnlyMyDebuffs == true
	local onlyWhitelist = isBoss and bossFilter.OnlyWhitelist == true
	local whitelistMap = ParsePandemicSpellIDs(bossFilter.Whitelist)
	local blacklistMap = ParsePandemicSpellIDs(bossFilter.Blacklist)
	local effectiveWhitelistMap = CopySpellIDMap(whitelistMap)
	for spellID in pairs(blacklistMap) do effectiveWhitelistMap[spellID] = nil end
	local hasWhitelist = HasSpellIDs(effectiveWhitelistMap)

	local signature = ManagedTargetDebuffSignature(DebuffsDB, unitFrame, unit, AurasDB)
	local container = unitFrame.UUFManagedTargetDebuffs
	local clipFrame = unitFrame.UUFManagedTargetDebuffsClip

	if container and unitFrame.UUFManagedTargetDebuffsSignature ~= signature then
		if InCombatLockdown() then return true end
		pcall(container.SetEnabled, container, false)
		pcall(container.Hide, container)
		if clipFrame then pcall(clipFrame.Hide, clipFrame) end
		container = nil
		clipFrame = nil
		unitFrame.UUFManagedTargetDebuffs = nil
		unitFrame.UUFManagedTargetDebuffsClip = nil
		unitFrame.UUFManagedDebuffButtons = nil
		unitFrame.UUFManagedDebuffGroupKeys = nil
		unitFrame.UUFManagedDebuffDeclaredGroupKeys = nil
	end

	if not DebuffsDB.Enabled then
		if container then
			pcall(container.SetEnabled, container, false)
			pcall(container.Hide, container)
		end
		if clipFrame then pcall(clipFrame.Hide, clipFrame) end
		return true
	end

	local perRow = DebuffsDB.Wrap or 4
	local spacing = DebuffsDB.Layout[5] or 0
	local width = math.max((DebuffsDB.Size + spacing) * perRow - spacing, DebuffsDB.Size)
	local rows = math.max(math.ceil(DebuffsDB.Num / perRow), 1)
	local height = math.max((DebuffsDB.Size + spacing) * rows - spacing, DebuffsDB.Size)

	if not container then
		if usesSplitPandemicGroups then
			clipFrame = CreateFrame("Frame", nil, unitFrame)
			clipFrame:SetPoint(DebuffsDB.Layout[1], anchorParent, DebuffsDB.Layout[2], DebuffsDB.Layout[3], DebuffsDB.Layout[4])
			clipFrame:SetSize(width, height)
			clipFrame:SetFrameStrata(AurasDB.FrameStrata)
			if clipFrame.SetClipsChildren then clipFrame:SetClipsChildren(false) end
			unitFrame.UUFManagedTargetDebuffsClip = clipFrame
		end

		local containerParent = clipFrame or unitFrame
		local ok, created = pcall(CreateFrame, "AuraContainer", nil, containerParent, "CustomAuraContainerTemplate")
		if not ok or not created then
			unitFrame.UUFManagedAuraLastError = tostring(created)
			return true
		end
		container = created

		if clipFrame then
			container:SetPoint(DebuffsDB.Layout[1], clipFrame, DebuffsDB.Layout[1], 0, 0)
		else
			container:SetPoint(DebuffsDB.Layout[1], anchorParent, DebuffsDB.Layout[2], DebuffsDB.Layout[3], DebuffsDB.Layout[4])
		end
		container:SetSize(width, height)
		container:SetFrameStrata(AurasDB.FrameStrata)

		if container.SetFlowLayoutAnchorPoint then
			container:SetFlowLayoutAnchorPoint(DebuffsDB.Layout[1])
		end
		if container.SetFlowLayoutAxis and AnchorUtil and AnchorUtil.FlowLayoutAxis then
			container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
		end
		if container.SetFlowLayoutMaximumLineSize then
			container:SetFlowLayoutMaximumLineSize(width)
		end
		if container.SetFlowLayoutGrowthDirection then
			local growthX = DebuffsDB.GrowthDirection == "LEFT" and -1 or 1
			local growthY = DebuffsDB.WrapDirection == "DOWN" and -1 or 1
			container:SetFlowLayoutGrowthDirection(growthX, growthY)
		end
		if container.SetFlowLayoutPadding then
			container:SetFlowLayoutPadding(0, 0, 0, 0)
		end

		local sortMethod, sortDirection = GetManagedAuraSort(DebuffsDB.Sorting)
		local groupKeys = {}
		if container.SetClipsChildren then container:SetClipsChildren(false) end

		local function BuildGroupOptions(enablePandemic, candidateFilters)
			return {
				maxFrameCount = DebuffsDB.Num,
				initializeFrame = function(button)
					CreateManagedDebuffButton(button, unitFrame, unit, DebuffsDB, enablePandemic)
				end,
				layout = {
					elementWidth = DebuffsDB.Size,
					elementHeight = DebuffsDB.Size,
					elementSpacing = spacing,
					lineSpacing = spacing,
				},
				sortMethod = sortMethod,
				sortDirection = sortDirection,
				candidateFilters = candidateFilters,
			}
		end

		local function AddDebuffGroup(groupKey, filterString, options)
			local added, addError = pcall(container.AddAuraGroup, container, groupKey, filterString, options)
			if not added then
				unitFrame.UUFManagedAuraLastError = tostring(addError)
				pcall(container.SetEnabled, container, false)
				pcall(container.Hide, container)
				if clipFrame then pcall(clipFrame.Hide, clipFrame) end
				return false
			end
			groupKeys[#groupKeys + 1] = groupKey
			return true
		end

		if not isPartyRaid then
			if isBoss then
				-- Boss debuffs are intentionally source-focused:
				--   1) Only My Debuffs is a source restriction and also applies to Whitelist;
				--   2) Only Whitelist is a Spell ID restriction;
				--   3) with both enabled, only player-applied + whitelisted debuffs survive;
				--   4) blacklist can always exclude listed IDs.
				if onlyMyDebuffs and onlyWhitelist then
					if hasWhitelist then
						if not AddDebuffGroup(
							"UUFManagedTargetDebuffs_PlayerWhitelistOnly",
							"HARMFUL|PLAYER",
							BuildGroupOptions(pandemicEnabled, { includeSpellIDs = effectiveWhitelistMap })
						) then
							return true
						end
					end
				elseif onlyMyDebuffs then
					local playerCandidateFilters = HasSpellIDs(blacklistMap) and { excludeSpellIDs = blacklistMap } or nil
					if not AddDebuffGroup(
						"UUFManagedTargetDebuffs_PlayerOnly",
						"HARMFUL|PLAYER",
						BuildGroupOptions(pandemicEnabled, playerCandidateFilters)
					) then
						return true
					end
				else
					-- Exclude whitelist IDs from the player group so an aura that is both
					-- player-applied and whitelisted is never rendered twice.
					if hasWhitelist then
						if not AddDebuffGroup(
							"UUFManagedTargetDebuffs_Whitelist",
							"HARMFUL",
							BuildGroupOptions(pandemicEnabled, { includeSpellIDs = effectiveWhitelistMap })
						) then
							return true
						end
					end

					if not onlyWhitelist then
						local playerExcludeMap = MergeSpellIDMaps(whitelistMap, blacklistMap)
						local playerCandidateFilters = HasSpellIDs(playerExcludeMap) and { excludeSpellIDs = playerExcludeMap } or nil
						if not AddDebuffGroup(
							"UUFManagedTargetDebuffs_Player",
							"HARMFUL|PLAYER",
							BuildGroupOptions(pandemicEnabled, playerCandidateFilters)
						) then
							return true
						end
					end
				end
			else
				local filter = DebuffsDB.OnlyShowPlayer and "HARMFUL|PLAYER" or "HARMFUL"
				if not AddDebuffGroup("UUFManagedTargetDebuffs", filter, BuildGroupOptions(false, nil)) then
					return true
				end
			end
		end

		if container.SetUnit then pcall(container.SetUnit, container, GetManagedAuraUnitToken(unitFrame, unit)) end
		if container.SetEnabled then pcall(container.SetEnabled, container, true) end

		unitFrame.UUFManagedTargetDebuffs = container
		unitFrame.UUFManagedTargetDebuffsSignature = signature
		unitFrame.UUFManagedDebuffGroupKeys = groupKeys
	else
		if not InCombatLockdown() then
			if clipFrame then
				clipFrame:ClearAllPoints()
				clipFrame:SetPoint(DebuffsDB.Layout[1], anchorParent, DebuffsDB.Layout[2], DebuffsDB.Layout[3], DebuffsDB.Layout[4])
				clipFrame:SetSize(width, height)
				clipFrame:SetFrameStrata(AurasDB.FrameStrata)

				container:ClearAllPoints()
				container:SetPoint(DebuffsDB.Layout[1], clipFrame, DebuffsDB.Layout[1], 0, 0)
			else
				container:ClearAllPoints()
				container:SetPoint(DebuffsDB.Layout[1], anchorParent, DebuffsDB.Layout[2], DebuffsDB.Layout[3], DebuffsDB.Layout[4])
			end

			container:SetSize(width, height)
			container:SetFrameStrata(AurasDB.FrameStrata)
			if container.SetFlowLayoutAnchorPoint then container:SetFlowLayoutAnchorPoint(DebuffsDB.Layout[1]) end
			if container.SetFlowLayoutMaximumLineSize then
				container:SetFlowLayoutMaximumLineSize(width)
			end
			if container.SetFlowLayoutGrowthDirection then
				local growthX = DebuffsDB.GrowthDirection == "LEFT" and -1 or 1
				local growthY = DebuffsDB.WrapDirection == "DOWN" and -1 or 1
				container:SetFlowLayoutGrowthDirection(growthX, growthY)
			end
		end
		if container.SetEnabled then pcall(container.SetEnabled, container, true) end
	end

	if isPartyRaid then
		local definitions = isEnemyDebuffUnit
			and BuildEnemyDebuffAuraGroups(DebuffsDB, AurasDB.Custom)
			or BuildPartyRaidAuraGroups(DebuffsDB, "HARMFUL", AurasDB.Custom)
		local activeKeys, declaredKeys, applied = ApplyPartyRaidAuraGroupSlots(
			container,
			unitFrame,
			"UUFManagedTargetDebuffs",
			definitions,
			DebuffsDB,
			function(button)
				CreateManagedDebuffButton(button, unitFrame, unit, DebuffsDB, false)
			end
		)
		if not applied then return true end
		unitFrame.UUFManagedDebuffGroupKeys = activeKeys
		unitFrame.UUFManagedDebuffDeclaredGroupKeys = declaredKeys

		if #activeKeys == 0 or (tonumber(DebuffsDB.Num) or 0) <= 0 then
			pcall(container.SetEnabled, container, false)
			pcall(container.Hide, container)
			if clipFrame then pcall(clipFrame.Hide, clipFrame) end
			return true
		end
	end

	if not isPartyRaid and not isBoss then
		local currentDebuffFilter = DebuffsDB.OnlyShowPlayer and "HARMFUL|PLAYER" or "HARMFUL"
		if container.SetAuraGroupFilterString then
			for _, groupKey in ipairs(unitFrame.UUFManagedDebuffGroupKeys or {"UUFManagedTargetDebuffs"}) do
				local ok, err = pcall(container.SetAuraGroupFilterString, container, groupKey, currentDebuffFilter)
				if not ok then unitFrame.UUFManagedAuraLastError = tostring(err) end
			end
		end
		unitFrame.UUFManagedDebuffFilter = currentDebuffFilter
	end

	if container.SetUnit then pcall(container.SetUnit, container, GetManagedAuraUnitToken(unitFrame, unit)) end
	if clipFrame then clipFrame:Show() end
	container:Show()
	RefreshManagedAuraContainer(container, false)
	return true
end


local function ManagedPartyRaidCustomSignature(CustomDB, unitFrame, unit)
	-- Custom exists in this managed path only for Party/Raid. Keep the container
	-- across filter/layout/count changes and rebuild only when button construction
	-- changes (buff vs debuff, size, dispel overlay, stack/duration styling).
	return table.concat({
		tostring(CustomDB.Type),
		tostring(CustomDB.Size),
		tostring(CustomDB.ShowType),
		ManagedAuraCountSignature(CustomDB),
		ManagedCooldownTextSignature(unitFrame, unit),
	}, "|")
end

local function UpdateManagedPartyRaidCustomAuras(unitFrame, unit, AurasDB, CustomDB, anchorParent)
	if not CustomDB or not IsUnifiedManagedAuraUnit(unitFrame, unit) then return false end
	if not HasManagedAuraContainers() then return true end

	local auraType = CustomDB.Type == "Debuffs" and "HARMFUL" or "HELPFUL"
	local signature = ManagedPartyRaidCustomSignature(CustomDB, unitFrame, unit)
	local container = unitFrame.UUFManagedPartyRaidCustomAuras

	if container and unitFrame.UUFManagedPartyRaidCustomSignature ~= signature then
		if InCombatLockdown() then return true end
		pcall(container.SetEnabled, container, false)
		pcall(container.Hide, container)
		container = nil
		unitFrame.UUFManagedPartyRaidCustomAuras = nil
		unitFrame.UUFManagedPartyRaidCustomGroupKeys = nil
		unitFrame.UUFManagedPartyRaidCustomDeclaredGroupKeys = nil
	end

	if not CustomDB.Enabled then
		if container then
			pcall(container.SetEnabled, container, false)
			pcall(container.Hide, container)
		end
		return true
	end

	local perRow = CustomDB.Wrap or 3
	local spacing = CustomDB.Layout[5] or 0
	local width = math.max((CustomDB.Size + spacing) * perRow - spacing, CustomDB.Size)
	local rows = math.max(math.ceil(CustomDB.Num / perRow), 1)
	local height = math.max((CustomDB.Size + spacing) * rows - spacing, CustomDB.Size)

	if not container then
		local ok, created = pcall(CreateFrame, "AuraContainer", nil, unitFrame, "CustomAuraContainerTemplate")
		if not ok or not created then
			unitFrame.UUFManagedAuraLastError = tostring(created)
			return true
		end
		container = created
		container:SetPoint(CustomDB.Layout[1], anchorParent, CustomDB.Layout[2], CustomDB.Layout[3], CustomDB.Layout[4])
		container:SetSize(width, height)
		container:SetFrameStrata(AurasDB.FrameStrata)
		if container.SetClipsChildren then container:SetClipsChildren(false) end

		if container.SetFlowLayoutAnchorPoint then container:SetFlowLayoutAnchorPoint(CustomDB.Layout[1]) end
		if container.SetFlowLayoutAxis and AnchorUtil and AnchorUtil.FlowLayoutAxis then
			container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
		end
		if container.SetFlowLayoutMaximumLineSize then container:SetFlowLayoutMaximumLineSize(width) end
		if container.SetFlowLayoutGrowthDirection then
			local growthX = CustomDB.GrowthDirection == "LEFT" and -1 or 1
			local growthY = CustomDB.WrapDirection == "DOWN" and -1 or 1
			container:SetFlowLayoutGrowthDirection(growthX, growthY)
		end
		if container.SetFlowLayoutPadding then container:SetFlowLayoutPadding(0, 0, 0, 0) end

		unitFrame.UUFManagedPartyRaidCustomAuras = container
		unitFrame.UUFManagedPartyRaidCustomSignature = signature
	else
		if not InCombatLockdown() then
			container:ClearAllPoints()
			container:SetPoint(CustomDB.Layout[1], anchorParent, CustomDB.Layout[2], CustomDB.Layout[3], CustomDB.Layout[4])
			container:SetSize(width, height)
			container:SetFrameStrata(AurasDB.FrameStrata)
			if container.SetFlowLayoutAnchorPoint then container:SetFlowLayoutAnchorPoint(CustomDB.Layout[1]) end
			if container.SetFlowLayoutMaximumLineSize then container:SetFlowLayoutMaximumLineSize(width) end
			if container.SetFlowLayoutGrowthDirection then
				local growthX = CustomDB.GrowthDirection == "LEFT" and -1 or 1
				local growthY = CustomDB.WrapDirection == "DOWN" and -1 or 1
				container:SetFlowLayoutGrowthDirection(growthX, growthY)
			end
		end
	end

	local definitions = BuildPartyRaidAuraGroups(CustomDB, auraType)
	local activeKeys, declaredKeys, applied = ApplyPartyRaidAuraGroupSlots(
		container,
		unitFrame,
		"UUFManagedPartyRaidCustom",
		definitions,
		CustomDB,
		function(button)
			if auraType == "HARMFUL" then
				CreateManagedDebuffButton(button, unitFrame, unit, CustomDB, false)
			else
				CreateManagedBuffButton(button, unitFrame, unit, CustomDB)
			end
		end
	)
	if not applied then return true end
	unitFrame.UUFManagedPartyRaidCustomGroupKeys = activeKeys
	unitFrame.UUFManagedPartyRaidCustomDeclaredGroupKeys = declaredKeys

	if #activeKeys == 0 or (tonumber(CustomDB.Num) or 0) <= 0 then
		pcall(container.SetEnabled, container, false)
		pcall(container.Hide, container)
		return true
	end

	if container.SetUnit then pcall(container.SetUnit, container, GetManagedAuraUnitToken(unitFrame, unit)) end
	if container.SetEnabled then pcall(container.SetEnabled, container, true) end
	container:Show()
	RefreshManagedAuraContainer(container, false)
	return true
end

local function FilterAura(AuraDB, filterUnit, aura, auraType)
	if AuraDB.OnlyShowPlayer then return aura.isPlayerAura end
	local setFilters = AuraDB.Filters
	if not setFilters or not next(setFilters) then return true end

	local auraInstanceID = aura.auraInstanceID
	local isPlayer = aura.isPlayerAura
	local cancelFilter = isPlayer and "CancelablePlayer" or "Cancelable"
	local noCancelFilter = isPlayer and "NotCancelablePlayer" or "NotCancelable"

	if setFilters.Player and isPlayer then return true end
	if auraType == "HARMFUL" and setFilters.Typed then
		if C_UnitAuras.GetAuraDispelTypeColor(filterUnit, auraInstanceID, TypedDebuffColorCurve) then return true end
		local dispelName = not UUF:IsSecretValue(aura.dispelName) and aura.dispelName
		if dispelName and TypedDebuffTypes[dispelName] then return true end
	end
	if setFilters.RaidPlayerDispellable and not C_UnitAuras.IsAuraFilteredOutByInstanceID(filterUnit, auraInstanceID, auraType .. "|RAID") then return true end

	if (setFilters[cancelFilter] or setFilters[noCancelFilter]) then
		local isCancellable = not C_UnitAuras.IsAuraFilteredOutByInstanceID(filterUnit, auraInstanceID, auraType .. "|CANCELABLE")
		if setFilters[cancelFilter] and isCancellable then return true end
		if setFilters[noCancelFilter] and not isCancellable then return true end
	end

	if isPlayer then
		if setFilters.CrowdControlPlayer and not C_UnitAuras.IsAuraFilteredOutByInstanceID(filterUnit, auraInstanceID, auraType .. "|CROWD_CONTROL") then return true end
		if setFilters.BigDefensivePlayer and not C_UnitAuras.IsAuraFilteredOutByInstanceID(filterUnit, auraInstanceID, auraType .. "|BIG_DEFENSIVE") then return true end
		if setFilters.ExternalDefensivePlayer and not C_UnitAuras.IsAuraFilteredOutByInstanceID(filterUnit, auraInstanceID, auraType .. "|EXTERNAL_DEFENSIVE") then return true end
		if setFilters.RaidInCombatPlayer and not C_UnitAuras.IsAuraFilteredOutByInstanceID(filterUnit, auraInstanceID, auraType .. "|RAID_IN_COMBAT") then return true end
		if setFilters.RaidPlayer and not C_UnitAuras.IsAuraFilteredOutByInstanceID(filterUnit, auraInstanceID, auraType .. "|RAID") then return true end
	else
		if setFilters.CrowdControl and not C_UnitAuras.IsAuraFilteredOutByInstanceID(filterUnit, auraInstanceID, auraType .. "|CROWD_CONTROL") then return true end
		if setFilters.BigDefensive and not C_UnitAuras.IsAuraFilteredOutByInstanceID(filterUnit, auraInstanceID, auraType .. "|BIG_DEFENSIVE") then return true end
		if setFilters.ExternalDefensive and not C_UnitAuras.IsAuraFilteredOutByInstanceID(filterUnit, auraInstanceID, auraType .. "|EXTERNAL_DEFENSIVE") then return true end
		if setFilters.RaidInCombat and not C_UnitAuras.IsAuraFilteredOutByInstanceID(filterUnit, auraInstanceID, auraType .. "|RAID_IN_COMBAT") then return true end
		if setFilters.Raid and not C_UnitAuras.IsAuraFilteredOutByInstanceID(filterUnit, auraInstanceID, auraType .. "|RAID") then return true end
	end
end

function UUF:UpdateUnitAuras(unitFrame, unit)
    if not unit or not unitFrame then return end
    if IsGroupAuraPreviewActive(unitFrame, unit) then
        SuspendRealAurasForGroupPreview(unitFrame)
        return
    end

	local managedGroupToken = GetManagedGroupAuraToken(unitFrame, unit)
	if managedGroupToken and not IsManagedGroupAuraUnitObservable(managedGroupToken) then
		unitFrame.UUFManagedAuraObservable = false
		ParkManagedGroupAuraContainers(unitFrame)
		return
	end

    local managedUnit = UsesMidnightManagedAuras(unit)
    unitFrame.UUFManagedAuraMode = managedUnit and true or nil

    if managedUnit then
        unitFrame.Buffs = nil
        unitFrame.Debuffs = nil
        if unitFrame:IsElementEnabled("Auras") then
            unitFrame:DisableElement("Auras")
        end
    end

    local AurasDB = UUF:GetUnitDB(unitFrame, unit).Auras
    if not AurasDB then return end
    local BuffsDB = AurasDB.Buffs
    local DebuffsDB = AurasDB.Debuffs
    local CustomDB = AurasDB.Custom
	local BuffAnchorParent = BuffsDB.AnchorParent == "Health" and unitFrame.Health or unitFrame
	local DebuffAnchorParent = DebuffsDB.AnchorParent == "Health" and unitFrame.Health or unitFrame
	local CustomAuraFilter, CustomAnchorParent
    BuffsDB.Filter = "HELPFUL"
    DebuffsDB.Filter = "HARMFUL"
	if CustomDB then
		CustomAuraFilter = CustomDB.Type == "Debuffs" and "HARMFUL" or "HELPFUL"
		CustomAnchorParent = CustomDB.AnchorParent == "Health" and unitFrame.Health or unitFrame
		CustomDB.Filter = CustomAuraFilter
	end

	local useManagedTargetBuffs = UpdateManagedTargetBuffs(unitFrame, unit, AurasDB, BuffsDB, BuffAnchorParent)
	local useManagedTargetDebuffs = UpdateManagedTargetDebuffs(unitFrame, unit, AurasDB, DebuffsDB, DebuffAnchorParent)
	local useManagedPartyRaidCustom = CustomDB and UpdateManagedPartyRaidCustomAuras(unitFrame, unit, AurasDB, CustomDB, CustomAnchorParent) or false

	if managedUnit then
		unitFrame.Buffs = nil
		unitFrame.Debuffs = nil
		if unitFrame:IsElementEnabled("Auras") then
			unitFrame:DisableElement("Auras")
		end
	end

    if AurasDB.PrivateAuras then
        local PrivateAurasDB = AurasDB.PrivateAuras
        local privateAuraContainerWidth = PrivateAurasDB.Size * PrivateAurasDB.Num + PrivateAurasDB.Spacing * (PrivateAurasDB.Num - 1)
		local PrivateAuraAnchorParent = PrivateAurasDB.AnchorParent == "Health" and unitFrame.Health or unitFrame

        unitFrame.PrivateAuraContainer:ClearAllPoints()
        unitFrame.PrivateAuraContainer:SetPoint(PrivateAurasDB.Layout[1], PrivateAuraAnchorParent, PrivateAurasDB.Layout[2], PrivateAurasDB.Layout[3], PrivateAurasDB.Layout[4])
        unitFrame.PrivateAuraContainer:SetSize(math.max(privateAuraContainerWidth, 1), PrivateAurasDB.Size)
        unitFrame.PrivateAuraContainer:SetFrameStrata(PrivateAurasDB.FrameStrata)
        unitFrame.PrivateAuraContainer.size = PrivateAurasDB.Size
        unitFrame.PrivateAuraContainer.width = nil
        unitFrame.PrivateAuraContainer.height = nil
        unitFrame.PrivateAuraContainer.spacing = PrivateAurasDB.Spacing
        unitFrame.PrivateAuraContainer.spacingX = nil
        unitFrame.PrivateAuraContainer.spacingY = nil
        unitFrame.PrivateAuraContainer.growthX = PrivateAurasDB.GrowthX
        unitFrame.PrivateAuraContainer.growthY = PrivateAurasDB.GrowthY
        unitFrame.PrivateAuraContainer.initialAnchor = PrivateAurasDB.InitialAnchor
        unitFrame.PrivateAuraContainer.num = PrivateAurasDB.Num
        unitFrame.PrivateAuraContainer.maxCols = PrivateAurasDB.Num
        unitFrame.PrivateAuraContainer.borderScale = PrivateAurasDB.BorderScale == -1 and -100 or PrivateAurasDB.BorderScale
        unitFrame.PrivateAuraContainer.disableCooldown = PrivateAurasDB.DisableCooldown
        unitFrame.PrivateAuraContainer.disableCooldownText = PrivateAurasDB.DisableCooldownText

        if PrivateAurasDB.Enabled then
            unitFrame.PrivateAuras = unitFrame.PrivateAuraContainer
            unitFrame.PrivateAuraContainer:Show()
            if not unitFrame:IsElementEnabled("PrivateAuras") then unitFrame:EnableElement("PrivateAuras") end
            if unitFrame.PrivateAuraContainer.ForceUpdate then unitFrame.PrivateAuraContainer:ForceUpdate() end
        else
            if unitFrame:IsElementEnabled("PrivateAuras") then unitFrame:DisableElement("PrivateAuras") end
            unitFrame.PrivateAuras = nil
            unitFrame.PrivateAuraContainer:Hide()
        end
    end

    local shouldEnableAuras = (not managedUnit) and ((BuffsDB.Enabled and not useManagedTargetBuffs) or (DebuffsDB.Enabled and not useManagedTargetDebuffs))

    if BuffsDB.Enabled and not useManagedTargetBuffs then
        unitFrame.Buffs = unitFrame.BuffContainer
        local buffPerRow = BuffsDB.Wrap or 4
        local buffRows = math.ceil(BuffsDB.Num / buffPerRow)
        local buffContainerWidth = (BuffsDB.Size + BuffsDB.Layout[5]) * buffPerRow - BuffsDB.Layout[5]
        local buffContainerHeight = (BuffsDB.Size + BuffsDB.Layout[5]) * buffRows - BuffsDB.Layout[5]
        unitFrame.BuffContainer:ClearAllPoints()
        unitFrame.BuffContainer:SetSize(buffContainerWidth, buffContainerHeight)
        unitFrame.BuffContainer:SetPoint(BuffsDB.Layout[1], BuffAnchorParent, BuffsDB.Layout[2], BuffsDB.Layout[3], BuffsDB.Layout[4])
        unitFrame.BuffContainer:SetFrameStrata(UUF:GetUnitDB(unitFrame, unit).Auras.FrameStrata)
        unitFrame.BuffContainer.size = BuffsDB.Size
        unitFrame.BuffContainer.spacing = BuffsDB.Layout[5]
        unitFrame.BuffContainer.num = BuffsDB.Num
        unitFrame.BuffContainer.initialAnchor = BuffsDB.Layout[1]
        unitFrame.BuffContainer.onlyShowPlayer = BuffsDB.OnlyShowPlayer
        unitFrame.BuffContainer["growthX"] = BuffsDB.GrowthDirection
        unitFrame.BuffContainer["growthY"] = BuffsDB.WrapDirection
        unitFrame.BuffContainer.filter = "HELPFUL"
        UUF:ConfigureAuraSorting(unitFrame.BuffContainer, BuffsDB.Sorting)
        unitFrame.BuffContainer.createdButtons = unitFrame.Buffs.createdButtons or 0
        unitFrame.BuffContainer.anchoredButtons = unitFrame.Buffs.anchoredButtons or 0
        unitFrame.BuffContainer.PostCreateButton = function(_, button) StyleAuras(_, button, unit, "HELPFUL") end
        unitFrame.BuffContainer.PostUpdateButton = function(_, button) StyleAuras(_, button, unit, "HELPFUL", true) end
        unitFrame.BuffContainer.showType = BuffsDB.ShowType
        unitFrame.BuffContainer.showBuffType = BuffsDB.ShowType
        unitFrame.BuffContainer:Show()
    else
        unitFrame.BuffContainer:Hide()
        unitFrame.Buffs = nil
    end

    if DebuffsDB.Enabled and not useManagedTargetDebuffs then
        unitFrame.Debuffs = unitFrame.DebuffContainer
        local debuffPerRow = DebuffsDB.Wrap or 4
        local debuffRows = math.ceil(DebuffsDB.Num / debuffPerRow)
        local debuffContainerWidth = (DebuffsDB.Size + DebuffsDB.Layout[5]) * debuffPerRow - DebuffsDB.Layout[5]
        local debuffContainerHeight = (DebuffsDB.Size + DebuffsDB.Layout[5]) * debuffRows - DebuffsDB.Layout[5]
        unitFrame.DebuffContainer:ClearAllPoints()
        unitFrame.DebuffContainer:SetSize(debuffContainerWidth, debuffContainerHeight)
        unitFrame.DebuffContainer:SetFrameStrata(UUF:GetUnitDB(unitFrame, unit).Auras.FrameStrata)
        unitFrame.DebuffContainer:SetPoint(DebuffsDB.Layout[1], DebuffAnchorParent, DebuffsDB.Layout[2], DebuffsDB.Layout[3], DebuffsDB.Layout[4])
        unitFrame.DebuffContainer.size = DebuffsDB.Size
        unitFrame.DebuffContainer.spacing = DebuffsDB.Layout[5]
        unitFrame.DebuffContainer.num = DebuffsDB.Num
        unitFrame.DebuffContainer.initialAnchor = DebuffsDB.Layout[1]
        unitFrame.DebuffContainer.onlyShowPlayer = DebuffsDB.OnlyShowPlayer
        unitFrame.DebuffContainer["growthX"] = DebuffsDB.GrowthDirection
        unitFrame.DebuffContainer["growthY"] = DebuffsDB.WrapDirection
        unitFrame.DebuffContainer.filter = "HARMFUL"
        UUF:ConfigureAuraSorting(unitFrame.DebuffContainer, DebuffsDB.Sorting)
        unitFrame.DebuffContainer.createdButtons = unitFrame.Debuffs.createdButtons or 0
        unitFrame.DebuffContainer.anchoredButtons = unitFrame.Debuffs.anchoredButtons or 0
        unitFrame.DebuffContainer.PostCreateButton = function(_, button) StyleAuras(_, button, unit, "HARMFUL") end
        unitFrame.DebuffContainer.PostUpdateButton = function(_, button) StyleAuras(_, button, unit, "HARMFUL", true) end
        unitFrame.DebuffContainer.showType = DebuffsDB.ShowType
        unitFrame.DebuffContainer.showDebuffType = DebuffsDB.ShowType
        unitFrame.DebuffContainer:Show()
    else
        unitFrame.DebuffContainer:Hide()
        unitFrame.Debuffs = nil
    end

    if useManagedPartyRaidCustom then
        if unitFrame:IsElementEnabled("CustomAuras") then unitFrame:DisableElement("CustomAuras") end
        if unitFrame.CustomAuraContainer then unitFrame.CustomAuraContainer:Hide() end
        unitFrame.CustomAuras = nil
    elseif unitFrame.CustomAuraContainer and CustomDB then
        if CustomDB.Enabled then
            unitFrame.CustomAuras = unitFrame.CustomAuraContainer
            local customPerRow = CustomDB.Wrap or 3
            local customRows = math.ceil(CustomDB.Num / customPerRow)
            local customContainerWidth = (CustomDB.Size + CustomDB.Layout[5]) * customPerRow - CustomDB.Layout[5]
            local customContainerHeight = (CustomDB.Size + CustomDB.Layout[5]) * customRows - CustomDB.Layout[5]
            unitFrame.CustomAuraContainer:ClearAllPoints()
            unitFrame.CustomAuraContainer:SetSize(customContainerWidth, customContainerHeight)
            unitFrame.CustomAuraContainer:SetFrameStrata(AurasDB.FrameStrata)
            unitFrame.CustomAuraContainer:SetPoint(CustomDB.Layout[1], CustomAnchorParent, CustomDB.Layout[2], CustomDB.Layout[3], CustomDB.Layout[4])
            unitFrame.CustomAuraContainer.size = CustomDB.Size
            unitFrame.CustomAuraContainer.spacing = CustomDB.Layout[5]
            unitFrame.CustomAuraContainer.num = CustomDB.Num
            unitFrame.CustomAuraContainer.initialAnchor = CustomDB.Layout[1]
            unitFrame.CustomAuraContainer.onlyShowPlayer = CustomDB.OnlyShowPlayer
            unitFrame.CustomAuraContainer.growthX = CustomDB.GrowthDirection
            unitFrame.CustomAuraContainer.growthY = CustomDB.WrapDirection
            unitFrame.CustomAuraContainer.filter = CustomAuraFilter
            UUF:ConfigureAuraSorting(unitFrame.CustomAuraContainer, CustomDB.Sorting)
            unitFrame.CustomAuraContainer.FilterAura = function(_, filterUnit, aura, auraType)
				return FilterAura(UUF:GetUnitDB(unitFrame, unit).Auras.Custom, filterUnit, aura, auraType)
            end
            unitFrame.CustomAuraContainer.createdButtons = unitFrame.CustomAuras.createdButtons or 0
            unitFrame.CustomAuraContainer.anchoredButtons = unitFrame.CustomAuras.anchoredButtons or 0
            unitFrame.CustomAuraContainer.PostCreateButton = function(_, button) StyleAuras(_, button, unit, CustomAuraFilter, nil, "Custom") end
            unitFrame.CustomAuraContainer.PostUpdateButton = function(_, button) StyleAuras(_, button, unit, CustomAuraFilter, true, "Custom") end
            unitFrame.CustomAuraContainer.showType = CustomDB.ShowType
            unitFrame.CustomAuraContainer.showBuffType = CustomAuraFilter == "HELPFUL" and CustomDB.ShowType
            unitFrame.CustomAuraContainer.showDebuffType = CustomAuraFilter == "HARMFUL" and CustomDB.ShowType
            unitFrame.CustomAuraContainer:Show()
            if not unitFrame:IsElementEnabled("CustomAuras") then unitFrame:EnableElement("CustomAuras") end
            if unitFrame.CustomAuraContainer.ForceUpdate then unitFrame.CustomAuraContainer:ForceUpdate() end
        else
            if unitFrame:IsElementEnabled("CustomAuras") then unitFrame:DisableElement("CustomAuras") end
            unitFrame.CustomAuraContainer:Hide()
            unitFrame.CustomAuras = nil
        end
    end

    if shouldEnableAuras then
        if not unitFrame:IsElementEnabled("Auras") then unitFrame:EnableElement("Auras") end
        if unitFrame.BuffContainer and unitFrame.BuffContainer.ForceUpdate then unitFrame.BuffContainer:ForceUpdate() end
        if unitFrame.DebuffContainer and unitFrame.DebuffContainer.ForceUpdate then unitFrame.DebuffContainer:ForceUpdate() end
    else
        if unitFrame:IsElementEnabled("Auras") then
            unitFrame:DisableElement("Auras")
        end
    end

    for _, button in ipairs(unitFrame.BuffContainer) do
        if button and button:IsShown() then
            StyleAuras(nil, button, unit, "HELPFUL", true)
        end
    end
    for _, button in ipairs(unitFrame.DebuffContainer) do
        if button and button:IsShown() then
            StyleAuras(nil, button, unit, "HARMFUL", true)
        end
    end
    if not useManagedPartyRaidCustom and unitFrame.CustomAuraContainer and CustomDB then
        for _, button in ipairs(unitFrame.CustomAuraContainer) do
            if button and button:IsShown() then
                StyleAuras(nil, button, unit, CustomAuraFilter, true, "Custom")
            end
        end
    end
    if UUF.AURA_TEST_MODE == true then UUF:CreateTestAuras(unitFrame, unit) end
end

function UUF:CreateUnitAuras(unitFrame, unit)
	local managedUnit = UsesMidnightManagedAuras(unit)
	unitFrame.UUFManagedAuraMode = managedUnit and true or nil
	local AurasDB = UUF:GetUnitDB(unitFrame, unit).Auras
	local BuffsDB = AurasDB.Buffs
	local DebuffsDB = AurasDB.Debuffs
	local CustomDB = AurasDB.Custom
	local useManagedTargetBuffs = managedUnit
	local useManagedTargetDebuffs = managedUnit
	local useManagedPartyRaidCustom = CustomDB and IsUnifiedManagedAuraUnit(unitFrame, unit) or false
	local BuffAnchorParent = BuffsDB.AnchorParent == "Health" and unitFrame.Health or unitFrame
	local DebuffAnchorParent = DebuffsDB.AnchorParent == "Health" and unitFrame.Health or unitFrame
	local CustomAuraFilter, CustomAnchorParent
	BuffsDB.Filter = "HELPFUL"
	DebuffsDB.Filter = "HARMFUL"
	if CustomDB then
		CustomAuraFilter = CustomDB.Type == "Debuffs" and "HARMFUL" or "HELPFUL"
		CustomAnchorParent = CustomDB.AnchorParent == "Health" and unitFrame.Health or unitFrame
		CustomDB.Filter = CustomAuraFilter
	end

	if not unitFrame.BuffContainer then
		unitFrame.BuffContainer = CreateFrame("Frame", UUF:FetchFrameName(unit) .. "_BuffsContainer", unitFrame)
		unitFrame.BuffContainer:SetFrameStrata(AurasDB.FrameStrata)
		local buffPerRow = BuffsDB.Wrap or 4
		local buffRows = math.ceil(BuffsDB.Num / buffPerRow)
		local buffContainerWidth = (BuffsDB.Size + BuffsDB.Layout[5]) * buffPerRow - BuffsDB.Layout[5]
		local buffContainerHeight = (BuffsDB.Size + BuffsDB.Layout[5]) * buffRows - BuffsDB.Layout[5]
		unitFrame.BuffContainer:SetSize(buffContainerWidth, buffContainerHeight)
		unitFrame.BuffContainer:SetPoint(BuffsDB.Layout[1], BuffAnchorParent, BuffsDB.Layout[2], BuffsDB.Layout[3], BuffsDB.Layout[4])
		unitFrame.BuffContainer.size = BuffsDB.Size
		unitFrame.BuffContainer.spacing = BuffsDB.Layout[5]
		unitFrame.BuffContainer.num = BuffsDB.Num
		unitFrame.BuffContainer.initialAnchor = BuffsDB.Layout[1]
		unitFrame.BuffContainer.onlyShowPlayer = BuffsDB.OnlyShowPlayer
		unitFrame.BuffContainer["growthX"] = BuffsDB.GrowthDirection
		unitFrame.BuffContainer["growthY"] = BuffsDB.WrapDirection
		unitFrame.BuffContainer.filter = "HELPFUL"
		UUF:ConfigureAuraSorting(unitFrame.BuffContainer, BuffsDB.Sorting)
		unitFrame.BuffContainer.FilterAura = function(_, filterUnit, aura)
			return FilterAura(UUF:GetUnitDB(unitFrame, unit).Auras.Buffs, filterUnit, aura, "HELPFUL")
		end
		unitFrame.BuffContainer.PostCreateButton = function(_, button) StyleAuras(_, button, unit, "HELPFUL") end
		unitFrame.BuffContainer.PostUpdateButton = function(_, button) StyleAuras(_, button, unit, "HELPFUL", true) end
		unitFrame.BuffContainer.anchoredButtons = 0
		unitFrame.BuffContainer.createdButtons = 0
		unitFrame.BuffContainer.tooltipAnchor = "ANCHOR_CURSOR"
		unitFrame.BuffContainer.showType = BuffsDB.ShowType
		unitFrame.BuffContainer.showBuffType = BuffsDB.ShowType
		unitFrame.BuffContainer.dispelColorCurve = C_CurveUtil.CreateColorCurve()
		unitFrame.BuffContainer.dispelColorCurve:SetType(Enum.LuaCurveType.Step)
		for _, dispelIndex in next, oUF.Enum.DispelType do
			if(oUF.colors.dispel[dispelIndex]) then
				unitFrame.BuffContainer.dispelColorCurve:AddPoint(dispelIndex, oUF.colors.dispel[dispelIndex])
			end
		end
		if not oUF.colors.dispel[0] then unitFrame.BuffContainer.dispelColorCurve:AddPoint(0, CreateColor(0.8, 0, 0, 1)) end

		if BuffsDB.Enabled and not useManagedTargetBuffs then
			unitFrame.Buffs = unitFrame.BuffContainer
		else
			unitFrame.Buffs = nil
		end
	end

	if useManagedTargetBuffs then
		unitFrame.BuffContainer:Hide()
		unitFrame.Buffs = nil
		UpdateManagedTargetBuffs(unitFrame, unit, AurasDB, BuffsDB, BuffAnchorParent)
	end

	if not unitFrame.DebuffContainer then
		unitFrame.DebuffContainer = CreateFrame("Frame", UUF:FetchFrameName(unit) .. "_DebuffsContainer", unitFrame)
		unitFrame.DebuffContainer:SetFrameStrata(AurasDB.FrameStrata)
		local debuffPerRow = DebuffsDB.Wrap or 3
		local debuffRows = math.ceil(DebuffsDB.Num / debuffPerRow)
		local debuffContainerWidth = (DebuffsDB.Size + DebuffsDB.Layout[5]) * debuffPerRow - DebuffsDB.Layout[5]
		local debuffContainerHeight = (DebuffsDB.Size + DebuffsDB.Layout[5]) * debuffRows - DebuffsDB.Layout[5]
		unitFrame.DebuffContainer:SetSize(debuffContainerWidth, debuffContainerHeight)
		unitFrame.DebuffContainer:SetPoint(DebuffsDB.Layout[1], DebuffAnchorParent, DebuffsDB.Layout[2], DebuffsDB.Layout[3], DebuffsDB.Layout[4])
		unitFrame.DebuffContainer.size = DebuffsDB.Size
		unitFrame.DebuffContainer.spacing = DebuffsDB.Layout[5]
		unitFrame.DebuffContainer.num = DebuffsDB.Num
		unitFrame.DebuffContainer.initialAnchor = DebuffsDB.Layout[1]
		unitFrame.DebuffContainer.onlyShowPlayer = DebuffsDB.OnlyShowPlayer
		unitFrame.DebuffContainer["growthX"] = DebuffsDB.GrowthDirection
		unitFrame.DebuffContainer["growthY"] = DebuffsDB.WrapDirection
		unitFrame.DebuffContainer.filter = "HARMFUL"
		UUF:ConfigureAuraSorting(unitFrame.DebuffContainer, DebuffsDB.Sorting)
		unitFrame.DebuffContainer.FilterAura = function(_, filterUnit, aura)
			return FilterAura(UUF:GetUnitDB(unitFrame, unit).Auras.Debuffs, filterUnit, aura, "HARMFUL")
		end

		unitFrame.DebuffContainer.anchoredButtons = 0
		unitFrame.DebuffContainer.createdButtons = 0
		unitFrame.DebuffContainer.PostCreateButton = function(_, button) StyleAuras(_, button, unit, "HARMFUL") end
		unitFrame.DebuffContainer.PostUpdateButton = function(_, button) StyleAuras(_, button, unit, "HARMFUL", true) end
		unitFrame.DebuffContainer.tooltipAnchor = "ANCHOR_CURSOR"
		unitFrame.DebuffContainer.showType = DebuffsDB.ShowType
		unitFrame.DebuffContainer.showDebuffType = DebuffsDB.ShowType
		unitFrame.DebuffContainer.dispelColorCurve = C_CurveUtil.CreateColorCurve()
		unitFrame.DebuffContainer.dispelColorCurve:SetType(Enum.LuaCurveType.Step)

		for _, dispelIndex in next, oUF.Enum.DispelType do
			if(oUF.colors.dispel[dispelIndex]) then
				unitFrame.DebuffContainer.dispelColorCurve:AddPoint(dispelIndex, oUF.colors.dispel[dispelIndex])
			end
		end

		if not oUF.colors.dispel[0] then unitFrame.DebuffContainer.dispelColorCurve:AddPoint(0, CreateColor(0.8, 0, 0, 1)) end

		if DebuffsDB.Enabled and not useManagedTargetDebuffs then
			unitFrame.Debuffs = unitFrame.DebuffContainer
		else
			unitFrame.Debuffs = nil
		end
	end

	if useManagedTargetDebuffs then
		unitFrame.DebuffContainer:Hide()
		unitFrame.Debuffs = nil
		UpdateManagedTargetDebuffs(unitFrame, unit, AurasDB, DebuffsDB, DebuffAnchorParent)
	end

	if CustomDB and not useManagedPartyRaidCustom and not unitFrame.CustomAuraContainer then
		unitFrame.CustomAuraContainer = CreateFrame("Frame", UUF:FetchFrameName(unit) .. "_CustomAurasContainer", unitFrame)
		unitFrame.CustomAuraContainer:SetFrameStrata(AurasDB.FrameStrata)
		local customPerRow = CustomDB.Wrap or 3
		local customRows = math.ceil(CustomDB.Num / customPerRow)
		local customContainerWidth = (CustomDB.Size + CustomDB.Layout[5]) * customPerRow - CustomDB.Layout[5]
		local customContainerHeight = (CustomDB.Size + CustomDB.Layout[5]) * customRows - CustomDB.Layout[5]
		unitFrame.CustomAuraContainer:SetSize(customContainerWidth, customContainerHeight)
		unitFrame.CustomAuraContainer:SetPoint(CustomDB.Layout[1], CustomAnchorParent, CustomDB.Layout[2], CustomDB.Layout[3], CustomDB.Layout[4])
		unitFrame.CustomAuraContainer.size = CustomDB.Size
		unitFrame.CustomAuraContainer.spacing = CustomDB.Layout[5]
		unitFrame.CustomAuraContainer.num = CustomDB.Num
		unitFrame.CustomAuraContainer.initialAnchor = CustomDB.Layout[1]
		unitFrame.CustomAuraContainer.onlyShowPlayer = CustomDB.OnlyShowPlayer
		unitFrame.CustomAuraContainer.growthX = CustomDB.GrowthDirection
		unitFrame.CustomAuraContainer.growthY = CustomDB.WrapDirection
		unitFrame.CustomAuraContainer.filter = CustomAuraFilter
		UUF:ConfigureAuraSorting(unitFrame.CustomAuraContainer, CustomDB.Sorting)
		unitFrame.CustomAuraContainer.FilterAura = function(_, filterUnit, aura, auraType)
			return FilterAura(UUF:GetUnitDB(unitFrame, unit).Auras.Custom, filterUnit, aura, auraType)
		end
		unitFrame.CustomAuraContainer.anchoredButtons = 0
		unitFrame.CustomAuraContainer.createdButtons = 0
		unitFrame.CustomAuraContainer.PostCreateButton = function(_, button) StyleAuras(_, button, unit, CustomAuraFilter, nil, "Custom") end
		unitFrame.CustomAuraContainer.PostUpdateButton = function(_, button) StyleAuras(_, button, unit, CustomAuraFilter, true, "Custom") end
		unitFrame.CustomAuraContainer.tooltipAnchor = "ANCHOR_CURSOR"
		unitFrame.CustomAuraContainer.showType = CustomDB.ShowType
		unitFrame.CustomAuraContainer.showBuffType = CustomAuraFilter == "HELPFUL" and CustomDB.ShowType
		unitFrame.CustomAuraContainer.showDebuffType = CustomAuraFilter == "HARMFUL" and CustomDB.ShowType
		unitFrame.CustomAuraContainer.dispelColorCurve = C_CurveUtil.CreateColorCurve()
		unitFrame.CustomAuraContainer.dispelColorCurve:SetType(Enum.LuaCurveType.Step)

		for _, dispelIndex in next, oUF.Enum.DispelType do
			if(oUF.colors.dispel[dispelIndex]) then
				unitFrame.CustomAuraContainer.dispelColorCurve:AddPoint(dispelIndex, oUF.colors.dispel[dispelIndex])
			end
		end

		if not oUF.colors.dispel[0] then unitFrame.CustomAuraContainer.dispelColorCurve:AddPoint(0, CreateColor(0.8, 0, 0, 1)) end

		if CustomDB.Enabled then
			unitFrame.CustomAuras = unitFrame.CustomAuraContainer
		else
			unitFrame.CustomAuraContainer:Hide()
		end
	end

	if useManagedPartyRaidCustom then
		unitFrame.CustomAuras = nil
		if unitFrame:IsElementEnabled("CustomAuras") then unitFrame:DisableElement("CustomAuras") end
		UpdateManagedPartyRaidCustomAuras(unitFrame, unit, AurasDB, CustomDB, CustomAnchorParent)
	end

    if AurasDB.PrivateAuras then
        local PrivateAurasDB = AurasDB.PrivateAuras
        local privateAuraContainerWidth = PrivateAurasDB.Size * PrivateAurasDB.Num + PrivateAurasDB.Spacing * (PrivateAurasDB.Num - 1)
		local PrivateAuraAnchorParent = PrivateAurasDB.AnchorParent == "Health" and unitFrame.Health or unitFrame

        unitFrame.PrivateAuraContainer = CreateFrame("Frame", UUF:FetchFrameName(unit) .. "_PrivateAurasContainer", unitFrame)
        unitFrame.PrivateAuraContainer:SetPoint(PrivateAurasDB.Layout[1], PrivateAuraAnchorParent, PrivateAurasDB.Layout[2], PrivateAurasDB.Layout[3], PrivateAurasDB.Layout[4])
        unitFrame.PrivateAuraContainer:SetSize(math.max(privateAuraContainerWidth, 1), PrivateAurasDB.Size)
        unitFrame.PrivateAuraContainer:SetFrameStrata(PrivateAurasDB.FrameStrata)
        unitFrame.PrivateAuraContainer.size = PrivateAurasDB.Size
        unitFrame.PrivateAuraContainer.width = nil
        unitFrame.PrivateAuraContainer.height = nil
        unitFrame.PrivateAuraContainer.spacing = PrivateAurasDB.Spacing
        unitFrame.PrivateAuraContainer.spacingX = nil
        unitFrame.PrivateAuraContainer.spacingY = nil
        unitFrame.PrivateAuraContainer.growthX = PrivateAurasDB.GrowthX
        unitFrame.PrivateAuraContainer.growthY = PrivateAurasDB.GrowthY
        unitFrame.PrivateAuraContainer.initialAnchor = PrivateAurasDB.InitialAnchor
        unitFrame.PrivateAuraContainer.num = PrivateAurasDB.Num
        unitFrame.PrivateAuraContainer.maxCols = PrivateAurasDB.Num
        unitFrame.PrivateAuraContainer.borderScale = PrivateAurasDB.BorderScale == -1 and -100 or PrivateAurasDB.BorderScale
        unitFrame.PrivateAuraContainer.disableCooldown = PrivateAurasDB.DisableCooldown
        unitFrame.PrivateAuraContainer.disableCooldownText = PrivateAurasDB.DisableCooldownText

        if PrivateAurasDB.Enabled then
            unitFrame.PrivateAuras = unitFrame.PrivateAuraContainer
        else
            unitFrame.PrivateAuraContainer:Hide()
        end
    end
end

function UUF:UpdateUnitAurasStrata(unit)
    if not unit then return end
    local normalizedUnit = UUF:GetNormalizedUnit(unit)
    local unitFrame = UUF[unit:upper()]
    local unitDB = UUF.db.profile.Units[normalizedUnit]
    if unit == "party" then
        if not unitDB or not unitDB.Auras then return end
        for i = 1, UUF.MAX_PARTY_FRAMES do
            UUF:UpdateUnitAurasStrata("party" .. i)
        end
        if UUF.PARTYPLAYER and unitDB.Auras.PrivateAuras and UUF.PARTYPLAYER.PrivateAuraContainer then UUF.PARTYPLAYER.PrivateAuraContainer:SetFrameStrata(unitDB.Auras.PrivateAuras.FrameStrata) end
        if UUF.PARTY_SOLO_PLAYER then
            if UUF.PARTY_SOLO_PLAYER.UUFManagedTargetBuffs then UUF.PARTY_SOLO_PLAYER.UUFManagedTargetBuffs:SetFrameStrata(unitDB.Auras.FrameStrata) end
            if UUF.PARTY_SOLO_PLAYER.UUFManagedTargetDebuffs then UUF.PARTY_SOLO_PLAYER.UUFManagedTargetDebuffs:SetFrameStrata(unitDB.Auras.FrameStrata) end
            if UUF.PARTY_SOLO_PLAYER.UUFManagedPartyRaidCustomAuras then UUF.PARTY_SOLO_PLAYER.UUFManagedPartyRaidCustomAuras:SetFrameStrata(unitDB.Auras.FrameStrata) end
            if unitDB.Auras.PrivateAuras and UUF.PARTY_SOLO_PLAYER.PrivateAuraContainer then UUF.PARTY_SOLO_PLAYER.PrivateAuraContainer:SetFrameStrata(unitDB.Auras.PrivateAuras.FrameStrata) end
        end
        return
	end
	if unit == "augmentation" then
		UUF:ForEachAugmentationRaidFrame(function(raidFrame, frameUnit)
			local augmentationDB = UUF:GetUnitDB(raidFrame, frameUnit)
			if raidFrame.BuffContainer then raidFrame.BuffContainer:SetFrameStrata(augmentationDB.Auras.FrameStrata) end
			if raidFrame.DebuffContainer then raidFrame.DebuffContainer:SetFrameStrata(augmentationDB.Auras.FrameStrata) end
			if raidFrame.CustomAuraContainer then raidFrame.CustomAuraContainer:SetFrameStrata(augmentationDB.Auras.FrameStrata) end
			if raidFrame.PrivateAuraContainer and augmentationDB.Auras.PrivateAuras then raidFrame.PrivateAuraContainer:SetFrameStrata(augmentationDB.Auras.PrivateAuras.FrameStrata) end
		end, false)
		return
	end
    if not unitFrame or not unitDB or not unitDB.Auras then return end
    if unitFrame.BuffContainer then unitFrame.BuffContainer:SetFrameStrata(unitDB.Auras.FrameStrata) end
    if unitFrame.UUFManagedTargetBuffs then unitFrame.UUFManagedTargetBuffs:SetFrameStrata(unitDB.Auras.FrameStrata) end
    if unitFrame.UUFManagedTargetDebuffs then unitFrame.UUFManagedTargetDebuffs:SetFrameStrata(unitDB.Auras.FrameStrata) end
    if unitFrame.UUFManagedTargetDebuffsClip then unitFrame.UUFManagedTargetDebuffsClip:SetFrameStrata(unitDB.Auras.FrameStrata) end
    if unitFrame.UUFManagedPartyRaidCustomAuras then unitFrame.UUFManagedPartyRaidCustomAuras:SetFrameStrata(unitDB.Auras.FrameStrata) end
    if unitFrame.DebuffContainer then unitFrame.DebuffContainer:SetFrameStrata(unitDB.Auras.FrameStrata) end
    if unitFrame.CustomAuraContainer then unitFrame.CustomAuraContainer:SetFrameStrata(unitDB.Auras.FrameStrata) end
    if unitFrame.PrivateAuraContainer and unitDB.Auras.PrivateAuras then unitFrame.PrivateAuraContainer:SetFrameStrata(unitDB.Auras.PrivateAuras.FrameStrata) end
end

function UUF:CreateTestAuras(unitFrame, unit)
    if not unit then return end
    if not unitFrame then return end
    local General = UUF.db.profile.General
    local AurasDB = UUF:GetUnitDB(unitFrame, unit).Auras
    local BuffsDB = AurasDB.Buffs
    local DebuffsDB = AurasDB.Debuffs
    local CustomDB = AurasDB.Custom
	local BuffAnchorParent = BuffsDB.AnchorParent == "Health" and unitFrame.Health or unitFrame
	local DebuffAnchorParent = DebuffsDB.AnchorParent == "Health" and unitFrame.Health or unitFrame
	local CustomAnchorParent = CustomDB and CustomDB.AnchorParent == "Health" and unitFrame.Health or unitFrame
    if UUF.AURA_TEST_MODE then
        if unitFrame:IsElementEnabled("Auras") then unitFrame:DisableElement("Auras") end
        if unitFrame:IsElementEnabled("CustomAuras") then unitFrame:DisableElement("CustomAuras") end
        if unitFrame.UUFManagedTargetBuffs then unitFrame.UUFManagedTargetBuffs:Hide() end
        if unitFrame.UUFManagedTargetDebuffs then unitFrame.UUFManagedTargetDebuffs:Hide() end
        if unitFrame.UUFManagedTargetDebuffsClip then unitFrame.UUFManagedTargetDebuffsClip:Hide() end
        if unitFrame.UUFManagedPartyRaidCustomAuras then unitFrame.UUFManagedPartyRaidCustomAuras:Hide() end

		if unitFrame.PrivateAuraContainer and AurasDB.PrivateAuras then
			local PrivateAurasDB = AurasDB.PrivateAuras
			if PrivateAurasDB.Enabled then
				unitFrame.PrivateAuraContainer:Show()

				for j = 1, PrivateAurasDB.Num do
					local button = unitFrame.PrivateAuraContainer["fake" .. j]
					if not button then
						button = CreateFrame("Frame", nil, unitFrame.PrivateAuraContainer, "BackdropTemplate")
						button:SetBackdrop(UUF.BACKDROP)
						button:SetBackdropColor(0, 0, 0, 0)
						button:SetBackdropBorderColor(0, 0, 0, 1)

						button.Icon = button:CreateTexture(nil, "BORDER")
						button.Icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
						button.Icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
						button.Icon:SetTexture(135768)
						button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

						button.Cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
						button.Cooldown:SetAllPoints()
						button.Cooldown:SetDrawEdge(false)
						button.Cooldown:SetReverse(true)
						button.Cooldown:SetCooldown(GetTime(), 600)
						unitFrame.PrivateAuraContainer["fake" .. j] = button
					end

					local column = (j - 1) % PrivateAurasDB.Num
					local row = math.floor((j - 1) / PrivateAurasDB.Num)
					local x = column * (PrivateAurasDB.Size + PrivateAurasDB.Spacing)
					local y = row * (PrivateAurasDB.Size + PrivateAurasDB.Spacing)
					if PrivateAurasDB.GrowthX == "LEFT" then x = -x end
					if PrivateAurasDB.GrowthY == "DOWN" then y = -y end

					button:SetSize(PrivateAurasDB.Size, PrivateAurasDB.Size)
					button:SetFrameStrata(PrivateAurasDB.FrameStrata)
					button:ClearAllPoints()
					button:SetPoint(PrivateAurasDB.InitialAnchor, unitFrame.PrivateAuraContainer, PrivateAurasDB.InitialAnchor, x, y)
					button.Cooldown:SetDrawSwipe(not PrivateAurasDB.DisableCooldown)
					button.Cooldown:SetHideCountdownNumbers(PrivateAurasDB.DisableCooldownText)
					button.Cooldown:SetShown(not PrivateAurasDB.DisableCooldown or not PrivateAurasDB.DisableCooldownText)
					button:Show()
				end

				local maxFake = PrivateAurasDB.Num
				for j = maxFake + 1, (unitFrame.PrivateAuraContainer.maxFake or maxFake) do
					local button = unitFrame.PrivateAuraContainer["fake" .. j]
					if button then button:Hide() end
				end
				unitFrame.PrivateAuraContainer.maxFake = PrivateAurasDB.Num
			else
				for j = 1, (unitFrame.PrivateAuraContainer.maxFake or 0) do
					local button = unitFrame.PrivateAuraContainer["fake" .. j]
					if button then button:Hide() end
				end
			end
		end

        if unitFrame.BuffContainer then
            if BuffsDB.Enabled then
                unitFrame.BuffContainer:ClearAllPoints()
                unitFrame.BuffContainer:SetPoint(BuffsDB.Layout[1], BuffAnchorParent, BuffsDB.Layout[2], BuffsDB.Layout[3], BuffsDB.Layout[4])
                unitFrame.BuffContainer:SetFrameStrata(UUF:GetUnitDB(unitFrame, unit).Auras.FrameStrata)
                unitFrame.BuffContainer:Show()
                for _, button in ipairs(unitFrame.BuffContainer) do
                    if button then button:Hide() end
                end

                for j = 1, BuffsDB.Num do
                    local button = unitFrame.BuffContainer["fake" .. j]
                    if not button then
                        button = CreateFrame("Button", nil, unitFrame.BuffContainer, "BackdropTemplate")
                        button:SetBackdrop(UUF.BACKDROP)
                        button:SetBackdropColor(0, 0, 0, 0)
                        button:SetBackdropBorderColor(0, 0, 0, 1)
                        button:SetFrameStrata(UUF:GetUnitDB(unitFrame, unit).Auras.FrameStrata)

                        button.Icon = button:CreateTexture(nil, "BORDER")
                        button.Icon:SetAllPoints()

                        button.Count = button:CreateFontString(nil, "OVERLAY")
                        unitFrame.BuffContainer["fake" .. j] = button
                    end

                    button:SetSize(BuffsDB.Size, BuffsDB.Size)
                    button.Count:ClearAllPoints()
                    button.Count:SetPoint(BuffsDB.Count.Layout[1], button, BuffsDB.Count.Layout[2], BuffsDB.Count.Layout[3], BuffsDB.Count.Layout[4])
                    button.Count:SetFont(UUF.Media.Font, BuffsDB.Count.FontSize, General.Fonts.FontFlag)
                    if General.Fonts.Shadow.Enabled then
                        button.Count:SetShadowColor(unpack(General.Fonts.Shadow.Colour))
                        button.Count:SetShadowOffset(General.Fonts.Shadow.XPos, General.Fonts.Shadow.YPos)
                    else
                        button.Count:SetShadowColor(0, 0, 0, 0)
                        button.Count:SetShadowOffset(0, 0)
                    end
                    button.Count:SetTextColor(unpack(BuffsDB.Count.Colour))

                    local row = math.floor((j - 1) / BuffsDB.Wrap)
                    local col = (j - 1) % BuffsDB.Wrap
                    local x = col * (BuffsDB.Size + BuffsDB.Layout[5])
                    local y = row * (BuffsDB.Size + BuffsDB.Layout[5])
                    if BuffsDB.GrowthDirection == "LEFT" then x = -x end
                    if BuffsDB.WrapDirection == "DOWN" then y = -y end

                    button:ClearAllPoints()
                    button:SetPoint(BuffsDB.Layout[1], unitFrame.BuffContainer, BuffsDB.Layout[1], x, y)

                    button.Icon:SetTexture(135769)
                    button.Icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                    button.Icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                    button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    button.Count:SetText(j)
                    if BuffsDB.Count.HideStacks then button.Count:Hide() else button.Count:Show() end
                    button.Duration = button.Duration or button:CreateFontString(nil, "OVERLAY")
					UUF:ApplyCooldownText(button, button.Duration, unit, unitFrame)
                    button.Duration:SetText("10m")
                    button:Show()
                end

                local maxFake = BuffsDB.Num
                for j = maxFake + 1, (unitFrame.BuffContainer.maxFake or maxFake) do
                    local button = unitFrame.BuffContainer["fake" .. j]
                    if button then button:Hide() end
                end
                unitFrame.BuffContainer.maxFake = BuffsDB.Num
            else
                unitFrame.BuffContainer:Hide()
            end
        end

        if unitFrame.DebuffContainer then
            if DebuffsDB.Enabled then
                unitFrame.DebuffContainer:ClearAllPoints()
                unitFrame.DebuffContainer:SetPoint(DebuffsDB.Layout[1], DebuffAnchorParent, DebuffsDB.Layout[2], DebuffsDB.Layout[3], DebuffsDB.Layout[4])
                unitFrame.DebuffContainer:SetFrameStrata(UUF:GetUnitDB(unitFrame, unit).Auras.FrameStrata)
                unitFrame.DebuffContainer:Show()
                for _, button in ipairs(unitFrame.DebuffContainer) do
                    if button then button:Hide() end
                end

                for j = 1, DebuffsDB.Num do
                    local button = unitFrame.DebuffContainer["fake" .. j]
                    if not button then
                        button = CreateFrame("Button", nil, unitFrame.DebuffContainer, "BackdropTemplate")
                        button:SetBackdrop(UUF.BACKDROP)
                        button:SetBackdropColor(0, 0, 0, 0)
                        button:SetBackdropBorderColor(0, 0, 0, 1)
                        button:SetFrameStrata(UUF:GetUnitDB(unitFrame, unit).Auras.FrameStrata)
                        button.Icon = button:CreateTexture(nil, "BORDER")
                        button.Icon:SetAllPoints()

                        button.Count = button:CreateFontString(nil, "OVERLAY")
                        unitFrame.DebuffContainer["fake" .. j] = button
                    end

                    button:SetSize(DebuffsDB.Size, DebuffsDB.Size)
                    button.Count:ClearAllPoints()
                    button.Count:SetPoint(DebuffsDB.Count.Layout[1], button, DebuffsDB.Count.Layout[2], DebuffsDB.Count.Layout[3], DebuffsDB.Count.Layout[4])
                    button.Count:SetFont(UUF.Media.Font, DebuffsDB.Count.FontSize, General.Fonts.FontFlag)
                    if General.Fonts.Shadow.Enabled then
                        button.Count:SetShadowColor(unpack(General.Fonts.Shadow.Colour))
                        button.Count:SetShadowOffset(General.Fonts.Shadow.XPos, General.Fonts.Shadow.YPos)
                    else
                        button.Count:SetShadowColor(0, 0, 0, 0)
                        button.Count:SetShadowOffset(0, 0)
                    end
                    button.Count:SetTextColor(unpack(DebuffsDB.Count.Colour))

                    local row = math.floor((j - 1) / DebuffsDB.Wrap)
                    local col = (j - 1) % DebuffsDB.Wrap
                    local x = col * (DebuffsDB.Size + DebuffsDB.Layout[5])
                    local y = row * (DebuffsDB.Size + DebuffsDB.Layout[5])
                    if DebuffsDB.GrowthDirection == "LEFT" then x = -x end
                    if DebuffsDB.WrapDirection == "DOWN" then y = -y end

                    button:ClearAllPoints()
                    button:SetPoint(DebuffsDB.Layout[1], unitFrame.DebuffContainer, DebuffsDB.Layout[1], x, y)
                    button.Icon:SetTexture(135768)
                    button.Icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                    button.Icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                    button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    button.Count:SetText(j)
                    if DebuffsDB.Count.HideStacks then button.Count:Hide() else button.Count:Show() end
                    button.Duration = button.Duration or button:CreateFontString(nil, "OVERLAY")
						UUF:ApplyCooldownText(button, button.Duration, unit, unitFrame)
                    button.Duration:SetText("10m")
                    button:Show()
                end

                local maxFake = DebuffsDB.Num
                for j = maxFake + 1, (unitFrame.DebuffContainer.maxFake or maxFake) do
                    local button = unitFrame.DebuffContainer["fake" .. j]
                    if button then button:Hide() end
                end
                unitFrame.DebuffContainer.maxFake = DebuffsDB.Num
            else
                unitFrame.DebuffContainer:Hide()
            end
        end

        if unitFrame.CustomAuraContainer and CustomDB then
            if CustomDB.Enabled then
                unitFrame.CustomAuraContainer:ClearAllPoints()
                unitFrame.CustomAuraContainer:SetPoint(CustomDB.Layout[1], CustomAnchorParent, CustomDB.Layout[2], CustomDB.Layout[3], CustomDB.Layout[4])
                unitFrame.CustomAuraContainer:SetFrameStrata(AurasDB.FrameStrata)
                unitFrame.CustomAuraContainer:Show()
                for _, button in ipairs(unitFrame.CustomAuraContainer) do
                    if button then button:Hide() end
                end

                for j = 1, CustomDB.Num do
                    local button = unitFrame.CustomAuraContainer["fake" .. j]
                    if not button then
                        button = CreateFrame("Button", nil, unitFrame.CustomAuraContainer, "BackdropTemplate")
                        button:SetBackdrop(UUF.BACKDROP)
                        button:SetBackdropColor(0, 0, 0, 0)
                        button:SetBackdropBorderColor(0, 0, 0, 1)
                        button:SetFrameStrata(AurasDB.FrameStrata)
                        button.Icon = button:CreateTexture(nil, "BORDER")
                        button.Icon:SetAllPoints()

                        button.Count = button:CreateFontString(nil, "OVERLAY")
                        unitFrame.CustomAuraContainer["fake" .. j] = button
                    end

                    button:SetSize(CustomDB.Size, CustomDB.Size)
                    button.Count:ClearAllPoints()
                    button.Count:SetPoint(CustomDB.Count.Layout[1], button, CustomDB.Count.Layout[2], CustomDB.Count.Layout[3], CustomDB.Count.Layout[4])
                    button.Count:SetFont(UUF.Media.Font, CustomDB.Count.FontSize, General.Fonts.FontFlag)
                    if General.Fonts.Shadow.Enabled then
                        button.Count:SetShadowColor(unpack(General.Fonts.Shadow.Colour))
                        button.Count:SetShadowOffset(General.Fonts.Shadow.XPos, General.Fonts.Shadow.YPos)
                    else
                        button.Count:SetShadowColor(0, 0, 0, 0)
                        button.Count:SetShadowOffset(0, 0)
                    end
                    button.Count:SetTextColor(unpack(CustomDB.Count.Colour))

                    local row = math.floor((j - 1) / CustomDB.Wrap)
                    local col = (j - 1) % CustomDB.Wrap
                    local x = col * (CustomDB.Size + CustomDB.Layout[5])
                    local y = row * (CustomDB.Size + CustomDB.Layout[5])
                    if CustomDB.GrowthDirection == "LEFT" then x = -x end
                    if CustomDB.WrapDirection == "DOWN" then y = -y end

                    button:ClearAllPoints()
                    button:SetPoint(CustomDB.Layout[1], unitFrame.CustomAuraContainer, CustomDB.Layout[1], x, y)
                    button.Icon:SetTexture(CustomDB.Type == "Debuffs" and 135768 or 135769)
                    button.Icon:SetPoint("TOPLEFT", button, "TOPLEFT", 1, -1)
                    button.Icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
                    button.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    button.Count:SetText(j)
                    if CustomDB.Count.HideStacks then button.Count:Hide() else button.Count:Show() end
                    button.Duration = button.Duration or button:CreateFontString(nil, "OVERLAY")
						UUF:ApplyCooldownText(button, button.Duration, unit, unitFrame)
                    button.Duration:SetText("10m")
                    button:Show()
                end

                local maxFake = CustomDB.Num
                for j = maxFake + 1, (unitFrame.CustomAuraContainer.maxFake or maxFake) do
                    local button = unitFrame.CustomAuraContainer["fake" .. j]
                    if button then button:Hide() end
                end
                unitFrame.CustomAuraContainer.maxFake = CustomDB.Num
            else
                unitFrame.CustomAuraContainer:Hide()
            end
        end
    else
        if unitFrame.BuffContainer then
            for j = 1, (unitFrame.BuffContainer.maxFake or 0) do
                local button = unitFrame.BuffContainer["fake" .. j]
                if button then button:Hide() end
            end
        end
        if unitFrame.DebuffContainer then
            for j = 1, (unitFrame.DebuffContainer.maxFake or 0) do
                local button = unitFrame.DebuffContainer["fake" .. j]
                if button then button:Hide() end
            end
        end
        if unitFrame.CustomAuraContainer then
            for j = 1, (unitFrame.CustomAuraContainer.maxFake or 0) do
                local button = unitFrame.CustomAuraContainer["fake" .. j]
                if button then button:Hide() end
            end
        end
        local managedAuraUnit = UsesMidnightManagedAuras(unit)
        local managedCustom = CustomDB and IsUnifiedManagedAuraUnit(unitFrame, unit)

        -- Party/Raid/Boss configuration pages use fake group frames with their
        -- secure unit attribute cleared. Do not bind real aura containers to the
        -- underlying party/raid/boss unit while that preview is active. Without
        -- this guard, opening the Party page can display the real buffs/debuffs
        -- that were still associated with those frames.
        local groupFrameTestMode =
            ((unit == "party" or unit == "partyplayer" or unit:match("^party%d+$")) and UUF.PARTY_TEST_MODE) or
            ((unit == "raid" or unit:match("^raid%d+$")) and UUF.RAID_TEST_MODE) or
            (unit:match("^boss%d*$") and UUF.BOSS_TEST_MODE)

        if groupFrameTestMode then
            local function HideTestAuraContainer(container)
                if not container then return end
                if container.SetEnabled then pcall(container.SetEnabled, container, false) end
                pcall(container.Hide, container)
            end

            HideTestAuraContainer(unitFrame.UUFManagedTargetBuffs)
            HideTestAuraContainer(unitFrame.UUFManagedTargetDebuffs)
            HideTestAuraContainer(unitFrame.UUFManagedTargetDebuffsClip)
            HideTestAuraContainer(unitFrame.UUFManagedPartyRaidCustomAuras)
            HideTestAuraContainer(unitFrame.BuffContainer)
            HideTestAuraContainer(unitFrame.DebuffContainer)
            HideTestAuraContainer(unitFrame.CustomAuraContainer)

            if unitFrame:IsElementEnabled("Auras") then unitFrame:DisableElement("Auras") end
            if unitFrame:IsElementEnabled("CustomAuras") then unitFrame:DisableElement("CustomAuras") end

            if unitFrame.PrivateAuraContainer then
                unitFrame.PrivateAuraContainer:Hide()
                for j = 1, (unitFrame.PrivateAuraContainer.maxFake or 0) do
                    local button = unitFrame.PrivateAuraContainer["fake" .. j]
                    if button then button:Hide() end
                end
            end
            return
        end

        if managedAuraUnit and (BuffsDB.Enabled or DebuffsDB.Enabled or (CustomDB and CustomDB.Enabled)) then
            unitFrame.Buffs = nil
            unitFrame.Debuffs = nil
            if unitFrame:IsElementEnabled("Auras") then unitFrame:DisableElement("Auras") end
            if unitFrame:IsElementEnabled("CustomAuras") then unitFrame:DisableElement("CustomAuras") end
            UUF:UpdateUnitAuras(unitFrame, unit)
        elseif BuffsDB.Enabled or DebuffsDB.Enabled then
            if not InCombatLockdown() then
                -- Midnight 12.1:
                -- CreateTestAuras puede ejecutarse desde la GUI mientras estamos
                -- en combate. El elemento legacy de oUF usa GetAuraSlots(), que
                -- no puede forzarse cuando las auras son secret.
                if not unitFrame:IsElementEnabled("Auras") then unitFrame:EnableElement("Auras") end
                if unitFrame.BuffContainer and unitFrame.BuffContainer.ForceUpdate then unitFrame.BuffContainer:ForceUpdate() end
                if unitFrame.DebuffContainer and unitFrame.DebuffContainer.ForceUpdate then unitFrame.DebuffContainer:ForceUpdate() end
            end
        end

        if CustomDB and CustomDB.Enabled and not managedCustom then
            unitFrame.CustomAuras = unitFrame.CustomAuraContainer

            -- CustomAuras legacy is kept only for non-managed units.
            if not InCombatLockdown() then
                if not unitFrame:IsElementEnabled("CustomAuras") then unitFrame:EnableElement("CustomAuras") end
                if unitFrame.CustomAuraContainer and unitFrame.CustomAuraContainer.ForceUpdate then
                    unitFrame.CustomAuraContainer:ForceUpdate()
                end
            end
        end
		if unitFrame.PrivateAuraContainer then
			for j = 1, (unitFrame.PrivateAuraContainer.maxFake or 0) do
				local button = unitFrame.PrivateAuraContainer["fake" .. j]
				if button then button:Hide() end
			end
		end
    end
end


-- Party/Raid managed-aura performance diagnostics.
-- This deliberately does not change Player/Target/Focus/Boss behaviour.
-- /uufauraperf raid on     -> force 40 raid test frames with real managed containers
-- /uufauraperf party on    -> force party test frames with real managed containers
-- /uufauraperf raid report -> aggregate AuraGroups and preallocated frames
-- /uufauraperf raid bench 20 -> UpdateAllAuras benchmark (no synthetic auras)
-- /uufauraperf raid off    -> leave forced test mode (reload clears allocations fully)
local AuraPerfDebugState = {
	raidOwned = false,
	partyOwned = false,
	raidMirror = false,
	partyMirror = false,
	previousAuraTestMode = nil,
}

local function AuraPerfPrint(message)
	if UUF.PrettyPrint then
		UUF:PrettyPrint("|cFFFFD100AuraPerf|r " .. tostring(message))
	else
		print("UUF AuraPerf: " .. tostring(message))
	end
end

local function ForEachAuraPerfFrame(groupType, callback)
	if groupType == "raid" then
		if UUF.RAID_TEST_MODE then
			-- Forced mode measures exactly the 40 synthetic raid frames, not the
			-- hidden secure-header frames that may also exist in RAID_FRAMES.
			UUF:ForEachRaidFrame(function(frame, unit)
				if frame and frame.isTestFrame then callback(frame, unit) end
			end, true, true)
		else
			-- Live report: only currently assigned real raid units.
			UUF:ForEachRaidFrame(function(frame, unit, assignedUnit)
				if frame and not frame.isTestFrame and assignedUnit then callback(frame, unit) end
			end, false, false)
		end
		return
	end

	if groupType == "party" then
		if UUF.PARTYPLAYER then callback(UUF.PARTYPLAYER, "partyplayer") end
		for index = 1, UUF.MAX_PARTY_FRAMES do
			local frame = UUF["PARTY" .. index]
			if frame then callback(frame, "party" .. index) end
		end
	end
end

local AuraPerfContainerDefinitions = {
	{ container = "UUFManagedTargetBuffs", active = "UUFManagedBuffGroupKeys", declared = "UUFManagedBuffDeclaredGroupKeys", label = "Buffs" },
	{ container = "UUFManagedTargetDebuffs", active = "UUFManagedDebuffGroupKeys", declared = "UUFManagedDebuffDeclaredGroupKeys", label = "Debuffs" },
	{ container = "UUFManagedPartyRaidCustomAuras", active = "UUFManagedPartyRaidCustomGroupKeys", declared = "UUFManagedPartyRaidCustomDeclaredGroupKeys", label = "Custom" },
}

local function CollectAuraPerfStats(groupType)
	local stats = {
		frames = 0,
		containers = 0,
		activeGroups = 0,
		declaredGroups = 0,
		ownedFrames = 0,
		byType = {},
	}
	for _, definition in ipairs(AuraPerfContainerDefinitions) do
		stats.byType[definition.label] = { containers = 0, activeGroups = 0, declaredGroups = 0, ownedFrames = 0 }
	end

	ForEachAuraPerfFrame(groupType, function(frame)
		stats.frames = stats.frames + 1
		for _, definition in ipairs(AuraPerfContainerDefinitions) do
			local container = frame[definition.container]
			if container then
				stats.containers = stats.containers + 1
				local typeStats = stats.byType[definition.label]
				typeStats.containers = typeStats.containers + 1

				local activeKeys = frame[definition.active] or {}
				local declaredKeys = frame[definition.declared] or activeKeys
				stats.activeGroups = stats.activeGroups + #activeKeys
				typeStats.activeGroups = typeStats.activeGroups + #activeKeys
				stats.declaredGroups = stats.declaredGroups + #declaredKeys
				typeStats.declaredGroups = typeStats.declaredGroups + #declaredKeys

				for _, groupKey in ipairs(declaredKeys) do
					if container.GetAuraGroupFrameCount then
						local ok, count = pcall(container.GetAuraGroupFrameCount, container, groupKey)
						if ok and type(count) == "number" then
							stats.ownedFrames = stats.ownedFrames + count
							typeStats.ownedFrames = typeStats.ownedFrames + count
						end
					end
				end
			end
		end
	end)

	return stats
end

local function ReportAuraPerfStats(groupType)
	local stats = CollectAuraPerfStats(groupType)
	local mirrored = groupType == "raid" and AuraPerfDebugState.raidMirror or AuraPerfDebugState.partyMirror
	local dispelContainers = 0
	local dispelManualAuraHandlers = 0
	ForEachAuraPerfFrame(groupType, function(frame)
		if frame.UUFManagedDispelHighlight then dispelContainers = dispelContainers + 1 end
		local handler = frame.DispelHighlightHandler
		if handler and handler.IsEventRegistered and handler:IsEventRegistered("UNIT_AURA") then
			dispelManualAuraHandlers = dispelManualAuraHandlers + 1
		end
	end)
	AuraPerfPrint(string.format(
		"%s: frames=%d, containers=%d, active groups=%d, declared groups=%d, allocated aura buttons=%d, dispel containers=%d, dispel manual UNIT_AURA=%d, mirror=%s",
		groupType,
		stats.frames,
		stats.containers,
		stats.activeGroups,
		stats.declaredGroups,
		stats.ownedFrames,
		dispelContainers,
		dispelManualAuraHandlers,
		tostring(mirrored == true)
	))
	for _, label in ipairs({ "Buffs", "Debuffs", "Custom" }) do
		local typeStats = stats.byType[label]
		AuraPerfPrint(string.format(
			"%s -> containers=%d, active=%d, declared=%d, allocated=%d",
			label,
			typeStats.containers,
			typeStats.activeGroups,
			typeStats.declaredGroups,
			typeStats.ownedFrames
		))
	end
end

local function SetAuraPerfMirror(groupType, enabled)
	if InCombatLockdown() then
		AuraPerfPrint("activa/desactiva mirror fuera de combate.")
		return
	end

	local forced = groupType == "raid" and UUF.RAID_TEST_MODE or UUF.PARTY_TEST_MODE
	if enabled and not forced then
		AuraPerfPrint("usa primero /uufauraperf " .. groupType .. " on")
		return
	end

	ForEachAuraPerfFrame(groupType, function(frame, unit)
		local token = enabled and "player" or GetManagedAuraUnitToken(frame, unit)
		for _, definition in ipairs(AuraPerfContainerDefinitions) do
			local container = frame[definition.container]
			if container and container.SetUnit then
				pcall(container.SetUnit, container, token)
				pcall(container.UpdateAllAuras, container)
			end
		end

		-- Include the managed dispel-highlight AuraContainer in mirror mode.
		-- This lets a single player's HoTs exercise the same native UNIT_AURA
		-- path used by Party/Raid dispel slots, without a real raid.
		local dispelContainer = frame.UUFManagedDispelHighlight
		if dispelContainer and dispelContainer.SetUnit then
			pcall(dispelContainer.SetUnit, dispelContainer, token)
			pcall(dispelContainer.UpdateAllAuras, dispelContainer)
		end
	end)

	if groupType == "raid" then
		AuraPerfDebugState.raidMirror = enabled == true
	else
		AuraPerfDebugState.partyMirror = enabled == true
	end

	if enabled then
		AuraPerfPrint(groupType .. " mirror enabled: todos los AuraContainers de prueba observan 'player'.")
		AuraPerfPrint("Ahora aplica/renueva HoTs o buffs sobre ti para generar UNIT_AURA real en todos los contenedores.")
	else
		AuraPerfPrint(groupType .. " mirror disabled: restaurados los unit tokens de prueba.")
	end
	ReportAuraPerfStats(groupType)
end

local function SetAuraPerfForcedFrames(groupType, enabled)
	if InCombatLockdown() then
		AuraPerfPrint("sal de combate antes de activar/desactivar el modo de prueba.")
		return
	end

	if enabled then
		if AuraPerfDebugState.previousAuraTestMode == nil then
			AuraPerfDebugState.previousAuraTestMode = UUF.AURA_TEST_MODE == true
		end
		-- Fake aura icons hide the native managed containers, so AuraPerf needs
		-- the real containers enabled on the test unit frames.
		UUF.AURA_TEST_MODE = false

		if groupType == "raid" then
			if not UUF.RAID_TEST_MODE then
				AuraPerfDebugState.raidOwned = true
				UUF.RAID_TEST_MODE = true
				UUF:EnableTestGroupFrames("raid")
			else
				UUF:UpdateTestEnvironment("raid", "Auras")
			end
		elseif groupType == "party" then
			if not UUF.PARTY_TEST_MODE then
				AuraPerfDebugState.partyOwned = true
				UUF.PARTY_TEST_MODE = true
				UUF:EnableTestGroupFrames("party")
			else
				UUF:UpdateTestEnvironment("party", "Auras")
			end
		end

		ReportAuraPerfStats(groupType)
		return
	end

	if groupType == "raid" and AuraPerfDebugState.raidMirror then
		SetAuraPerfMirror("raid", false)
	elseif groupType == "party" and AuraPerfDebugState.partyMirror then
		SetAuraPerfMirror("party", false)
	end

	if groupType == "raid" and AuraPerfDebugState.raidOwned then
		AuraPerfDebugState.raidOwned = false
		UUF.RAID_TEST_MODE = false
		UUF:UpdateTestEnvironment("raid", "all")
	elseif groupType == "party" and AuraPerfDebugState.partyOwned then
		AuraPerfDebugState.partyOwned = false
		UUF.PARTY_TEST_MODE = false
		UUF:UpdateTestEnvironment("party", "all")
	end

	if not AuraPerfDebugState.raidOwned and not AuraPerfDebugState.partyOwned and AuraPerfDebugState.previousAuraTestMode ~= nil then
		UUF.AURA_TEST_MODE = AuraPerfDebugState.previousAuraTestMode
		AuraPerfDebugState.previousAuraTestMode = nil
	end

	AuraPerfPrint(groupType .. " forced test mode disabled. /reload fully releases the test-session allocations.")
end

local function BenchmarkAuraPerf(groupType, iterations)
	if InCombatLockdown() then
		AuraPerfPrint("el benchmark solo se ejecuta fuera de combate.")
		return
	end

	iterations = math.floor(tonumber(iterations) or 20)
	iterations = math.max(1, math.min(iterations, 100))
	local containers = {}
	ForEachAuraPerfFrame(groupType, function(frame)
		for _, definition in ipairs(AuraPerfContainerDefinitions) do
			local container = frame[definition.container]
			if container then containers[#containers + 1] = container end
		end
		if frame.UUFManagedDispelHighlight then
			containers[#containers + 1] = frame.UUFManagedDispelHighlight
		end
	end)

	if #containers == 0 then
		AuraPerfPrint("no hay managed AuraContainers. Usa primero /uufauraperf " .. groupType .. " on")
		return
	end

	local start = debugprofilestop()
	local calls = 0
	for _ = 1, iterations do
		for _, container in ipairs(containers) do
			pcall(container.UpdateAllAuras, container)
			calls = calls + 1
		end
	end
	local elapsed = debugprofilestop() - start
	AuraPerfPrint(string.format(
		"%s benchmark: %d UpdateAllAuras calls in %.2f ms (%.4f ms/call).",
		groupType,
		calls,
		elapsed,
		calls > 0 and elapsed / calls or 0
	))
	AuraPerfPrint("Este benchmark mide overhead del contenedor; no simula HoTs/UNIT_AURA reales.")
end

local HealthPerfEvents = {
	"UNIT_HEALTH",
	"UNIT_MAXHEALTH",
	"UNIT_HEAL_PREDICTION",
	"UNIT_ABSORB_AMOUNT_CHANGED",
	"UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
	"UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
}

local function ReportHealthPredictionPerf(groupType)
	local frames = 0
	local enabled = 0
	local unified = 0
	local leanHealth = 0
	local eventCounts = {}
	for _, event in ipairs(HealthPerfEvents) do eventCounts[event] = 0 end

	ForEachAuraPerfFrame(groupType, function(frame)
		frames = frames + 1
		if frame.HealthPrediction and frame:IsElementEnabled("HealthPrediction") then enabled = enabled + 1 end
		if frame.UUFGroupUnifiedPrediction and frame.Health then unified = unified + 1 end
		if frame.UUFGroupLeanHealth then leanHealth = leanHealth + 1 end
		for _, event in ipairs(HealthPerfEvents) do
			if frame.IsEventRegistered and frame:IsEventRegistered(event) then
				eventCounts[event] = eventCounts[event] + 1
			end
		end
	end)

	local unitDB = UUF.db and UUF.db.profile and UUF.db.profile.Units and UUF.db.profile.Units[groupType]
	local hp = unitDB and unitDB.HealPrediction
	local incoming = hp and hp.IncomingHeal or {}
	local absorbs = hp and hp.Absorbs or {}
	local healAbsorbs = hp and hp.HealAbsorbs or {}
	AuraPerfPrint(string.format(
		"%s healthprediction: frames=%d, legacy element=%d, unified Health=%d, lean Health=%d, IncomingHeal=%s, Absorbs=%s, ShowOverAbsorb=%s, HealAbsorbs=%s",
		groupType, frames, enabled, unified, leanHealth, tostring(incoming.Enabled == true), tostring(absorbs.Enabled == true),
		tostring(absorbs.ShowOverAbsorb == true), tostring(healAbsorbs.Enabled == true)
	))
	AuraPerfPrint(string.format(
		"HP events registered -> HEALTH=%d, MAXHEALTH=%d, HEAL_PREDICTION=%d, ABSORB=%d, HEAL_ABSORB=%d, MAX_MOD=%d",
		eventCounts.UNIT_HEALTH, eventCounts.UNIT_MAXHEALTH, eventCounts.UNIT_HEAL_PREDICTION,
		eventCounts.UNIT_ABSORB_AMOUNT_CHANGED, eventCounts.UNIT_HEAL_ABSORB_AMOUNT_CHANGED,
		eventCounts.UNIT_MAX_HEALTH_MODIFIERS_CHANGED
	))
end

local function BenchmarkFrameElementPerf(groupType, elementName, iterations)
	if InCombatLockdown() then
		AuraPerfPrint("el benchmark solo se ejecuta fuera de combate.")
		return
	end

	iterations = math.floor(tonumber(iterations) or 100)
	iterations = math.max(1, math.min(iterations, 500))
	local runners = {}
	ForEachAuraPerfFrame(groupType, function(frame)
		local element = frame[elementName]
		if element and frame:IsElementEnabled(elementName) then
			local fn = element.ForceUpdate
			if elementName == "Health" and frame.UUFGroupUnifiedPrediction and element.UUFGroupForceHealthUpdate then
				fn = element.UUFGroupForceHealthUpdate
			end
			if fn then runners[#runners + 1] = {fn = fn, element = element} end
		end
	end)

	if #runners == 0 then
		AuraPerfPrint("no hay elementos " .. elementName .. " activos. Usa primero /uufauraperf " .. groupType .. " on")
		return
	end

	for _, runner in ipairs(runners) do pcall(runner.fn, runner.element) end

	local start = debugprofilestop()
	local calls = 0
	local errors = 0
	for _ = 1, iterations do
		for _, runner in ipairs(runners) do
			local ok = pcall(runner.fn, runner.element)
			if ok then calls = calls + 1 else errors = errors + 1 end
		end
	end
	local elapsed = debugprofilestop() - start
	AuraPerfPrint(string.format(
		"%s %s benchmark: %d calls in %.2f ms (%.4f ms/call), errors=%d.",
		groupType, elementName, calls, elapsed, calls > 0 and elapsed / calls or 0, errors
	))
	AuraPerfPrint("Este benchmark usa los unit tokens de los frames de prueba; mide el coste Lua/layout del elemento, no una carga de raid real.")
end

local function BenchmarkPredictionPathPerf(groupType, iterations)
	if InCombatLockdown() then
		AuraPerfPrint("el benchmark solo se ejecuta fuera de combate.")
		return
	end

	iterations = math.floor(tonumber(iterations) or 100)
	iterations = math.max(1, math.min(iterations, 500))
	local runners = {}
	ForEachAuraPerfFrame(groupType, function(frame)
		if frame.UUFGroupUnifiedPrediction and frame.Health and frame.Health.UUFGroupForcePredictionUpdate then
			runners[#runners + 1] = {fn = frame.Health.UUFGroupForcePredictionUpdate, element = frame.Health}
		elseif frame.HealthPrediction and frame:IsElementEnabled("HealthPrediction") and frame.HealthPrediction.ForceUpdate then
			runners[#runners + 1] = {fn = frame.HealthPrediction.ForceUpdate, element = frame.HealthPrediction}
		end
	end)

	if #runners == 0 then
		AuraPerfPrint("no hay ruta de prediction activa. Usa primero /uufauraperf " .. groupType .. " on")
		return
	end

	for _, runner in ipairs(runners) do pcall(runner.fn, runner.element) end
	local start = debugprofilestop()
	local calls = 0
	local errors = 0
	for _ = 1, iterations do
		for _, runner in ipairs(runners) do
			local ok = pcall(runner.fn, runner.element)
			if ok then calls = calls + 1 else errors = errors + 1 end
		end
	end
	local elapsed = debugprofilestop() - start
	AuraPerfPrint(string.format(
		"%s prediction-path benchmark: %d calls in %.2f ms (%.4f ms/call), errors=%d.",
		groupType, calls, elapsed, calls > 0 and elapsed / calls or 0, errors
	))
end

local function SetHealthPredictionPerfEnabled(groupType, enabled)
	if InCombatLockdown() then
		AuraPerfPrint("activa/desactiva HealthPrediction fuera de combate.")
		return
	end

	local changed = 0
	ForEachAuraPerfFrame(groupType, function(frame, unit)
		if not frame.HealthPrediction then return end
		if enabled then
			if not frame:IsElementEnabled("HealthPrediction") then
				frame:EnableElement("HealthPrediction", frame.unit or (unit == "partyplayer" and "player" or unit))
				if frame.HealthPrediction.ForceUpdate then pcall(frame.HealthPrediction.ForceUpdate, frame.HealthPrediction) end
				changed = changed + 1
			end
		else
			if frame:IsElementEnabled("HealthPrediction") then
				frame:DisableElement("HealthPrediction", frame.unit or (unit == "partyplayer" and "player" or unit))
				changed = changed + 1
			end
		end
	end)
	AuraPerfPrint(string.format("%s HealthPrediction %s en %d frames.", groupType, enabled and "enabled" or "disabled", changed))
	ReportHealthPredictionPerf(groupType)
end

SLASH_UUFAURAPERF1 = "/uufauraperf"
SlashCmdList["UUFAURAPERF"] = function(message)
	local groupType, command, value = tostring(message or ""):lower():match("^%s*(%S*)%s*(%S*)%s*(%S*)")
	if groupType ~= "raid" and groupType ~= "party" then
		AuraPerfPrint("uso: /uufauraperf raid|party on|off|report|bench|hpreport|hpbench|healthbench|hpon|hpoff|mirror on|off")
		return
	end

	if command == "on" then
		SetAuraPerfForcedFrames(groupType, true)
	elseif command == "off" then
		SetAuraPerfForcedFrames(groupType, false)
	elseif command == "report" then
		ReportAuraPerfStats(groupType)
	elseif command == "bench" then
		BenchmarkAuraPerf(groupType, value)
	elseif command == "hpreport" then
		ReportHealthPredictionPerf(groupType)
	elseif command == "hpbench" then
		BenchmarkPredictionPathPerf(groupType, value)
	elseif command == "healthbench" then
		BenchmarkFrameElementPerf(groupType, "Health", value)
	elseif command == "hpoff" then
		SetHealthPredictionPerfEnabled(groupType, false)
	elseif command == "hpon" then
		SetHealthPredictionPerfEnabled(groupType, true)
	elseif command == "mirror" and (value == "on" or value == "off") then
		SetAuraPerfMirror(groupType, value == "on")
	else
		AuraPerfPrint("uso: /uufauraperf " .. groupType .. " on|off|report|bench|hpreport|hpbench|healthbench|hpon|hpoff|mirror on|off")
	end
end


-- Party/Raid synthetic stress harness.
-- Diagnostic only. It deliberately drives the existing update paths on the
-- forced test frames so performance can be compared without assembling a raid.
-- It does NOT synthesize Blizzard UNIT_AURA payloads; aura mode uses the public
-- container UpdateAllAuras path as a controlled worst-case refresh load.
local AuraStressState = {
	ticker = nil,
	groupType = nil,
	mode = nil,
	hz = 0,
	frames = nil,
	startedAt = 0,
	ticks = 0,
	calls = 0,
	luaMs = 0,
	worstTickMs = 0,
	errors = 0,
}

local function AuraStressPrint(message)
	if UUF.PrettyPrint then
		UUF:PrettyPrint("|cFFFF7A59Stress|r " .. tostring(message))
	else
		print("UUF Stress: " .. tostring(message))
	end
end

local function AuraStressResetCounters()
	AuraStressState.startedAt = GetTime()
	AuraStressState.ticks = 0
	AuraStressState.calls = 0
	AuraStressState.luaMs = 0
	AuraStressState.worstTickMs = 0
	AuraStressState.errors = 0
end

local function AuraStressReport()
	if not AuraStressState.ticker then
		AuraStressPrint("no hay stress activo. Usa /uufstress raid|party aura|health|hp|all [Hz]")
		return
	end

	local duration = math.max(GetTime() - AuraStressState.startedAt, 0.001)
	local avgTick = AuraStressState.ticks > 0 and AuraStressState.luaMs / AuraStressState.ticks or 0
	AuraStressPrint(string.format(
		"%s mode=%s, frames=%d, target=%d Hz, duration=%.1fs, ticks=%d, calls=%d, errors=%d",
		tostring(AuraStressState.groupType), tostring(AuraStressState.mode), #(AuraStressState.frames or {}),
		AuraStressState.hz, duration, AuraStressState.ticks, AuraStressState.calls, AuraStressState.errors
	))
	AuraStressPrint(string.format(
		"Lua=%.2f ms total (%.2f ms/s), avg tick=%.3f ms, worst tick=%.3f ms, calls/s=%.0f",
		AuraStressState.luaMs, AuraStressState.luaMs / duration, avgTick, AuraStressState.worstTickMs,
		AuraStressState.calls / duration
	))
end

local function AuraStressStop(printReport)
	if not AuraStressState.ticker then
		AuraStressPrint("no hay stress activo.")
		return
	end

	if printReport then AuraStressReport() end
	AuraStressState.ticker:Cancel()
	AuraStressState.ticker = nil
	AuraStressState.groupType = nil
	AuraStressState.mode = nil
	AuraStressState.hz = 0
	AuraStressState.frames = nil
	AuraStressPrint("stress detenido. Los frames de prueba siguen activos; usa /uufauraperf raid|party off cuando termines.")
end

local function AuraStressTick()
	local state = AuraStressState
	if not state.ticker or not state.frames then return end

	local start = debugprofilestop()
	local calls = 0
	local errors = 0

	for _, frame in ipairs(state.frames) do
		if state.mode == "aura" or state.mode == "all" then
			for _, definition in ipairs(AuraPerfContainerDefinitions) do
				local container = frame[definition.container]
				if container and container.UpdateAllAuras then
					local ok = pcall(container.UpdateAllAuras, container)
					if ok then calls = calls + 1 else errors = errors + 1 end
				end
			end
			local dispel = frame.UUFManagedDispelHighlight
			if dispel and dispel.UpdateAllAuras then
				local ok = pcall(dispel.UpdateAllAuras, dispel)
				if ok then calls = calls + 1 else errors = errors + 1 end
			end
		end

		if state.mode == "health" or state.mode == "all" then
			local health = frame.Health
			if health and frame:IsElementEnabled("Health") then
				local updater = frame.UUFGroupUnifiedPrediction and health.UUFGroupForceHealthUpdate or health.ForceUpdate
				if updater then
					local ok = pcall(updater, health)
					if ok then calls = calls + 1 else errors = errors + 1 end
				end
			end
		end

		if state.mode == "hp" or state.mode == "all" then
			if frame.UUFGroupUnifiedPrediction then
				local health = frame.Health
				local updater = health and health.UUFGroupForcePredictionUpdate
				if updater then
					local ok = pcall(updater, health)
					if ok then calls = calls + 1 else errors = errors + 1 end
				end
			else
				local hp = frame.HealthPrediction
				if hp and hp.ForceUpdate and frame:IsElementEnabled("HealthPrediction") then
					local ok = pcall(hp.ForceUpdate, hp)
					if ok then calls = calls + 1 else errors = errors + 1 end
				end
			end
		end
	end

	local elapsed = debugprofilestop() - start
	state.ticks = state.ticks + 1
	state.calls = state.calls + calls
	state.errors = state.errors + errors
	state.luaMs = state.luaMs + elapsed
	if elapsed > state.worstTickMs then state.worstTickMs = elapsed end
end

local function AuraStressStart(groupType, mode, hz)
	if InCombatLockdown() then
		AuraStressPrint("inicia/detén el stress fuera de combate.")
		return
	end
	if AuraStressState.ticker then
		AuraStressPrint("ya hay un stress activo. Usa /uufstress stop antes de iniciar otro.")
		return
	end
	if mode ~= "aura" and mode ~= "health" and mode ~= "hp" and mode ~= "all" then
		AuraStressPrint("modos: aura | health | hp | all")
		return
	end

	hz = math.floor(tonumber(hz) or 20)
	hz = math.max(1, math.min(hz, 60))

	local forced = groupType == "raid" and UUF.RAID_TEST_MODE or UUF.PARTY_TEST_MODE
	if not forced then
		SetAuraPerfForcedFrames(groupType, true)
	end
	local mirrored = groupType == "raid" and AuraPerfDebugState.raidMirror or AuraPerfDebugState.partyMirror
	if not mirrored then
		SetAuraPerfMirror(groupType, true)
	end

	local frames = {}
	ForEachAuraPerfFrame(groupType, function(frame)
		frames[#frames + 1] = frame
	end)
	if #frames == 0 then
		AuraStressPrint("no he encontrado frames de prueba.")
		return
	end

	AuraStressState.groupType = groupType
	AuraStressState.mode = mode
	AuraStressState.hz = hz
	AuraStressState.frames = frames
	AuraStressResetCounters()
	AuraStressState.ticker = C_Timer.NewTicker(1 / hz, AuraStressTick)

	local callsPerTick = 0
	if mode == "aura" then callsPerTick = #frames * 4
	elseif mode == "health" or mode == "hp" then callsPerTick = #frames
	else callsPerTick = #frames * 6 end
	AuraStressPrint(string.format(
		"%s %s iniciado: %d frames, %d Hz, hasta ~%d llamadas/s. Mira FPS durante 20-30s.",
		groupType, mode, #frames, hz, callsPerTick * hz
	))
	AuraStressPrint("Usa /uufstress report y después /uufstress stop. Puedes repetir a 20, 40 o 60 Hz.")
end

SLASH_UUFSTRESS1 = "/uufstress"
SlashCmdList["UUFSTRESS"] = function(message)
	local first, second, third = tostring(message or ""):lower():match("^%s*(%S*)%s*(%S*)%s*(%S*)")
	if first == "report" then
		AuraStressReport()
		return
	elseif first == "stop" then
		AuraStressStop(true)
		return
	end

	if first ~= "raid" and first ~= "party" then
		AuraStressPrint("uso: /uufstress raid|party aura|health|hp|all [Hz] | report | stop")
		return
	end
	AuraStressStart(first, second, third)
end


-- Party/Raid live performance profiler.
-- Diagnostic only: wraps existing UUF/oUF handlers and addon-owned managed
-- AuraContainer methods while active; it does not change filtering/layout.
--
-- /uufperf start            -> auto-detect raid/party and start sampling
-- /uufperf raid start       -> start sampling raid frames
-- /uufperf party start      -> start sampling party frames
-- /uufperf report           -> print current sample without stopping
-- /uufperf stop             -> print final sample and restore wrappers
-- /uufperf reset            -> stop without report and clear sample
local LivePerfState = {
	active = false,
	groupType = nil,
	startedAt = 0,
	frames = 0,
	wrappers = {},
	wrapperFailures = 0,
	frameEvents = {},
	callbacks = {},
	observed = {},
	observerPool = {},
}

local function LivePerfPrint(message)
	if UUF.PrettyPrint then
		UUF:PrettyPrint("|cFF4DD0E1Perf|r " .. tostring(message))
	else
		print("UUF Perf: " .. tostring(message))
	end
end

local function LivePerfNewStat()
	return { calls = 0, total = 0, max = 0 }
end

local function LivePerfRecord(bucket, key, elapsed)
	local stat = bucket[key]
	if not stat then
		stat = LivePerfNewStat()
		bucket[key] = stat
	end
	stat.calls = stat.calls + 1
	stat.total = stat.total + elapsed
	if elapsed > stat.max then stat.max = elapsed end
end

local function LivePerfRecordCount(bucket, key)
	local stat = bucket[key]
	if not stat then
		stat = LivePerfNewStat()
		bucket[key] = stat
	end
	stat.calls = stat.calls + 1
end

local function LivePerfResetStats()
	LivePerfState.startedAt = debugprofilestop()
	LivePerfState.frameEvents = {}
	LivePerfState.callbacks = {}
	LivePerfState.observed = {}
end

local function LivePerfStoreWrapper(owner, key, original, wrapper)
	LivePerfState.wrappers[#LivePerfState.wrappers + 1] = {
		owner = owner,
		key = key,
		original = original,
		wrapper = wrapper,
	}
end

local function LivePerfAssign(owner, key, value)
	local ok = pcall(function() owner[key] = value end)
	if not ok then
		LivePerfState.wrapperFailures = LivePerfState.wrapperFailures + 1
		return false
	end
	local readOK, current = pcall(function() return owner[key] end)
	if not readOK or current ~= value then
		LivePerfState.wrapperFailures = LivePerfState.wrapperFailures + 1
		return false
	end
	return true
end

local function LivePerfWrapFrameEvent(frame, event)
	local original = frame[event]
	if not original then return end

	local wrapper = function(self, ...)
		local started = debugprofilestop()
		original(self, ...)
		LivePerfRecord(LivePerfState.frameEvents, event, debugprofilestop() - started)
	end

	if LivePerfAssign(frame, event, wrapper) then
		LivePerfStoreWrapper(frame, event, original, wrapper)
	end
end

local function LivePerfWrapCallback(owner, key, label)
	if not owner then return end
	local original = owner[key]
	if type(original) ~= "function" then return end

	local wrapper = function(self, ...)
		local started = debugprofilestop()
		original(self, ...)
		LivePerfRecord(LivePerfState.callbacks, label, debugprofilestop() - started)
	end

	if LivePerfAssign(owner, key, wrapper) then
		LivePerfStoreWrapper(owner, key, original, wrapper)
	end
end

local function LivePerfRestoreWrappers()
	local skipped = 0
	for index = #LivePerfState.wrappers, 1, -1 do
		local entry = LivePerfState.wrappers[index]
		local readOK, current = pcall(function() return entry.owner[entry.key] end)
		if readOK and current == entry.wrapper then
			local restored = pcall(function() entry.owner[entry.key] = entry.original end)
			if not restored then skipped = skipped + 1 end
		else
			skipped = skipped + 1
		end
	end
	LivePerfState.wrappers = {}
	return skipped
end

local function LivePerfGetObserver(unitToken)
	local observer = LivePerfState.observerPool[unitToken]
	if observer then return observer end

	observer = CreateFrame("Frame")
	observer:SetScript("OnEvent", function()
		if LivePerfState.active then
			LivePerfRecordCount(LivePerfState.observed, "UNIT_AURA observed")
		end
	end)
	LivePerfState.observerPool[unitToken] = observer
	return observer
end

local function LivePerfSetAuraObservers(groupType, enabled)
	local tokens = {}
	if groupType == "raid" then
		for index = 1, UUF.MAX_RAID_FRAMES do tokens[#tokens + 1] = "raid" .. index end
	else
		tokens[#tokens + 1] = "player"
		for index = 1, UUF.MAX_PARTY_FRAMES do tokens[#tokens + 1] = "party" .. index end
	end

	for _, unitToken in ipairs(tokens) do
		local observer = LivePerfGetObserver(unitToken)
		if enabled then
			pcall(observer.RegisterUnitEvent, observer, "UNIT_AURA", unitToken)
		else
			pcall(observer.UnregisterEvent, observer, "UNIT_AURA")
		end
	end
end

local function LivePerfCollectFrames(groupType)
	local frames = {}
	local seen = {}
	ForEachAuraPerfFrame(groupType, function(frame)
		if frame and not seen[frame] then
			seen[frame] = true
			frames[#frames + 1] = frame
		end
	end)
	return frames
end

local function LivePerfInstall(groupType)
	local frames = LivePerfCollectFrames(groupType)
	if #frames == 0 then
		LivePerfPrint("no hay frames " .. groupType .. " activos. Entra en un grupo o usa /uufauraperf " .. groupType .. " on para pruebas sintéticas.")
		return false
	end

	LivePerfState.frames = #frames
	LivePerfState.wrapperFailures = 0

	for _, frame in ipairs(frames) do
		-- oUF stores unit-specific registrations in unitEvents. Wrapping the
		-- dispatch target measures the real Lua work run for each visible frame.
		if frame.unitEvents then
			for event in pairs(frame.unitEvents) do
				LivePerfWrapFrameEvent(frame, event)
			end
		end

		-- Small nested probes identify UUF's custom work inside the stock oUF
		-- Health / HealthPrediction event paths.
		LivePerfWrapCallback(frame.Health, "PostUpdate", "Health.PostUpdate")
		LivePerfWrapCallback(frame.Health, "PostUpdateColor", "Health.PostUpdateColor")
		LivePerfWrapCallback(frame.HealthPrediction, "PostUpdate", "HealthPrediction.PostUpdate")
	end

	-- UNIT_AURA can carry restricted aura data in 12.1. The profiler never
	-- inspects its payload and does not wrap Blizzard AuraContainer methods;
	-- these passive unit-event observers only count event pressure.
	LivePerfSetAuraObservers(groupType, true)
	return true
end

local function LivePerfSortedStats(bucket)
	local rows = {}
	for key, stat in pairs(bucket) do
		rows[#rows + 1] = { key = key, stat = stat }
	end
	table.sort(rows, function(a, b)
		if a.stat.total == b.stat.total then return a.stat.calls > b.stat.calls end
		return a.stat.total > b.stat.total
	end)
	return rows
end

local function LivePerfPrintBucket(title, bucket, durationSeconds, maxRows)
	local rows = LivePerfSortedStats(bucket)
	if #rows == 0 then
		LivePerfPrint(title .. ": sin llamadas registradas.")
		return
	end

	LivePerfPrint(title .. ":")
	local count = math.min(#rows, maxRows or #rows)
	for index = 1, count do
		local row = rows[index]
		local stat = row.stat
		local avg = stat.calls > 0 and stat.total / stat.calls or 0
		local rate = durationSeconds > 0 and stat.calls / durationSeconds or 0
		LivePerfPrint(string.format(
			"%s -> %d calls, %.2f ms total, %.4f avg, %.3f max, %.1f/s",
			row.key, stat.calls, stat.total, avg, stat.max, rate
		))
	end
end

local function LivePerfPrintCountBucket(title, bucket, durationSeconds)
	local rows = LivePerfSortedStats(bucket)
	if #rows == 0 then
		LivePerfPrint(title .. ": sin eventos registrados.")
		return
	end
	LivePerfPrint(title .. ":")
	for _, row in ipairs(rows) do
		local rate = durationSeconds > 0 and row.stat.calls / durationSeconds or 0
		LivePerfPrint(string.format("%s -> %d eventos, %.1f/s", row.key, row.stat.calls, rate))
	end
end

local function LivePerfReport()
	if not LivePerfState.active then
		LivePerfPrint("no hay una captura activa. Usa /uufperf start o /uufperf raid|party start.")
		return
	end

	local elapsedMs = debugprofilestop() - LivePerfState.startedAt
	local durationSeconds = math.max(elapsedMs / 1000, 0.001)
	LivePerfPrint(string.format(
		"%s sample: %.1fs, frames=%d, wrappers=%d, wrapper failures=%d.",
		LivePerfState.groupType, durationSeconds, LivePerfState.frames, #LivePerfState.wrappers, LivePerfState.wrapperFailures
	))
	LivePerfPrint("Los tiempos son instrumentacion Lua de UUF/oUF; no equivalen al frame time total del cliente.")
	LivePerfPrintBucket("Top frame events", LivePerfState.frameEvents, durationSeconds, 12)
	LivePerfPrintBucket("UUF callbacks", LivePerfState.callbacks, durationSeconds, 8)
	LivePerfPrintCountBucket("Passive event pressure", LivePerfState.observed, durationSeconds)
end

local function LivePerfStart(groupType)
	if InCombatLockdown() then
		LivePerfPrint("inicia el profiler fuera de combate, antes del pull.")
		return
	end
	if LivePerfState.active then
		LivePerfPrint("ya hay una captura activa de " .. tostring(LivePerfState.groupType) .. ". Usa /uufperf stop antes de iniciar otra.")
		return
	end

	if groupType ~= "raid" and groupType ~= "party" then
		if IsInRaid and IsInRaid() then
			groupType = "raid"
		elseif IsInGroup and IsInGroup() then
			groupType = "party"
		else
			LivePerfPrint("no puedo autodetectar grupo. Usa /uufperf raid start o /uufperf party start.")
			return
		end
	end

	LivePerfState.groupType = groupType
	LivePerfState.active = true
	LivePerfResetStats()
	if not LivePerfInstall(groupType) then
		LivePerfSetAuraObservers(groupType, false)
		LivePerfState.active = false
		LivePerfState.groupType = nil
		LivePerfRestoreWrappers()
		return
	end
	LivePerfPrint(groupType .. " profiler iniciado en " .. LivePerfState.frames .. " frames. Déjalo 30-60s durante curación intensa y usa /uufperf report.")
	LivePerfPrint("No cambies opciones de UUF durante la captura. /uufperf report es seguro durante combate; usa /uufperf stop al terminar el pull.")
end

local function LivePerfStop(printReport)
	if not LivePerfState.active then
		LivePerfPrint("no hay una captura activa.")
		return
	end
	if InCombatLockdown() then
		if printReport then LivePerfReport() end
		LivePerfPrint("espera a salir de combate para /uufperf stop; no restauro handlers de frames seguros durante el pull.")
		return
	end
	if printReport then LivePerfReport() end
	LivePerfSetAuraObservers(LivePerfState.groupType, false)
	local skipped = LivePerfRestoreWrappers()
	LivePerfState.active = false
	LivePerfState.groupType = nil
	LivePerfState.frames = 0
	if skipped > 0 then
		LivePerfPrint("profiler detenido; " .. skipped .. " wrappers cambiaron durante la captura y no se sobrescribieron al restaurar.")
	else
		LivePerfPrint("profiler detenido y wrappers restaurados.")
	end
end

SLASH_UUFLIVEPERF1 = "/uufperf"
SlashCmdList["UUFLIVEPERF"] = function(message)
	local first, second = tostring(message or ""):lower():match("^%s*(%S*)%s*(%S*)")

	if first == "start" then
		LivePerfStart(nil)
	elseif first == "raid" or first == "party" then
		if second == "start" then
			LivePerfStart(first)
		else
			LivePerfPrint("uso: /uufperf raid|party start")
		end
	elseif first == "report" then
		LivePerfReport()
	elseif first == "stop" then
		LivePerfStop(true)
	elseif first == "reset" then
		LivePerfStop(false)
		LivePerfResetStats()
	else
		LivePerfPrint("uso: /uufperf start | raid start | party start | report | stop | reset")
	end
end
