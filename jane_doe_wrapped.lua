local RobloxServices = {
    Players = game:GetService("Players"),
    RunService = game:GetService("RunService"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    Workspace = game:GetService("Workspace"),
    UserInput = game:GetService("UserInputService"),
    Stats = game:GetService("Stats"),
}

local LocalPlayer = RobloxServices.Players.LocalPlayer
local CurrentCamera = RobloxServices.Workspace.CurrentCamera

-- ──────────────────────────────────────────────
--  SHARED RF DISPATCHER SYSTEM
-- ──────────────────────────────────────────────
local rfDispatch = {
    hooks = {},
    installed = false,
    originalCallback = nil
}

function rfDispatch:register(id, callback)
    self.hooks[id] = callback
end

function rfDispatch:unregister(id)
    self.hooks[id] = nil
end

function rfDispatch:install(remoteFunction)
    if self.installed then return end
    
    if typeof(getcallbackvalue) == "function" then
        self.originalCallback = getcallbackvalue(remoteFunction, "OnClientInvoke")
    else
        self.originalCallback = remoteFunction.OnClientInvoke
    end

    remoteFunction.OnClientInvoke = function(requestName, ...)
        for id, hookFunc in pairs(self.hooks) do
            local success, result = pcall(hookFunc, requestName, ...)
            if success and result ~= nil then
                return result
            end
        end
        
        if self.originalCallback then
            local ok, res = pcall(self.originalCallback, requestName, ...)
            if ok then return res end
        end
    end
    self.installed = true
end

function rfDispatch:uninstall(remoteFunction)
    if not self.installed then return end
    if remoteFunction and self.originalCallback then
        remoteFunction.OnClientInvoke = self.originalCallback
    end
    self.hooks = {}
    self.originalCallback = nil
    self.installed = false
end

-- ──────────────────────────────────────────────
--  WINDUI MAIN GUI
-- ──────────────────────────────────────────────
local WindUI
local windUISuccess, windUIErr = pcall(function()
    WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
end)

if not windUISuccess then
    warn("Failed to load WindUI: " .. tostring(windUIErr))
    return
end

local Window = WindUI:CreateWindow({
    Title = "JANE DOE",
    Icon = "gem",
    Author = "mitsuki & viper",
    Folder = "SAKIWARE_JANEDOE_V1",
    Size = UDim2.fromOffset(420, 480),
    Theme = "Dark",
})

-- ============================== JANE DOE CRYSTAL SILENT AIM ==============================

local tabJaneDoe = Window:Tab({ Title = "Jane Doe", Icon = "gem", IconColor = Color3.fromHex("#7DD3FC"), ShowTabTitle = false })

do
    local jd_Run    = RobloxServices.RunService
    local jd_RS     = RobloxServices.ReplicatedStorage
    local jd_lp     = LocalPlayer
    local jd_Camera = CurrentCamera

    local jd_RemoteEvent = nil
    local jd_NetworkRF   = nil
    
    -- Find the remotes
    pcall(function()
        jd_RemoteEvent = jd_RS:WaitForChild("Modules",10):WaitForChild("Network",10):WaitForChild("Network",10):WaitForChild("RemoteEvent",10)
    end)
    pcall(function()
        jd_NetworkRF = jd_RS:WaitForChild("Modules",10):WaitForChild("Network",10):WaitForChild("Network",10):WaitForChild("RemoteFunction",10)
    end)

    -- Settings
    local jd_enabled       = false
    local jd_aimbotOn      = false
    local jd_patched       = false
    local jd_unloaded      = false
    local jd_AIM_OFFSET    = -0.3        
    local jd_PREDICTION    = 0.6         
    local jd_HOLD_DURATION = 0.9         
    local jd_axeEnabled    = false
    local jd_AXE_LOCK_DURATION = 1.7     
    local jd_axeLocked     = false
    local jd_killerMotionData  = {}

    -- Get killer velocity for prediction
    local function jd_getKillerVelocity(hrp)
        local ok, result = pcall(function()
            local now=tick(); local pos=hrp.Position; local data=jd_killerMotionData[hrp]
            if not data then 
                jd_killerMotionData[hrp]={lastPos=pos,lastTime=now,velocity=Vector3.zero}; 
                return Vector3.zero 
            end
            local dt=now-data.lastTime; if dt<=0 then return data.velocity end
            local vel=(pos-data.lastPos)/dt; data.lastPos=pos; data.lastTime=now; data.velocity=vel
            return vel
        end)
        return ok and result or Vector3.zero
    end

    -- Find nearest killer mapped to workspace structure
    local function jd_getNearestKiller(fromPos)
        local ok, result = pcall(function()
            local playerFolder = RobloxServices.Workspace:FindFirstChild("Players")
            local folder = playerFolder and playerFolder:FindFirstChild("Killers")
            if not folder then return nil end
            
            local nearest,best=nil,math.huge
            for _,model in ipairs(folder:GetChildren()) do
                local hrp=model:FindFirstChild("HumanoidRootPart"); local hum=model:FindFirstChildOfClass("Humanoid")
                if hrp and hum and hum.Health>0 then 
                    local d=(hrp.Position-fromPos).Magnitude; 
                    if d<best then best=d; nearest=model end 
                end
            end
            return nearest
        end)
        return ok and result or nil
    end

    -- Hold crystal (charge)
    local function jd_holdCrystal()
        local ok = pcall(function()
            if not jd_RemoteEvent then return end
            local b = buffer.create(8)
            buffer.writeu32(b, 0, 2)
            buffer.writef32(b, 4, RobloxServices.Workspace.DistributedGameTime)
            jd_RemoteEvent:FireServer(jd_lp.Name .. "CrystalInput", { b })
        end)
        if not ok then
            warn("Failed to hold crystal")
        end
    end

    -- Axe lock-on (turns you to face killer when throwing axe)
    local function jd_axeDoLock()
        local ok = pcall(function()
            if jd_axeLocked then return end
            local char = jd_lp.Character
            local myHRP = char and char:FindFirstChild("HumanoidRootPart")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if not myHRP or not hum then return end
            local killer = jd_getNearestKiller(myHRP.Position)
            local killerHRP = killer and killer:FindFirstChild("HumanoidRootPart")
            if not killerHRP then return end
            jd_axeLocked = true
            local savedAutoRotate = hum.AutoRotate
            hum.AutoRotate = false
            local deadline = tick() + jd_AXE_LOCK_DURATION
            local conn; conn = jd_Run.RenderStepped:Connect(function()
                local connOk = pcall(function()
                    if tick() >= deadline or not jd_axeEnabled then
                        conn:Disconnect()
                        pcall(function() hum.AutoRotate = savedAutoRotate end)
                        jd_axeLocked = false
                        return
                    end
                    if not myHRP.Parent or not killerHRP.Parent then
                        conn:Disconnect()
                        pcall(function() hum.AutoRotate = savedAutoRotate end)
                        jd_axeLocked = false
                        return
                    end
                    local dir = Vector3.new(killerHRP.Position.X - myHRP.Position.X, 0, killerHRP.Position.Z - myHRP.Position.Z)
                    if dir.Magnitude > 0 then
                        myHRP.CFrame = CFrame.new(myHRP.Position, myHRP.Position + dir.Unit)
                    end
                end)
                if not connOk then
                    pcall(function() conn:Disconnect() end)
                    pcall(function() hum.AutoRotate = savedAutoRotate end)
                    jd_axeLocked = false
                end
            end)
        end)
        if not ok then
            warn("Failed to execute axe lock-on")
            jd_axeLocked = false
        end
    end

    -- Build camera CFrame for silent aim (calculates angle to hit target)
    local function jd_buildCamCF(myHRP, killerHRP, v0, g)
        local ok, result = pcall(function()
            local hum=myHRP.Parent and myHRP.Parent:FindFirstChildOfClass("Humanoid")
            local hipH=hum and hum.HipHeight or 1.35
            local v238=(hipH+myHRP.Size.Y/2)/2
            local spawnPos=myHRP.CFrame.Position+Vector3.new(0,v238,0)
            local vel=jd_getKillerVelocity(killerHRP)
            local predicted=killerHRP.Position+vel*jd_PREDICTION
            local target=predicted+Vector3.new(0,jd_AIM_OFFSET,0)
            local delta=target-spawnPos
            local flatV=Vector3.new(delta.X,0,delta.Z)
            local dx=flatV.Magnitude; local dy=delta.Y
            if dx<0.01 then
                local d=dy>=0 and Vector3.new(0,1,0) or Vector3.new(0,-1,0)
                return CFrame.new(jd_Camera.CFrame.Position,jd_Camera.CFrame.Position+d)
            end
            local flatDir=flatV.Unit; local v2=v0*v0
            local disc=v2*v2-g*(g*dx*dx+2*dy*v2)
            local theta=disc<0 and math.atan2(dy,dx) or math.atan2(v2-math.sqrt(disc),g*dx)
            local T=math.tan(theta); local denom=3+T
            local alpha=math.abs(denom)<0.0001 and -math.pi/2 or math.atan2(3*T-1,denom)
            local yawCF=CFrame.new(jd_Camera.CFrame.Position,jd_Camera.CFrame.Position+flatDir)
            return yawCF*CFrame.Angles(alpha,0,0)
        end)
        return ok and result or nil
    end

    -- Get local actor
    local function jd_getLocalActor() 
        return jd_lp.Character
    end

    -- Apply silent aim patch to RemoteFunction
    local function jd_applyPatch(actor)
        local ok = pcall(function()
            if jd_patched or not actor or not jd_NetworkRF then return end
            rfDispatch:install(jd_NetworkRF)
            rfDispatch:register("jd", function(reqName, ...)
                local hookOk, result = pcall(function()
                    if not (jd_enabled and jd_aimbotOn) then return nil end
                    local char = jd_lp.Character
                    local myHRP = char and char:FindFirstChild("HumanoidRootPart")
                    if not myHRP then return nil end
                    local killer = jd_getNearestKiller(myHRP.Position)
                    local killerHRP = killer and killer:FindFirstChild("HumanoidRootPart")
                    if not killerHRP then return nil end
                    
                    -- Silent aim for GetMousePosition
                    if reqName == "GetMousePosition" then
                        local vel = jd_getKillerVelocity(killerHRP)
                        return killerHRP.Position + vel * jd_PREDICTION + Vector3.new(0, jd_AIM_OFFSET, 0)
                    end
                    
                    -- Camera CFrame override
                    if reqName == "GetCameraCF" then
                        local cf = jd_buildCamCF(myHRP, killerHRP, 250, 40)
                        if cf then return cf end
                    end
                    return nil
                end)
                if hookOk then return result else return nil end
            end)
            jd_patched = true
        end)
        if not ok then
            warn("Failed to apply patch")
        end
    end
    
    -- Remove patch
    local function jd_removePatch()
        local ok = pcall(function()
            if not jd_patched then return end
            rfDispatch:unregister("jd")
            jd_patched = false
        end)
        if not ok then
            warn("Failed to remove patch")
        end
    end

    -- Auto-hold crystal when firing (extends duration)
    local jd_holdActive = false
    task.spawn(function()
        local ok, re = pcall(function()
            return RobloxServices.ReplicatedStorage:WaitForChild("Modules",5):WaitForChild("Network",5):WaitForChild("Network",5):WaitForChild("RemoteEvent",5)
        end)
        if not ok or not re then 
            warn("Failed to find RemoteEvent for crystal hold")
            return 
        end
        
        local oldNC
        pcall(function()
            oldNC = hookmetamethod(game, "__namecall", function(self, ...)
                local method = getnamecallmethod()
                local args = {...}
                if method == "FireServer" and self == re then
                    local eventName = tostring(args[1])
                    
                    -- Auto-hold crystal when used
                    if jd_enabled and eventName == (jd_lp.Name .. "CrystalInput") then
                        if not jd_holdActive then
                            jd_holdActive = true
                            task.spawn(function()
                                local holdOk = pcall(function()
                                    local deadline = tick() + jd_HOLD_DURATION
                                    while tick() < deadline and jd_enabled and not jd_unloaded do
                                        jd_holdCrystal()
                                        task.wait(1/30)
                                    end
                                    jd_holdActive = false
                                end)
                                if not holdOk then
                                    warn("Crystal hold loop failed")
                                    jd_holdActive = false
                                end
                            end)
                        end
                    end
                    
                    -- Axe lock-on when axe is thrown
                    if jd_axeEnabled and eventName == "UseActorAbility" and args[2] and args[2][1] then
                        local ok2, bs = pcall(function() return buffer.tostring(args[2][1]) end)
                        if ok2 and bs and bs:find("Axe") then
                            task.spawn(jd_axeDoLock)
                        end
                    end
                end
                return oldNC(self, ...)
            end)
        end)
    end)

    -- Monitor character changes to re-apply patch
    task.spawn(function()
        local lastActor=nil
        while not jd_unloaded do
            task.wait(0.5)
            local cur=jd_getLocalActor()
            if cur~=lastActor then
                if lastActor~=nil then jd_patched=false; jd_killerMotionData={} end
                lastActor=cur
                if cur and jd_enabled then jd_applyPatch(cur) end
            end
        end
    end)

    -- ============================== UI SECTION ==============================
    
    -- Crystal Auto-Fire Section
    local sec_024 = tabJaneDoe:Section({ Title = "Crystal Auto-Fire", Opened = true })
    
    sec_024:Toggle({ 
        Title = "Enable Jane Doe Aimbot", Flag = "jdEnabled", Default = false, Type = "Checkbox",
        Callback = function(on)
            jd_enabled=on; local actor=jd_getLocalActor()
            if on and not jd_patched and actor then jd_applyPatch(actor) end
        end
    })
    
    sec_024:Toggle({ 
        Title = "Aimbot (Silent Aim)", Flag = "jdSilentAim", Default = false, Type = "Checkbox",
        Callback = function(on)
            jd_aimbotOn=on
            local actor=jd_getLocalActor(); if on and not jd_patched and actor then jd_applyPatch(actor) end
        end
    })
    
    sec_024:Slider({ 
        Title = "Aim Offset (Y)", Flag = "jdAimOffset", Value = {Min=-5.0,Max=5.0,Default=jd_AIM_OFFSET}, Step = 0.1, 
        Callback = function(v) jd_AIM_OFFSET=v end 
    })
    
    sec_024:Slider({ 
        Title = "Prediction", Flag = "jdPrediction", Value = {Min=0.0,Max=1.0,Default=jd_PREDICTION}, Step = 0.01, 
        Callback = function(v) jd_PREDICTION=v end 
    })
    
    sec_024:Slider({ 
        Title = "Hold Duration (s)", Flag = "jdHoldDur", Value = {Min=0.3,Max=2.0,Default=jd_HOLD_DURATION}, Step = 0.1, 
        Callback = function(v) jd_HOLD_DURATION=v end 
    })

    -- Axe Lock-On Section
    local sec_025 = tabJaneDoe:Section({ Title = "Axe Lock-On", Opened = true })
    
    sec_025:Toggle({ 
        Title = "Enable Axe Lock-On", Flag = "jdAxeEnabled", Default = false, Type = "Checkbox",
        Callback = function(on) 
            jd_axeEnabled=on
        end
    })
    
    sec_025:Slider({ 
        Title = "Lock Duration (s)", Flag = "jdAxeLockDur", Value = {Min=0.5,Max=3.0,Default=jd_AXE_LOCK_DURATION}, Step = 0.1, 
        Callback = function(v) 
            jd_AXE_LOCK_DURATION=v
        end 
    })

    -- Control Section
    local sec_026 = tabJaneDoe:Section({ Title = "Control", Opened = true })
    sec_026:Button({ 
        Title = "Unload Jane Doe", Callback = function()
            if jd_unloaded then return end
            jd_unloaded=true; jd_enabled=false; jd_aimbotOn=false; jd_axeEnabled=false
            jd_removePatch()
        end
    })
end

-- Global Unload UI Element
tabJaneDoe:Section({ Title = "System" }):Button({
    Title = "Unload Script Completely",
    Callback = function()
        local ok, rf = pcall(function()
            return RobloxServices.ReplicatedStorage:WaitForChild("Modules", 2)
                :WaitForChild("Network", 2)
                :WaitForChild("Network", 2)
                :WaitForChild("RemoteFunction", 2)
        end)
        if ok and rf then
            rfDispatch:uninstall(rf)
        end
        Window:Destroy()
    end
})
