local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local lp = Players.LocalPlayer

local STEAL_RADIUS = 60
local STEAL_DURATION = 1.4
local isStealing = false
local StealData = {}
local progressFill = nil
local percentLabel = nil
local pingLabel = nil
local fpsLabel = nil
local pingDot = nil

local function updateTopBar()
    if not pingLabel or not fpsLabel then return end
    local fps = 60
    local ping = 0
    local framesCount = 0
    local last = tick()
    RunService.RenderStepped:Connect(function()
        framesCount = framesCount + 1
        if tick() - last >= 1 then
            fps = framesCount
            framesCount = 0
            last = tick()
        end
        local network = Stats:FindFirstChild("Network")
        if network and network:FindFirstChild("ServerStatsItem") then
            local dataPing = network.ServerStatsItem:FindFirstChild("Data Ping")
            if dataPing then ping = math.floor(dataPing:GetValue()) end
        end
        pingLabel.Text = ping .. " ms"
        fpsLabel.Text = tostring(fps)
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
        -- container: 280x32, bottom-center
        local container = Instance.new("Frame")
        container.Size = UDim2.new(0, 280, 0, 32)
        container.Position = UDim2.new(0.5, -140, 1, -110)
        container.BackgroundTransparency = 1
        container.Parent = sg

        -- outer glow
        local glowFrame = Instance.new("Frame")
        glowFrame.Size = UDim2.new(1, 8, 1, 8)
        glowFrame.Position = UDim2.new(0, -4, 0, -4)
        glowFrame.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
        glowFrame.BackgroundTransparency = 0.82
        glowFrame.BorderSizePixel = 0
        glowFrame.ZIndex = 1
        glowFrame.Parent = container
        Instance.new("UICorner", glowFrame).CornerRadius = UDim.new(1, 0)

        -- main bar
        local mainBar = Instance.new("Frame")
        mainBar.Size = UDim2.new(1, 0, 1, 0)
        mainBar.BackgroundColor3 = Color3.fromRGB(10, 10, 12)
        mainBar.BorderSizePixel = 0
        mainBar.ZIndex = 2
        mainBar.Parent = container
        Instance.new("UICorner", mainBar).CornerRadius = UDim.new(1, 0)

        local neonStroke = Instance.new("UIStroke")
        neonStroke.Color = Color3.fromRGB(255, 20, 20)
        neonStroke.Thickness = 1.5
        neonStroke.Parent = mainBar

        -- progress bar bg with STEAL text inside — x=6, width=150
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

        -- STEAL inside bar
        local stealLabel = Instance.new("TextLabel")
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

        -- % label right of bar, x=152
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

        -- FPS label inline, x=186
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

        -- right green dot (matches ref image 2/3)
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

local function getHRP()
    local c = lp.Character
    if c then return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso") or c:FindFirstChild("UpperTorso") end
    return nil
end

local function isMyPlotByName(pn)
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return false end
    local plot = plots:FindFirstChild(pn)
    if not plot then return false end
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yb = sign:FindFirstChild("YourBase")
        if yb and yb:IsA("BillboardGui") then return yb.Enabled == true end
    end
    return false
end

local function findNearestPrompt()
    local hrp = getHRP()
    if not hrp then return nil end
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    local nearest, dist = nil, math.huge
    for _, plot in ipairs(plots:GetChildren()) do
        if isMyPlotByName(plot.Name) then continue end
        local pods = plot:FindFirstChild("AnimalPodiums")
        if not pods then continue end
        for _, pod in ipairs(pods:GetChildren()) do
            local base = pod:FindFirstChild("Base")
            if not base then continue end
            local spawn = base:FindFirstChild("Spawn")
            if not spawn then continue end
            local d = (spawn.Position - hrp.Position).Magnitude
            if d <= STEAL_RADIUS and d < dist then
                local att = spawn:FindFirstChild("PromptAttachment")
                if att then
                    for _, p in ipairs(att:GetChildren()) do
                        if p:IsA("ProximityPrompt") and p.ActionText and p.ActionText:find("Steal") then
                            nearest, dist = p, d
                        end
                    end
                end
            end
        end
    end
    return nearest
end

local function updateProgressBar(p)
    if progressFill then
        progressFill.Size = UDim2.new(p, 0, 1, 0)
    end
    if percentLabel then
        percentLabel.Text = math.floor(p * 100) .. "%"
    end
end

local function executeSteal(prompt)
    if isStealing then return end
    if not StealData[prompt] then
        StealData[prompt] = {hold = {}, trigger = {}, ready = true}
        if getconnections then
            for _, c in ipairs(getconnections(prompt.PromptButtonHoldBegan)) do
                if c.Function then table.insert(StealData[prompt].hold, c.Function) end
            end
            for _, c in ipairs(getconnections(prompt.Triggered)) do
                if c.Function then table.insert(StealData[prompt].trigger, c.Function) end
            end
        end
    end
    local data = StealData[prompt]
    if not data.ready then return end
    data.ready = false
    isStealing = true
    local startTime = tick()
    task.spawn(function()
        for _, f in ipairs(data.hold) do pcall(f) end
        while tick() - startTime < STEAL_DURATION do
            local elapsed = tick() - startTime
            local p = math.clamp(elapsed / STEAL_DURATION, 0, 1)
            updateProgressBar(p)
            task.wait()
        end
        updateProgressBar(1)
        for _, f in ipairs(data.trigger) do pcall(f) end
        task.wait(0.05)
        updateProgressBar(0)
        data.ready = true
        isStealing = false
    end)
end

local heartbeatConn
local function startAutoSteal()
    setupUI()
    if heartbeatConn then return end
    heartbeatConn = RunService.Heartbeat:Connect(function()
        if isStealing then return end
        local success, prompt = pcall(findNearestPrompt)
        if success and prompt then pcall(executeSteal, prompt) end
    end)
end

local function stopAutoSteal()
    if heartbeatConn then heartbeatConn:Disconnect() heartbeatConn = nil end
    isStealing = false
    updateProgressBar(0)
end

startAutoSteal()
