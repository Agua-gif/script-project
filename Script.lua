-- ═══════════════════════════════════════════════════════════════════
--  Dandy's World AutoFarm v13  |  WindUI
--  PlaceId guard • modular • Quick/Safe • dodge • player tab • config
-- ═══════════════════════════════════════════════════════════════════
if game.PlaceId ~= 103241332655096 then
    warn("AutoFarm v13: wrong PlaceId, aborting."); return
end

local WindUI = loadstring(game:HttpGet(
    "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
))()
local H = loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/Agua-gif/script-project/refs/heads/main/main-helper.lua"
))()

local RS    = game:GetService("RunService")
local VIM   = game:GetService("VirtualInputManager")
local HS    = game:GetService("HttpService")
local LP    = H.LP

-- ═══════════════════════════════════════════════════════════════════
--  CONFIG (serialisable for save/load)
-- ═══════════════════════════════════════════════════════════════════
local CFG = {
    -- Automation
    AutoFarm             = false,
    AutoPickup           = true,
    AutoUseItems         = false,
    AutoAbility          = false,
    AutoBuyShop          = false,
    AutoEncounter        = false,
    EncounterEscapeDelay = 1.0,

    -- Skillcheck
    AutoSkillcheck       = true,
    InstantSkillcheck    = true,
    AimGold              = true,
    SkillDelay           = 0,

    -- Safety
    SafetyMode           = "safe",   -- "safe" | "quick"
    HideWhenChased       = true,
    DodgeTwisteds        = false,    -- sky-spam ALL twisters when chased
    DodgeDangerous       = false,    -- sky-spam Goob/Scraps/Dandy only
    SpottedPauseDuration = 5,
    PanicElevator        = true,
    SafetyBuffer         = 5,
    QuickModeMinDist     = 12,

    -- Movement
    NoClip               = true,
    TeleportTop          = true,
    PipeOffsetY          = 7,
    ActionCooldown       = 0.05,

    -- Player
    WalkSpeedBuff        = 0,
    RunSpeedBuff         = 0,
    LoopRunSpeed         = false,
    Spin                 = false,
    SpinSpeed            = 5,
    TpWalk               = false,

    -- Blacklists
    IgnoredTwisters      = {},
    IgnoredItems         = {},
}

-- ═══════════════════════════════════════════════════════════════════
--  CONFIG SAVE / LOAD
-- ═══════════════════════════════════════════════════════════════════
local CONFIG_PATH = "DandysAutofarm_v13.json"

local function saveConfig()
    -- Only serialise primitive-value fields (skip tables with Instance refs)
    local out = {}
    for k, v in pairs(CFG) do
        local t = type(v)
        if t == "boolean" or t == "number" or t == "string" then
            out[k] = v
        elseif t == "table" then
            -- Shallow-copy string-keyed tables (blacklists)
            local tbl = {}
            for tk, tv in pairs(v) do
                if type(tk) == "string" then tbl[tk] = tv end
            end
            out[k] = tbl
        end
    end
    pcall(function() writefile(CONFIG_PATH, HS:JSONEncode(out)) end)
end

local function loadConfig()
    pcall(function()
        if not isfile(CONFIG_PATH) then return end
        local data = HS:JSONDecode(readfile(CONFIG_PATH))
        for k, v in pairs(data) do
            if CFG[k] ~= nil then CFG[k] = v end
        end
    end)
end

local function optimizeConfig()
    -- Remove empty/default table entries
    for k, v in pairs(CFG) do
        if type(v) == "table" then
            local empty = true
            for _ in pairs(v) do empty=false; break end
            if empty then CFG[k] = {} end
        end
    end
    saveConfig()
end

loadConfig()

-- ═══════════════════════════════════════════════════════════════════
--  INIT
-- ═══════════════════════════════════════════════════════════════════
H.setupAC()

local _cancelSkillcheck    = nil
local _cancelLegitSkill    = nil

local function rehookSkillcheck()
    if _cancelSkillcheck then _cancelSkillcheck() end
    if _cancelLegitSkill then _cancelLegitSkill() end
    _cancelSkillcheck = nil; _cancelLegitSkill = nil
    if CFG.InstantSkillcheck and CFG.AutoSkillcheck then
        _cancelSkillcheck = H.hookSkillcheck(CFG.AimGold)
    end
    if CFG.AutoSkillcheck and not CFG.InstantSkillcheck then
        _cancelLegitSkill = H.startLegitSkillcheck(CFG.AimGold, CFG.SkillDelay)
    end
end
rehookSkillcheck()

-- NoClip (no BodyPosition — autofarm handles vertical movement)
task.defer(function()
    if LP.Character and CFG.NoClip then H.enableNoClip(LP.Character) end
end)
LP.CharacterAdded:Connect(function(c)
    task.wait(0.15)
    if CFG.NoClip then H.enableNoClip(c) end
end)

-- ═══════════════════════════════════════════════════════════════════
--  STATE
-- ═══════════════════════════════════════════════════════════════════
local _currentGen           = nil
local _extracting           = false
local _pipePos              = nil
local _pipeConn             = nil
local _chasedLoopActive     = false
local _farmRunning          = false
local _spottedUntil         = 0
local _floorEncounterDone   = false
local _pickedUpItems        = {}
local _encounteredMonsters  = {}
local _statusPara           = nil
local _spinConn             = nil
local _tpWalkConn           = nil
local _loopRunConn          = nil

local function setStatus(msg)
    pcall(function() if _statusPara then _statusPara:SetDesc(msg) end end)
end
local function isInPause() return tick() < _spottedUntil end

-- ═══════════════════════════════════════════════════════════════════
--  FLOOR RESET
-- ═══════════════════════════════════════════════════════════════════
local function onFloorStart()
    _floorEncounterDone  = false
    _pickedUpItems       = {}
    _encounteredMonsters = {}
end
pcall(function()
    workspace.Info.FloorActive.Changed:Connect(function(v)
        if v then onFloorStart()
        else
            _pickedUpItems       = {}
            _encounteredMonsters = {}
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
--  SPOTTED PAUSE  (sky hide by default, never elevator unless panic)
-- ═══════════════════════════════════════════════════════════════════
local function stopExtractionNow()
    H.stopExtraction()
    if _pipeConn then _pipeConn:Disconnect(); _pipeConn=nil end
    _pipePos=nil; _currentGen=nil; _extracting=false
end

local function triggerSpottedPause(reason)
    _spottedUntil = tick() + CFG.SpottedPauseDuration
    setStatus("🚨 Spotted (".. (reason or "?")..") → sky pause "..CFG.SpottedPauseDuration.."s")
    stopExtractionNow()
    H.tp(H.skyPos())
end

-- ═══════════════════════════════════════════════════════════════════
--  CHASE & DODGE SYSTEM
-- ═══════════════════════════════════════════════════════════════════
local function handleChasedState()
    if isInPause() then return true end
    if H.isDead() then return true end
    if not CFG.HideWhenChased then return false end

    local chased, chaserModel = H.isBeingChased(CFG.IgnoredTwisters)
    if not chased then _chasedLoopActive=false; return false end

    -- Always stop extraction immediately when chased
    if _extracting or _currentGen then stopExtractionNow() end

    local shouldDodge = CFG.DodgeTwisteds or
        (CFG.DodgeDangerous and chaserModel and H.isDangerousTwisted(chaserModel.Name))

    if not _chasedLoopActive then
        _chasedLoopActive = true
        task.spawn(function()
            while _chasedLoopActive and H.isBeingChased(CFG.IgnoredTwisters) do
                if shouldDodge then
                    -- Sky-spam: random offsets to confuse monster pathfinding
                    local hrp = H.getHRP()
                    local base = hrp and hrp.Position or Vector3.new(0,800,0)
                    H.tp(Vector3.new(
                        base.X + math.random(-30,30),
                        800 + math.random(0,50),
                        base.Z + math.random(-30,30)
                    ))
                else
                    H.tp(H.skyPos())
                end
                task.wait(0.1)
            end
            _chasedLoopActive = false
        end)
    end
    return true
end

-- ═══════════════════════════════════════════════════════════════════
--  PIPE KEEP (stays at pipe top during extraction)
-- ═══════════════════════════════════════════════════════════════════
local function stopPipeKeep()
    _pipePos=nil
    if _pipeConn then _pipeConn:Disconnect(); _pipeConn=nil end
end

local function startPipeKeep(pos)
    _pipePos = pos
    if _pipeConn then _pipeConn:Disconnect() end
    _pipeConn = RS.Heartbeat:Connect(function()
        if not _pipePos then return end
        -- Don't interrupt pipe keep if being chased/spotted
        if isInPause() or H.isDead() then stopPipeKeep(); return end
        if handleChasedState() then stopPipeKeep(); return end
        local hrp = H.getHRP()
        if hrp and (hrp.Position - _pipePos).Magnitude > 2 then
            H.tp(_pipePos)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════
--  SPOTTED WATCHER  (connects to gen.Stats BoolValues)
-- ═══════════════════════════════════════════════════════════════════
local function connectSpottedWatcher(gen)
    local stats = gen:FindFirstChild("Stats")
    if not stats then return end
    for _, c in ipairs(stats:GetChildren()) do
        if c:IsA("BoolValue") and c.Name ~= "SkillCheck" and c.Name ~= "Completed" then
            c.Changed:Connect(function(v)
                if not v then return end
                -- Only react if we are currently extracting THIS gen
                if not (_extracting and _currentGen == gen) then return end
                -- Ignore if this twisted is blacklisted
                if CFG.IgnoredTwisters[c.Name] then return end

                if CFG.SafetyMode == "quick" then
                    stopExtractionNow()
                    setStatus("⚡ Quick: spotted → next machine")
                else
                    triggerSpottedPause(c.Name)
                end
            end)
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  PANIC
-- ═══════════════════════════════════════════════════════════════════
local _panicVal = workspace.Info:FindFirstChild("Panic")
if _panicVal then
    _panicVal.Changed:Connect(function(v)
        -- Works regardless of AutoFarm state
        if v and CFG.PanicElevator then
            task.spawn(function()
                stopExtractionNow()
                local deadline = tick() + 5
                while tick() < deadline and _panicVal and _panicVal.Value do
                    H.tp(H.elevatorSafePos())
                    task.wait(0.1)
                end
            end)
        end
    end)
end

-- ═══════════════════════════════════════════════════════════════════
--  AUTO USE ITEMS — runs independently every 2s
-- ═══════════════════════════════════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(2)
        if CFG.AutoUseItems and not H.isDead() then
            pcall(function() H.useItems(_extracting) end)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
--  AUTO ABILITY — runs independently every 1s
-- ═══════════════════════════════════════════════════════════════════
task.spawn(function()
    while true do
        task.wait(1)
        if CFG.AutoAbility and not H.isDead() then
            pcall(H.useAbility)
        end
    end
end)

-- ═══════════════════════════════════════════════════════════════════
--  ENCOUNTER PHASE  (floor start, sequential, skip already done)
-- ═══════════════════════════════════════════════════════════════════
local function doEncounterPhase()
    if not CFG.AutoEncounter or _floorEncounterDone then return end
    _floorEncounterDone = true
    setStatus("🎯 Encounter phase…")
    for _, m in ipairs(H.getMonsters()) do
        if not CFG.AutoFarm then break end
        if H.isDead() or (_panicVal and _panicVal.Value) or isInPause() then break end
        if CFG.IgnoredTwisters[m.Name] then continue end
        if _encounteredMonsters[m] then continue end
        if not H.isMonsterActive(m) then continue end

        _encounteredMonsters[m] = true
        local mhrp = m:FindFirstChild("HumanoidRootPart")
        if mhrp then
            local r = H.getRadii(m)
            -- Approach from above
            H.tp(mhrp.Position + Vector3.new(0, r.instant + 10, 0))
            task.wait(0.05)
            H.tp(mhrp.Position + Vector3.new(0, r.instant - 2, 0))
            -- Escape IMMEDIATELY when spotted (no delay slider)
            local spotted = false
            local conn = nil
            conn = RS.Heartbeat:Connect(function()
                local chased = H.isBeingChased(CFG.IgnoredTwisters)
                if chased then spotted=true end
            end)
            -- Wait until spotted or 3s max
            local deadline = tick() + 3
            while not spotted and tick() < deadline do task.wait(0.05) end
            conn:Disconnect()
            H.tp(H.skyPos())
            task.wait(1)
        end
    end
    setStatus("✅ Encounter done")
end

-- ═══════════════════════════════════════════════════════════════════
--  ITEM PICKUP
-- ═══════════════════════════════════════════════════════════════════
local function pickupAllItems()
    if not CFG.AutoPickup then return end
    local room  = H.getRoom()
    if not room then return end
    local items = room:FindFirstChild("Items")
    if not items then return end

    for _, item in ipairs(items:GetChildren()) do
        if not CFG.AutoFarm and not true then break end -- allow manual call
        if H.isDead() or isInPause() or handleChasedState() then break end
        if _pickedUpItems[item] then continue end
        if CFG.IgnoredItems[item.Name] then continue end

        local pp = H.findPrompt(item)
        if not (pp and pp.Enabled) then _pickedUpItems[item]=true; continue end

        local root = item:FindFirstChildWhichIsA("BasePart") or (item:IsA("BasePart") and item)
        if not root then continue end

        local itemPos = root.Position
        if H.nearestMonsterDist(itemPos, CFG.IgnoredTwisters) < CFG.SafetyBuffer then
            continue
        end

        local range    = pp.MaxActivationDistance or 6
        local belowPos = Vector3.new(itemPos.X, itemPos.Y - (range*0.7), itemPos.Z)
        H.tp(belowPos)
        task.wait(0.04)
        if H.isDead() or isInPause() or handleChasedState() then break end

        H.firePrompt(pp, itemPos)

        -- Wait for pickup confirmation (item removed or prompt disabled)
        local deadline = tick() + 1.5
        while tick() < deadline do
            if not item.Parent or not pp or not pp.Enabled then break end
            task.wait(0.05)
        end
        _pickedUpItems[item] = true
        task.wait(CFG.ActionCooldown)
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  AUTO BUY
-- ═══════════════════════════════════════════════════════════════════
local function autoBuyShop()
    if not CFG.AutoBuyShop then return end
    H.buyShopItems()
end
pcall(function()
    workspace.Info:WaitForChild("DandyStoreOpen", 10)
    workspace.Info.DandyStoreOpen.Changed:Connect(function(v)
        if v and CFG.AutoBuyShop then task.delay(0.3, autoBuyShop) end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════
--  PLAYER EFFECTS
-- ═══════════════════════════════════════════════════════════════════
local function applyPlayerEffects()
    local char = LP.Character
    local hum  = char and char:FindFirstChild("Humanoid")
    if not hum then return end
    if CFG.WalkSpeedBuff ~= 0 then hum.WalkSpeed = 16 + CFG.WalkSpeedBuff end
    if CFG.RunSpeedBuff  ~= 0 then hum.WalkSpeed = math.max(hum.WalkSpeed, 16 + CFG.RunSpeedBuff) end
end

LP.CharacterAdded:Connect(function() task.wait(0.5); applyPlayerEffects() end)
task.defer(applyPlayerEffects)

local function startSpin(speed)
    if _spinConn then _spinConn:Disconnect() end
    _spinConn = RS.Heartbeat:Connect(function()
        if not CFG.Spin then return end
        local hrp = H.getHRP()
        if hrp then hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(speed), 0) end
    end)
end

local function stopSpin()
    if _spinConn then _spinConn:Disconnect(); _spinConn=nil end
end

local function startTpWalk()
    if _tpWalkConn then _tpWalkConn:Disconnect() end
    local UIS = game:GetService("UserInputService")
    _tpWalkConn = RS.Heartbeat:Connect(function()
        if not CFG.TpWalk then return end
        local hrp = H.getHRP()
        local hum = LP.Character and LP.Character:FindFirstChild("Humanoid")
        if not (hrp and hum) then return end
        local mv  = hum.MoveDirection
        if mv.Magnitude > 0.1 then
            H.tp(hrp.Position + mv * 3)
        end
    end)
end

local function stopTpWalk()
    if _tpWalkConn then _tpWalkConn:Disconnect(); _tpWalkConn=nil end
end

local function startLoopRun()
    if _loopRunConn then _loopRunConn:Disconnect() end
    _loopRunConn = RS.Heartbeat:Connect(function()
        if not CFG.LoopRunSpeed then return end
        local char = LP.Character
        local hum  = char and char:FindFirstChild("Humanoid")
        if hum then hum.WalkSpeed = 24 + CFG.RunSpeedBuff end
    end)
end

local function stopLoopRun()
    if _loopRunConn then _loopRunConn:Disconnect(); _loopRunConn=nil end
end

-- ═══════════════════════════════════════════════════════════════════
--  MAIN FARM CYCLE
-- ═══════════════════════════════════════════════════════════════════
local function farmCycle()
    -- Guard: dead player
    if H.isDead() then
        setStatus("💀 Dead — waiting for respawn")
        stopExtractionNow(); task.wait(2); return
    end

    -- 1. Panic
    if _panicVal and _panicVal.Value then
        setStatus("🚨 Panic! → elevator")
        stopExtractionNow(); H.tp(H.elevatorSafePos()); task.wait(2); return
    end

    -- 2. Spotted pause
    if isInPause() then
        setStatus("⏸ Pause: "..math.ceil(_spottedUntil-tick()).."s")
        task.wait(0.2); return
    end

    -- 3. Chase check — ALWAYS stops extraction
    if handleChasedState() then
        setStatus("🏃 Chased → sky")
        task.wait(0.1); return
    end

    -- 4. Mid-extraction: check spotted + completion
    if _extracting and _currentGen then
        -- Quick mode: check proximity
        if CFG.SafetyMode == "quick" then
            local chased, cm = H.isBeingChased(CFG.IgnoredTwisters)
            if chased and cm then
                local mhrp = cm:FindFirstChild("HumanoidRootPart")
                local hrp  = H.getHRP()
                if mhrp and hrp and (mhrp.Position-hrp.Position).Magnitude < CFG.QuickModeMinDist then
                    stopExtractionNow(); setStatus("⚡ Quick: too close → next"); task.wait(0.3); return
                end
            end
        end

        local spotted, spottedBy = H.isSpottedAtGen(_currentGen, CFG.IgnoredTwisters)
        if spotted then
            if CFG.SafetyMode == "quick" then
                stopExtractionNow(); setStatus("⚡ Quick: spotted → next"); return
            else
                triggerSpottedPause(spottedBy); return
            end
        end

        local stats     = _currentGen:FindFirstChild("Stats")
        local completed = stats and stats:FindFirstChild("Completed")
        local ap        = stats and stats:FindFirstChild("ActivePlayer")
        if (completed and completed.Value) or (ap and ap.Value == nil) then
            setStatus("✅ Done → next")
            stopExtractionNow(); task.wait(CFG.ActionCooldown)
        else
            setStatus("⚡ Extracting…"); task.wait(0.1)
        end
        return
    end

    local floorActive = workspace.Info.FloorActive.Value
    if not floorActive then
        setStatus("🛗 Waiting for floor…"); task.wait(1); return
    end

    -- 5. ENCOUNTER phase (floor start)
    if CFG.AutoEncounter and not _floorEncounterDone then
        doEncounterPhase(); return
    end

    -- 6. ITEMS phase
    if CFG.AutoPickup then
        local room  = H.getRoom()
        local items = room and room:FindFirstChild("Items")
        if items then
            local hasNew = false
            for _, item in ipairs(items:GetChildren()) do
                if not _pickedUpItems[item] and not CFG.IgnoredItems[item.Name] then
                    local pp = H.findPrompt(item)
                    if pp and pp.Enabled then hasNew=true; break end
                end
            end
            if hasNew then
                setStatus("🎁 Picking up items…")
                pickupAllItems(); return
            end
        end
    end

    -- 7. Pick generator
    local gen, reason = H.pickGenerator(CFG.SafetyBuffer, CFG.IgnoredTwisters)

    if reason == "ALL_DONE" then
        setStatus("🏁 All done → elevator")
        H.tp(H.elevatorSafePos()); task.wait(3); return
    end
    if reason == "ALL_OCCUPIED" then
        setStatus("👥 All occupied → sky")
        H.tp(H.skyPos()); task.wait(2); return
    end
    if not gen then
        -- All unsafe: sky, NOT elevator
        setStatus("⚠ All unsafe → sky")
        H.tp(H.skyPos()); task.wait(2); return
    end

    -- Guard: don't retarget if already heading to this gen
    _currentGen = gen
    local origin = gen:FindFirstChild("Origin")
    local prompt = gen:FindFirstChild("Prompt")
    if not (origin and prompt) then _currentGen=nil; task.wait(0.3); return end

    if not H.isSafe(origin.Position, CFG.SafetyBuffer, CFG.HideWhenChased, CFG.IgnoredTwisters) then
        setStatus("⚠ Twisted at target → repick")
        _currentGen=nil; task.wait(0.3); return
    end

    -- 8. Move to prompt
    setStatus("🚶 Moving to machine…")
    H.tp(prompt.Position + Vector3.new(0, 3, 0))
    task.wait(0.1)

    if H.isDead() or isInPause() or handleChasedState() or
       not H.isSafe(origin.Position, CFG.SafetyBuffer, CFG.HideWhenChased, CFG.IgnoredTwisters) then
        setStatus("🚫 Danger → sky")
        H.tp(H.skyPos()); _currentGen=nil; task.wait(1); return
    end

    -- 9. Fire prompt
    local pp = H.findPrompt(prompt)
    if not pp then
        setStatus("❌ No prompt"); _currentGen=nil; task.wait(0.3); return
    end
    setStatus("⚙ Firing prompt…")
    H.firePrompt(pp, prompt.Position)
    task.wait(0.15)

    -- Verify extraction started
    local ap = gen.Stats and gen.Stats:FindFirstChild("ActivePlayer")
    if ap and ap.Value ~= LP then
        H.firePrompt(pp, prompt.Position); task.wait(0.2)
        if ap and ap.Value ~= LP then
            setStatus("❌ Prompt failed → retry")
            _currentGen=nil; return
        end
    end

    -- 10. Connect spotted watcher
    task.spawn(function() connectSpottedWatcher(gen) end)

    -- 11. Pipe top
    if CFG.TeleportTop then
        local pipePos = H.genPipeTopPos(gen, CFG.PipeOffsetY)
        if pipePos then
            H.tp(pipePos)
            startPipeKeep(pipePos)
            setStatus("🔝 Extracting from pipe top")
        end
    end

    _extracting = true
end

-- ═══════════════════════════════════════════════════════════════════
--  START / STOP
-- ═══════════════════════════════════════════════════════════════════
local function startFarm()
    if _farmRunning then return end
    _farmRunning = true
    setStatus("🌀 Farm running")
    task.spawn(function()
        while _farmRunning do
            local ok, err = pcall(farmCycle)
            if not ok then setStatus("❗ "..tostring(err):sub(1,55)); task.wait(1) end
            task.wait(CFG.ActionCooldown)
        end
        setStatus("⏹ Stopped")
    end)
end

local function stopFarm()
    _farmRunning=false; CFG.AutoFarm=false
    stopExtractionNow()
end

-- ═══════════════════════════════════════════════════════════════════
--  VISUAL HELPERS
-- ═══════════════════════════════════════════════════════════════════
local _origLighting = {}
local LT = game:GetService("Lighting")

local function fullBright(on)
    if on then
        _origLighting.Brightness      = LT.Brightness
        _origLighting.Ambient         = LT.Ambient
        _origLighting.OutdoorAmbient  = LT.OutdoorAmbient
        LT.Brightness = 2
        LT.Ambient    = Color3.fromRGB(178,178,178)
        LT.OutdoorAmbient = Color3.fromRGB(178,178,178)
    else
        LT.Brightness = _origLighting.Brightness or 1
        LT.Ambient    = _origLighting.Ambient or Color3.fromRGB(70,70,70)
        LT.OutdoorAmbient = _origLighting.OutdoorAmbient or Color3.fromRGB(140,140,140)
    end
end

local function fullBrightAlt(on)
    LT.ClockTime = on and 14 or 6
end

local function noFog(on)
    LT.FogEnd   = on and 1e6  or (_origLighting.FogEnd   or 10000)
    LT.FogStart = on and 1e6  or (_origLighting.FogStart or 0)
end

local _origLighting2 = {}
local function antiLag(on)
    if on then
        -- Remove textures from workspace (surfaces), don't touch scripts
        for _, p in ipairs(workspace:GetDescendants()) do
            if p:IsA("BasePart") then
                pcall(function()
                    p.Material = Enum.Material.SmoothPlastic
                    p.Reflectance = 0
                    p.CastShadow = false
                end)
            elseif p:IsA("Texture") or p:IsA("Decal") then
                p.Transparency = 1
            elseif p:IsA("ParticleEmitter") or p:IsA("Smoke") or p:IsA("Fire") or p:IsA("Sparkles") then
                p.Enabled = false
            end
        end
        LT.GlobalShadows = false
        LT.FogEnd   = 1e6
        LT.FogStart = 1e6
    else
        LT.GlobalShadows = true
    end
end

-- ═══════════════════════════════════════════════════════════════════
--  WIND UI
-- ═══════════════════════════════════════════════════════════════════
local Win = WindUI:CreateWindow({
    Title="Dandy's World", Icon="sprout", Author="AutoFarm v13",
    Size=UDim2.fromOffset(620, 720), Theme="Dark",
    ToggleKey=Enum.KeyCode.RightShift, IgnoreAlerts=true,
})

-- ─── TAB: Automation ─────────────────────────────────────────────
local TA = Win:Tab({ Title="Automation", Icon="bot" })
_statusPara = TA:Paragraph({ Title="Status", Desc="Idle" })

TA:Toggle({ Title="Enable AutoFarm", Icon="play", Value=false,
    Desc="Starts the full loop: encounter → items → extract.",
    Callback=function(v) CFG.AutoFarm=v; if v then startFarm() else stopFarm() end end })
TA:Toggle({ Title="Auto Pickup Items", Icon="package", Value=CFG.AutoPickup,
    Desc="Picks up floor items before extracting. Skips items near twisters or blacklisted ones.",
    Callback=function(v) CFG.AutoPickup=v end })
TA:Toggle({ Title="Auto Use Items (smart)", Icon="pill", Value=CFG.AutoUseItems,
    Desc="Runs every 2s independently. Medkit at 1hp, bandage <3hp, pop when stamina low.",
    Callback=function(v) CFG.AutoUseItems=v end })
TA:Toggle({ Title="Auto Use Ability", Icon="zap", Value=CFG.AutoAbility,
    Desc="Fires ability every 1s when off cooldown and ability button is visible.",
    Callback=function(v) CFG.AutoAbility=v end })
TA:Toggle({ Title="Auto Buy Dandy Shop", Icon="shopping-cart", Value=CFG.AutoBuyShop,
    Desc="Teleports to each shop item and fires its ProximityPrompt when store opens.",
    Callback=function(v) CFG.AutoBuyShop=v end })
TA:Toggle({ Title="Auto Encounter Twisted", Icon="crosshair", Value=CFG.AutoEncounter,
    Desc="At floor start, enters each active twisted's radius. Escapes the moment it spots you.",
    Callback=function(v) CFG.AutoEncounter=v end })
TA:Slider({ Title="Global Action Cooldown (s)", Icon="timer",
    Desc="Minimum delay between farm cycle steps.",
    Value={Min=0.02, Max=0.5, Default=CFG.ActionCooldown}, Step=0.01,
    Callback=function(v) CFG.ActionCooldown=v end })

-- ─── TAB: Utility ─────────────────────────────────────────────────
local TU = Win:Tab({ Title="Utility", Icon="wrench" })
TU:Toggle({ Title="Auto Skillcheck (legit)", Icon="zap", Value=CFG.AutoSkillcheck,
    Desc="Watches marker in RenderStepped and presses Space when it overlaps the target zone.",
    Callback=function(v) CFG.AutoSkillcheck=v; rehookSkillcheck() end })
TU:Toggle({ Title="Instant Skillcheck (hook)", Icon="shield-check", Value=CFG.InstantSkillcheck,
    Desc="Replaces the skillcheck handler to return the best result immediately. Fallback VIM fires Space.",
    Callback=function(v) CFG.InstantSkillcheck=v; rehookSkillcheck() end })
TU:Toggle({ Title="Aim Gold Zone", Icon="star", Value=CFG.AimGold,
    Desc="Returns 'supercomplete' (Great Job!) for hook mode, aims gold area for legit mode.",
    Callback=function(v) CFG.AimGold=v; rehookSkillcheck() end })
TU:Slider({ Title="Skillcheck Press Delay (s)", Icon="timer",
    Desc="Legit mode only: wait this long before pressing Space.",
    Value={Min=0, Max=0.5, Default=CFG.SkillDelay}, Step=0.05,
    Callback=function(v) CFG.SkillDelay=v; rehookSkillcheck() end })
TU:Separator()
TU:Button({ Title="→ Safest Machine", Icon="search",
    Desc="Teleport to the generator furthest from any active twisted.",
    Callback=function()
        local gen=H.pickGenerator(CFG.SafetyBuffer, CFG.IgnoredTwisters)
        if gen then local p=gen:FindFirstChild("Prompt"); if p then H.tp(p.Position+Vector3.new(0,3,0)) end
        else setStatus("⚠ No safe machine found") end
    end })
TU:Button({ Title="Collect All Floor Items", Icon="package",
    Desc="Immediately runs the pickup loop for all items on the floor.",
    Callback=function() _pickedUpItems={}; task.spawn(pickupAllItems) end })
TU:Button({ Title="Stop Extraction", Icon="square",
    Desc="Spams StopInteracting:FireServer('Stop') 5 times to force-stop the machine.",
    Callback=function() stopExtractionNow() end })
TU:Button({ Title="→ Elevator", Icon="door-open",
    Desc="Teleport to the elevator.",
    Callback=function() H.tp(H.elevatorSafePos()) end })
TU:Button({ Title="→ Sky (Y=800)", Icon="cloud",
    Desc="Teleport straight up to safety.",
    Callback=function() H.tp(H.skyPos()) end })
TU:Button({ Title="Force Buy Shop", Icon="shopping-cart",
    Desc="Immediately tries to buy all available Dandy Shop items.",
    Callback=function() task.spawn(autoBuyShop) end })
TU:Button({ Title="Force Use Items", Icon="pill",
    Desc="Uses all appropriate items right now.",
    Callback=function() task.spawn(function() H.useItems(_extracting) end) end })
TU:Button({ Title="Force Use Ability", Icon="zap",
    Desc="Fires ability if off cooldown.",
    Callback=function() task.spawn(H.useAbility) end })
TU:Button({ Title="Check Status", Icon="alert-triangle",
    Desc="Shows health, stamina, chase/spotted/pause state.",
    Callback=function()
        if _panicVal and _panicVal.Value then setStatus("🚨 PANIC!")
        elseif H.isDead() then setStatus("💀 Dead")
        elseif isInPause() then setStatus("⏸ Pause: "..math.ceil(_spottedUntil-tick()).."s")
        elseif H.isBeingChased(CFG.IgnoredTwisters) then setStatus("🏃 Being chased!")
        else setStatus("✅ Safe | hp:"..H.getHealth().."/3 sta:"..math.floor(H.getStamina()*100).."%") end
    end })

-- ─── TAB: Safety ─────────────────────────────────────────────────
local TS = Win:Tab({ Title="Safety", Icon="shield" })
TS:Dropdown({ Title="Safety Mode", Icon="shield", Values={"safe","quick"}, Value="safe",
    Desc="Safe: pause + sky hide when spotted. Quick: immediately find next machine.",
    Callback=function(v) CFG.SafetyMode=v end })
TS:Toggle({ Title="Hide When Chased", Icon="shield", Value=CFG.HideWhenChased,
    Desc="Spam-TPs to sky while a twisted is chasing you. Always stops extraction immediately.",
    Callback=function(v) CFG.HideWhenChased=v; if not v then _chasedLoopActive=false end end })
TS:Toggle({ Title="Dodge Twisteds (sky spam)", Icon="move", Value=CFG.DodgeTwisteds,
    Desc="Random sky coordinates while being chased by ANY twisted.",
    Callback=function(v) CFG.DodgeTwisteds=v end })
TS:Toggle({ Title="Dodge Dangerous Only (Goob/Scraps/Dandy)", Icon="alert-triangle", Value=CFG.DodgeDangerous,
    Desc="Random sky spam only when chased by Goob, Scraps, or Dandy.",
    Callback=function(v) CFG.DodgeDangerous=v end })
TS:Toggle({ Title="Panic → Elevator", Icon="door-open", Value=CFG.PanicElevator,
    Desc="Works even when AutoFarm is off. Spam-TPs to elevator for 5s during panic.",
    Callback=function(v) CFG.PanicElevator=v end })
TS:Toggle({ Title="Teleport to Pipe Top", Icon="arrow-up", Value=CFG.TeleportTop,
    Desc="Teleports to the pipe top after starting extraction and stays there.",
    Callback=function(v) CFG.TeleportTop=v end })
TS:Slider({ Title="Safety Buffer (studs)", Icon="shield",
    Desc="Extra distance beyond the instant radius considered unsafe.",
    Value={Min=0, Max=30, Default=CFG.SafetyBuffer}, Step=1,
    Callback=function(v) CFG.SafetyBuffer=v end })
TS:Slider({ Title="Spotted Pause (s)", Icon="clock",
    Desc="Safe mode: how long to wait in sky after being spotted.",
    Value={Min=1, Max=15, Default=CFG.SpottedPauseDuration}, Step=0.5,
    Callback=function(v) CFG.SpottedPauseDuration=v end })
TS:Slider({ Title="Quick Mode Min Dist (studs)", Icon="alert-triangle",
    Desc="Quick mode: wait if twisted is closer than this before moving to next machine.",
    Value={Min=5, Max=30, Default=CFG.QuickModeMinDist}, Step=1,
    Callback=function(v) CFG.QuickModeMinDist=v end })
TS:Slider({ Title="Pipe Top Offset (Y studs)", Icon="move-up",
    Desc="Extra height above the pipe top.",
    Value={Min=1, Max=20, Default=CFG.PipeOffsetY}, Step=1,
    Callback=function(v) CFG.PipeOffsetY=v end })

-- ─── TAB: Player ─────────────────────────────────────────────────
local TP = Win:Tab({ Title="Player", Icon="user" })
TP:Toggle({ Title="No-Clip (GMM bypass)", Icon="ghost", Value=CFG.NoClip,
    Desc="Phases through walls only. Does NOT add floating — autofarm handles vertical movement.",
    Callback=function(v)
        CFG.NoClip=v
        if v then H.enableNoClip(LP.Character) else H.disableNoClip(LP.Character) end
    end })
TP:Slider({ Title="Walk Speed Buff", Icon="footprints",
    Desc="Added on top of default WalkSpeed (16). 0 = no change.",
    Value={Min=0, Max=50, Default=CFG.WalkSpeedBuff}, Step=1,
    Callback=function(v)
        CFG.WalkSpeedBuff=v
        local c=LP.Character; local h=c and c:FindFirstChild("Humanoid")
        if h then h.WalkSpeed=16+v end
    end })
TP:Slider({ Title="Run Speed Buff", Icon="zap",
    Desc="Applied when LoopRunSpeed is active.",
    Value={Min=0, Max=50, Default=CFG.RunSpeedBuff}, Step=1,
    Callback=function(v) CFG.RunSpeedBuff=v end })
TP:Toggle({ Title="Loop Run Speed", Icon="repeat", Value=CFG.LoopRunSpeed,
    Desc="Continuously sets WalkSpeed to sprint speed (24 + Run Speed Buff).",
    Callback=function(v)
        CFG.LoopRunSpeed=v
        if v then startLoopRun() else stopLoopRun() end
    end })
TP:Toggle({ Title="Spin", Icon="rotate-cw", Value=CFG.Spin,
    Desc="Makes the character spin continuously.",
    Callback=function(v)
        CFG.Spin=v
        if v then startSpin(CFG.SpinSpeed) else stopSpin() end
    end })
TP:Slider({ Title="Spin Speed", Icon="wind",
    Desc="Degrees per Heartbeat tick to spin.",
    Value={Min=1, Max=30, Default=CFG.SpinSpeed}, Step=1,
    Callback=function(v)
        CFG.SpinSpeed=v
        if CFG.Spin then startSpin(v) end
    end })
TP:Toggle({ Title="Tp-Walk", Icon="map-pin", Value=CFG.TpWalk,
    Desc="Replaces walking with small teleport steps in the movement direction.",
    Callback=function(v)
        CFG.TpWalk=v
        if v then startTpWalk() else stopTpWalk() end
    end })

-- ─── TAB: Blacklist ───────────────────────────────────────────────
local TBL = Win:Tab({ Title="Blacklist", Icon="eye-off" })
TBL:Paragraph({ Title="Twisted Blacklist",
    Desc="Ignored in all checks: safety, chased, spotted, encounter, generator picking." })
TBL:Toggle({ Title="Ignore Connie (auto)", Icon="x-circle", Value=true,
    Desc="Always skip Connie-possessed machines. Connie herself is ignored in chased checks.",
    Callback=function(v) CFG.IgnoredTwisters["Connie"]=v and true or nil; CFG.IgnoredTwisters["ConnieMonster"]=v and true or nil end })
TBL:Toggle({ Title="Ignore RnD (if inactive)", Icon="x-circle", Value=false,
    Desc="Skip RnD when LostInterest is true (inactive/in capsule).",
    Callback=function(v) CFG.IgnoredTwisters["RnD"]=v and true or nil; CFG.IgnoredTwisters["RnDMonster"]=v and true or nil end })
TBL:Toggle({ Title="Ignore Rodger (if in capsule)", Icon="x-circle", Value=false,
    Desc="Skip Rodger when LostInterest is true (in capsule).",
    Callback=function(v) CFG.IgnoredTwisters["Rodger"]=v and true or nil; CFG.IgnoredTwisters["RodgerMonster"]=v and true or nil end })
TBL:Separator()
TBL:Paragraph({ Title="Item Blacklist", Desc="Skipped during auto-pickup." })
TBL:Toggle({ Title="Skip Bandages", Icon="x-circle", Value=false,
    Callback=function(v) CFG.IgnoredItems["Bandage"]=v and true or nil end })
TBL:Toggle({ Title="Skip Medkits", Icon="x-circle", Value=false,
    Callback=function(v) CFG.IgnoredItems["Medkit"]=v and true or nil end })
TBL:Toggle({ Title="Skip Pop", Icon="x-circle", Value=false,
    Callback=function(v) CFG.IgnoredItems["Pop"]=v and true or nil end })
TBL:Toggle({ Title="Skip Instructions", Icon="x-circle", Value=false,
    Callback=function(v) CFG.IgnoredItems["Instructions"]=v and true or nil end })
TBL:Toggle({ Title="Skip Stopwatch", Icon="x-circle", Value=false,
    Callback=function(v) CFG.IgnoredItems["Stopwatch"]=v and true or nil end })

-- ─── TAB: Visual ─────────────────────────────────────────────────
local TV = Win:Tab({ Title="Visual", Icon="eye" })
TV:Toggle({ Title="Full Bright", Icon="sun", Value=false,
    Desc="Sets max brightness and ambient lighting.",
    Callback=function(v) fullBright(v) end })
TV:Toggle({ Title="Full Bright Alt (daytime)", Icon="cloud-sun", Value=false,
    Desc="Forces clock time to 2pm for natural daylight.",
    Callback=function(v) fullBrightAlt(v) end })
TV:Toggle({ Title="No-Fog", Icon="wind", Value=false,
    Desc="Sets FogEnd and FogStart to 1,000,000 to remove fog.",
    Callback=function(v) noFog(v) end })
TV:Toggle({ Title="Anti-Lag", Icon="cpu", Value=false,
    Desc="Removes textures/particles/shadows/fog. Does NOT touch scripts or game logic.",
    Callback=function(v) antiLag(v) end })

-- ─── TAB: Config ─────────────────────────────────────────────────
local TC = Win:Tab({ Title="Config", Icon="settings" })
TC:Paragraph({ Title="Configuration Manager",
    Desc="Save and load all toggles, sliders, and settings to/from "..CONFIG_PATH..". Stored in your executor's workspace folder." })
TC:Button({ Title="💾 Save Config", Icon="save",
    Desc="Writes current CFG to "..CONFIG_PATH..".",
    Callback=function()
        saveConfig()
        setStatus("💾 Config saved to "..CONFIG_PATH)
    end })
TC:Button({ Title="📂 Load Config", Icon="folder-open",
    Desc="Reads "..CONFIG_PATH.." and applies all saved values. Reload script to see UI changes.",
    Callback=function()
        loadConfig()
        setStatus("📂 Config loaded — restart script to update UI")
    end })
TC:Button({ Title="🧹 Optimize Config", Icon="trash-2",
    Desc="Removes empty or default-value entries from the saved config file.",
    Callback=function()
        optimizeConfig()
        setStatus("🧹 Config optimized and saved")
    end })
TC:Button({ Title="🗑 Delete Config", Icon="x",
    Desc="Permanently deletes the saved config file.",
    Callback=function()
        pcall(function() delfile(CONFIG_PATH) end)
        setStatus("🗑 Config deleted")
    end })

-- Set Connie ignore on by default
CFG.IgnoredTwisters["Connie"]        = true
CFG.IgnoredTwisters["ConnieMonster"] = true

WindUI:Notify({ Title="Dandy's World v13", Content="Loaded! RightShift = toggle UI.", Duration=4, Icon="sprout" })
