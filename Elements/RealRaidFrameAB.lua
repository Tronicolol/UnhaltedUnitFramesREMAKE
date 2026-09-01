local _, UUF = ...

local framesHidden = false

local function Print(message)
    if UUF and UUF.PrettyPrint then
        UUF:PrettyPrint("|cFFFFB86CRealRaidFrameAB|r " .. tostring(message))
    else
        print("UUF RealRaidFrameAB: " .. tostring(message))
    end
end

local function FramesOff()
    if InCombatLockdown() then
        Print("solo puede ocultarse fuera de combate.")
        return
    end

    local container = UUF.RAID_CONTAINER
    if not container then
        Print("RAID_CONTAINER no existe.")
        return
    end

    UnregisterStateDriver(container, "visibility")
    container:Hide()
    framesHidden = true

    Print("RAID FRAMES OFF. Espera 5 s y ejecuta /uufrealidle profile 10.")
end

local function FramesOn()
    if InCombatLockdown() then
        Print("solo puede restaurarse fuera de combate.")
        return
    end

    local container = UUF.RAID_CONTAINER
    if not container then
        Print("RAID_CONTAINER no existe.")
        return
    end

    local RaidDB = UUF.db and UUF.db.profile and UUF.db.profile.Units and UUF.db.profile.Units.raid
    if RaidDB and RaidDB.Enabled then
        RegisterStateDriver(container, "visibility", "show")
        container:Show()
    end

    framesHidden = false
    Print("RAID FRAMES ON. Espera 5 s y ejecuta /uufrealidle profile 10.")
end

local function Status()
    local container = UUF.RAID_CONTAINER
    Print(string.format(
        "hidden=%s | containerExists=%s | shown=%s.",
        tostring(framesHidden),
        tostring(container ~= nil),
        tostring(container and container:IsShown() or false)
    ))
end

SLASH_UUFRAIDFRAMEAB1 = "/uufraidframes"
SlashCmdList["UUFRAIDFRAMEAB"] = function(message)
    local command = tostring(message or ""):lower():match("^%s*(%S*)")

    if command == "off" then
        FramesOff()
    elseif command == "on" then
        FramesOn()
    elseif command == "status" then
        Status()
    else
        Print("uso: /uufraidframes off | on | status")
    end
end
