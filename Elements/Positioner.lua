local _, UUF = ...

local CDM_ANCHOR_WIDTH = 300
local CDM_ANCHOR_HEIGHT = 48

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

        CDMAnchor:ClearAllPoints()
        CDMAnchor:SetPoint("CENTER", ECDM, "CENTER", 0, 0)
        CDMAnchor:SetSize(CDM_ANCHOR_WIDTH, CDM_ANCHOR_HEIGHT)
    else
        UUF:PrettyPrint("|cFF8080FFAnchor Point|r was not found.")
    end
end
