local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")

local ZlexConfig = {}

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
    {
        creatorId = 6042520,
        name = "99 Nights in the Forest",
        emoji = "🌲",
        scriptUrl = "https://raw.githubusercontent.com/zzxzsss/zxs/refs/heads/main/main/sum.lua"
    },
    {
        creatorId = 33548380,
        name = "Forsaken",
        emoji = "👻",
        scriptUrl = "https://raw.githubusercontent.com/zzxzsss/-mms/refs/heads/main/forskan.lua"
    }
}

ZlexConfig.GAMES = GAMES

local function isInPlaceList(placeId, placeList)
    if not placeList then return false end
    for _, id in pairs(placeList) do
        if id == placeId then
            return true
        end
    end
    return false
end

local function findCurrentGame()
    local currentPlaceId = game.PlaceId
    local currentCreatorId = nil

    pcall(function()
        local gameInfo = MarketplaceService:GetProductInfo(game.PlaceId)
        if gameInfo.Creator then
            if gameInfo.Creator.CreatorType == "Group" then
                currentCreatorId = gameInfo.Creator.CreatorTargetId
            else
                currentCreatorId = gameInfo.Creator.Id
            end
        end
    end)

    for _, gameConfig in pairs(GAMES) do
        if gameConfig.placeIds then
            if isInPlaceList(currentPlaceId, gameConfig.placeIds) then
                return gameConfig
            end
        end

        if gameConfig.creatorId and currentCreatorId then
            if gameConfig.creatorId == currentCreatorId then
                return gameConfig
            end
        end
    end

    return nil
end

ZlexConfig.isInPlaceList = isInPlaceList
ZlexConfig.findCurrentGame = findCurrentGame

function ZlexConfig:GetCurrentGameScript()
    local gameConfig = findCurrentGame()
    if gameConfig then
        return gameConfig.scriptUrl, gameConfig.name
    end
    return nil, nil
end

function ZlexConfig:GetCurrentGame()
    return findCurrentGame()
end

function ZlexConfig:IsGameSupported()
    return findCurrentGame() ~= nil
end

ZlexConfig.discord_key = true

ZlexConfig.DISCORD_PRESET_KEY = "niggerboy"

ZlexConfig.SERVICE_IDENTIFIER = "zzzhub2"

ZlexConfig.DISCORD_INVITE = "https://discord.gg/Zxe99EjbC7"

ZlexConfig.ACCENT_COLOR = Color3.fromRGB(139, 48, 48)
ZlexConfig.DARK_BG = Color3.fromRGB(10, 10, 10)
ZlexConfig.SECONDARY_BG = Color3.fromRGB(20, 20, 20)

function ZlexConfig:GetIdentifier()
    return self.SERVICE_IDENTIFIER
end

function ZlexConfig:IsDiscordMode()
    return self.discord_key
end

function ZlexConfig:GetDiscordKey()
    return self.DISCORD_PRESET_KEY
end

function ZlexConfig:SetAuthMode(useDiscord)
    self.discord_key = useDiscord
    print("[Zlex Hub] Mode changed to: " .. (useDiscord and "Discord Preset Key" or "Individual Keys"))
end

function ZlexConfig:SetDiscordKey(key)
    self.DISCORD_PRESET_KEY = key
    print("[Zlex Hub] Discord preset key updated")
end

function ZlexConfig:SetIdentifier(id)
    self.SERVICE_IDENTIFIER = id
    print("[Zlex Hub] Service identifier updated")
end

function ZlexConfig:GetAuthMode()
    return self.discord_key and "discord" or "individual"
end

function ZlexConfig:SetDiscordInvite(invite)
    self.DISCORD_INVITE = invite
end

function ZlexConfig:SetAccentColor(color)
    self.ACCENT_COLOR = color
end

return ZlexConfig
