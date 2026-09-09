local _, UUF = ...

local recoveryGeneration = 0
local RECOVERY_DELAYS = {0, 0.25, 1.0, 2.0, 4.0}
local PARTY_AURA_NO_UNIT = "none"

local function RefreshFrame(frame, unit)
	if not frame or not UUF.db or not UUF.RefreshMidnightManagedAuras then return end
	UUF:RefreshMidnightManagedAuras(frame, unit, true)
end

local function RefreshPrimaryManagedAuras()
	RefreshFrame(UUF.PLAYER, "player")
	RefreshFrame(UUF.TARGET, "target")
	RefreshFrame(UUF.TARGETTARGET, "targettarget")
	RefreshFrame(UUF.PET, "pet")
	RefreshFrame(UUF.FOCUS, "focus")
	RefreshFrame(UUF.FOCUSTARGET, "focustarget")

	for index, frame in ipairs(UUF.BOSS_FRAMES or {}) do
		if frame then RefreshFrame(frame, "boss" .. index) end
	end
end

local function ParkManagedContainer(container)
	if not container then return end
	if container.SetEnabled then pcall(container.SetEnabled, container, false) end
	if container.SetUnit then pcall(container.SetUnit, container, PARTY_AURA_NO_UNIT) end
	if container.UpdateAllAuras then pcall(container.UpdateAllAuras, container) end
	pcall(container.Hide, container)
end

local function ParkPartyManagedAuras()
	local seen = {}

	local function ParkFrame(frame)
		if not frame or seen[frame] or frame.isTestFrame then return end
		seen[frame] = true

		ParkManagedContainer(frame.UUFManagedTargetBuffs)
		ParkManagedContainer(frame.UUFManagedTargetDebuffs)
		ParkManagedContainer(frame.UUFManagedPartyRaidCustomAuras)
		if frame.UUFManagedTargetDebuffsClip then
			pcall(frame.UUFManagedTargetDebuffsClip.Hide, frame.UUFManagedTargetDebuffsClip)
		end

		-- Auras.lua already owns the group restore lifecycle. Marking this false
		-- makes its next PLAYER_ENTERING_WORLD/visibility sweep take the existing
		-- "became observable" path, which rebuilds the configured filters before
		-- binding the AuraContainers back to partyX.
		frame.UUFManagedAuraObservable = false
	end

	ParkFrame(UUF.PARTYPLAYER)
	for _, frame in ipairs(UUF.PARTY_FRAMES or {}) do ParkFrame(frame) end
end

local function QueueAuraLoadRecovery()
	recoveryGeneration = recoveryGeneration + 1
	local generation = recoveryGeneration

	for _, delay in ipairs(RECOVERY_DELAYS) do
		C_Timer.After(delay, function()
			if generation ~= recoveryGeneration then return end
			RefreshPrimaryManagedAuras()
		end)
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LEAVING_WORLD")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LEAVING_WORLD" then
		-- Cut the live partyX aura stream before the loading screen. A container
		-- bound to a real unit can otherwise receive transient aura state while the
		-- world/instance is changing and briefly expose it when UI rendering resumes.
		ParkPartyManagedAuras()
		return
	end

	-- Re-assert the null binding synchronously after the loading screen, before
	-- Auras.lua's own deferred PLAYER_ENTERING_WORLD refresh runs. That existing
	-- refresh is then the single owner that restores Party Buff/Debuff/Custom
	-- containers with their configured filters.
	ParkPartyManagedAuras()
	QueueAuraLoadRecovery()
end)
