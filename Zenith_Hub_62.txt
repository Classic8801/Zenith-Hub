local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer


;(function()
local NS, CS, LS, LS2 = 60, 30, 15, 24.5
local laggerPhase = 0 -- 0=off, 1=lagger, 2=lagger carry

local State = {
	speedToggled = false, laggerToggled = false, autoBatToggled = false,
	hittingCooldown = false, infJumpEnabled = false, jumpMethod = "Tap",
	antiRagdollEnabled = false, fpsBoostEnabled = false,
	antiLagEnabled = false,
	guiVisible = true,
	introEnabled = true, selectedIntroMusic = 1,
	isStealing = false, stealStartTime = nil, lastStealTick = 0,
	lastKnownHealth = 100,
	dropActive = false,
	dropBrainrotActive = false,
	autoLeftEnabled = false, autoRightEnabled = false,
	movementMode = "FullAuto",
	dragSmallMenus = false,
	unwalkEnabled = false,
	stretchRezEnabled = false,
}

local _anyKeyListening, uiLocked = false, false
local setLockUIVisual, MobilePanel, rebuildMobileButtons, resetMobileButtons
local autoSavePositions = function() end  -- no-op, MobilePanel removed
local mobilePanelStyle = "darkhub"
local mobileBtnFrames, mobileBtnActive, allMobileBtns = {}, {}, {}
local BTN_POSITIONS_DH = {
	Drop       = UDim2.new(1, -298, 1, -334),
	AutoLeft   = UDim2.new(1, -144, 1, -334),
	AutoBat    = UDim2.new(1, -298, 1, -270),
	AutoRight  = UDim2.new(1, -144, 1, -270),
	TPDown     = UDim2.new(1, -298, 1, -206),
	Speed      = UDim2.new(1, -144, 1, -206),
	Lagger     = UDim2.new(1, -144, 1, -142),
}

local KB = {
	AutoLeft  = {kb = Enum.KeyCode.Z,           gp = nil},
	AutoRight = {kb = Enum.KeyCode.C,           gp = nil},
	Drop      = {kb = Enum.KeyCode.X,           gp = nil},
	TPDown    = {kb = Enum.KeyCode.F,           gp = nil},
	AutoBat   = {kb = Enum.KeyCode.E,           gp = nil},
	Speed     = {kb = Enum.KeyCode.Q,           gp = nil},
	Lagger    = {kb = Enum.KeyCode.R,           gp = nil},
	GuiHide   = {kb = Enum.KeyCode.LeftControl, gp = nil},
}

local function kbMatch(entry, kc)
	return kc == entry.kb or (entry.gp and kc == entry.gp)
end

local AP = {
	L1=Vector3.new(-476.48,-6.28,92.73), L2=Vector3.new(-483.12,-4.95,94.80), L_FACE=Vector3.new(-482.25,-4.96,92.09),
	R1=Vector3.new(-476.16,-6.52,25.62), R2=Vector3.new(-483.06,-5.03,25.48), R_FACE=Vector3.new(-482.06,-6.93,35.47),
}

local Steal = {
	AutoStealEnabled = false, StealRadius = 8, StealDuration = 1.3,
	Data = {}, plotCache = {}, plotCacheTime = {},
	cachedPrompts = {}, promptCacheTime = 0,
}

local Conns = {
	autoSteal = nil, antiRag = nil,
	anchor = {}, progress = nil,
}

-- ─── Bat Aimbot (Opium) ──────────────────────────────────────────────────────
local startBatAimbot, stopBatAimbot
local function findAnyToolMob()
	local c=LP.Character
	if c then for _,v in ipairs(c:GetChildren()) do if v:IsA("Tool") then return v end end end
	local bp=LP:FindFirstChildOfClass("Backpack")
	if bp then for _,v in ipairs(bp:GetChildren()) do if v:IsA("Tool") then return v end end end
	return nil
end
local function getClosestPlayerMob2()
	local root=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil,math.huge end
	local cp,cd=nil,math.huge
	for _,p in pairs(Players:GetPlayers()) do
		if p~=LP and p.Character then
			local tr=p.Character:FindFirstChild("HumanoidRootPart")
			local ph=p.Character:FindFirstChildOfClass("Humanoid")
			if tr and ph and ph.Health>0 then
				local d=(root.Position-tr.Position).Magnitude
				if d<cd then cd=d; cp=p end
			end
		end
	end
	return cp,cd
end
local MOB_SWING_COOLDOWN=0.08
local function tryHitBatMob()
	if State.hittingCooldown then return end; State.hittingCooldown=true
	pcall(function()
		local c=LP.Character; if not c then return end
		local hum2=c:FindFirstChildOfClass("Humanoid"); local tool=findAnyToolMob()
		if tool then
			if tool.Parent~=c and hum2 then pcall(function() hum2:EquipTool(tool) end) end
			local remote=tool:FindFirstChildOfClass("RemoteEvent")
			if remote then pcall(function() remote:FireServer() end)
			else pcall(function() tool:Activate() end) end
		end
	end)
	task.delay(MOB_SWING_COOLDOWN,function() State.hittingCooldown=false end)
end
local _aimbotTarget = nil

local function findBat()
	local char = LP.Character; if not char then return nil end
	for _, tool in ipairs(char:GetChildren()) do
		if tool:IsA("Tool") and (tool.Name:lower():find("bat") or tool.Name:lower():find("slap")) then return tool end
	end
	local bp = LP:FindFirstChild("Backpack")
	if bp then
		for _, tool in ipairs(bp:GetChildren()) do
			if tool:IsA("Tool") and (tool.Name:lower():find("bat") or tool.Name:lower():find("slap")) then return tool end
		end
	end
	return nil
end

local function getClosestTarget()
	local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local closest, minDist = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= LP and plr.Character then
			local tRoot = plr.Character:FindFirstChild("HumanoidRootPart")
			local hum = plr.Character:FindFirstChildOfClass("Humanoid")
			if tRoot and hum and hum.Health > 0 then
				local dist = (tRoot.Position - root.Position).Magnitude
				if dist < minDist then minDist = dist; closest = tRoot end
			end
		end
	end
	return closest
end

startBatAimbot = function()
	if Conns.aimbot then Conns.aimbot:Disconnect() end
	if State.autoLeftEnabled then State.autoLeftEnabled=false; if autoLeftSetVisual then autoLeftSetVisual(false) end; stopAutoLeft() end
	if State.autoRightEnabled then State.autoRightEnabled=false; if autoRightSetVisual then autoRightSetVisual(false) end; stopAutoRight() end

	local hum0 = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
	if hum0 then hum0.AutoRotate = false end

	Conns.aimbot = RunService.RenderStepped:Connect(function()
		if not State.autoBatToggled then return end
		local char = LP.Character; if not char then return end
		local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
		local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end

		if not char:FindFirstChildOfClass("Tool") then
			local bat = findBat()
			if bat then pcall(function() hum:EquipTool(bat) end) end
		end

		local target = getClosestTarget()
		if not target then return end
		_aimbotTarget = target

		local targetVel = target.AssemblyLinearVelocity
		local myPos = root.Position
		local targetPos = target.Position

		local predictPos = targetPos + targetVel * 0.14
		predictPos = predictPos + target.CFrame.LookVector * 0.3

		local direction = predictPos - myPos
		local flatDir = Vector3.new(direction.X, 0, direction.Z).Unit
		local chaseSpeed = 58

		local desiredHeight = targetPos.Y + 3.7
		local yVel = (desiredHeight - myPos.Y) * 19.5 + targetVel.Y * 0.8
		if hum.FloorMaterial ~= Enum.Material.Air then
			yVel = math.max(yVel, 13)
		end
		yVel = math.clamp(yVel, -70, 110)

		local desiredVel = Vector3.new(flatDir.X * chaseSpeed, yVel, flatDir.Z * chaseSpeed)
		root.AssemblyLinearVelocity = root.AssemblyLinearVelocity:Lerp(desiredVel, 0.8)

		-- Dark hub style tilt: look toward predicted position in 3D (including Y)
		local speed3 = targetVel.Magnitude
		local predictTime = math.clamp(speed3 / 150, 0.05, 0.2)
		local predictedPos = targetPos + targetVel * predictTime
		local toPredict = predictedPos - myPos
		if toPredict.Magnitude > 0.1 then
			local goalCF = CFrame.lookAt(myPos, predictedPos)
			local curCF  = root.CFrame
			local diffCF = curCF:Inverse() * goalCF
			local rx, ry, rz = diffCF:ToEulerAnglesXYZ()
			rx = math.clamp(rx, -2.5, 2.5)
			ry = math.clamp(ry, -2.5, 2.5)
			rz = math.clamp(rz, -2.5, 2.5)
			local tiltSpeed = 42
			root.AssemblyAngularVelocity = root.CFrame:VectorToWorldSpace(
				Vector3.new(rx * tiltSpeed, ry * tiltSpeed, rz * tiltSpeed)
			)
		end
	end)
end

stopBatAimbot = function()
	if Conns.aimbot then Conns.aimbot:Disconnect(); Conns.aimbot = nil end
	_aimbotTarget = nil
	local c = LP.Character
	local root = c and c:FindFirstChild("HumanoidRootPart")
	if root then root.AssemblyLinearVelocity = Vector3.zero; root.AssemblyAngularVelocity = Vector3.zero end
	local hum2 = c and c:FindFirstChildOfClass("Humanoid")
	if hum2 then hum2.AutoRotate = true end
	State.hittingCooldown = false
end
-- ─── End of Bat Aimbot ───────────────────────────────────────────────────────
local PLOT_CACHE_DURATION, PROMPT_CACHE_REFRESH, STEAL_COOLDOWN = 2, 0.15, 0.1

local h, hrp, speedLbl
local setAutoGrab, setAutoBat, setInfJump, setAntiRag, setFps, setUnwalkToggle, autoLeftSetVisual, autoRightSetVisual, autoBatSetVisual, setIntroToggle
local setAntiLag, setStretchRez, setDarkMode
local setMedusaCounter, setBatCounter, setInstaGrab, setAutoSwingVisual
local startAntiRagdoll, stopAntiRagdoll, applyFPSBoost, startAutoSteal, stopAutoSteal
local mobileSpeedSetActive, mobileLaggerSetActive, saveConfig, loadConfig = nil, nil, nil, nil
local setDragSmallMenus, setDragSmallMenusVisual
local allBtns = {}
local lcBtn
local normalBox, carryBox, laggerBox, laggerBox2, durValBtn, uiScaleBox
local modeValLbl, progressFill, progressPct, progressRadLbl
local radValBtn
local alConn, arConn, alPhase, arPhase = nil, nil, 1, 1
local autoTPDownEnabled, autoTPDownConn, autoTPDownHeight = false, nil, 20

local function showDiscordInProgressBar()
	if not progressPct or not progressFill then return end

	local originalText = progressPct.Text
	local originalColor = progressPct.TextColor3
	local originalSize = progressPct.TextSize
	local originalAlign = progressPct.TextXAlignment

	progressPct.Text = "discord.gg/ED6cqXFRY"
	progressPct.TextColor3 = Color3.fromRGB(255, 255, 255)
	progressPct.TextSize = 13
	progressPct.TextXAlignment = Enum.TextXAlignment.Center
	progressPct.ZIndex = 12

	if progressRadLbl then progressRadLbl.Visible = false end

	task.delay(4, function()
		if progressPct then
			progressPct.Text = originalText or "0%"
			progressPct.TextColor3 = originalColor or Color3.fromRGB(235, 235, 235)
			progressPct.TextSize = originalSize or 11
			progressPct.TextXAlignment = originalAlign or Enum.TextXAlignment.Left
			progressPct.ZIndex = 5
		end
		if progressRadLbl then progressRadLbl.Visible = true end
	end)
end

-- ─── Full Auto Play (Misco Hub logic) ────────────────────────────────────────
local _apRouteRunning  = false
local _apRouteId       = 0
local _apDetectedSpawn = nil
local _apAutoPlayEnabled = false  -- internal flag, separate from State

local AP_PLOT3_POS = Vector3.new(-476.7524719238281, 10.464664459228516, 7.107429504394531)
local AP_PLOT7_POS = Vector3.new(-476.7524719238281, 10.464664459228516, 114.10742950439453)

local _apRoutes = {
	START_A = {
		StartPoint = Vector3.new(-484.37,-5.22,94.32),
		Route = {
			Vector3.new(-476,-8,29),
			Vector3.new(-480,-6,25),
			Vector3.new(-486,-6,25),
			Vector3.new(-475.75,-7.03,94.03)
		}
	},
	START_B = {
		StartPoint = Vector3.new(-485.08,-5.22,25.94),
		Route = {
			Vector3.new(-476.07,-8,91.05),
			Vector3.new(-480.07,-6,95.05),
			Vector3.new(-486.07,-6,95.05),
			Vector3.new(-476.08,-6.89,25.65)
		}
	}
}

local function _apGetMyPlot()
	local char = LP.Character
	if not char then return nil end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return nil end
	local checks = {
		{plotNum=3, pos=AP_PLOT3_POS},
		{plotNum=7, pos=AP_PLOT7_POS},
	}
	for _, entry in ipairs(checks) do
		for _, obj in ipairs(workspace:GetDescendants()) do
			if obj:IsA("BasePart") and obj.Name == "PlotSign" and (obj.Position - entry.pos).Magnitude < 5 then
				for _, child in ipairs(obj:GetDescendants()) do
					if child:IsA("SurfaceGui") then
						for _, label in ipairs(child:GetDescendants()) do
							if label:IsA("TextLabel") and label.Text ~= "" and
							   (string.find(label.Text, LP.Name) or string.find(label.Text, LP.DisplayName)) then
								return entry.plotNum
							end
						end
					end
				end
			end
		end
	end
	return nil
end

local function _apDirectMove(point, myRouteId, isFast)
	while _apRouteRunning and _apRouteId == myRouteId do
		local char = LP.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum  = char and char:FindFirstChildOfClass("Humanoid")
		if not root or not hum then task.wait(0.5); continue end
			-- Fast legs: normal→lagger speed; slow/carry legs: carry→lagger carry speed
		local spd = isFast
			and (State.laggerToggled and LS or NS)
			or  (State.laggerToggled and LS2 or CS)
		local dir = point - root.Position
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude < 2 then break end
		dir = dir.Unit
		hum.WalkSpeed = spd
		hum:Move(dir, false)
		root.AssemblyLinearVelocity = Vector3.new(dir.X * spd, root.AssemblyLinearVelocity.Y, dir.Z * spd)
		task.wait()
	end
	local char = LP.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum  = char and char:FindFirstChildOfClass("Humanoid")
	if hum then hum:Move(Vector3.zero, false) end
	if root then root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0) end
end

local function _apPathMove(point)
	local char = LP.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local PathfindingService = game:GetService("PathfindingService")
	local path = PathfindingService:CreatePath({AgentRadius=2, AgentHeight=5, AgentCanJump=false})
	pcall(function() path:ComputeAsync(root.Position, point) end)
	local waypoints = path.Status == Enum.PathStatus.Success and path:GetWaypoints() or {{Position = point}}
	local index = 2
	while _apRouteRunning and index <= #waypoints do
		local c   = LP.Character
		local r   = c and c:FindFirstChild("HumanoidRootPart")
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if not r or not hum then task.wait(0.5); continue end
		local target = waypoints[index].Position
		local dir = target - r.Position
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude < 2 then
			index += 1
		else
			dir = dir.Unit
			hum.WalkSpeed = NS
			hum:Move(dir, false)
			r.AssemblyLinearVelocity = Vector3.new(dir.X * NS, r.AssemblyLinearVelocity.Y, dir.Z * NS)
		end
		task.wait()
	end
	local c   = LP.Character
	local r   = c and c:FindFirstChild("HumanoidRootPart")
	local hum = c and c:FindFirstChildOfClass("Humanoid")
	if hum then hum:Move(Vector3.zero, false) end
	if r then r.AssemblyLinearVelocity = Vector3.new(0, r.AssemblyLinearVelocity.Y, 0) end
end

local function _apWalkRoute(route)
	local myId = _apRouteId
	_apRouteRunning = true
	_apDirectMove(route.Route[1], myId, true)
	if myId ~= _apRouteId then _apRouteRunning = false; return end
	_apDirectMove(route.Route[2], myId, true)
	if myId ~= _apRouteId then _apRouteRunning = false; return end
	_apDirectMove(route.Route[3], myId, true)
	if myId ~= _apRouteId then _apRouteRunning = false; return end
	task.wait(0.1)
	_apDirectMove(route.Route[2], myId, false)
	if myId ~= _apRouteId then _apRouteRunning = false; return end
	_apDirectMove(route.Route[1], myId, false)
	if myId ~= _apRouteId then _apRouteRunning = false; return end
	if route.Route[4] then _apDirectMove(route.Route[4], myId, false) end
	_apDirectMove(route.StartPoint, myId, false)
	_apRouteRunning = false
	-- Auto-off after one full trip
	_apAutoPlayEnabled = false
	-- Sync visual state
	if State.autoLeftEnabled then
		State.autoLeftEnabled = false
		if autoLeftSetVisual then autoLeftSetVisual(false) end
	end
	if State.autoRightEnabled then
		State.autoRightEnabled = false
		if autoRightSetVisual then autoRightSetVisual(false) end
	end
end

local function _apDetectLoop()
	task.spawn(function()
		while _apAutoPlayEnabled do
			local plot = _apGetMyPlot()
			if plot then
				_apDetectedSpawn = plot == 3 and 1 or (plot == 7 and 2 or nil)
			end
			task.wait(2)
		end
	end)
end

local function _apRunLoop()
	task.spawn(function()
		while _apAutoPlayEnabled do
			if not _apDetectedSpawn then task.wait(0.5); continue end
			local route = (_apDetectedSpawn == 1) and _apRoutes.START_B or _apRoutes.START_A
			_apRouteId = _apRouteId + 1
			_apWalkRoute(route)
			break
		end
		_apRouteRunning = false
	end)
end

local function startFullAutoPlay(routeKey)
	if _apRouteRunning then return end
	_apAutoPlayEnabled = true
	_apRouteRunning = false
	-- Increment only ONCE so _apWalkRoute captures the correct myId
	_apRouteId = _apRouteId + 1
	local char = LP.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = State.laggerToggled and LS or (State.speedToggled and CS or NS) end
	end
	local route = _apRoutes[routeKey]
	task.spawn(function()
		_apWalkRoute(route)
	end)
end

local function stopFullAutoPlay()
	_apAutoPlayEnabled = false
	_apRouteRunning = false
	_apRouteId = _apRouteId + 1
	local char = LP.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart")
		local hum  = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.WalkSpeed = 16 end
		if root then root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0) end
	end
end
-- ─── End Full Auto Play ───────────────────────────────────────────────────────

local function stopAutoLeft()
	if State.movementMode == "FullAuto" then
		stopFullAutoPlay()
	end
	if alConn then alConn:Disconnect(); alConn = nil end
	alPhase = 1
	local char = LP.Character
	if char then local hum = char:FindFirstChildOfClass("Humanoid"); if hum then hum:Move(Vector3.zero, false) end end
end

local function stopAutoRight()
	if State.movementMode == "FullAuto" then
		stopFullAutoPlay()
	end
	if arConn then arConn:Disconnect(); arConn = nil end
	arPhase = 1
	local char = LP.Character
	if char then local hum = char:FindFirstChildOfClass("Humanoid"); if hum then hum:Move(Vector3.zero, false) end end
end

local function startAutoLeft()
	if State.movementMode == "FullAuto" then
		startFullAutoPlay("START_B")
		return
	end
	if alConn then alConn:Disconnect() end
	alPhase = 1
	alConn = RunService.Heartbeat:Connect(function()
		if not State.autoLeftEnabled then return end
		if State.movementMode ~= "SemiAuto" then return end  -- disabled in Full Auto mode
		local char = LP.Character; if not char then return end
		local hrp2 = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hrp2 or not hum then return end
		-- Phase 1 = going out: lagger speed or normal; phase 2 = return: lagger carry or normal
		local spd = alPhase == 2
			and (State.laggerToggled and LS2 or NS)
			or  (State.laggerToggled and LS  or NS)
		hum.WalkSpeed = spd
		if alPhase == 1 then
			local tgt = Vector3.new(AP.L1.X, hrp2.Position.Y, AP.L1.Z)
			if (tgt - hrp2.Position).Magnitude < 1 then
				alPhase = 2
				local d = AP.L2 - hrp2.Position; local mv = Vector3.new(d.X,0,d.Z).Unit
				hum:Move(mv,false); hrp2.AssemblyLinearVelocity = Vector3.new(mv.X*spd, hrp2.AssemblyLinearVelocity.Y, mv.Z*spd); return
			end
			local d = AP.L1 - hrp2.Position; local mv = Vector3.new(d.X,0,d.Z).Unit
			hum:Move(mv,false); hrp2.AssemblyLinearVelocity = Vector3.new(mv.X*spd, hrp2.AssemblyLinearVelocity.Y, mv.Z*spd)
		elseif alPhase == 2 then
			local tgt = Vector3.new(AP.L2.X, hrp2.Position.Y, AP.L2.Z)
			if (tgt - hrp2.Position).Magnitude < 1 then
				hum:Move(Vector3.zero,false); hrp2.AssemblyLinearVelocity = Vector3.zero
				State.autoLeftEnabled = false
				if alConn then alConn:Disconnect(); alConn = nil end
				alPhase = 1
				if autoLeftSetVisual then autoLeftSetVisual(false) end
				if (AP.L_FACE - hrp2.Position).Magnitude > 0.01 then
					hrp2.CFrame = CFrame.new(hrp2.Position, Vector3.new(AP.L_FACE.X, hrp2.Position.Y, AP.L_FACE.Z))
				end
				return
			end
			local d = AP.L2 - hrp2.Position; local mv = Vector3.new(d.X,0,d.Z).Unit
			hum:Move(mv,false); hrp2.AssemblyLinearVelocity = Vector3.new(mv.X*spd, hrp2.AssemblyLinearVelocity.Y, mv.Z*spd)
		end
	end)
end

local function startAutoRight()
	if State.movementMode == "FullAuto" then
		startFullAutoPlay("START_A")
		return
	end
	if arConn then arConn:Disconnect() end
	arPhase = 1
	arConn = RunService.Heartbeat:Connect(function()
		if not State.autoRightEnabled then return end
		if State.movementMode ~= "SemiAuto" then return end  -- disabled in Full Auto mode
		local char = LP.Character; if not char then return end
		local hrp2 = char:FindFirstChild("HumanoidRootPart")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hrp2 or not hum then return end
		-- Phase 1 = going out: lagger speed or normal; phase 2 = return: lagger carry or normal
		local spd = arPhase == 2
			and (State.laggerToggled and LS2 or NS)
			or  (State.laggerToggled and LS  or NS)
		hum.WalkSpeed = spd
		if arPhase == 1 then
			local tgt = Vector3.new(AP.R1.X, hrp2.Position.Y, AP.R1.Z)
			if (tgt - hrp2.Position).Magnitude < 1 then
				arPhase = 2
				local d = AP.R2 - hrp2.Position; local mv = Vector3.new(d.X,0,d.Z).Unit
				hum:Move(mv,false); hrp2.AssemblyLinearVelocity = Vector3.new(mv.X*spd, hrp2.AssemblyLinearVelocity.Y, mv.Z*spd); return
			end
			local d = AP.R1 - hrp2.Position; local mv = Vector3.new(d.X,0,d.Z).Unit
			hum:Move(mv,false); hrp2.AssemblyLinearVelocity = Vector3.new(mv.X*spd, hrp2.AssemblyLinearVelocity.Y, mv.Z*spd)
		elseif arPhase == 2 then
			local tgt = Vector3.new(AP.R2.X, hrp2.Position.Y, AP.R2.Z)
			if (tgt - hrp2.Position).Magnitude < 1 then
				hum:Move(Vector3.zero,false); hrp2.AssemblyLinearVelocity = Vector3.zero
				State.autoRightEnabled = false
				if arConn then arConn:Disconnect(); arConn = nil end
				arPhase = 1
				if autoRightSetVisual then autoRightSetVisual(false) end
				if (AP.R_FACE - hrp2.Position).Magnitude > 0.01 then
					hrp2.CFrame = CFrame.new(hrp2.Position, Vector3.new(AP.R_FACE.X, hrp2.Position.Y, AP.R_FACE.Z))
				end
				return
			end
			local d = AP.R2 - hrp2.Position; local mv = Vector3.new(d.X,0,d.Z).Unit
			hum:Move(mv,false); hrp2.AssemblyLinearVelocity = Vector3.new(mv.X*spd, hrp2.AssemblyLinearVelocity.Y, mv.Z*spd)
		end
	end)
end


-- ─── Drop Brainrot ───────────────────────────────────────────────────────────
local DROP_ASCEND_DURATION = 0.2
local DROP_ASCEND_SPEED = 150

local function runDrop()
	if State.dropActive then return end
	local char = LP.Character; if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
	State.dropActive = true; local t0 = tick(); local dc
	dc = RunService.Heartbeat:Connect(function()
		local r = char and char:FindFirstChild("HumanoidRootPart")
		if not r then dc:Disconnect(); State.dropActive = false; return end
		if tick() - t0 >= DROP_ASCEND_DURATION then
			dc:Disconnect()
			local rp = RaycastParams.new(); rp.FilterDescendantsInstances = {char}; rp.FilterType = Enum.RaycastFilterType.Exclude
			local rr = workspace:Raycast(r.Position, Vector3.new(0, -2000, 0), rp)
			if rr then
				local hum2 = char:FindFirstChildOfClass("Humanoid")
				local off = (hum2 and hum2.HipHeight or 2) + (r.Size.Y / 2)
				r.CFrame = CFrame.new(r.Position.X, rr.Position.Y + off, r.Position.Z); r.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			end
			State.dropActive = false; return
		end
		r.AssemblyLinearVelocity = Vector3.new(r.AssemblyLinearVelocity.X, DROP_ASCEND_SPEED, r.AssemblyLinearVelocity.Z)
	end)
end
-- ─── TP Floor ────────────────────────────────────────────────────────────────
local _tpDownActive = false
local function runTPDown()
	if _tpDownActive then return end
	_tpDownActive = true
	pcall(function()
		local char = LP.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not root or not hum then _tpDownActive = false; return end
		local rp = RaycastParams.new()
		rp.FilterDescendantsInstances = {char}
		rp.FilterType = Enum.RaycastFilterType.Exclude
		local result = workspace:Raycast(root.Position, Vector3.new(0, -1000, 0), rp)
		if result then
			local hipOffset = hum.HipHeight + (root.Size.Y / 2)
			local targetPos = result.Position + Vector3.new(0, hipOffset, 0)
			root.CFrame = CFrame.new(targetPos) * root.CFrame.Rotation
		end
	end)
	_tpDownActive = false
end

local function startAutoTPDown()
	if autoTPDownConn then task.cancel(autoTPDownConn); autoTPDownConn = nil end
	autoTPDownConn = task.spawn(function()
		while autoTPDownEnabled do
			task.wait(0.1)
			pcall(function()
				local char = LP.Character; if not char then return end
				local root = char:FindFirstChild("HumanoidRootPart"); if not root then return end
				local hum = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
				if hum.FloorMaterial ~= Enum.Material.Air then return end
				if root.Position.Y < autoTPDownHeight then return end
				local rp = RaycastParams.new()
				rp.FilterDescendantsInstances = {char}
				rp.FilterType = Enum.RaycastFilterType.Exclude
				local result = workspace:Raycast(root.Position, Vector3.new(0, -2000, 0), rp)
				local hipOffset = hum.HipHeight + (root.Size.Y / 2)
				local targetY = result and (result.Position.Y + hipOffset) or -7.00
				root.CFrame = CFrame.new(Vector3.new(root.Position.X, targetY, root.Position.Z))
					* CFrame.Angles(0, select(2, root.CFrame:ToEulerAnglesYXZ()), 0)
				root.AssemblyLinearVelocity = Vector3.zero
			end)
		end
	end)
end

local function stopAutoTPDown()
	autoTPDownEnabled = false
	if autoTPDownConn then task.cancel(autoTPDownConn); autoTPDownConn = nil end
end

for _, name in pairs({"ZenithHubGUI"}) do
	local old = game:GetService("CoreGui"):FindFirstChild(name)
	if old then old:Destroy() end
	local pg = LP:FindFirstChild("PlayerGui")
	if pg then local o = pg:FindFirstChild(name); if o then o:Destroy() end end
end

local function makeDraggable(frame)
	local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
	frame.InputBegan:Connect(function(inp)
		if uiLocked then return end
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			dragging = true; dragStart = inp.Position; startPos = frame.Position
			inp.Changed:Connect(function() if inp.UserInputState == Enum.UserInputState.End then dragging = false end end)
		end
	end)
	frame.InputChanged:Connect(function(inp)
		if uiLocked then dragging = false; return end
		if inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch then dragInput = inp end
	end)
	UIS.InputChanged:Connect(function(inp)
		if uiLocked then dragging = false; return end
		if inp == dragInput and dragging then
			local d = inp.Position - dragStart
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset+d.X, startPos.Y.Scale, startPos.Y.Offset+d.Y)
		end
	end)
end

local gui = Instance.new("ScreenGui")
gui.Name = "ZenithHubGUI"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.IgnoreGuiInset = true
if not pcall(function() gui.Parent = game:GetService("CoreGui") end) then
	gui.Parent = LP:WaitForChild("PlayerGui")
end

local _C={
	[1]=Color3.fromRGB(14,3,3),   [2]=Color3.fromRGB(14,3,3),
	[3]=Color3.fromRGB(32,6,7),[4]=Color3.fromRGB(55,10,12),
	[5]=Color3.fromRGB(160,20,25),[6]=Color3.fromRGB(220,30,40),
	[7]=Color3.fromRGB(255,255,255),[8]=Color3.fromRGB(220,150,150),
	[9]=Color3.fromRGB(70,12,14),[10]=Color3.fromRGB(12,3,3),
}
local BG=_C[1];local SIDEBAR_BG=_C[2];local CARD_BG=_C[3];local CARD_HOV=_C[4]
local BORDER=_C[5];local BORDER2=_C[6];local WHITE=_C[7];local DIM=_C[8]
local DIM2=_C[9];local KB_BG=_C[10];local INPUT_BG=_C[10]
local ACCENT=Color3.fromRGB(220,30,40)
local ACCENT_HOV=Color3.fromRGB(240,55,65)
local ACCENT_CLICK=Color3.fromRGB(180,15,25)

local W, H, SW = 490, 460, 90
local PW = 0 -- portrait panel width (photo removed)
local CORNER = 12

local uiScaleValue = 100
local mainUIScale = nil
local main = Instance.new("Frame", gui)
main.Name = "Main"
main.Size = UDim2.new(0, W, 0, H)
main.Position = UDim2.new(0, 50, 0, 50)
main.BackgroundColor3 = BG
main.BorderSizePixel = 0
main.Active = true
main.ClipsDescendants = true
Instance.new("UICorner", main).CornerRadius = UDim.new(0, CORNER)
local mainStroke = Instance.new("UIStroke", main)
mainStroke.Color = ACCENT
mainStroke.Thickness = 1
makeDraggable(main)
mainUIScale = Instance.new("UIScale", main)
mainUIScale.Scale = uiScaleValue / 100

-- ── Red lightning flash effect on GUI border ─────────────────────────
local flashStroke = Instance.new("UIStroke", main)
flashStroke.Color = ACCENT_HOV
flashStroke.Thickness = 1
flashStroke.Transparency = 1
task.spawn(function()
	while true do
		if main.Visible then
			-- lightning-style flicker burst
			local flashes = math.random(1, 3)
			for i = 1, flashes do
				flashStroke.Thickness = math.random(2, 4)
				flashStroke.Transparency = 0
				TweenService:Create(flashStroke, TweenInfo.new(0.08, Enum.EasingStyle.Linear), {Transparency = 1}):Play()
				task.wait(math.random(6, 14) / 100)
			end
		end
		task.wait(math.random(20, 50) / 10)
	end
end)

local topbar = Instance.new("Frame", main)
topbar.Size = UDim2.new(1, 0, 0, 44)
topbar.BackgroundColor3 = Color3.fromRGB(20, 4, 4)
topbar.BorderSizePixel = 0
topbar.ZIndex = 10
Instance.new("UICorner", topbar).CornerRadius = UDim.new(0, CORNER)
local topPatch = Instance.new("Frame", topbar)
topPatch.Size = UDim2.new(1, 0, 0, CORNER)
topPatch.Position = UDim2.new(0, 0, 1, -CORNER)
topPatch.BackgroundColor3 = Color3.fromRGB(20, 4, 4)
topPatch.BorderSizePixel = 0
topPatch.ZIndex = 9
local topDiv = Instance.new("Frame", topbar)
topDiv.Size = UDim2.new(1, 0, 0, 1)
topDiv.Position = UDim2.new(0, 0, 1, -1)
topDiv.BackgroundColor3 = BORDER
topDiv.BorderSizePixel = 0
topDiv.ZIndex = 11

local titleLbl = Instance.new("TextLabel", topbar)
titleLbl.Size = UDim2.new(0, 160, 1, 0)
titleLbl.Position = UDim2.new(0, 14, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "ZENITH HUB"
titleLbl.TextColor3 = WHITE
titleLbl.Font = Enum.Font.GothamBlack
titleLbl.TextSize = 13
titleLbl.TextXAlignment = Enum.TextXAlignment.Left
titleLbl.ZIndex = 12

local verLbl = Instance.new("TextLabel", topbar)
verLbl.Size = UDim2.new(0, 130, 1, 0)
verLbl.Position = UDim2.new(0, 100, 0, 0)
verLbl.BackgroundTransparency = 1
verLbl.Text = "discord.gg/ED6cqXFRY"
verLbl.TextColor3 = DIM
verLbl.Font = Enum.Font.Gotham
verLbl.TextSize = 9
verLbl.TextXAlignment = Enum.TextXAlignment.Left
verLbl.ZIndex = 12

local minBtn = Instance.new("TextButton", topbar)
minBtn.Size = UDim2.new(0, 26, 0, 26)
minBtn.Position = UDim2.new(1, -36, 0.5, -13)
minBtn.BackgroundColor3 = Color3.fromRGB(35, 7, 7)
minBtn.BorderSizePixel = 0
minBtn.Text = "–"
minBtn.TextColor3 = WHITE
minBtn.Font = Enum.Font.GothamBlack
minBtn.TextSize = 16
minBtn.ZIndex = 13
Instance.new("UICorner", minBtn).CornerRadius = UDim.new(0, 6)
Instance.new("UIStroke", minBtn).Color = BORDER
minBtn.MouseEnter:Connect(function() TweenService:Create(minBtn, TweenInfo.new(0.1), {BackgroundColor3=ACCENT_HOV}):Play() end)
minBtn.MouseLeave:Connect(function() TweenService:Create(minBtn, TweenInfo.new(0.1), {BackgroundColor3=Color3.fromRGB(35,7,7)}):Play() end)


local sidebar = Instance.new("Frame", main)
sidebar.Size = UDim2.new(0, SW, 1, -44)
sidebar.Position = UDim2.new(0, PW + 1, 0, 44)
sidebar.BackgroundColor3 = SIDEBAR_BG
sidebar.BorderSizePixel = 0
sidebar.ZIndex = 5
sidebar.ClipsDescendants = false
do local _st=Instance.new("Frame",main); _st.Size=UDim2.new(0,SW,0,CORNER); _st.Position=UDim2.new(0,PW+1,0,44); _st.BackgroundColor3=SIDEBAR_BG; _st.BorderSizePixel=0; _st.ZIndex=4 end

do local _sd=Instance.new("Frame",sidebar); _sd.Size=UDim2.new(0,1,1,0); _sd.Position=UDim2.new(1,-1,0,0); _sd.BackgroundColor3=BORDER; _sd.BorderSizePixel=0; _sd.ZIndex=6 end

local content = Instance.new("Frame", main)
content.Name = "ContentArea"
content.Size = UDim2.new(1, -(PW + 1 + SW + 1), 1, -44 - CORNER)
content.Position = UDim2.new(0, PW + 1 + SW + 1, 0, 44)
content.BackgroundColor3 = BG
content.BackgroundTransparency = 0
content.BorderSizePixel = 0
content.ClipsDescendants = true
content.ZIndex = 2

local mini = Instance.new("TextButton", gui)
mini.Name = "ZenithMini"
mini.Size = UDim2.new(0, 160, 0, 30)
mini.Position = UDim2.new(0, 50, 0, 50)
mini.BackgroundColor3 = Color3.fromRGB(20, 4, 4)
mini.BorderSizePixel = 0
mini.Text = "ZENITH HUB"
mini.TextColor3 = WHITE
mini.Font = Enum.Font.GothamBold
mini.TextSize = 11
mini.TextXAlignment = Enum.TextXAlignment.Center
mini.ZIndex = 20
mini.Visible = false
Instance.new("UICorner", mini).CornerRadius = UDim.new(0, 8)
local miniStroke = Instance.new("UIStroke", mini)
miniStroke.Color = ACCENT
miniStroke.Thickness = 1
makeDraggable(mini)

local function showGui() main.Visible=true; mini.Visible=false; State.guiVisible=true end
local function hideGui() main.Visible=false; mini.Visible=false; State.guiVisible=false end
minBtn.MouseButton1Click:Connect(hideGui)
mini.MouseButton1Click:Connect(showGui)
mini.MouseEnter:Connect(function() TweenService:Create(mini,TweenInfo.new(0.1),{BackgroundColor3=ACCENT_HOV}):Play() end)
mini.MouseLeave:Connect(function() TweenService:Create(mini,TweenInfo.new(0.1),{BackgroundColor3=Color3.fromRGB(20, 4, 4)}):Play() end)

local tabs = {}
local tabPages = {}
local activeTabName = nil
local tabDefs = {
	{name="Speed"},
	{name="Bat Aimbot"},
	{name="Mechanics"},
	{name="Movement"},
	{name="Performance"},
	{name="Settings"},
}
local switchTab
local pageLOs = {}

local tabListFrame = Instance.new("Frame", sidebar)
tabListFrame.Size = UDim2.new(1, 0, 1, 0)
tabListFrame.Position = UDim2.new(0, 0, 0, 0)
tabListFrame.BackgroundTransparency = 1
tabListFrame.BorderSizePixel = 0
tabListFrame.ZIndex = 6

local tabLL = Instance.new("UIListLayout", tabListFrame)
tabLL.SortOrder = Enum.SortOrder.LayoutOrder
tabLL.Padding = UDim.new(0, 2)
local tabPad = Instance.new("UIPadding", tabListFrame)
tabPad.PaddingTop = UDim.new(0, 10)
tabPad.PaddingLeft = UDim.new(0, 6)
tabPad.PaddingRight = UDim.new(0, 6)

local ACTIVE_TAB_BG  = ACCENT
local ACTIVE_TAB_TXT = WHITE
local IDLE_TAB_BG    = Color3.fromRGB(35, 7, 7)
local IDLE_TAB_TXT   = WHITE

switchTab = function(name)
	activeTabName = name
	for _, td in ipairs(tabDefs) do
		local t = tabs[td.name]
		local isA = td.name == name
		TweenService:Create(t.frame, TweenInfo.new(0.14), {BackgroundColor3 = isA and ACTIVE_TAB_BG or IDLE_TAB_BG}):Play()
		TweenService:Create(t.lbl,   TweenInfo.new(0.14), {TextColor3 = isA and ACTIVE_TAB_TXT or IDLE_TAB_TXT}):Play()
		tabPages[td.name].Visible = isA
	end
end

for i, td in ipairs(tabDefs) do
	local btn = Instance.new("TextButton", tabListFrame)
	btn.Size = UDim2.new(1, 0, 0, 34)
	btn.BackgroundColor3 = IDLE_TAB_BG
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.LayoutOrder = i
	btn.ZIndex = 7
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
	local lbl = Instance.new("TextLabel", btn)
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.Position = UDim2.new(0, 0, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = td.name
	lbl.TextColor3 = IDLE_TAB_TXT
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 9
	lbl.TextXAlignment = Enum.TextXAlignment.Center
	lbl.TextWrapped = true
	lbl.ZIndex = 9
	tabs[td.name] = {frame=btn, lbl=lbl}

	local page = Instance.new("ScrollingFrame", content)
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundColor3 = BG
	page.BackgroundTransparency = 0
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 2
	page.ScrollBarImageColor3 = BORDER2
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new(0, 0, 0, 0)
	page.Visible = false
	page.ZIndex = 3
	local pll = Instance.new("UIListLayout", page)
	pll.SortOrder = Enum.SortOrder.LayoutOrder
	pll.Padding = UDim.new(0, 4)
	local pp = Instance.new("UIPadding", page)
	pp.PaddingLeft = UDim.new(0, 8)
	pp.PaddingRight = UDim.new(0, 8)
	pp.PaddingTop = UDim.new(0, 10)
	pp.PaddingBottom = UDim.new(0, 10)
	tabPages[td.name] = page
	pageLOs[td.name] = 0
	btn.Activated:Connect(function() switchTab(td.name) end)
	btn.MouseEnter:Connect(function()
		if activeTabName ~= td.name then TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3=Color3.fromRGB(55, 10, 12)}):Play() end
	end)
	btn.MouseLeave:Connect(function()
		if activeTabName ~= td.name then TweenService:Create(btn, TweenInfo.new(0.1), {BackgroundColor3=IDLE_TAB_BG}):Play() end
	end)
end

local function lo(tabName) pageLOs[tabName] = pageLOs[tabName] + 1; return pageLOs[tabName] end
local function pg(tabName) return tabPages[tabName] end

local function makeSecHeader(tabName, text)
	local f = Instance.new("Frame", pg(tabName))
	f.Size = UDim2.new(1, 0, 0, 18)
	f.BackgroundTransparency = 1
	f.BorderSizePixel = 0
	f.LayoutOrder = lo(tabName)
	f.ZIndex = 4
	local t = Instance.new("TextLabel", f)
	t.Size = UDim2.new(1, 0, 1, 0)
	t.BackgroundTransparency = 1
	t.Text = text:upper()
	t.TextColor3 = WHITE
	t.Font = Enum.Font.GothamBold
	t.TextSize = 8
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.ZIndex = 5
	local line = Instance.new("Frame", f)
	line.Size = UDim2.new(1, 0, 0, 1)
	line.Position = UDim2.new(0, 0, 1, -1)
	line.BackgroundColor3 = BORDER
	line.BorderSizePixel = 0
	line.ZIndex = 4
end

local _unwalkSavedAnimate = nil
local function startUnwalk()
    local c = LP.Character; if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid")
    if hum then for _,t in ipairs(hum:GetPlayingAnimationTracks()) do pcall(function() t:Stop() end) end end
    local anim = c:FindFirstChild("Animate")
    if anim then _unwalkSavedAnimate = anim:Clone(); anim:Destroy() end
end
local function stopUnwalk()
    local c = LP.Character
    if c then
        local existing = c:FindFirstChild("Animate")
        if not existing then
            local src = game:GetService("StarterPlayer"):FindFirstChildOfClass("StarterCharacterScripts")
            local starterAnim = src and src:FindFirstChild("Animate")
            if starterAnim then starterAnim:Clone().Parent = c
            elseif _unwalkSavedAnimate then _unwalkSavedAnimate:Clone().Parent = c end
        end
    end
    _unwalkSavedAnimate = nil
end

local function baseCard(tabName, h2)
	local c = Instance.new("Frame", pg(tabName))
	c.Size = UDim2.new(1, 0, 0, h2 or 38)
	c.BackgroundColor3 = CARD_BG
	c.BorderSizePixel = 0
	c.LayoutOrder = lo(tabName)
	c.ZIndex = 4
	Instance.new("UICorner", c).CornerRadius = UDim.new(0, 7)
	Instance.new("UIStroke", c).Color = BORDER
	c.MouseEnter:Connect(function() TweenService:Create(c, TweenInfo.new(0.1), {BackgroundColor3=CARD_HOV}):Play() end)
	c.MouseLeave:Connect(function() TweenService:Create(c, TweenInfo.new(0.1), {BackgroundColor3=CARD_BG}):Play() end)
	return c
end

local function cLabel(p, text, x, w, sz, col, font, xa)
	local l = Instance.new("TextLabel", p)
	l.Size = UDim2.new(0, w or 140, 1, 0)
	l.Position = UDim2.new(0, x or 10, 0, 0)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = col or WHITE
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = sz or 11
	l.TextXAlignment = xa or Enum.TextXAlignment.Left
	l.ZIndex = 10
	return l
end

local function makePillToggle(parent, defOn, onToggle)
	local PW, PH = 36, 19
	local pbg = Instance.new("Frame", parent)
	pbg.Size = UDim2.new(0, PW, 0, PH)
	pbg.Position = UDim2.new(1, -(PW+10), 0.5, -PH/2)
	pbg.BackgroundColor3 = defOn and ACCENT or Color3.fromRGB(16, 16, 16)
	pbg.BorderSizePixel = 0
	pbg.ZIndex = 8
	Instance.new("UICorner", pbg).CornerRadius = UDim.new(0, 10)
	local ps = Instance.new("UIStroke", pbg); ps.Color = defOn and ACCENT or BORDER2; ps.Thickness = 1
	local dot = Instance.new("Frame", pbg)
	dot.Size = UDim2.new(0, 13, 0, 13)
	dot.Position = defOn and UDim2.new(1, -15, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
	dot.BackgroundColor3 = defOn and BG or DIM2
	dot.BorderSizePixel = 0
	dot.ZIndex = 9
	Instance.new("UICorner", dot).CornerRadius = UDim.new(0, 4)
	local isOn = defOn or false
	local function setV(on)
		isOn = on
		TweenService:Create(pbg, TweenInfo.new(0.18), {BackgroundColor3=on and ACCENT or Color3.fromRGB(16, 16, 16)}):Play()
		TweenService:Create(ps,  TweenInfo.new(0.18), {Color=on and ACCENT or BORDER2}):Play()
		TweenService:Create(dot, TweenInfo.new(0.18, Enum.EasingStyle.Back), {
			Position = on and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,2,0.5,-6),
			BackgroundColor3 = on and BG or DIM2
		}):Play()
	end
	local clk = Instance.new("TextButton", parent)
	clk.Size = UDim2.new(1, 0, 1, 0)
	clk.BackgroundTransparency = 1
	clk.Text = ""
	clk.ZIndex = 6
	clk.MouseButton1Click:Connect(function()
		if _anyKeyListening then return end
		isOn = not isOn; setV(isOn); if onToggle then pcall(onToggle, isOn) end
	end)
	return setV
end

local function makeKB(parent, kbEntry, onChange)
	local b = Instance.new("TextButton", parent)
	b.Size = UDim2.new(0, 44, 0, 20)
	b.BackgroundColor3 = KB_BG
	b.BorderSizePixel = 0
	local function getDisplayText()
		if kbEntry.gp then return "GP:"..kbEntry.gp.Name
		elseif kbEntry.kb then return kbEntry.kb.Name
		else return "None" end
	end
	b.Text = getDisplayText()
	b.TextColor3 = WHITE
	b.Font = Enum.Font.GothamBold
	b.TextSize = 8
	b.ZIndex = 11
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
	local bs = Instance.new("UIStroke", b); bs.Color = BORDER2; bs.Thickness = 1
	local li = false; local lc; local pv = b.Text
	b.MouseButton1Click:Connect(function()
		if li then li=false; _anyKeyListening=false; if lc then lc:Disconnect(); lc=nil end; b.Text=pv; b.TextColor3=WHITE; return end
		pv=b.Text; li=true; _anyKeyListening=true; b.Text="···"; b.TextColor3=DIM
		TweenService:Create(bs, TweenInfo.new(0.1), {Color=ACCENT}):Play()
		lc = UIS.InputBegan:Connect(function(inp)
			if not li then return end
			local isKb = inp.UserInputType == Enum.UserInputType.Keyboard
			local isGp = inp.UserInputType == Enum.UserInputType.Gamepad1
			if not isKb and not isGp then return end
			if inp.KeyCode == Enum.KeyCode.Escape then
				li=false; _anyKeyListening=false; if lc then lc:Disconnect(); lc=nil end
				b.Text=pv; b.TextColor3=WHITE; TweenService:Create(bs,TweenInfo.new(0.1),{Color=BORDER2}):Play(); return
			end
			if isGp then
				kbEntry.gp = inp.KeyCode; kbEntry.kb = nil
				b.Text = "GP:"..inp.KeyCode.Name; pv = b.Text
			else
				kbEntry.kb = inp.KeyCode; kbEntry.gp = nil
				b.Text = inp.KeyCode.Name; pv = b.Text
			end
			b.TextColor3=WHITE
			li=false; _anyKeyListening=false; if lc then lc:Disconnect(); lc=nil end
			TweenService:Create(bs, TweenInfo.new(0.1), {Color=BORDER2}):Play()
			if onChange then onChange(inp.KeyCode) end
		end)
	end)
	return b
end

local function rowToggle(tabName, label, sub, defOn, onToggle)
	local c = baseCard(tabName, sub and 48 or 38)
	cLabel(c, label, 10, 160, 11, WHITE, Enum.Font.GothamBold)
	if sub then
		local sl = cLabel(c, sub, 10, 170, 9, DIM, Enum.Font.Gotham)
		sl.Size = UDim2.new(0, 170, 0, 13); sl.Position = UDim2.new(0, 10, 0, 24)
	end
	return makePillToggle(c, defOn, onToggle)
end

local function rowToggleKB(tabName, label, sub, kbEntry, defOn, onToggle, onKeyChange)
	local c = baseCard(tabName, sub and 48 or 38)
	cLabel(c, label, 10, 120, 11, WHITE, Enum.Font.GothamBold)
	if sub then
		local sl = cLabel(c, sub, 10, 150, 9, DIM, Enum.Font.Gotham)
		sl.Size = UDim2.new(0, 150, 0, 13); sl.Position = UDim2.new(0, 10, 0, 24)
	end
	local kb = makeKB(c, kbEntry, function(k) if onKeyChange then onKeyChange(k) end end)
	kb.Position = UDim2.new(1, -(44+10+36+8), 0.5, -10)
	kb.ZIndex = 11
	local PW, PH = 36, 19
	local pbg = Instance.new("Frame", c)
	pbg.Size = UDim2.new(0, PW, 0, PH)
	pbg.Position = UDim2.new(1, -(PW+10), 0.5, -PH/2)
	pbg.BackgroundColor3 = defOn and ACCENT or Color3.fromRGB(16, 16, 16)
	pbg.BorderSizePixel = 0
	pbg.ZIndex = 8
	Instance.new("UICorner", pbg).CornerRadius = UDim.new(0, 10)
	local ps = Instance.new("UIStroke", pbg); ps.Color = defOn and ACCENT or BORDER2; ps.Thickness = 1
	local dot = Instance.new("Frame", pbg)
	dot.Size = UDim2.new(0, 13, 0, 13)
	dot.Position = defOn and UDim2.new(1, -15, 0.5, -6) or UDim2.new(0, 2, 0.5, -6)
	dot.BackgroundColor3 = defOn and BG or DIM2
	dot.BorderSizePixel = 0
	dot.ZIndex = 9
	Instance.new("UICorner", dot).CornerRadius = UDim.new(0, 4)
	local isOn = defOn or false
	local function setV(on)
		isOn = on
		TweenService:Create(pbg, TweenInfo.new(0.18), {BackgroundColor3=on and ACCENT or Color3.fromRGB(16, 16, 16)}):Play()
		TweenService:Create(ps,  TweenInfo.new(0.18), {Color=on and ACCENT or BORDER2}):Play()
		TweenService:Create(dot, TweenInfo.new(0.18, Enum.EasingStyle.Back), {
			Position = on and UDim2.new(1,-15,0.5,-6) or UDim2.new(0,2,0.5,-6),
			BackgroundColor3 = on and BG or DIM2
		}):Play()
	end
	local clk = Instance.new("TextButton", c)
	clk.Size = UDim2.new(1, 0, 1, 0)
	clk.BackgroundTransparency = 1
	clk.Text = ""
	clk.ZIndex = 6
	clk.MouseButton1Click:Connect(function()
		if _anyKeyListening then return end
		isOn = not isOn; setV(isOn); if onToggle then pcall(onToggle, isOn) end
	end)
	return setV, kb
end

local function rowKBOnly(tabName, label, sub, kbEntry, onKeyChange)
	local c = baseCard(tabName, sub and 48 or 38)
	cLabel(c, label, 10, 160, 11, WHITE, Enum.Font.GothamBold)
	if sub then
		local sl = cLabel(c, sub, 10, 170, 9, DIM, Enum.Font.Gotham)
		sl.Size = UDim2.new(0, 170, 0, 13); sl.Position = UDim2.new(0, 10, 0, 24)
	end
	local kb = makeKB(c, kbEntry, function(k) if onKeyChange then onKeyChange(k) end end)
	kb.Position = UDim2.new(1, -(44+10), 0.5, -10)
	kb.ZIndex = 11
	return kb
end

local function rowInput(tabName, label, sub, default, onChange)
	local c = baseCard(tabName, sub and 48 or 38)
	cLabel(c, label, 10, 130, 11, WHITE, Enum.Font.GothamBold)
	if sub then
		local sl = cLabel(c, sub, 10, 160, 9, DIM, Enum.Font.Gotham)
		sl.Size = UDim2.new(0, 160, 0, 13); sl.Position = UDim2.new(0, 10, 0, 24)
	end
	local box = Instance.new("TextBox", c)
	box.Size = UDim2.new(0, 64, 0, 24)
	box.Position = UDim2.new(1, -74, 0.5, -12)
	box.BackgroundColor3 = INPUT_BG
	box.BorderSizePixel = 0
	box.Text = tostring(default)
	box.TextColor3 = WHITE
	box.Font = Enum.Font.GothamBold
	box.TextSize = 11
	box.ClearTextOnFocus = false
	box.ZIndex = 11
	Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)
	local bs = Instance.new("UIStroke", box); bs.Color = BORDER2; bs.Thickness = 1; bs.ZIndex = 12
	box.Focused:Connect(function() TweenService:Create(bs, TweenInfo.new(0.1), {Color=ACCENT}):Play() end)
	box.FocusLost:Connect(function()
		TweenService:Create(bs, TweenInfo.new(0.1), {Color=BORDER2}):Play()
		if onChange then local n = tonumber(box.Text); if n then onChange(n) else box.Text = tostring(default) end end
	end)
	return box
end

local function rowCycle(tabName, label, options, defaultIdx, onChange)
	local c = baseCard(tabName, 38)
	cLabel(c, label, 10, 160, 11, WHITE, Enum.Font.GothamBold)
	local idx = defaultIdx or 1
	local btn = Instance.new("TextButton", c)
	btn.Size = UDim2.new(0, 64, 0, 24)
	btn.Position = UDim2.new(1, -74, 0.5, -12)
	btn.BackgroundColor3 = INPUT_BG
	btn.BorderSizePixel = 0
	btn.Text = tostring(options[idx])
	btn.TextColor3 = WHITE
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 11
	btn.ZIndex = 11
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
	local bs = Instance.new("UIStroke", btn); bs.Color = BORDER2; bs.Thickness = 1; bs.ZIndex = 12
	btn.MouseButton1Click:Connect(function()
		idx = (idx % #options) + 1
		btn.Text = tostring(options[idx])
		TweenService:Create(bs, TweenInfo.new(0.1), {Color=ACCENT}):Play()
		task.delay(0.15, function() TweenService:Create(bs, TweenInfo.new(0.1), {Color=BORDER2}):Play() end)
		if onChange then onChange(options[idx], idx) end
	end)
	return btn
end

local function rowActionBtn(tabName, label, onClick)
	local b = Instance.new("TextButton", pg(tabName))
	b.Size = UDim2.new(1, 0, 0, 36)
	b.BackgroundColor3 = ACCENT
	b.BorderSizePixel = 0
	b.Text = label
	b.TextColor3 = WHITE
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.LayoutOrder = lo(tabName)
	b.ZIndex = 5
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 7)
	b.MouseButton1Click:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.08), {BackgroundColor3=ACCENT_CLICK}):Play()
		task.delay(0.15, function() TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3=ACCENT}):Play() end)
		if onClick then pcall(onClick) end
	end)
	b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3=ACCENT_HOV}):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.1), {BackgroundColor3=ACCENT}):Play() end)
	return b
end

local pbFrame = Instance.new("Frame", gui)
pbFrame.Size = UDim2.new(0, 250, 0, 44)
pbFrame.Position = UDim2.new(0.5, -125, 1, -62)
pbFrame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
pbFrame.BorderSizePixel = 0
pbFrame.Active = false
Instance.new("UICorner", pbFrame).CornerRadius = UDim.new(0, 14)
Instance.new("UIStroke", pbFrame).Color = ACCENT

progressPct = Instance.new("TextLabel", pbFrame)
progressPct.Size = UDim2.new(1, -16, 0, 16)
progressPct.Position = UDim2.new(0, 8, 0, 4)
progressPct.BackgroundTransparency = 1
progressPct.Text = "0%"
progressPct.TextColor3 = WHITE
progressPct.Font = Enum.Font.GothamBlack
progressPct.TextSize = 10
progressPct.TextXAlignment = Enum.TextXAlignment.Center
progressPct.TextYAlignment = Enum.TextYAlignment.Center
progressPct.ZIndex = 4

progressRadLbl = Instance.new("TextLabel", pbFrame)
progressRadLbl.Size = UDim2.new(0, 130, 0, 16)
progressRadLbl.Position = UDim2.new(0, 8, 0, 25)
progressRadLbl.BackgroundTransparency = 1
progressRadLbl.Text = "Radius: "..Steal.StealRadius
progressRadLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
progressRadLbl.Font = Enum.Font.GothamBold
progressRadLbl.TextSize = 9
progressRadLbl.TextXAlignment = Enum.TextXAlignment.Left
progressRadLbl.ZIndex = 4
do
	local pbMenuBtn = Instance.new("TextButton")
	pbMenuBtn.Parent = pbFrame
	pbMenuBtn.Size = UDim2.new(0, 48, 0, 14)
	pbMenuBtn.Position = UDim2.new(1, -56, 0, 23)
	pbMenuBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	pbMenuBtn.BorderSizePixel = 0
	pbMenuBtn.Text = "Menu"
	pbMenuBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	pbMenuBtn.Font = Enum.Font.GothamBold
	pbMenuBtn.TextSize = 9
	pbMenuBtn.ZIndex = 5
	Instance.new("UICorner", pbMenuBtn).CornerRadius = UDim.new(0, 5)
	pbMenuBtn.MouseButton1Click:Connect(function()
		if main.Visible then
			main.Visible = false; mini.Visible = false; State.guiVisible = false
		else
			main.Visible = true; mini.Visible = false; State.guiVisible = true
		end
	end)
end

do
	-- Single label: "FPS: 59 | 📡 206ms" centered between Radius and Menu
	local fpsLbl = Instance.new("TextLabel")
	fpsLbl.Parent = pbFrame
	fpsLbl.Size = UDim2.new(0, 130, 0, 16)
	fpsLbl.Position = UDim2.new(0.5, -65, 0, 25)
	fpsLbl.BackgroundTransparency = 1
	fpsLbl.Text = "FPS: -- | 📡 --ms"
	fpsLbl.TextColor3 = Color3.fromRGB(200, 200, 200)
	fpsLbl.Font = Enum.Font.GothamBold
	fpsLbl.TextSize = 8
	fpsLbl.TextXAlignment = Enum.TextXAlignment.Center
	fpsLbl.ZIndex = 5
	local pingLbl = fpsLbl  -- alias so update loop still works
	local _fpsCount, _fpsTimer = 0, 0
	RunService.Heartbeat:Connect(function(dt)
		_fpsCount = _fpsCount + 1
		_fpsTimer = _fpsTimer + dt
		if _fpsTimer >= 0.5 then
			local fps = math.floor(_fpsCount / _fpsTimer)
			local ping = math.floor(game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue())
			local pingColor
			if ping <= 50 then pingColor = Color3.fromRGB(0, 210, 0)
			elseif ping <= 100 then pingColor = Color3.fromRGB(255, 220, 0)
			elseif ping <= 200 then pingColor = Color3.fromRGB(255, 140, 0)
			else pingColor = Color3.fromRGB(255, 40, 40) end
			-- Use RichText to color only the ping part
			fpsLbl.RichText = true
			local r,g,b = math.floor(pingColor.R*255), math.floor(pingColor.G*255), math.floor(pingColor.B*255)
			fpsLbl.Text = string.format('FPS: %d | <font color="rgb(%d,%d,%d)">📡 %dms</font>', fps, r, g, b, ping)
			_fpsCount, _fpsTimer = 0, 0
		end
	end)
end

local pbBg = Instance.new("Frame", pbFrame)
pbBg.Size = UDim2.new(1, -16, 0, 16)
pbBg.Position = UDim2.new(0, 8, 0, 4)
pbBg.BackgroundColor3 = Color3.fromRGB(20, 8, 8)
pbBg.BorderSizePixel = 0
Instance.new("UICorner", pbBg).CornerRadius = UDim.new(0, 10)
progressFill = Instance.new("Frame", pbBg)
progressFill.Size = UDim2.new(0, 0, 1, 0)
progressFill.BackgroundColor3 = ACCENT
progressFill.BorderSizePixel = 0
Instance.new("UICorner", progressFill).CornerRadius = UDim.new(0, 10)

local function resetProgressBar()
	progressPct.Text = "0%"
	progressFill.Size = UDim2.new(0,0,1,0)
	if progressRadLbl then progressRadLbl.Visible = true end
end

do -- tab content scope
makeSecHeader("Speed", "Speed Configuration")
normalBox = rowInput("Speed", "Normal Speed", nil, NS, function(v) if v>0 and v<=500 then NS=v end end)
carryBox  = rowInput("Speed", "Carry Speed",  nil, CS, function(v) if v>0 and v<=500 then CS=v end end)
laggerBox = rowInput("Speed", "Lagger Speed", nil, LS, function(v) if v>0 and v<=500 then LS=v end end)
laggerBox2 = rowInput("Speed", "Lagger Carry Speed", nil, LS2, function(v) if v>0 and v<=500 then LS2=v end end)

do
	local c = baseCard("Speed", 38)
	cLabel(c, "Mode", 10, 80, 11, WHITE, Enum.Font.GothamBold)
	modeValLbl = cLabel(c, "Normal", 88, 80, 10, DIM, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	local kb = makeKB(c, KB.Speed, function(k) end)
	kb.Position = UDim2.new(1, -(44+10), 0.5, -10)
	kb.ZIndex = 11
	local clk = Instance.new("TextButton", c)
	clk.Size = UDim2.new(0.65, 0, 1, 0)
	clk.BackgroundTransparency = 1
	clk.Text = ""
	clk.ZIndex = 6
	clk.Active = true
	clk.Activated:Connect(function()
		if _anyKeyListening then return end
		State.speedToggled = not State.speedToggled
		if State.speedToggled then State.laggerToggled = false; if mobileLaggerSetActive then mobileLaggerSetActive(false) end end
		modeValLbl.Text = State.laggerToggled and "Lagger" or (State.speedToggled and "Carry" or "Normal")
	end)
end

do
	local c = baseCard("Speed", 38)
	cLabel(c, "Lagger Mode", 10, 120, 11, WHITE, Enum.Font.GothamBold)
	local kb = makeKB(c, KB.Lagger, function(k) KB.Lagger.kb = k end)
	kb.Position = UDim2.new(1, -(44+10), 0.5, -10)
	kb.ZIndex = 11
	local clk = Instance.new("TextButton", c)
	clk.Size = UDim2.new(0.65, 0, 1, 0)
	clk.BackgroundTransparency = 1
	clk.Text = ""
	clk.ZIndex = 6
	clk.Active = true
	clk.Activated:Connect(function()
		if _anyKeyListening then return end
		State.laggerToggled = not State.laggerToggled
		if State.laggerToggled then State.speedToggled = false; if mobileSpeedSetActive then mobileSpeedSetActive(false) end end
		modeValLbl.Text = State.laggerToggled and "Lagger" or (State.speedToggled and "Carry" or "Normal")
		if mobileLaggerSetActive then mobileLaggerSetActive(State.laggerToggled) end
	end)
end

makeSecHeader("Bat Aimbot", "Bat Combat")
do
	local sv
	sv, _ = rowToggleKB("Bat Aimbot", "Auto Bat", nil, KB.AutoBat, false,
	function(on)
		State.autoBatToggled = on
		if on then startBatAimbot() else stopBatAimbot() end
	end,
	function(k) KB.AutoBat.kb = k end)
	autoBatSetVisual = sv -- will be extended after panel is built
	setAutoBat = sv       -- keep reference to UI row setter
end

makeSecHeader("Mechanics", "Game Mechanics")
setAutoGrab = rowToggle("Mechanics", "Auto Grab", nil, false, function(on)
	Steal.AutoStealEnabled = on
	if on then if not pcall(startAutoSteal) then Steal.AutoStealEnabled = false; setAutoGrab(false) end
	else stopAutoSteal() end
end)

do
	local c = baseCard("Mechanics", 38)
	cLabel(c, "Grab Radius", 10, 120, 11, WHITE, Enum.Font.GothamBold)
	radValBtn = Instance.new("TextButton", c)
	radValBtn.Size = UDim2.new(0, 64, 0, 24)
	radValBtn.Position = UDim2.new(1, -74, 0.5, -12)
	radValBtn.BackgroundColor3 = INPUT_BG
	radValBtn.BorderSizePixel = 0
	radValBtn.Text = tostring(Steal.StealRadius)
	radValBtn.TextColor3 = WHITE
	radValBtn.Font = Enum.Font.GothamBold
	radValBtn.TextSize = 11
	radValBtn.ZIndex = 11
	Instance.new("UICorner", radValBtn).CornerRadius = UDim.new(0, 5)
	Instance.new("UIStroke", radValBtn).Color = BORDER2
	local typing2 = false
	radValBtn.Activated:Connect(function()
		if typing2 then return end; typing2 = true
		local tb = Instance.new("TextBox", c)
		tb.Size = radValBtn.Size; tb.Position = radValBtn.Position
		tb.BackgroundColor3 = CARD_HOV; tb.BorderSizePixel = 0
		tb.Text = tostring(Steal.StealRadius)
		tb.TextColor3 = WHITE; tb.Font = Enum.Font.GothamBold; tb.TextSize = 11
		tb.ClearTextOnFocus = false; tb.ZIndex = 12
		Instance.new("UICorner", tb).CornerRadius = UDim.new(0, 5)
		Instance.new("UIStroke", tb).Color = ACCENT
		tb:CaptureFocus()
		tb.FocusLost:Connect(function()
			local num = tonumber(tb.Text)
			if num and num>=5 and num<=300 then
				Steal.StealRadius = math.floor(num)
				radValBtn.Text = tostring(Steal.StealRadius)
				progressRadLbl.Text = "Radius: "..Steal.StealRadius
				Steal.cachedPrompts = {}; Steal.promptCacheTime = 0
			end
			tb:Destroy(); typing2 = false
		end)
	end)
end

setInfJump       = rowToggle("Mechanics", "Infinite Jump",  nil, false, function(on) State.infJumpEnabled = on end)
-- Jump Method: two-button toggle (Manual | Hold) styled like the reference UI
local jumpMethodBtn
do
	local JUMP_PINK   = Color3.fromRGB(255, 50, 50)  -- Changed to red like other toggles
	local JUMP_INACTIVE = Color3.fromRGB(44, 10, 12)
	local jc = baseCard("Mechanics", 38)
	cLabel(jc, "Jump Method", 10, 160, 11, WHITE, Enum.Font.GothamBold)

	local btnContainer = Instance.new("Frame", jc)
	btnContainer.Size = UDim2.new(0, 148, 0, 26)
	btnContainer.Position = UDim2.new(1, -158, 0.5, -13)
	btnContainer.BackgroundTransparency = 1
	btnContainer.BorderSizePixel = 0
	btnContainer.ZIndex = 11
	local btnLayout = Instance.new("UIListLayout", btnContainer)
	btnLayout.FillDirection = Enum.FillDirection.Horizontal
	btnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	btnLayout.Padding = UDim.new(0, 6)

	local function makeJumpBtn(label, order)
		local b = Instance.new("TextButton", btnContainer)
		b.Size = UDim2.new(0, 71, 1, 0)
		b.BackgroundColor3 = JUMP_INACTIVE
		b.BorderSizePixel = 0
		b.Text = label
		b.TextColor3 = WHITE
		b.Font = Enum.Font.GothamBold
		b.TextSize = 11
		b.ZIndex = 12
		b.LayoutOrder = order
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
		return b
	end

	local manualBtn = makeJumpBtn("Manual", 1)
	local holdBtn   = makeJumpBtn("Hold",   2)

	local function setJumpMethod(val)
		State.jumpMethod = val
		if val == "Tap" then
			TweenService:Create(manualBtn, TweenInfo.new(0.12), {BackgroundColor3 = JUMP_PINK}):Play()
			TweenService:Create(holdBtn,   TweenInfo.new(0.12), {BackgroundColor3 = JUMP_INACTIVE}):Play()
		else
			TweenService:Create(holdBtn,   TweenInfo.new(0.12), {BackgroundColor3 = JUMP_PINK}):Play()
			TweenService:Create(manualBtn, TweenInfo.new(0.12), {BackgroundColor3 = JUMP_INACTIVE}):Play()
		end
	end

	-- Default: Manual (Tap) active
	setJumpMethod("Tap")

	manualBtn.MouseButton1Click:Connect(function() setJumpMethod("Tap") end)
	holdBtn.MouseButton1Click:Connect(function() setJumpMethod("Hold") end)

	-- Expose a .Text property shim so existing code that writes jumpMethodBtn.Text still works
	jumpMethodBtn = setmetatable({}, {
		__newindex = function(_, k, v)
			if k == "Text" then setJumpMethod(v) end
		end,
		__index = function(_, k)
			if k == "Text" then return State.jumpMethod end
		end,
	})
end
setAntiRag       = rowToggle("Mechanics", "Anti Ragdoll",   nil, false, function(on) State.antiRagdollEnabled=on; if on then startAntiRagdoll() else stopAntiRagdoll() end end)
setMedusaCounter = rowToggle("Mechanics", "Medusa Counter", nil, false, function(on) State.medusaCounterEnabled=on; if on then setupMedusaCounter(LP.Character) else stopMedusaCounter() end end)
setBatCounter    = rowToggle("Mechanics", "Bat Counter",    nil, false, function(on) State.batCounterEnabled=on; if on then startBatCounter() else stopBatCounter() end end)

makeSecHeader("Movement", "Movement & Teleport")

-- ── Mode Toggle (Full Auto Play / Semi Auto Play) ────────────────────────
do
	local isFullAuto = true
	local modeCard = Instance.new("Frame", pg("Movement"))
	modeCard.Size = UDim2.new(1, 0, 0, 38)
	modeCard.BackgroundColor3 = CARD_BG
	modeCard.BorderSizePixel = 0
	modeCard.LayoutOrder = lo("Movement")
	modeCard.ZIndex = 4
	Instance.new("UICorner", modeCard).CornerRadius = UDim.new(0, 7)
	local modeStroke = Instance.new("UIStroke", modeCard)
	modeStroke.Color = BORDER
	modeStroke.Thickness = 1

	local modeLbl = Instance.new("TextLabel", modeCard)
	modeLbl.Size = UDim2.new(1, 0, 1, 0)
	modeLbl.BackgroundTransparency = 1
	modeLbl.Text = "Mode: Full Auto Play"
	modeLbl.TextColor3 = WHITE
	modeLbl.Font = Enum.Font.GothamBold
	modeLbl.TextSize = 12
	modeLbl.TextXAlignment = Enum.TextXAlignment.Center
	modeLbl.ZIndex = 6

	local modeBtn = Instance.new("TextButton", modeCard)
	modeBtn.Size = UDim2.new(1, 0, 1, 0)
	modeBtn.BackgroundTransparency = 1
	modeBtn.Text = ""
	modeBtn.ZIndex = 7
	modeBtn.MouseButton1Click:Connect(function()
		isFullAuto = not isFullAuto
		if isFullAuto then
			modeLbl.Text = "Mode: Full Auto Play"
			State.movementMode = "FullAuto"
			TweenService:Create(modeStroke, TweenInfo.new(0.18), {Color = BORDER}):Play()
			-- Stop semi auto left/right when entering Full Auto
			if alConn then alConn:Disconnect(); alConn = nil end
			if arConn then arConn:Disconnect(); arConn = nil end
		else
			modeLbl.Text = "Mode: Semi Auto Play"
			State.movementMode = "SemiAuto"
			TweenService:Create(modeStroke, TweenInfo.new(0.18), {Color = ACCENT}):Play()
			-- Stop any running Misco route when leaving Full Auto
			stopFullAutoPlay()
			-- Resume semi auto if was enabled
			if State.autoLeftEnabled then startAutoLeft() end
			if State.autoRightEnabled then startAutoRight() end
		end
		-- Use State so the billboard always gets the latest text regardless of spawn order
		if State._modeBillLbl then
			State._modeBillLbl.Text = isFullAuto and "Mode: Full" or "Mode: Semi"
		end
		-- Show Lagger Carry button only in Semi Auto
		if lcBtn then lcBtn.Visible = not isFullAuto end
	end)

	modeCard.MouseEnter:Connect(function() TweenService:Create(modeCard, TweenInfo.new(0.1), {BackgroundColor3=CARD_HOV}):Play() end)
	modeCard.MouseLeave:Connect(function() TweenService:Create(modeCard, TweenInfo.new(0.1), {BackgroundColor3=CARD_BG}):Play() end)

	-- Allow loadConfig to restore the mode toggle visual
	getgenv()._zenithSetMovementModeVisual = function(mode)
		isFullAuto = (mode ~= "SemiAuto")
		modeLbl.Text = isFullAuto and "Mode: Full Auto Play" or "Mode: Semi Auto Play"
		modeStroke.Color = isFullAuto and BORDER or ACCENT
		if State._modeBillLbl then State._modeBillLbl.Text = isFullAuto and "Mode: Full" or "Mode: Semi" end
		if lcBtn then lcBtn.Visible = not isFullAuto end
	end
end

do
	local sv
	sv, _ = rowToggleKB("Movement", "Auto Left", nil, KB.AutoLeft, false,
	function(on)
		State.autoLeftEnabled = on
		if on then
			if State.autoRightEnabled then State.autoRightEnabled=false; if autoRightSetVisual then autoRightSetVisual(false) end; stopAutoRight() end
			if State.autoBatToggled then State.autoBatToggled=false; if autoBatSetVisual then autoBatSetVisual(false) end; stopBatAimbot() end
			startAutoLeft()
		else stopAutoLeft() end
		if autoLeftSetVisual then autoLeftSetVisual(State.autoLeftEnabled) end
	end, function(k) KB.AutoLeft.kb=k end)
	autoLeftSetVisual = sv
end
do
	local sv
	sv, _ = rowToggleKB("Movement", "Auto Right", nil, KB.AutoRight, false,
	function(on)
		State.autoRightEnabled = on
		if on then
			if State.autoLeftEnabled then State.autoLeftEnabled=false; if autoLeftSetVisual then autoLeftSetVisual(false) end; stopAutoLeft() end
			if State.autoBatToggled then State.autoBatToggled=false; if autoBatSetVisual then autoBatSetVisual(false) end; stopBatAimbot() end
			startAutoRight()
		else stopAutoRight() end
		if autoRightSetVisual then autoRightSetVisual(State.autoRightEnabled) end
	end, function(k) KB.AutoRight.kb=k end)
	autoRightSetVisual = sv
end
rowKBOnly("Movement", "Drop",    nil, KB.Drop,   function(k) KB.Drop.kb=k end)
rowKBOnly("Movement", "TP Down", nil,       KB.TPDown, function(k) KB.TPDown.kb=k end)

do
	setAutoTPDownVisual = rowToggle("Movement", "Auto TP Down", nil, false, function(on)
		autoTPDownEnabled = on
		if on then startAutoTPDown() else stopAutoTPDown() end
	end)
	rowInput("Movement", "TP Down Height", nil, autoTPDownHeight, function(v)
		autoTPDownHeight = math.clamp(v, 0, 500)
	end)
end

-- ── Stretch Rez ──────────────────────────────────────────────────────────
local stretchRezConn = nil
local function enableStretchRez()
	State.stretchRezEnabled = true
	workspace.CurrentCamera.FieldOfView = 120
	if stretchRezConn then stretchRezConn:Disconnect() end
	stretchRezConn = RunService.RenderStepped:Connect(function()
		if not State.stretchRezEnabled then stretchRezConn:Disconnect(); stretchRezConn = nil; return end
		workspace.CurrentCamera.FieldOfView = 120
	end)
end
local function disableStretchRez()
	State.stretchRezEnabled = false
	if stretchRezConn then stretchRezConn:Disconnect(); stretchRezConn = nil end
	workspace.CurrentCamera.FieldOfView = 70
end

-- ── Dark Mode ───────────────────────────────────────────────────────────
local _darkEnabled = false
local _defBrightness = game:GetService("Lighting").Brightness
local _defClock = game:GetService("Lighting").ClockTime
local _defAmbient = game:GetService("Lighting").OutdoorAmbient
local function enableDarkMode()
	_darkEnabled = true; State.darkModeEnabled = true
	local Lighting = game:GetService("Lighting")
	local sky = Lighting:FindFirstChild("GalaxySky") or Instance.new("Sky")
	sky.Name = "GalaxySky"
	sky.SkyboxBk = "rbxassetid://159454299"
	sky.SkyboxDn = "rbxassetid://159454296"
	sky.SkyboxFt = "rbxassetid://159454293"
	sky.SkyboxLf = "rbxassetid://159454286"
	sky.SkyboxRt = "rbxassetid://159454289"
	sky.SkyboxUp = "rbxassetid://159454291"
	sky.Parent = Lighting
	Lighting.Brightness = 0
	Lighting.ClockTime = 0
	Lighting.ExposureCompensation = -2
	Lighting.OutdoorAmbient = Color3.fromRGB(0, 0, 0)
end
local function disableDarkMode()
	_darkEnabled = false; State.darkModeEnabled = false
	local Lighting = game:GetService("Lighting")
	local sky = Lighting:FindFirstChild("GalaxySky")
	if sky then sky:Destroy() end
	Lighting.Brightness = _defBrightness
	Lighting.ClockTime = _defClock
	Lighting.ExposureCompensation = 0
	Lighting.OutdoorAmbient = _defAmbient
end

-- ── Performance Tab UI ───────────────────────────────────────────────────
makeSecHeader("Performance", "Performance")

setUnwalkToggle  = rowToggle("Performance", "Unwalk",         nil, false, function(on) State.unwalkEnabled=on; if on then startUnwalk() else stopUnwalk() end end)

-- ── Anti Lag ─────────────────────────────────────────────────────────────
do
	local _Lighting = game:GetService("Lighting")
	local _antiLagConn = nil

	local function applyAntiLag(instance)
		if instance:IsA("ParticleEmitter") then
			instance.Enabled = false
		elseif instance:IsA("Decal") then
			instance.Transparency = 1
		elseif instance:IsA("BasePart") then
			instance.Material = Enum.Material.Plastic
			instance.Reflectance = 0
			instance.CastShadow = false
		end
	end

	local function optimizeLighting()
		_Lighting.GlobalShadows = false
		_Lighting.FogEnd = 9e9
		_Lighting.Brightness = 1
		_Lighting.EnvironmentDiffuseScale = 0
		_Lighting.EnvironmentSpecularScale = 0
		for _, child in pairs(_Lighting:GetChildren()) do
			if child:IsA("BloomEffect") or child:IsA("BlurEffect") or child:IsA("SunRaysEffect") then
				child.Enabled = false
			end
		end
	end

	local function enableAntiLag()
		optimizeLighting()
		for _, desc in pairs(workspace:GetDescendants()) do
			applyAntiLag(desc)
			if desc:IsA("Accessory") then desc:Destroy() end
		end
		if _antiLagConn then _antiLagConn:Disconnect() end
		_antiLagConn = workspace.DescendantAdded:Connect(function(desc)
			applyAntiLag(desc)
			if desc:IsA("Accessory") then desc:Destroy() end
		end)
	end

	local function disableAntiLag()
		if _antiLagConn then _antiLagConn:Disconnect(); _antiLagConn = nil end
	end

	setAntiLag = function(on)
		State.antiLagEnabled = on
		if on then enableAntiLag() else disableAntiLag() end
	end
	local setAntiLagVisual = rowToggle("Performance", "Anti Lag", nil, false, function(on) setAntiLag(on) end)
	local _origSetAntiLag = setAntiLag
	setAntiLag = function(on) setAntiLagVisual(on); _origSetAntiLag(on) end
end

-- ── TIMER ──────────────────────────────────────────────────────────────────────
do
	local STUN_DURATION = 3.0   -- seconds the ragdoll lasts
	
	local timerEnabled      = false
	local stunActive        = false
	local stunStartTime     = 0
	local lastDisplayedSec  = nil
	local stunConnection    = nil
	local stateChangedConn  = nil
	local billboardGui      = nil
	local timerLabel        = nil

	-- CREATE BILLBOARD ABOVE THE LOCAL PLAYER'S HEAD
	local function createBillboard()
		if billboardGui then return end
		local char = LP.Character
		if not char then return end
		local head = char:FindFirstChild("Head")
		if not head then return end

		billboardGui = Instance.new("BillboardGui")
		billboardGui.Name         = "RagdollTimerBB"
		billboardGui.Adornee      = head
		billboardGui.Size         = UDim2.new(0, 120, 0, 40)
		billboardGui.StudsOffset  = Vector3.new(0, 5.5, 0)
		billboardGui.AlwaysOnTop  = true
		billboardGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
		billboardGui.Parent       = LP:FindFirstChildOfClass("PlayerGui") or game:GetService("CoreGui")

		timerLabel = Instance.new("TextLabel", billboardGui)
		timerLabel.Size                  = UDim2.new(1, 0, 1, 0)
		timerLabel.BackgroundTransparency = 1
		timerLabel.Text                  = ""
		timerLabel.Font                  = Enum.Font.GothamBlack
		timerLabel.TextSize              = 28
		timerLabel.TextStrokeTransparency = 0.4
		timerLabel.TextStrokeColor3      = Color3.fromRGB(0, 0, 0)
		timerLabel.TextXAlignment        = Enum.TextXAlignment.Center
		timerLabel.TextYAlignment        = Enum.TextYAlignment.Center
	end

	-- UPDATE THE DISPLAY EVERY HEARTBEAT
	local function updateDisplay()
		if not timerLabel then return end

		-- Ragdoll finished → show "Steal!!"
		if not stunActive then
			timerLabel.Text      = "Steal!!"
			timerLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
			timerLabel.TextSize  = 22
			if billboardGui then billboardGui.Enabled = timerEnabled end
			return
		end

		local elapsed   = tick() - stunStartTime
		local remaining = math.max(0, STUN_DURATION - elapsed)

		-- Timer just ran out → flip to "Steal!!"
		if remaining <= 0 then
			stunActive = false
			if stunConnection then stunConnection:Disconnect(); stunConnection = nil end
			timerLabel.Text       = "Steal!!"
			timerLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
			timerLabel.TextSize   = 22
			if billboardGui then billboardGui.Enabled = true end
			return
		end

		-- Show the countdown: 3 (green) → 2 (orange) → 1 (red)
		local second = math.ceil(remaining)
		if second ~= lastDisplayedSec then
			lastDisplayedSec     = second
			timerLabel.Text      = tostring(second)
			timerLabel.TextSize  = 36
			if second == 3 then
				timerLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
			elseif second == 2 then
				timerLabel.TextColor3 = Color3.fromRGB(255, 165, 0)
			elseif second == 1 then
				timerLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
			end
		end
		if billboardGui then billboardGui.Enabled = true end
	end

	-- CALLED WHEN RAGDOLL IS DETECTED
	local function onRagdollDetected()
		if not timerEnabled then return end
		if stunActive then return end   -- already counting

		stunActive       = true
		stunStartTime    = tick()
		lastDisplayedSec = nil

		createBillboard()
		updateDisplay()

		if stunConnection then stunConnection:Disconnect() end
		stunConnection = RunService.Heartbeat:Connect(updateDisplay)
	end

	-- LISTEN TO HUMANOID STATE CHANGES
	local function setupDetection(char)
		if stateChangedConn then stateChangedConn:Disconnect() end
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return end

		stateChangedConn = hum.StateChanged:Connect(function(_, newState)
			if not timerEnabled then return end
			local ragdolled = (
				newState == Enum.HumanoidStateType.Physics      or
				newState == Enum.HumanoidStateType.Ragdoll      or
				newState == Enum.HumanoidStateType.FallingDown
			)
			if ragdolled then
				onRagdollDetected()
			end
		end)
	end

	-- CHARACTER LIFECYCLE
	local function onCharacterAdded(char)
		-- Reset billboard (new head each spawn)
		if billboardGui then billboardGui:Destroy(); billboardGui = nil; timerLabel = nil end
		stunActive  = false
		if stunConnection then stunConnection:Disconnect(); stunConnection = nil end

		task.wait(0.5)  -- wait for character to fully load
		if timerEnabled then
			createBillboard()
			setupDetection(char)
		end
	end

	LP.CharacterAdded:Connect(onCharacterAdded)
	if LP.Character then
		task.spawn(function() onCharacterAdded(LP.Character) end)
	end

	rowToggle("Performance", "TIMER", nil, false, function(on)
		timerEnabled = on

		if timerEnabled then
			createBillboard()
			local char = LP.Character
			if char then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then
					local st = hum:GetState()
					if st == Enum.HumanoidStateType.Physics or
					   st == Enum.HumanoidStateType.Ragdoll or
					   st == Enum.HumanoidStateType.FallingDown then
						onRagdollDetected()
					end
				end
				setupDetection(char)
			end
		else
			if stunConnection then stunConnection:Disconnect(); stunConnection = nil end
			if stateChangedConn then stateChangedConn:Disconnect(); stateChangedConn = nil end
			stunActive = false
			if billboardGui then billboardGui.Enabled = false end
		end
	end)
end

setStretchRez = function(on) if on then enableStretchRez() else disableStretchRez() end end
local setStretchRezVisual = rowToggle("Performance", "FOV", nil, false, function(on) setStretchRez(on) end)
local _origStretchRez = setStretchRez
setStretchRez = function(on) setStretchRezVisual(on); _origStretchRez(on) end

-- ── Stretcher ────────────────────────────────────────────────────────────────
local _stretcherOn = false
local _stretcherSetVisual
do
	local gsEnabled = false
	local gsConn = nil
	local gsResConn = nil
	local function enableStretcher()
		gsEnabled = true; _stretcherOn = true
		if gsResConn then gsResConn:Disconnect() end
		gsResConn = RunService.RenderStepped:Connect(function()
			if not gsEnabled then return end
			workspace.CurrentCamera.CFrame = workspace.CurrentCamera.CFrame * CFrame.new(0,0,0, 1,0,0, 0,0.7,0, 0,0,1)
		end)
	end
	local function disableStretcher()
		gsEnabled = false; _stretcherOn = false
		if gsConn then gsConn:Disconnect(); gsConn = nil end
		if gsResConn then gsResConn:Disconnect(); gsResConn = nil end
	end
	_stretcherSetVisual = rowToggle("Performance", "Stretcher", nil, false, function(on)
		if on then enableStretcher() else disableStretcher() end
	end)
end

-- ── ESP Player ───────────────────────────────────────────────────────────────
local _espToggleFn = nil
local _espEnabled = false
pcall(function()
	-- ESP HIGHLIGHT
	local espObjects = {}   -- [Player] = { highlight, char }
	local espConn    = nil

	local function removeEsp(p)
		if espObjects[p] then
			pcall(function()
				if espObjects[p].highlight and espObjects[p].highlight.Parent then
					espObjects[p].highlight:Destroy()
				end
			end)
			espObjects[p] = nil
		end
	end

	local function createEsp(p)
		if p == LP then return end
		removeEsp(p)
		local char = p.Character
		if not char then return end
		if not char:FindFirstChild("HumanoidRootPart") then return end

		local hl = Instance.new("Highlight")
		hl.Name                = "ESP_HL"
		hl.Adornee             = char
		hl.FillColor           = Color3.fromRGB(200, 200, 200)
		hl.FillTransparency    = 0.93
		hl.OutlineColor        = Color3.fromRGB(220, 220, 220)
		hl.OutlineTransparency = 0.2
		hl.DepthMode           = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent              = workspace

		espObjects[p] = { highlight = hl, char = char }
	end

	local function startEsp()
		if espConn then return end
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP then createEsp(p) end
		end
		espConn = RunService.Heartbeat:Connect(function()
			for p, data in pairs(espObjects) do
				if not p or not p.Parent then
					removeEsp(p)
				elseif p.Character ~= data.char then
					removeEsp(p)
					createEsp(p)
				end
			end
		end)
	end

	local function stopEsp()
		if espConn then espConn:Disconnect(); espConn = nil end
		for p in pairs(espObjects) do removeEsp(p) end
		espObjects = {}
	end

	-- TRACERS
	local tracersEnabled = false
	local tracerLines    = {}
	local tracerConn     = nil

	local function clearTracers()
		for _, line in pairs(tracerLines) do
			pcall(function() line:Remove() end)
		end
		tracerLines = {}
	end

	local function updateTracers()
		if not tracersEnabled then
			clearTracers()
			return
		end

		local camera = workspace.CurrentCamera
		local char   = LP.Character
		local myHRP  = char and char:FindFirstChild("HumanoidRootPart")
		if not myHRP or not camera then clearTracers(); return end

		local validKeys = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= LP and plr.Character then
				local tHRP = plr.Character:FindFirstChild("HumanoidRootPart")
				if tHRP then
					validKeys[tostring(plr.UserId)] = { hrp = tHRP }
				end
			end
		end

		for key, line in pairs(tracerLines) do
			if not validKeys[key] then
				pcall(function() line:Remove() end)
				tracerLines[key] = nil
			end
		end

		local screenSize = camera.ViewportSize
		local fromX = screenSize.X / 2
		local fromY = screenSize.Y

		for key, data in pairs(validKeys) do
			local tPos, onScreen = camera:WorldToViewportPoint(data.hrp.Position)
			if onScreen then
				local line = tracerLines[key]
				if not line then
					line = Drawing.new("Line")
					line.Thickness    = 2
					line.Color        = Color3.fromRGB(255, 0, 0)
					line.Transparency = 0.3
					line.Visible      = true
					tracerLines[key]  = line
				end
				line.From    = Vector2.new(fromX, fromY)
				line.To      = Vector2.new(tPos.X, tPos.Y)
				line.Visible = true
			else
				local line = tracerLines[key]
				if line then line.Visible = false end
			end
		end
	end

	-- PLAYER LIFECYCLE HOOKS
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			task.wait(0.5)
			if _espEnabled then createEsp(p) end
		end)
	end)

	Players.PlayerRemoving:Connect(function(p)
		removeEsp(p)
	end)

	_espToggleFn = function(on)
		_espEnabled = on
		tracersEnabled = on
		if on then
			startEsp()
			-- Start tracer updates when ESP is enabled
			if tracerConn then tracerConn:Disconnect() end
			tracerConn = RunService.Heartbeat:Connect(updateTracers)
		else
			stopEsp()
			-- Stop tracer updates and clear tracers when ESP is disabled
			if tracerConn then tracerConn:Disconnect(); tracerConn = nil end
			clearTracers()
		end
	end
end)
rowToggle("Performance", "ESP Player", nil, false, function(on)
	if _espToggleFn then _espToggleFn(on) end
end)

-- ── X-RAY ─────────────────────────────────────────────────────────────────────
do
	local decorationTransparencyAmount = 0.75
	local decorationParts = {}
	local decorationOriginal = {}
	local decorationWatcher = nil
	local decorationEnabled = false

	local function getDecorationParts()
		local parts = {}
		local plots = workspace:FindFirstChild("Plots")
		if not plots then return parts end
		for _, plot in ipairs(plots:GetChildren()) do
			local decorations = plot:FindFirstChild("Decorations")
			if decorations then
				for _, part in ipairs(decorations:GetDescendants()) do
					if part:IsA("BasePart") then
						table.insert(parts, part)
					end
				end
			end
		end
		return parts
	end

	local function enableDecorationTransparency()
		local parts = getDecorationParts()
		for _, part in ipairs(parts) do
			if not decorationOriginal[part] then
				decorationOriginal[part] = part.Transparency
			end
			part.Transparency = decorationTransparencyAmount
			table.insert(decorationParts, part)
		end
	end

	local function disableDecorationTransparency()
		for part, orig in pairs(decorationOriginal) do
			if part and part.Parent then
				part.Transparency = orig
			end
		end
		decorationOriginal = {}
		decorationParts = {}
	end

	local function startDecorationWatcher()
		if decorationWatcher then decorationWatcher:Disconnect() end
		decorationWatcher = workspace.DescendantAdded:Connect(function(obj)
			if not decorationEnabled then return end
			if obj:IsA("BasePart") then
				local plots = workspace:FindFirstChild("Plots")
				if plots and obj:IsDescendantOf(plots) then
					local decorations = obj:FindFirstAncestor("Decorations")
					if decorations then
						if not decorationOriginal[obj] then
							decorationOriginal[obj] = obj.Transparency
						end
						task.wait(0.05)
						if obj and obj.Parent then
							obj.Transparency = decorationTransparencyAmount
						end
					end
				end
			end
		end)
	end

	local function stopDecorationWatcher()
		if decorationWatcher then
			decorationWatcher:Disconnect()
			decorationWatcher = nil
		end
	end

	local function setDecorationEnabled(state)
		decorationEnabled = state
		if state then
			enableDecorationTransparency()
			startDecorationWatcher()
		else
			stopDecorationWatcher()
			disableDecorationTransparency()
		end
	end

	rowToggle("Performance", "X-RAY", nil, false, function(on)
		setDecorationEnabled(on)
	end)
end

setDarkMode = function(on) if on then enableDarkMode() else disableDarkMode() end end
local setDarkModeVisual = rowToggle("Performance", "Dark Mode", nil, false, function(on) setDarkMode(on) end)
local _origDarkMode = setDarkMode
setDarkMode = function(on) setDarkModeVisual(on); _origDarkMode(on) end

makeSecHeader("Settings", "Interface & Binds")

setIntroToggle = rowToggle("Settings", "Play Intro", nil, State.introEnabled, function(on)
	State.introEnabled = on
	pcall(saveConfig)
end)

do
	local musicURLs = {
		"https://files.catbox.moe/zuid5n.mp3",
		"https://files.catbox.moe/z6eqnt.mp3",
		"https://files.catbox.moe/t0nlhv.mp3",
		"https://files.catbox.moe/mthg31.mp3",
		"https://files.catbox.moe/ddnbup.mp3",
		"https://files.catbox.moe/hg5cr4.mp3",
		"https://files.catbox.moe/nps6gk.mp3",
		"https://files.catbox.moe/iyw1cb.mp3",
		"https://files.catbox.moe/2w0wtv.mp3",
	}
	
	local currentPreviewSound = nil
	local isChangingMusic = false
	
	local function stopPreview()
		if currentPreviewSound then
			pcall(function() currentPreviewSound:Stop() end)
			pcall(function() currentPreviewSound:Destroy() end)
			currentPreviewSound = nil
		end
	end
	
	local function playPreview(idx)
		stopPreview()
		task.spawn(function()
			pcall(function()
				local tempFile = "ZenithHubPreview"
				writefile(tempFile, game:HttpGet(musicURLs[idx]))
				currentPreviewSound = Instance.new("Sound", gethui())
				currentPreviewSound.SoundId = getcustomasset(tempFile)
				currentPreviewSound.Volume = 0.5
				currentPreviewSound:Play()
				
				task.delay(10, function()
					stopPreview()
				end)
			end)
		end)
	end
	
	local c = baseCard("Settings", 38)
	cLabel(c, "Intro Music", 10, 130, 11, WHITE, Enum.Font.GothamBold)
	
	local musicBtn = Instance.new("TextButton", c)
	musicBtn.Size = UDim2.new(0, 80, 0, 24)
	musicBtn.Position = UDim2.new(1, -90, 0.5, -12)
	musicBtn.BackgroundColor3 = ACCENT
	musicBtn.BorderSizePixel = 0
	musicBtn.Text = "Music " .. State.selectedIntroMusic
	musicBtn.TextColor3 = WHITE
	musicBtn.Font = Enum.Font.GothamBold
	musicBtn.TextSize = 11
	musicBtn.ZIndex = 11
	Instance.new("UICorner", musicBtn).CornerRadius = UDim.new(0, 5)
    getgenv().ZenithMusicBtn = musicBtn
	
	musicBtn.Activated:Connect(function()
		if isChangingMusic then return end
		isChangingMusic = true
		
		stopPreview()
		task.wait(0.15)
		
		State.selectedIntroMusic = State.selectedIntroMusic + 1
		if State.selectedIntroMusic > #musicURLs then
			State.selectedIntroMusic = 1
		end
		
		musicBtn.Text = "Music " .. State.selectedIntroMusic
		playPreview(State.selectedIntroMusic)
		pcall(saveConfig)
		
		TweenService:Create(musicBtn, TweenInfo.new(0.1), {BackgroundColor3=ACCENT_CLICK}):Play()
		task.delay(0.15, function()
			TweenService:Create(musicBtn, TweenInfo.new(0.1), {BackgroundColor3=ACCENT}):Play()
		end)
		
		task.wait(0.5)
		isChangingMusic = false
	end)
	
	musicBtn.MouseEnter:Connect(function()
		TweenService:Create(musicBtn, TweenInfo.new(0.1), {BackgroundColor3=ACCENT_HOV}):Play()
	end)
	musicBtn.MouseLeave:Connect(function()
		TweenService:Create(musicBtn, TweenInfo.new(0.1), {BackgroundColor3=ACCENT}):Play()
	end)
end

uiScaleBox = rowInput("Settings", "UI Scale", nil, uiScaleValue, function(v)
	local n = math.clamp(math.floor(v + 0.5), 50, 150)
	uiScaleValue = n
	if mainUIScale then mainUIScale.Scale = n / 100 end
	pcall(saveConfig)
end)
rowKBOnly("Settings", "Hide / Show GUI", nil, KB.GuiHide, function(k) KB.GuiHide.kb=k end)
setLockUIVisual = rowToggle("Settings", "Lock UI", nil, false, function(on)
	uiLocked = on
	autoSavePositions()
end)
local _dragToggleSet; _dragToggleSet = rowToggle("Settings", "Drag Small Menus", nil, false, function(on)
	State.dragSmallMenus = on
	if setDragSmallMenus then setDragSmallMenus(on) end
end)
setDragSmallMenusVisual = function(on) if _dragToggleSet then _dragToggleSet(on) end end
local saveBtn; saveBtn = rowActionBtn("Settings", "Save Config", function()
	if saveConfig then
		pcall(function() saveConfig(saveBtn) end)
		if saveBtn then
			local prev = saveBtn.Text
			saveBtn.Text = "✓ Saved!"
			task.delay(1.5, function() if saveBtn and saveBtn.Parent then saveBtn.Text = prev end end)
		end
	end
end)
rowActionBtn("Settings", "Reset Mobile Buttons", function()
	if resetMobileButtons then resetMobileButtons() end
end)

end -- tab content scope

-- ==================== RUBY-STYLE MOBILE PANEL ====================
do
	local BTN_SIZE = 58
	local BTN_GAP  = 6
	local PADDING  = 6
	local COLS     = 2
	local ROWS     = 5
	local PANEL_W  = PADDING * 2 + COLS * BTN_SIZE + (COLS - 1) * BTN_GAP
	local PANEL_H  = PADDING * 2 + ROWS * BTN_SIZE + (ROWS - 1) * BTN_GAP

	MobilePanel = Instance.new("Frame")
	MobilePanel.Name = "MobileButtonsPanel"
	MobilePanel.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
	MobilePanel.Position = UDim2.new(1, -(PANEL_W + 20), 1, -(PANEL_H + 20))
	MobilePanel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	MobilePanel.BackgroundTransparency = 1
	MobilePanel.BorderSizePixel = 0
	MobilePanel.ZIndex = 95
	MobilePanel.Parent = gui
	-- no UICorner needed since panel is invisible

	makeDraggable(MobilePanel)
	MobilePanel.InputEnded:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			task.defer(function() pcall(saveConfig) end)
		end
	end)

	resetMobileButtons = function()
		MobilePanel.Position = UDim2.new(1, -(PANEL_W + 20), 1, -(PANEL_H + 20))
		task.defer(function() pcall(saveConfig) end)
	end

	-- OFF/default: red btn, white text  |  ON: black btn, red text
	local Q_OFF      = ACCENT
	local Q_ON       = Color3.fromRGB(8,4,4)
	local Q_TEXT_OFF = Color3.fromRGB(255, 255, 255)
	local Q_TEXT_ON  = ACCENT

	local function createMobileButton(name, displayText, col, row, isToggle, onAction)
		local xPos = PADDING + col * (BTN_SIZE + BTN_GAP)
		local yPos = PADDING + row * (BTN_SIZE + BTN_GAP)

		local btn = Instance.new("TextButton")
		btn.Name = "Btn_" .. name
		btn.Size = UDim2.new(0, BTN_SIZE, 0, BTN_SIZE)
		btn.Position = UDim2.new(0, xPos, 0, yPos)
		btn.BackgroundColor3 = Q_OFF
		btn.Text = displayText
		btn.TextColor3 = Q_TEXT_OFF
		btn.TextScaled = false; btn.TextSize = 11
		btn.Font = Enum.Font.GothamBold
		btn.TextWrapped = true; btn.LineHeight = 1.2
		btn.BorderSizePixel = 0; btn.AutoButtonColor = false
		btn.ZIndex = 99
		btn.Parent = MobilePanel
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)

		-- rotating red "walking" border highlight for press feedback
		local flashStroke = Instance.new("UIStroke", btn)
		flashStroke.Thickness = 2
		flashStroke.Transparency = 1
		flashStroke.Color = ACCENT
		local flashGrad = Instance.new("UIGradient", flashStroke)
		flashGrad.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, ACCENT_HOV),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(8,4,4)),
			ColorSequenceKeypoint.new(1, ACCENT_HOV),
		})
		flashGrad.Rotation = 0

		local isOn = false
		local function playBorderEffect()
			flashStroke.Transparency = 0
			flashGrad.Rotation = 0
			TweenService:Create(flashGrad, TweenInfo.new(0.5, Enum.EasingStyle.Linear), {Rotation = 360}):Play()
			task.delay(0.5, function()
				if not isOn then
					TweenService:Create(flashStroke, TweenInfo.new(0.2), {Transparency = 1}):Play()
				end
			end)
		end
		local function setter(s)
			isOn = s
			TweenService:Create(btn, TweenInfo.new(0.15), {
				BackgroundColor3 = s and Q_ON or Q_OFF,
				TextColor3       = s and Q_TEXT_ON or Q_TEXT_OFF,
			}):Play()
			if s then
				playBorderEffect()
			else
				TweenService:Create(flashStroke, TweenInfo.new(0.2), {Transparency = 1}):Play()
			end
		end

		-- flash feedback for non-toggle buttons
		local function flash()
			TweenService:Create(btn, TweenInfo.new(0.08), {BackgroundColor3=Q_ON, TextColor3=Q_TEXT_ON}):Play()
			playBorderEffect()
			task.delay(0.22, function()
				TweenService:Create(btn, TweenInfo.new(0.15), {BackgroundColor3=Q_OFF, TextColor3=Q_TEXT_OFF}):Play()
			end)
		end

		btn.Activated:Connect(function()
			if isToggle then
				isOn = not isOn; setter(isOn)
				if onAction then onAction(isOn) end
			else
				flash()
				if onAction then onAction() end
			end
		end)

		return btn, setter
	end

	-- Row 0: AUTO LEFT | AUTO RIGHT
	-- Row 1: BAT AIMBOT | TP DOWN
	-- Row 2: DROP | CARRY SPD
	-- Row 3: LAGGER MODE
	local _, saAL = createMobileButton("AutoLeft", "AUTO\nLEFT", 0, 0, true, function(on)
		State.autoLeftEnabled = on
		if on then
			if State.autoRightEnabled then State.autoRightEnabled=false; if autoRightSetVisual then autoRightSetVisual(false) end; stopAutoRight() end
			if State.autoBatToggled then State.autoBatToggled=false; if autoBatSetVisual then autoBatSetVisual(false) end; stopBatAimbot() end
			startAutoLeft()
		else stopAutoLeft() end
		if autoLeftSetVisual then autoLeftSetVisual(State.autoLeftEnabled) end
	end)
	autoLeftSetVisual = function(on) saAL(on) end

	local _, saAR = createMobileButton("AutoRight", "AUTO\nRIGHT", 1, 0, true, function(on)
		State.autoRightEnabled = on
		if on then
			if State.autoLeftEnabled then State.autoLeftEnabled=false; if autoLeftSetVisual then autoLeftSetVisual(false) end; stopAutoLeft() end
			if State.autoBatToggled then State.autoBatToggled=false; if autoBatSetVisual then autoBatSetVisual(false) end; stopBatAimbot() end
			startAutoRight()
		else stopAutoRight() end
		if autoRightSetVisual then autoRightSetVisual(State.autoRightEnabled) end
	end)
	autoRightSetVisual = function(on) saAR(on) end

	local _, saAB = createMobileButton("AutoBat", "BAT\nAIMBOT", 0, 1, true, function(on)
		State.autoBatToggled = on
		if on then startBatAimbot() else stopBatAimbot() end
	end)
	autoBatSetVisual = function(on) saAB(on); if setAutoBat then setAutoBat(on) end end

	createMobileButton("TPDown", "TP\nDOWN", 1, 1, false, function() task.spawn(runTPDown) end)

	createMobileButton("Drop", "DROP\nBR", 0, 2, false, function() task.spawn(runDrop) end)

	local _, saCS = createMobileButton("Speed", "CARRY\nSPD", 1, 2, true, function(on)
		State.speedToggled = on; State.laggerToggled = false; laggerPhase = 0
		if mobileLaggerSetActive then mobileLaggerSetActive(false) end
		if modeValLbl then modeValLbl.Text = on and "Carry" or "Normal" end
	end)
	mobileSpeedSetActive = function(on) saCS(on) end

	local _, saLM = createMobileButton("Lagger", "LAGGER\nMODE", 0, 3, true, function(on)
		State.laggerToggled = on; laggerPhase = on and 1 or 0
		if on then
			State.speedToggled = false
			if mobileSpeedSetActive then mobileSpeedSetActive(false) end
			if modeValLbl then modeValLbl.Text = "Lagger" end
		else
			laggerPhase = 0
			if modeValLbl then modeValLbl.Text = "Normal" end
		end
	end)
	mobileLaggerSetActive = function(on) saLM(on); if not on then laggerPhase = 0 end end

	-- Lagger Carry button: uses laggerPhase=2 (LS2 speed), only visible in Semi Auto
	local saLC; lcBtn, saLC = createMobileButton("LaggerCarry", "LAGGER\nCARRY", 0, 4, true, function(on)
		if on then
			laggerPhase = 2; State.laggerToggled = true; State.speedToggled = false
			if mobileLaggerSetActive then saLM(true) end
			if modeValLbl then modeValLbl.Text = "Lagger Carry" end
		else
			laggerPhase = 1; State.laggerToggled = true
			if modeValLbl then modeValLbl.Text = "Lagger" end
		end
	end)
	-- Only show in Semi Auto mode; hide in Full Auto
	lcBtn.Visible = (State.movementMode == "SemiAuto")

	-- ── Taunt button ─────────────────────────────────────────────────────────
	do
		local TAUNT_MSG = "Zenith OWNS"
		local TAUNT_CD = 3
		local tauntOnCD = false
		local tauntBtn = createMobileButton("Taunt", "TAUNT", 1, 3, false, function()
			if tauntOnCD then return end
			tauntOnCD = true
			pcall(function()
				local ch = game:GetService("TextChatService"):WaitForChild("TextChannels"):WaitForChild("RBXGeneral")
				ch:SendAsync(TAUNT_MSG)
			end)
			task.delay(TAUNT_CD, function() tauntOnCD = false end)
		end)
	end

	mobileBtnActive.AutoLeft  = saAL
	mobileBtnActive.AutoRight = saAR
	mobileBtnActive.AutoBat   = saAB

	-- ── Per-button drag (Drag Small Menus) ──────────────────────────────────
	-- Collect all buttons with their default grid positions
	for _, btn in ipairs(MobilePanel:GetChildren()) do
		if btn:IsA("TextButton") then
			table.insert(allBtns, {btn=btn, defaultPos=btn.Position})
		end
	end

	local function makeBtnDraggable(btn)
		local dragging, dragStart, startPos = false, nil, nil
		btn.InputBegan:Connect(function(inp)
			if not State.dragSmallMenus then return end
			if uiLocked then return end
			if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				dragStart = inp.Position
				-- Convert btn absolute position to screen coords for free movement
				local absPos = btn.AbsolutePosition
				startPos = UDim2.new(0, absPos.X, 0, absPos.Y)
				inp.Changed:Connect(function()
					if inp.UserInputState == Enum.UserInputState.End then dragging = false end
				end)
			end
		end)
		UIS.InputChanged:Connect(function(inp)
			if not State.dragSmallMenus then return end
			if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
				local delta = inp.Position - dragStart
				btn.Position = UDim2.new(0, startPos.X.Offset + delta.X, 0, startPos.Y.Offset + delta.Y)
			end
		end)
		UIS.InputEnded:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
				if dragging then dragging = false; task.defer(function() pcall(saveConfig) end) end
			end
		end)
	end

	setDragSmallMenus = function(on)
		if on then
			local guiAbs   = gui.AbsolutePosition
			local panelAbs = MobilePanel.AbsolutePosition
			for _, entry in ipairs(allBtns) do
				local btn = entry.btn
				-- Only recalculate from panel position if freePos wasn't already set (e.g. by loadConfig)
				if not entry.freePos then
					local screenX = panelAbs.X - guiAbs.X + btn.Position.X.Offset
					local screenY = panelAbs.Y - guiAbs.Y + btn.Position.Y.Offset
					entry.freePos = UDim2.new(0, screenX, 0, screenY)
				end
			end
			for _, entry in ipairs(allBtns) do
				local btn = entry.btn
				btn.Parent = gui
				btn.Position = entry.freePos
				makeBtnDraggable(btn)
			end
			MobilePanel.Visible = false
		else
			-- Save current free positions before reparenting so buttons stay where dragged
			for _, entry in ipairs(allBtns) do
				entry.freePos = entry.btn.Position
			end
			local panelAbs = MobilePanel.AbsolutePosition
			local guiAbs   = gui.AbsolutePosition
			for _, entry in ipairs(allBtns) do
				local btn = entry.btn
				btn.Parent = MobilePanel
				-- Convert gui-relative free position back to panel-relative
				local relX = entry.freePos.X.Offset - (panelAbs.X - guiAbs.X)
				local relY = entry.freePos.Y.Offset - (panelAbs.Y - guiAbs.Y)
				btn.Position = UDim2.new(0, relX, 0, relY)
			end
			MobilePanel.Visible = true
			-- Clear freePos so next manual enable recalculates from current panel position
			for _, entry in ipairs(allBtns) do
				entry.freePos = nil
			end
		end
	end

	-- Override resetMobileButtons so it also restores buttons to default grid positions
	resetMobileButtons = function()
		-- If drag mode is on, reattach all buttons back to panel first
		if State.dragSmallMenus then
			for _, entry in ipairs(allBtns) do
				entry.btn.Parent = MobilePanel
			end
			MobilePanel.Visible = true
			State.dragSmallMenus = false
			-- Turn off the toggle visual if possible
			if setDragSmallMenusVisual then setDragSmallMenusVisual(false) end
		end
		-- Reset every button to its original grid position
		for _, entry in ipairs(allBtns) do
			entry.btn.Position = entry.defaultPos
		end
		-- Reset panel to default screen position
		MobilePanel.Position = UDim2.new(1, -(PANEL_W + 20), 1, -(PANEL_H + 20))
		task.defer(function() pcall(saveConfig) end)
	end
end

saveConfig = function(btn)
	local function ks(e) return {kb=e.kb and e.kb.Name or nil, gp=e.gp and e.gp.Name or nil} end
	local cfg = {
		normalSpeed=NS, carrySpeed=CS, laggerSpeed=LS,
		introEnabled=State.introEnabled,
		selectedIntroMusic=State.selectedIntroMusic,
		autoLeftKey=ks(KB.AutoLeft), autoRightKey=ks(KB.AutoRight),
		dropKey=ks(KB.Drop), tpDownKey=ks(KB.TPDown),
		autoBatKey=ks(KB.AutoBat), speedKey=ks(KB.Speed), guiHideKey=ks(KB.GuiHide),
		laggerKey=ks(KB.Lagger),
		grabRadius=Steal.StealRadius,
		infJump=State.infJumpEnabled, antiRagdoll=State.antiRagdollEnabled,
		autoStealEnabled=Steal.AutoStealEnabled, unwalkEnabled=State.unwalkEnabled,
		laggerMode=State.laggerToggled, uiLocked=uiLocked,
		autoBatToggled=State.autoBatToggled,
		mainPos=main and {xs=main.Position.X.Scale,xo=main.Position.X.Offset,ys=main.Position.Y.Scale,yo=main.Position.Y.Offset} or nil,
		miniPos=mini and {xs=mini.Position.X.Scale,xo=mini.Position.X.Offset,ys=mini.Position.Y.Scale,yo=mini.Position.Y.Offset} or nil,
		panelPos=MobilePanel and {xs=MobilePanel.Position.X.Scale,xo=MobilePanel.Position.X.Offset,ys=MobilePanel.Position.Y.Scale,yo=MobilePanel.Position.Y.Offset} or nil,
		pbPos=pbFrame and {xs=pbFrame.Position.X.Scale,xo=pbFrame.Position.X.Offset,ys=pbFrame.Position.Y.Scale,yo=pbFrame.Position.Y.Offset} or nil,
		dragSmallMenus=State.dragSmallMenus,
		dragBtnPositions=(function()
			if not (State.dragSmallMenus and allBtns) then return nil end
			local t={}
			for _,entry in ipairs(allBtns) do
				local p = entry.btn.Position
				t[entry.btn.Name]={xo=p.X.Offset,yo=p.Y.Offset}
			end
			return t
		end)(),
	}
	local ok = pcall(function()
		local encoded = HttpService:JSONEncode(cfg)
		if writefile then writefile("ZenithMobileConfig.json", encoded) end
	end)
	if not ok then
		pcall(function()
			local encoded = HttpService:JSONEncode(cfg)
			if _writefile then _writefile("ZenithMobileConfig.json", encoded) end
		end)
	end
	if btn then
		local prev = btn.Text
		btn.Text = ok and "✓  Saved!" or "✕  Failed!"
		task.wait(1.5); btn.Text = prev
	end
end







-- ============================================================
-- OPIUM v5.2 LOGIC (message 9) - adapted for Zenith Mobile
-- ============================================================
;(function()

local _isfile   = isfile   or (syn and syn.isfile)   or (getgenv and getgenv().isfile)   or function() return false end
local _readfile = readfile  or (syn and syn.readfile)  or (getgenv and getgenv().readfile)  or function() return nil  end
local _writefile= writefile or (syn and syn.writefile) or (getgenv and getgenv().writefile) or function() end
local getconnections = getconnections or get_signal_cons or getconnects or (syn and syn.get_signal_cons)

local MOVE_KEYS={[Enum.KeyCode.W]=true,[Enum.KeyCode.A]=true,[Enum.KeyCode.S]=true,[Enum.KeyCode.D]=true,
    [Enum.KeyCode.Up]=true,[Enum.KeyCode.Left]=true,[Enum.KeyCode.Down]=true,[Enum.KeyCode.Right]=true}
local PLOT_CACHE_DURATION=2; local PROMPT_CACHE_REFRESH=0.15
local STEAL_COOLDOWN=0.1; local MEDUSA_COOLDOWN=25; local DROP_AUTO_OFF_DELAY=0.15
local CONFIG_FILE="ZenithMobileConfig.json"

-- Extra State fields from message 9
State.autoLeftPhase=1; State.autoRightPhase=1
State.medusaLastUsed=0; State.medusaDebounce=false; State.medusaCounterEnabled=false
State.batAimbotToggled=false; State.autoSwingEnabled=false
State.hittingCooldown=false
State.batCounterEnabled=false; State.batCounterDebounce=false
State.dropEnabled=false; State._tpInProgress=false
State.lastMoveDir=Vector3.new(0,0,0)
State._prevCarry=CS; State._prevSpeed=false
State.laggerEnabled=false

-- Extra Conns
Conns.autoLeft=nil; Conns.autoRight=nil; Conns.aimbot=nil
Conns.batCounter=nil; Conns.unwalk=nil

-- Presets
local Presets={}
local PRESET_FILE="ZenithMobilePresets.json"; local LAST_PRESET_FILE="ZenithMobileLastPreset.json"
local function buildPresetSnapshot()
    return {normalSpeed=NS,carrySpeed=CS,laggerSpeed=LS,stealRadius=Steal.StealRadius,
        infJump=State.infJumpEnabled,
        jumpMethod=State.jumpMethod,
        antiRagdoll=State.antiRagdollEnabled,fpsBoost=State.fpsBoostEnabled,
        medusaCounter=State.medusaCounterEnabled,batCounter=State.batCounterEnabled,
        autoSteal=Steal.AutoStealEnabled,uiScale=uiScaleValue}
end
local function savePresetsFile()
    local ok,enc=pcall(function() return HttpService:JSONEncode(Presets) end)
    if ok then pcall(function() _writefile(PRESET_FILE,enc) end) end
end
local function loadPresetsFile()
    local hasFile=false; pcall(function() hasFile=_isfile(PRESET_FILE) end)
    if not hasFile then return end
    local raw; pcall(function() raw=_readfile(PRESET_FILE) end)
    if not raw then return end
    local ok,dec=pcall(function() return HttpService:JSONDecode(raw) end)
    if ok and dec then Presets=dec end
end
local function saveLastPresetName(name)
    local ok,enc=pcall(function() return HttpService:JSONEncode({lastPreset=name}) end)
    if ok then pcall(function() _writefile(LAST_PRESET_FILE,enc) end) end
end
local function loadLastPresetName()
    local hasFile=false; pcall(function() hasFile=_isfile(LAST_PRESET_FILE) end)
    if not hasFile then return nil end
    local raw; pcall(function() raw=_readfile(LAST_PRESET_FILE) end)
    if not raw then return nil end
    local ok,dec=pcall(function() return HttpService:JSONDecode(raw) end)
    if ok and dec then return dec.lastPreset end; return nil
end

-- setInfJump, setAntiRag, setFps, setMedusaCounter, setBatCounter, setInstaGrab
-- are outer upvalues declared at line 296 and assigned by the UI rows above
local setAutoSwingVisual
-- autoLeftSetVisual, autoRightSetVisual, autoBatSetVisual are outer upvalues

-- ============================================================
-- ANTI-MEDUSA RESET
-- ============================================================
-- ============================================================
-- TP DOWN
-- ============================================================
local function doTpDown()
    pcall(function()
        local c=LP.Character; if not c then return end
        local root=c:FindFirstChild("HumanoidRootPart"); if not root then return end
        local rp=RaycastParams.new(); rp.FilterDescendantsInstances={c}; rp.FilterType=Enum.RaycastFilterType.Exclude
        local res=workspace:Raycast(root.Position,Vector3.new(0,-1000,0),rp)
        if res then root.CFrame=CFrame.new(res.Position+Vector3.new(0,root.Size.Y/2+0.5,0)); root.AssemblyLinearVelocity=Vector3.zero end
    end)
end

-- ============================================================
-- DROP BRAINROT
-- ============================================================
local _dropConns={}
local function runDropBrainrot()
    if State.dropEnabled then return end; State.dropEnabled=true
    task.spawn(function()
        local colConn=RunService.Stepped:Connect(function()
            if not State.dropEnabled then return end
            for _,p in ipairs(Players:GetPlayers()) do
                if p~=LP and p.Character then
                    for _,part in ipairs(p.Character:GetChildren()) do if part:IsA("BasePart") then part.CanCollide=false end end
                end
            end
        end)
        table.insert(_dropConns,colConn)
        task.spawn(function()
            while State.dropEnabled do
                RunService.Heartbeat:Wait()
                local c=LP.Character; local root=c and c:FindFirstChild("HumanoidRootPart")
                if not root then break end
                local vel=root.Velocity; root.Velocity=vel*10000+Vector3.new(0,10000,0)
                RunService.RenderStepped:Wait(); if root and root.Parent then root.Velocity=vel end
                RunService.Stepped:Wait(); if root and root.Parent then root.Velocity=vel+Vector3.new(0,0.1,0) end
            end
        end)
        task.wait(DROP_AUTO_OFF_DELAY); State.dropEnabled=false
        for _,cn in ipairs(_dropConns) do pcall(function() cn:Disconnect() end) end; _dropConns={}
    end)
end

-- ============================================================
-- startBatAimbot/stopBatAimbot defined above (message5 velocity-chase logic)

-- ============================================================
-- BAT COUNTER
-- ============================================================
local BAT_COUNTER_SLAP_LIST={"Bat","Slap","Iron Slap","Gold Slap","Diamond Slap","Emerald Slap","Ruby Slap","Dark Matter Slap","Flame Slap","Nuclear Slap","Galaxy Slap","Glitched Slap"}
local function findBatForCounter()
    local c=LP.Character; if not c then return nil end
    local bp=LP:FindFirstChildOfClass("Backpack")
    for _,name in ipairs(BAT_COUNTER_SLAP_LIST) do
        local t=c:FindFirstChild(name) or (bp and bp:FindFirstChild(name)); if t then return t end
    end
    for _,ch in ipairs(c:GetChildren()) do if ch:IsA("Tool") and ch.Name:lower():find("bat") then return ch end end
    if bp then for _,ch in ipairs(bp:GetChildren()) do if ch:IsA("Tool") and ch.Name:lower():find("bat") then return ch end end end
    return nil
end
local function swingBatForCounter(bat,char)
    local hum2=char:FindFirstChildOfClass("Humanoid")
    if bat.Parent~=char then if hum2 then pcall(function() hum2:EquipTool(bat) end) end; task.wait(0.05) end
    local remote=bat:FindFirstChildOfClass("RemoteEvent") or bat:FindFirstChildOfClass("RemoteFunction")
    if remote and remote:IsA("RemoteEvent") then
        pcall(function() remote:FireServer() end); task.wait(0.15); pcall(function() remote:FireServer() end)
    else pcall(function() bat:Activate() end); task.wait(0.15); pcall(function() bat:Activate() end) end
end
local function startBatCounter()
    if Conns.batCounter then return end
    Conns.batCounter=RunService.Heartbeat:Connect(function()
        if not State.batCounterEnabled then return end
        if State.batCounterDebounce then return end
        local char=LP.Character; if not char then return end
        local hum2=char:FindFirstChildOfClass("Humanoid"); if not hum2 then return end
        local st=hum2:GetState()
        if st==Enum.HumanoidStateType.Physics or st==Enum.HumanoidStateType.Ragdoll or st==Enum.HumanoidStateType.FallingDown then
            State.batCounterDebounce=true
            task.spawn(function()
                local bat=findBatForCounter()
                if bat then swingBatForCounter(bat,char) end
                task.wait(0.5); State.batCounterDebounce=false
            end)
        end
    end)
end
local function stopBatCounter()
    if Conns.batCounter then Conns.batCounter:Disconnect(); Conns.batCounter=nil end
    State.batCounterDebounce=false
end

-- ============================================================
-- MEDUSA COUNTER
-- ============================================================
local function findMedusa()
    local c=LP.Character; if not c then return nil end
    for _,t in ipairs(c:GetChildren()) do if t:IsA("Tool") then local n=t.Name:lower(); if n:find("medusa") or n:find("head") or n:find("stone") then return t end end end
    local bp=LP:FindFirstChild("Backpack")
    if bp then for _,t in ipairs(bp:GetChildren()) do if t:IsA("Tool") then local n=t.Name:lower(); if n:find("medusa") or n:find("head") or n:find("stone") then return t end end end end
    return nil
end
local function useMedusaCounter()
    if State.medusaDebounce then return end; if tick()-State.medusaLastUsed<MEDUSA_COOLDOWN then return end
    local c=LP.Character; if not c then return end; State.medusaDebounce=true
    local med=findMedusa(); if not med then State.medusaDebounce=false; return end
    if med.Parent~=c then local hum2=c:FindFirstChildOfClass("Humanoid"); if hum2 then hum2:EquipTool(med) end end
    pcall(function() med:Activate() end); State.medusaLastUsed=tick(); State.medusaDebounce=false
end
local function onAnchorChanged(part) return part:GetPropertyChangedSignal("Anchored"):Connect(function() if part.Anchored and part.Transparency==1 then useMedusaCounter() end end) end
local function setupMedusaCounter(char)
    for _,c2 in pairs(Conns.anchor) do pcall(function() c2:Disconnect() end) end; Conns.anchor={}
    if not char then return end
    for _,part in ipairs(char:GetDescendants()) do if part:IsA("BasePart") then table.insert(Conns.anchor,onAnchorChanged(part)) end end
    table.insert(Conns.anchor,char.DescendantAdded:Connect(function(part) if part:IsA("BasePart") then table.insert(Conns.anchor,onAnchorChanged(part)) end end))
end
local function stopMedusaCounter() for _,c2 in pairs(Conns.anchor) do pcall(function() c2:Disconnect() end) end; Conns.anchor={} end

-- ============================================================
-- AUTO LEFT / RIGHT
-- ============================================================
local function faceSouth() pcall(function() local c=LP.Character; if not c then return end; local root=c:FindFirstChild("HumanoidRootPart"); if root then root.CFrame=CFrame.new(root.Position)*CFrame.Angles(0,0,0) end end) end
local function faceNorth() pcall(function() local c=LP.Character; if not c then return end; local root=c:FindFirstChild("HumanoidRootPart"); if root then root.CFrame=CFrame.new(root.Position)*CFrame.Angles(0,math.rad(180),0) end end) end

local function startAutoLeft()
    if State.movementMode == "FullAuto" then startFullAutoPlay("START_B"); return end
    if Conns.autoLeft then Conns.autoLeft:Disconnect() end; State.autoLeftPhase=1
    Conns.autoLeft=RunService.Heartbeat:Connect(function()
        if not State.autoLeftEnabled then return end
        local c=LP.Character; if not c then return end
        local root=c:FindFirstChild("HumanoidRootPart"); local hum2=c:FindFirstChildOfClass("Humanoid"); if not root or not hum2 then return end
        -- Phase 1 = going out: use Lagger Speed when lagger on, else Normal Speed
        -- Phase 2 = returning: use Lagger Carry Speed when lagger on, else Normal Speed
        local spd = State.autoLeftPhase==2
            and (State.laggerToggled and LS2 or NS)
            or  (State.laggerToggled and LS  or NS)
        hum2.WalkSpeed = spd
        if State.autoLeftPhase==1 then
            local tgt=Vector3.new(AP.L1.X,root.Position.Y,AP.L1.Z); if (tgt-root.Position).Magnitude<1 then State.autoLeftPhase=2; local d=(AP.L2-root.Position); local mv=Vector3.new(d.X,0,d.Z).Unit; hum2:Move(mv,false); root.AssemblyLinearVelocity=Vector3.new(mv.X*spd,root.AssemblyLinearVelocity.Y,mv.Z*spd); return end
            local d=(AP.L1-root.Position); local mv=Vector3.new(d.X,0,d.Z).Unit; hum2:Move(mv,false); root.AssemblyLinearVelocity=Vector3.new(mv.X*spd,root.AssemblyLinearVelocity.Y,mv.Z*spd)
        elseif State.autoLeftPhase==2 then
            local tgt=Vector3.new(AP.L2.X,root.Position.Y,AP.L2.Z); if (tgt-root.Position).Magnitude<1 then hum2:Move(Vector3.zero,false); root.AssemblyLinearVelocity=Vector3.zero; State.autoLeftEnabled=false; if Conns.autoLeft then Conns.autoLeft:Disconnect(); Conns.autoLeft=nil end; State.autoLeftPhase=1; if autoLeftSetVisual then autoLeftSetVisual(false) end; faceSouth(); return end
            local d=(AP.L2-root.Position); local mv=Vector3.new(d.X,0,d.Z).Unit; hum2:Move(mv,false); root.AssemblyLinearVelocity=Vector3.new(mv.X*spd,root.AssemblyLinearVelocity.Y,mv.Z*spd)
        end
    end)
end
local function stopAutoLeft()
    if State.movementMode == "FullAuto" then stopFullAutoPlay() end
    if Conns.autoLeft then Conns.autoLeft:Disconnect(); Conns.autoLeft=nil end; State.autoLeftPhase=1
    local c=LP.Character; if c then local hum2=c:FindFirstChildOfClass("Humanoid"); if hum2 then hum2:Move(Vector3.zero,false) end end
end
local function startAutoRight()
    if State.movementMode == "FullAuto" then startFullAutoPlay("START_A"); return end
    if Conns.autoRight then Conns.autoRight:Disconnect() end; State.autoRightPhase=1
    Conns.autoRight=RunService.Heartbeat:Connect(function()
        if not State.autoRightEnabled then return end
        local c=LP.Character; if not c then return end
        local root=c:FindFirstChild("HumanoidRootPart"); local hum2=c:FindFirstChildOfClass("Humanoid"); if not root or not hum2 then return end
        -- Phase 1 = going out: use Lagger Speed when lagger on, else Normal Speed
        -- Phase 2 = returning: use Lagger Carry Speed when lagger on, else Normal Speed
        local spd = State.autoRightPhase==2
            and (State.laggerToggled and LS2 or NS)
            or  (State.laggerToggled and LS  or NS)
        hum2.WalkSpeed = spd
        if State.autoRightPhase==1 then
            local tgt=Vector3.new(AP.R1.X,root.Position.Y,AP.R1.Z); if (tgt-root.Position).Magnitude<1 then State.autoRightPhase=2; local d=(AP.R2-root.Position); local mv=Vector3.new(d.X,0,d.Z).Unit; hum2:Move(mv,false); root.AssemblyLinearVelocity=Vector3.new(mv.X*spd,root.AssemblyLinearVelocity.Y,mv.Z*spd); return end
            local d=(AP.R1-root.Position); local mv=Vector3.new(d.X,0,d.Z).Unit; hum2:Move(mv,false); root.AssemblyLinearVelocity=Vector3.new(mv.X*spd,root.AssemblyLinearVelocity.Y,mv.Z*spd)
        elseif State.autoRightPhase==2 then
            local tgt=Vector3.new(AP.R2.X,root.Position.Y,AP.R2.Z); if (tgt-root.Position).Magnitude<1 then hum2:Move(Vector3.zero,false); root.AssemblyLinearVelocity=Vector3.zero; State.autoRightEnabled=false; if Conns.autoRight then Conns.autoRight:Disconnect(); Conns.autoRight=nil end; State.autoRightPhase=1; if autoRightSetVisual then autoRightSetVisual(false) end; faceNorth(); return end
            local d=(AP.R2-root.Position); local mv=Vector3.new(d.X,0,d.Z).Unit; hum2:Move(mv,false); root.AssemblyLinearVelocity=Vector3.new(mv.X*spd,root.AssemblyLinearVelocity.Y,mv.Z*spd)
        end
    end)
end
local function stopAutoRight()
    if State.movementMode == "FullAuto" then stopFullAutoPlay() end
    if Conns.autoRight then Conns.autoRight:Disconnect(); Conns.autoRight=nil end; State.autoRightPhase=1
    local c=LP.Character; if c then local hum2=c:FindFirstChildOfClass("Humanoid"); if hum2 then hum2:Move(Vector3.zero,false) end end
end

-- ============================================================
-- ANTI RAGDOLL
-- ============================================================
-- startAntiRagdoll/stopAntiRagdoll are outer upvalues
startAntiRagdoll=function()
    if Conns.antiRag then return end
    Conns.antiRag=RunService.Heartbeat:Connect(function()
        if not State.antiRagdollEnabled then return end
        local c=LP.Character; if not c then return end
        local hum2=c:FindFirstChildOfClass("Humanoid"); local root=c:FindFirstChild("HumanoidRootPart")
        if not hum2 or not root then return end; if hum2.Health<=0 then return end
        local st=hum2:GetState(); if st==Enum.HumanoidStateType.Dead then return end
        if st==Enum.HumanoidStateType.Physics or st==Enum.HumanoidStateType.Ragdoll or st==Enum.HumanoidStateType.FallingDown then
            pcall(function() hum2:ChangeState(Enum.HumanoidStateType.GettingUp) end)
            pcall(function() workspace.CurrentCamera.CameraSubject=hum2 end)
            pcall(function() local PM=LP.PlayerScripts:FindFirstChild("PlayerModule"); if PM then local CM=require(PM:FindFirstChild("ControlModule")); if CM then CM:Enable() end end end)
            root.Velocity=Vector3.new(0,0,0); root.RotVelocity=Vector3.new(0,0,0)
        end
        for _,obj in ipairs(c:GetDescendants()) do pcall(function() if obj:IsA("Motor6D") and obj.Enabled==false then obj.Enabled=true end end) end
    end)
end
stopAntiRagdoll=function() if Conns.antiRag then Conns.antiRag:Disconnect(); Conns.antiRag=nil end end

-- ============================================================
-- UNWALK (message 9 improved)
-- ============================================================



-- ============================================================
-- FPS BOOST
-- ============================================================
local applyFPSBoost
applyFPSBoost=function()
    pcall(function() setfpscap(999999999) end)
    local function pO(v) pcall(function()
        if v:IsA("Model") then v.LevelOfDetail=Enum.ModelLevelOfDetail.Disabled; v.ModelStreamingMode=Enum.ModelStreamingMode.Nonatomic
        elseif v:IsA("MeshPart") then v.CastShadow=false; v.DoubleSided=false; v.RenderFidelity=Enum.RenderFidelity.Performance
        elseif v:IsA("BasePart") then v.CastShadow=false; v.Material=Enum.Material.Plastic; v.Reflectance=0
        elseif v:IsA("Decal") or v:IsA("Texture") then v.Transparency=1
        elseif v:IsA("SpecialMesh") then v.TextureId=""
        elseif v:IsA("Fire") or v:IsA("SpotLight") or v:IsA("Smoke") or v:IsA("Sparkles") or v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Beam") then v.Enabled=false
        elseif v:IsA("SurfaceAppearance") or v:IsA("MaterialVariant") then v:Destroy()
        elseif v:IsA("Attachment") then v.Visible=false end
    end) end
    for _,v in pairs(workspace:GetDescendants()) do pO(v) end
    pcall(function()
        local L=game:GetService("Lighting")
        for _,v in pairs(L:GetDescendants()) do pcall(function() if v:IsA("Sky") or v:IsA("Atmosphere") or v:IsA("BloomEffect") or v:IsA("BlurEffect") or v:IsA("SunRaysEffect") or v:IsA("DepthOfFieldEffect") or v:IsA("Clouds") or v:IsA("PostEffect") or v:IsA("ColorCorrectionEffect") then v:Destroy() end end) end
        pcall(function() sethiddenproperty(L,"Technology",Enum.Technology.Legacy) end)
        L.GlobalShadows=false; L.FogEnd=9e9; L.Brightness=0
        local ter=workspace:FindFirstChildOfClass("Terrain")
        if ter then pcall(function() sethiddenproperty(ter,"Decoration",false) end); ter.WaterReflectance=0; ter.WaterTransparency=0.7; ter.WaterWaveSize=0; ter.WaterWaveSpeed=0 end
    end)
    workspace.DescendantAdded:Connect(function(v) if State.fpsBoostEnabled then task.spawn(pO,v) end end)
end

-- ============================================================
-- STEAL
-- ============================================================
-- progressFill is the outer upvalue from the UI progress bar
local stealPctLbl = progressPct  -- alias for the percentage label
local function resetProgressBar()
    if stealPctLbl then stealPctLbl.Text="0%" end
    if progressFill then progressFill.Size=UDim2.new(0,0,1,0) end
end
local function isMyPlotByName(pn)
    local ct=tick(); if Steal.plotCache[pn] and (ct-(Steal.plotCacheTime[pn] or 0))<PLOT_CACHE_DURATION then return Steal.plotCache[pn] end
    local plots=workspace:FindFirstChild("Plots"); if not plots then Steal.plotCache[pn]=false; Steal.plotCacheTime[pn]=ct; return false end
    local plot=plots:FindFirstChild(pn); if not plot then Steal.plotCache[pn]=false; Steal.plotCacheTime[pn]=ct; return false end
    local sign=plot:FindFirstChild("PlotSign"); if sign then local yb=sign:FindFirstChild("YourBase"); if yb and yb:IsA("BillboardGui") then local r=yb.Enabled==true; Steal.plotCache[pn]=r; Steal.plotCacheTime[pn]=ct; return r end end
    Steal.plotCache[pn]=false; Steal.plotCacheTime[pn]=ct; return false
end
local function findNearestPrompt()
    local c=LP.Character; if not c then return nil end; local root=c:FindFirstChild("HumanoidRootPart"); if not root then return nil end
    local ct=tick(); if ct-Steal.promptCacheTime<PROMPT_CACHE_REFRESH and #Steal.cachedPrompts>0 then local np,nd=nil,math.huge; for _,data in ipairs(Steal.cachedPrompts) do if data.spawn then local dist=(data.spawn.Position-root.Position).Magnitude; if dist<=Steal.StealRadius and dist<nd then np=data.prompt; nd=dist end end end; if np then return np end end
    Steal.cachedPrompts={}; Steal.promptCacheTime=ct; local plots=workspace:FindFirstChild("Plots"); if not plots then return nil end; local np,nd=nil,math.huge
    for _,plot in ipairs(plots:GetChildren()) do if isMyPlotByName(plot.Name) then continue end; local pods=plot:FindFirstChild("AnimalPodiums"); if not pods then continue end
        for _,pod in ipairs(pods:GetChildren()) do pcall(function() local base=pod:FindFirstChild("Base"); local sp=base and base:FindFirstChild("Spawn"); if sp then local att=sp:FindFirstChild("PromptAttachment"); if att then for _,child in ipairs(att:GetChildren()) do if child:IsA("ProximityPrompt") then local dist=(sp.Position-root.Position).Magnitude; table.insert(Steal.cachedPrompts,{prompt=child,spawn=sp}); if dist<=Steal.StealRadius and dist<nd then np=child; nd=dist end; break end end end end end) end
    end; return np
end
local function executeSteal(prompt)
    local ct=tick(); if ct-State.lastStealTick<STEAL_COOLDOWN then return end; if State.isStealing then return end
    if not Steal.Data[prompt] then Steal.Data[prompt]={hold={},trigger={},ready=true}; pcall(function() if getconnections then for _,c2 in ipairs(getconnections(prompt.PromptButtonHoldBegan)) do if c2.Function then table.insert(Steal.Data[prompt].hold,c2.Function) end end; for _,c2 in ipairs(getconnections(prompt.Triggered)) do if c2.Function then table.insert(Steal.Data[prompt].trigger,c2.Function) end end else Steal.Data[prompt].useFallback=true end end) end
    local data=Steal.Data[prompt]; if not data.ready then return end; data.ready=false; State.isStealing=true; State.stealStartTime=ct; State.lastStealTick=ct
    if Conns.progress then Conns.progress:Disconnect() end
    Conns.progress=RunService.Heartbeat:Connect(function() if not State.isStealing then Conns.progress:Disconnect(); return end; local prog=math.clamp((tick()-State.stealStartTime)/Steal.StealDuration,0,1); if progressFill then progressFill.Size=UDim2.new(prog,0,1,0) end; if stealPctLbl then stealPctLbl.Text=math.floor(prog*100).."%" end end)
    task.spawn(function()
        local ok=false; pcall(function() if not data.useFallback then for _,fn in ipairs(data.hold) do task.spawn(fn) end; task.wait(Steal.StealDuration); for _,fn in ipairs(data.trigger) do task.spawn(fn) end; ok=true end end)
        if not ok and fireproximityprompt then pcall(function() fireproximityprompt(prompt); ok=true end) end
        if not ok then pcall(function() prompt:InputHoldBegin(); task.wait(Steal.StealDuration); prompt:InputHoldEnd() end) end
        task.wait(Steal.StealDuration*0.3); if Conns.progress then Conns.progress:Disconnect() end; resetProgressBar(); task.wait(0.05); data.ready=true; State.isStealing=false
    end)
end
startAutoSteal=function()
    if Conns.autoSteal then return end
    Conns.autoSteal=RunService.Heartbeat:Connect(function() if not Steal.AutoStealEnabled or State.isStealing then return end; local p=findNearestPrompt(); if p then executeSteal(p) end end)
end
stopAutoSteal=function()
    if Conns.autoSteal then Conns.autoSteal:Disconnect(); Conns.autoSteal=nil end
    State.isStealing=false; State.lastStealTick=0; Steal.plotCache={}; Steal.plotCacheTime={}; Steal.cachedPrompts={}; resetProgressBar()
end

-- ============================================================
-- SAVE / LOAD CONFIG
-- ============================================================
-- saveConfig and loadConfig are outer upvalues - assign directly below
saveConfig=function(btn)
    local function ks(e) return {kb=e.kb and e.kb.Name or nil,gp=e.gp and e.gp.Name or nil} end
    local function sp(f) if not f then return nil end; local p=f.Position; return {xs=p.X.Scale,xo=p.X.Offset,ys=p.Y.Scale,yo=p.Y.Offset} end
    local cfg={
        normalSpeed=NS,carrySpeed=CS,laggerSpeed=LS,laggerCarrySpeed=LS2,
        stealRadius=Steal.StealRadius,
        uiScale=uiScaleValue,
        uiLocked=uiLocked,
        autoLeftKey=ks(KB.AutoLeft),autoRightKey=ks(KB.AutoRight),
        dropKey=ks(KB.Drop),tpDownKey=ks(KB.TPDown),autoBatKey=ks(KB.AutoBat),
        speedKey=ks(KB.Speed),laggerKey=ks(KB.Lagger),guiHideKey=ks(KB.GuiHide),
        infJump=State.infJumpEnabled,
        antiRagdoll=State.antiRagdollEnabled,
        fpsBoost=State.fpsBoostEnabled,
        medusaCounter=State.medusaCounterEnabled,
        batCounter=State.batCounterEnabled,
        autoStealEnabled=Steal.AutoStealEnabled,
        unwalkEnabled=State.unwalkEnabled,
        autoSwing=State.autoSwingEnabled,
        autoBatToggled=State.autoBatToggled,
        stretchRez=State.stretchRezEnabled,
        stretcher=_stretcherOn,
        jumpMethod=State.jumpMethod,
        espPlayer=_espEnabled,
        antiLag=State.antiLagEnabled,
        darkMode=State.darkModeEnabled,
        introEnabled=State.introEnabled,
        selectedIntroMusic=State.selectedIntroMusic,
        autoTPDown=autoTPDownEnabled,
        autoTPDownHeight=autoTPDownHeight,
        movementMode=State.movementMode,
        panelPos=sp(MobilePanel),mainPos=sp(main),miniPos=sp(mini),pbPos=sp(pbFrame),
        dragSmallMenus=State.dragSmallMenus,
        dragBtnPositions=(function()
            if not (State.dragSmallMenus and allBtns) then return nil end
            local t={}
            for _,entry in ipairs(allBtns) do
                local p=entry.btn.Position
                t[entry.btn.Name]={xo=p.X.Offset,yo=p.Y.Offset}
            end
            return t
        end)(),
    }
    local ok,enc=pcall(function() return HttpService:JSONEncode(cfg) end)
    if ok and enc then
        local wf = writefile or (syn and syn.writefile) or (getgenv and getgenv().writefile) or _writefile
        if wf then pcall(wf, CONFIG_FILE, enc) end
    end
    if btn then local prev=btn.Text; btn.Text="Saved!"; task.wait(1.5); if btn and btn.Parent then btn.Text=prev end end
end

loadConfig=function()
    local isf = isfile or (syn and syn.isfile) or (getgenv and getgenv().isfile) or _isfile
    local rdf = readfile or (syn and syn.readfile) or (getgenv and getgenv().readfile) or _readfile
    local hasFile=false; pcall(function() hasFile=isf(CONFIG_FILE) end)
    if not hasFile then return end
    local raw; pcall(function() raw=rdf(CONFIG_FILE) end)
    if not raw then return end
    local cfg; pcall(function() cfg=HttpService:JSONDecode(raw) end)
    if not cfg then return end

    if cfg.normalSpeed then NS=cfg.normalSpeed; task.defer(function() if normalBox then normalBox.Text=tostring(NS) end end) end
    if cfg.carrySpeed  then CS=cfg.carrySpeed;  task.defer(function() if carryBox  then carryBox.Text=tostring(CS)  end end) end
    if cfg.laggerSpeed then LS=cfg.laggerSpeed; task.defer(function() if laggerBox then laggerBox.Text=tostring(LS) end end) end
    if cfg.laggerCarrySpeed then LS2=cfg.laggerCarrySpeed; task.defer(function() if laggerBox2 then laggerBox2.Text=tostring(LS2) end end) end
    if cfg.uiScale and type(cfg.uiScale)=="number" then
        uiScaleValue=math.clamp(math.floor(cfg.uiScale+0.5),50,150)
        if mainUIScale then mainUIScale.Scale=uiScaleValue/100 end
        task.defer(function() if uiScaleBox then uiScaleBox.Text=tostring(uiScaleValue) end end)
    end
    if cfg.uiLocked then uiLocked=true; task.defer(function() if setLockUIVisual then setLockUIVisual(true) end end) end
   if cfg.selectedIntroMusic then 
    State.selectedIntroMusic = cfg.selectedIntroMusic 
    task.defer(function() 
        if getgenv().ZenithMusicBtn then 
            getgenv().ZenithMusicBtn.Text = "Music " .. State.selectedIntroMusic 
        end 
    end)
end
if cfg.introEnabled ~= nil then State.introEnabled = cfg.introEnabled; if setIntroToggle then task.defer(function() setIntroToggle(cfg.introEnabled) end) end end
    if cfg.autoTPDown then 
        autoTPDownEnabled=true
        task.defer(function() 
            if setAutoTPDownVisual then setAutoTPDownVisual(true) end
            startAutoTPDown() 
        end) 
    end
    if cfg.autoTPDownHeight and type(cfg.autoTPDownHeight)=="number" then 
        autoTPDownHeight=math.clamp(cfg.autoTPDownHeight,0,500)
        task.defer(function()
            -- Find the TP Down Height input box and update it
            for _, page in pairs(tabPages) do
                for _, child in ipairs(page:GetChildren()) do
                    if child:IsA("Frame") then
                        for _, subchild in ipairs(child:GetChildren()) do
                            if subchild:IsA("TextBox") and subchild.Parent.Name ~= "ZenithHubGUI" then
                                -- Check if this is near a label that says "TP Down Height"
                                for _, label in ipairs(child:GetChildren()) do
                                    if label:IsA("TextLabel") and label.Text == "TP Down Height" then
                                        subchild.Text = tostring(autoTPDownHeight)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
    if cfg.stealRadius or cfg.grabRadius then
        Steal.StealRadius = cfg.stealRadius or cfg.grabRadius
        task.defer(function() if progressRadLbl then progressRadLbl.Text="Radius: "..Steal.StealRadius end end)
    end

    local function lk(e,d) if not d then return end
        if d.kb and Enum.KeyCode[d.kb] then e.kb=Enum.KeyCode[d.kb] end
        if d.gp and Enum.KeyCode[d.gp] then e.gp=Enum.KeyCode[d.gp] end
    end
    lk(KB.AutoLeft,cfg.autoLeftKey); lk(KB.AutoRight,cfg.autoRightKey)
    lk(KB.Drop,cfg.dropKey); lk(KB.TPDown,cfg.tpDownKey); lk(KB.AutoBat,cfg.autoBatKey)
    lk(KB.Speed,cfg.speedKey); lk(KB.Lagger,cfg.laggerKey); lk(KB.GuiHide,cfg.guiHideKey)

    if cfg.infJump           then State.infJumpEnabled=true;           if setInfJump           then setInfJump(true)           end end
    if cfg.jumpMethod and (cfg.jumpMethod=="Tap" or cfg.jumpMethod=="Hold") then
        State.jumpMethod = cfg.jumpMethod
        if jumpMethodBtn then jumpMethodBtn.Text = cfg.jumpMethod end
    end
    if cfg.antiRagdoll       then State.antiRagdollEnabled=true;       if setAntiRag           then setAntiRag(true)           end; startAntiRagdoll() end
    if cfg.fpsBoost          then State.fpsBoostEnabled=true;          if setFps               then setFps(true)               end; pcall(applyFPSBoost) end
    if cfg.medusaCounter     then State.medusaCounterEnabled=true;     if setMedusaCounter     then setMedusaCounter(true)     end; setupMedusaCounter(LP.Character) end
    if cfg.batCounter        then State.batCounterEnabled=true;        if setBatCounter        then setBatCounter(true)        end; startBatCounter() end
    if cfg.autoStealEnabled  then Steal.AutoStealEnabled=true;         if setAutoGrab          then setAutoGrab(true)          end; pcall(startAutoSteal) end
    if cfg.autoSwing         then State.autoSwingEnabled=true;         if setAutoSwingVisual   then setAutoSwingVisual(true)   end end
    if cfg.unwalkEnabled     then State.unwalkEnabled=true; if setUnwalkToggle then setUnwalkToggle(true) end; startUnwalk() end
    if cfg.stretchRez        then State.stretchRezEnabled=true;        if setStretchRez        then setStretchRez(true)        end end
    if cfg.stretcher         then if _stretcherSetVisual then _stretcherSetVisual(true) end end
    if cfg.espPlayer        then if _espToggleFn then _espToggleFn(true) end end
    if cfg.antiLag           then State.antiLagEnabled=true;           if setAntiLag           then setAntiLag(true)           end end
    if cfg.darkMode          then State.darkModeEnabled=true;          if setDarkMode          then setDarkMode(true)          end end
    if cfg.autoBatToggled    then State.autoBatToggled=true; task.defer(function() if autoBatSetVisual then autoBatSetVisual(true) end; pcall(startBatAimbot) end) end
    if cfg.movementMode then
        State.movementMode = cfg.movementMode
        task.defer(function()
            if getgenv()._zenithSetMovementModeVisual then
                getgenv()._zenithSetMovementModeVisual(cfg.movementMode)
            end
        end)
    end
    -- restore positions after UI is fully built
    task.spawn(function()
        task.wait(0.5)
        local function lp(frame, d) if frame and type(d)=="table" and d.xs~=nil then frame.Position=UDim2.new(d.xs,d.xo,d.ys,d.yo) end end
        lp(main, cfg.mainPos); lp(mini, cfg.miniPos)
        lp(MobilePanel, cfg.panelPos); lp(pbFrame, cfg.pbPos)
        -- Restore drag small menus state and per-button positions
        if cfg.dragSmallMenus and setDragSmallMenus and allBtns then
            if cfg.dragBtnPositions then
                -- Set freePos ONLY (not btn.Position) so setDragSmallMenus uses saved coords
                for _, entry in ipairs(allBtns) do
                    local saved = cfg.dragBtnPositions[entry.btn.Name]
                    if saved then
                        entry.freePos = UDim2.new(0, saved.xo, 0, saved.yo)
                    end
                end
            end
            State.dragSmallMenus = true
            setDragSmallMenus(true)
            if setDragSmallMenusVisual then setDragSmallMenusVisual(true) end
        end
    end)
end

-- ============================================================
-- CHARACTER SETUP (message 9 version)
-- ============================================================
-- Speed display for other players
local function setupOtherPlayerBillboard(player)
    if player == LP then return end
    
    local function addBillboard(char)
        task.wait(0.2)
        local head = char:FindFirstChild("Head")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if not head or not hrp then return end
        
        local oldBB = head:FindFirstChild("ZenithOtherBB")
        if oldBB then oldBB:Destroy() end
        
        local bb = Instance.new("BillboardGui", head)
        bb.Name = "ZenithOtherBB"
        bb.Size = UDim2.new(0, 100, 0, 30)
        bb.StudsOffset = Vector3.new(0, 3, 0)
        bb.AlwaysOnTop = true
        
        local speedLbl = Instance.new("TextLabel", bb)
        speedLbl.Size = UDim2.new(1, 0, 1, 0)
        speedLbl.BackgroundTransparency = 1
        speedLbl.Text = "0.0"
        speedLbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        speedLbl.Font = Enum.Font.GothamBlack
        speedLbl.TextScaled = true
        speedLbl.TextStrokeTransparency = 0
        speedLbl.TextStrokeColor3 = Color3.new(0, 0, 0)
        
        -- Update their speed
        local conn = RunService.RenderStepped:Connect(function()
            if not hrp or not hrp.Parent then 
                conn:Disconnect()
                return 
            end
            local hspd = Vector3.new(hrp.Velocity.X, 0, hrp.Velocity.Z).Magnitude
            speedLbl.Text = string.format("%.1f", hspd)
        end)
    end
    
    player.CharacterAdded:Connect(addBillboard)
    
    if player.Character then
        task.spawn(addBillboard, player.Character)
    end
end

-- Setup for all existing players
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= LP then
        setupOtherPlayerBillboard(player)
    end
end

-- Setup for new players joining
Players.PlayerAdded:Connect(setupOtherPlayerBillboard)

local h,hrp,speedLbl,modeBillLbl
local function setupChar(char)
    task.wait(0.1)
    h=char:WaitForChild("Humanoid",5)
    hrp=char:WaitForChild("HumanoidRootPart",5)
    if not h or not hrp then return end

    local head=char:FindFirstChild("Head")
    if head then
        local oldBB=head:FindFirstChild("ZenithMobileBB"); if oldBB then oldBB:Destroy() end
        local bb=Instance.new("BillboardGui",head); bb.Name="ZenithMobileBB"
        bb.Size=UDim2.new(0,160,0,62); bb.StudsOffset=Vector3.new(0,3,0); bb.AlwaysOnTop=true
        speedLbl=Instance.new("TextLabel",bb); speedLbl.Name="SpeedBillLbl"
        speedLbl.Size=UDim2.new(1,0,0,36); speedLbl.Position=UDim2.new(0,0,0,0); speedLbl.BackgroundTransparency=1
        speedLbl.Text="0.0"; speedLbl.TextColor3=Color3.fromRGB(255,255,255)
        speedLbl.Font=Enum.Font.GothamBlack; speedLbl.TextScaled=true
        speedLbl.TextStrokeTransparency=0; speedLbl.TextStrokeColor3=Color3.new(0,0,0)
        -- Mode label displayed below the speed number
        modeBillLbl=Instance.new("TextLabel",bb); modeBillLbl.Name="ModeBillLbl"
        modeBillLbl.Size=UDim2.new(1,0,0,26); modeBillLbl.Position=UDim2.new(0,0,0,34); modeBillLbl.BackgroundTransparency=1
        modeBillLbl.Text=(State.movementMode=="SemiAuto") and "Mode: Semi" or "Mode: Full"
        modeBillLbl.TextColor3=Color3.fromRGB(255,255,255)
        modeBillLbl.Font=Enum.Font.GothamBlack; modeBillLbl.TextScaled=true
        modeBillLbl.TextStrokeTransparency=0; modeBillLbl.TextStrokeColor3=Color3.new(0,0,0)
        State._modeBillLbl = modeBillLbl  -- shared reference so toggle can update it anytime
    end

    if State.unwalkEnabled then task.wait(0.3); startUnwalk() end
    stopAntiRagdoll()
    if State.antiRagdollEnabled then task.wait(0.5); startAntiRagdoll() end
    if State.medusaCounterEnabled then setupMedusaCounter(char) end
    if State.autoBatToggled then stopBatAimbot(); task.wait(0.2); pcall(startBatAimbot) end
    if State.batCounterEnabled then task.wait(0.3); startBatCounter() end
    if Steal.AutoStealEnabled then pcall(stopAutoSteal); task.wait(0.5); pcall(startAutoSteal) end
end

LP.CharacterAdded:Connect(setupChar)
if LP.Character then task.spawn(function() setupChar(LP.Character) end) end

-- ============================================================
-- RUNTIME LOOPS
-- ============================================================
RunService.Stepped:Connect(function()
    for _,p in ipairs(Players:GetPlayers()) do
        if p~=LP and p.Character then
            for _,part in ipairs(p.Character:GetChildren()) do if part:IsA("BasePart") then part.CanCollide=false end end
        end
    end
end)

-- Tap inf jump: fires on every JumpRequest (original logic)
UIS.JumpRequest:Connect(function()
    if not State.infJumpEnabled then return end
    if State.jumpMethod == "Hold" then return end  -- hold mode handled separately
    local c=LP.Character; if not c then return end
    local root=c:FindFirstChild("HumanoidRootPart")
    if root then root.AssemblyLinearVelocity=Vector3.new(root.AssemblyLinearVelocity.X,55,root.AssemblyLinearVelocity.Z) end
end)

-- Hold inf jump: checks hum.Jump every frame (works on mobile + PC)
local _holdJumpTimer = 0
RunService.Heartbeat:Connect(function(dt)
    if not State.infJumpEnabled then return end
    if State.jumpMethod ~= "Hold" then return end
    local c = LP.Character; if not c then return end
    local hum = c:FindFirstChildOfClass("Humanoid"); if not hum then return end
    local root = c:FindFirstChild("HumanoidRootPart"); if not root then return end
    -- hum.Jump is true the entire time the jump button is held (mobile + keyboard + controller)
    if not hum.Jump then _holdJumpTimer = 0; return end
    _holdJumpTimer = _holdJumpTimer + dt
    if _holdJumpTimer >= 0.1 then
        _holdJumpTimer = 0
        root.AssemblyLinearVelocity = Vector3.new(
            root.AssemblyLinearVelocity.X, 55, root.AssemblyLinearVelocity.Z)
    end
end)

RunService.RenderStepped:Connect(function()
    if not (h and hrp) then return end; if State._tpInProgress then return end
    if not _apRouteRunning and not State.autoBatToggled and not State.autoLeftEnabled and not State.autoRightEnabled then
        local md=h.MoveDirection
        local spd=State.laggerToggled and (laggerPhase==2 and LS2 or LS) or (State.speedToggled and CS or NS)
        if md.Magnitude>0 then
            State.lastMoveDir=md; hrp.Velocity=Vector3.new(md.X*spd,hrp.Velocity.Y,md.Z*spd)
        elseif State.antiRagdollEnabled and State.lastMoveDir.Magnitude>0 then
            local anyHeld=false; for key in pairs(MOVE_KEYS) do if UIS:IsKeyDown(key) then anyHeld=true; break end end
            if anyHeld then hrp.Velocity=Vector3.new(State.lastMoveDir.X*spd,hrp.Velocity.Y,State.lastMoveDir.Z*spd) end
        end
    end
    pcall(function()
        if speedLbl then
            local hspd=Vector3.new(hrp.Velocity.X,0,hrp.Velocity.Z).Magnitude
            speedLbl.Text=string.format("%.1f",hspd)
        end
    end)
end)

-- ============================================================
-- INPUT
-- ============================================================
UIS.InputBegan:Connect(function(inp,gp)
    if gp and inp.UserInputType ~= Enum.UserInputType.Gamepad1 then return end
    local kc=inp.KeyCode; if kc==Enum.KeyCode.Unknown then return end
    if kbMatch(KB.Speed,kc) then
        State.laggerToggled = false; laggerPhase = 0
        State.speedToggled = not State.speedToggled
        if mobileLaggerSetActive then mobileLaggerSetActive(false) end
        if modeValLbl then modeValLbl.Text = State.speedToggled and "Carry" or "Normal" end
    elseif kbMatch(KB.AutoLeft,kc) then
        State.autoLeftEnabled=not State.autoLeftEnabled
        if State.autoLeftEnabled and State.autoBatToggled then State.autoBatToggled=false; stopBatAimbot(); if autoBatSetVisual then autoBatSetVisual(false) end end
        if State.autoLeftEnabled then startAutoLeft() else stopAutoLeft() end
        if autoLeftSetVisual then autoLeftSetVisual(State.autoLeftEnabled) end
    elseif kbMatch(KB.AutoRight,kc) then
        State.autoRightEnabled=not State.autoRightEnabled
        if State.autoRightEnabled and State.autoBatToggled then State.autoBatToggled=false; stopBatAimbot(); if autoBatSetVisual then autoBatSetVisual(false) end end
        if State.autoRightEnabled then startAutoRight() else stopAutoRight() end
        if autoRightSetVisual then autoRightSetVisual(State.autoRightEnabled) end
    elseif kbMatch(KB.Drop,kc) then
        if not State.dropActive then task.spawn(runDrop) end
    elseif kbMatch(KB.TPDown,kc) then
        task.spawn(doTpDown)
    elseif kbMatch(KB.Lagger,kc) then
        if laggerPhase == 1 then
            laggerPhase = 2; State.laggerToggled = true; State.speedToggled = false
            if mobileLaggerSetActive then mobileLaggerSetActive(true) end
            if modeValLbl then modeValLbl.Text = "Lagger Carry" end
        else
            laggerPhase = 1; State.laggerToggled = true; State.speedToggled = false
            if mobileSpeedSetActive then mobileSpeedSetActive(false) end
            if mobileLaggerSetActive then mobileLaggerSetActive(true) end
            if modeValLbl then modeValLbl.Text = "Lagger" end
        end
    elseif kbMatch(KB.AutoBat,kc) then
        State.autoBatToggled=not State.autoBatToggled
        if State.autoBatToggled then
            if State.autoLeftEnabled then State.autoLeftEnabled=false; stopAutoLeft(); if autoLeftSetVisual then autoLeftSetVisual(false) end end
            if State.autoRightEnabled then State.autoRightEnabled=false; stopAutoRight(); if autoRightSetVisual then autoRightSetVisual(false) end end
            pcall(startBatAimbot)
        else stopBatAimbot() end
        if autoBatSetVisual then autoBatSetVisual(State.autoBatToggled) end
    elseif kbMatch(KB.GuiHide,kc) then
        State.guiVisible=not State.guiVisible
        pcall(function() main.Visible=State.guiVisible end)
        pcall(function() mini.Visible=not State.guiVisible end)
    end
end)

-- ============================================================
-- INIT
-- ============================================================
loadPresetsFile()
loadConfig()

task.spawn(function()
    task.wait(0.3)
    local lastPresetName=loadLastPresetName()
    if lastPresetName and lastPresetName~="" then
        for _,preset in ipairs(Presets) do
            if preset.name==lastPresetName then
                pcall(function() applyPreset(preset.data) end); break
            end
        end
    end
end)

task.delay(1,function() pcall(saveConfig) end)
task.spawn(function() while task.wait(10) do pcall(saveConfig) end end)
-- Save on leave (BindToClose is server-only)
Players.LocalPlayer.AncestryChanged:Connect(function() pcall(saveConfig) end)

print("[Zenith Hub] Loaded!")

end)()

-- ============================================================
-- INTRO ANIMATION
-- ============================================================
local function playIntroAnimation()
	if not State or not State.introEnabled then return end
	
	local _introPlayers = game:GetService("Players")
	local _introTween = game:GetService("TweenService")
	local _introPlayer = _introPlayers.LocalPlayer
	local _introGui = _introPlayer:WaitForChild("PlayerGui")
	
	local introGui = Instance.new("ScreenGui")
	introGui.Name = "SoulHubIntro"
	introGui.ResetOnSpawn = false
	introGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	introGui.DisplayOrder = 999
	introGui.IgnoreGuiInset = true
	introGui.Parent = _introGui

	local introFrame = Instance.new("Frame")
	introFrame.Size = UDim2.new(1, 0, 1, 0)
	introFrame.Position = UDim2.new(0, 0, 0, 0)
	introFrame.BackgroundColor3 = Color3.fromRGB(5, 8, 18)
	introFrame.BackgroundTransparency = 0.35
	introFrame.BorderSizePixel = 0
	introFrame.Parent = introGui

	local soulLabel = Instance.new("TextLabel")
	soulLabel.Size = UDim2.new(0, 400, 0, 110)
	soulLabel.Position = UDim2.new(0, -350, 0.5, -95)
	soulLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	soulLabel.BackgroundTransparency = 1
	soulLabel.Text = "Zenith"
	soulLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
	soulLabel.TextTransparency = 0
	soulLabel.TextSize = 88
	soulLabel.Font = Enum.Font.GothamBold
	soulLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	soulLabel.TextStrokeTransparency = 1
	soulLabel.ZIndex = 2
	soulLabel.Parent = introFrame

	local hubLabel = Instance.new("TextLabel")
	hubLabel.Size = UDim2.new(0, 400, 0, 110)
	hubLabel.Position = UDim2.new(1, 350, 0.5, 95)
	hubLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	hubLabel.BackgroundTransparency = 1
	hubLabel.Text = "Hub"
	hubLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
	hubLabel.TextTransparency = 0
	hubLabel.TextSize = 88
	hubLabel.Font = Enum.Font.GothamBold
	hubLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	hubLabel.TextStrokeTransparency = 1
	hubLabel.ZIndex = 2
	hubLabel.Parent = introFrame

	local introCompleteEvent = Instance.new("BindableEvent")
	
	task.spawn(function()
		pcall(function()
			local intros = {
				"https://files.catbox.moe/zuid5n.mp3",
				"https://files.catbox.moe/z6eqnt.mp3",
				"https://files.catbox.moe/t0nlhv.mp3",
				"https://files.catbox.moe/mthg31.mp3",
				"https://files.catbox.moe/ddnbup.mp3",
				"https://files.catbox.moe/hg5cr4.mp3",
				"https://files.catbox.moe/nps6gk.mp3",
				"https://files.catbox.moe/iyw1cb.mp3",
				"https://files.catbox.moe/2w0wtv.mp3",
			}
			local selectedMusic = State.selectedIntroMusic or 1
			local RandomIntro = intros[selectedMusic]
			writefile("ZenithHubIntro", game:HttpGet(RandomIntro))
			local flex1 = Instance.new("Sound", gethui())
			flex1.SoundId = getcustomasset("ZenithHubIntro")
			flex1.PlaybackSpeed = 1
			flex1.Volume = 1
			flex1:Play()
		end)
		
		pcall(function()
		end)
		
		task.wait(0.3)
		
		local camera = workspace.CurrentCamera
		local blur = Instance.new("BlurEffect")
		blur.Size = 56
		blur.Parent = camera

		local flickering = true
		task.spawn(function()
			while flickering do
				soulLabel.TextTransparency = 1
				soulLabel.TextStrokeTransparency = 1
				hubLabel.TextTransparency = 1
				hubLabel.TextStrokeTransparency = 1
				task.wait(0.08)
				
				if not flickering then break end
				
				soulLabel.TextTransparency = 0.25
				soulLabel.TextStrokeTransparency = 0.3
				hubLabel.TextTransparency = 0.25
				hubLabel.TextStrokeTransparency = 0.3
				task.wait(0.08)
			end
		end)

		local tweenInfo = TweenInfo.new(1.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local soulTween = _introTween:Create(soulLabel, tweenInfo, {Position = UDim2.new(0.5, 0, 0.5, -95)})
		soulTween:Play()
		
		task.wait(0.55)
		
		local hubTween = _introTween:Create(hubLabel, tweenInfo, {Position = UDim2.new(0.5, 0, 0.5, 95)})
		hubTween:Play()
		
		soulTween.Completed:Wait()
		task.wait(0.5)

		flickering = false
		task.wait(1.2)

		local fadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad)
		_introTween:Create(soulLabel, fadeInfo, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
		_introTween:Create(hubLabel, fadeInfo, {TextTransparency = 1, TextStrokeTransparency = 1}):Play()
		_introTween:Create(introFrame, fadeInfo, {BackgroundTransparency = 1}):Play()
		
		task.wait(0.55)

		pcall(function() blur:Destroy() end)
		introGui:Destroy()
		introCompleteEvent:Fire()
	end)

	introCompleteEvent.Event:Wait()
	introCompleteEvent:Destroy()
end

task.spawn(function()
	task.wait(0.5)
	if State and State.introEnabled then
		playIntroAnimation()
	end
end)

end)()