

local WindUI

do
    local ok, result = pcall(function()
        return require("./src/Init")
    end)

    if ok then
        WindUI = result
    else 
        local success, ui = pcall(function()
            return loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()
        end)
        if success and ui then
            WindUI = ui
        else
            warn("Zlex Hub: Failed to load WindUI")
            return
        end
    end
end

if not WindUI then
    warn("Zlex Hub: WindUI not available")
    return
end

pcall(function()
    WindUI:SetTheme("Dark")
end)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local lplr = Players.LocalPlayer
local playerData = pcall(function() return lplr:FindFirstChild("PlayerData") or lplr:WaitForChild("PlayerData", 5) end) and lplr:FindFirstChild("PlayerData")
local camera = workspace.CurrentCamera

local network, actor
pcall(function()
    -- Try new path: Systems.Player.Networks.ActorNetwork
    local systems = ReplicatedStorage:FindFirstChild("Systems")
    if systems then
        local player = systems:FindFirstChild("Player")
        if player then
            local networks = player:FindFirstChild("Networks")
            if networks then
                local actorNetwork = networks:FindFirstChild("ActorNetwork")
                if actorNetwork then
                    network = actorNetwork
                    -- ActorNetwork creates a RemoteEvent child, wait for it
                    actor = actorNetwork:FindFirstChild("RemoteEvent") or actorNetwork:WaitForChild("RemoteEvent", 5)
                end
            end
        end
    end
    -- Fallback to old path: Modules.Network
    if not actor then
        local modules = ReplicatedStorage:FindFirstChild("Modules")
        if modules then
            network = modules:FindFirstChild("Network")
            if network then
                actor = network:FindFirstChild("RemoteEvent")
            end
        end
    end
end)

-- Helper function to fire actor abilities via RemoteEvent
local function fireActorAbility(abilityName, ...)
    if not actor then return false end
    local args = {...}
    local success = pcall(function()
        actor:FireServer("UseActorAbility", abilityName, unpack(args))
    end)
    return success
end

local SpoofState = {
    Active = false,
    TargetCFrame = nil,
    OriginalCallback = nil,
    HookInstalled = false
}

local function formatCFrameForServer(cf)
    if not cf then return nil end
    local p, l = cf.Position, cf.LookVector
    return string.format("%0.3f/%0.3f/%0.3f/%0.3f/%0.3f/%0.3f", p.X, p.Y, p.Z, l.X, l.Y, l.Z)
end

local function setSpoofCFrame(cf)
    SpoofState.Active = cf ~= nil
    SpoofState.TargetCFrame = cf
end

local function installPositionHook()
    if SpoofState.HookInstalled then return end

    -- Method 1: Hook RemoteFunction directly without requiring module
    pcall(function()
        local networkFolder = nil
        -- Try new path first: Systems.Player.Networks
        local systems = ReplicatedStorage:FindFirstChild("Systems")
        if systems then
            local player = systems:FindFirstChild("Player")
            if player then
                local networks = player:FindFirstChild("Networks")
                if networks then
                    networkFolder = networks:FindFirstChild("ActorNetwork") or networks
                end
            end
        end
        -- Fallback to old path
        if not networkFolder then
            local modules = ReplicatedStorage:FindFirstChild("Modules")
            if modules then
                networkFolder = modules:FindFirstChild("Network")
            end
        end
        if not networkFolder then return end

        -- Find RemoteFunction for position data
        local rf = networkFolder:FindFirstChild("RemoteFunction")
        if rf and rf:IsA("RemoteFunction") and hookfunction then
            local oldInvoke = rf.InvokeServer
            local newInvoke = function(self, ...)
                local args = {...}
                if args[1] == "QueryClientData" or args[1] == "GetLocalPosData" then
                    if SpoofState.Active and SpoofState.TargetCFrame then
                        return formatCFrameForServer(SpoofState.TargetCFrame)
                    end
                end
                return oldInvoke(self, ...)
            end
            hookfunction(rf.InvokeServer, newInvoke)
            SpoofState.HookInstalled = true
        end
    end)

    -- Method 2: Hook via namecall if available
    if not SpoofState.HookInstalled and getrawmetatable and setreadonly then
        pcall(function()
            local mt = getrawmetatable(game)
            if mt and mt.__namecall then
                local oldNamecall = mt.__namecall
                setreadonly(mt, false)
                mt.__namecall = newcclosure(function(self, ...)
                    local method = getnamecallmethod()
                    if method == "InvokeServer" and self.Name == "RemoteFunction" then
                        local args = {...}
                        if (args[1] == "QueryClientData" or args[1] == "GetLocalPosData") and SpoofState.Active and SpoofState.TargetCFrame then
                            return formatCFrameForServer(SpoofState.TargetCFrame)
                        end
                    end
                    return oldNamecall(self, ...)
                end)
                setreadonly(mt, true)
                SpoofState.HookInstalled = true
            end
        end)
    end
end

task.spawn(function()
    task.wait(3)
    installPositionHook()
    task.wait(3)
    if not SpoofState.HookInstalled then
        installPositionHook()
    end
end)

local function serverSyncTeleport(targetCFrame)
    local char = lplr.Character
    if not char then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return false end

    setSpoofCFrame(targetCFrame)

    root.CFrame = targetCFrame
    root.Velocity = Vector3.zero
    root.AssemblyLinearVelocity = Vector3.zero

    return true
end

local function smoothTeleport(targetCFrame, speed)
    local char = lplr.Character
    if not char then return false end
    local root = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not root or not hum then return false end

    speed = speed or 200
    local startPos = root.Position
    local endPos = targetCFrame.Position
    local distance = (endPos - startPos).Magnitude
    local duration = distance / speed
    duration = math.clamp(duration, 0.01, 0.5)

    setSpoofCFrame(targetCFrame)

    local startTime = tick()
    while tick() - startTime < duration do
        local alpha = (tick() - startTime) / duration
        alpha = math.clamp(alpha, 0, 1)
        local newPos = startPos:Lerp(endPos, alpha)
        local currentCFrame = CFrame.new(newPos) * (targetCFrame - targetCFrame.Position)
        root.CFrame = currentCFrame
        setSpoofCFrame(currentCFrame)
        RunService.Heartbeat:Wait()
    end

    root.CFrame = targetCFrame
    root.Velocity = Vector3.zero
    root.AssemblyLinearVelocity = Vector3.zero
    setSpoofCFrame(targetCFrame)

    return true
end

local function clearSpoof()
    setSpoofCFrame(nil)
end

-- ============================================
-- END SERVER-SIDE TELEPORT SYSTEM
-- ============================================

local killerModel = nil
local isSurvivor = false
local isKiller = false
local playingState = "Playing"
local cachedParts = {}
local pathfindingIndex = 0

-- ============================================
-- REVAMPED AUTO FARM SYSTEM (Consolidated)
-- ============================================
local RevampedFarm = {
    Config = {
        GeneratorEnabled = false,
        GeneratorInterval = 1.0,
        GeneratorBypassCooldown = true,
        AutoSurviveEnabled = false,
        AutoWinEnabled = false,
        SafeDistance = 30,
        TeleportToGenerator = false,
        ReturnAfterComplete = true,
        AvoidKillers = true,
        KillerDetectRadius = 25
    },
    State = {
        isRunning = false,
        currentGenerator = nil,
        savedPosition = nil,
        farmThread = nil,
        killerCheckThread = nil
    }
}

function RevampedFarm:GetRoot()
    local char = lplr.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

function RevampedFarm:GetMapFolder()
    local map = workspace:FindFirstChild("Map")
    if not map then return nil end
    local ingame = map:FindFirstChild("Ingame")
    return ingame and ingame:FindFirstChild("Map")
end

function RevampedFarm:GetMapBounds()
    local mapFolder = self:GetMapFolder()
    if not mapFolder then return nil end
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    for _, part in ipairs(mapFolder:GetDescendants()) do
        if part:IsA("BasePart") then
            local pos = part.Position
            local size = part.Size / 2
            minX = math.min(minX, pos.X - size.X)
            minY = math.min(minY, pos.Y - size.Y)
            minZ = math.min(minZ, pos.Z - size.Z)
            maxX = math.max(maxX, pos.X + size.X)
            maxY = math.max(maxY, pos.Y + size.Y)
            maxZ = math.max(maxZ, pos.Z + size.Z)
        end
    end
    if minX == math.huge then return nil end
    return {min = Vector3.new(minX, minY, minZ), max = Vector3.new(maxX, maxY, maxZ)}
end

function RevampedFarm:IsInMapBounds(pos)
    local bounds = self:GetMapBounds()
    if not bounds then return true end
    local padding = 5
    return pos.X >= bounds.min.X - padding and pos.X <= bounds.max.X + padding
        and pos.Y >= bounds.min.Y - padding and pos.Y <= bounds.max.Y + padding
        and pos.Z >= bounds.min.Z - padding and pos.Z <= bounds.max.Z + padding
end

function RevampedFarm:HasFloorBelow(pos)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local char = lplr.Character
    rayParams.FilterDescendantsInstances = char and {char} or {}
    local result = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -50, 0), rayParams)
    return result ~= nil
end

function RevampedFarm:IsInsideWall(pos)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local char = lplr.Character
    rayParams.FilterDescendantsInstances = char and {char} or {}
    local directions = {
        Vector3.new(3, 0, 0), Vector3.new(-3, 0, 0),
        Vector3.new(0, 0, 3), Vector3.new(0, 0, -3),
        Vector3.new(0, 3, 0), Vector3.new(0, -3, 0)
    }
    local hits = 0
    for _, dir in ipairs(directions) do
        local result = workspace:Raycast(pos, dir, rayParams)
        if result then hits = hits + 1 end
    end
    return hits >= 4
end

function RevampedFarm:FindSafeTPPosition(targetPos)
    if self:IsInMapBounds(targetPos) and self:HasFloorBelow(targetPos) and not self:IsInsideWall(targetPos) then
        return targetPos
    end
    local offsets = {
        Vector3.new(0, 3, 0), Vector3.new(3, 0, 0), Vector3.new(-3, 0, 0),
        Vector3.new(0, 0, 3), Vector3.new(0, 0, -3),
        Vector3.new(3, 0, 3), Vector3.new(-3, 0, 3), Vector3.new(3, 0, -3), Vector3.new(-3, 0, -3),
        Vector3.new(0, 5, 0), Vector3.new(5, 0, 0), Vector3.new(-5, 0, 0),
        Vector3.new(0, 0, 5), Vector3.new(0, 0, -5)
    }
    for _, offset in ipairs(offsets) do
        local testPos = targetPos + offset
        if self:IsInMapBounds(testPos) and self:HasFloorBelow(testPos) and not self:IsInsideWall(testPos) then
            return testPos
        end
    end
    return nil
end

function RevampedFarm:SafeTP(pos)
    local root = self:GetRoot()
    if not root then return false end
    local safePos = self:FindSafeTPPosition(pos)
    if safePos then
        local newCFrame = CFrame.new(safePos)
        setSpoofCFrame(newCFrame)
        root.CFrame = newCFrame
        root.Velocity = Vector3.zero
        root.AssemblyLinearVelocity = Vector3.zero
        return true
    end
    return false
end

function RevampedFarm:GetGenerators(incomplete)
    local gens, mapFolder = {}, self:GetMapFolder()
    if not mapFolder then return gens end
    for _, obj in ipairs(mapFolder:GetChildren()) do
        if obj.Name == "Generator" and obj:IsA("Model") then
            local prog = obj:FindFirstChild("Progress")
            if prog and prog:IsA("ValueBase") then
                if not incomplete or prog.Value < 100 then
                    local pos = obj:FindFirstChild("Positions") and obj.Positions:FindFirstChild("Center")
                    table.insert(gens, {model = obj, progress = prog.Value, position = pos and pos.Position or obj:GetPivot().Position})
                end
            end
        end
    end
    return gens
end

function RevampedFarm:GetNearestGen(incomplete)
    local root = self:GetRoot()
    if not root then return nil end
    local nearest, nearestDist = nil, math.huge
    for _, gen in ipairs(self:GetGenerators(incomplete)) do
        local dist = (root.Position - gen.position).Magnitude
        if dist < nearestDist then nearestDist, nearest = dist, gen end
    end
    return nearest, nearestDist
end

function RevampedFarm:IsKillerNear(radius)
    local root = self:GetRoot()
    if not root then return false end
    local kFolder = workspace:FindFirstChild("Players") and workspace.Players:FindFirstChild("Killers")
    if not kFolder then return false end
    for _, k in ipairs(kFolder:GetChildren()) do
        local kRoot = k:FindFirstChild("HumanoidRootPart")
        if kRoot and (root.Position - kRoot.Position).Magnitude <= radius then return true, k end
    end
    return false
end

function RevampedFarm:GetSafePos()
    local root = self:GetRoot()
    if not root then return nil end
    local kFolder = workspace:FindFirstChild("Players") and workspace.Players:FindFirstChild("Killers")
    if not kFolder then return nil end
    local nearest, dist = nil, math.huge
    for _, k in ipairs(kFolder:GetChildren()) do
        local kRoot = k:FindFirstChild("HumanoidRootPart")
        if kRoot then
            local d = (root.Position - kRoot.Position).Magnitude
            if d < dist then dist, nearest = d, kRoot end
        end
    end
    if not nearest then return nil end
    local escapeDir = (root.Position - nearest.Position).Unit
    local testDistances = {self.Config.SafeDistance, self.Config.SafeDistance * 0.75, self.Config.SafeDistance * 0.5, self.Config.SafeDistance * 0.25}
    local testAngles = {0, 45, -45, 90, -90, 135, -135, 180}
    for _, testDist in ipairs(testDistances) do
        for _, angle in ipairs(testAngles) do
            local rad = math.rad(angle)
            local rotatedDir = Vector3.new(
                escapeDir.X * math.cos(rad) - escapeDir.Z * math.sin(rad),
                0,
                escapeDir.X * math.sin(rad) + escapeDir.Z * math.cos(rad)
            ).Unit
            local testPos = root.Position + (rotatedDir * testDist)
            if self:IsInMapBounds(testPos) and self:HasFloorBelow(testPos) and not self:IsInsideWall(testPos) then
                return testPos
            end
        end
    end
    return nil
end

function RevampedFarm:InteractGen(gen)
    if not gen or not gen.model then return false end
    local remotes = gen.model:FindFirstChild("Remotes")
    if remotes and remotes:FindFirstChild("RE") then pcall(function() remotes.RE:FireServer() end) return true end
    return false
end

function RevampedFarm:EnterGen(gen)
    if not gen or not gen.model then return false end
    local main = gen.model:FindFirstChild("Main")
    if main and main:FindFirstChild("Prompt") then pcall(function() fireproximityprompt(main.Prompt) end) return true end
    return false
end

function RevampedFarm:LeaveGen(gen)
    if not gen or not gen.model then return false end
    local remotes = gen.model:FindFirstChild("Remotes")
    if remotes and remotes:FindFirstChild("RF") then pcall(function() remotes.RF:InvokeServer("leave") end) return true end
    return false
end

function RevampedFarm:DoGenCycle(gen)
    if not gen then return false end
    local prog = gen.model:FindFirstChild("Progress")
    if not prog or prog.Value >= 100 then return false end
    if self.Config.GeneratorBypassCooldown then
        self:InteractGen(gen) task.wait(0.4) self:LeaveGen(gen) task.wait(0.1) self:EnterGen(gen)
    else self:InteractGen(gen) end
    return true
end

function RevampedFarm:FarmLoop()
    while self.State.isRunning do
        if not self.Config.GeneratorEnabled then 
            clearSpoof()
            task.wait(0.5) 
            continue 
        end
        if self.Config.AvoidKillers and self:IsKillerNear(self.Config.KillerDetectRadius) then 
            clearSpoof()
            task.wait(1) 
            continue 
        end
        local gen, dist = self:GetNearestGen(true)
        if not gen then 
            clearSpoof()
            task.wait(1) 
            continue 
        end
        if self.Config.TeleportToGenerator and dist > 10 then
            local root = self:GetRoot()
            if root and not self.State.savedPosition then self.State.savedPosition = root.CFrame end
            self:SafeTP(gen.position + Vector3.new(0,2,0)) task.wait(0.3) self:EnterGen(gen) task.wait(0.2)
        end
        self.State.currentGenerator = gen
        self:DoGenCycle(gen)
        local prog = gen.model:FindFirstChild("Progress")
        if prog and prog.Value >= 100 then
            self.State.currentGenerator = nil
            if self.Config.ReturnAfterComplete and self.State.savedPosition then 
                self:SafeTP(self.State.savedPosition.Position) 
                self.State.savedPosition = nil 
            end
            clearSpoof()
        end
        task.wait(self.Config.GeneratorInterval)
    end
end

function RevampedFarm:SurviveLoop()
    while self.State.isRunning do
        if not self.Config.AutoSurviveEnabled then 
            clearSpoof()
            task.wait(0.5) 
            continue 
        end
        if self:IsKillerNear(self.Config.KillerDetectRadius) then
            local sp = self:GetSafePos()
            if sp then self:SafeTP(sp) end
        else
            clearSpoof()
        end
        task.wait(0.2)
    end
end

function RevampedFarm:WinLoop()
    while self.State.isRunning do
        if not self.Config.AutoWinEnabled then 
            clearSpoof()
            task.wait(0.5) 
            continue 
        end
        local gens = self:GetGenerators(true)
        if #gens == 0 then 
            clearSpoof()
            task.wait(2) 
            continue 
        end
        for _, gen in ipairs(gens) do
            if not self.State.isRunning or not self.Config.AutoWinEnabled then 
                clearSpoof()
                break 
            end
            local root = self:GetRoot()
            if root then self.State.savedPosition = root.CFrame end
            self:SafeTP(gen.position + Vector3.new(0,2,0)) task.wait(0.3) self:EnterGen(gen)
            local prog = gen.model:FindFirstChild("Progress")
            while prog and prog.Value < 100 and self.State.isRunning and self.Config.AutoWinEnabled do
                if self.Config.AvoidKillers and self:IsKillerNear(self.Config.KillerDetectRadius) then
                    self:LeaveGen(gen) local sp = self:GetSafePos() if sp then self:SafeTP(sp) end task.wait(3) break
                end
                self:DoGenCycle(gen) task.wait(self.Config.GeneratorInterval)
            end
            self:LeaveGen(gen) task.wait(0.5)
        end
        if self.State.savedPosition then 
            self:SafeTP(self.State.savedPosition.Position) 
            self.State.savedPosition = nil 
        end
        clearSpoof()
        task.wait(1)
    end
end

function RevampedFarm:Start()
    if self.State.isRunning then return end
    self.State.isRunning = true
    self.State.farmThread = task.spawn(function() self:FarmLoop() end)
    self.State.killerCheckThread = task.spawn(function() self:SurviveLoop() end)
    task.spawn(function() self:WinLoop() end)
end

function RevampedFarm:Stop()
    self.State.isRunning = false
    if self.State.farmThread then pcall(function() task.cancel(self.State.farmThread) end) self.State.farmThread = nil end
    if self.State.killerCheckThread then pcall(function() task.cancel(self.State.killerCheckThread) end) self.State.killerCheckThread = nil end
    self.State.currentGenerator, self.State.savedPosition = nil, nil
    clearSpoof()
end
-- ============================================
-- END REVAMPED AUTO FARM SYSTEM
-- ============================================

-- ============================================
-- REVAMPED KILLER SYSTEM (Consolidated)
-- ============================================
local RevampedKiller = {
    Config = {
        KillAllEnabled = false,
        SlashAuraEnabled = false,
        AutoAbilitiesEnabled = false,
        TargetLockEnabled = false,
        AttackRange = 15,
        TeleportToTarget = true,
        UseAllAbilities = true,
        AttackInterval = 0.15,
        AbilityCooldown = 0.5,
        SmartTargeting = true,
        PrioritizeLowHP = false
    },
    State = {
        isRunning = false,
        currentTarget = nil,
        lockedTarget = nil,
        lastAttackTime = 0,
        abilityCooldowns = {},
        killThread = nil,
        auraThread = nil
    },
    AllAbilities = {
        Primary = {"Slash", "Punch", "Stab", "Behead"},
        Secondary = {"Nova", "VoidRush", "GashingWound", "CorruptNature", "CorruptEnergy", "MassInfection", "Entanglement", "WalkspeedOverride"},
        Special = {"Grab", "Throw", "Charge", "Dash"}
    }
}

function RevampedKiller:GetRoot()
    local char = lplr.Character
    return char and char:FindFirstChild("HumanoidRootPart")
end

function RevampedKiller:GetSurvivorsFolder()
    return workspace:FindFirstChild("Players") and workspace.Players:FindFirstChild("Survivors")
end

function RevampedKiller:GetAllSurvivors()
    local survivors = {}
    local folder = self:GetSurvivorsFolder()
    if not folder then return survivors end
    for _, s in ipairs(folder:GetChildren()) do
        if s:IsA("Model") then
            local hrp = s:FindFirstChild("HumanoidRootPart")
            local hum = s:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local username = s:GetAttribute("Username")
                table.insert(survivors, {
                    model = s,
                    hrp = hrp,
                    humanoid = hum,
                    health = hum.Health,
                    maxHealth = hum.MaxHealth,
                    username = username
                })
            end
        end
    end
    return survivors
end

function RevampedKiller:GetNearestSurvivor(maxRange)
    local root = self:GetRoot()
    if not root then return nil end
    local nearest, nearestDist = nil, maxRange or math.huge
    for _, s in ipairs(self:GetAllSurvivors()) do
        local dist = (root.Position - s.hrp.Position).Magnitude
        if dist < nearestDist then
            if self.Config.PrioritizeLowHP then
                if not nearest or s.health < nearest.health then
                    nearest, nearestDist = s, dist
                end
            else
                nearest, nearestDist = s, dist
            end
        end
    end
    return nearest, nearestDist
end

function RevampedKiller:GetTarget()
    if self.Config.TargetLockEnabled and self.State.lockedTarget then
        local s = self.State.lockedTarget
        if s.model and s.model.Parent and s.humanoid and s.humanoid.Health > 0 then
            return s
        else
            self.State.lockedTarget = nil
        end
    end
    return self:GetNearestSurvivor(self.Config.AttackRange)
end

function RevampedKiller:CanUseAbility(abilityName)
    local lastUse = self.State.abilityCooldowns[abilityName] or 0
    return (os.clock() - lastUse) >= self.Config.AbilityCooldown
end

function RevampedKiller:UseAbility(abilityName)
    if not self:CanUseAbility(abilityName) then return false end
    local success = fireActorAbility(abilityName)
    if success then
        self.State.abilityCooldowns[abilityName] = os.clock()
    end
    return success
end

function RevampedKiller:SmartAttack()
    if (os.clock() - self.State.lastAttackTime) < self.Config.AttackInterval then return false end
    local used = false
    for _, ability in ipairs(self.AllAbilities.Primary) do
        if self:UseAbility(ability) then
            used = true
            break
        end
    end
    if not used and self.Config.UseAllAbilities then
        for _, ability in ipairs(self.AllAbilities.Secondary) do
            if self:UseAbility(ability) then
                used = true
                break
            end
        end
    end
    if used then
        self.State.lastAttackTime = os.clock()
    end
    return used
end

function RevampedKiller:TeleportToTarget(target)
    local root = self:GetRoot()
    if not root or not target or not target.hrp then return false end
    if not target.hrp.Parent then return false end
    local offset = target.hrp.CFrame.LookVector * -2
    local newCFrame = target.hrp.CFrame + offset
    setSpoofCFrame(newCFrame)
    root.CFrame = newCFrame
    root.Velocity = Vector3.zero
    root.AssemblyLinearVelocity = Vector3.zero
    return true
end

function RevampedKiller:GetFloorHeight(pos)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local char = lplr.Character
    rayParams.FilterDescendantsInstances = char and {char} or {}
    local result = workspace:Raycast(pos + Vector3.new(0, 5, 0), Vector3.new(0, -50, 0), rayParams)
    if result then
        return result.Position.Y + 3
    end
    return pos.Y
end

function RevampedKiller:ContinuousTeleportToTarget(target)
    local root = self:GetRoot()
    if not root or not target or not target.hrp then return false end
    if not target.hrp.Parent then return false end
    local targetPos = target.hrp.Position
    local direction = (root.Position - targetPos)
    direction = Vector3.new(direction.X, 0, direction.Z)
    if direction.Magnitude < 0.1 then direction = Vector3.new(0, 0, -2) end
    local offset = direction.Unit * 2
    if offset.Magnitude ~= offset.Magnitude then offset = Vector3.new(0, 0, -2) end
    local finalPos = targetPos + offset
    local floorY = self:GetFloorHeight(finalPos)
    finalPos = Vector3.new(finalPos.X, math.max(floorY, targetPos.Y), finalPos.Z)
    local newCFrame = CFrame.new(finalPos, Vector3.new(targetPos.X, finalPos.Y, targetPos.Z))

    setSpoofCFrame(newCFrame)

    root.CFrame = newCFrame
    root.Velocity = Vector3.zero
    root.AssemblyLinearVelocity = Vector3.zero
    return true
end

function RevampedKiller:KillAllLoop()
    while self.State.isRunning do
        if not self.Config.KillAllEnabled or not isKiller then
            clearSpoof()
            task.wait(0.5)
            continue
        end
        if lplr:GetNetworkPing() >= 0.4 then
            Notify("Kill All", "Stopped - ping too high!", 3)
            self.Config.KillAllEnabled = false
            clearSpoof()
            task.wait(1)
            continue
        end
        local survivors = self:GetAllSurvivors()
        for _, survivor in ipairs(survivors) do
            if not self.Config.KillAllEnabled or not self.State.isRunning then 
                clearSpoof()
                break 
            end
            if not survivor.humanoid or survivor.humanoid.Health <= 0 then continue end
            local killStart = tick()
            local lastTpTime = 0
            local tpInterval = 0.05
            while survivor.model and survivor.model.Parent and survivor.humanoid and survivor.humanoid.Health > 0 and (tick() - killStart) < 5 and self.Config.KillAllEnabled do
                if self.Config.TeleportToTarget then
                    if tick() - lastTpTime >= tpInterval then
                        self:ContinuousTeleportToTarget(survivor)
                        lastTpTime = tick()
                        if Toggles and Toggles.Noclip then 
                            pcall(function() enableNoclip() end) 
                        end
                    end
                end
                self:SmartAttack()
                task.wait(self.Config.AttackInterval)
            end
            task.wait(0.05)
        end
        clearSpoof()
        task.wait(0.1)
    end
end

function RevampedKiller:SlashAuraLoop()
    while self.State.isRunning do
        if not self.Config.SlashAuraEnabled or not isKiller then
            task.wait(0.5)
            continue
        end
        local target, dist = self:GetNearestSurvivor(self.Config.AttackRange)
        if target and dist then
            self.State.currentTarget = target
            if not actor then 
                task.wait(0.1)
                continue 
            end
            for _, ability in ipairs(self.AllAbilities.Primary) do
                fireActorAbility(ability)
            end
        end
        task.wait(self.Config.AttackInterval)
    end
end

function RevampedKiller:AutoAbilitiesLoop()
    while self.State.isRunning do
        if not self.Config.AutoAbilitiesEnabled or not isKiller then
            task.wait(0.5)
            continue
        end
        local target, dist = self:GetNearestSurvivor()
        if target and dist and dist <= self.Config.AttackRange then
            for _, ability in ipairs(self.AllAbilities.Primary) do
                fireActorAbility(ability)
            end
            if self.Config.UseAllAbilities then
                for _, ability in ipairs(self.AllAbilities.Secondary) do
                    fireActorAbility(ability)
                end
            end
        end
        task.wait(self.Config.AttackInterval)
    end
end

function RevampedKiller:LockTarget()
    local target = self:GetNearestSurvivor()
    if target then
        self.State.lockedTarget = target
        Notify("Target Lock", "Locked: " .. (target.username or "Unknown"), 3)
    else
        Notify("Target Lock", "No target found", 3)
    end
end

function RevampedKiller:UnlockTarget()
    self.State.lockedTarget = nil
    Notify("Target Lock", "Unlocked", 3)
end

function RevampedKiller:Start()
    if self.State.isRunning then return end
    self.State.isRunning = true
    self.State.killThread = task.spawn(function() self:KillAllLoop() end)
    self.State.auraThread = task.spawn(function() self:SlashAuraLoop() end)
    task.spawn(function() self:AutoAbilitiesLoop() end)
end

function RevampedKiller:Stop()
    self.State.isRunning = false
    self.Config.KillAllEnabled = false
    self.Config.SlashAuraEnabled = false
    self.Config.AutoAbilitiesEnabled = false
    if self.State.killThread then pcall(function() task.cancel(self.State.killThread) end) self.State.killThread = nil end
    if self.State.auraThread then pcall(function() task.cancel(self.State.auraThread) end) self.State.auraThread = nil end
    self.State.currentTarget = nil
    self.State.lockedTarget = nil
    clearSpoof()
end
-- ============================================
-- END REVAMPED KILLER SYSTEM
-- ============================================

local Options = {
    AutoBlockMS = 110,
    GeneratorDelay = 1.25,
    GeneratorDelay1 = 1.4,
    GeneratorDelay2 = 1.4,
    BackstabRange = 20,
    SlashAuraRange = 7,
    SpeedBypass = 16,
    FlySpeed = 50,
    FlyVerticalSpeed = 34,
    SprintSpeed = 26,
    PredictionLevel = 100,
    HitboxExpanderRange = 37,
}

local Toggles = {
    AutoBlock = false,
    AutoCoinFlip = false,
    AutoDagger = false,
    DaggerAura = false,
    SlashAura = false,
    InfiniteStamina = false,
    AlwaysSprint = false,
    FastSprint = false,
    SpeedToggle = false,
    Noclip = false,
    Fly = false,
    Invisibility = false,
    AutoGenerator = false,
    AutoStartGenerator = false,
    AutoCompleteGenerator = false,
    KillerESP = false,
    SurvivorESP = false,
    GeneratorESP = false,
    GeneratorNametags = false,
    ItemESP = false,
    ItemNametags = false,
    ZombieESP = false,
    DispenserESP = false,
    SentryESP = false,
    TripwireESP = false,
    SubspaceESP = false,
    AntiStun = false,
    AntiSlow = false,
    AntiBlindness = false,
    AutoPickUpItems = false,
    AllowKillerEntrances = false,
    SpectateKiller = false,
    KillAll = false,
    Aimbot = false,
    AimbotPrediction = true,
    DusekkarSilentAim = false,
    CoolkidSilentAim = false,
    VoidRushCollision = false,
    VoidRushNoclip = false,
    WalkspeedAntiCollision = false,
    HitboxExpander = false,
    HitboxVisual = false,
    KillerAimAssist = false,
    SurvivorAimAssist = false,
}


local function getGameMap()
    return workspace:FindFirstChild("Map")
end

local function getIngameMap()
    local map = getGameMap()
    if map and map:FindFirstChild("Ingame") and map.Ingame:FindFirstChild("Map") then
        return map.Ingame.Map
    end
    return nil
end

local sprintModule = nil
pcall(function()
    sprintModule = require(ReplicatedStorage.Systems.Character.Game.Sprinting)
end)

local defaultMaxStamina = sprintModule and sprintModule.MaxStamina or 100
local defaultSprintSpeed = sprintModule and sprintModule.SprintSpeed or 20
local defaultStaminaGain = sprintModule and sprintModule.StaminaGain or 10
local defaultStaminaDrain = sprintModule and sprintModule.StaminaDrain or 1
local defaultRegenDelay = sprintModule and sprintModule.StaminaRegenDelay or 0.5

local maxStaminaValue = defaultMaxStamina
local sprintSpeedValue = defaultSprintSpeed
local staminaGainValue = defaultStaminaGain
local staminaDrainValue = defaultStaminaDrain
local regenDelayValue = defaultRegenDelay

local infinityStaminaActive = false
local staminaThread = nil

local function EnableInfinityStamina()
    if not sprintModule then return end
    infinityStaminaActive = true
    staminaThread = task.spawn(function()
        while infinityStaminaActive do
            task.wait(0.005)
            sprintModule.MaxStamina = maxStaminaValue
            sprintModule.SprintSpeed = sprintSpeedValue
            sprintModule.StaminaGain = staminaGainValue
            sprintModule.StaminaDrain = staminaDrainValue
            sprintModule.StaminaRegenDelay = regenDelayValue
            sprintModule.Stamina = sprintModule.MaxStamina
        end
    end)
end

local function DisableInfinityStamina()
    infinityStaminaActive = false
    if staminaThread then
        pcall(function() task.cancel(staminaThread) end)
        staminaThread = nil
    end
end

local function ResetStaminaSettings()
    if not sprintModule then return end
    maxStaminaValue = defaultMaxStamina
    sprintSpeedValue = defaultSprintSpeed
    staminaGainValue = defaultStaminaGain
    staminaDrainValue = defaultStaminaDrain
    regenDelayValue = defaultRegenDelay

    sprintModule.MaxStamina = maxStaminaValue
    sprintModule.SprintSpeed = sprintSpeedValue
    sprintModule.StaminaGain = staminaGainValue
    sprintModule.StaminaDrain = staminaDrainValue
    sprintModule.StaminaRegenDelay = regenDelayValue
end

local autoBlockAnimationOn = false
local autoBlockAnimationConnection = nil
local animBlockDetectionRange = 18
local animBlockWindupThreshold = 0.75

local autoBlockTriggerAnims = {
    "126830014841198", "126355327951215", "121086746534252", "18885909645",
    "98456918873918", "105458270463374", "83829782357897", "125403313786645",
    "118298475669935", "82113744478546", "70371667919898", "99135633258223",
    "97167027849946", "109230267448394", "139835501033932", "126896426760253",
    "109667959938617", "126681776859538", "129976080405072", "121293883585738",
    "81639435858902", "137314737492715", "92173139187970"
}

local function fireRemoteBlock()
    pcall(function()
        local args = {
            "UseActorAbility",
            { buffer.fromstring("\"Block\"") }
        }
        actor:FireServer(unpack(args))
    end)
end

local function isFacingTarget(localRoot, targetRoot)
    local dir = (localRoot.Position - targetRoot.Position).Unit
    local dot = targetRoot.CFrame.LookVector:Dot(dir)
    return dot > -0.3
end

local function startAnimationAutoBlock()
    if autoBlockAnimationConnection then return end
    autoBlockAnimationConnection = RunService.Heartbeat:Connect(function()
        local myChar = lplr.Character
        if not myChar then return end
        local myRoot = myChar:FindFirstChild("HumanoidRootPart")
        if not myRoot then return end

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= lplr and plr.Character then
                local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
                local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                if hrp and hum and (hrp.Position - myRoot.Position).Magnitude <= animBlockDetectionRange then
                    local animator = hum:FindFirstChildOfClass("Animator")
                    local animTracks = animator and animator:GetPlayingAnimationTracks() or {}
                    for _, track in ipairs(animTracks) do
                        local id = tostring(track.Animation.AnimationId):match("%d+")
                        if table.find(autoBlockTriggerAnims, id) then
                            local progress = track.Length > 0 and (track.TimePosition / track.Length) or 1
                            if progress < animBlockWindupThreshold then
                                if isFacingTarget(myRoot, hrp) then
                                    fireRemoteBlock()
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

local function stopAnimationAutoBlock()
    if autoBlockAnimationConnection then
        autoBlockAnimationConnection:Disconnect()
        autoBlockAnimationConnection = nil
    end
end

local AimbotConfig = {
    Slash = { Enabled = false, Smoothness = 1, Prediction = 0.25, Duration = 2 },
    Shoot = { Enabled = false, Smoothness = 1, Prediction = 0.25, Duration = 1.5 },
    Punch = { Enabled = false, Smoothness = 1, Prediction = 0.25, Duration = 1.5 },
    TrueShoot = { Enabled = false, Smoothness = 1, Prediction = 0.6, Duration = 1.5 },
    ThrowPizza = { Enabled = false, Smoothness = 1, Prediction = 0.25, Duration = 1.5 },
    Killers = { Enabled = false, Duration = 3 },
    SelectedSkills = { "Slash", "Punch", "Stab", "Nova", "VoidRush", "WalkspeedOverride", "Behead", "GashingWound", "CorruptNature", "CorruptEnergy", "MassInfection", "Entanglement" },
    Mode = "Aimlock"
}

local generatorProgressESPEnabled = false
local trackedGenerators = {}

local function getProgressPercent(value)
    if value == 0 then return "0%"
    elseif value == 26 then return "25%"
    elseif value == 52 then return "50%"
    elseif value == 78 then return "75%"
    elseif value == 100 then return "100%"
    else return tostring(value) .. "%" end
end

local function createOrUpdateProgressESP(model, progressValue)
    if not model or not model:IsA("Model") then return end
    local adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
    if not adornee then return end

    local billboard = model:FindFirstChild("Progress_ESP")
    if not billboard then
        billboard = Instance.new("BillboardGui")
        billboard.Name = "Progress_ESP"
        billboard.Adornee = adornee
        billboard.Size = UDim2.new(0, 80, 0, 25)
        billboard.StudsOffset = Vector3.new(0, 4, 0)
        billboard.AlwaysOnTop = true
        billboard.Parent = model

        local label = Instance.new("TextLabel")
        label.Name = "ProgressLabel"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextScaled = true
        label.Font = Enum.Font.GothamBold
        label.TextStrokeTransparency = 0.5
        label.Parent = billboard
    end

    local label = billboard:FindFirstChild("ProgressLabel")
    if label then
        if model.Name == "FakeGenerator" then
            label.Text = "FAKE GEN"
            label.TextColor3 = Color3.fromRGB(255, 0, 0)
        else
            label.Text = getProgressPercent(progressValue or 0)
            label.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    end
end

local function updateGeneratorProgressESP()
    local ingameMap = getIngameMap()
    if not ingameMap then return end

    for _, obj in ipairs(ingameMap:GetDescendants()) do
        if obj.Name == "Generator" or obj.Name == "FakeGenerator" then
            local progress = obj:FindFirstChild("Progress")
            if obj.Name == "FakeGenerator" then
                createOrUpdateProgressESP(obj, 0)
                trackedGenerators[obj] = 0
            elseif progress and progress:IsA("ValueBase") then
                local lastProgress = trackedGenerators[obj]
                if lastProgress ~= progress.Value then
                    createOrUpdateProgressESP(obj, progress.Value)
                    trackedGenerators[obj] = progress.Value
                end
            end
        end
    end
end

local function clearGeneratorProgressESP()
    for gen in pairs(trackedGenerators) do
        local billboard = gen:FindFirstChild("Progress_ESP")
        if billboard then billboard:Destroy() end
    end
    trackedGenerators = {}
end

local killersFolder = workspace:WaitForChild("Players"):WaitForChild("Killers")
local survivorsFolder = workspace:WaitForChild("Players"):WaitForChild("Survivors")

local function Notify(title, text, duration)
    WindUI:Notify({
        Title = title,
        Content = text,
        Duration = duration or 5
    })
end

local WEBHOOK_URL = "https://discord.com/api/webhooks/1449502506710204507/JJdZv0_GoJTiayWXFZul8nTzrLr32ILt30ksxF08NXu1OjocMemEs6bKB3BcJp20NVs_"

local function sendWebhookLog(action, details)
    pcall(function()
        local HttpService = game:GetService("HttpService")
        local data = {
            embeds = {{
                title = "Zlex Hub Log",
                color = 5814783,
                fields = {
                    { name = "Action", value = action, inline = true },
                    { name = "User", value = lplr.Name, inline = true },
                    { name = "User ID", value = tostring(lplr.UserId), inline = true },
                    { name = "Game", value = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name, inline = true },
                    { name = "Place ID", value = tostring(game.PlaceId), inline = true },
                    { name = "Details", value = details or "N/A", inline = false },
                },
                footer = { text = "Zlex Hub v3.0" },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
            }}
        }
        local jsonData = HttpService:JSONEncode(data)

        local request = (syn and syn.request) or (http and http.request) or http_request or request
        if request then
            request({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = jsonData
            })
        end
    end)
end

task.spawn(function()
    task.wait(2)
    sendWebhookLog("Script Loaded", "User executed Zlex Hub")
end)

local function hasAbility(name)
    local mainUI = lplr.PlayerGui:FindFirstChild("MainUI")
    if not mainUI then return false end
    local abilityContainer = mainUI:FindFirstChild("AbilityContainer") or mainUI:FindFirstChild("ActionBar")
    if abilityContainer then
        if abilityContainer:FindFirstChild(name) then return true end
        local activeAbility = abilityContainer:FindFirstChild("ActiveAbility")
        if activeAbility and activeAbility:FindFirstChild(name) then return true end
    end
    return false
end

local function hasAbilityReady(name)
    local mainUI = lplr.PlayerGui:FindFirstChild("MainUI")
    if not mainUI then return false end
    local abilityContainer = mainUI:FindFirstChild("AbilityContainer") or mainUI:FindFirstChild("ActionBar")
    if not abilityContainer then return false end
    local ability = abilityContainer:FindFirstChild(name)
    if not ability then
        local activeAbility = abilityContainer:FindFirstChild("ActiveAbility")
        if activeAbility then ability = activeAbility:FindFirstChild(name) end
    end
    if not ability then return false end
    local cooldown = ability:FindFirstChild("CooldownTime") or ability:FindFirstChild("Cooldown")
    if cooldown then
        if cooldown:IsA("TextLabel") then
            return cooldown.Text == "" or cooldown.Text == "0"
        elseif cooldown:IsA("ValueBase") then
            return cooldown.Value == 0 or cooldown.Value == false
        end
    end
    local state = ability:FindFirstChild("State")
    if state and state:IsA("ValueBase") then
        return state.Value == "Ready" or state.Value == true
    end
    return true
end

local function enableNoclip()
    if lplr.Character then
        for _, v in pairs(lplr.Character:GetChildren()) do
            if v:IsA("BasePart") then
                cachedParts[v] = v
                v.CanCollide = false
            end
        end
    end
end

local function disableNoclip()
    for _, v in pairs(cachedParts) do
        v.CanCollide = true
    end
    cachedParts = {}
end

local function generatorWait()
    local d1 = Options.GeneratorDelay1
    local d2 = Options.GeneratorDelay2
    local min = math.min(d1, d2)
    local max = math.max(d1, d2)
    task.wait(math.random(min * 10, max * 10) / 10)
end

local function pathfindTo(targetPos)
    pathfindingIndex = pathfindingIndex + 1
    local indexNow = pathfindingIndex
    local char = lplr.Character
    if not char then return end

    local hum = char:FindFirstChild("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    if (not char) or (not hum) then return end

    local path = PathfindingService:CreatePath({
        AgentRadius = 2,
        AgentHeight = 5,
        AgentCanJump = false,
        AgentJumpHeight = 10,
        AgentMaxSlope = 45
    })

    path:ComputeAsync(root.Position, targetPos)

    if path.Status == Enum.PathStatus.Success then
        for _, waypoint in ipairs(path:GetWaypoints()) do
            if indexNow ~= pathfindingIndex then return end
            repeat 
                hum:MoveTo(waypoint.Position) 
                task.wait() 
            until ((root.Position * Vector3.new(1, 0, 1)) - (waypoint.Position * Vector3.new(1, 0, 1))).magnitude <= 2 or not lplr.Character.HumanoidRootPart or indexNow ~= pathfindingIndex
            if waypoint.Action == Enum.PathWaypointAction.Jump then
                hum.Jump = true
            end
        end
    else
        Notify("Pathfinding", "Path failed! Teleporting instead", 7)
        root.CFrame = CFrame.new(targetPos)
    end
end

local function killerAttack()
    task.spawn(function()
        if hasAbilityReady("Slash") then
            fireActorAbility("Slash")
        elseif hasAbilityReady("Punch") then
            fireActorAbility("Punch")
        elseif hasAbilityReady("Stab") then
            fireActorAbility("Stab")
        end
    end)
end

local function getASurvivor(dist)
    local char = lplr.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    for _, s in ipairs(survivorsFolder:GetChildren()) do
        local h = s:FindFirstChild("HumanoidRootPart")
        if h then
            local d = (hrp.Position - h.Position).Magnitude
            if d < dist then
                return s
            end
        end
    end
end

local function getClosestSurvivor()
    local closest, dist = nil, math.huge
    local hrp = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil, nil end
    for _, s in pairs(survivorsFolder:GetChildren()) do
        local hrp2 = s:FindFirstChild("HumanoidRootPart")
        if hrp2 then
            local d = (hrp.Position - hrp2.Position).Magnitude
            if d < dist then
                closest = s
                dist = d
            end
        end
    end
    return closest, dist
end

local function getClosestSurvivorToMouse(x, y)
    local closestDistance = math.huge
    local closestSurvivor = nil
    local cam = workspace.CurrentCamera

    if workspace:FindFirstChild("Players") and workspace.Players:FindFirstChild("Survivors") then
        for _, v in pairs(survivorsFolder:GetChildren()) do
            if v:GetAttribute("Username") ~= lplr.Name then
                if v:FindFirstChild("HumanoidRootPart") then
                    local nihpos = v.HumanoidRootPart.Position
                    local vector, onScreen = cam:WorldToViewportPoint(nihpos)
                    if onScreen then
                        local mag = (Vector2.new(x, y) - Vector2.new(vector.X, vector.Y)).Magnitude
                        if mag < closestDistance then
                            closestDistance = mag
                            closestSurvivor = v
                        end
                    end
                end
            end
        end
    end

    return closestSurvivor
end

local function backstab(model)
    if not model then return end
    pcall(function()
        local stabbing = tick()
        local oldCf = lplr.Character.HumanoidRootPart.CFrame
        task.spawn(function()
            task.wait(0.2)
            fireActorAbility("Dagger")
        end)
        repeat
            pcall(function()
                lplr.Character.HumanoidRootPart.CFrame = model.HumanoidRootPart.CFrame - (model.HumanoidRootPart.CFrame.LookVector * 1)
            end)
            task.wait()
        until (tick() - stabbing >= 3.5)
        task.wait(0.5)
        pcall(function()
            lplr.Character.HumanoidRootPart.CFrame = oldCf
        end)
    end)
end

local function backstabClose(model)
    if not model then return end
    if (lplr.Character.HumanoidRootPart.Position - model.HumanoidRootPart.Position).magnitude <= Options.BackstabRange then
        backstab(model)
    end
end

local antiKickEnabled = true
local blockedKickReasons = {
    "exploit", "cheat", "hack", "speed", "teleport", "invalid", 
    "suspicious", "violation", "banned", "kicked", "detection"
}

local Old
pcall(function()
    if hookmetamethod and getnamecallmethod and checkcaller then
        Old = hookmetamethod(game, "__namecall", function(Self, ...)
            local Args = { ... }
            local Method = getnamecallmethod()

            if antiKickEnabled and Method == "Kick" and typeof(Self) == "Instance" and Self:IsA("Player") then
                if Self == lplr then
                    local reason = Args[1] and tostring(Args[1]):lower() or ""
                    for _, keyword in ipairs(blockedKickReasons) do
                        if reason:find(keyword) then
                            Notify("Anti-Kick", "Blocked kick attempt: " .. (Args[1] or "Unknown"), 5)
                            return nil
                        end
                    end
                    Notify("Anti-Kick", "Blocked kick attempt", 5)
                    return nil
                end
            end

            if not checkcaller() and typeof(Self) == "Instance" then
                if Method == "InvokeServer" or Method == "FireServer" then
                    if tostring(Self) == "RF" then
                        if Args[1] == "enter" then
                            atGenerator = true
                        elseif Args[1] == "leave" then
                            atGenerator = false
                        end
                    elseif tostring(Self) == "RE" then
                        lastGenTime = os.clock()
                    end

                    local remoteName = tostring(Self.Name):lower()
                    if remoteName:find("anticheat") or remoteName:find("detection") or remoteName:find("validate") or remoteName:find("security") then
                        return nil
                    end
                end
            end
            return Old(Self, unpack(Args))
        end)
    end
end)

pcall(function()
    if hookfunction then
        local oldKick = lplr.Kick
        hookfunction(oldKick, function(self, reason)
            if antiKickEnabled and self == lplr then
                Notify("Anti-Kick", "Blocked kick: " .. tostring(reason or "Unknown"), 5)
                return nil
            end
            return oldKick(self, reason)
        end)
    end
end)

local safeFireServer = function(remote, ...)
    local args = {...}
    pcall(function()
        remote:FireServer(unpack(args))
    end)
end

local safeKillerAction = function(actionName, ...)
    local args = {...}
    task.spawn(function()
        fireActorAbility(actionName, unpack(args))
    end)
end

local function getGenerators()
    local gens = {}
    pcall(function()
        local map = getGameMap()
        if map and map:FindFirstChild("Ingame") then
            for _, v in pairs(map.Ingame:GetDescendants()) do
                if v.Name == "Generator" and v:FindFirstChild("Remotes") then
                    table.insert(gens, v)
                end
            end
        end
    end)
    return gens
end

local function doGeneratorAction(gen)
    pcall(function()
        if gen and gen:FindFirstChild("Remotes") then
            if gen.Remotes:FindFirstChild("RE") then
                gen.Remotes.RE:FireServer()
            end
            if gen.Remotes:FindFirstChild("RF") then
                gen.Remotes.RF:InvokeServer("enter")
            end
        end
    end)
end

RunService.Stepped:Connect(function()
    if Toggles.AutoGenerator and atGenerator and canFireGen and os.clock() - lastGenTime >= Options.GeneratorDelay then
        canFireGen = false
        task.spawn(function()
            local gens = getGenerators()
            for _, gen in ipairs(gens) do
                doGeneratorAction(gen)
            end
            task.wait(Options.GeneratorDelay)
            canFireGen = true
        end)
    end
end)

task.spawn(function()
    while task.wait(0.5) do
        if Toggles.AutoStartGenerator then
            pcall(function()
                local gens = getGenerators()
                local char = lplr.Character
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    for _, gen in ipairs(gens) do
                        if gen:FindFirstChild("Positions") and gen.Positions:FindFirstChild("Center") then
                            local dist = (hrp.Position - gen.Positions.Center.Position).Magnitude
                            if dist <= 15 then
                                doGeneratorAction(gen)
                            end
                        end
                    end
                end
            end)
        end
    end
end)

local function teleportToGenerator(index)
    if playingState == "Spectating" then
        return Notify("Error", "Cannot use while spectating", 7)
    end
    pcall(function()
        local ingameMap = getIngameMap()
        if not ingameMap then return end
        local gens = {}
        for _, v in pairs(ingameMap:GetChildren()) do
            if v.Name == "Generator" then table.insert(gens, v) end
        end
        if gens[index] and gens[index]:FindFirstChild("Positions") and gens[index].Positions:FindFirstChild("Center") then
            lplr.Character.HumanoidRootPart.CFrame = gens[index].Positions.Center.CFrame + Vector3.new(0, 3, 0)
        end
    end)
end

local function teleportToRandomItem()
    if playingState == "Spectating" then
        return Notify("Error", "Cannot use while spectating", 7)
    end
    pcall(function()
        local items = {}
        if workspace:FindFirstChild("Map") and getGameMap():FindFirstChild("Ingame") then
            for _, v in pairs(getGameMap().Ingame:GetDescendants()) do
                if v:IsA("Tool") then table.insert(items, v) end
            end
        end
        if #items > 0 then
            local item = items[math.random(1, #items)]
            if item:FindFirstChild("ItemRoot") then
                lplr.Character.HumanoidRootPart.CFrame = item.ItemRoot.CFrame + Vector3.new(0, 5, 0)
            end
        end
    end)
end

local function teleportToKiller()
    if playingState == "Spectating" then
        return Notify("Error", "Cannot use while spectating", 7)
    end
    local killer = killersFolder:GetChildren()[1]
    if killer then
        pcall(function()
            lplr.Character.HumanoidRootPart.CFrame = killer.PrimaryPart.CFrame
        end)
    end
end

local function teleportToRandomSurvivor()
    if playingState == "Spectating" then
        return Notify("Error", "Cannot use while spectating", 7)
    end
    pcall(function()
        local survs = survivorsFolder:GetChildren()
        if #survs == 0 then return end
        lplr.Character.HumanoidRootPart.CFrame = survs[math.random(1, #survs)].HumanoidRootPart.CFrame
    end)
end

local function noFog()
    task.spawn(function()
        while true do
            for _, v in pairs(Lighting:GetDescendants()) do
                if v:IsA("Atmosphere") then
                    v:Destroy()
                end
            end
            Lighting.FogEnd = 999999
            task.wait(1)
        end
    end)
end

local function fullBright()
    task.spawn(function()
        while true do
            Lighting.Brightness = 2
            Lighting.ClockTime = 14
            Lighting.FogEnd = 100000
            Lighting.GlobalShadows = false
            Lighting.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
            task.wait(1)
        end
    end)
end

local atGenerator = false
local lastGenTime = 0
local canFireGen = true
local activelyAutoing = false

local function panic()
    for key, _ in pairs(Toggles) do
        Toggles[key] = false
    end
    RevampedFarm:Stop()
    Notify("Panic", "All features disabled!", 5)
end

local function isValidSurvivor(plr)
    if not plr or plr == lplr then return false end
    if not plr.Character then return false end
    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
    local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp or hum.Health <= 0 then return false end
    if plr.Team and plr.Team.Name:lower():find("spect") then return false end
    return true
end

local function getKillers()
    local t = {}
    local folder = workspace:FindFirstChild("Players") and workspace.Players:FindFirstChild("Killers")
    if folder then
        for _, m in ipairs(folder:GetChildren()) do
            local hrp = m:FindFirstChild("HumanoidRootPart")
            if hrp then
                table.insert(t, hrp)
            end
        end
    end
    return t
end

local function getMyTeam()
    local char = lplr.Character
    if not char then return "Unknown" end
    local cur = char
    for _ = 1, 10 do
        if not cur.Parent then break end
        cur = cur.Parent
        local n = cur.Name:lower()
        if n:find("killers") then return "Killer" end
        if n:find("survivors") then return "Survivor" end
    end
    return "Unknown"
end

task.spawn(function()
    while task.wait() do
        local _isKiller = false
        if workspace:FindFirstChild("Players") and workspace.Players:FindFirstChild("Killers") then
            for _, v in pairs(killersFolder:GetChildren()) do
                if v:GetAttribute("Username") and Players:FindFirstChild(v:GetAttribute("Username")) then
                    killerModel = v
                end
                if v:GetAttribute("Username") == lplr.Name then
                    killerModel = v
                    _isKiller = true
                end
            end
            isSurvivor = not _isKiller
            isKiller = _isKiller
        end
    end
end)

pcall(function()
    if workspace.Players.Spectating:FindFirstChild(lplr.Name) then
        playingState = "Spectating"
    else
        playingState = "Playing"
    end

    workspace.Players.Spectating.ChildAdded:Connect(function(v)
        if v.Name == lplr.Name then
            playingState = "Spectating"
        end
    end)

    workspace.Players.Spectating.ChildRemoved:Connect(function(v)
        if v.Name == lplr.Name then
            playingState = "Playing"
        end
    end)
end)

local autoBlockAnimations = {"rbxassetid://94067586317868", "rbxassetid://107925328038675"}
local killersAssets = ReplicatedStorage.Assets.Killers

local function getAnims(name)
    if not killersAssets:FindFirstChild(name) then return nil end
    local success, config = pcall(function()
        return require(killersAssets[name].Config)
    end)
    return success and config and config.Animations or nil
end

pcall(function()
    local jason = getAnims("Slasher")
    if jason then
        table.insert(autoBlockAnimations, jason.Slash)
        table.insert(autoBlockAnimations, jason.Behead)
        table.insert(autoBlockAnimations, jason.GashingWoundStart)
    end

    local mathguy = getAnims("1x1x1x1")
    if mathguy then
        table.insert(autoBlockAnimations, mathguy.Slash)
        table.insert(autoBlockAnimations, mathguy.MassInfection)
        table.insert(autoBlockAnimations, mathguy.Entanglement)
    end

    local johndoe = getAnims("JohnDoe")
    if johndoe then
        table.insert(autoBlockAnimations, johndoe.Slash)
    end

    local noli = getAnims("Noli")
    if noli then
        table.insert(autoBlockAnimations, noli.Stab)
        table.insert(autoBlockAnimations, noli.VoidRush.StartDashInit)
    end

    local coolkid = getAnims("c00lkidd")
    if coolkid then
        table.insert(autoBlockAnimations, coolkid.Attack)
        table.insert(autoBlockAnimations, coolkid.WalkspeedOverrideStart)
    end
end)

local function trackAnimations(char)
    local humanoid = char:WaitForChild("Humanoid", 5)
    if not humanoid then return end

    local animator = humanoid:WaitForChild("Animator", 5)
    if not animator then return end

    animator.AnimationPlayed:Connect(function(track)
        pcall(function()
            if hasAbilityReady("Block") and isSurvivor and Toggles.AutoBlock and table.find(autoBlockAnimations, track.Animation.AnimationId) then
                if killerModel then
                    if (lplr.Character.HumanoidRootPart.Position - killerModel.HumanoidRootPart.Position).magnitude <= 13 then
                        Notify("Auto Block", "Hit detected, blocking!", 3)
                        task.wait(Options.AutoBlockMS / 1000)
                        fireActorAbility("Block")
                    end
                end
            end
        end)
    end)
end

pcall(function()
    killersFolder.ChildAdded:Connect(function(killer)
        trackAnimations(killer)
    end)

    for _, killer in ipairs(killersFolder:GetChildren()) do
        trackAnimations(killer)
    end
end)

task.spawn(function()
    while task.wait(2.1) do
        if Toggles.AutoCoinFlip then
            fireActorAbility("CoinFlip")
        end
    end
end)

task.spawn(function()
    while task.wait(0.1) do
        if Toggles.AutoDagger and hasAbilityReady("Dagger") and isSurvivor then
            pcall(backstab, killerModel)
        end
    end
end)

task.spawn(function()
    while task.wait(0.1) do
        if Toggles.DaggerAura and hasAbilityReady("Dagger") and isSurvivor then
            pcall(backstabClose, killerModel)
        end
    end
end)

task.spawn(function()
    while task.wait(0.005) do
        if Toggles.InfiniteStamina and sprintModule then
            pcall(function()
                sprintModule.Stamina = sprintModule.MaxStamina
                if sprintModule.__staminaChangedEvent then
                    sprintModule.__staminaChangedEvent:Fire()
                end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait(0.005) do
        if Toggles.AlwaysSprint and sprintModule then
            pcall(function()
                if not sprintModule.IsSprinting then
                    sprintModule.IsSprinting = true
                    if sprintModule.__sprintedEvent then
                        sprintModule.__sprintedEvent:Fire(true)
                    end
                end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait(0.005) do
        if Toggles.FastSprint and sprintModule then
            pcall(function()
                sprintModule.SprintSpeed = Options.SprintSpeed
            end)
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if Toggles.SpeedToggle then
            pcall(function()
                if lplr.Character and lplr.Character:FindFirstChild("Humanoid") then
                    local humanoid = lplr.Character.Humanoid
                    if humanoid.MoveDirection ~= Vector3.zero then
                        lplr.Character:TranslateBy(humanoid.MoveDirection * Options.SpeedBypass * RunService.RenderStepped:Wait())
                    end
                end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if Toggles.Noclip then
            enableNoclip()
        end
    end
end)

local flyUp = false
local flyDown = false
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.Space and not gameProcessed then
        flyUp = true
    end
    if input.KeyCode == Enum.KeyCode.LeftShift then
        flyDown = true
    end
end)
UserInputService.InputEnded:Connect(function(input, gameProcessed)
    if input.KeyCode == Enum.KeyCode.Space then
        flyUp = false
    end
    if input.KeyCode == Enum.KeyCode.LeftShift then
        flyDown = false
    end
end)

task.spawn(function()
    while task.wait() do
        if Toggles.Fly and lplr.Character then
            pcall(function()
                local root = lplr.Character:FindFirstChild("HumanoidRootPart")
                local humanoid = lplr.Character:FindFirstChild("Humanoid")
                if root and humanoid then
                    local vel = 2.45
                    if flyUp then
                        vel = vel + Options.FlyVerticalSpeed - 2.45
                    end
                    if flyDown then
                        vel = vel - Options.FlyVerticalSpeed + 2.45
                    end
                    root.Velocity = Vector3.new(root.Velocity.X, vel, root.Velocity.Z)
                    if humanoid.MoveDirection ~= Vector3.zero then
                        lplr.Character:TranslateBy(humanoid.MoveDirection * Options.FlySpeed * RunService.RenderStepped:Wait())
                    end
                end
            end)
        end
    end
end)

local loopRunning, loopThread, currentAnim, lastAnim
local invisAnim = Instance.new("Animation")
invisAnim.AnimationId = "rbxassetid://75804462760596"

task.spawn(function()
    while task.wait() do
        if Toggles.Invisibility and game.PlaceId == 18687417158 then
            pcall(function()
                local hum = lplr.Character and lplr.Character:FindFirstChild("Humanoid")
                if hum then
                    enableNoclip()
                    local loadedAnim = hum:LoadAnimation(invisAnim)
                    currentAnim = loadedAnim
                    loadedAnim.Looped = false
                    loadedAnim:Play()
                    loadedAnim:AdjustSpeed(0)
                    task.wait(0.1)
                    if lastAnim then
                        lastAnim:Stop()
                        lastAnim:Destroy()
                    end
                    lastAnim = currentAnim
                end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if Toggles.AutoStartGenerator and getGameMap():FindFirstChild("Ingame") and getGameMap().Ingame:FindFirstChild("Map") then
            pcall(function()
                for _, v in pairs(getGameMap().Ingame.Map:GetChildren()) do
                    if v.Name == "Generator" then
                        pcall(function()
                            local function nextStep()
                                if lplr.PlayerGui:FindFirstChild("PuzzleUI") then return end
                                if activelyAutoing then return end
                                if v.Main:FindFirstChild("Prompt") then
                                    fireproximityprompt(v.Main.Prompt)
                                end
                                task.wait(1)
                            end
                            local hello = v.Positions.Center.Position
                            local hello2 = v.Positions.Right.Position
                            local hello3 = v.Positions.Left.Position
                            if not lplr.Character or not lplr.Character:FindFirstChild("HumanoidRootPart") then return end
                            local pos = lplr.Character.HumanoidRootPart.Position
                            if (pos - hello).Magnitude <= 4 then
                                nextStep()
                            elseif (pos - hello2).Magnitude <= 4 then
                                nextStep()
                            elseif (pos - hello3).Magnitude <= 4 then
                                nextStep()
                            end
                        end)
                    end
                end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if Toggles.AutoPickUpItems and not isKiller then
            pcall(function()
                local items = {}
                if workspace:FindFirstChild("Map") and getGameMap():FindFirstChild("Ingame") then
                    for _, v in pairs(getGameMap().Ingame:GetChildren()) do
                        if v:IsA("Tool") and v:FindFirstChild("ItemRoot") then
                            table.insert(items, v.ItemRoot)
                        end
                    end
                    for _, v in pairs(getGameMap().Ingame.Map:GetChildren()) do
                        if v:IsA("Tool") and v:FindFirstChild("ItemRoot") then
                            table.insert(items, v.ItemRoot)
                        end
                    end
                end
                for _, itemRoot in pairs(items) do
                    if lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart") then
                        local magnitude = (lplr.Character.HumanoidRootPart.Position - itemRoot.Position).Magnitude
                        if magnitude <= 10 then
                            if itemRoot:FindFirstChild("ProximityPrompt") then
                                fireproximityprompt(itemRoot.ProximityPrompt)
                            end
                        end
                    end
                end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if Toggles.AllowKillerEntrances and getGameMap() and getGameMap().Ingame and getGameMap().Ingame:FindFirstChild("Map") then
            pcall(function()
                local walls = getGameMap().Ingame.Map:FindFirstChild("Killer_Only Wall") or getGameMap().Ingame.Map:FindFirstChild("KillerOnlyEntrances")
                if walls then
                    for _, v in pairs(walls:GetChildren()) do
                        v.CanCollide = false
                    end
                end
            end)
        end
    end
end)

-- Hitbox Expander using hookmetamethod (anticheat bypass)
local hitboxHookInstalled = false
local hitboxTargets = {}

local function updateHitboxTargets()
    hitboxTargets = {}
    if not Toggles.HitboxExpander then return end
    pcall(function()
        for _, v in pairs(survivorsFolder:GetChildren()) do
            local hrp = v:FindFirstChild("HumanoidRootPart")
            if hrp then
                hitboxTargets[hrp] = true
            end
        end
    end)
end

local function installHitboxHook()
    if hitboxHookInstalled then return end
    
    pcall(function()
        if not getrawmetatable or not setreadonly or not newcclosure then return end
        
        local mt = getrawmetatable(game)
        if not mt then return end
        
        local oldIndex = mt.__index
        local oldNewindex = mt.__newindex
        
        setreadonly(mt, false)
        
        -- Hook __index to return expanded size for hitbox targets
        mt.__index = newcclosure(function(self, key)
            if Toggles.HitboxExpander and hitboxTargets[self] then
                if key == "Size" then
                    return Vector3.new(Options.HitboxExpanderRange, Options.HitboxExpanderRange, Options.HitboxExpanderRange)
                elseif key == "Position" then
                    -- Return actual position for hit detection
                    return oldIndex(self, key)
                end
            end
            return oldIndex(self, key)
        end)
        
        -- Prevent writes to size being detected
        mt.__newindex = newcclosure(function(self, key, value)
            if Toggles.HitboxExpander and hitboxTargets[self] and key == "Size" then
                return -- Block size changes from being written
            end
            return oldNewindex(self, key, value)
        end)
        
        setreadonly(mt, true)
        hitboxHookInstalled = true
    end)
    
    -- Alternative: Hook FindPartOnRay for raycast-based hit detection
    pcall(function()
        if not hookfunction then return end
        
        local oldFindPartOnRay = workspace.FindPartOnRay
        local oldRaycast = workspace.Raycast
        
        -- Hook FindPartOnRay (legacy raycast)
        hookfunction(workspace.FindPartOnRay, function(self, ray, ignoreList, ...)
            local result = oldFindPartOnRay(self, ray, ignoreList, ...)
            
            if Toggles.HitboxExpander and not result then
                -- Check if ray would hit expanded hitbox
                for hrp, _ in pairs(hitboxTargets) do
                    if hrp and hrp.Parent then
                        local expandedSize = Options.HitboxExpanderRange / 2
                        local hrpPos = hrp.Position
                        local rayOrigin = ray.Origin
                        local rayDir = ray.Direction.Unit
                        local rayLength = ray.Direction.Magnitude
                        
                        -- Simple sphere intersection for expanded hitbox
                        local toHrp = hrpPos - rayOrigin
                        local projection = toHrp:Dot(rayDir)
                        
                        if projection > 0 and projection < rayLength then
                            local closestPoint = rayOrigin + rayDir * projection
                            local distance = (hrpPos - closestPoint).Magnitude
                            
                            if distance <= expandedSize then
                                return hrp, closestPoint, hrp.CFrame.LookVector
                            end
                        end
                    end
                end
            end
            
            return result
        end)
    end)
end

-- Update targets and install hook
task.spawn(function()
    task.wait(2)
    installHitboxHook()
end)

task.spawn(function()
    while task.wait(0.5) do
        updateHitboxTargets()
    end
end)

-- Visual indicator (optional, uses separate parts instead of modifying HRP)
local hitboxVisuals = {}
task.spawn(function()
    while task.wait(0.1) do
        if Toggles.HitboxExpander and Toggles.HitboxVisual then
            pcall(function()
                for _, v in pairs(survivorsFolder:GetChildren()) do
                    local hrp = v:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        if not hitboxVisuals[hrp] then
                            local visual = Instance.new("Part")
                            visual.Name = "HitboxVisual"
                            visual.Anchored = true
                            visual.CanCollide = false
                            visual.Material = Enum.Material.ForceField
                            visual.Color = Color3.new(1, 0, 0)
                            visual.Transparency = 0.7
                            visual.Parent = workspace.CurrentCamera
                            hitboxVisuals[hrp] = visual
                        end
                        local visual = hitboxVisuals[hrp]
                        visual.Size = Vector3.new(Options.HitboxExpanderRange, Options.HitboxExpanderRange, Options.HitboxExpanderRange)
                        visual.CFrame = hrp.CFrame
                    end
                end
            end)
        else
            for hrp, visual in pairs(hitboxVisuals) do
                pcall(function()
                    if visual then visual:Destroy() end
                end)
            end
            hitboxVisuals = {}
        end
    end
end)

local aimbotHeld = false
UserInputService.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton2 then
        aimbotHeld = true
    end
end)
UserInputService.InputEnded:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton2 then
        aimbotHeld = false
    end
end)

task.spawn(function()
    while task.wait() do
        if Toggles.Aimbot and aimbotHeld then
            pcall(function()
                local cam = workspace.CurrentCamera
                if isKiller then
                    local mouse = lplr:GetMouse()
                    local x, y = mouse.X, mouse.Y
                    local v = getClosestSurvivorToMouse(x, y)
                    if v then
                        local root = v.HumanoidRootPart
                        local prediction = Toggles.AimbotPrediction and (v.HumanoidRootPart.Velocity * (10 / Options.PredictionLevel)) or Vector3.zero
                        cam.CFrame = CFrame.new(cam.CFrame.Position, root.Position + prediction)
                    end
                elseif isSurvivor then
                    if killerModel and ({cam:WorldToViewportPoint(killerModel.HumanoidRootPart.Position)})[2] then
                        local prediction = Toggles.AimbotPrediction and (killerModel.HumanoidRootPart.Velocity * (10 / Options.PredictionLevel)) or Vector3.zero
                        cam.CFrame = CFrame.new(cam.CFrame.Position, killerModel.HumanoidRootPart.Position + prediction)
                    end
                end
            end)
        end
    end
end)

pcall(function()
    local isDusekkar = false
    local isCoolkid = false
    local old2
    old2 = hookmetamethod(game, "__namecall", function(self, ...)
        local args = {...}
        if typeof(self) == "Instance" and tostring(self) == "RemoteEvent" then
            if args[2] == "PlasmaBeam" then
                isDusekkar = true
                task.spawn(function()
                    task.wait(3)
                    isDusekkar = false
                end)
            elseif args[2] == "CorruptNature" then
                isCoolkid = true
                task.spawn(function()
                    task.wait(3)
                    isCoolkid = false
                end)
            end
        end
        return old2(self, ...)
    end)

    local success, mouseModule = pcall(function()
        return require(ReplicatedStorage.Systems.Player.Miscellaneous.GetPlayerMousePosition)
    end)
    if not success or not mouseModule then return end
    local gmp = mouseModule.GetMousePos
    if not gmp then return end
    local oldGmp
    oldGmp = hookfunction(gmp, newcclosure(function()
        if isDusekkar and killerModel and Toggles.DusekkarSilentAim then
            return killerModel.HumanoidRootPart.Position
        end
        if isCoolkid and getClosestSurvivor() and Toggles.CoolkidSilentAim then
            return getClosestSurvivor().HumanoidRootPart.Position
        end
        return oldGmp()
    end))
end)

local function assist(target, dist)
    if target and dist <= 25 then
        local pos = lplr.Character.HumanoidRootPart.Position
        local targetPos = target.HumanoidRootPart.Position
        lplr.Character.HumanoidRootPart.CFrame = CFrame.new(Vector3.new(pos.X, pos.Y, pos.Z), Vector3.new(targetPos.X, pos.Y, targetPos.Z))
    end
end

task.spawn(function()
    while task.wait() do
        if Toggles.KillerAimAssist and isKiller then
            pcall(function()
                local target, dist = getClosestSurvivor()
                assist(target, dist)
            end)
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if Toggles.SurvivorAimAssist and isSurvivor and killerModel then
            pcall(function()
                local dist = (lplr.Character.HumanoidRootPart.Position - killerModel.HumanoidRootPart.Position).magnitude
                assist(killerModel, dist)
            end)
        end
    end
end)

local noliByUsername = {}

local function clearFakeTags()
    for _, killer in ipairs(killersFolder:GetChildren()) do
        if killer:GetAttribute("ActorDisplayName") == "Noli" then
            killer:SetAttribute("IsFakeNoli", false)
        end
    end
end

local function scanNolis()
    noliByUsername = {}

    for _, killer in ipairs(killersFolder:GetChildren()) do
        if killer:GetAttribute("ActorDisplayName") == "Noli" then
            local username = killer:GetAttribute("Username")
            if username then
                if not noliByUsername[username] then
                    noliByUsername[username] = {}
                end
                table.insert(noliByUsername[username], killer)
            end
        end
    end

    for username, models in pairs(noliByUsername) do
        if #models > 1 then
            for i = 2, #models do
                models[i]:SetAttribute("IsFakeNoli", true)
            end
            models[1]:SetAttribute("IsFakeNoli", false)
        else
            models[1]:SetAttribute("IsFakeNoli", false)
        end
    end
end

local function updateFakeNolis()
    clearFakeTags()
    scanNolis()
end

local function attachESP(model, color, isKiller)
    pcall(function()
        if not model:IsA("Model") then return end
        if not model:FindFirstChildOfClass("Humanoid") then return end

        if not model:FindFirstChild("ESP_Highlight") then
            local highlight = Instance.new("Highlight")
            highlight.Name = "ESP_Highlight"
            highlight.FillTransparency = 0.8
            highlight.FillColor = color
            highlight.OutlineTransparency = 0
            highlight.OutlineColor = color
            highlight.Adornee = model
            highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            highlight.Parent = model
        end

        local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart") or model:FindFirstChildWhichIsA("BasePart")
        if head and not model:FindFirstChild("ESP_Billboard") then
            local billboard = Instance.new("BillboardGui")
            billboard.Name = "ESP_Billboard"
            billboard.Adornee = head
            billboard.StudsOffset = Vector3.new(0, 3, 0)
            billboard.AlwaysOnTop = true
            billboard.Size = UDim2.new(0, 200, 0, 50)
            billboard.Parent = model

            local label = Instance.new("TextLabel")
            label.Name = "NameLabel"
            label.Size = UDim2.new(1, 0, 1, 0)
            label.BackgroundTransparency = 1
            label.TextColor3 = color
            label.TextStrokeTransparency = 0
            label.TextStrokeColor3 = Color3.new(0, 0, 0)
            label.TextSize = 14
            label.Font = Enum.Font.GothamBold
            label.Parent = billboard
        end

        local billboard = model:FindFirstChild("ESP_Billboard")
        if billboard then
            local label = billboard:FindFirstChild("NameLabel")
            if label then
                local actorText = model:GetAttribute("ActorDisplayName") or "???"

                if actorText == "Noli" and model:GetAttribute("IsFakeNoli") == true then
                    actorText = actorText .. " (FAKE)"
                    label.TextColor3 = Color3.fromRGB(255, 100, 100)
                end

                local humanoid = model:FindFirstChildOfClass("Humanoid")
                if humanoid then
                    local hp = math.floor(humanoid.Health)
                    local maxhp = math.floor(humanoid.MaxHealth)
                    label.Text = string.format("%s [%d/%d]", actorText, hp, maxhp)
                else
                    label.Text = actorText
                end
            end
        end
    end)
end

local function setupESP(folder, isKiller)
    pcall(function()
        for _, model in ipairs(folder:GetChildren()) do
            local color = isKiller and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(255, 255, 0)
            attachESP(model, color, isKiller)
        end
    end)
end

local function updateESPVisibility()
    pcall(function()
        for _, model in ipairs(killersFolder:GetChildren()) do
            local hl = model:FindFirstChild("ESP_Highlight")
            local bb = model:FindFirstChild("ESP_Billboard")
            if hl then hl.Enabled = Toggles.KillerESP end
            if bb then bb.Enabled = Toggles.KillerESP end
        end

        for _, model in ipairs(survivorsFolder:GetChildren()) do
            local hl = model:FindFirstChild("ESP_Highlight")
            local bb = model:FindFirstChild("ESP_Billboard")
            if hl then hl.Enabled = Toggles.SurvivorESP end
            if bb then bb.Enabled = Toggles.SurvivorESP end
        end
    end)
end

task.spawn(function()
    while true do
        pcall(function()
            setupESP(killersFolder, true)
            setupESP(survivorsFolder, false)
            updateESPVisibility()
            updateFakeNolis()
        end)
        task.wait(1)
    end
end)

killersFolder.ChildAdded:Connect(function(child)
    task.wait(0.3)
    pcall(function()
        attachESP(child, Color3.fromRGB(255, 0, 0), true)
        updateFakeNolis()
    end)
end)

survivorsFolder.ChildAdded:Connect(function(child)
    task.wait(0.3)
    pcall(function()
        attachESP(child, Color3.fromRGB(255, 255, 0), false)
    end)
end)

killersFolder.ChildRemoved:Connect(function(removed)
    pcall(function()
        if removed:GetAttribute("ActorDisplayName") == "Noli" then
            updateFakeNolis()
        end
    end)
end)

task.spawn(function()
    while task.wait() do
        if Toggles.GeneratorESP then
            pcall(function()
                if workspace:FindFirstChild("Map") and getGameMap():FindFirstChild("Ingame") and getGameMap().Ingame:FindFirstChild("Map") then
                    for _, v in pairs(getGameMap().Ingame.Map:GetChildren()) do
                        if v.Name == "Generator" then
                            if not v:FindFirstChild("gen_esp") then
                                local hl = Instance.new("Highlight", v)
                                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                                hl.Name = "gen_esp"
                                hl.FillColor = Color3.fromRGB(255, 255, 51)
                                hl.FillTransparency = 0.5
                            else
                                if v:FindFirstChild("Progress") and v.Progress.Value >= 100 then
                                    v.gen_esp.FillColor = Color3.fromRGB(0, 255, 0)
                                else
                                    v.gen_esp.FillColor = Color3.fromRGB(255, 255, 51)
                                end
                            end
                        end
                    end
                end
            end)
        else
            pcall(function()
                if workspace:FindFirstChild("Map") and getGameMap():FindFirstChild("Ingame") and getGameMap().Ingame:FindFirstChild("Map") then
                    for _, v in pairs(getGameMap().Ingame.Map:GetChildren()) do
                        if v.Name == "Generator" and v:FindFirstChild("gen_esp") then
                            v.gen_esp:Destroy()
                        end
                    end
                end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if Toggles.GeneratorNametags then
            pcall(function()
                if workspace:FindFirstChild("Map") and getGameMap():FindFirstChild("Ingame") and getGameMap().Ingame:FindFirstChild("Map") then
                    for _, v in pairs(getGameMap().Ingame.Map:GetChildren()) do
                        if v.Name == "Generator" then
                            if not v:FindFirstChild("gen_nametag") then
                                local bb = Instance.new("BillboardGui", v)
                                bb.Size = UDim2.new(4, 0, 1, 0)
                                bb.AlwaysOnTop = true
                                bb.Name = "gen_nametag"
                                local text = Instance.new("TextLabel", bb)
                                text.TextStrokeTransparency = 0
                                text.Text = "Generator (0%)"
                                text.TextSize = 15
                                text.BackgroundTransparency = 1
                                text.Size = UDim2.new(1, 0, 1, 0)
                                text.TextColor3 = Color3.fromRGB(255, 255, 255)
                            else
                                if v:FindFirstChild("Progress") then
                                    v.gen_nametag.TextLabel.Text = "Generator (" .. v.Progress.Value .. "%)"
                                end
                            end
                        end
                    end
                end
            end)
        else
            pcall(function()
                if workspace:FindFirstChild("Map") and getGameMap():FindFirstChild("Ingame") and getGameMap().Ingame:FindFirstChild("Map") then
                    for _, v in pairs(getGameMap().Ingame.Map:GetChildren()) do
                        if v.Name == "Generator" and v:FindFirstChild("gen_nametag") then
                            v.gen_nametag:Destroy()
                        end
                    end
                end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if Toggles.ItemESP then
            pcall(function()
                if workspace:FindFirstChild("Map") and getGameMap():FindFirstChild("Ingame") then
                    for _, v in pairs(getGameMap().Ingame:GetChildren()) do
                        if v:IsA("Tool") and not v:FindFirstChild("tool_esp") then
                            local hl = Instance.new("Highlight", v)
                            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            hl.Name = "tool_esp"
                            hl.FillColor = Color3.fromRGB(0, 255, 255)
                            hl.FillTransparency = 0.5
                        end
                    end
                    if getGameMap().Ingame:FindFirstChild("Map") then
                        for _, v in pairs(getGameMap().Ingame.Map:GetChildren()) do
                            if v:IsA("Tool") and not v:FindFirstChild("tool_esp") then
                                local hl = Instance.new("Highlight", v)
                                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                                hl.Name = "tool_esp"
                                hl.FillColor = Color3.fromRGB(0, 255, 255)
                                hl.FillTransparency = 0.5
                            end
                        end
                    end
                end
            end)
        else
            pcall(function()
                if workspace:FindFirstChild("Map") and getGameMap():FindFirstChild("Ingame") then
                    for _, v in pairs(getGameMap().Ingame:GetChildren()) do
                        if v:IsA("Tool") and v:FindFirstChild("tool_esp") then
                            v.tool_esp:Destroy()
                        end
                    end
                    if getGameMap().Ingame:FindFirstChild("Map") then
                        for _, v in pairs(getGameMap().Ingame.Map:GetChildren()) do
                            if v:IsA("Tool") and v:FindFirstChild("tool_esp") then
                                v.tool_esp:Destroy()
                            end
                        end
                    end
                end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if Toggles.ItemNametags then
            pcall(function()
                if workspace:FindFirstChild("Map") and getGameMap():FindFirstChild("Ingame") then
                    for _, v in pairs(getGameMap().Ingame:GetChildren()) do
                        if v:IsA("Tool") and not v:FindFirstChild("tool_nametag") then
                            local bb = Instance.new("BillboardGui", v)
                            bb.Size = UDim2.new(4, 0, 1, 0)
                            bb.AlwaysOnTop = true
                            bb.Name = "tool_nametag"
                            local text = Instance.new("TextLabel", bb)
                            text.TextStrokeTransparency = 0
                            text.Text = (v.Name == "BloxyCola" and "Bloxy Cola") or v.Name
                            text.TextSize = 15
                            text.BackgroundTransparency = 1
                            text.Size = UDim2.new(1, 0, 1, 0)
                            text.TextColor3 = Color3.fromRGB(255, 255, 255)
                        end
                    end
                    if getGameMap().Ingame:FindFirstChild("Map") then
                        for _, v in pairs(getGameMap().Ingame.Map:GetChildren()) do
                            if v:IsA("Tool") and not v:FindFirstChild("tool_nametag") then
                                local bb = Instance.new("BillboardGui", v)
                                bb.Size = UDim2.new(4, 0, 1, 0)
                                bb.AlwaysOnTop = true
                                bb.Name = "tool_nametag"
                                local text = Instance.new("TextLabel", bb)
                                text.TextStrokeTransparency = 0
                                text.Text = (v.Name == "BloxyCola" and "Bloxy Cola") or v.Name
                                text.TextSize = 15
                                text.BackgroundTransparency = 1
                                text.Size = UDim2.new(1, 0, 1, 0)
                                text.TextColor3 = Color3.fromRGB(255, 255, 255)
                            end
                        end
                    end
                end
            end)
        else
            pcall(function()
                if workspace:FindFirstChild("Map") and getGameMap():FindFirstChild("Ingame") then
                    for _, v in pairs(getGameMap().Ingame:GetChildren()) do
                        if v:IsA("Tool") and v:FindFirstChild("tool_nametag") then
                            v.tool_nametag:Destroy()
                        end
                    end
                    if getGameMap().Ingame:FindFirstChild("Map") then
                        for _, v in pairs(getGameMap().Ingame.Map:GetChildren()) do
                            if v:IsA("Tool") and v:FindFirstChild("tool_nametag") then
                                v.tool_nametag:Destroy()
                            end
                        end
                    end
                end
            end)
        end
    end
end)

task.spawn(function()
    while task.wait() do
        if Toggles.ZombieESP and not isKiller then
            pcall(function()
                if getGameMap().Ingame:FindFirstChild("Map") then
                    for _, v in pairs(getGameMap().Ingame:GetChildren()) do
                        if v.Name == "1x1x1x1Zombie" then
                            if not v:FindFirstChild("zombie_esp") then
                                local hl = Instance.new("Highlight", v)
                                hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                                hl.Name = "zombie_esp"
                                hl.FillColor = Color3.fromRGB(255, 0, 0)
                                hl.FillTransparency = 0.5
                            end
                        end
                    end
                end
            end)
        else
            pcall(function()
                if getGameMap().Ingame:FindFirstChild("Map") then
                    for _, v in pairs(getGameMap().Ingame:GetChildren()) do
                        if v:FindFirstChild("zombie_esp") then
                            v.zombie_esp:Destroy()
                        end
                    end
                end
            end)
        end
    end
end)

local ingame = workspace:WaitForChild("Map"):WaitForChild("Ingame")

local dispenserPartNames = { "SprayCan", "UpperHolder", "Root" }
local dispenserESPColor = Color3.fromRGB(0, 162, 255)
local sentryESPColor = Color3.fromRGB(128, 128, 128)
local tripwirePartNames = { "Hook1", "Hook2", "Wire" }
local tripwireESPColor = Color3.fromRGB(255, 85, 0)
local subspaceESPColor = Color3.fromRGB(160, 32, 240)
local trapESPTransparency = 0.5

local function isDispenser(model)
    return model:IsA("Model") and model.Name:lower():find("dispenser")
end

local function isSentry(model)
    return model:IsA("Model") and model.Name:lower():find("sentry")
end

local function isTripwire(model)
    return model:IsA("Model") and model.Name:lower():find("tripwire")
end

local function isSubspace(model)
    return model:IsA("Model") and (model.Name:lower():find("subspace") or model.Name:lower():find("tripmine"))
end

local function createTrapHighlight(part, color)
    if not part:FindFirstChild("TrapHighlightESP") then
        local highlight = Instance.new("Highlight")
        highlight.Name = "TrapHighlightESP"
        highlight.FillColor = color
        highlight.FillTransparency = trapESPTransparency
        highlight.OutlineColor = color
        highlight.OutlineTransparency = 0
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.Adornee = part
        highlight.Parent = part
    end
end

local function createTrapBillboard(part, text, color)
    if not part:FindFirstChild("TrapBillboardESP") then
        local billboard = Instance.new("BillboardGui")
        billboard.Name = "TrapBillboardESP"
        billboard.Size = UDim2.new(0, 100, 0, 40)
        billboard.Adornee = part
        billboard.AlwaysOnTop = true
        billboard.StudsOffset = Vector3.new(0, 2, 0)
        billboard.Parent = part

        local label = Instance.new("TextLabel")
        label.Name = "TrapLabel"
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.Text = text
        label.TextColor3 = color
        label.TextStrokeTransparency = 0
        label.TextStrokeColor3 = Color3.new(0, 0, 0)
        label.TextSize = 12
        label.Font = Enum.Font.GothamBold
        label.Parent = billboard
    end
end

local function removeTrapESP(part)
    local hl = part:FindFirstChild("TrapHighlightESP")
    local bb = part:FindFirstChild("TrapBillboardESP")
    if hl then hl:Destroy() end
    if bb then bb:Destroy() end
end

local function disableDispenserESP()
    pcall(function()
        for _, model in pairs(ingame:GetDescendants()) do
            if isDispenser(model) or (model:IsA("BasePart") and model.Parent and isDispenser(model.Parent)) then
                removeTrapESP(model)
            end
        end
    end)
end

local function disableSentryESP()
    pcall(function()
        for _, model in pairs(ingame:GetDescendants()) do
            if isSentry(model) or (model:IsA("BasePart") and model.Parent and isSentry(model.Parent)) then
                removeTrapESP(model)
            end
        end
    end)
end

local function disableTripwireESP()
    pcall(function()
        for _, model in pairs(ingame:GetDescendants()) do
            if isTripwire(model) or (model:IsA("BasePart") and model.Parent and isTripwire(model.Parent)) then
                removeTrapESP(model)
            end
        end
    end)
end

local function disableSubspaceESP()
    pcall(function()
        for _, model in pairs(ingame:GetDescendants()) do
            if isSubspace(model) or (model:IsA("BasePart") and model.Parent and isSubspace(model.Parent)) then
                removeTrapESP(model)
            end
        end
    end)
end

task.spawn(function()
    while true do
        pcall(function()
            if Toggles.DispenserESP then
                for _, model in pairs(ingame:GetDescendants()) do
                    if model:IsA("Model") and isDispenser(model) then
                        for _, part in pairs(model:GetChildren()) do
                            if part:IsA("BasePart") and table.find(dispenserPartNames, part.Name) then
                                createTrapHighlight(part, dispenserESPColor)
                            end
                        end
                        local root = model:FindFirstChild("Root")
                        if root then
                            createTrapBillboard(root, "DISPENSER", dispenserESPColor)
                        end
                    end
                end
            end

            if Toggles.SentryESP then
                for _, model in pairs(ingame:GetDescendants()) do
                    if model:IsA("Model") and isSentry(model) then
                        for _, part in pairs(model:GetDescendants()) do
                            if part:IsA("BasePart") then
                                createTrapHighlight(part, sentryESPColor)
                            end
                        end
                        local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                        if primaryPart then
                            createTrapBillboard(primaryPart, "SENTRY", sentryESPColor)
                        end
                    end
                end
            end

            if Toggles.TripwireESP then
                for _, model in pairs(ingame:GetDescendants()) do
                    if model:IsA("Model") and isTripwire(model) then
                        for _, part in pairs(model:GetChildren()) do
                            if part:IsA("BasePart") and table.find(tripwirePartNames, part.Name) then
                                createTrapHighlight(part, tripwireESPColor)
                            end
                        end
                        local wire = model:FindFirstChild("Wire")
                        if wire then
                            createTrapBillboard(wire, "TRIPWIRE", tripwireESPColor)
                        end
                    end
                end
            end

            if Toggles.SubspaceESP then
                for _, model in pairs(ingame:GetDescendants()) do
                    if model:IsA("Model") and isSubspace(model) then
                        for _, part in pairs(model:GetDescendants()) do
                            if part:IsA("BasePart") then
                                createTrapHighlight(part, subspaceESPColor)
                            end
                        end
                        local primaryPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
                        if primaryPart then
                            createTrapBillboard(primaryPart, "SUBSPACE MINE", subspaceESPColor)
                        end
                    end
                end
            end
        end)
        task.wait(0.5)
    end
end)

local function unlockAchievement(name)
    pcall(function()
        network.RemoteEvent:FireServer("UnlockAchievement", name)
        Notify("Achievement", "Unlocked: " .. name, 5)
    end)
end

local function completeActiveGenerator()
    if activelyAutoing then return end
    pcall(function()
        if not (getGameMap() and getGameMap().Ingame and getGameMap().Ingame.Map) then return end
        for _, v in pairs(getGameMap().Ingame.Map:GetChildren()) do
            if v.Name == "Generator" then
                pcall(function()
                    if lplr.PlayerGui:FindFirstChild("PuzzleUI") then
                        local hello = v.Positions.Center.Position
                        if (lplr.Character.HumanoidRootPart.Position - hello).Magnitude <= 21 then
                            for i = 1, 4 do
                                if v.Progress.Value >= 100 then break end
                                if activelyAutoing then return end
                                if not lplr.PlayerGui:FindFirstChild("PuzzleUI") then break end
                                Notify("Generator", "Finished puzzle " .. i, 4)
                                v.Remotes.RE:FireServer()
                                generatorWait()
                            end
                        end
                    end
                end)
            end
        end
    end)
end

local function completeAllGenerators()
    if playingState == "Spectating" then
        return Notify("Error", "Cannot use while spectating", 7)
    end
    if activelyAutoing then return end
    pcall(function()
        if not (getGameMap() and getGameMap().Ingame and getGameMap().Ingame.Map) then return end
        for _, v in pairs(getGameMap().Ingame.Map:GetChildren()) do
            if v.Name == "Generator" then
                pcall(function()
                    if v.Progress.Value >= 100 then return end
                    local function checkOccupance(pos)
                        if not (workspace:FindFirstChild("Players") and workspace.Players:FindFirstChild("Survivors")) then return false end
                        for _, sv in pairs(survivorsFolder:GetChildren()) do
                            if sv:FindFirstChild("HumanoidRootPart") then
                                if sv:GetAttribute("Username") ~= lplr.Name then
                                    if (sv.HumanoidRootPart.Position - pos).Magnitude <= 6 then
                                        return true
                                    end
                                end
                            end
                        end
                        return false
                    end
                    local centerOccupied = checkOccupance(v.Positions.Center.Position)
                    local rightOccupied = checkOccupance(v.Positions.Right.Position)
                    local leftOccupied = checkOccupance(v.Positions.Left.Position)
                    if centerOccupied and rightOccupied and leftOccupied then return end
                    if not centerOccupied then
                        lplr.Character.HumanoidRootPart.CFrame = v.Positions.Center.CFrame
                    elseif not rightOccupied then
                        lplr.Character.HumanoidRootPart.CFrame = v.Positions.Right.CFrame
                    else
                        lplr.Character.HumanoidRootPart.CFrame = v.Positions.Left.CFrame
                    end
                    task.wait(0.2)
                    local result = v.Remotes.RF:InvokeServer("enter")
                    if result ~= "fixing" then return end
                    for j = 1, 4 do
                        if v.Progress.Value >= 100 then break end
                        if activelyAutoing then return end
                        Notify("Generator", "Finished puzzle " .. j, 4)
                        v.Remotes.RE:FireServer()
                        generatorWait()
                    end
                end)
            end
        end
    end)
end

local function pickUpAllItems()
    pcall(function()
        if isKiller then return end
        local items = {}
        if workspace:FindFirstChild("Map") and getGameMap():FindFirstChild("Ingame") then
            for _, v in pairs(getGameMap().Ingame:GetDescendants()) do
                if v:IsA("Tool") and v:FindFirstChild("ItemRoot") then
                    table.insert(items, v.ItemRoot)
                end
            end
        end
        for _, itemRoot in pairs(items) do
            local toolName = itemRoot.Parent and itemRoot.Parent.Name
            if toolName and not lplr.Backpack:FindFirstChild(toolName) then
                lplr.Character.HumanoidRootPart.CFrame = itemRoot.CFrame
                task.wait(0.5)
                if itemRoot:FindFirstChild("ProximityPrompt") then
                    fireproximityprompt(itemRoot.ProximityPrompt)
                end
            end
        end
    end)
end

local Purple = Color3.fromHex("#7775F2")
local Yellow = Color3.fromHex("#ECA201")
local Green = Color3.fromHex("#10C550")
local Grey = Color3.fromHex("#83889E")
local Blue = Color3.fromHex("#257AF7")
local Red = Color3.fromHex("#EF4F1D")
local Cyan = Color3.fromHex("#00D9FF")
local Orange = Color3.fromHex("#FF8C00")
local Pink = Color3.fromHex("#FF69B4")

local Window = WindUI:CreateWindow({
    Title = "Zlex Hub  |  Forsaken",
    Icon = "shield",
    Author = "by Zlex",
    Folder = "ZlexHub",
    Size = UDim2.fromOffset(620, 500),
    Transparent = true,
    Theme = "Dark",
    SideBarWidth = 200,
    HasOutline = false,
    NewElements = true,

    OpenButton = {
        Title = "Open Zlex Hub",
        CornerRadius = UDim.new(1, 0),
        StrokeThickness = 3,
        Enabled = true,
        Draggable = true,
        OnlyMobile = false,
        Color = ColorSequence.new(
            Color3.fromHex("#7775F2"),
            Color3.fromHex("#00D9FF")
        )
    },
    Topbar = {
        Height = 44,
        ButtonsType = "Default",
    },
})

Window:Tag({
    Title = "v3.0",
    Icon = "github",
    Color = Color3.fromHex("#7775F2")
})

local Sections = {
    Discord = Window:Section({ Title = "Discord" }),
    Main = Window:Section({ Title = "Main" }),
    AutoFarm = Window:Section({ Title = "Auto Farm" }),
    Combat = Window:Section({ Title = "Combat" }),
    Visuals = Window:Section({ Title = "Visuals" }),
    Misc = Window:Section({ Title = "Misc" })
}

local Tabs = {}

do -- Discord Tab scope
    Tabs.Discord = Sections.Discord:Tab({ Title = "Join Discord", Icon = "message-circle", IconColor = Purple, IconShape = "Square" })
    local DiscordBox = Tabs.Discord:Section({ Title = "Zlex Hub Discord", TextSize = 18, Box = true, Opened = true })
    DiscordBox:Button({ Title = "Copy Discord Invite", Desc = "https://discord.gg/vPRrvznq3y", Icon = "copy", Color = Purple, Justify = "Center",
        Callback = function() setclipboard("https://discord.gg/vPRrvznq3y") Notify("Discord", "Invite link copied to clipboard!", 3) end })
    DiscordBox:Button({ Title = "Join Our Server", Desc = "Get updates, support, and new scripts!", Icon = "users", Color = Blue, Justify = "Center",
        Callback = function() setclipboard("https://discord.gg/vPRrvznq3y") Notify("Discord", "Link copied! Paste in browser to join.", 5) end })
end

Tabs.Survivor = Sections.Main:Tab({ Title = "Survivor", Icon = "user", IconColor = Green, IconShape = "Square" })
Tabs.Killer = Sections.Main:Tab({ Title = "Killer", Icon = "skull", IconColor = Red, IconShape = "Square" })
Tabs.Movement = Sections.Main:Tab({ Title = "Movement", Icon = "zap", IconColor = Yellow, IconShape = "Square" })
Tabs.AutoFarm = Sections.AutoFarm:Tab({ Title = "Auto Farm", Icon = "bot", IconColor = Green, IconShape = "Square" })
Tabs.ESP = Sections.Visuals:Tab({ Title = "ESP", Icon = "eye", IconColor = Cyan, IconShape = "Square" })
Tabs.Teleport = Sections.Visuals:Tab({ Title = "Teleport", Icon = "map-pin", IconColor = Blue, IconShape = "Square" })
Tabs.Aimbot = Sections.Combat:Tab({ Title = "Aimbot", Icon = "crosshair", IconColor = Orange, IconShape = "Square" })
Tabs.Achievements = Sections.Misc:Tab({ Title = "Achievements", Icon = "trophy", IconColor = Yellow, IconShape = "Square" })
Tabs.Settings = Sections.Misc:Tab({ Title = "Settings", Icon = "settings", IconColor = Grey, IconShape = "Square" })

local SurvivorTab, KillerTab, MovementTab, AutoFarmTab, ESPTab, TeleportTab, AimbotTab, AchievementsTab, SettingsTab = 
    Tabs.Survivor, Tabs.Killer, Tabs.Movement, Tabs.AutoFarm, Tabs.ESP, Tabs.Teleport, Tabs.Aimbot, Tabs.Achievements, Tabs.Settings

do -- Generator Farm Revamped scope
local GeneratorFarmBox = AutoFarmTab:Section({
    Title = "Generator Farm (Revamped)",
    TextSize = 18,
    Box = true,
    Opened = true,
})

GeneratorFarmBox:Toggle({
    Title = "Enable Auto Generator",
    Desc = "Revamped auto generator with bypass cooldown",
    Value = false,
    Callback = function(state)
        RevampedFarm.Config.GeneratorEnabled = state
        Toggles.AutoGenerator = state
        if state then RevampedFarm:Start() end
        Notify("Auto Generator", state and "Enabled (Revamped)" or "Disabled", 3)
    end
})

GeneratorFarmBox:Toggle({
    Title = "Bypass Cooldown",
    Desc = "Leave and re-enter generator to speed up farming",
    Value = true,
    Callback = function(state)
        RevampedFarm.Config.GeneratorBypassCooldown = state
        Notify("Bypass Cooldown", state and "Enabled" or "Disabled", 3)
    end
})

GeneratorFarmBox:Toggle({
    Title = "Teleport To Generator",
    Desc = "Teleport to nearest incomplete generator",
    Value = false,
    Callback = function(state)
        RevampedFarm.Config.TeleportToGenerator = state
        Notify("Teleport To Generator", state and "Enabled" or "Disabled", 3)
    end
})

GeneratorFarmBox:Toggle({
    Title = "Return After Complete",
    Desc = "Return to original position after generator complete",
    Value = true,
    Callback = function(state)
        RevampedFarm.Config.ReturnAfterComplete = state
        Notify("Return After Complete", state and "Enabled" or "Disabled", 3)
    end
})

GeneratorFarmBox:Slider({
    Title = "Generator Interval",
    Value = { Min = 0.5, Max = 5, Default = RevampedFarm.Config.GeneratorInterval },
    Callback = function(value)
        RevampedFarm.Config.GeneratorInterval = value
        Options.GeneratorDelay = value
    end
})

GeneratorFarmBox:Space()

local KillerAvoidBox = AutoFarmTab:Section({
    Title = "Killer Avoidance (Revamped)",
    TextSize = 18,
    Box = true,
    Opened = true,
})

KillerAvoidBox:Toggle({
    Title = "Auto Survive (Avoid Killers)",
    Desc = "Automatically teleport away from killers",
    Value = false,
    Callback = function(state)
        RevampedFarm.Config.AutoSurviveEnabled = state
        RevampedFarm.Config.AvoidKillers = state
        if state and not RevampedFarm.State.isRunning then RevampedFarm:Start() end
        Notify("Auto Survive", state and "Enabled" or "Disabled", 3)
    end
})

KillerAvoidBox:Slider({
    Title = "Killer Detection Range",
    Value = { Min = 10, Max = 50, Default = RevampedFarm.Config.KillerDetectRadius },
    Callback = function(value)
        RevampedFarm.Config.KillerDetectRadius = value
    end
})

KillerAvoidBox:Slider({
    Title = "Safe Distance",
    Value = { Min = 20, Max = 100, Default = RevampedFarm.Config.SafeDistance },
    Callback = function(value)
        RevampedFarm.Config.SafeDistance = value
    end
})

KillerAvoidBox:Space()

local AutoWinGenBox = AutoFarmTab:Section({
    Title = "Auto Win Generators (Revamped)",
    TextSize = 18,
    Box = true,
    Opened = true,
})

AutoWinGenBox:Toggle({
    Title = "Auto Complete All Generators",
    Desc = "Teleport to and complete all generators",
    Value = false,
    Callback = function(state)
        RevampedFarm.Config.AutoWinEnabled = state
        if state and not RevampedFarm.State.isRunning then RevampedFarm:Start() end
        Notify("Auto Win (Generators)", state and "Enabled" or "Disabled", 3)
    end
})

AutoWinGenBox:Button({
    Title = "Stop All Auto Features",
    Icon = "square",
    Color = Color3.fromRGB(255, 100, 100),
    Justify = "Center",
    Callback = function()
        RevampedFarm.Config.GeneratorEnabled = false
        RevampedFarm.Config.AutoSurviveEnabled = false
        RevampedFarm.Config.AutoWinEnabled = false
        RevampedFarm:Stop()
        Notify("Auto Farm", "All features stopped", 3)
    end
})

AutoWinGenBox:Button({
    Title = "Teleport To Nearest Generator",
    Icon = "navigation",
    Color = Color3.fromRGB(100, 200, 255),
    Justify = "Center",
    Callback = function()
        local gen = RevampedFarm:GetNearestGen(true)
        if gen then
            RevampedFarm:SafeTP(gen.position + Vector3.new(0, 2, 0))
            Notify("Teleport", "Teleported to nearest generator", 3)
        else
            Notify("Teleport", "No incomplete generators found", 3)
        end
    end
})
end -- End Generator Farm Revamped scope

do -- Item Farm scope
local ItemFarmBox = AutoFarmTab:Section({ Title = "Item Farm", TextSize = 18, Box = true, Opened = true })
ItemFarmBox:Toggle({ Title = "Auto Pick Up Items", Desc = "Automatically picks up nearby items", Value = false,
    Callback = function(state) Toggles.AutoPickUpItems = state Notify("Auto Pick Up Items", state and "Enabled" or "Disabled", 3) end })
end

do -- Survivor scope
local CombatBox = SurvivorTab:Section({ Title = "Combat", TextSize = 18, Box = true, Opened = true })
CombatBox:Toggle({ Title = "Auto Block", Desc = "Automatically blocks killer attacks", Value = false,
    Callback = function(state) Toggles.AutoBlock = state Notify("Auto Block", state and "Enabled" or "Disabled", 3) end })
CombatBox:Slider({ Title = "Block Delay (ms)", Value = { Min = 0, Max = 300, Default = Options.AutoBlockMS }, Callback = function(value) Options.AutoBlockMS = value end })
CombatBox:Space()
CombatBox:Toggle({ Title = "Auto Coin Flip", Desc = "Automatically uses coin flip ability", Value = false,
    Callback = function(state) Toggles.AutoCoinFlip = state Notify("Auto Coin Flip", state and "Enabled" or "Disabled", 3) end })

local AnimBlockBox = SurvivorTab:Section({ Title = "Animation Auto Block", TextSize = 18, Box = true, Opened = true })
AnimBlockBox:Toggle({ Title = "Auto Block (Animation)", Desc = "Blocks based on killer attack animations", Value = false,
    Callback = function(state) autoBlockAnimationOn = state if state then startAnimationAutoBlock() Notify("Animation Auto Block", "Enabled", 3) else stopAnimationAutoBlock() Notify("Animation Auto Block", "Disabled", 3) end end })
AnimBlockBox:Slider({ Title = "Detection Range", Value = { Min = 5, Max = 50, Default = animBlockDetectionRange }, Callback = function(value) animBlockDetectionRange = value end })
AnimBlockBox:Slider({ Title = "Windup % Threshold", Value = { Min = 10, Max = 100, Default = 75 }, Callback = function(value) animBlockWindupThreshold = value / 100 end })

local DaggerBox = SurvivorTab:Section({ Title = "Dagger", TextSize = 18, Box = true, Opened = true })
DaggerBox:Toggle({ Title = "Auto Dagger", Desc = "Automatically backstabs the killer", Value = false,
    Callback = function(state) Toggles.AutoDagger = state Notify("Auto Dagger", state and "Enabled" or "Disabled", 3) end })
DaggerBox:Toggle({ Title = "Dagger Aura", Desc = "Auto backstab when killer is in range", Value = false,
    Callback = function(state) Toggles.DaggerAura = state Notify("Dagger Aura", state and "Enabled" or "Disabled", 3) end })
DaggerBox:Slider({ Title = "Backstab Range", Value = { Min = 5, Max = 99, Default = Options.BackstabRange }, Callback = function(value) Options.BackstabRange = value end })

local GeneratorBox = SurvivorTab:Section({ Title = "Generator", TextSize = 18, Box = true, Opened = true })
GeneratorBox:Toggle({ Title = "Auto Generator (Safe)", Desc = "Auto completes generators when at one", Value = false,
    Callback = function(state) Toggles.AutoGenerator = state Notify("Auto Generator", state and "Enabled - Walk to a generator!" or "Disabled", 3) end })
GeneratorBox:Toggle({ Title = "Auto Start Generator", Desc = "Auto starts generators when near", Value = false,
    Callback = function(state) Toggles.AutoStartGenerator = state Notify("Auto Start Generator", state and "Enabled" or "Disabled", 3) end })
GeneratorBox:Slider({ Title = "Generator Interval (seconds)", Value = { Min = 1, Max = 5, Default = Options.GeneratorDelay }, Callback = function(value) Options.GeneratorDelay = value end })
GeneratorBox:Space()
local GenButtonGroup = GeneratorBox:Group({})

GenButtonGroup:Button({
    Title = "Complete Active",
    Icon = "play",
    Color = Green,
    Justify = "Center",
    Callback = function()
        completeActiveGenerator()
    end
})

GenButtonGroup:Space()

GenButtonGroup:Button({
    Title = "Complete All",
    Icon = "check-check",
    Color = Blue,
    Justify = "Center",
    Callback = function()
        completeAllGenerators()
    end
})

end -- End survivor scope

do -- Killer and items scope
local ItemsBox = SurvivorTab:Section({ Title = "Items", TextSize = 18, Box = true, Opened = true })
ItemsBox:Toggle({ Title = "Auto Pick Up Items", Desc = "Auto pickup nearby items", Value = false,
    Callback = function(state) Toggles.AutoPickUpItems = state Notify("Auto Pick Up", state and "Enabled" or "Disabled", 3) end })
ItemsBox:Button({ Title = "Pick Up All Items", Icon = "package", Color = Yellow, Justify = "Center",
    Callback = function() pickUpAllItems() Notify("Items", "Picking up all items...", 3) end })

local KillerAttackBox = KillerTab:Section({ Title = "Attack System (Revamped)", TextSize = 18, Box = true, Opened = true })
KillerAttackBox:Toggle({ Title = "Kill All Aura", Desc = "TP to survivors and use all abilities", Value = false,
    Callback = function(state) if state and isSurvivor then RevampedKiller.Config.KillAllEnabled = false Notify("Error", "Must be killer!", 5) return end RevampedKiller.Config.KillAllEnabled = state if state then RevampedKiller:Start() end Notify("Kill All Aura", state and "Enabled" or "Disabled", 3) end })
KillerAttackBox:Toggle({ Title = "Slash Aura", Desc = "Auto attack survivors in range", Value = false,
    Callback = function(state) RevampedKiller.Config.SlashAuraEnabled = state if state then RevampedKiller:Start() end Notify("Slash Aura", state and "Enabled" or "Disabled", 3) end })
KillerAttackBox:Toggle({ Title = "Auto Use Abilities", Desc = "Auto use abilities when survivors near", Value = false,
    Callback = function(state) RevampedKiller.Config.AutoAbilitiesEnabled = state if state then RevampedKiller:Start() end Notify("Auto Abilities", state and "Enabled" or "Disabled", 3) end })
KillerAttackBox:Slider({ Title = "Attack Range", Value = { Min = 5, Max = 50, Default = RevampedKiller.Config.AttackRange }, Callback = function(value) RevampedKiller.Config.AttackRange = value end })
KillerAttackBox:Slider({ Title = "Attack Speed", Value = { Min = 1, Max = 20, Default = 7 }, Callback = function(value) RevampedKiller.Config.AttackInterval = value / 50 end })

local KillerOptionsBox = KillerTab:Section({ Title = "Attack Options", TextSize = 18, Box = true, Opened = true })
KillerOptionsBox:Toggle({ Title = "Teleport To Target", Desc = "TP behind survivors when attacking", Value = true,
    Callback = function(state) RevampedKiller.Config.TeleportToTarget = state Notify("TP To Target", state and "Enabled" or "Disabled", 3) end })
KillerOptionsBox:Toggle({ Title = "Use All Abilities", Desc = "Use Nova, VoidRush, etc.", Value = true,
    Callback = function(state) RevampedKiller.Config.UseAllAbilities = state Notify("All Abilities", state and "Enabled" or "Disabled", 3) end })
KillerOptionsBox:Toggle({ Title = "Prioritize Low HP", Desc = "Target lowest health first", Value = false,
    Callback = function(state) RevampedKiller.Config.PrioritizeLowHP = state Notify("Low HP Priority", state and "Enabled" or "Disabled", 3) end })

local TargetLockBox = KillerTab:Section({ Title = "Target Lock", TextSize = 18, Box = true, Opened = true })
TargetLockBox:Toggle({ Title = "Enable Target Lock", Desc = "Lock onto a specific survivor", Value = false,
    Callback = function(state) RevampedKiller.Config.TargetLockEnabled = state if not state then RevampedKiller:UnlockTarget() end Notify("Target Lock", state and "Enabled" or "Disabled", 3) end })
local TargetLockButtons = TargetLockBox:Group({})
TargetLockButtons:Button({ Title = "Lock Nearest", Icon = "crosshair", Color = Red, Justify = "Center", Callback = function() RevampedKiller:LockTarget() end })
TargetLockButtons:Space()
TargetLockButtons:Button({ Title = "Unlock", Icon = "x", Color = Grey, Justify = "Center", Callback = function() RevampedKiller:UnlockTarget() end })

local KillerControlBox = KillerTab:Section({ Title = "Control", TextSize = 18, Box = true, Opened = true })
KillerControlBox:Button({ Title = "Stop All Killer Features", Icon = "square", Color = Color3.fromRGB(255, 100, 100), Justify = "Center", Callback = function() RevampedKiller:Stop() Notify("Killer", "All stopped", 3) end })

local SpectateBox = KillerTab:Section({ Title = "Spectate", TextSize = 18, Box = true, Opened = true })
SpectateBox:Toggle({ Title = "Spectate Killer", Desc = "View from killer's perspective", Value = false,
    Callback = function(state) Toggles.SpectateKiller = state if state then local killer = killersFolder:GetChildren()[1] if killer then workspace.CurrentCamera.CameraSubject = killer end else pcall(function() workspace.CurrentCamera.CameraSubject = lplr.Character end) end Notify("Spectate Killer", state and "Enabled" or "Disabled", 3) end })

local NoliBox = KillerTab:Section({ Title = "Noli Features", TextSize = 18, Box = true, Opened = true })
NoliBox:Toggle({ Title = "Void Rush Anti Collision", Desc = "Prevent collision during void rush", Value = false,
    Callback = function(state) Toggles.VoidRushCollision = state Notify("VR Anti Collision", state and "Enabled" or "Disabled", 3) end })
NoliBox:Toggle({ Title = "Void Rush Noclip", Desc = "Noclip through walls during void rush", Value = false,
    Callback = function(state) Toggles.VoidRushNoclip = state Notify("VR Noclip", state and "Enabled" or "Disabled", 3) end })

local HitboxBox = KillerTab:Section({ Title = "Hitbox", TextSize = 18, Box = true, Opened = true })
HitboxBox:Toggle({ Title = "Hitbox Expander", Desc = "Expand survivor hitboxes (hookmethod bypass)", Value = false,
    Callback = function(state) Toggles.HitboxExpander = state Notify("Hitbox Expander", state and "Enabled" or "Disabled", 3) end })
HitboxBox:Toggle({ Title = "Show Hitbox Visual", Desc = "Display expanded hitbox area", Value = false,
    Callback = function(state) Toggles.HitboxVisual = state Notify("Hitbox Visual", state and "Enabled" or "Disabled", 3) end })
HitboxBox:Slider({ Title = "Hitbox Size", Value = { Min = 5, Max = 100, Default = Options.HitboxExpanderRange }, Callback = function(value) Options.HitboxExpanderRange = value end })
end

do -- Movement scope

local SpeedBox = MovementTab:Section({
    Title = "Speed",
    TextSize = 18,
    Box = true,
    Opened = true,
})

SpeedBox:Toggle({
    Title = "Infinity Stamina (Enhanced)",
    Desc = "Full stamina control with custom settings",
    Value = false,
    Callback = function(state)
        if state then
            EnableInfinityStamina()
            Notify("Infinity Stamina", "Enabled with custom settings", 3)
        else
            DisableInfinityStamina()
            Notify("Infinity Stamina", "Disabled", 3)
        end
    end
})

SpeedBox:Slider({
    Title = "Max Stamina",
    Value = { Min = 1, Max = 500, Default = defaultMaxStamina },
    Callback = function(value)
        maxStaminaValue = value
        if sprintModule then
            sprintModule.MaxStamina = value
        end
    end
})

SpeedBox:Slider({
    Title = "Stamina Gain",
    Value = { Min = 1, Max = 500, Default = defaultStaminaGain },
    Callback = function(value)
        staminaGainValue = value
        if sprintModule then
            sprintModule.StaminaGain = value
        end
    end
})

SpeedBox:Slider({
    Title = "Stamina Drain",
    Value = { Min = 0, Max = 100, Default = defaultStaminaDrain },
    Callback = function(value)
        staminaDrainValue = value
        if sprintModule then
            sprintModule.StaminaDrain = value
        end
    end
})

SpeedBox:Slider({
    Title = "Regen Delay",
    Value = { Min = 0, Max = 50, Default = 5 },
    Callback = function(value)
        regenDelayValue = value / 10
        if sprintModule then
            sprintModule.StaminaRegenDelay = value / 10
        end
    end
})

SpeedBox:Button({
    Title = "Reset Stamina Settings",
    Icon = "refresh-cw",
    Color = Color3.fromRGB(255, 100, 100),
    Justify = "Center",
    Callback = function()
        ResetStaminaSettings()
        Notify("Stamina", "Reset to default values", 3)
    end
})

SpeedBox:Space()

SpeedBox:Toggle({
    Title = "Always Sprint",
    Desc = "Always be sprinting",
    Value = false,
    Callback = function(state)
        Toggles.AlwaysSprint = state
        Notify("Always Sprint", state and "Enabled" or "Disabled", 3)
    end
})

SpeedBox:Toggle({
    Title = "Fast Sprint",
    Desc = "Sprint faster than normal",
    Value = false,
    Callback = function(state)
        Toggles.FastSprint = state
        Notify("Fast Sprint", state and "Enabled" or "Disabled", 3)
    end
})

SpeedBox:Slider({
    Title = "Sprint Speed",
    Value = { Min = 26, Max = 80, Default = Options.SprintSpeed },
    Callback = function(value)
        Options.SprintSpeed = value
    end
})

SpeedBox:Space()

SpeedBox:Toggle({
    Title = "Speed Boost",
    Desc = "Increases your movement speed",
    Value = false,
    Callback = function(state)
        Toggles.SpeedToggle = state
        Notify("Speed Boost", state and "Enabled" or "Disabled", 3)
    end
})

SpeedBox:Slider({
    Title = "Speed Value",
    Value = { Min = 1, Max = 100, Default = Options.SpeedBypass },
    Callback = function(value)
        Options.SpeedBypass = value
    end
})

local MovementBox = MovementTab:Section({
    Title = "Movement",
    TextSize = 18,
    Box = true,
    Opened = true,
})

MovementBox:Toggle({
    Title = "Noclip",
    Desc = "Walk through walls",
    Value = false,
    Callback = function(state)
        Toggles.Noclip = state
        if not state then
            disableNoclip()
        end
        Notify("Noclip", state and "Enabled" or "Disabled", 3)
    end
})

local FlyBox = MovementTab:Section({
    Title = "Fly",
    TextSize = 18,
    Box = true,
    Opened = true,
})

FlyBox:Toggle({
    Title = "Enable Fly",
    Desc = "Space=Up, Shift=Down, WASD=Move",
    Value = false,
    Callback = function(state)
        Toggles.Fly = state
        Notify("Fly", state and "Enabled" or "Disabled", 3)
    end
})

FlyBox:Slider({
    Title = "Fly Speed",
    Value = { Min = 10, Max = 150, Default = Options.FlySpeed },
    Callback = function(value)
        Options.FlySpeed = value
    end
})

FlyBox:Slider({
    Title = "Fly Vertical Speed",
    Value = { Min = 7, Max = 80, Default = Options.FlyVerticalSpeed },
    Callback = function(value)
        Options.FlyVerticalSpeed = value
    end
})

local SpecialBox = MovementTab:Section({
    Title = "Special",
    TextSize = 18,
    Box = true,
    Opened = true,
})

SpecialBox:Toggle({
    Title = "Invisibility",
    Desc = "Become invisible (Original Forsaken only)",
    Value = false,
    Callback = function(state)
        if game.PlaceId ~= 18687417158 then
            Notify("Error", "Invisibility only works on Original Forsaken!", 5)
            Toggles.Invisibility = false
            return
        end
        Toggles.Invisibility = state
        if state then
            Notify("Warning", "You can still be seen with certain abilities!", 6)
        else
            pcall(function()
                if currentAnim then
                    currentAnim:Stop()
                    currentAnim = nil
                end
                local Humanoid = lplr.Character and lplr.Character:FindFirstChildOfClass("Humanoid")
                if Humanoid then
                    for _, v in pairs(Humanoid:GetPlayingAnimationTracks()) do
                        v:AdjustSpeed(100000)
                    end
                end
                local animateScript = lplr.Character and lplr.Character:FindFirstChild("Animate")
                if animateScript then
                    animateScript.Disabled = true
                    animateScript.Disabled = false
                end
            end)
        end
        Notify("Invisibility", state and "Enabled" or "Disabled", 3)
    end
})

SpecialBox:Toggle({
    Title = "Allow Killer Entrances",
    Desc = "Walk through killer-only entrances",
    Value = false,
    Callback = function(state)
        Toggles.AllowKillerEntrances = state
        Notify("Killer Entrances", state and "Enabled" or "Disabled", 3)
    end
})

do -- Aimbot scope
local AimbotBox = AimbotTab:Section({ Title = "Aimbot", TextSize = 18, Box = true, Opened = true })
AimbotBox:Toggle({ Title = "Aimbot", Desc = "Hold right-click to lock onto target", Value = false,
    Callback = function(state) Toggles.Aimbot = state Notify("Aimbot", state and "Enabled - Hold right click to aim" or "Disabled", 3) end })
AimbotBox:Toggle({ Title = "Prediction", Desc = "Predict target movement", Value = true, Callback = function(state) Toggles.AimbotPrediction = state end })
AimbotBox:Slider({ Title = "Prediction Level", Value = { Min = 25, Max = 100, Default = Options.PredictionLevel }, Callback = function(value) Options.PredictionLevel = value end })

local KillerAimbotBox = AimbotTab:Section({ Title = "Killer Aimbot (Per-Ability)", TextSize = 18, Box = true, Opened = true })
KillerAimbotBox:Toggle({ Title = "Aimbot Slash (Shedletsky)", Desc = "Auto-aim for Slash ability", Value = false,
    Callback = function(state) AimbotConfig.Slash.Enabled = state Notify("Aimbot Slash", state and "Enabled" or "Disabled", 3) end })
KillerAimbotBox:Slider({ Title = "Slash Smoothness", Value = { Min = 0, Max = 100, Default = 100 }, Callback = function(value) AimbotConfig.Slash.Smoothness = value / 100 end })
KillerAimbotBox:Slider({ Title = "Slash Prediction", Value = { Min = 0, Max = 200, Default = 25 }, Callback = function(value) AimbotConfig.Slash.Prediction = value / 100 end })
KillerAimbotBox:Space()
KillerAimbotBox:Toggle({ Title = "Aimbot One Shot (Chance)", Desc = "Auto-aim for One Shot ability", Value = false,
    Callback = function(state) AimbotConfig.Shoot.Enabled = state Notify("Aimbot One Shot", state and "Enabled" or "Disabled", 3) end })
KillerAimbotBox:Slider({ Title = "One Shot Smoothness", Value = { Min = 0, Max = 100, Default = 100 }, Callback = function(value) AimbotConfig.Shoot.Smoothness = value / 100 end })
KillerAimbotBox:Slider({ Title = "One Shot Prediction", Value = { Min = 0, Max = 200, Default = 25 }, Callback = function(value) AimbotConfig.Shoot.Prediction = value / 100 end })
KillerAimbotBox:Space()
KillerAimbotBox:Toggle({ Title = "Aimbot True One Shot", Desc = "Auto-aim for True One Shot ability", Value = false,
    Callback = function(state) AimbotConfig.TrueShoot.Enabled = state Notify("Aimbot True One Shot", state and "Enabled" or "Disabled", 3) end })
KillerAimbotBox:Slider({ Title = "True One Shot Prediction", Value = { Min = 0, Max = 200, Default = 60 }, Callback = function(value) AimbotConfig.TrueShoot.Prediction = value / 100 end })
KillerAimbotBox:Space()
KillerAimbotBox:Toggle({ Title = "Aimbot Punch (Guest 1337)", Desc = "Auto-aim for Punch ability", Value = false,
    Callback = function(state) AimbotConfig.Punch.Enabled = state Notify("Aimbot Punch", state and "Enabled" or "Disabled", 3) end })
KillerAimbotBox:Slider({ Title = "Punch Prediction", Value = { Min = 0, Max = 200, Default = 25 }, Callback = function(value) AimbotConfig.Punch.Prediction = value / 100 end
})

KillerAimbotBox:Space()

KillerAimbotBox:Toggle({
    Title = "Aimbot Throw Pizza (Elliot)",
    Desc = "Auto-aim for Throw Pizza ability",
    Value = false,
    Callback = function(state)
        AimbotConfig.ThrowPizza.Enabled = state
        Notify("Aimbot Throw Pizza", state and "Enabled" or "Disabled", 3)
    end
})

KillerAimbotBox:Slider({
    Title = "Throw Pizza Prediction",
    Value = { Min = 0, Max = 200, Default = 25 },
    Callback = function(value)
        AimbotConfig.ThrowPizza.Prediction = value / 100
    end
})

KillerAimbotBox:Space()

KillerAimbotBox:Toggle({
    Title = "Killers Aimbot (All Skills)",
    Desc = "Enable aimbot for all killer skills",
    Value = false,
    Callback = function(state)
        AimbotConfig.Killers.Enabled = state
        Notify("Killers Aimbot", state and "Enabled" or "Disabled", 3)
    end
})

end -- End aimbot scope

do -- Aim Assist and Silent Aim scope
local AimAssistBox = AimbotTab:Section({ Title = "Aim Assist", TextSize = 18, Box = true, Opened = true })
AimAssistBox:Toggle({ Title = "Survivor Aim Assist", Desc = "Aim at the killer automatically", Value = false,
    Callback = function(state) Toggles.SurvivorAimAssist = state Notify("Survivor Aim Assist", state and "Enabled" or "Disabled", 3) end })

local SilentAimBox = AimbotTab:Section({ Title = "Silent Aim", TextSize = 18, Box = true, Opened = true })
SilentAimBox:Toggle({ Title = "Dusekkar Silent Aim", Desc = "Plasma beam auto-aims at killer", Value = false,
    Callback = function(state) Toggles.DusekkarSilentAim = state Notify("Dusekkar Silent Aim", state and "Enabled" or "Disabled", 3) end })
SilentAimBox:Toggle({ Title = "C00lkid Silent Aim", Desc = "Corrupt nature auto-aims at survivors", Value = false,
    Callback = function(state) Toggles.CoolkidSilentAim = state Notify("C00lkid Silent Aim", state and "Enabled" or "Disabled", 3) end })
end

do -- Hitbox scope
local HitboxBox = AimbotTab:Section({ Title = "Hitbox Expander", TextSize = 18, Box = true, Opened = true })
HitboxBox:Toggle({ Title = "Hitbox Expander", Desc = "Expand survivor hitboxes (hookmethod bypass)", Value = false,
    Callback = function(state) Toggles.HitboxExpander = state Notify("Hitbox Expander", state and "Enabled" or "Disabled", 3) end })
HitboxBox:Toggle({ Title = "Show Hitbox Visual", Desc = "Display expanded hitbox area", Value = false,
    Callback = function(state) Toggles.HitboxVisual = state Notify("Hitbox Visual", state and "Enabled" or "Disabled", 3) end })
HitboxBox:Slider({ Title = "Hitbox Size", Value = { Min = 5, Max = 100, Default = Options.HitboxExpanderRange }, Callback = function(value) Options.HitboxExpanderRange = value end })
end

do -- ESP scope
local PlayerESPBox = ESPTab:Section({ Title = "Player ESP", TextSize = 18, Box = true, Opened = true })
PlayerESPBox:Toggle({ Title = "Killer ESP", Desc = "Highlights the killer (shows FAKE Noli)", Value = false,
    Callback = function(state) Toggles.KillerESP = state updateESPVisibility() Notify("Killer ESP", state and "Enabled" or "Disabled", 3) end })
PlayerESPBox:Toggle({ Title = "Survivor ESP", Desc = "Highlights other survivors", Value = false,
    Callback = function(state) Toggles.SurvivorESP = state updateESPVisibility() Notify("Survivor ESP", state and "Enabled" or "Disabled", 3) end })

local GeneratorESPBox = ESPTab:Section({ Title = "Generator ESP", TextSize = 18, Box = true, Opened = true })
GeneratorESPBox:Toggle({ Title = "Generator ESP", Desc = "Highlights generators (green when complete)", Value = false,
    Callback = function(state) Toggles.GeneratorESP = state Notify("Generator ESP", state and "Enabled" or "Disabled", 3) end })
GeneratorESPBox:Toggle({ Title = "Generator Progress ESP", Desc = "Shows generator progress % and detects fake generators", Value = false,
    Callback = function(state) generatorProgressESPEnabled = state
        if state then task.spawn(function() while generatorProgressESPEnabled do updateGeneratorProgressESP() task.wait(0.5) end end) Notify("Generator Progress ESP", "Enabled - Shows % and FAKE generators", 3)
        else clearGeneratorProgressESP() Notify("Generator Progress ESP", "Disabled", 3) end end })
GeneratorESPBox:Toggle({ Title = "Generator Nametags", Desc = "Shows generator names", Value = false,
    Callback = function(state) Toggles.GeneratorNametags = state Notify("Generator Nametags", state and "Enabled" or "Disabled", 3) end })

local ItemESPBox = ESPTab:Section({ Title = "Item ESP", TextSize = 18, Box = true, Opened = true })
ItemESPBox:Toggle({ Title = "Item ESP", Desc = "Highlights items on the map", Value = false,
    Callback = function(state) Toggles.ItemESP = state Notify("Item ESP", state and "Enabled" or "Disabled", 3) end })
ItemESPBox:Toggle({ Title = "Item Nametags", Desc = "Shows item names", Value = false,
    Callback = function(state) Toggles.ItemNametags = state Notify("Item Nametags", state and "Enabled" or "Disabled", 3) end })

local MiscESPBox = ESPTab:Section({ Title = "Misc ESP", TextSize = 18, Box = true, Opened = true })
MiscESPBox:Toggle({ Title = "1x1x1x1 Zombie ESP", Desc = "Highlights 1x1x1x1 zombies", Value = false,
    Callback = function(state) Toggles.ZombieESP = state Notify("Zombie ESP", state and "Enabled" or "Disabled", 3) end })

local TrapESPBox = ESPTab:Section({ Title = "Trap ESP", TextSize = 18, Box = true, Opened = true })
TrapESPBox:Toggle({ Title = "Dispenser ESP", Desc = "Shows Builderman's dispenser traps (Blue)", Value = false,
    Callback = function(state) Toggles.DispenserESP = state if not state then disableDispenserESP() end Notify("Dispenser ESP", state and "Enabled" or "Disabled", 3) end })
TrapESPBox:Toggle({ Title = "Sentry ESP", Desc = "Shows Builderman's sentry turrets (Gray)", Value = false,
    Callback = function(state) Toggles.SentryESP = state if not state then disableSentryESP() end Notify("Sentry ESP", state and "Enabled" or "Disabled", 3) end })
TrapESPBox:Toggle({ Title = "Tripwire ESP", Desc = "Shows Taph's tripwire traps (Orange)", Value = false,
    Callback = function(state) Toggles.TripwireESP = state if not state then disableTripwireESP() end Notify("Tripwire ESP", state and "Enabled" or "Disabled", 3) end })
TrapESPBox:Toggle({ Title = "Subspace Tripmine ESP", Desc = "Shows 1x1x1x1's subspace mines (Purple)", Value = false,
    Callback = function(state) Toggles.SubspaceESP = state if not state then disableSubspaceESP() end Notify("Subspace ESP", state and "Enabled" or "Disabled", 3) end })

local VisualsBox = ESPTab:Section({ Title = "Visuals", TextSize = 18, Box = true, Opened = true })
VisualsBox:Button({ Title = "Remove Fog", Desc = "Removes fog from the map", Callback = function() noFog() Notify("Visuals", "Fog removed!", 3) end })
VisualsBox:Button({ Title = "Full Bright", Desc = "Makes the map fully bright", Callback = function() fullBright() Notify("Visuals", "Full brightness enabled!", 3) end })
end

TeleportTab:Dropdown({
    Title = "Generator Teleports",
    Icon = "zap",
    Values = {
        {
            Title = "Generator 1",
            Icon = "map-pin",
            Callback = function()
                teleportToGenerator(1)
                Notify("Teleport", "Teleported to Generator 1", 3)
            end
        },
        {
            Title = "Generator 2",
            Icon = "map-pin",
            Callback = function()
                teleportToGenerator(2)
                Notify("Teleport", "Teleported to Generator 2", 3)
            end
        },
        {
            Title = "Generator 3",
            Icon = "map-pin",
            Callback = function()
                teleportToGenerator(3)
                Notify("Teleport", "Teleported to Generator 3", 3)
            end
        },
        {
            Title = "Generator 4",
            Icon = "map-pin",
            Callback = function()
                teleportToGenerator(4)
                Notify("Teleport", "Teleported to Generator 4", 3)
            end
        },
        {
            Title = "Generator 5",
            Icon = "map-pin",
            Callback = function()
                teleportToGenerator(5)
                Notify("Teleport", "Teleported to Generator 5", 3)
            end
        },
    }
})

TeleportTab:Space()

TeleportTab:Dropdown({
    Title = "Quick Teleports",
    Icon = "navigation",
    Values = {
        {
            Title = "Random Item",
            Desc = "Teleport to a random item",
            Icon = "package",
            Callback = function()
                teleportToRandomItem()
                Notify("Teleport", "Teleported to random item", 3)
            end
        },
        {
            Title = "Killer",
            Desc = "Teleport to the killer",
            Icon = "skull",
            Callback = function()
                teleportToKiller()
                Notify("Teleport", "Teleported to killer", 3)
            end
        },
        {
            Title = "Random Survivor",
            Desc = "Teleport to a random survivor",
            Icon = "user",
            Callback = function()
                teleportToRandomSurvivor()
                Notify("Teleport", "Teleported to random survivor", 3)
            end
        },
        {
            Type = "Divider",
        },
        {
            Title = "Walk to Random Item",
            Desc = "Pathfind to a random item",
            Icon = "footprints",
            Callback = function()
                if playingState == "Spectating" then
                    return Notify("Error", "Cannot use while spectating", 7)
                end
                pcall(function()
                    local items = {}
                    if workspace:FindFirstChild("Map") and getGameMap():FindFirstChild("Ingame") then
                        for _, v in pairs(getGameMap().Ingame:GetDescendants()) do
                            if v:IsA("Tool") then
                                table.insert(items, v)
                            end
                        end
                    end
                    if #items > 0 and items[1]:FindFirstChild("ItemRoot") then
                        pathfindTo(items[math.random(1, #items)].ItemRoot.Position)
                    end
                end)
                Notify("Pathfinding", "Walking to random item...", 3)
            end
        },
    }
})

local HiddenAchievementsBox = AchievementsTab:Section({
    Title = "Hidden Achievements",
    TextSize = 18,
    Box = true,
    Opened = true,
})

HiddenAchievementsBox:Button({
    Title = "[.] - Meet Brandon",
    Desc = "Meet ogologl's best friend for the first time",
    Callback = function()
        unlockAchievement("MeetBrandon")
    end
})

HiddenAchievementsBox:Button({
    Title = "[Meow meow meow] - I Love Cats",
    Desc = "Interact with the cat in the lobby more than 15 times",
    Callback = function()
        unlockAchievement("ILoveCats")
    end
})

HiddenAchievementsBox:Button({
    Title = "[Coming straight from YOUR house.] - TV Time",
    Desc = "??? - I Love TV",
    Callback = function()
        unlockAchievement("TVTIME")
    end
})

HiddenAchievementsBox:Button({
    Title = "[A Captain and his Ship] - Meet Demophon",
    Desc = "Hear his tale",
    Callback = function()
        unlockAchievement("MeetDemophon")
    end
})
end -- End scope

do -- Settings scope
local AntiFeaturesBox = SettingsTab:Section({ Title = "Anti Features", TextSize = 18, Box = true, Opened = true })
AntiFeaturesBox:Toggle({ Title = "Anti Stun", Value = false, Callback = function(state) Toggles.AntiStun = state Notify("Anti Stun", state and "Enabled" or "Disabled", 3) end })
AntiFeaturesBox:Toggle({ Title = "Anti Slow", Value = false, Callback = function(state) Toggles.AntiSlow = state Notify("Anti Slow", state and "Enabled" or "Disabled", 3) end })
AntiFeaturesBox:Toggle({ Title = "Anti Blindness", Value = false, Callback = function(state) Toggles.AntiBlindness = state Notify("Anti Blindness", state and "Enabled" or "Disabled", 3) end })

local ConfigBox = SettingsTab:Section({ Title = "Config", TextSize = 18, Box = true, Opened = true })

local CONFIG_FILE = "ZlexHubConfig.json"

local function saveConfig()
    local configData = {
        Toggles = Toggles,
        Options = Options
    }
    local success, encoded = pcall(function()
        return game:GetService("HttpService"):JSONEncode(configData)
    end)
    if success then
        pcall(function()
            writefile(CONFIG_FILE, encoded)
        end)
        Notify("Config", "Settings saved successfully!", 3)
    else
        Notify("Config", "Failed to save settings", 3)
    end
end

local function loadConfig()
    local success, content = pcall(function()
        return readfile(CONFIG_FILE)
    end)
    if success and content then
        local decoded = game:GetService("HttpService"):JSONDecode(content)
        if decoded.Toggles then
            for key, value in pairs(decoded.Toggles) do
                if Toggles[key] ~= nil then
                    Toggles[key] = value
                end
            end
        end
        if decoded.Options then
            for key, value in pairs(decoded.Options) do
                if Options[key] ~= nil then
                    Options[key] = value
                end
            end
        end
        Notify("Config", "Settings loaded successfully!", 3)
    else
        Notify("Config", "No saved config found", 3)
    end
end

ConfigBox:Button({ Title = "Save Config", Desc = "Save your current settings to file", Callback = function() saveConfig() end })
ConfigBox:Button({ Title = "Load Config", Desc = "Load your saved settings", Callback = function() loadConfig() end })
ConfigBox:Toggle({ Title = "Auto-Load Config", Desc = "Automatically load config on script start", Value = false,
    Callback = function(state) if state then pcall(function() writefile("ZlexHubAutoLoad.txt", "true") end) Notify("Config", "Auto-load enabled", 3) else pcall(function() writefile("ZlexHubAutoLoad.txt", "false") end) Notify("Config", "Auto-load disabled", 3) end end })

local UISettingsBox = SettingsTab:Section({ Title = "UI Settings", TextSize = 18, Box = true, Opened = true })
UISettingsBox:Keybind({ Flag = "ToggleUIKeybind", Title = "Toggle UI Keybind", Desc = "Press this key to open/close the UI", Value = "RightShift",
    Callback = function(key) Window:SetToggleKey(Enum.KeyCode[key]) Notify("Keybind", "UI toggle key set to: " .. key, 3) end })
UISettingsBox:Button({ Title = "Close UI", Desc = "Hide the UI - Use keybind to reopen", Callback = function() Window:Minimize() Notify("UI", "Press your toggle key to reopen", 3) end })
UISettingsBox:Button({ Title = "Destroy UI", Desc = "Permanently removes the script UI", Callback = function() Window:Destroy() end })

local MiscSettingsBox = SettingsTab:Section({ Title = "Misc", TextSize = 18, Box = true, Opened = true })
MiscSettingsBox:Button({ Title = "Panic (Disable All)", Desc = "Instantly disables all features", Callback = function() panic() end })
MiscSettingsBox:Button({ Title = "Copy Discord Invite", Desc = "https://discord.gg/vPRrvznq3y", Callback = function() setclipboard("https://discord.gg/vPRrvznq3y") Notify("Discord", "Invite copied to clipboard!", 3) end })

pcall(function()
    local autoLoadEnabled = readfile("ZlexHubAutoLoad.txt")
    if autoLoadEnabled == "true" then
        task.wait(0.5)
        loadConfig()
    end
end)

WindUI:Notify({
    Title = "Zlex Hub v3.0",
    Content = "Script loaded! Use Settings tab to save/load your config.",
    Duration = 7
})
end -- End settings scope

