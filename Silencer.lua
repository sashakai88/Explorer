--[[
    IronMan - Silencer Module
    Automates mundane interactions to remove the "click tax"
]]

local addonName, IronMan = ...

-- Ensure namespace exists
IronMan = IronMan or {}
IronMan.Silencer = IronMan.Silencer or {}

-- Local references
local Silencer = IronMan.Silencer

-- Constants
local GOSSIP_ICON_VENDOR = 132060
local GOSSIP_ICON_TAXI = 132057
local GOSSIP_ICON_INNKEEPER = 132055

--[[
    Checks if gossip has quests available
    @return boolean - True if quests are available
]]
local function HasQuests()
    local activeQuests = C_GossipInfo.GetActiveQuests() or {}
    local availableQuests = C_GossipInfo.GetAvailableQuests() or {}
    return (#activeQuests > 0) or (#availableQuests > 0)
end

--[[
    Checks if gossip option is an innkeeper binding
    @param option - Gossip option table
    @return boolean - True if it's an innkeeper binding option
]]
local function IsInnkeeperBinding(option)
    if not option then
        return false
    end

    -- Check icon ID
    if option.icon == GOSSIP_ICON_INNKEEPER then
        return true
    end

    -- Check name patterns
    if option.name then
        local name = option.name:lower()
        if name:match("make this inn your home") or name:match("bind your hearthstone") then
            return true
        end
    end

    return false
end

--[[
    Handles GOSSIP_SHOW event to auto-select vendor/taxi options
]]
local function OnGossipShow()
    -- Safety check: Don't auto-select if there are quests
    if HasQuests() then
        return
    end

    local options = C_GossipInfo.GetOptions()
    if not options then
        return
    end

    -- Safety check: Don't auto-select if this is an innkeeper
    for _, option in ipairs(options) do
        if IsInnkeeperBinding(option) then
            return
        end
    end

    -- Auto-select vendor or taxi options
    for _, option in ipairs(options) do
        if option.icon == GOSSIP_ICON_VENDOR or option.icon == GOSSIP_ICON_TAXI then
            local success, err = pcall(C_GossipInfo.SelectOption, option.gossipOptionID)
            if not success then
                -- Silently fail - some gossip options may not be selectable
            end
            -- Only select the first matching option
            break
        end
    end
end

--[[
    Handles QUEST_DETAIL event to auto-accept quests
]]
local function OnQuestDetail()
    local success, err = pcall(AcceptQuest)
    if not success then
        -- Silently fail - quest may not be acceptible
    end
end

--[[
    Initialize the Silencer module
]]
function Silencer.Initialize()
    -- Gossip automation frame
    local gossipFrame = CreateFrame("Frame", "IronManSilencerGossipFrame")
    gossipFrame:RegisterEvent("GOSSIP_SHOW")
    gossipFrame:SetScript("OnEvent", OnGossipShow)

    -- Quest auto-accept frame
    local questFrame = CreateFrame("Frame", "IronManSilencerQuestFrame")
    questFrame:RegisterEvent("QUEST_DETAIL")
    questFrame:SetScript("OnEvent", OnQuestDetail)
end

-- Auto-initialize on load
Silencer.Initialize()
