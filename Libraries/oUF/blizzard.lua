local _, ns = ...
local oUF = ns.oUF

-- sourced from Blizzard_UnitFrame/Mainline/TargetFrame.lua
local MAX_BOSS_FRAMES = _G.MAX_BOSS_FRAMES or 5

-- sourced from Blizzard_FrameXMLBase/Shared/Constants.lua
local MEMBERS_PER_RAID_GROUP = _G.MEMBERS_PER_RAID_GROUP or 5

local hookedFrames = {}
local isArenaHooked = false
local isBossHooked = false
local isPartyHooked = false

local hiddenParent = CreateFrame('Frame', nil, UIParent)
hiddenParent:SetAllPoints()
hiddenParent:Hide()

local function shouldDisableBlizzard(unit)
	if oUF.ShouldDisableBlizzard then
		local ok, result = pcall(oUF.ShouldDisableBlizzard, oUF, unit)
		if ok and result ~= nil then
			return result and true or false
		end
	end

	return true
end

local looseFrames = {}
local watcher = CreateFrame('Frame')
watcher:RegisterEvent('PLAYER_REGEN_ENABLED')
watcher:SetScript('OnEvent', function()
	for frame in next, looseFrames do
		frame:SetParent(hiddenParent)
	end

	table.wipe(looseFrames)
end)

local function resetParent(self, parent)
	if(parent ~= hiddenParent) then
		if(InCombatLockdown() and self:IsProtected()) then
			looseFrames[self] = true
		else
			self:SetParent(hiddenParent)
		end
	end
end

local pendingManagedFrames = {}

local function detachFromManagedFrameContainer(frame)
	if not frame then return false end

	-- Impide que Blizzard vuelva a colocar automáticamente el frame
	-- dentro de PlayerBottomManagedFrameContainer u otro managed container.
	frame.ignoreFramePositionManager = true

	if InCombatLockdown() then
		pendingManagedFrames[frame] = true
		return false
	end

	if frame.SetAttribute then
		pcall(frame.SetAttribute, frame, "ignoreFramePositionManager", true)
	end

	if frame:GetParent() ~= UIParent then
		pcall(frame.SetParent, frame, UIParent)
	end

	pendingManagedFrames[frame] = nil
	return true
end

local function refreshIndependentBlizzardFrames()
	-- Player UUF/Blizzard oculto + Pet Blizzard visible.
	if shouldDisableBlizzard('player') and not shouldDisableBlizzard('pet') then
		local petFrame = _G.PetFrame
		if petFrame and detachFromManagedFrameContainer(petFrame) then
			if UnitExists('pet') then
				pcall(petFrame.Show, petFrame)
			else
				pcall(petFrame.Hide, petFrame)
			end
		end
	end
end

local independentFrameWatcher = CreateFrame('Frame')
independentFrameWatcher:RegisterEvent('PLAYER_ENTERING_WORLD')
independentFrameWatcher:RegisterEvent('UNIT_PET')
independentFrameWatcher:RegisterEvent('PLAYER_REGEN_ENABLED')
independentFrameWatcher:SetScript('OnEvent', function(_, event, unit)
	if event == 'UNIT_PET' and unit ~= 'player' then return end

	if event == 'PLAYER_REGEN_ENABLED' then
		for frame in next, pendingManagedFrames do
			detachFromManagedFrameContainer(frame)
		end
	end

	refreshIndependentBlizzardFrames()
end)

local function hideFrame(frame, doNotReparent, keepEventsAlive)
	if not frame then return end

	-- Si otra unidad Blizzard depende de este frame (Pet de Player,
	-- ToT de Target/Focus), lo ocultamos visualmente pero dejamos sus
	-- eventos y subframes funcionando.
	if keepEventsAlive then
		frame:Hide()

		if not doNotReparent then
			frame:SetParent(hiddenParent)

			if not hookedFrames[frame] then
				hooksecurefunc(frame, 'SetParent', resetParent)
				hookedFrames[frame] = true
			end
		end
		return
	end

	-- Camino original de oUF cuando no hay ninguna dependencia que preservar.
	frame:UnregisterAllEvents()
	frame:Hide()

	if not doNotReparent then
		frame:SetParent(hiddenParent)

		if not hookedFrames[frame] then
			hooksecurefunc(frame, 'SetParent', resetParent)
			hookedFrames[frame] = true
		end
	end

	local health = frame.healthBar or frame.healthbar or frame.HealthBar or (frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar)
	if health then health:UnregisterAllEvents() end

	local power = frame.manabar or frame.ManaBar
	if power then power:UnregisterAllEvents() end

	local castbar = frame.castBar or frame.spellbar or frame.CastingBarFrame
	if castbar then castbar:UnregisterAllEvents() end

	local altpowerbar = frame.powerBarAlt or frame.PowerBarAlt
	if altpowerbar then altpowerbar:UnregisterAllEvents() end

	local buffFrame = frame.BuffFrame or frame.AurasFrame
	if buffFrame then buffFrame:UnregisterAllEvents() end

	local petFrame = frame.petFrame or frame.PetFrame
	if petFrame then petFrame:UnregisterAllEvents() end

	local totFrame = frame.totFrame
	if totFrame then totFrame:UnregisterAllEvents() end

	local ccRemoverFrame = frame.CcRemoverFrame
	if ccRemoverFrame then ccRemoverFrame:UnregisterAllEvents() end

	local debuffFrame = frame.DebuffFrame
	if debuffFrame then debuffFrame:UnregisterAllEvents() end
end

local function handleFrame(baseName, doNotReparent, keepEventsAlive)
	local frame
	if type(baseName) == 'string' then
		frame = _G[baseName]
	else
		frame = baseName
	end

	hideFrame(frame, doNotReparent, keepEventsAlive)
end

function oUF:DisableBlizzard(unit)
	if not unit then return end

	-- UUF decide por unidad si Blizzard debe ocultarse.
	if not shouldDisableBlizzard(unit) then return end

	if unit == 'player' then
		-- Si Pet Blizzard debe seguir visible, impedir que el FramePositionManager
		-- lo vuelva a colgar del contenedor gestionado de Player.
		local keepPlayerLogic = not shouldDisableBlizzard('pet')
		if keepPlayerLogic and _G.PetFrame then
			detachFromManagedFrameContainer(_G.PetFrame)
		end

		handleFrame(PlayerFrame, false, keepPlayerLogic)

		if keepPlayerLogic then
			C_Timer.After(0, refreshIndependentBlizzardFrames)
		end

	elseif unit == 'pet' then
		handleFrame(PetFrame)

	elseif unit == 'target' then
		local keepTargetLogic = not shouldDisableBlizzard('targettarget')
		handleFrame(TargetFrame, false, keepTargetLogic)

	elseif unit == 'targettarget' then
		handleFrame(_G.TargetFrameToT or (TargetFrame and TargetFrame.totFrame), true)

	elseif unit == 'focus' then
		local keepFocusLogic = not shouldDisableBlizzard('focustarget')
		handleFrame(FocusFrame, false, keepFocusLogic)

	elseif unit == 'focustarget' then
		handleFrame(_G.FocusFrameToT or (FocusFrame and FocusFrame.totFrame), true)

	elseif unit:match('boss%d?$') then
		if not isBossHooked then
			isBossHooked = true

			handleFrame(BossTargetFrameContainer)

			for i = 1, MAX_BOSS_FRAMES do
				handleFrame('Boss' .. i .. 'TargetFrame', true)
			end
		end

	elseif unit:match('party%d?$') then
		if not isPartyHooked then
			isPartyHooked = true

			handleFrame(PartyFrame)

			for frame in PartyFrame.PartyMemberFramePool:EnumerateActive() do
				hideFrame(frame, true, false)
			end

			for i = 1, MEMBERS_PER_RAID_GROUP do
				handleFrame('CompactPartyFrameMember' .. i)
			end
		end

	elseif unit:match('arena%d?$') then
		if not isArenaHooked then
			isArenaHooked = true

			handleFrame(CompactArenaFrame)

			for _, frame in next, CompactArenaFrame.memberUnitFrames do
				hideFrame(frame, true, false)
			end

			handleFrame(ArenaEnemyMatchFramesContainer)

			for _, frame in next, ArenaEnemyMatchFramesContainer.UnitFrames do
				hideFrame(frame, true, false)
			end
		end

	elseif unit:match('nameplate%d?%d?%d?$') then
		local frame = C_NamePlate.GetNamePlateForUnit(unit)
		if frame then
			hideFrame(frame.UnitFrame, true, false)
		end
	end
end

