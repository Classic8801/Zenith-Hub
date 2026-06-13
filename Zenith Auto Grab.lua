local CONFIG = {
    AUTO_STEAL_ENABLED = true,
    HOLD_MIN = 1.3,
    HOLD_MAX = 2.6,
    ENTRY_DELAY = 0.3,
    COOLDOWN = 0.05,
    STEAL_RANGE = 7,
    PRIME_RANGE = 61,
}

local Players   = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats     = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer
local plots = workspace:WaitForChild("Plots")

local Packages   = ReplicatedStorage:WaitForChild("Packages")
local Datas      = ReplicatedStorage:WaitForChild("Datas")
local AnimalsData = require(Datas:WaitForChild("Animals"))

-- ── SYNC CHANNELS ────────────────────────────────────────────
local syncRemotes = (function()
    local folder = Packages:WaitForChild("Synchronizer")
    return {
        channelFolder = folder:WaitForChild("Channel"),
        routeRemote   = folder:WaitForChild("CommunicationRoute"),
        requestData   = folder:FindFirstChild("RequestData"),
    }
end)()

local plotAnimalSync = { caches = {}, connections = {} }

local function splitSyncPath(path)
    if typeof(path) == "table" then return path end
    local out = {}
    for part in string.gmatch(tostring(path), "[^%.]+") do
        table.insert(out, tonumber(part) or part)
    end
    return out
end

local function resolveSyncPath(path, root)
    local current, parent, key = root, nil, nil
    for _, part in ipairs(splitSyncPath(path)) do
        parent  = current
        key     = part
        current = current and current[part] or nil
    end
    return current, parent, key
end

local function applyPlotSyncDiff(channelName, packet)
    local cache = plotAnimalSync.caches[channelName]
    if typeof(cache) ~= "table" then return end
    local path, action, a, b = packet[1], packet[2], packet[3], packet[4]
    local current, parent, key = resolveSyncPath(path, cache)
    if action == "Changed" then
        if parent ~= nil then parent[key] = a end
    elseif action == "ArrayInsert" then
        if current ~= nil then table.insert(current, b, a) end
    elseif action == "ArrayRemoved" then
        if current ~= nil then table.remove(current, b) end
    elseif action == "DictionaryInsert" then
        if current ~= nil then current[b] = a end
    elseif action == "DictionaryRemoved" then
        if current ~= nil then current[b] = nil end
    end
end

local function attachPlotChannel(remote)
    if plotAnimalSync.connections[remote] then return end
    local channelName = tostring(remote.Name)
    if not plots:FindFirstChild(channelName) then return end
    if syncRemotes.requestData and plotAnimalSync.caches[channelName] == nil then
        local ok, data = pcall(function()
            return syncRemotes.requestData:InvokeServer(channelName)
        end)
        plotAnimalSync.caches[channelName] = (ok and typeof(data) == "table") and data or {}
    elseif plotAnimalSync.caches[channelName] == nil then
        plotAnimalSync.caches[channelName] = {}
    end
    plotAnimalSync.connections[remote] = remote.OnClientEvent:Connect(function(queue)
        for _, packet in ipairs(queue) do
            applyPlotSyncDiff(channelName, packet)
        end
    end)
end

local function detachPlotChannel(channelName)
    for remote, conn in pairs(plotAnimalSync.connections) do
        if tostring(remote.Name) == tostring(channelName) then
            conn:Disconnect()
            plotAnimalSync.connections[remote] = nil
            plotAnimalSync.caches[tostring(channelName)] = nil
            break
        end
    end
end

for _, child in ipairs(syncRemotes.channelFolder:GetChildren()) do
    if child:IsA("RemoteEvent") then attachPlotChannel(child) end
end
syncRemotes.channelFolder.ChildAdded:Connect(function(child)
    if child:IsA("RemoteEvent") then attachPlotChannel(child) end
end)
syncRemotes.routeRemote.OnClientEvent:Connect(function(actions)
    for _, action in ipairs(actions) do
        local kind, channelName = action[1], tostring(action[2])
        if not plots:FindFirstChild(channelName) then continue end
        if kind == "ListenerAdded" then
            local remote = syncRemotes.channelFolder:FindFirstChild(channelName)
            if remote and remote:IsA("RemoteEvent") then attachPlotChannel(remote) end
        elseif kind == "ListenerRemoved" then
            detachPlotChannel(channelName)
        end
    end
end)

local function getPlotChannelData(plotName)
    return plotAnimalSync.caches[plotName]
end

-- ── STEAL STATE & CACHES ─────────────────────────────────────
local allAnimalsCache  = {}
local PromptMemoryCache = {}
local InternalStealCache = {}
local stealConnection  = nil

local StealState = {
    active          = false,
    startTime       = 0,
    waitingTime     = 0,
    phase           = "idle",
    label           = "",
    lastResult      = "",
    lastResultTime  = 0,
    totalSteals     = 0,
    failedSteals    = 0,
}

-- ── HELPERS ───────────────────────────────────────────────────
local function getPlotOwner(plot)
    local sign  = plot:FindFirstChild("PlotSign")
    local frame = sign and sign:FindFirstChild("SurfaceGui") and sign.SurfaceGui:FindFirstChild("Frame")
    local label = frame and frame:FindFirstChild("TextLabel")
    if not label or label.Text == "Empty Base" then return nil end
    return label.Text:gsub("'s [Bb]ase$", ""):gsub("%s+$", "")
end

local function isMyBaseAnimal(animalData)
    if not animalData or not animalData.plot then return false end
    local plot = plots:FindFirstChild(animalData.plot)
    if not plot then return false end
    return getPlotOwner(plot) == lp.DisplayName
end

local function findProximityPromptForAnimal(animalData)
    if not animalData then return nil end
    local cached = PromptMemoryCache[animalData.uid]
    if cached and cached.Parent then return cached end
    local plot = workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(animalData.slot)
    if not podium then return nil end
    local base  = podium:FindFirstChild("Base")
    if not base then return nil end
    local spawn = base:FindFirstChild("Spawn")
    if not spawn then return nil end
    local attach = spawn:FindFirstChild("PromptAttachment")
    if not attach then return nil end
    for _, p in ipairs(attach:GetChildren()) do
        if p:IsA("ProximityPrompt") then
            PromptMemoryCache[animalData.uid] = p
            return p
        end
    end
    return nil
end

local function getAnimalPosition(animalData)
    local plot = workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return nil end
    local podiums = plot:FindFirstChild("AnimalPodiums")
    if not podiums then return nil end
    local podium = podiums:FindFirstChild(animalData.slot)
    if not podium then return nil end
    return podium:GetPivot().Position
end

local function distToAnimal(animalData)
    local character = lp.Character
    if not character then return math.huge end
    local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("UpperTorso")
    if not hrp then return math.huge end
    local pos = getAnimalPosition(animalData)
    if not pos then return math.huge end
    return (hrp.Position - pos).Magnitude
end

local function pickClosest()
    local character = lp.Character
    if not character then return nil end
    local hrp = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("UpperTorso")
    if not hrp then return nil end
    local best, bestDist = nil, math.huge
    for _, animalData in ipairs(allAnimalsCache) do
        if isMyBaseAnimal(animalData) then continue end
        local pos = getAnimalPosition(animalData)
        if not pos then continue end
        local dist = (hrp.Position - pos).Magnitude
        if dist > CONFIG.PRIME_RANGE then continue end
        if dist < bestDist then bestDist = dist; best = animalData end
    end
    return best
end

local function buildStealCallbacks(prompt)
    if InternalStealCache[prompt] then return end
    local data = { holdCallbacks = {}, triggerCallbacks = {}, ready = true }
    local ok1, conns1 = pcall(getconnections, prompt.PromptButtonHoldBegan)
    if ok1 and type(conns1) == "table" then
        for _, conn in ipairs(conns1) do
            if type(conn.Function) == "function" then
                table.insert(data.holdCallbacks, conn.Function)
            end
        end
    end
    local ok2, conns2 = pcall(getconnections, prompt.Triggered)
    if ok2 and type(conns2) == "table" then
        for _, conn in ipairs(conns2) do
            if type(conn.Function) == "function" then
                table.insert(data.triggerCallbacks, conn.Function)
            end
        end
    end
    if (#data.holdCallbacks > 0) or (#data.triggerCallbacks > 0) then
        InternalStealCache[prompt] = data
    end
end

local function executeStealAsync(prompt, animalData)
    local data = InternalStealCache[prompt]
    if not data or not data.ready then return false end
    data.ready = false
    local label = animalData.name or "Animal"
    StealState.active    = true
    StealState.startTime = tick()
    StealState.phase     = "holding"
    StealState.label     = label
    task.spawn(function()
        for _, fn in ipairs(data.holdCallbacks) do task.spawn(fn) end
        task.wait(CONFIG.HOLD_MIN)
        StealState.phase = "waitingRange"
        StealState.waitingTime = tick()
        local alreadyInRange = distToAnimal(animalData) <= CONFIG.STEAL_RANGE
        local fired = false
        while true do
            local elapsed = tick() - StealState.startTime
            if elapsed > CONFIG.HOLD_MAX then break end
            if not prompt.Parent then break end
            if distToAnimal(animalData) <= CONFIG.STEAL_RANGE then
                if not alreadyInRange then task.wait(CONFIG.ENTRY_DELAY) end
                for _, fn in ipairs(data.triggerCallbacks) do task.spawn(fn) end
                fired = true
                break
            end
            task.wait()
        end
        if fired then
            StealState.totalSteals  = StealState.totalSteals + 1
            StealState.lastResult   = "Stole " .. label
        else
            StealState.failedSteals = StealState.failedSteals + 1
            StealState.lastResult   = "Missed: " .. label
        end
        StealState.active         = false
        StealState.phase          = "idle"
        StealState.lastResultTime = tick()
        task.wait(CONFIG.COOLDOWN)
        data.ready = true
    end)
    return true
end

local function attemptSteal(prompt, animalData)
    if not prompt or not prompt.Parent then return false end
    buildStealCallbacks(prompt)
    if not InternalStealCache[prompt] then return false end
    return executeStealAsync(prompt, animalData)
end

local function scanAllPlots()
    local newCache = {}
    for _, plot in ipairs(plots:GetChildren()) do
        local cache = getPlotChannelData(plot.Name)
        if not cache then continue end
        local animalList = cache.AnimalList
        if typeof(animalList) ~= "table" then continue end
        for slot, animalData in pairs(animalList) do
            if type(animalData) == "table" then
                local animalName = animalData.Index
                local animalInfo = AnimalsData[animalName]
                if not animalInfo then continue end
                table.insert(newCache, {
                    name = animalInfo.DisplayName or animalName,
                    plot = plot.Name,
                    slot = tostring(slot),
                    uid  = plot.Name .. "_" .. tostring(slot),
                })
            end
        end
    end
    allAnimalsCache = newCache
    return #allAnimalsCache
end

local function startAutoSteal()
    if stealConnection then return end
    stealConnection = RunService.Heartbeat:Connect(function()
        if not CONFIG.AUTO_STEAL_ENABLED then return end
        if StealState.active then return end
        local target = pickClosest()
        if not target then return end
        local prompt = PromptMemoryCache[target.uid]
        if not prompt or not prompt.Parent then
            prompt = findProximityPromptForAnimal(target)
        end
        if prompt then attemptSteal(prompt, target) end
    end)
end

local function stopAutoSteal()
    if not stealConnection then return end
    stealConnection:Disconnect()
    stealConnection = nil
end

-- ── GUI (v3 zenith bar) ───────────────────────────────────────
local progressFill  = nil
local percentLabel  = nil
local pingLabel     = nil
local fpsLabel      = nil
local pingDot       = nil
local stealLabel    = nil
local neonStroke    = nil
local glowFrame     = nil

local function updateTopBar()
    if not pingLabel or not fpsLabel then return end
    local fps         = 60
    local ping        = 0
    local framesCount = 0
    local last        = tick()
    RunService.RenderStepped:Connect(function()
        framesCount = framesCount + 1
        if tick() - last >= 1 then
            fps         = framesCount
            framesCount = 0
            last        = tick()
        end
        local network = Stats:FindFirstChild("Network")
        if network and network:FindFirstChild("ServerStatsItem") then
            local dataPing = network.ServerStatsItem:FindFirstChild("Data Ping")
            if dataPing then ping = math.floor(dataPing:GetValue()) end
        end
        pingLabel.Text = ping .. " ms"
        fpsLabel.Text  = tostring(fps)
        if pingDot then
            if ping <= 50 then
                pingDot.BackgroundColor3 = Color3.fromRGB(0, 200, 60)
            elseif ping <= 100 then
                pingDot.BackgroundColor3 = Color3.fromRGB(255, 210, 0)
            elseif ping <= 200 then
                pingDot.BackgroundColor3 = Color3.fromRGB(255, 120, 0)
            else
                pingDot.BackgroundColor3 = Color3.fromRGB(220, 30, 30)
            end
        end
        -- drive progress bar from StealState
        if progressFill and percentLabel then
            local pct = 0
            local fillColor
            local labelText

            if StealState.active then
                if StealState.phase == "waitingRange" then
                    local waitWindow = CONFIG.HOLD_MAX
                    pct = math.clamp((tick() - StealState.waitingTime) / waitWindow, 0, 1)
                    fillColor = Color3.fromRGB(255, 140, 0)
                    local remaining = math.max(0, waitWindow - (tick() - StealState.waitingTime))
                    labelText = "WAITING RANGE  ·  " .. string.format("%.2fs", remaining)
                else
                    pct = math.clamp((tick() - StealState.startTime) / CONFIG.HOLD_MIN, 0, 1)
                    fillColor = Color3.fromRGB(220, 30, 30)
                    local elapsed = tick() - StealState.startTime
                    labelText = "STEALING  ·  " .. string.format("%.2fs", elapsed)
                end
            elseif StealState.lastResultTime > 0 and (tick() - StealState.lastResultTime) < 0.4 then
                pct = 1
                local success = string.find(StealState.lastResult, "Stole") ~= nil
                fillColor = success and Color3.fromRGB(0, 200, 80) or Color3.fromRGB(200, 50, 50)
                labelText = string.upper(StealState.lastResult)
            else
                pct = 0
                fillColor = Color3.fromRGB(220, 30, 30)
                labelText = "STEAL"
            end

            progressFill.Size = UDim2.new(pct, 0, 1, 0)
            progressFill.BackgroundColor3 = fillColor
            percentLabel.Text = math.floor(pct * 100) .. "%"
            if stealLabel then stealLabel.Text = labelText end
            if neonStroke then neonStroke.Color = fillColor end
            if glowFrame then glowFrame.BackgroundColor3 = fillColor end
        end
    end)
end

local function setupUI()
    local sg = lp.PlayerGui:FindFirstChild("J hub ")
    if not sg then
        sg = Instance.new("ScreenGui")
        sg.Name = "J hub "
        sg.ResetOnSpawn = false
        sg.Parent = lp.PlayerGui
    end

    if not progressFill then
        local container = Instance.new("Frame")
        container.Size = UDim2.new(0, 280, 0, 32)
        container.Position = UDim2.new(0.5, -140, 1, -110)
        container.BackgroundTransparency = 1
        container.Parent = sg

        glowFrame = Instance.new("Frame")
        glowFrame.Size = UDim2.new(1, 8, 1, 8)
        glowFrame.Position = UDim2.new(0, -4, 0, -4)
        glowFrame.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
        glowFrame.BackgroundTransparency = 0.82
        glowFrame.BorderSizePixel = 0
        glowFrame.ZIndex = 1
        glowFrame.Parent = container
        Instance.new("UICorner", glowFrame).CornerRadius = UDim.new(1, 0)

        local mainBar = Instance.new("Frame")
        mainBar.Size = UDim2.new(1, 0, 1, 0)
        mainBar.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
        mainBar.BorderSizePixel = 0
        mainBar.ZIndex = 2
        mainBar.Parent = container
        Instance.new("UICorner", mainBar).CornerRadius = UDim.new(1, 0)

        neonStroke = Instance.new("UIStroke")
        neonStroke.Color = Color3.fromRGB(255, 20, 20)
        neonStroke.Thickness = 1.5
        neonStroke.Parent = mainBar

        local progressBarBg = Instance.new("Frame")
        progressBarBg.Size = UDim2.new(0, 150, 0, 20)
        progressBarBg.Position = UDim2.new(0, 6, 0.5, -10)
        progressBarBg.BackgroundColor3 = Color3.fromRGB(22, 22, 24)
        progressBarBg.BorderSizePixel = 0
        progressBarBg.ZIndex = 3
        progressBarBg.Parent = mainBar
        Instance.new("UICorner", progressBarBg).CornerRadius = UDim.new(1, 0)

        local progStroke = Instance.new("UIStroke")
        progStroke.Color = Color3.fromRGB(120, 15, 15)
        progStroke.Thickness = 1
        progStroke.Parent = progressBarBg

        progressFill = Instance.new("Frame")
        progressFill.Name = "ProgressFill"
        progressFill.Size = UDim2.new(0, 0, 1, 0)
        progressFill.BackgroundColor3 = Color3.fromRGB(220, 30, 30)
        progressFill.BorderSizePixel = 0
        progressFill.ZIndex = 4
        progressFill.Parent = progressBarBg
        Instance.new("UICorner", progressFill).CornerRadius = UDim.new(1, 0)

        local stripeGrad = Instance.new("UIGradient")
        stripeGrad.Color = ColorSequence.new{
            ColorSequenceKeypoint.new(0,   Color3.fromRGB(255, 80, 80)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 20, 20)),
            ColorSequenceKeypoint.new(1,   Color3.fromRGB(180, 10, 10)),
        }
        stripeGrad.Rotation = 45
        stripeGrad.Parent = progressFill

        stealLabel = Instance.new("TextLabel")
        stealLabel.Size = UDim2.new(1, -6, 1, 0)
        stealLabel.Position = UDim2.new(0, 6, 0, 0)
        stealLabel.BackgroundTransparency = 1
        stealLabel.Text = "STEAL"
        stealLabel.Font = Enum.Font.GothamBlack
        stealLabel.TextSize = 10
        stealLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        stealLabel.TextXAlignment = Enum.TextXAlignment.Left
        stealLabel.TextTransparency = 0.1
        stealLabel.ZIndex = 6
        stealLabel.Parent = progressBarBg

        percentLabel = Instance.new("TextLabel")
        percentLabel.Size = UDim2.new(0, 24, 1, 0)
        percentLabel.Position = UDim2.new(0, 160, 0, 0)
        percentLabel.BackgroundTransparency = 1
        percentLabel.Text = "0%"
        percentLabel.Font = Enum.Font.GothamBlack
        percentLabel.TextSize = 10
        percentLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        percentLabel.ZIndex = 3
        percentLabel.Parent = mainBar

        local fpsPrefixLabel = Instance.new("TextLabel")
        fpsPrefixLabel.Size = UDim2.new(0, 16, 1, 0)
        fpsPrefixLabel.Position = UDim2.new(0, 186, 0, 0)
        fpsPrefixLabel.BackgroundTransparency = 1
        fpsPrefixLabel.Text = "FPS"
        fpsPrefixLabel.Font = Enum.Font.GothamBlack
        fpsPrefixLabel.TextSize = 7
        fpsPrefixLabel.TextColor3 = Color3.fromRGB(255, 35, 35)
        fpsPrefixLabel.ZIndex = 3
        fpsPrefixLabel.Parent = mainBar

        fpsLabel = Instance.new("TextLabel")
        fpsLabel.Size = UDim2.new(0, 18, 1, 0)
        fpsLabel.Position = UDim2.new(0, 203, 0, 0)
        fpsLabel.BackgroundTransparency = 1
        fpsLabel.Text = "0"
        fpsLabel.Font = Enum.Font.GothamBold
        fpsLabel.TextSize = 8
        fpsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        fpsLabel.ZIndex = 3
        fpsLabel.Parent = mainBar

        local pingIcon = Instance.new("TextLabel")
        pingIcon.Size = UDim2.new(0, 12, 1, 0)
        pingIcon.Position = UDim2.new(0, 223, 0, 0)
        pingIcon.BackgroundTransparency = 1
        pingIcon.Text = "📡"
        pingIcon.TextScaled = true
        pingIcon.Font = Enum.Font.GothamBlack
        pingIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
        pingIcon.ZIndex = 3
        pingIcon.Parent = mainBar

        pingLabel = Instance.new("TextLabel")
        pingLabel.Size = UDim2.new(0, 28, 1, 0)
        pingLabel.Position = UDim2.new(0, 236, 0, 0)
        pingLabel.BackgroundTransparency = 1
        pingLabel.Text = "0ms"
        pingLabel.Font = Enum.Font.GothamBold
        pingLabel.TextSize = 8
        pingLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        pingLabel.ZIndex = 3
        pingLabel.Parent = mainBar

        pingDot = Instance.new("Frame")
        pingDot.Size = UDim2.new(0, 10, 0, 10)
        pingDot.Position = UDim2.new(1, -14, 0.5, -5)
        pingDot.BackgroundColor3 = Color3.fromRGB(220, 30, 30)
        pingDot.BorderSizePixel = 0
        pingDot.ZIndex = 3
        pingDot.Parent = mainBar
        Instance.new("UICorner", pingDot).CornerRadius = UDim.new(1, 0)

        updateTopBar()
    end
end

-- ── INIT ─────────────────────────────────────────────────────
task.spawn(function()
    while task.wait(5) do scanAllPlots() end
end)

setupUI()
scanAllPlots()
if CONFIG.AUTO_STEAL_ENABLED then startAutoSteal() end
