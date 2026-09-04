local _, UUF = ...

local recoveryGeneration = 0
local RECOVERY_DELAYS = {0, 0.25, 1.0, 2.0, 4.0}

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
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", QueueAuraLoadRecovery)
