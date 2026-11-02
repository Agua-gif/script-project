-- ═══════════════════════════════════════════════════════════════════
--  Dandy's World Helpers v13
--  Upload to: https://gitlab.com/hello-world395023/legacy-world/-/raw/main/helpers/main-helper
--  All paths confirmed from live GMM decompile + eval testing
-- ═══════════════════════════════════════════════════════════════════
local H = {}

local RS  = game:GetService("RunService")
local RES = game:GetService("ReplicatedStorage")
local PLR = game:GetService("Players")
local LP  = PLR.LocalPlayer

H.LP     = LP
H.RS     = RS
H.RES    = RES
H.Events = RES:WaitForChild("Events")

-- ── NOCLIP STATE ─────────────────────────────────────────────────
-- v13: noclip ONLY phases through walls (CanCollide=false).
-- NO BodyPosition — autofarm handles vertical movement separately.
local _noclipConn = nil

local function disconnectGMMWatchers(char)
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp then
        for _, sig in ipairs({"CanCollide","CanQuery","CanTouch"}) do
            pcall(function()
                for _, c in ipairs(getconnections(hrp:GetPropertyChangedSignal(sig))) do
                    if c.LuaConnection and not c.ForeignState then c:Disconnect() end
                end
            end)
        end
    end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            pcall(function()
                for _, c in ipairs(getconnections(p:GetPropertyChangedSignal("CollisionGroup"))) do
                    if c.LuaConnection and not c.ForeignState then c:Disconnect() end
                end
            end)
        end
    end
end

function H.enableNoClip(char)
    if not char then return end
    disconnectGMMWatchers(char)
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then pcall(function() p.CanCollide = false end) end
    end
    if _noclipConn then _noclipConn:Disconnect() end
    _noclipConn = RS.Heartbeat:Connect(function()
        local c = LP.Character
        if not c then return end
        for _, p in ipairs(c:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then
                pcall(function() p.CanCollide = false end)
            end
        end
    end)
end

function H.disableNoClip(char)
    if _noclipConn then _noclipConn:Disconnect(); _noclipConn = nil end
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then pcall(function() p.CanCollide = true end) end
    end
end

-- ── BASIC ─────────────────────────────────────────────────────────
function H.getHRP()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end

function H.tp(pos)
    local hrp = H.getHRP()
    if hrp then hrp.CFrame = CFrame.new(pos) end
end

function H.getRoom()
    return workspace.CurrentRoom:FindFirstChildOfClass("Model")
end

function H.getMonsters()
    local room = H.getRoom()
    if not room then return {} end
    local f = room:FindFirstChild("Monsters")
    return f and f:GetChildren() or {}
end

function H.getGenerators()
    local room = H.getRoom()
    if not room then return {} end
    local f = room:FindFirstChild("Generators")
    return f and f:GetChildren() or {}
end

function H.elevatorSafePos()
    local ok, elev = pcall(function() return workspace.Elevators.Elevator end)
    if ok and elev and elev.PrimaryPart then
        return elev.PrimaryPart.Position + Vector3.new(0, 10, 0)
    end
    return Vector3.new(0, 500, 0)
end

function H.skyPos()
    local hrp = H.getHRP()
    return Vector3.new(hrp and hrp.Position.X or 0, 800, hrp and hrp.Position.Z or 0)
end

-- ── DEATH CHECK ───────────────────────────────────────────────────
function H.isDead()
    local c   = LP.Character
    local hum = c and c:FindFirstChild("Humanoid")
    return hum == nil or hum.Health <= 0
end

-- ── HEALTH / STAMINA ──────────────────────────────────────────────
function H.getHealth()
    local igs   = workspace.InGamePlayers:FindFirstChild(LP.Name)
    local stats = igs and igs:FindFirstChild("Stats")
    local h     = stats and stats:FindFirstChild("Health")
    return h and h.Value or 3
end

function H.getStamina()
    local sg = LP.PlayerGui:FindFirstChild("ScreenGui")
    if not sg then return 1 end
    local sf = sg:FindFirstChild("Menu") and sg.Menu:FindFirstChild("StaminaFrame")
    local ca = sf and sf:FindFirstChild("CurrentAmount")
    return ca and ca.Size.X.Scale or 1
end

-- ── SPEED ─────────────────────────────────────────────────────────
function H.setWalkSpeed(speed)
    local c   = LP.Character
    local hum = c and c:FindFirstChild("Humanoid")
    if hum then hum.WalkSpeed = speed end
end

function H.setJumpPower(power)
    local c   = LP.Character
    local hum = c and c:FindFirstChild("Humanoid")
    if hum then hum.JumpPower = power end
end

-- ── MONSTER ───────────────────────────────────────────────────────
function H.getRadii(monster)
    local chaser = monster:FindFirstChild("Chaser")
    if chaser then
        local ir = chaser:FindFirstChild("InstantRadius")
        local vr = chaser:FindFirstChild("VisionRadius")
        return { instant=(ir and ir.Value) or 30, los=(vr and vr.Value) or 65 }
    end
    return { instant=30, los=65 }
end

function H.nearestMonsterDist(pos, ignoredNames)
    local minDist = math.huge
    for _, m in ipairs(H.getMonsters()) do
        if not (ignoredNames and ignoredNames[m.Name]) then
            local hrp = m:FindFirstChild("HumanoidRootPart")
            if hrp then
                local r = H.getRadii(m)
                local d = (hrp.Position - pos).Magnitude - r.instant
                if d < minDist then minDist = d end
            end
        end
    end
    return minDist
end

-- isBeingChased: reads Chaser.ChasingValue confirmed from GMM decompile
-- Returns: chased (bool), chaserModel (Model or nil)
function H.isBeingChased(ignoredNames)
    for _, m in ipairs(H.getMonsters()) do
        if not (ignoredNames and ignoredNames[m.Name]) then
            local chaser = m:FindFirstChild("Chaser")
            if chaser then
                local cv = chaser:FindFirstChild("ChasingValue")
                if cv and cv.Value == LP then return true, m end
            end
            local cv2 = m:FindFirstChild("ChasingValue")
            if cv2 and cv2.Value == LP then return true, m end
        end
    end
    return false, nil
end

-- isDangerousTwisted: Goob, Scraps, Dandy
local DANGEROUS = { Goob=true, Scraps=true, Dandy=true,
                    GoobMonster=true, ScrapsMonster=true, DandyMonster=true }
function H.isDangerousTwisted(monsterName)
    return DANGEROUS[monsterName] == true
end

-- isSpottedAtGen: gen.Stats BoolValues (e.g. "Connie") confirmed from live decompile
function H.isSpottedAtGen(gen, ignoredNames)
    local stats = gen and gen:FindFirstChild("Stats")
    if not stats then return false end
    for _, c in ipairs(stats:GetChildren()) do
        if c:IsA("BoolValue") and c.Name ~= "SkillCheck" and c.Name ~= "Completed" then
            if c.Value and not (ignoredNames and ignoredNames[c.Name]) then
                return true, c.Name
            end
        end
    end
    return false
end

-- isGenConniePossessed: gen.Stats.Connie == true means Connie is on this machine
function H.isGenConniePossessed(gen)
    local stats = gen and gen:FindFirstChild("Stats")
    local c = stats and stats:FindFirstChild("Connie")
    return c and c.Value == true
end

-- isMonsterActive: checks LostInterest BoolValue (confirmed live on each monster)
-- Rodger inactive = LostInterest.Value == true AND monster name contains "Rodger"
-- RND inactive = same pattern
function H.isMonsterActive(monster)
    local li = monster:FindFirstChild("LostInterest")
    if li and li.Value == true then return false end
    -- Also check Chaser.Chasing BoolValue
    local chaser  = monster:FindFirstChild("Chaser")
    local chasing = chaser and chaser:FindFirstChild("Chasing")
    -- A monster with no chaser is considered inactive
    if not chaser then return false end
    return true
end

function H.isSafe(pos, safetyBuffer, hideWhenChased, ignoredNames)
    if hideWhenChased and H.isBeingChased(ignoredNames) then return false end
    for _, m in ipairs(H.getMonsters()) do
        if not (ignoredNames and ignoredNames[m.Name]) then
            local hrp = m:FindFirstChild("HumanoidRootPart")
            if hrp then
                local r = H.getRadii(m)
                if (hrp.Position - pos).Magnitude < (r.instant + (safetyBuffer or 5)) then
                    return false
                end
            end
        end
    end
    return true
end

-- ── GENERATOR ─────────────────────────────────────────────────────
function H.genDone(gen)
    local c = gen.Stats and gen.Stats:FindFirstChild("Completed")
    return c and c.Value == true
end

function H.genOccupied(gen)
    local ap = gen.Stats and gen.Stats:FindFirstChild("ActivePlayer")
    return ap and ap.Value ~= nil
end

function H.genPipeTopPos(gen, offsetY)
    offsetY = offsetY or 7
    local model = gen:FindFirstChild("Model")
    if model then
        local pipe = model:FindFirstChild("Pipe", true)
        if pipe and pipe:IsA("BasePart") then
            return pipe.Position + Vector3.new(0, pipe.Size.Y/2 + offsetY, 0)
        end
        local bestY, bestPos = -math.huge, nil
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") then
                local top = p.Position.Y + p.Size.Y/2
                if top > bestY then bestY=top; bestPos=p.Position+Vector3.new(0,p.Size.Y/2,0) end
            end
        end
        if bestPos then return bestPos + Vector3.new(0, offsetY, 0) end
    end
    local tp2 = gen:FindFirstChild("TeleportPositions")
    if tp2 then
        local tpp = tp2:FindFirstChild("TeleportPosition")
        if tpp then return tpp.Position + Vector3.new(0, offsetY+4, 0) end
    end
    return nil
end

function H.pickGenerator(safetyBuffer, ignoredNames)
    safetyBuffer = safetyBuffer or 5
    local anyIncomplete, allOccupied = false, true
    local best, bestScore = nil, -math.huge
    for _, gen in ipairs(H.getGenerators()) do
        if not H.genDone(gen) then
            anyIncomplete = true
            -- Skip Connie-possessed machines
            if H.isGenConniePossessed(gen) then continue end
            if not H.genOccupied(gen) then
                allOccupied = false
                local origin = gen:FindFirstChild("Origin")
                if origin then
                    local score = H.nearestMonsterDist(origin.Position, ignoredNames)
                    if score >= safetyBuffer and score > bestScore then
                        bestScore=score; best=gen
                    end
                end
            end
        end
    end
    if not anyIncomplete then return nil,"ALL_DONE"    end
    if best             then return best,"OK"          end
    if allOccupied      then return nil,"ALL_OCCUPIED" end
    return nil,"UNSAFE"
end

-- ── PROXIMITY PROMPT ──────────────────────────────────────────────
function H.findPrompt(inst)
    if not inst then return nil end
    if inst:IsA("ProximityPrompt") and inst.Enabled then return inst end
    for _, d in ipairs(inst:GetDescendants()) do
        if d:IsA("ProximityPrompt") and d.Enabled then return d end
    end
    return nil
end

function H.firePrompt(pp, promptPartPos)
    if not pp or not pp.Parent or not pp.Enabled then return false end
    local hrp = H.getHRP()
    if not hrp then return false end
    local targetPos = promptPartPos or pp.Parent.Position
    if (hrp.Position - targetPos).Magnitude > (pp.MaxActivationDistance - 1) then
        H.tp(targetPos + Vector3.new(0, 2, 0))
        task.wait(0.03)
    end
    for i = 1, 20 do
        if not pp or not pp.Parent or not pp.Enabled then break end
        pcall(fireproximityprompt, pp)
    end
    return true
end

-- ── ANTI-CHEAT ────────────────────────────────────────────────────
function H.setupAC()
    local Events = H.Events
    -- __namecall hook: block AntiCheatTrigger:FireServer
    local mt = getrawmetatable(game)
    local oldNC = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = function(self, ...)
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            local ok, name = pcall(function() return self.Name end)
            if ok and name == "AntiCheatTrigger" then return nil end
        end
        return oldNC(self, ...)
    end
    setreadonly(mt, true)

    local function nukeAC(c)
        task.defer(function() pcall(game.Destroy, c) end)
    end
    local existing = Events:FindFirstChild("AntiCheatTrigger")
    if existing then nukeAC(existing) end
    Events.ChildAdded:Connect(function(c)
        if c.Name == "AntiCheatTrigger" then nukeAC(c) end
    end)
    pcall(function()
        local cps = Events:FindFirstChild("CheckPlayerSpeed")
        if cps then cps.OnClientInvoke = function() return true end end
    end)
    pcall(function()
        local tpEv = Events:FindFirstChild("Teleport")
        if tpEv and tpEv.ClassName == "RemoteEvent" then
            tpEv.OnClientEvent:Connect(function() end)
        end
    end)
end

-- ── SKILLCHECK (v13) ──────────────────────────────────────────────
-- Strategy:
--   1. Replace OnClientInvoke → returns immediately, hides frame, plays sound
--   2. Watch SkillCheckFrame.Visible → if frame appears (race condition), 
--      use legit VIM Space key aimed at gold zone as fallback
-- This ensures the native skillcheck system is NOT broken:
-- returning from OnClientInvoke before the frame tweens in prevents GMM
-- from entering its "wait for Space" loop entirely.
function H.hookSkillcheck(aimGold)
    local SCRF   = H.Events:FindFirstChild("SkillcheckUpdate")
    if not SCRF  then return function() end end
    local active = true
    local VIM    = game:GetService("VirtualInputManager")

    local function ourHook(a1, a2, a3)
        if not a1 then return "noinput" end
        -- Immediately hide frame to prevent flash
        pcall(function()
            local sg   = LP.PlayerGui:FindFirstChild("ScreenGui")
            local menu = sg and sg:FindFirstChild("Menu")
            if not menu then return end
            local scf = menu:FindFirstChild("SkillCheckFrame")
            local cal = menu:FindFirstChild("Calibrate")
            local sbt = menu:FindFirstChild("SpaceBarPromptText")
            if scf then scf.Visible = false end
            if cal then cal.Visible = false end
            if sbt then sbt.Visible = false end
            -- Show success message
            local msg = menu:FindFirstChild("SkillCheckMessage")
            if msg then
                msg.Text = aimGold and "Great Job!" or "Good Job!"
                local g  = msg:FindFirstChild("UIGradient")
                local gw = msg:FindFirstChild("UIGradientWin")
                if g  then g.Enabled  = not aimGold end
                if gw then gw.Enabled = aimGold      end
                msg.Visible=true; msg.TextTransparency=0; msg.TextStrokeTransparency=0
                task.delay(1.5, function()
                    pcall(function()
                        game:GetService("TweenService"):Create(msg,
                            TweenInfo.new(1, Enum.EasingStyle.Quad),
                            {TextTransparency=1, TextStrokeTransparency=1}):Play()
                        task.wait(1); msg.Visible=false
                    end)
                end)
            end
            local snd = sg:FindFirstChild(aimGold and "GoldAreaHit" or "Correct")
            if snd then pcall(function() snd:Stop(); snd:Play() end) end
        end)
        return aimGold and "supercomplete" or true
    end

    -- Tight re-hook (0.1s)
    task.spawn(function()
        while active do
            pcall(function()
                if SCRF.OnClientInvoke ~= ourHook then
                    SCRF.OnClientInvoke = ourHook
                end
            end)
            task.wait(0.1)
        end
    end)

    -- Frame watcher: legit VIM fallback if frame appears anyway
    local frameConn = nil
    local function watchFrame()
        local sg  = LP.PlayerGui:FindFirstChild("ScreenGui")
        local menu = sg and sg:FindFirstChild("Menu")
        local scf  = menu and menu:FindFirstChild("SkillCheckFrame")
        if not scf then return end
        if frameConn then frameConn:Disconnect() end
        frameConn = scf:GetPropertyChangedSignal("Visible"):Connect(function()
            if not active or not scf.Visible then return end
            task.spawn(function()
                for i = 1, 15 do
                    if not scf.Visible then break end
                    local marker = scf:FindFirstChild("Marker")
                    local gold   = scf:FindFirstChild("GoldArea")
                    local req    = scf:FindFirstChild("RequiredArea")
                    local target = gold or req
                    if marker and target then
                        local mX = marker.Position.X.Scale
                        local tX = target.Position.X.Scale
                        local tW = target.Size.X.Scale
                        if mX >= tX and mX <= tX + tW then
                            pcall(function()
                                VIM:SendKeyEvent(true,  Enum.KeyCode.Space, false, game)
                                task.wait(0.02)
                                VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                            end)
                            break
                        end
                    end
                    task.wait(0.04)
                end
            end)
        end)
    end

    watchFrame()
    LP.CharacterAdded:Connect(function()
        task.wait(0.3)
        if active then
            SCRF.OnClientInvoke = ourHook
            watchFrame()
        end
    end)
    H.Events.ChildAdded:Connect(function(c)
        pcall(function()
            if c.Name == "SkillcheckUpdate" then
                SCRF = c; task.wait(0.05)
                SCRF.OnClientInvoke = ourHook
            end
        end)
    end)

    return function()
        active = false
        if frameConn then frameConn:Disconnect() end
        pcall(function() SCRF.OnClientInvoke = nil end)
    end
end

-- ── LEGIT SKILLCHECK (separate, always-on RenderStepped watcher) ──
-- Returns a disconnect function. Call this alongside or instead of hook.
function H.startLegitSkillcheck(aimGold, delaySeconds)
    local VIM     = game:GetService("VirtualInputManager")
    local pressed = false
    local conn    = RS.RenderStepped:Connect(function()
        local sg  = LP.PlayerGui:FindFirstChild("ScreenGui")
        local menu = sg and sg:FindFirstChild("Menu")
        local scf  = menu and menu:FindFirstChild("SkillCheckFrame")
        if not scf or not scf.Visible then pressed=false; return end
        local marker = scf:FindFirstChild("Marker")
        local req    = scf:FindFirstChild("RequiredArea")
        local gold   = scf:FindFirstChild("GoldArea")
        if not (marker and req) then return end
        local target = (aimGold and gold) and gold or req
        local mX = marker.Position.X.Scale
        local tX = target.Position.X.Scale
        local tW = target.Size.X.Scale
        if mX >= tX and mX <= tX + tW then
            if not pressed then
                pressed = true
                task.delay(delaySeconds or 0, function()
                    pcall(function()
                        VIM:SendKeyEvent(true,  Enum.KeyCode.Space, false, game)
                        VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
                    end)
                end)
            end
        else
            pressed = false
        end
    end)
    return function() conn:Disconnect() end
end

-- ── STOP EXTRACTION ───────────────────────────────────────────────
-- Events.StopInteracting is the GLOBAL RemoteEvent (confirmed live)
function H.stopExtraction()
    local si = H.Events:FindFirstChild("StopInteracting")
    if not si then return end
    for i = 1, 5 do
        pcall(function() si:FireServer("Stop") end)
        task.wait(0.03)
    end
end

-- ── ABILITY ───────────────────────────────────────────────────────
function H.canUseAbility()
    local char = LP.Character
    if not char then return false end
    local sg  = LP.PlayerGui:FindFirstChild("ScreenGui")
    local ab1 = sg and sg:FindFirstChild("Ability1")
    if not ab1 or not ab1.Visible then return false end
    local abilities = char:FindFirstChild("Abilities")
    local ab1f      = abilities and abilities:FindFirstChild("Ability1")
    local cd        = ab1f and ab1f:FindFirstChild("CurrentCooldown")
    return not (cd and cd.Value ~= 0)
end

function H.useAbility()
    if not H.canUseAbility() then return false end
    local char = LP.Character
    local hrp  = H.getHRP()
    if not char or not hrp then return false end
    local abEv = H.Events:FindFirstChild("AbilityEvent")
    if not abEv then return false end
    pcall(function() abEv:InvokeServer(char, 1, hrp.Position) end)
    return true
end

-- ── ITEM USE ──────────────────────────────────────────────────────
-- extracting=true allows machine items (instructions/stopwatch)
function H.useItems(extracting)
    local char = LP.Character
    if not char then return end
    local inv    = char:FindFirstChild("Inventory")
    if not inv   then return end
    local itemEv = H.Events:FindFirstChild("ItemEvent")
    if not itemEv then return end
    local health  = H.getHealth()
    local stamina = H.getStamina()
    for _, slotName in ipairs({"Slot1","Slot2","Slot3"}) do
        local slot = inv:FindFirstChild(slotName)
        if slot and slot.Value and slot.Value ~= "" and slot.Value ~= "None" then
            local item = slot.Value:lower()
            local use  = false
            if     item:find("medkit")      then use = health == 1
            elseif item:find("bandage")     then use = health < 3
            elseif item:find("pop") or item:find("soda") or item:find("bottle") then
                                                 use = stamina < 0.99
            elseif item:find("instruction") or item:find("stopwatch") then
                                                 use = extracting == true
            else                                 use = true end
            if use then
                for i = 1, 3 do
                    pcall(function() itemEv:InvokeServer(char, slot) end)
                    task.wait(0.05)
                end
            end
        end
    end
end

-- ── SHOP BUY ──────────────────────────────────────────────────────
-- DandyStore.Items populates when DandyStoreOpen=true
function H.buyShopItems()
    local store = workspace.Elevators.Elevator:FindFirstChild("DandyStore")
    if not store then return end
    local items = store:FindFirstChild("Items")
    if not items then return end
    for _, item in ipairs(items:GetChildren()) do
        local pp = H.findPrompt(item)
        if pp and pp.Enabled then
            local root = item:FindFirstChildWhichIsA("BasePart") or (item:IsA("BasePart") and item)
            local pos  = root and root.Position or item:GetPivot().Position
            H.tp(pos + Vector3.new(0, 2, 0))
            task.wait(0.05)
            H.firePrompt(pp, pos)
            task.wait(0.1)
        end
    end
end

return H
