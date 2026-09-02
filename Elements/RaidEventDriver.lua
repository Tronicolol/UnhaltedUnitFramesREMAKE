local _, UUF = ...
local oUF = UUF.oUF

-- Raid hot-path event routing inspired by EllesmereUI's raid-frame architecture:
-- secure unit buttons display the unit, while ordinary tracker frames own the
-- high-frequency unit events. This keeps Health/absorb traffic off the protected
-- oUF children without changing their visuals, secure attributes or click-casting.

local trackers = {}
local frameToAssignedUnit = setmetatable({}, { __mode = "k" })

local BASE_EVENTS = {
    UNIT_HEALTH = true,
    UNIT_MAXHEALTH = true,
    UNIT_CONNECTION = true,
}

local function IsRaidUnit(unit)
    return type(unit) == "string" and unit:match("^raid%d+$") ~= nil
end

local function GetAssignedRaidUnit(frame)
    if not frame then return nil end

    local unit = frame.GetAttribute and frame:GetAttribute("unit") or nil
    if IsRaidUnit(unit) then return unit end

    return nil
end

local function GetActiveTrackedUnit(frame, assignedUnit)
    if not frame then return assignedUnit end

    local activeUnit = frame.unit
    if type(activeUnit) == "string" and activeUnit ~= "" then
        return activeUnit
    end

    return assignedUnit
end

local function WantsEvent(frame, event)
    local health = frame and frame.Health
    if not health then return false end

    if BASE_EVENTS[event] then return true end
    if event == "UNIT_ABSORB_AMOUNT_CHANGED" then
        return health.DamageAbsorb ~= nil or health.OverDamageAbsorbIndicator ~= nil
    end
    if event == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
        return health.HealAbsorb ~= nil or health.OverHealAbsorbIndicator ~= nil
    end
    if event == "UNIT_HEAL_PREDICTION" then
        return health.HealingAll ~= nil
            or health.HealingPlayer ~= nil
            or health.HealingOther ~= nil
            or health.OverHealIndicator ~= nil
    end
    if event == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
        return health.TempLoss ~= nil
    end

    return false
end

local TRACKABLE_EVENTS = {
    "UNIT_HEALTH",
    "UNIT_MAXHEALTH",
    "UNIT_CONNECTION",
    "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_PREDICTION",
    "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
}

local function DispatchTrackerEvent(tracker, event, unit, ...)
    local frame = tracker.ownerFrame
    local health = frame and frame.Health
    if not frame or not health then return end

    -- The secure unit can temporarily become raidpetN/vehicle-like through oUF's
    -- normal vehicle handling. The tracker is re-bound to frame.unit on those
    -- lifecycle edges; ignore any stale event that races that transition.
    if frame.unit ~= unit then return end

    if event == "UNIT_CONNECTION" then
        -- Connection changes can alter disconnected colouring as well as value.
        -- ForceUpdate still uses the existing oUF Path, but it is a rare edge,
        -- not the high-frequency health/prediction lane.
        if health.ForceUpdate then health:ForceUpdate() end
        return
    end

    -- Party/Raid Health already installs GroupLeanHealthOverride. Calling the
    -- Override directly deliberately bypasses generic oUF Path/ColorPath and its
    -- prediction-size probe on every event. Configuration changes size/re-anchor
    -- the persistent prediction widgets explicitly, so hot events only paint data.
    if health.Override then
        health.Override(frame, event, unit, ...)
    elseif health.ForceUpdate then
        health:ForceUpdate()
    end
end

local function CreateTracker(assignedUnit)
    local tracker = CreateFrame("Frame")
    tracker.assignedUnit = assignedUnit
    tracker.ownerFrame = nil
    tracker.activeUnit = nil
    tracker:SetScript("OnEvent", DispatchTrackerEvent)
    trackers[assignedUnit] = tracker
    return tracker
end

for index = 1, 40 do
    CreateTracker("raid" .. index)
end

local function SyncTracker(tracker, frame, assignedUnit)
    if not tracker then return end

    tracker:UnregisterAllEvents()
    tracker.ownerFrame = frame
    tracker.activeUnit = nil

    if not frame or not assignedUnit or not frame.Health then return end
    if frame.Health.UUFExternalEventDriver ~= true then return end

    local activeUnit = GetActiveTrackedUnit(frame, assignedUnit)
    if type(activeUnit) ~= "string" or activeUnit == "" then return end

    tracker.activeUnit = activeUnit

    for _, event in ipairs(TRACKABLE_EVENTS) do
        if WantsEvent(frame, event) then
            local ok = pcall(tracker.RegisterUnitEvent, tracker, event, activeUnit)
            if not ok then
                -- A missing/unsupported event should not prevent the rest of the
                -- health lane from being driven. The corresponding visual simply
                -- keeps its previous behavior until the next explicit ForceUpdate.
            end
        end
    end
end

local function UnassignFrame(frame)
    local previous = frame and frameToAssignedUnit[frame]
    if not previous then return end

    local tracker = trackers[previous]
    if tracker and tracker.ownerFrame == frame then
        SyncTracker(tracker, nil, previous)
    end

    frameToAssignedUnit[frame] = nil
end

function UUF:SyncRaidEventDriverFrame(frame)
    if not frame or not frame.Health then return end

    local assignedUnit = GetAssignedRaidUnit(frame)
    local previous = frameToAssignedUnit[frame]

    if previous and previous ~= assignedUnit then
        local previousTracker = trackers[previous]
        if previousTracker and previousTracker.ownerFrame == frame then
            SyncTracker(previousTracker, nil, previous)
        end
        frameToAssignedUnit[frame] = nil
    end

    if not assignedUnit then return end

    local tracker = trackers[assignedUnit]
    if not tracker then return end

    -- Secure-header reassignment should never leave two buttons driving one token.
    local displaced = tracker.ownerFrame
    if displaced and displaced ~= frame then
        frameToAssignedUnit[displaced] = nil
    end

    frameToAssignedUnit[frame] = assignedUnit
    SyncTracker(tracker, frame, assignedUnit)
end

function UUF:UnassignRaidEventDriverFrame(frame)
    UnassignFrame(frame)
end

-- Mark Raid Health for external driving before oUF enables its Health element.
-- CreateUnitHealPrediction runs inside the style function, while oUF enables
-- elements only after the style has completed.
local originalCreateUnitHealPrediction = UUF.CreateUnitHealPrediction
if type(originalCreateUnitHealPrediction) == "function" then
    UUF.CreateUnitHealPrediction = function(self, frame, unit, ...)
        local result = originalCreateUnitHealPrediction(self, frame, unit, ...)

        if frame and frame.Health and self:GetNormalizedUnit(unit) == "raid" then
            frame.Health.UUFExternalEventDriver = true
        end

        return result
    end
end

-- Prediction option changes can alter which tracker events are useful. The
-- existing updater owns widget creation/reconfiguration; resync registrations
-- only after it has finished.
local originalUpdateUnitHealPrediction = UUF.UpdateUnitHealPrediction
if type(originalUpdateUnitHealPrediction) == "function" then
    UUF.UpdateUnitHealPrediction = function(self, frame, unit, ...)
        local result = originalUpdateUnitHealPrediction(self, frame, unit, ...)

        if frame and frame.Health and self:GetNormalizedUnit(unit) == "raid" then
            frame.Health.UUFExternalEventDriver = true
            self:SyncRaidEventDriverFrame(frame)
        end

        return result
    end
end

-- oUF init callbacks run after all elements have been enabled, making this the
-- reliable initial hand-off point from the secure child to the plain tracker.
oUF:RegisterInitCallback(function(frame)
    if not frame or not frame.UUFConfiguredUnit then return end
    if UUF:GetNormalizedUnit(frame.UUFConfiguredUnit) ~= "raid" then return end

    frame:HookScript("OnAttributeChanged", function(changedFrame, attribute)
        if attribute ~= "unit" then return end

        -- oUF's own attribute hook updates frame.unit. Defer one frame so the
        -- external tracker always binds to that final active token.
        C_Timer.After(0, function()
            if not changedFrame then return end
            if GetAssignedRaidUnit(changedFrame) then
                UUF:SyncRaidEventDriverFrame(changedFrame)
            else
                UUF:UnassignRaidEventDriverFrame(changedFrame)
            end
        end)
    end)

    C_Timer.After(0, function()
        UUF:SyncRaidEventDriverFrame(frame)
    end)
end)

-- Preserve oUF's vehicle/pet lifecycle. Those low-frequency events remain on the
-- secure buttons; after they update frame.unit, simply re-bind our unit events to
-- the resulting active token (raidN, raidpetN, etc.).
local vehicleWatch = CreateFrame("Frame")
vehicleWatch:RegisterEvent("UNIT_ENTERED_VEHICLE")
vehicleWatch:RegisterEvent("UNIT_EXITED_VEHICLE")
vehicleWatch:RegisterEvent("UNIT_PET")
vehicleWatch:SetScript("OnEvent", function(_, _, unit)
    if not IsRaidUnit(unit) then return end

    C_Timer.After(0, function()
        local tracker = trackers[unit]
        local frame = tracker and tracker.ownerFrame
        if frame then UUF:SyncRaidEventDriverFrame(frame) end
    end)
end)

-- Small diagnostic for tomorrow's real-raid run. It is silent unless requested.
SLASH_UUFRAIDDRIVER1 = "/uufraiddriver"
SlashCmdList["UUFRAIDDRIVER"] = function()
    local assigned = 0
    local registrations = 0

    for _, tracker in pairs(trackers) do
        if tracker.ownerFrame then
            assigned = assigned + 1
            for _, event in ipairs(TRACKABLE_EVENTS) do
                if tracker:IsEventRegistered(event) then registrations = registrations + 1 end
            end
        end
    end

    if UUF.PrettyPrint then
        UUF:PrettyPrint(string.format(
            "RaidEventDriver: %d frames asignados | %d registros unit-event externos.",
            assigned,
            registrations
        ))
    end
end
