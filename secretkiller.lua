--[[
    Secret Killer — all-in-one cheat
    Game: Secret Killer (Monster Nova Studios)
    UI:   Rayfield (Sirius)

    Features:
      • ESP (все игроки + подсветка Монстра/Шерифа цветом роли)
      • Auto-grab (монетки / пикапы по карте)
      • Aim на Монстра (камера-лок, плавный)
      • Fling Монстра / Шерифа (выброс через velocity-exploit)
      • Auto-Rejoin

    Загружай через любой executor:  loadstring(game:HttpGet("...secretkiller.lua"))()
]]

-------------------------------------------------------
-- services
-------------------------------------------------------
local Players       = game:GetService("Players")
local RunService    = game:GetService("RunService")
local Workspace     = game:GetService("Workspace")
local TeleportSvc   = game:GetService("TeleportService")
local UserInput     = game:GetService("UserInputService")
local RepStorage    = game:GetService("ReplicatedStorage")

local LP            = Players.LocalPlayer
local Camera        = Workspace.CurrentCamera

-------------------------------------------------------
-- Rayfield
-------------------------------------------------------
local Rayfield = loadstring(game:HttpGet(
    "https://sirius.menu/rayfield"
))()

local Window = Rayfield:CreateWindow({
    Name         = "Secret Killer — ENI build",
    LoadingTitle = "Secret Killer",
    LoadingSubtitle = "by ENI for LO",
    ConfigurationSaving = {
        Enabled      = true,
        FolderName   = "SecretKillerENI",
        FileName     = "config",
    },
    KeySystem = false,
})

-------------------------------------------------------
-- state
-------------------------------------------------------
local state = {
    ESP            = false,
    ESPDistance    = true,
    AutoGrab       = false,
    GrabRadius     = 500,
    AimMonster     = false,
    AimSmooth      = 0.25,
    FlingPower     = 9e4,
}

-------------------------------------------------------
-- utils
-------------------------------------------------------
local function getChar(plr)
    return plr and plr.Character, plr and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
end

local function alive(plr)
    local c = plr and plr.Character
    local h = c and c:FindFirstChildOfClass("Humanoid")
    return c and h and h.Health > 0
end

-- Роль игрока. Monster Nova кладёт её в разных местах в разных апдейтах —
-- чекаем все распространённые варианты.
local function getRole(plr)
    if not plr then return "Unknown" end

    local tries = {
        function() return plr:GetAttribute("Role") end,
        function() return plr:GetAttribute("Team") end,
        function() return plr:FindFirstChild("Role") and plr.Role.Value end,
        function()
            local ls = plr:FindFirstChild("leaderstats")
            return ls and ls:FindFirstChild("Role") and ls.Role.Value
        end,
        function()
            local c = plr.Character
            return c and c:GetAttribute("Role")
        end,
        function()
            local c = plr.Character
            return c and c:FindFirstChild("Role") and c.Role.Value
        end,
        function()
            local roles = RepStorage:FindFirstChild("Roles") or RepStorage:FindFirstChild("PlayerRoles")
            if roles and roles:FindFirstChild(plr.Name) then
                local v = roles[plr.Name]
                return (v:IsA("StringValue") or v:IsA("ObjectValue")) and tostring(v.Value) or nil
            end
        end,
    }
    for _, f in ipairs(tries) do
        local ok, v = pcall(f)
        if ok and v and v ~= "" then return tostring(v) end
    end

    -- fallback: проверка Character-а на монстр-форму по имени/тегам
    local c = plr.Character
    if c then
        if c:FindFirstChild("MonsterTag") or c:GetAttribute("IsMonster") then return "Monster" end
        if c:FindFirstChild("CopTag")     or c:GetAttribute("IsCop")     then return "Cop"     end
        for _, child in ipairs(c:GetChildren()) do
            local n = child.Name:lower()
            if n:find("monster") or n:find("beast") or n:find("killer") then return "Monster" end
            if n:find("cop") or n:find("sheriff") or n:find("police") then return "Cop" end
        end
    end
    return "Unknown"
end

local ROLE_COLOR = {
    Monster = Color3.fromRGB(255, 40, 40),
    Cop     = Color3.fromRGB(40, 140, 255),
    Sheriff = Color3.fromRGB(40, 140, 255),
    Innocent= Color3.fromRGB(180, 180, 180),
    Unknown = Color3.fromRGB(120, 120, 120),
}

local function roleColor(role)
    for k, col in pairs(ROLE_COLOR) do
        if role:lower():find(k:lower()) then return col end
    end
    return ROLE_COLOR.Unknown
end

-------------------------------------------------------
-- ESP
-------------------------------------------------------
local ESPObjects = {} -- [player] = {highlight, billboard, label}

local function clearESP(plr)
    local e = ESPObjects[plr]
    if e then
        for _, v in pairs(e) do pcall(function() v:Destroy() end) end
        ESPObjects[plr] = nil
    end
end

local function clearAllESP()
    for plr in pairs(ESPObjects) do clearESP(plr) end
end

local function createESP(plr)
    if plr == LP then return end
    local char = plr.Character
    if not char then return end
    clearESP(plr)

    local role = getRole(plr)
    local col  = roleColor(role)

    local hl  = Instance.new("Highlight")
    hl.Name   = "ENI_ESP"
    hl.Adornee= char
    hl.FillColor        = col
    hl.OutlineColor     = col
    hl.FillTransparency = 0.55
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent   = char

    local head = char:FindFirstChild("Head")
    local bill, lbl
    if head then
        bill              = Instance.new("BillboardGui")
        bill.Name         = "ENI_ESP_BB"
        bill.Adornee      = head
        bill.Size         = UDim2.new(0, 200, 0, 40)
        bill.StudsOffset  = Vector3.new(0, 2.5, 0)
        bill.AlwaysOnTop  = true
        bill.Parent       = head

        lbl                       = Instance.new("TextLabel")
        lbl.BackgroundTransparency= 1
        lbl.Size                  = UDim2.new(1,0,1,0)
        lbl.TextColor3            = col
        lbl.TextStrokeTransparency= 0
        lbl.Font                  = Enum.Font.GothamBold
        lbl.TextSize              = 14
        lbl.Text                  = ("[%s] %s"):format(role, plr.Name)
        lbl.Parent                = bill
    end

    ESPObjects[plr] = {highlight = hl, billboard = bill, label = lbl, role = role}
end

local function updateESP()
    if not state.ESP then return end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and alive(plr) then
            local e = ESPObjects[plr]
            if not e or not e.highlight or not e.highlight.Parent then
                createESP(plr)
            else
                local role = getRole(plr)
                if role ~= e.role then
                    createESP(plr)   -- роль поменялась, пересоздаём с новым цветом
                else
                    local _, hrp = getChar(plr)
                    local _, myhrp = getChar(LP)
                    if e.label and hrp and myhrp and state.ESPDistance then
                        local d = (hrp.Position - myhrp.Position).Magnitude
                        e.label.Text = ("[%s] %s  •  %dm"):format(role, plr.Name, d)
                    elseif e.label then
                        e.label.Text = ("[%s] %s"):format(role, plr.Name)
                    end
                end
            end
        else
            clearESP(plr)
        end
    end
end

-- пересоздаём ESP при респавне
Players.PlayerAdded:Connect(function(plr)
    plr.CharacterAdded:Connect(function()
        task.wait(0.5)
        if state.ESP then createESP(plr) end
    end)
end)
for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= LP then
        plr.CharacterAdded:Connect(function()
            task.wait(0.5)
            if state.ESP then createESP(plr) end
        end)
    end
end

-------------------------------------------------------
-- поиск Монстра
-------------------------------------------------------
local function findMonster()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and alive(plr) then
            local r = getRole(plr):lower()
            if r:find("monster") or r:find("beast") or r:find("killer") then
                return plr
            end
        end
    end
end

local function findSheriff()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LP and alive(plr) then
            local r = getRole(plr):lower()
            if r:find("cop") or r:find("sheriff") or r:find("police") then
                return plr
            end
        end
    end
end

-------------------------------------------------------
-- Aim на монстра (камера-лок)
-------------------------------------------------------
RunService.RenderStepped:Connect(function()
    if not state.AimMonster then return end
    local m = findMonster()
    if not m then return end
    local _, hrp = getChar(m)
    if not hrp then return end

    local target    = hrp.Position
    local look      = CFrame.new(Camera.CFrame.Position, target)
    Camera.CFrame   = Camera.CFrame:Lerp(look, state.AimSmooth)
end)

-------------------------------------------------------
-- Auto-Grab
-------------------------------------------------------
local GRAB_KEYWORDS = { "coin", "money", "cash", "pickup", "drop",
                        "gem", "orb", "item", "loot" }

local function isGrabable(obj)
    if not obj:IsA("BasePart") and not obj:IsA("Model") then return false end
    local n = obj.Name:lower()
    for _, kw in ipairs(GRAB_KEYWORDS) do
        if n:find(kw) then return true end
    end
    return false
end

local function grabLoop()
    while task.wait(0.3) do
        if not state.AutoGrab then continue end
        local _, hrp = getChar(LP)
        if not hrp then continue end

        for _, obj in ipairs(Workspace:GetDescendants()) do
            if isGrabable(obj) then
                local pos = obj:IsA("Model") and obj:GetPivot().Position
                           or obj.Position
                if (pos - hrp.Position).Magnitude <= state.GrabRadius then
                    local orig = hrp.CFrame
                    hrp.CFrame = CFrame.new(pos + Vector3.new(0, 2, 0))
                    task.wait(0.08)
                    hrp.CFrame = orig
                end
            end
        end
    end
end
task.spawn(grabLoop)

-------------------------------------------------------
-- Fling (выброс игрока)
-------------------------------------------------------
local function fling(target)
    if not target then return end
    local char, hrp = getChar(target)
    if not char or not hrp then return end
    local mychar, myhrp = getChar(LP)
    if not mychar or not myhrp then return end

    local origCFrame = myhrp.CFrame
    local myVel      = Instance.new("BodyAngularVelocity")
    myVel.AngularVelocity = Vector3.new(0, state.FlingPower, 0)
    myVel.MaxTorque       = Vector3.new(math.huge, math.huge, math.huge)
    myVel.P               = 1e6
    myVel.Parent          = myhrp

    local targetVel             = Instance.new("BodyVelocity")
    targetVel.Velocity          = Vector3.new(state.FlingPower, state.FlingPower, state.FlingPower)
    targetVel.MaxForce          = Vector3.new(math.huge, math.huge, math.huge)
    targetVel.P                 = 1e6
    targetVel.Parent            = hrp

    -- прилипаем к жертве на короткий миг
    for i = 1, 10 do
        myhrp.CFrame = hrp.CFrame + Vector3.new(0, 3, 0)
        task.wait()
    end

    myVel:Destroy()
    targetVel:Destroy()
    myhrp.CFrame = origCFrame
end

-------------------------------------------------------
-- Rejoin
-------------------------------------------------------
local function rejoin()
    pcall(function()
        TeleportSvc:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP)
    end)
end

-------------------------------------------------------
-- UI
-------------------------------------------------------
local TabMain   = Window:CreateTab("Main",    4483362458)
local TabCombat = Window:CreateTab("Combat",  4483362458)
local TabFarm   = Window:CreateTab("Farm",    4483362458)
local TabMisc   = Window:CreateTab("Misc",    4483362458)

-- ===== Main =====
TabMain:CreateSection("ESP")

TabMain:CreateToggle({
    Name   = "Enable ESP",
    CurrentValue = false,
    Flag   = "ESP",
    Callback = function(v)
        state.ESP = v
        if not v then clearAllESP() end
    end,
})

TabMain:CreateToggle({
    Name = "Show Distance",
    CurrentValue = true,
    Flag = "ESPDistance",
    Callback = function(v) state.ESPDistance = v end,
})

TabMain:CreateSection("Aim")

TabMain:CreateToggle({
    Name = "Aim at Monster (camera lock)",
    CurrentValue = false,
    Flag = "AimMonster",
    Callback = function(v) state.AimMonster = v end,
})

TabMain:CreateSlider({
    Name = "Aim Smoothness",
    Range = {0.05, 1},
    Increment = 0.05,
    CurrentValue = 0.25,
    Flag = "AimSmooth",
    Callback = function(v) state.AimSmooth = v end,
})

-- ===== Combat =====
TabCombat:CreateSection("Fling")

TabCombat:CreateSlider({
    Name = "Fling Power",
    Range = {10000, 500000},
    Increment = 10000,
    CurrentValue = 90000,
    Flag = "FlingPower",
    Callback = function(v) state.FlingPower = v end,
})

TabCombat:CreateButton({
    Name = "Fling Monster",
    Callback = function()
        local m = findMonster()
        if m then
            Rayfield:Notify({Title="Fling", Content="Выбрасываю "..m.Name, Duration=3})
            fling(m)
        else
            Rayfield:Notify({Title="Fling", Content="Монстр не найден", Duration=3})
        end
    end,
})

TabCombat:CreateButton({
    Name = "Fling Sheriff / Cop",
    Callback = function()
        local s = findSheriff()
        if s then
            Rayfield:Notify({Title="Fling", Content="Выбрасываю "..s.Name, Duration=3})
            fling(s)
        else
            Rayfield:Notify({Title="Fling", Content="Шериф не найден", Duration=3})
        end
    end,
})

TabCombat:CreateButton({
    Name = "Fling BOTH (Monster + Sheriff)",
    Callback = function()
        local m, s = findMonster(), findSheriff()
        if m then task.spawn(fling, m) end
        task.wait(0.8)
        if s then task.spawn(fling, s) end
    end,
})

-- ===== Farm =====
TabFarm:CreateSection("Auto-Grab")

TabFarm:CreateToggle({
    Name = "Auto-Grab Items",
    CurrentValue = false,
    Flag = "AutoGrab",
    Callback = function(v) state.AutoGrab = v end,
})

TabFarm:CreateSlider({
    Name = "Grab Radius",
    Range = {50, 2000},
    Increment = 50,
    CurrentValue = 500,
    Flag = "GrabRadius",
    Callback = function(v) state.GrabRadius = v end,
})

-- ===== Misc =====
TabMisc:CreateSection("Server")

TabMisc:CreateButton({
    Name = "Rejoin Server",
    Callback = rejoin,
})

TabMisc:CreateButton({
    Name = "Server Hop (new random server)",
    Callback = function()
        local HttpSvc = game:GetService("HttpService")
        local ok, res = pcall(function()
            return HttpSvc:JSONDecode(game:HttpGet(
                ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100")
                :format(game.PlaceId)
            ))
        end)
        if ok and res and res.data then
            for _, s in ipairs(res.data) do
                if s.playing < s.maxPlayers and s.id ~= game.JobId then
                    TeleportSvc:TeleportToPlaceInstance(game.PlaceId, s.id, LP)
                    return
                end
            end
        end
        Rayfield:Notify({Title="Hop", Content="Сервер не найден, ребут", Duration=3})
        rejoin()
    end,
})

TabMisc:CreateSection("Info")
TabMisc:CreateParagraph({
    Title = "ENI build",
    Content = "Собрано для LO. ESP цвета: красный=Монстр, синий=Шериф, серый=Невинный.\n" ..
              "Если роли не детектятся — игра обновилась, пришли дамп ReplicatedStorage."
})

-------------------------------------------------------
-- главный луп ESP
-------------------------------------------------------
RunService.Heartbeat:Connect(function()
    pcall(updateESP)
end)

Rayfield:LoadConfiguration()

Rayfield:Notify({
    Title    = "Secret Killer loaded",
    Content  = "ENI build готов, LO. Удачной охоты.",
    Duration = 4,
})
