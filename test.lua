
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")

local ZlexConfig = {}

-- HTTP Request Handler (supports multiple executors)
local function httpRequest(options)
    local request = syn and syn.request or http and http.request or http_request or (request ~= nil and request) or httprequest or (fluxus and fluxus.request)
    
    if request then
        return request(options)
    end
    
    local success, response = pcall(function()
        return HttpService:RequestAsync(options)
    end)
    
    if success then
        return response
    end
    
    return nil
end

ZlexConfig.httpRequest = httpRequest

local GAMES = {
    ["99NightsInTheForest"] = {
        name = "99 Nights in the Forest",
        groupId = 6042520,
        creatorId = 2600997,
        placeIds = {},  -- Add specific place IDs if needed
        scriptUrl = "https://raw.githubusercontent.com/zzxzsss/zxs/refs/heads/main/main/sum.lua"
    },
    ["Forsaken"] = {
        name = "Forsaken",
        groupId = 33548380,
        creatorId = 8717405446,
        placeIds = {},  -- Add specific place IDs if needed
        scriptUrl = "https://raw.githubusercontent.com/zzxzsss/-mms/refs/heads/main/forskan.lua"
    }
}

ZlexConfig.GAMES = GAMES


-- Function to check if current place is in a game's place list
local function isInPlaceList(placeId, placeList)
    for _, id in pairs(placeList) do
        if id == placeId then
            return true
        end
    end
    return false
end

-- Function to find current game configuration
local function findCurrentGame()
    local currentPlaceId = game.PlaceId
    local currentCreatorId = nil

    -- Try to get creator ID from game info (works for both users and groups)
    pcall(function()
        local gameInfo = MarketplaceService:GetProductInfo(game.PlaceId)
        if gameInfo.Creator then
            -- Handle both user creators and group creators
            if gameInfo.Creator.CreatorType == "Group" then
                currentCreatorId = gameInfo.Creator.CreatorTargetId
            else
                currentCreatorId = gameInfo.Creator.Id
            end
        end
    end)

    for _, gameConfig in pairs(GAMES) do
        -- Check by Place ID first
        if gameConfig.placeIds then
            for _, placeId in pairs(gameConfig.placeIds) do
                if placeId == currentPlaceId then
                    return gameConfig
                end
            end
        end

        -- Check by Creator ID if place ID not found or not provided
        if gameConfig.creatorId and currentCreatorId and gameConfig.creatorId == currentCreatorId then
            return gameConfig
        end
        
        -- Check by Group ID
        if gameConfig.groupId and currentCreatorId and gameConfig.groupId == currentCreatorId then
            return gameConfig
        end
    end

    return nil
end

-- Expose game detection functions
ZlexConfig.isInPlaceList = isInPlaceList
ZlexConfig.findCurrentGame = findCurrentGame

-- Get script URL for current game
function ZlexConfig:GetCurrentGameScript()
    local gameConfig = findCurrentGame()
    if gameConfig then
        return gameConfig.scriptUrl, gameConfig.name
    end
    return nil, nil
end

-- Get current game config
function ZlexConfig:GetCurrentGame()
    return findCurrentGame()
end

--[[
    ==========================================
    CONFIGURATION SETTINGS
    ==========================================
    
    discord_key: 
        false = Uses Panda Development key system (users get individual keys from getkey link)
        true  = Uses your preset Discord key (all Discord members use the same key)
    
    DISCORD_PRESET_KEY:
        The key you give to Discord members (only used when discord_key = true)
        Set this to the key you share in your Discord channel
    
    SERVICE_IDENTIFIER:
        Your service identifier from Panda Development (used for API validation)
]]

ZlexConfig.discord_key = false  -- Set to true to use Discord preset key

-- Discord preset key (the key you share in your Discord server channel)
ZlexConfig.DISCORD_PRESET_KEY = "niggerboy"  -- Example: "PANDA-XXXX-XXXX-XXXX"

-- Service identifier from Panda Development (required for both modes)
ZlexConfig.SERVICE_IDENTIFIER = "zzzhub2"

-- Discord invite link
ZlexConfig.DISCORD_INVITE = "https://discord.gg/Zxe99EjbC7"

-- Default script URL (used if game not detected)
ZlexConfig.MAIN_SCRIPT_URL = "https://raw.githubusercontent.com/zzxzsss/zxs/refs/heads/main/main/sum.lua"

-- UI Theme Colors
ZlexConfig.ACCENT_COLOR = Color3.fromRGB(139, 48, 48)
ZlexConfig.DARK_BG = Color3.fromRGB(10, 10, 10)
ZlexConfig.SECONDARY_BG = Color3.fromRGB(20, 20, 20)

--[[
    ==========================================
    MODULE FUNCTIONS
    ==========================================
]]

-- Get the service identifier
function ZlexConfig:GetIdentifier()
    return self.SERVICE_IDENTIFIER
end

-- Check if using Discord preset key mode
function ZlexConfig:IsDiscordMode()
    return self.discord_key
end

-- Get the Discord preset key
function ZlexConfig:GetDiscordKey()
    return self.DISCORD_PRESET_KEY
end

-- Set auth mode dynamically
function ZlexConfig:SetAuthMode(useDiscord)
    self.discord_key = useDiscord
    print("[Zlex Hub] Mode changed to: " .. (useDiscord and "Discord Preset Key" or "Individual Keys"))
end

-- Set Discord preset key
function ZlexConfig:SetDiscordKey(key)
    self.DISCORD_PRESET_KEY = key
    print("[Zlex Hub] Discord preset key updated")
end

-- Set service identifier
function ZlexConfig:SetIdentifier(id)
    self.SERVICE_IDENTIFIER = id
    print("[Zlex Hub] Service identifier updated")
end

-- Get current auth mode as string
function ZlexConfig:GetAuthMode()
    return self.discord_key and "discord" or "individual"
end

-- Set main script URL
function ZlexConfig:SetMainScript(url)
    self.MAIN_SCRIPT_URL = url
end

-- Set Discord invite
function ZlexConfig:SetDiscordInvite(invite)
    self.DISCORD_INVITE = invite
end

-- Set accent color
function ZlexConfig:SetAccentColor(color)
    self.ACCENT_COLOR = color
end

-- Get the script URL (auto-detects game or uses default)
function ZlexConfig:GetScriptUrl()
    local gameScript, gameName = self:GetCurrentGameScript()
    if gameScript then
        print("[Zlex Hub] Detected game: " .. gameName)
        return gameScript
    end
    return self.MAIN_SCRIPT_URL
end

return ZlexConfig
