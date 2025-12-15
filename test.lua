--- test not in works rn
local PandaAuthConfig = {}

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

PandaAuthConfig.discord_key = false  -- Set to true to use Discord preset key

-- Discord preset key (the key you share in your Discord server channel)
PandaAuthConfig.DISCORD_PRESET_KEY = "niggerboy"  -- Example: "PANDA-XXXX-XXXX-XXXX"

-- Service identifier from Panda Development (required for both modes)
PandaAuthConfig.SERVICE_IDENTIFIER = "zzzhub2"

-- Discord invite link
PandaAuthConfig.DISCORD_INVITE = "https://discord.gg/eAc9ku2N8g"

-- Script to load after successful authentication
PandaAuthConfig.MAIN_SCRIPT_URL = "https://raw.githubusercontent.com/zzxzsss/zxs/refs/heads/main/main/sum.lua"

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
