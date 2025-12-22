
local HttpService = game:GetService("HttpService")

local PandaAuthConfig = {}

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

-- Expose httpRequest function
PandaAuthConfig.httpRequest = httpRequest

PandaAuthConfig.discord_key = false  -- Set to true to use Discord preset key

-- Discord preset key (the key you share in your Discord server channel)
PandaAuthConfig.DISCORD_PRESET_KEY = "niggerboy"  -- Example: "PANDA-XXXX-XXXX-XXXX"

-- Service identifier from Panda Development (required for both modes)
PandaAuthConfig.SERVICE_IDENTIFIER = "zzzhub2"

-- Discord invite link
PandaAuthConfig.DISCORD_INVITE = "https://discord.gg/fF7UjXHW9a"

-- Script to load after successful authentication
PandaAuthConfig.MAIN_SCRIPT_URL = "https://raw.githubusercontent.com/kizzythegng/GROW-A-GARDEN-PET-DUPE/refs/heads/main/nggg"

-- UI Theme Colors
PandaAuthConfig.ACCENT_COLOR = Color3.fromRGB(139, 48, 48)
PandaAuthConfig.DARK_BG = Color3.fromRGB(10, 10, 10)
PandaAuthConfig.SECONDARY_BG = Color3.fromRGB(20, 20, 20)

--[[
    ==========================================
    MODULE FUNCTIONS
    ==========================================
]]

-- Get the service identifier
function PandaAuthConfig:GetIdentifier()
    return self.SERVICE_IDENTIFIER
end

-- Check if using Discord preset key mode
function PandaAuthConfig:IsDiscordMode()
    return self.discord_key
end

-- Get the Discord preset key
function PandaAuthConfig:GetDiscordKey()
    return self.DISCORD_PRESET_KEY
end

-- Set auth mode dynamically
function PandaAuthConfig:SetAuthMode(useDiscord)
    self.discord_key = useDiscord
    print("[Panda Auth] Mode changed to: " .. (useDiscord and "Discord Preset Key" or "Individual Keys"))
end

-- Set Discord preset key
function PandaAuthConfig:SetDiscordKey(key)
    self.DISCORD_PRESET_KEY = key
    print("[Panda Auth] Discord preset key updated")
end

-- Set service identifier
function PandaAuthConfig:SetIdentifier(id)
    self.SERVICE_IDENTIFIER = id
    print("[Panda Auth] Service identifier updated")
end

-- Get current auth mode as string
function PandaAuthConfig:GetAuthMode()
    return self.discord_key and "discord" or "individual"
end

-- Set main script URL
function PandaAuthConfig:SetMainScript(url)
    self.MAIN_SCRIPT_URL = url
end

-- Set Discord invite
function PandaAuthConfig:SetDiscordInvite(invite)
    self.DISCORD_INVITE = invite
end

-- Set accent color
function PandaAuthConfig:SetAccentColor(color)
    self.ACCENT_COLOR = color
end

return PandaAuthConfig
