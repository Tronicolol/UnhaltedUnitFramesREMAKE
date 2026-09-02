local _, UUF = ...

local CDM_ANCHOR_WIDTH = 300
local CDM_ANCHOR_HEIGHT = 48

local function SnapAbsoluteUIValue(value)
    if not PixelUtil or not PixelUtil.GetNearestPixelSize then
        return value
    end

    return PixelUtil.GetNearestPixelSize(value, UIParent:GetEffectiveScale())
end

function UUF:CreatePositionController()
    local ECDM = ""

    if C_AddOns.IsAddOnLoaded("SkironCooldownManager") then
        ECDM = _G["SCM_GroupAnchor_1"]
    elseif C_AddOns.IsAddOnLoaded("Coolinator") then
        ECDM = _G["CoolinatorPrimaryGroupAnchor"]
    else
        ECDM = _G["EssentialCooldownViewer"]
    end

    if ECDM and ECDM:IsShown() then
        local CDMAnchor = _G["UUF_CDMAnchor"] or CreateFrame("Frame", "UUF_CDMAnchor", UIParent)
        local centerX = ECDM:GetCenter()

        if not centerX then
            UUF:PrettyPrint("|cFF8080FFAnchor Point|r was not ready yet.")
            return
        end

        local halfWidth = CDM_ANCHOR_WIDTH / 2
        local desiredLeft = centerX - halfWidth
        local desiredRight = centerX + halfWidth
        local snappedLeft = SnapAbsoluteUIValue(desiredLeft)
        local snappedRight = SnapAbsoluteUIValue(desiredRight)
        local leftOffset = snappedLeft - centerX
        local rightOffset = snappedRight - centerX

        CDMAnchor:ClearAllPoints()
        CDMAnchor:SetPoint("LEFT", ECDM, "CENTER", leftOffset, 0)
        CDMAnchor:SetPoint("RIGHT", ECDM, "CENTER", rightOffset, 0)

        if PixelUtil and PixelUtil.SetHeight then
            PixelUtil.SetHeight(CDMAnchor, CDM_ANCHOR_HEIGHT)
        else
            CDMAnchor:SetHeight(CDM_ANCHOR_HEIGHT)
        end
    else
        UUF:PrettyPrint("|cFF8080FFAnchor Point|r was not found.")
    end
end
