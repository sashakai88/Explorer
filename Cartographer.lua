--[[
    IronMan - Cartographer Module
    Handles map modifications, compass HUD, and map reveal integration
]]

local addonName, IronMan = ...

-- Ensure namespace exists
IronMan = IronMan or {}
IronMan.Cartographer = IronMan.Cartographer or {}

-- Local references
local Cartographer = IronMan.Cartographer

-- Compass direction lookup table (optimized)
local COMPASS_DIRECTIONS = {
    [0] = "N",   -- 0-22.5
    [1] = "NW",  -- 22.5-67.5
    [2] = "W",   -- 67.5-112.5
    [3] = "SW",  -- 112.5-157.5
    [4] = "S",   -- 157.5-202.5
    [5] = "SE",  -- 202.5-247.5
    [6] = "E",   -- 247.5-292.5
    [7] = "NE",  -- 292.5-337.5
}

--[[
    Gets compass direction from facing angle
    @param facing - Player facing in radians
    @return string - Compass direction
]]
local function GetCompassDirection(facing)
    if not facing then
        return "N"
    end

    local deg = math.deg(facing)
    -- Normalize to 0-360
    if deg < 0 then
        deg = deg + 360
    end

    -- Determine direction index
    local index = math.floor((deg + 22.5) / 45) % 8
    return COMPASS_DIRECTIONS[index] or "N"
end

--[[
    Map exploration pin refresh overlay hook
    Integrates Leatrix Maps reveal mechanism
]]
local function MapExplorationPin_RefreshOverlays(pin, fullUpdate)
    local mapID = WorldMapFrame.mapID
    if not mapID then
        return
    end

    local artID = C_Map.GetMapArtID(mapID)
    if not artID or not IronMan.RevealData or not IronMan.RevealData[artID] then
        return
    end

    local revealZone = IronMan.RevealData[artID]
    local exploredMapTextures = C_MapExplorationInfo.GetExploredMapTextures(mapID)
    local tileExists = {}

    -- Build lookup table for existing tiles
    if exploredMapTextures then
        for _, info in ipairs(exploredMapTextures) do
            local key = string.format("%d:%d:%d:%d", info.textureWidth, info.textureHeight, info.offsetX, info.offsetY)
            tileExists[key] = true
        end
    end

    -- Get layer information
    pin.layerIndex = pin:GetMap():GetCanvasContainer():GetCurrentLayerIndex()
    local layers = C_Map.GetMapArtLayers(mapID)
    local layerInfo = layers and layers[pin.layerIndex]

    if not layerInfo then
        return
    end

    local TILE_SIZE_WIDTH = layerInfo.tileWidth
    local TILE_SIZE_HEIGHT = layerInfo.tileHeight

    -- Process reveal data
    for key, files in pairs(revealZone) do
        if not tileExists[key] then
            local width, height, offsetX, offsetY = strsplit(":", key)
            width = tonumber(width)
            height = tonumber(height)
            offsetX = tonumber(offsetX)
            offsetY = tonumber(offsetY)

            if not width or not height or not offsetX or not offsetY then
                -- Skip invalid entries
                break
            end

            local fileDataIDs = { strsplit(",", files) }
            local numTexturesWide = math.ceil(width / TILE_SIZE_WIDTH)
            local numTexturesTall = math.ceil(height / TILE_SIZE_HEIGHT)

            -- Create textures for this reveal zone
            for j = 1, numTexturesTall do
                local texturePixelHeight, textureFileHeight
                if j < numTexturesTall then
                    texturePixelHeight = TILE_SIZE_HEIGHT
                    textureFileHeight = TILE_SIZE_HEIGHT
                else
                    texturePixelHeight = height % TILE_SIZE_HEIGHT
                    if texturePixelHeight == 0 then
                        texturePixelHeight = TILE_SIZE_HEIGHT
                    end
                    textureFileHeight = 16
                    while textureFileHeight < texturePixelHeight do
                        textureFileHeight = textureFileHeight * 2
                    end
                end

                for k = 1, numTexturesWide do
                    local texturePixelWidth, textureFileWidth
                    if k < numTexturesWide then
                        texturePixelWidth = TILE_SIZE_WIDTH
                        textureFileWidth = TILE_SIZE_WIDTH
                    else
                        texturePixelWidth = width % TILE_SIZE_WIDTH
                        if texturePixelWidth == 0 then
                            texturePixelWidth = TILE_SIZE_WIDTH
                        end
                        textureFileWidth = 16
                        while textureFileWidth < texturePixelWidth do
                            textureFileWidth = textureFileWidth * 2
                        end
                    end

                    local texture = pin.overlayTexturePool:Acquire()
                    texture:SetSize(texturePixelWidth, texturePixelHeight)
                    texture:SetTexCoord(0, texturePixelWidth / textureFileWidth, 0, texturePixelHeight / textureFileHeight)
                    texture:SetPoint("TOPLEFT", offsetX + (TILE_SIZE_WIDTH * (k - 1)), -(offsetY + (TILE_SIZE_HEIGHT * (j - 1))))

                    local textureIndex = ((j - 1) * numTexturesWide) + k
                    local fileDataID = tonumber(fileDataIDs[textureIndex])
                    if fileDataID then
                        texture:SetTexture(fileDataID)
                    end

                    texture:SetDrawLayer("ARTWORK", -1)
                    texture:Show()
                end
            end
        end
    end
end

--[[
    Creates the compass HUD frame
]]
local function CreateCompassFrame()
    local compass = CreateFrame("Frame", "IronManCompassFrame", UIParent)
    compass:SetSize(400, 30)
    compass:SetPoint("TOP", 0, -20)
    compass:Show()

    -- Background
    local bg = compass:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(compass)
    bg:SetColorTexture(0, 0, 0, 0.5)

    -- Direction text
    local text = compass:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER")
    text:SetTextColor(1, 0.8, 0, 1) -- Gold
    text:SetText("N")

    -- Optimized OnUpdate: throttle to update every 0.1 seconds
    local updateThrottle = 0
    compass:SetScript("OnUpdate", function(self, elapsed)
        updateThrottle = updateThrottle + elapsed
        if updateThrottle < 0.1 then
            return
        end
        updateThrottle = 0

        local facing = GetPlayerFacing()
        local direction = GetCompassDirection(facing)
        text:SetText(direction)
    end)

    Cartographer.compassFrame = compass
end

--[[
    Hides and suppresses the minimap cluster
]]
local function SuppressMinimap()
    if not MinimapCluster then
        return
    end

    MinimapCluster:Hide()

    if not Cartographer.minimapHooked then
        hooksecurefunc(MinimapCluster, "Show", function(self)
            self:Hide()
        end)
        Cartographer.minimapHooked = true
    end
end

--[[
    Hides GPS features on the world map
]]
local function SuppressWorldMapGPS()
    -- Hide player arrow on map change
    if not Cartographer.mapGPSHooked then
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
            if WorldMapFrame.UnitPositionFrame then
                WorldMapFrame.UnitPositionFrame:SetAlpha(0)
                WorldMapFrame.UnitPositionFrame:Hide()
            end
        end)
        Cartographer.mapGPSHooked = true
    end

    -- Hide immediately if it exists
    if WorldMapFrame.UnitPositionFrame then
        WorldMapFrame.UnitPositionFrame:SetAlpha(0)
        WorldMapFrame.UnitPositionFrame:Hide()
    end

    -- Ensure quest blobs are hidden (redundant with Core, but safe)
    pcall(C_CVar.SetCVar, "ShowQuestUnitCircles", "0")
    pcall(C_CVar.SetCVar, "questPOI", "0")
end

--[[
    Hooks map exploration pins for reveal integration
]]
local function HookMapExplorationPins()
    if Cartographer.pinsHooked then
        return
    end

    -- Hook existing pins
    for pin in WorldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
        hooksecurefunc(pin, "RefreshOverlays", MapExplorationPin_RefreshOverlays)
    end

    -- Also hook new pins as they're created
    WorldMapFrame:HookScript("OnShow", function()
        C_Timer.After(0.1, function()
            for pin in WorldMapFrame:EnumeratePinsByTemplate("MapExplorationPinTemplate") do
                if not pin._ironmanHooked then
                    hooksecurefunc(pin, "RefreshOverlays", MapExplorationPin_RefreshOverlays)
                    pin._ironmanHooked = true
                end
            end
        end)
    end)

    Cartographer.pinsHooked = true
end

--[[
    Event handler for PLAYER_LOGIN
]]
local function OnPlayerLogin()
    CreateCompassFrame()
    SuppressMinimap()
    SuppressWorldMapGPS()
    HookMapExplorationPins()

    print("IronMan: Cartographer Loaded (Modified Default Map).")
end

--[[
    Initialize the Cartographer module
]]
function Cartographer.Initialize()
    local eventFrame = CreateFrame("Frame", "IronManCartographerFrame")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:SetScript("OnEvent", OnPlayerLogin)
end

-- Auto-initialize on load
Cartographer.Initialize()
