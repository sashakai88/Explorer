--[[
    IronMan - Core Module
    Handles UI suppression and immersion features
]]

local addonName, IronMan = ...

-- Ensure namespace exists
IronMan = IronMan or {}
IronMan.Core = IronMan.Core or {}

-- Local references
local Core = IronMan.Core

-- Binding declarations
BINDING_HEADER_IRONMAN = "IronMan Mode"
BINDING_NAME_IRONMAN_TOGGLE_JOURNAL = "Toggle Journal"
BINDING_NAME_IRONMAN_TOGGLE_MAP = "Toggle Paper Map"

-- Configuration: CVars to disable
local CVARS_TO_DISABLE = {
    -- Quest POI System
    ShowQuestUnitCircles = "0",
    questPOI = "0",
    -- Soft Target Interact (Dragonflight feature)
    softTargetInteract = "0",
    -- Nameplates
    nameplateShowEnemies = "0",
    nameplateShowFriends = "0",
    -- Minimap tracking
    minimapShowQuestBlobs = "0",
    minimapTrackedInfov2 = "0",
}

--[[
    Applies CVar settings to disable hand-holding UI elements
]]
local function ApplyCVarSettings()
    for cvar, value in pairs(CVARS_TO_DISABLE) do
        local success, err = pcall(C_CVar.SetCVar, cvar, value)
        if not success then
            -- Silently fail for CVars that don't exist in this client version
        end
    end
end

--[[
    Hides and suppresses the Objective Tracker frame
]]
local function SuppressObjectiveTracker()
    if not ObjectiveTrackerFrame then
        return
    end

    -- Hide immediately
    ObjectiveTrackerFrame:Hide()

    -- Hook Show to prevent it from appearing
    if not Core.objectiveTrackerHooked then
        hooksecurefunc(ObjectiveTrackerFrame, "Show", function(self)
            self:Hide()
        end)
        Core.objectiveTrackerHooked = true
    end

    -- Collapse as fallback
    if ObjectiveTrackerFrame.SetCollapsed then
        ObjectiveTrackerFrame:SetCollapsed(true)
    end
end

--[[
    Main function to disable all hand-holding UI elements
]]
function Core.DisableHandHolding()
    print("|cffcc3333IronMan|r: Engaging Blindfolds. Good luck.")

    -- Apply CVar settings
    ApplyCVarSettings()

    -- Suppress Objective Tracker
    SuppressObjectiveTracker()
end

--[[
    Event handler for PLAYER_LOGIN
    CVars need to be set after character settings load
]]
local function OnPlayerLogin()
    Core.DisableHandHolding()
end

--[[
    Initialize the Core module
]]
function Core.Initialize()
    -- Create event frame
    local eventFrame = CreateFrame("Frame", "IronManCoreFrame")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:SetScript("OnEvent", OnPlayerLogin)

    -- Register slash command
    SLASH_IRONMAN1 = "/ironman"
    SlashCmdList["IRONMAN"] = function(msg)
        Core.DisableHandHolding()
    end
end

-- Auto-initialize on load
Core.Initialize()
