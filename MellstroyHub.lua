-- ============================================================
-- НАДЁЖНАЯ ЗАГРУЗКА OBSIDIAN
-- ============================================================
-- ============================================================
-- ANTI RE-INJECT (защита от двойной инжекции)
-- ============================================================
do
    local FLAG = "__MellstroyHub_Loaded"
    local INSTANCE_ID = "__MellstroyHub_Instance"

    if getgenv()[FLAG] == true then
        print("[MellstroyHub] Уже заинжекчен. Повторная инжекция отменена.")

        pcall(function()
            if getgenv().__MellstroyHub_Library and getgenv().__MellstroyHub_Library.Notify then
                getgenv().__MellstroyHub_Library:Notify({
                    Title = "MellstroyHub",
                    Description = "Уже запущен!",
                    Time = 3
                })
            end
        end)

        return
    end

    -- НЕ ставим флаг здесь! Ставим только после успешной загрузки Library.
    getgenv()[INSTANCE_ID] = tick()
end

local function safeHttpGet(url)
    -- Пробуем разные способы
    local methods = {
        function() return game:HttpGet(url, true) end,
        function() return game:HttpGet(url) end,
    }
    if request then
        table.insert(methods, function()
            local r = request({ Url = url, Method = "GET" })
            return r and r.Body
        end)
    end
    if syn and syn.request then
        table.insert(methods, function()
            local r = syn.request({ Url = url, Method = "GET" })
            return r and r.Body
        end)
    end
    if http_request then
        table.insert(methods, function() return http_request({ Url = url, Method = "GET" }).Body end)
    end

    for i, fn in ipairs(methods) do
        local ok, res = pcall(fn)
        if ok and type(res) == "string" and #res > 100 then
            print("[Loader] Успешно скачано через метод #" .. i .. " (" .. #res .. " байт)")
            return res
        end
    end
    return nil
end

local repos = {
    "https://raw.githubusercontent.com/deividcomsono/Obsidian/refs/heads/main/",
    "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/",
    "https://raw.githubusercontent.com/deividcomsono/Obsidian/master/",
}

local Library, SaveManager, ThemeManager

for _, repo in ipairs(repos) do
    print("[Loader] Пробую: " .. repo)
    local src = safeHttpGet(repo .. "Library.lua")
    if src then
        local fn = loadstring or load
        local ok, lib = pcall(fn, src)
        if ok and lib then
            Library = lib()
            print("[Loader] Library OK")
            local smSrc = safeHttpGet(repo .. "addons/SaveManager.lua")
            local tmSrc = safeHttpGet(repo .. "addons/ThemeManager.lua")
            if smSrc then SaveManager = loadstring(smSrc)() end
            if tmSrc then ThemeManager = loadstring(tmSrc)() end
            break
        else
            warn("[Loader] loadstring упал:", lib)
        end
    end
end

if not Library then
    warn("[Loader] ОШИБКА: не удалось загрузить Obsidian. Проверь интернет/executor.")
    -- Сброс флага — чтобы можно было переинжектить после фикса
    getgenv()["__MellstroyHub_Loaded"] = false
    getgenv()["__MellstroyHub_Instance"] = nil
    return
end

local Options = Library.Options
-- ✅ Library успешно загружен — теперь ставим флаг
getgenv()["__MellstroyHub_Loaded"] = true
getgenv()["__MellstroyHub_Library"] = Library
-- Сохраняем ссылки для anti-reinject
getgenv().__MellstroyHub_Library = Library
getgenv().__MellstroyHub_Unload = function()
    pcall(function()
        if Library and Library.Unload then
            Library:Unload()
        end
    end)
    pcall(function()
        RunAllCleanups()
    end)
    getgenv().__MellstroyHub_Loaded = false
    getgenv().__MellstroyHub_Library = nil
    getgenv().__MellstroyHub_Unload = nil
    print("[MellstroyHub] Unloaded by re-inject.")
end
local Toggles = Library.Toggles

task.spawn(function()
    local CG = game:GetService("CoreGui")
    for _, name in ipairs({ "MyHub_ESP", "MyHub_KeyBindList", "MyHub_ShiverTimer" }) do
        local old = CG:FindFirstChild(name)
        if old then pcall(function() old:Destroy() end) end
    end

    local toRemove = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        local n = obj.Name
        if n == "DoorESP_Anchor" or n == "RouteCue_Anchor"
           or n == "MyHub_EntityAnchor" or n == "MyHub_EntityBox"
           or n:match("^Edge%d+$") then
            table.insert(toRemove, obj)
        end
    end
    for _, obj in ipairs(toRemove) do
        pcall(function() obj:Destroy() end)
    end
end)


-- ============================================================
-- UNIVERSAL CLEANUP REGISTRY
-- ============================================================
local CleanupRegistry = {}

local function RegisterCleanup(name, fn)
    table.insert(CleanupRegistry, { Name = name, Fn = fn })
end

local function RunAllCleanups()
    -- ФАЗА 1: отключаем функционал (без SetValue — они отложены)
    for _, entry in ipairs(CleanupRegistry) do
        pcall(function()
            entry.Fn()
        end)
    end

    -- ФАЗА 2: сбрасываем UI-тогглы ПОСЛЕ функционала
    -- (когда функции уже отключены — SetValue безопасен)
    task.defer(function()
        for _, entry in ipairs(CleanupRegistry) do
            if entry.ResetToggles then
                pcall(entry.ResetToggles)
            end
        end
    end)

    print("[MyHub] Cleanup complete. Functions disabled: " .. #CleanupRegistry)
end

local function SafeSetValue(toggle, value)
    if not toggle then return end
    task.defer(function()
        pcall(function() toggle:SetValue(value) end)
    end)
end



-- ============================================================
-- SLIDER DEFAULT RESET (middle mouse click)
-- ============================================================
local SliderDefaults = {}
local SliderRefs = {}

local function AddResettableSlider(Parent, Key, Opts)
    local option = Parent:AddSlider(Key, Opts)
    if Opts.Text and Opts.Default ~= nil then
        SliderDefaults[Opts.Text] = { Key = Key, Default = Opts.Default, Ref = option }
    end
    SliderRefs[Key] = option

    -- Прицепить MMB к ФРЕЙМУ самого слайдера (не поиск по координатам!)
    task.spawn(function()
        task.wait(1)
        local holder = option.Holder or option.Frame
        if holder then
            print("[SliderReset] Прицепил к " .. Opts.Text)
            holder.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton3 then
                    pcall(function() option:SetValue(Opts.Default) end)
                    if Library and Library.Notify then
                        Library:Notify("Reset " .. Opts.Text .. " = " .. tostring(Opts.Default), 2)
                    end
                end
            end)
        else
            warn("[SliderReset] Нет Frame у " .. Opts.Text)
        end
    end)

    return option
end


local CoreGui = game:GetService("CoreGui")

-- ============================================================
-- KEYBIND LIST — плавающий список активных биндов
-- ============================================================
do
local KeyBindListState = {
    Entries = {},
    UI = nil,
    Frame = nil,
    ListFrame = nil,
    Enabled = false,
    Dragging = false,
    DragStart = nil,
    DragOffset = nil,
    RefreshConn = nil,
}

local function CreateKeyBindListUI()
    if KeyBindListState.UI then return KeyBindListState.UI end

    local gui = Instance.new("ScreenGui")
    gui.Name = "MyHub_KeyBindList"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.Parent = CoreGui
    KeyBindListState.UI = gui

    -- Общий контейнер, растёт по вертикали
    local frame = Instance.new("Frame")
    frame.Name = "Frame"
    frame.AutomaticSize = Enum.AutomaticSize.Y
    frame.Size = UDim2.new(0, 240, 0, 0)
    frame.Position = UDim2.new(0.02, 0, 0.4, 0)
    frame.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    frame.BackgroundTransparency = 0.15
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Parent = gui
    KeyBindListState.Frame = frame

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(60, 60, 80)
    stroke.Thickness = 1
    stroke.Transparency = 0.4
    stroke.Parent = frame

    -- Padding всего фрейма
    local framePadding = Instance.new("UIPadding")
    framePadding.PaddingTop    = UDim.new(0, 4)
    framePadding.PaddingBottom = UDim.new(0, 6)
    framePadding.PaddingLeft   = UDim.new(0, 4)
    framePadding.PaddingRight  = UDim.new(0, 4)
    framePadding.Parent = frame

    -- Layout: заголовок + список
    local mainLayout = Instance.new("UIListLayout")
    mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
    mainLayout.Padding = UDim.new(0, 4)
    mainLayout.Parent = frame

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.LayoutOrder = 1
    title.Size = UDim2.new(1, 0, 0, 22)
    title.BackgroundTransparency = 1
    title.Text = "Keybinds"
    title.TextColor3 = Color3.fromRGB(200, 200, 220)
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Center
    title.Parent = frame

    local list = Instance.new("Frame")
    list.Name = "List"
    list.LayoutOrder = 2
    list.Size = UDim2.new(1, 0, 0, 0)
    list.BackgroundTransparency = 1
    list.AutomaticSize = Enum.AutomaticSize.Y
    list.Parent = frame
    KeyBindListState.ListFrame = list

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 2)
    layout.Parent = list

    -- Перетаскивание мышью (за title)
    local UserInputService = game:GetService("UserInputService")
    title.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            KeyBindListState.Dragging = true
            KeyBindListState.DragStart = input.Position
            KeyBindListState.DragOffset = frame.Position
        end
    end)
    title.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement and KeyBindListState.Dragging then
            local delta = input.Position - KeyBindListState.DragStart
            frame.Position = UDim2.new(
                KeyBindListState.DragOffset.X.Scale,
                KeyBindListState.DragOffset.X.Offset + delta.X,
                KeyBindListState.DragOffset.Y.Scale,
                KeyBindListState.DragOffset.Y.Offset + delta.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            KeyBindListState.Dragging = false
        end
    end)

    return gui
end

getgenv().RegisterKeyBind = function(Id, Name, GetKeyFunc, IsActiveFunc, ToggleObj, KeyPickerObj)
    KeyBindListState.Entries[Id] = {
        Id = Id,
        Name = Name,
        GetKey = GetKeyFunc,
        IsActive = IsActiveFunc,
        Toggle = ToggleObj,
    }
    -- Мгновенное обновление при смене тоггла
    if ToggleObj and ToggleObj.OnChanged then
        ToggleObj:OnChanged(function()
            if KeyBindListState.Enabled then
                KeyBindListState.Rebuild()
            end
        end)
    end
	    -- Форс-перестройка Rows + мгновенное обновление
    KeyBindListState.Rows = nil
    if KeyBindListState.Enabled and KeyBindListState.ListFrame then
        KeyBindListState.Rebuild()
    end

    -- Форсим полный Rebuild и через 0.5 сек (UI может строиться)
    task.delay(0.5, function()
        if KeyBindListState.Enabled and KeyBindListState.ListFrame then
            KeyBindListState.Rows = nil
            KeyBindListState.Rebuild()
        end
    end)
	end

function SetKeyBindListEnabled(value)
    KeyBindListState.Enabled = value
    if value then
        local ui = CreateKeyBindListUI()
        ui.Enabled = true
        KeyBindListState.Rows = nil
        KeyBindListState.Rebuild()
        -- Лёгкий polling — ТОЛЬКО для текста [KEY] и цвета точки
        -- Тоггл-состояние обновляется мгновенно через OnChanged, polling подстраивает текст клавиши
        if KeyBindListState.RefreshConn then
            task.cancel(KeyBindListState.RefreshConn)
        end
        KeyBindListState.RefreshConn = task.spawn(function()
            while KeyBindListState.Enabled do
                task.wait(0.2)   -- 0.2 сек — практически незаметно
                KeyBindListState.Rebuild()
            end
        end)
    else
        if KeyBindListState.UI then
            KeyBindListState.UI.Enabled = false
        end
        if KeyBindListState.RefreshConn then
            task.cancel(KeyBindListState.RefreshConn)
            KeyBindListState.RefreshConn = nil
        end
    end
end


function KeyBindListState.Rebuild()
    if not KeyBindListState.ListFrame then return end

    -- Строим UI при первом вызове
    if not KeyBindListState.Rows then
        KeyBindListState.Rows = {}
        KeyBindListState.ListFrame:ClearAllChildren()

        local layout = Instance.new("UIListLayout")
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Padding = UDim.new(0, 2)
        layout.Parent = KeyBindListState.ListFrame

        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 8)
        padding.PaddingRight = UDim.new(0, 8)
        padding.PaddingBottom = UDim.new(0, 6)
        padding.Parent = KeyBindListState.ListFrame
    end

    -- ГЛАВНОЕ: создаём строки для ВСЕХ записей (в т.ч. новых)
    local order = 1
    for id, entry in pairs(KeyBindListState.Entries) do
        if not KeyBindListState.Rows[id] then
            -- Новая запись — создаём строку
            local row = Instance.new("Frame")
            row.Name = "Row_" .. tostring(id)
            row.LayoutOrder = order
            row.Size = UDim2.new(1, 0, 0, 20)
            row.BackgroundTransparency = 1
            row.Parent = KeyBindListState.ListFrame

            local lbl = Instance.new("TextLabel")
            lbl.Size = UDim2.new(1, 0, 1, 0)
            lbl.BackgroundTransparency = 1
            lbl.Text = "..."
            lbl.TextSize = 12
            lbl.Font = Enum.Font.Gotham
            lbl.TextXAlignment = Enum.TextXAlignment.Left
            lbl.Parent = row

            KeyBindListState.Rows[id] = lbl
        end
        order = order + 1
    end

    -- Обновляем текст/цвет у всех строк
    for id, entry in pairs(KeyBindListState.Entries) do
        local lbl = KeyBindListState.Rows[id]
        if lbl then
            local key = "?"
            local ok, res = pcall(entry.GetKey)
            if ok and res ~= nil then key = tostring(res) end

            local isActive = false
            if entry.IsActive then
                local okA, resA = pcall(entry.IsActive)
                if okA and resA then isActive = true end
            end

            if isActive then
                local newText = "[" .. key .. "]  ●  " .. entry.Name
                local newColor = Color3.fromRGB(120, 220, 140)
                if lbl.Text ~= newText then lbl.Text = newText end
                if lbl.TextColor3 ~= newColor then lbl.TextColor3 = newColor end
            else
                local newText = "[" .. key .. "]  ○  " .. entry.Name
                local newColor = Color3.fromRGB(140, 140, 160)
                if lbl.Text ~= newText then lbl.Text = newText end
                if lbl.TextColor3 ~= newColor then lbl.TextColor3 = newColor end
            end
        end
    end
end
end

-- ============================================================
-- ПРОВЕРКА ИНЖЕКТОРА
-- ============================================================
local Environment = {}
local Results = {}
local Passed = 0
local Failed = 0

local BrokenFeatures = {
    ["Solara"] = { "require" },
    ["Xeno"]   = { "require" },
}

local RootEnv = getfenv(0)
local function GetGlobal(Path)
    local Value = RootEnv
    while Value ~= nil and Path ~= "" do
        local Name, NextPath = string.match(Path, "^([^.]+)%.?(.*)$")
        Value = Value[Name]
        Path = NextPath
    end
    return Value
end
local Global = setmetatable({}, { __index = function(_, Name) return GetGlobal(Name) end })
local Services = setmetatable({}, { __index = function(_, Name) return game:GetService(Name) end })

local function AddResult(Text, DidPass)
    table.insert(Results, { Text = Text, Passed = DidPass })
end

local function RunTest(Name, Test, InternalName)
    local TimedOut = false
    local ExecutorName = Global.identifyexecutor and Global.identifyexecutor() or "Unknown"
    local BrokenList = BrokenFeatures[ExecutorName]

    if BrokenList and table.find(BrokenList, Name) then
        AddResult("❌ " .. Name .. " (skipped)", false)
        Failed = Failed + 1
        return
    end

    local TargetGlobal = Global[Name]
    if not TargetGlobal then
        AddResult("❌ " .. Name .. " (nil)", false)
        Failed = Failed + 1
        return
    end

    local Finished = false
    task.spawn(function()
        local Success, Result = pcall(Test)
        if not TimedOut then
            if Success then
                Environment[InternalName or Name] = TargetGlobal
                AddResult("✅ " .. Name, true)
                Passed = Passed + 1
            else
                AddResult("❌ " .. Name .. ": " .. tostring(Result), false)
                Failed = Failed + 1
            end
        end
        Finished = true
    end)

    local Time = 0
    while not Finished do
        Time = Time + 1
        if Time > 50 then
            AddResult("❌ " .. Name .. " (timeout)", false)
            Failed = Failed + 1
            TimedOut = true
            break
        end
        task.wait(0.1)
    end
end

RunTest("getgenv", function()
    assert(typeof(Global.getgenv()) == "table")
    Global.getgenv().Test = "ok"
    assert(Test == "ok")
    Global.getgenv().Test = nil
end)
RunTest("identifyexecutor", function()
    assert(typeof(Global.identifyexecutor()) == "string")
end)
RunTest("cloneref", function()
    local p = Instance.new("Part")
    local c = Global.cloneref(p)
    assert(typeof(c) == "Instance" and p ~= c)
    p:Destroy()
end)
RunTest("gethui", function()
    assert(typeof(Global.gethui()) == "Instance")
end)
RunTest("fireproximityprompt", function()
    local p = Instance.new("Part", Services.Workspace)
    local pr = Instance.new("ProximityPrompt", p)
    local f = false
    local c = pr.Triggered:Connect(function() f = true end)
    Global.fireproximityprompt(pr)
    local t = 0
    while not f and t < 10 do t = t + 1 task.wait(0.1) end
    c:Disconnect(); p:Destroy()
    assert(f, "not fired")
end)
RunTest("fireclickdetector", function()
    local p = Instance.new("Part", Services.Workspace)
    local cd = Instance.new("ClickDetector", p)
    local f = false
    local c = cd.MouseClick:Connect(function() f = true end)
    Global.fireclickdetector(cd)
    local t = 0
    while not f and t < 10 do t = t + 1 task.wait(0.1) end
    c:Disconnect(); p:Destroy()
    assert(f, "not fired")
end)
RunTest("firetouchinterest", function()
    local p1 = Instance.new("Part", Services.Workspace)
    p1.Position = Vector3.new(0, 1000, 0)
    local p2 = Instance.new("Part", Services.Workspace)
    p2.Position = Vector3.new(0, 1000, 0)
    local f = false
    local c = p1.Touched:Connect(function(x) if x == p2 then f = true end end)
    Global.firetouchinterest(p1, p2, 0); task.wait()
    Global.firetouchinterest(p1, p2, 1)
    local t = 0
    while not f and t < 10 do t = t + 1 task.wait(0.1) end
    c:Disconnect(); p1:Destroy(); p2:Destroy()
    assert(f, "not fired")
end)
RunTest("newcclosure", function()
    local f = function() return 10 end
    local c = Global.newcclosure(f)
    assert(c() == 10)
end)
RunTest("hookfunction", function()
    local f = function() return 10 end
    local old = Global.hookfunction(f, function() return 100 end)
    assert(f() == 100 and old() == 10)
    Global.restorefunction(f)
end)
RunTest("hookmetamethod", function()
    local t = setmetatable({}, { __index = Global.newcclosure(function() return "a" end) })
    Global.hookmetamethod(t, "__index", Global.newcclosure(function() return "b" end))
    assert(t.X == "b")
end)
RunTest("getrawmetatable", function()
    local mt = { __metatable = "L" }
    local o = setmetatable({}, mt)
    assert(Global.getrawmetatable(o) == mt)
end)
RunTest("isreadonly", function()
    assert(Global.isreadonly({}) == false)
    assert(Global.isreadonly(table.freeze({})) == true)
end)
RunTest("writefile", function()
    Global.writefile("_ab_test", "x")
    assert(Global.readfile("_ab_test") == "x")
    Global.delfile("_ab_test")
end)
RunTest("getcustomasset", function()
    assert(Environment.writefile, "writefile required")
    Global.writefile("_ab_img", game:HttpGet("https://raw.githubusercontent.com/bocaj111004/Abysall/refs/heads/main/Assets/Check.png"))
    local a = Global.getcustomasset("_ab_img")
    Global.delfile("_ab_img")
    assert(string.find(a, "rbxasset://") or string.find(a, "rbxassetid://"))
end)
RunTest("gethiddenproperty", function()
    local p = Instance.new("Part")
    local v = Global.gethiddenproperty(p, "NetworkIsSleeping")
    p:Destroy()
    assert(v == false)
end)
RunTest("getthreadidentity", function()
    assert(typeof(Global.getthreadidentity()) == "number")
end)
RunTest("isnetworkowner", function()
    local p = Instance.new("Part", Services.Workspace)
    local v = Global.isnetworkowner(p)
    p:Destroy()
    assert(typeof(v) == "boolean")
end)
RunTest("firesignal", function()
    local e = Instance.new("RemoteEvent")
    local f = false
    local c = e.OnClientEvent:Connect(function() f = true end)
    Global.firesignal(e.OnClientEvent, "hi")
    local t = 0
    while not f and t < 10 do t = t + 1 task.wait(0.1) end
    c:Disconnect(); e:Destroy()
    assert(f)
end)
RunTest("getconnections", function()
    local c = game.ChildAdded:Connect(function() end)
    local list = Global.getconnections(game.ChildAdded)
    c:Disconnect()
    assert(#list > 0)
end)
RunTest("require", function()
    local m = Global.require(Services.Players.LocalPlayer.PlayerScripts.PlayerModule)
    assert(typeof(m) == "table")
end)
RunTest("Drawing.new", function()
    local d = Global.Drawing.new("Circle")
    d.Visible = false
    d:Remove()
end, "Drawing_New")
RunTest("replicatesignal", function()
    local f = Instance.new("Frame")
    Global.replicatesignal(f.MouseWheelForward, 1, 2)
    f:Destroy()
end)

-- ============================================================
-- СОЗДАЁМ МЕНЮ (Obsidian)
-- ============================================================
Window = Library:CreateWindow({
    Title = "MellstroyHub",
    Footer = "version 1.0",
    NotifySide = "Right",
    ShowCustomCursor = false,
    AutoShow = true,
    Center = true,
    TabPadding = 3,
    MenuFadeTime = 0,
    CornerRadius = 6,
})

Tabs = {
    Info     = Window:AddTab("Info", "user"),
    Lobby    = Window:AddTab("Lobby", "house"),
    Exploits = Window:AddTab("Exploits", "zap"),
    Visuals  = Window:AddTab("Visuals", "eye"),
    Rofls    = Window:AddTab("Rofls", "smile"),
    Settings = Window:AddTab("Settings", "settings"),
}
-- Локальные алиасы (глобальные не выставляются в этой версии Obsidian)
Options = Library.Options
Toggles = Library.Toggles

-- ==== Info Tab ====
local ExecName = Global.identifyexecutor and Global.identifyexecutor() or "Unknown"
local ExecVersion = "Unknown"
pcall(function()
    if Global.getexecutorname then ExecName = Global.getexecutorname() end
    if Global.getversion then ExecVersion = Global.getversion() end
end)

local UserName = "Unknown"
local UserDisplay = "Unknown"
local UserId = 0
pcall(function()
    UserName = game.Players.LocalPlayer.Name
    UserDisplay = game.Players.LocalPlayer.DisplayName
    UserId = game.Players.LocalPlayer.UserId
end)

-- ============ LEFT: User Info ============
local InfoLeft = Tabs.Info:AddLeftGroupbox("User Info")

-- Сначала создаём все labels — они нужны, чтобы Obsidian построил ScrollingFrame
InfoLeft:AddLabel("Name: " .. tostring(UserName), true)
InfoLeft:AddLabel("DisplayName: " .. tostring(UserDisplay), true)
InfoLeft:AddLabel("UserId: " .. tostring(UserId), true)

-- Теперь ищем ScrollingFrame внутри Groupbox и вставляем туда аватар
task.spawn(function()
    task.wait(0.5)  -- ждём пока Obsidian построит UI

    -- Ищем ScrollingFrame где лежат наши labels
    local function findScrolling(inst)
        if not inst then return nil end
        for _, d in ipairs(inst:GetDescendants()) do
            if d:IsA("ScrollingFrame") then
                -- Проверяем что внутри есть наш label
                for _, c in ipairs(d:GetChildren()) do
                    if c:IsA("TextLabel") and c.Text:find("Name:") then
                        return d
                    end
                end
            end
        end
        return nil
    end

    local scroll
    for _, sg in ipairs(game:GetService("CoreGui"):GetChildren()) do
        scroll = findScrolling(sg)
        if scroll then break end
    end

    if not scroll then
        warn("[MyHub] ScrollingFrame не найден — аватар не добавлен")
        return
    end

    -- Создаём аватар ВНУТРИ ScrollingFrame
local AvatarFrame = Instance.new("Frame")
AvatarFrame.Name = "AvatarFrame"
AvatarFrame.Size = UDim2.new(1, 0, 0, 110)
AvatarFrame.BackgroundTransparency = 1
AvatarFrame.LayoutOrder = -1
AvatarFrame.Parent = scroll

local Avatar = Instance.new("ImageLabel")
Avatar.AnchorPoint = Vector2.new(0.5, 0)
Avatar.Position = UDim2.new(0.5, 0, 0, 0)
Avatar.Size = UDim2.new(1, -8, 0, 100)
Avatar.BackgroundTransparency = 1
Avatar.Image = ""
task.spawn(function()
    -- Способ 1: rbxthumb с PreloadAsync
    local thumb = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(UserId) .. "&w=420&h=420"
    Avatar.Image = thumb

    -- Прекешим — это заставит движок резолвить URI
    local ok = pcall(function()
        game:GetService("ContentProvider"):PreloadAsync({ Avatar })
    end)
    task.wait(1)

    if Avatar.IsLoaded then
        print("[MyHub] Avatar loaded via rbxthumb + Preload")
        return
    end

    -- Способ 2: скачиваем PNG как custom asset
    local url = "https://www.roblox.com/headshot-thumbnail/image?userId="
        .. tostring(UserId) .. "&width=420&height=420&format=png"
    local ok2, data = pcall(function() return game:HttpGet(url) end)
    if ok2 and data and #data > 100 then
        if writefile and getcustomasset then
            pcall(function() writefile("_myhub_avatar.png", data) end)
            local ok3, asset = pcall(function() return getcustomasset("_myhub_avatar.png") end)
            if ok3 and asset then
                Avatar.Image = ""
                task.wait(0.2)
                Avatar.Image = asset
                pcall(function()
                    game:GetService("ContentProvider"):PreloadAsync({ Avatar })
                end)
                task.wait(0.5)
                if Avatar.IsLoaded then
                    print("[MyHub] Avatar loaded via custom asset")
                    return
                end
            end
        end
    end

    print("[MyHub] Avatar: NOT loaded. IsLoaded:", Avatar.IsLoaded)
end)
Avatar.ScaleType = Enum.ScaleType.Crop
Avatar.Parent = AvatarFrame

local AvatarCorner = Instance.new("UICorner")
AvatarCorner.CornerRadius = UDim.new(0, 8)
AvatarCorner.Parent = Avatar

    print("[MyHub] Avatar добавлен в ScrollingFrame")
end)

-- ============ RIGHT: Credits ============
local CreditsBox = Tabs.Info:AddRightGroupbox("Credits")

local function AddColoredLabel(Groupbox, Text, Color)
    local label = Groupbox:AddLabel(Text, true)
    -- Пытаемся покрасить через разные возможные поля Obsidian
    pcall(function()
        if label.SetTextColor then label:SetTextColor(Color) end
    end)
    pcall(function()
        if label.Label and label.Label.TextColor3 then label.Label.TextColor3 = Color end
    end)
    pcall(function()
        if label.TextLabel then label.TextLabel.TextColor3 = Color end
    end)
    pcall(function()
        if label.Frame and label.Frame.TextLabel then label.Frame.TextLabel.TextColor3 = Color end
    end)
    pcall(function()
        if label.Holder and label.Holder.TextLabel then label.Holder.TextLabel.TextColor3 = Color end
    end)
    return label
end

AddColoredLabel(CreditsBox, "Hviiia — Developer",         Color3.fromRGB(255, 215, 0))    -- золотой
AddColoredLabel(CreditsBox, "Obsidian UI — Library",       Color3.fromRGB(120, 200, 255))  -- голубой

-- ============ RIGHT третий: Executor Info ============
local ExecInfoBox = Tabs.Info:AddRightGroupbox("Executor Info")
ExecInfoBox:AddLabel("Name: " .. tostring(ExecName), true)
ExecInfoBox:AddLabel("Version: " .. tostring(ExecVersion), true)
ExecInfoBox:AddLabel(("Tests Passed: %d / %d"):format(Passed, Passed + Failed), true)

-- ============ RIGHT четвёртый: Test Results ============
local TestResultsBox = Tabs.Info:AddRightGroupbox("Test Results")
for _, R in ipairs(Results) do
    TestResultsBox:AddLabel(R.Text, true)
end

local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local LP               = game:GetService("Players").LocalPlayer

do
-- ==== Lobby Tab ====
local LobbyLeft  = Tabs.Lobby:AddLeftGroupbox("Character")
local LobbyRight = Tabs.Lobby:AddRightGroupbox("Lighting")

local function Resolve(returned, globalTable, key)
    return returned or (globalTable and globalTable[key])
end



-- ============================================================
-- NOCLIP (Lobby — независимый)
-- ============================================================
local NoclipConnLobby = nil
local NoclipSavedCollideLobby = {}
local NoclipToggleLobby = LobbyLeft:AddToggle("NoclipToggleLobby", {
    Text = "Noclip", Default = false,
    Tooltip = "Проходишь сквозь стены."
})
NoclipToggleLobby = NoclipToggleLobby or (Toggles and Toggles.NoclipToggleLobby)

if NoclipToggleLobby then
    NoclipToggleLobby:OnChanged(function(Value)
        if NoclipConnLobby then NoclipConnLobby:Disconnect() NoclipConnLobby = nil end

        if not Value then
            local char = LP.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        local orig = NoclipSavedCollideLobby[part]
                        if orig ~= nil then
                            part.CanCollide = orig
                        end
                    end
                end
            end
            NoclipSavedCollideLobby = {}
            return
        end

        NoclipSavedCollideLobby = {}
        local char = LP.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    NoclipSavedCollideLobby[part] = part.CanCollide
                end
            end
        end

        NoclipConnLobby = RunService.Stepped:Connect(function()
            local char = LP.Character
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    if NoclipSavedCollideLobby[part] == nil then
                        NoclipSavedCollideLobby[part] = part.CanCollide
                    end
                    part.CanCollide = false
                end
            end
        end)
    end)
end

RegisterCleanup("NoclipLobby", function()
    if NoclipConnLobby then NoclipConnLobby:Disconnect() NoclipConnLobby = nil end
    local char = LP.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                local orig = NoclipSavedCollideLobby[part]
                if orig ~= nil then
                    part.CanCollide = orig
                else
                    part.CanCollide = true
                end
            end
        end
    end
    NoclipSavedCollideLobby = {}
    if Toggles.NoclipToggleLobby then SafeSetValue(Toggles.NoclipToggleLobby, false) end
end)


-- ============================================================
-- FLY
-- ============================================================
local FlyConn = nil
local FlyBody = nil
local FlyToggle = LobbyLeft:AddToggle("FlyToggle", {
    Text = "Fly", Default = false,
    Tooltip = "Позволяет летать. WASD — движение, Space вверх, Ctrl вниз."
})
FlyToggle = FlyToggle or (Toggles and Toggles.FlyToggle)

local FlySpeedSlider = AddResettableSlider(LobbyLeft, "FlySpeed", {
    Text = "Fly Speed",
    Min = 0, Max = 100, Default = 20,
    Rounding = 0, Compact = true
})

local function GetFlySpeed()
    if FlySpeedSlider and FlySpeedSlider.Value then
        return FlySpeedSlider.Value
    end
    if SliderRefs and SliderRefs.FlySpeed and SliderRefs.FlySpeed.Value then
        return SliderRefs.FlySpeed.Value
    end
    if Library and Library.Options and Library.Options.FlySpeed then
        return Library.Options.FlySpeed.Value
    end
    return 20
end

if FlyToggle then
    FlyToggle:OnChanged(function(Value)
        if FlyConn then FlyConn:Disconnect() FlyConn = nil end
        if FlyBody then FlyBody:Destroy() FlyBody = nil end
        if not Value then return end

        local char = LP.Character
        if not char then
            LP.CharacterAdded:Wait()
            char = LP.Character
        end
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        -- Отключаем гравитацию
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = true end

        FlyBody = Instance.new("BodyVelocity")
        FlyBody.Name = "MyHub_FlyBody"
        FlyBody.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        FlyBody.Velocity = Vector3.zero
        FlyBody.Parent = hrp

        FlyConn = RunService.RenderStepped:Connect(function()
            local c = LP.Character
            if not c then return end
            local root = c:FindFirstChild("HumanoidRootPart")
            if not root then return end
            if not FlyBody or not FlyBody.Parent then return end

            local cam = workspace.CurrentCamera
            if not cam then return end

            local speed = GetFlySpeed()
            local dir = Vector3.zero
            local look = cam.CFrame.LookVector

            if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + look end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - look end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end

            FlyBody.Velocity = dir * speed
        end)
    end)
end

RegisterCleanup("Fly", function()
    if FlyConn then FlyConn:Disconnect() FlyConn = nil end
    if FlyBody then FlyBody:Destroy() FlyBody = nil end
    local char = LP.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.PlatformStand = false end
    end
    if Toggles.FlyToggle then SafeSetValue(Toggles.FlyToggle, false) end
end)

-- ============================================================
-- FULLBRIGHT — с постоянным применением
-- ============================================================
local OriginalLighting = { Saved = false }
local FullbrightConn = nil

local FullbrightToggle = LobbyRight:AddToggle("FullbrightToggle", {
    Text = "Fullbright", Default = false,
    Tooltip = "Освещает все пространство."
})
FullbrightToggle = Resolve(FullbrightToggle, Toggles, "FullbrightToggle")

local FullbrightColorPicker = nil
if FullbrightToggle and FullbrightToggle.AddColorPicker then
    FullbrightToggle:AddColorPicker("FullbrightColor", {
        Text = "Ambient Color",
        Default = Color3.fromRGB(200, 200, 200),
        Transparency = 0
    })
end
FullbrightColorPicker = Options and Options.FullbrightColor

local FullbrightBrightness = LobbyRight:AddSlider("FullbrightBrightness", {
    Text = "Brightness",
    Min = 0, Max = 10, Default = 2,
    Rounding = 1, Compact = true
})
FullbrightBrightness = Resolve(FullbrightBrightness, Options, "FullbrightBrightness")

local function GetColor()
    if FullbrightColorPicker then
        local v = FullbrightColorPicker.Value
        if typeof(v) == "Color3" then return v end
    end
    return Color3.fromRGB(200, 200, 200)
end
local function GetBrightness()
    if FullbrightBrightness then
        local v = FullbrightBrightness.Value
        if typeof(v) == "number" then return v end
    end
    return 2
end

local function SaveLighting()
    if OriginalLighting.Saved then return end
    OriginalLighting.Ambient        = Lighting.Ambient
    OriginalLighting.OutdoorAmbient = Lighting.OutdoorAmbient
    OriginalLighting.Brightness     = Lighting.Brightness
    OriginalLighting.ClockTime      = Lighting.ClockTime
    OriginalLighting.GlobalShadows  = Lighting.GlobalShadows
    OriginalLighting.FogEnd         = Lighting.FogEnd
    OriginalLighting.FogStart       = Lighting.FogStart
    OriginalLighting.EnvironmentDiffuseScale  = Lighting.EnvironmentDiffuseScale
    OriginalLighting.EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale
    OriginalLighting.Saved = true
end

local function RestoreLighting()
    if not OriginalLighting.Saved then return end
    Lighting.Ambient        = OriginalLighting.Ambient
    Lighting.OutdoorAmbient = OriginalLighting.OutdoorAmbient
    Lighting.Brightness     = OriginalLighting.Brightness
    Lighting.ClockTime      = OriginalLighting.ClockTime
    Lighting.GlobalShadows  = OriginalLighting.GlobalShadows
    Lighting.FogEnd         = OriginalLighting.FogEnd
    Lighting.FogStart       = OriginalLighting.FogStart
    Lighting.EnvironmentDiffuseScale  = OriginalLighting.EnvironmentDiffuseScale
    Lighting.EnvironmentSpecularScale = OriginalLighting.EnvironmentSpecularScale
end

local function ApplyFullbrightNow()
    local col = GetColor()
    local bri = GetBrightness()
    Lighting.Ambient        = col
    Lighting.OutdoorAmbient = col
    Lighting.Brightness     = bri
    Lighting.ClockTime      = 12
    Lighting.GlobalShadows  = false
    Lighting.FogEnd         = 100000
    Lighting.FogStart       = 0
    Lighting.EnvironmentDiffuseScale  = 1
    Lighting.EnvironmentSpecularScale = 1
    -- Убиваем Atmospheres, которые могут давать туман
    for _, v in ipairs(Lighting:GetChildren()) do
        if v:IsA("Atmosphere") then
            v.Density = 0
        end
    end
end

if FullbrightToggle then
    FullbrightToggle:OnChanged(function(Value)
        if Value then
            SaveLighting()
            ApplyFullbrightNow()

            -- Постоянно переприменяем — игра может твинить Lighting
            if FullbrightConn then FullbrightConn:Disconnect() end
            FullbrightConn = RunService.RenderStepped:Connect(function()
                if not FullbrightToggle.Value then return end
                ApplyFullbrightNow()
            end)
        else
            if FullbrightConn then FullbrightConn:Disconnect() FullbrightConn = nil end
            RestoreLighting()
        end
    end)
end

RegisterCleanup("Fullbright", function()
    if FullbrightConn then FullbrightConn:Disconnect() FullbrightConn = nil end
    if OriginalLighting and OriginalLighting.Saved then
        Lighting.Ambient        = OriginalLighting.Ambient
        Lighting.OutdoorAmbient = OriginalLighting.OutdoorAmbient
        Lighting.Brightness     = OriginalLighting.Brightness
        Lighting.ClockTime      = OriginalLighting.ClockTime
        Lighting.GlobalShadows  = OriginalLighting.GlobalShadows
        Lighting.FogEnd         = OriginalLighting.FogEnd
        Lighting.FogStart       = OriginalLighting.FogStart
        Lighting.EnvironmentDiffuseScale  = OriginalLighting.EnvironmentDiffuseScale
        Lighting.EnvironmentSpecularScale = OriginalLighting.EnvironmentSpecularScale
    end
    if Toggles.FullbrightToggle then SafeSetValue(Toggles.FullbrightToggle, false) end
end)

if FullbrightColorPicker then
    FullbrightColorPicker:OnChanged(function()
        if FullbrightToggle and FullbrightToggle.Value then
            ApplyFullbrightNow()
        end
    end)
end

if FullbrightBrightness then
    FullbrightBrightness:OnChanged(function()
        if FullbrightToggle and FullbrightToggle.Value then
            ApplyFullbrightNow()
        end
    end)
end
end

do
-- ==== Exploits Tab ====
local ExploitsLeft  = Tabs.Exploits:AddLeftGroupbox("Player")      -- сверху слева
local ExploitsRight = Tabs.Exploits:AddLeftGroupbox("Bypass")      -- снизу слева (было справа)
local ExploitsGeneral = Tabs.Exploits:AddRightGroupbox("General")  -- справа — новый

do
-- ============================================================
-- POSITION SPOOF (Over Ceiling)
-- ============================================================
local PositionSpoofToggle = ExploitsGeneral:AddToggle("PositionSpoofToggle", {
    Text = "Position Spoof",
    Default = false,
    Tooltip = "Телепорт над потолок — защита от Cue/Route."
})

if PositionSpoofToggle and PositionSpoofToggle.AddKeyPicker then
    PositionSpoofToggle:AddKeyPicker("PositionSpoofKeybind", {
        Default = "B",
        Mode = "Toggle",
        SyncToggleState = true,
        Text = "Position Spoof",
        NoUI = false,
    })
end

local PositionSpoofAlphaSlider = AddResettableSlider(ExploitsGeneral, "PositionSpoofAlpha", {
    Text = "Ceiling Transparency",
    Min = 0, Max = 1, Default = 0.1,
    Rounding = 2, Compact = true,
})

getgenv().RegisterKeyBind("PositionSpoof", "Position Spoof", function()
    local kp = Library and Library.Options and Library.Options.PositionSpoofKeybind
    if kp then
        if kp.ValueString then return kp.ValueString end
        if kp.Value then return tostring(kp.Value) end
    end
    return "B"
end, function()
    return PositionSpoofToggle and PositionSpoofToggle.Value == true
end, PositionSpoofToggle, Library and Library.Options and Library.Options.PositionSpoofKeybind)

-- ═══════════════════════════════════════════════
local POS_OFFSET_UP = 40            -- подняли с 20 → 40
local POS_CEILING_RADIUS = 300
local POS_RETRY_LIMIT = 5
local POS_RETRY_DELAY = 0.05
-- ═══════════════════════════════════════════════

local PosSpoofState = {
    Enabled = false,
    BaseY = nil,
    BasePos = nil,
    CeilingY = nil,
    BP = nil,
    OrigHRPCanCollide = nil,
    OrigHipHeight = nil,
    ModifiedParts = {},
    RestoreToken = 0,
    DeathConn = nil,
    CeilingScanned = false,   -- ← добавь
}

local function Pos_Alpha()
    local opt = Library and Library.Options and Library.Options.PositionSpoofAlpha
    if opt and typeof(opt.Value) == "number" then return opt.Value end
    return 0.1
end

-- Glitch.Fire блок
do
    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        if PosSpoofState.Enabled == true and method == "Fire"
           and typeof(self) == "Instance" and self:IsA("BindableEvent") then
            if self.Name == "Glitch" then return end
        end
        return oldNamecall(self, ...)
    end)
    setreadonly(mt, true)
end

-- Расширенный raycast: исключаем персонажа И сущностей
local function Pos_BuildRaycastParams()
    local rp = RaycastParams.new()
    rp.FilterType = Enum.RaycastFilterType.Exclude
    local filterList = {}
    local char = LP.Character
    if char then table.insert(filterList, char) end
    local ents = workspace:FindFirstChild("Entities")
    if ents then table.insert(filterList, ents) end
    rp.FilterDescendantsInstances = filterList
    return rp
end

-- Ищем потолок: raycast от ГОЛОВЫ вверх, если не находим — от HRP
local function Pos_FindCeilingY(pos)
    local rp = Pos_BuildRaycastParams()
    local char = LP.Character
    local head = char and char:FindFirstChild("Head")

    -- Стартовая точка: голова если есть, иначе HRP
    local startPos = head and head.Position or pos

    -- Первый raycast: 1000 studs вверх от головы
    local hit = workspace:Raycast(startPos, Vector3.new(0, 1000, 0), rp)
    if hit then return hit.Position.Y end

    -- Fallback: от HRP
    hit = workspace:Raycast(pos, Vector3.new(0, 1000, 0), rp)
    if hit then return hit.Position.Y end

    -- Если вообще ничего — ставим +50 от текущей
    return pos.Y + 50
end

local function Pos_SetCeilingTransparency(alpha)
    if not PosSpoofState.CeilingScanned then
        PosSpoofState.ModifiedParts = {}
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local pos = hrp.Position
        local radiusSq = POS_CEILING_RADIUS * POS_CEILING_RADIUS
        local baseY = PosSpoofState.BaseY or pos.Y

        -- Ищем только в CurrentRooms (не во всём Workspace)
        local rooms = workspace:FindFirstChild("CurrentRooms")
        if not rooms then return end

        for _, room in ipairs(rooms:GetChildren()) do
            if tonumber(room.Name) then
                for _, obj in ipairs(room:GetDescendants()) do
                    if obj:IsA("BasePart") and obj.Transparency < 1 then
                        if obj.Position.Y > baseY + 3 then
                            local dx = obj.Position.X - pos.X
                            local dz = obj.Position.Z - pos.Z
                            if dx*dx + dz*dz < radiusSq then
                                PosSpoofState.ModifiedParts[obj] = obj.LocalTransparencyModifier
                                obj.LocalTransparencyModifier = alpha
                            end
                        end
                    end
                end
            end
        end
        PosSpoofState.CeilingScanned = true
    else
        for part, _ in pairs(PosSpoofState.ModifiedParts) do
            if part and part.Parent then
                if part.LocalTransparencyModifier > alpha then
                    part.LocalTransparencyModifier = alpha
                end
            end
        end
    end
end

local function Pos_RestoreCeiling()
    local parts = PosSpoofState.ModifiedParts
    PosSpoofState.ModifiedParts = {}
    local myToken = PosSpoofState.RestoreToken

    for part, orig in pairs(parts) do
        if part and part.Parent then
            pcall(function() part.LocalTransparencyModifier = orig end)
        end
    end

    task.spawn(function()
        for i = 1, 30 do
            task.wait(0.1)
            if PosSpoofState.RestoreToken ~= myToken then return end
            for part, orig in pairs(parts) do
                if part and part.Parent then
                    if part.LocalTransparencyModifier ~= orig then
                        pcall(function() part.LocalTransparencyModifier = orig end)
                    end
                end
            end
        end
    end)
end

-- Проверка что персонаж жив
local function Pos_IsAlive()
    local char = LP.Character
    if not char then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return false end
    if hum.Health <= 0 then return false end
    local state = hum:GetState()
    if state == Enum.HumanoidStateType.Dead then return false end
    return true
end

-- Отключение при смерти — вызывается из Heartbeat-лупа
local function Pos_HandleDeath()
    if not PosSpoofState.Enabled then return end
    if Pos_IsAlive() then return end

    -- Персонаж мёртв → отключаем спуфер БЕЗ возврата на BaseY
    -- (чтобы не телепортировать труп обратно)
    PosSpoofState.Enabled = false

    local char = LP.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local bp = hrp:FindFirstChild("MyHub_PosSpoofBP")
            if bp then bp:Destroy() end
            if PosSpoofState.OrigHRPCanCollide ~= nil then
                hrp.CanCollide = PosSpoofState.OrigHRPCanCollide
            end
        end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and PosSpoofState.OrigHipHeight then
            hum.HipHeight = PosSpoofState.OrigHipHeight
        end
    end

    Pos_RestoreCeiling()

    PosSpoofState.BP = nil
    PosSpoofState.BaseY = nil
    PosSpoofState.BasePos = nil
    PosSpoofState.CeilingY = nil

    -- Синхронизируем UI-тоггл
    if PositionSpoofToggle then
        pcall(function() PositionSpoofToggle:SetValue(false) end)
    end

    print("[PositionSpoof] Auto-disabled (died)")
end

local function Pos_Enable()
    local char = LP.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    if not Pos_IsAlive() then
        print("[PositionSpoof] Отмена: персонаж мёртв")
        if PositionSpoofToggle then
            pcall(function() PositionSpoofToggle:SetValue(false) end)
        end
        return
    end

    PosSpoofState.RestoreToken = PosSpoofState.RestoreToken + 1
    PosSpoofState.BaseY = hrp.Position.Y
    PosSpoofState.BasePos = hrp.Position
    PosSpoofState.CeilingY = Pos_FindCeilingY(hrp.Position)
    PosSpoofState.OrigHRPCanCollide = hrp.CanCollide
    PosSpoofState.OrigHipHeight = hum.HipHeight

    -- ВАЖНО: сначала телепортируем, потом меняем CanCollide/HipHeight
    -- (иначе при raycast'е персонаж уже "ломаный" и CeilingY может быть неверный)
    local targetY = PosSpoofState.CeilingY + POS_OFFSET_UP
    hrp.CFrame = CFrame.new(hrp.Position.X, targetY, hrp.Position.Z) * hrp.CFrame.Rotation
    hrp.AssemblyLinearVelocity = Vector3.zero

    -- После телепорта: ставим коллизию/hipheight
    hrp.CanCollide = false
    hum.HipHeight = 0.05

    -- BodyPosition
    local bp = hrp:FindFirstChild("MyHub_PosSpoofBP")
    if bp then bp:Destroy() end
    bp = Instance.new("BodyPosition")
    bp.Name = "MyHub_PosSpoofBP"
    bp.MaxForce = Vector3.new(0, math.huge, 0)
    bp.P = 10000
    bp.D = 800
    bp.Position = Vector3.new(hrp.Position.X, targetY, hrp.Position.Z)
    bp.Parent = hrp
    PosSpoofState.BP = bp

    -- Прозрачность потолка
    task.wait(0.1)
    Pos_SetCeilingTransparency(Pos_Alpha())

    -- Проверка: реально ли мы на потолке?
    task.spawn(function()
        for attempt = 1, POS_RETRY_LIMIT do
            task.wait(POS_RETRY_DELAY)
            if not PosSpoofState.Enabled then return end
            local c = LP.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if not r then return end
            local wantY = PosSpoofState.CeilingY + POS_OFFSET_UP
            if math.abs(r.Position.Y - wantY) > 5 then
                r.CFrame = CFrame.new(r.Position.X, wantY, r.Position.Z) * r.CFrame.Rotation
                r.AssemblyLinearVelocity = Vector3.zero
            end
        end
    end)

    print("[PositionSpoof] ON | Ceiling " .. math.floor(PosSpoofState.CeilingY))
end

local function Pos_Disable()
    PosSpoofState.Enabled = false
	PosSpoofState.CeilingScanned = false
    local savedBaseY = PosSpoofState.BaseY

    local char = LP.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hrp then
            local bp = hrp:FindFirstChild("MyHub_PosSpoofBP")
            if bp then bp:Destroy() end

            -- Возвращаем на BaseY только если живы (иначе труп останется висеть)
            if savedBaseY and Pos_IsAlive() then
                hrp.CFrame = CFrame.new(hrp.Position.X, savedBaseY, hrp.Position.Z) * hrp.CFrame.Rotation
                hrp.AssemblyLinearVelocity = Vector3.zero
            end
            if PosSpoofState.OrigHRPCanCollide ~= nil then hrp.CanCollide = PosSpoofState.OrigHRPCanCollide end
        end
        if hum and PosSpoofState.OrigHipHeight then hum.HipHeight = PosSpoofState.OrigHipHeight end
    end

    Pos_RestoreCeiling()

    PosSpoofState.BP = nil
    PosSpoofState.BaseY = nil
    PosSpoofState.BasePos = nil
    PosSpoofState.CeilingY = nil
    PosSpoofState.OrigHRPCanCollide = nil
    PosSpoofState.OrigHipHeight = nil
    print("[PositionSpoof] === OFF ===")
end

if PositionSpoofToggle then
    PositionSpoofToggle:OnChanged(function(Value)
        PosSpoofState.Enabled = Value
        if Value then Pos_Enable() else Pos_Disable() end
    end)
end

-- Alpha live update
do
    local alphaOpt = Library and Library.Options and Library.Options.PositionSpoofAlpha
    if alphaOpt then
        alphaOpt:OnChanged(function()
            if not PosSpoofState.Enabled then return end
            local alpha = Pos_Alpha()
            for part, _ in pairs(PosSpoofState.ModifiedParts) do
                if part and part.Parent then
                    pcall(function() part.LocalTransparencyModifier = alpha end)
                end
            end
        end)
    end
end

-- Main loop
RunService.Heartbeat:Connect(function()
    if not PosSpoofState.Enabled then return end
    if not PosSpoofState.BP or not PosSpoofState.CeilingY then return end

    -- Проверка смерти — самое главное
    Pos_HandleDeath()
    if not PosSpoofState.Enabled then return end

    local char = LP.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    PosSpoofState.BP.Position = Vector3.new(hrp.Position.X, PosSpoofState.CeilingY + POS_OFFSET_UP, hrp.Position.Z)
end)

-- Force alpha
task.spawn(function()
    while true do
        task.wait(1.0)   -- было 0.3 → 1.0 сек (в 3 раза реже)
        if not PosSpoofState.Enabled then continue end
        local alpha = Pos_Alpha()
        for part, _ in pairs(PosSpoofState.ModifiedParts) do
            if part and part.Parent then
                if part.LocalTransparencyModifier > alpha then
                    part.LocalTransparencyModifier = alpha
                end
            end
        end
    end
end)

RegisterCleanup("PositionSpoof", function()
    if PosSpoofState.Enabled then
        PosSpoofState.Enabled = false
        pcall(Pos_Disable)
    end
    if Toggles and Toggles.PositionSpoofToggle then
        SafeSetValue(Toggles.PositionSpoofToggle, false)
    end
end)
end


do
-- ============================================================
-- FAST INTERACT (без лагов)
-- ============================================================
local FastInteractToggle = ExploitsGeneral:AddToggle("FastInteractToggle", {
    Text = "Fast Interact",
    Default = false,
    Tooltip = "Мгновенное взаимодействие."
})

local FastInteractState = {
    Enabled = false,
    SavedHolds = {},
    AddedConn = nil,
}

local function FastInteract_ApplyOne(prompt)
    if not prompt or not prompt:IsA("ProximityPrompt") then return end
    if FastInteractState.SavedHolds[prompt] == nil then
        FastInteractState.SavedHolds[prompt] = prompt.HoldDuration
    end
    if prompt.HoldDuration ~= 0 then
        prompt.HoldDuration = 0
    end
end

local function FastInteract_ApplyAll()
    -- Один раз проходим (при ON)
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            FastInteract_ApplyOne(obj)
        end
    end
end

local function FastInteract_Enable()
    if FastInteractState.Enabled then return end
    FastInteractState.Enabled = true

    FastInteract_ApplyAll()

    -- Новые prompts → сразу обнуляем HoldDuration
    if FastInteractState.AddedConn then
        FastInteractState.AddedConn:Disconnect()
    end
    FastInteractState.AddedConn = workspace.DescendantAdded:Connect(function(obj)
        if FastInteractState.Enabled and obj:IsA("ProximityPrompt") then
            task.wait(0.1)
            FastInteract_ApplyOne(obj)
        end
    end)

    print("[FastInteract] === ON ===")
end

local function FastInteract_Disable()
    if not FastInteractState.Enabled then return end
    FastInteractState.Enabled = false

    if FastInteractState.AddedConn then
        FastInteractState.AddedConn:Disconnect()
        FastInteractState.AddedConn = nil
    end

    for prompt, origHold in pairs(FastInteractState.SavedHolds) do
        if prompt and prompt.Parent then
            pcall(function() prompt.HoldDuration = origHold end)
        end
    end
    FastInteractState.SavedHolds = {}

    print("[FastInteract] === OFF ===")
end

if FastInteractToggle then
    FastInteractToggle:OnChanged(function(Value)
        if Value then FastInteract_Enable() else FastInteract_Disable() end
    end)
end

RegisterCleanup("FastInteract", function()
    pcall(FastInteract_Disable)
    if Toggles and Toggles.FastInteractToggle then
        SafeSetValue(Toggles.FastInteractToggle, false)
    end
end)
end

do
-- ============================================================
-- AUTO INTERACT (simplified — no OpenedByUs)
-- ============================================================
local AutoInteractToggle = ExploitsGeneral:AddToggle("AutoInteractToggle", {
    Text = "Auto Interact",
    Default = false,
    Tooltip = "Автоматическое взаимодействие"
})

if AutoInteractToggle and AutoInteractToggle.AddKeyPicker then
    AutoInteractToggle:AddKeyPicker("AutoInteractKeybind", {
        Default = "R",
        Mode = "Toggle",
        SyncToggleState = true,
        Text = "Auto Interact",
        NoUI = false,
    })
end

getgenv().RegisterKeyBind("AutoInteract", "Auto Interact", function()
    local kp = Library and Library.Options and Library.Options.AutoInteractKeybind
    if kp then
        if kp.ValueString then return kp.ValueString end
        if kp.Value then return tostring(kp.Value) end
    end
    return "R"
end, function()
    return AutoInteractToggle and AutoInteractToggle.Value == true
end, AutoInteractToggle, Library and Library.Options and Library.Options.AutoInteractKeybind)

local AutoInteractIntervalSlider = AddResettableSlider(ExploitsGeneral, "AutoInteractInterval", {
    Text = "Interact Interval (ms)",
    Min = 0, Max = 500, Default = 150,
    Rounding = 0, Compact = true,
})

local AutoInteractState = {
    Enabled = false,
    LoopConn = nil,
    AddedConn = nil,
    LastFire = 0,
    PromptList = {},
    PromptCooldown = {},
	RecentlyOpened = {},
}

local AUTO_INTERACT_RADIUS = 15

local function AutoInteract_GetRadius()
    return AUTO_INTERACT_RADIUS
end

local function AutoInteract_GetInterval()
    local opt = Library and Library.Options and Library.Options.AutoInteractInterval
    if opt and typeof(opt.Value) == "number" then return opt.Value / 1000 end
    return 0.15
end

local function CollectParentNames(prompt)
    local names = {}
    local p = prompt.Parent
    for _ = 1, 8 do
        if not p then break end
        table.insert(names, string.lower(p.Name or ""))
        p = p.Parent
    end
    return names
end

local function ParentContains(parentNames, kw)
    for _, n in ipairs(parentNames) do
        if string.find(n, kw, 1, true) then return true end
    end
    return false
end

-- Проверка: контейнер реально открыт?
-- 1) Атрибут Open = true у самого контейнера (для Drawer'ов)
-- 2) Для LootLocker: внутри есть активный Door.ProximityPrompt (для закрытия)
local function IsContainerOpened(root)
    if not root then return false end
    
    -- Атрибут Open
    local ok, v = pcall(function() return root:GetAttribute("Open") end)
    if ok and v == true then return true end
    
    -- Для LootLocker проверяем наличие Door.ProximityPrompt
    local rootName = string.lower(root.Name or "")
    if string.find(rootName, "lootlocker", 1, true) then
        for _, d in ipairs(root:GetDescendants()) do
            if d:IsA("ProximityPrompt") and d.Enabled then
                local pn = string.lower(d.Parent and d.Parent.Name or "")
                if pn == "door" then
                    return true
                end
            end
        end
    end
    
    return false
end

local function GetPromptType(prompt)
    local name = string.lower(prompt.Name or "")
    local parentNames = CollectParentNames(prompt)

    -- HidingLocker — игнор
    if ParentContains(parentNames, "hidinglocker")
       or ParentContains(parentNames, "hidelocker")
       or ParentContains(parentNames, "hiding")
       or ParentContains(parentNames, "wardrobe")
       or ParentContains(parentNames, "closet")
       or ParentContains(parentNames, "vent")
       or ParentContains(parentNames, "dumpster") then
        return "hide"
    end

    -- Door внутри LootLocker — игнорируем (это промпт закрытия)
    local parentName = string.lower(prompt.Parent and prompt.Parent.Name or "")
    if parentName == "door" then
        local grandparent = prompt.Parent and prompt.Parent.Parent
        if grandparent and string.find(string.lower(grandparent.Name or ""), "lootlocker", 1, true) then
            return "close"
        end
    end

    -- LOOT
    if ParentContains(parentNames, "shard")
       or ParentContains(parentNames, "amethyst")
       or ParentContains(parentNames, "crystal")
       or ParentContains(parentNames, "emerald")
       or ParentContains(parentNames, "gem")
       or ParentContains(parentNames, "fragment")
       or ParentContains(parentNames, "piece")
       or ParentContains(parentNames, "dust")
       or ParentContains(parentNames, "deceiving")
       or ParentContains(parentNames, "artifact")
       or ParentContains(parentNames, "relic")
       or ParentContains(parentNames, "vitamin")
       or ParentContains(parentNames, "money")
       or ParentContains(parentNames, "cash")
       or ParentContains(parentNames, "coin")
       or ParentContains(parentNames, "gold")
       or ParentContains(parentNames, "stardust")
       or ParentContains(parentNames, "bandage")
       or ParentContains(parentNames, "bottle")
       or ParentContains(parentNames, "vial")
       or ParentContains(parentNames, "fuse")
       or ParentContains(parentNames, "battery")
       or ParentContains(parentNames, "keycard")
       or ParentContains(parentNames, "pickup")
       or ParentContains(parentNames, "dropitem")
       or ParentContains(parentNames, "lighter")
       or ParentContains(parentNames, "zippo")
       or ParentContains(parentNames, "match")
       or ParentContains(parentNames, "flame")
       or ParentContains(parentNames, "torch")
       or ParentContains(parentNames, "flashlight")
       or ParentContains(parentNames, "lamp") then
        return "loot"
    end

    -- OPEN
    if ParentContains(parentNames, "lootlocker")
       or ParentContains(parentNames, "drawer")
       or ParentContains(parentNames, "chest")
       or ParentContains(parentNames, "cabinet")
       or ParentContains(parentNames, "toolbox")
       or ParentContains(parentNames, "crate") then
        return "open"
    end

    if string.find(name, "draweropen", 1, true)
       or string.find(name, "open", 1, true) then
        return "open"
    end

    return "normal"
end

local function GetPriority(promptType)
    if promptType == "loot" then return 1 end
    if promptType == "open" then return 2 end
    if promptType == "hide" then return 999 end
    if promptType == "close" then return 999 end
    return 3
end

local function GetRootModel(prompt)
    local p = prompt.Parent
    if not p then return prompt end
    local current = p
    for _ = 1, 8 do
        if not current or not current.Parent then break end
        local n = string.lower(current.Name or "")
        if string.find(n, "drawer", 1, true)
           or string.find(n, "lootlocker", 1, true)
           or string.find(n, "chest", 1, true)
           or string.find(n, "cabinet", 1, true)
           or string.find(n, "toolbox", 1, true)
           or string.find(n, "crate", 1, true) then
            return current
        end
        if n == "furniture" or n == "currentrooms" or n == "assets" or tonumber(n) then
            break
        end
        current = current.Parent
    end
    return p
end

local function RegisterPrompt(obj)
    if not obj:IsA("ProximityPrompt") then return end
    for _, p in ipairs(AutoInteractState.PromptList) do
        if p == obj then return end
    end
    table.insert(AutoInteractState.PromptList, obj)
end

local function BuildPromptList()
    AutoInteractState.PromptList = {}
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("ProximityPrompt") then
            table.insert(AutoInteractState.PromptList, obj)
        end
    end
    print("[AutoInteract] Собрано prompts: " .. #AutoInteractState.PromptList)
end

local function AutoInteract_Enable()
    if AutoInteractState.Enabled then return end
    AutoInteractState.Enabled = true
    AutoInteractState.PromptCooldown = {}
    AutoInteractState.RecentlyOpened = {}

    BuildPromptList()

    if AutoInteractState.AddedConn then
        AutoInteractState.AddedConn:Disconnect()
    end
    AutoInteractState.AddedConn = workspace.DescendantAdded:Connect(function(obj)
        if AutoInteractState.Enabled and obj:IsA("ProximityPrompt") then
            RegisterPrompt(obj)
        end
    end)

    if AutoInteractState.LoopConn then
        AutoInteractState.LoopConn:Disconnect()
    end

    AutoInteractState.LoopConn = RunService.Heartbeat:Connect(function()
        if not AutoInteractState.Enabled then return end

        local now = tick()
        local interval = AutoInteract_GetInterval()
        if now - AutoInteractState.LastFire < interval then return end
        AutoInteractState.LastFire = now

        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local radius = AutoInteract_GetRadius()

        -- Собираем prompts в радиусе
        local inRange = {}
        local removeList = nil
        for i, obj in ipairs(AutoInteractState.PromptList) do
            if not obj or not obj.Parent then
                if not removeList then removeList = {} end
                table.insert(removeList, i)
                continue
            end
            if obj.Enabled then
                local cd = AutoInteractState.PromptCooldown[obj]
                if not cd or (now - cd) >= 1.5 then
                    local parent = obj.Parent
                    local ppos
                    if parent:IsA("BasePart") then ppos = parent.Position
                    elseif parent:IsA("Model") then
                        local pp = parent.PrimaryPart or parent:FindFirstChildWhichIsA("BasePart")
                        if pp then ppos = pp.Position end
                    end
                    if ppos then
                        local d = (hrp.Position - ppos).Magnitude
                        if d <= radius then
                            local pType = GetPromptType(obj)
                            local prio = GetPriority(pType)
                            if prio < 999 then
                                local root = GetRootModel(obj)
                                table.insert(inRange, {
                                    prompt = obj, dist = d, priority = prio,
                                    type = pType, root = root
                                })
                            end
                        end
                    end
                end
            end
        end

        if removeList then
            for i = #removeList, 1, -1 do
                table.remove(AutoInteractState.PromptList, removeList[i])
            end
        end

        if #inRange == 0 then return end

        -- Очистка RecentlyOpened: если прошло > 30 сек с момента открытия — сбрасываем
        for root, openedAt in pairs(AutoInteractState.RecentlyOpened) do
            if now - openedAt > 30 then
                AutoInteractState.RecentlyOpened[root] = nil
            end
        end

        -- Фильтр: контейнеры которые РЕАЛЬНО открыты или недавно открывались нами — не трогаем
        local openedRoots = {}
        for _, c in ipairs(inRange) do
            if c.root and not openedRoots[c.root] then
                -- Проверка 1: мы недавно открывали (защита от закрытия пока игра не обновила)
                local recentlyOpened = AutoInteractState.RecentlyOpened[c.root]
                if recentlyOpened and (now - recentlyOpened) < 30 then
                    openedRoots[c.root] = true
                -- Проверка 2: игра реально открыла контейнер
                elseif IsContainerOpened(c.root) then
                    openedRoots[c.root] = true
                end
            end
        end

        local candidates = {}
        for _, c in ipairs(inRange) do
            if c.type == "loot" then
                table.insert(candidates, c)
            elseif c.type == "open" then
                if not openedRoots[c.root] then
                    table.insert(candidates, c)
                end
            end
        end

        if #candidates == 0 then return end

        table.sort(candidates, function(a, b)
            if a.priority ~= b.priority then return a.priority < b.priority end
            return a.dist < b.dist
        end)

        local target = candidates[1]
        AutoInteractState.PromptCooldown[target.prompt] = now

        -- Запоминаем что мы открыли этот root — не трогаем 30 секунд
        if target.type == "open" and target.root then
            AutoInteractState.RecentlyOpened[target.root] = now
        end

        pcall(function() fireproximityprompt(target.prompt) end)
    end)

    print("[AutoInteract] === ON ===")
end

local function AutoInteract_Disable()
    if not AutoInteractState.Enabled then return end
    AutoInteractState.Enabled = false

    if AutoInteractState.LoopConn then
        AutoInteractState.LoopConn:Disconnect()
        AutoInteractState.LoopConn = nil
    end
    if AutoInteractState.AddedConn then
        AutoInteractState.AddedConn:Disconnect()
        AutoInteractState.AddedConn = nil
    end

    AutoInteractState.PromptList = {}
    AutoInteractState.RecentlyOpened = {}

    print("[AutoInteract] === OFF ===")
end

if AutoInteractToggle then
    AutoInteractToggle:OnChanged(function(Value)
        if Value then AutoInteract_Enable() else AutoInteract_Disable() end
    end)
end

RegisterCleanup("AutoInteract", function()
    pcall(AutoInteract_Disable)
    if Toggles and Toggles.AutoInteractToggle then
        SafeSetValue(Toggles.AutoInteractToggle, false)
    end
end)
end

-- ============================================================
-- FLY (game-версия) — точно по шаблону Noclip
-- ============================================================
local FlyGameState = { Active = false, Conn = nil }

local FlyGameToggle = ExploitsLeft:AddToggle("FlyGameToggle", {
    Text = "Fly",
    Default = false,
    Tooltip = "Позволяет летать."
})
FlyGameToggle = FlyGameToggle or (Toggles and Toggles.FlyGameToggle)

local FlyGameSpeedSlider = AddResettableSlider(ExploitsLeft, "FlyGameSpeed", {
    Text = "Fly Speed",
    Min = 5, Max = 200, Default = 40,
    Rounding = 0, Compact = true
})

-- KeyPicker ПЕРЕД OnChanged (как у Noclip)
if FlyGameToggle and FlyGameToggle.AddKeyPicker then
    FlyGameToggle:AddKeyPicker("FlyGameKeybind", {
        Default = "V",
        Mode = "Toggle",
        SyncToggleState = true,
        Text = "Fly",
        NoUI = false,
    })
end

-- RegisterKeyBind ПЕРЕД OnChanged (как у Noclip)
getgenv().RegisterKeyBind("FlyGame", "Fly", function()
    local kp = Library and Library.Options and Library.Options.FlyGameKeybind
    if kp then
        if kp.ValueString then return kp.ValueString end
        if kp.Value then return tostring(kp.Value) end
    end
    return "V"
end, function()
    return FlyGameToggle and FlyGameToggle.Value == true
end, FlyGameToggle)

local function GetFlyGameSpeed()
    if FlyGameSpeedSlider and FlyGameSpeedSlider.Value then
        return FlyGameSpeedSlider.Value
    end
    if SliderRefs and SliderRefs.FlyGameSpeed and SliderRefs.FlyGameSpeed.Value then
        return SliderRefs.FlyGameSpeed.Value
    end
    return 40
end

-- Чистим старый RenderStepped от прошлых инжектов
pcall(function()
    if getgenv().MyHub_FlyConn then
        getgenv().MyHub_FlyConn:Disconnect()
        getgenv().MyHub_FlyConn = nil
    end
end)

-- ОДИН ПОСТОЯННЫЙ RenderStepped — проверяет Value каждый кадр
-- Никаких OnChanged, никаких Create/Disconnect — от двойных срабатываний не зависит
getgenv().MyHub_FlyConn = RunService.RenderStepped:Connect(function()
    if not FlyGameToggle then return end
    local active = FlyGameToggle.Value

    -- Активный полёт
    if active then
        local c = LP.Character
        if not c then return end
        local hrp = c:FindFirstChild("HumanoidRootPart")
        local hum = c:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum then return end

        pcall(function() hrp:SetNetworkOwner(LP) end)
        if hum.WalkSpeed ~= 0 then hum.WalkSpeed = 0 end

        local bp = hrp:FindFirstChild("MyHub_FlyBP")
        if not bp then
            bp = Instance.new("BodyPosition")
            bp.Name = "MyHub_FlyBP"
            bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bp.P = 50000
            bp.D = 1000
            bp.Position = hrp.Position
            bp.Parent = hrp
        end

        local cam = workspace.CurrentCamera
        if not cam then return end

        local speed = GetFlyGameSpeed()
        local dir = Vector3.zero
        local look = cam.CFrame.LookVector

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + look end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - look end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end

        local lastTick = getgenv().MyHub_FlyLastTick or tick()
        local now = tick()
        local dt = now - lastTick
        if dt > 0.1 then dt = 0.1 end
        getgenv().MyHub_FlyLastTick = now

        local newPos = bp.Position
        if dir.Magnitude > 0 then
            newPos = newPos + dir.Unit * speed * dt
        end

        local noclipActive = Toggles and Toggles.NoclipToggleEx and Toggles.NoclipToggleEx.Value
        if not noclipActive then
            if newPos.Y < bp.Position.Y then
                if hum.FloorMaterial ~= Enum.Material.Air then
                    newPos = Vector3.new(newPos.X, bp.Position.Y, newPos.Z)
                end
            end
            if newPos.Y > bp.Position.Y then
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = { c }
                local upDist = newPos.Y - bp.Position.Y
                local hit = workspace:Raycast(bp.Position, Vector3.new(0, upDist + 3, 0), rp)
                if hit then
                    local maxY = hit.Position.Y - 3
                    if newPos.Y > maxY and maxY >= bp.Position.Y then
                        newPos = Vector3.new(newPos.X, maxY, newPos.Z)
                    end
                end
            end
            local horizDelta = Vector3.new(dir.X, 0, dir.Z)
            if horizDelta.Magnitude > 0.001 and dir.Magnitude > 0 then
                local rp = RaycastParams.new()
                rp.FilterType = Enum.RaycastFilterType.Exclude
                rp.FilterDescendantsInstances = { c }
                local moveHoriz = horizDelta.Unit * speed * dt
                local hit = workspace:Raycast(bp.Position, horizDelta.Unit * (moveHoriz.Magnitude + 2), rp)
                if hit then
                    local safeDist = math.max(0, hit.Distance - 2)
                    if safeDist < moveHoriz.Magnitude then
                        local allowedMove = horizDelta.Unit * safeDist
                        newPos = Vector3.new(
                            bp.Position.X + allowedMove.X,
                            newPos.Y,
                            bp.Position.Z + allowedMove.Z
                        )
                    end
                end
            end
        end

        bp.Position = newPos
    else
        -- Не активен — если BodyPosition остался, удаляем
        local c = LP.Character
        if c then
            local hrp = c:FindFirstChild("HumanoidRootPart")
            if hrp then
                local bp = hrp:FindFirstChild("MyHub_FlyBP")
                if bp then pcall(function() bp:Destroy() end) end
            end
            local hum = c:FindFirstChildOfClass("Humanoid")
            if hum and hum.WalkSpeed == 0 then
                pcall(function() hum.WalkSpeed = 16 end)
            end
        end
    end
end)

RegisterCleanup("FlyGame", function()
    if getgenv().MyHub_FlyConn then
        getgenv().MyHub_FlyConn:Disconnect()
        getgenv().MyHub_FlyConn = nil
    end
    if getgenv().MyHub_FlyLastTick then
        getgenv().MyHub_FlyLastTick = nil
    end
    local c = LP.Character
    if c then
        local hrp = c:FindFirstChild("HumanoidRootPart")
        if hrp then
            local bp = hrp:FindFirstChild("MyHub_FlyBP")
            if bp then pcall(function() bp:Destroy() end) end
        end
        local hum = c:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() hum.WalkSpeed = 16 end) end
    end
    if Toggles and Toggles.FlyGameToggle then
        SafeSetValue(Toggles.FlyGameToggle, false)
    end
end)

-- ============================================================
-- NOCLIP (главный, с биндом и логикой)
-- ============================================================
local NoclipConn = nil
local NoclipSavedCollide = {}   -- [part] = оригинальный CanCollide
local NoclipToggleEx = ExploitsLeft:AddToggle("NoclipToggleEx", {
    Text = "Noclip", Default = false,
    Tooltip = "Позволяет проходить сквозь стены."
})
NoclipToggleEx = NoclipToggleEx or Toggles.NoclipToggleEx

-- KeyPicker (только на этот — он главный)
if NoclipToggleEx and NoclipToggleEx.AddKeyPicker then
    NoclipToggleEx:AddKeyPicker("NoclipKeybind", {
        Default = "N",
        Mode = "Toggle",
        SyncToggleState = true,
        Text = "Noclip",
        NoUI = false,
    })
end

-- Регистрируем в KeyBindList
getgenv().RegisterKeyBind("Noclip", "Noclip", function()
    local kp = Library and Library.Options and Library.Options.NoclipKeybind
    if kp then
        if kp.ValueString then return kp.ValueString end
        if kp.Value then return tostring(kp.Value) end
    end
    return "N"
end, function()
    return NoclipToggleEx and NoclipToggleEx.Value == true
end, NoclipToggleEx, Library and Library.Options and Library.Options.NoclipKeybind)

-- Синхронизация между Lobby-тогглом и Exploits-тогглом
if NoclipToggleEx and NoclipToggle then
    NoclipToggleEx:OnChanged(function(v)
        if NoclipToggle.Value ~= v then NoclipToggle:SetValue(v) end
    end)
    NoclipToggle:OnChanged(function(v)
        if NoclipToggleEx.Value ~= v then NoclipToggleEx:SetValue(v) end
    end)
end

-- Основная логика (CanCollide) — только на Exploits-тоггле
if NoclipToggleEx then
    NoclipToggleEx:OnChanged(function(Value)
        if NoclipConn then NoclipConn:Disconnect() NoclipConn = nil end

        if not Value then
            -- Возвращаем ОРИГИНАЛЬНЫЕ CanCollide каждой части
            local char = LP.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") then
                        local orig = NoclipSavedCollide[part]
                        if orig ~= nil then
                            part.CanCollide = orig
                        end
                    end
                end
            end
            NoclipSavedCollide = {}
            return
        end

        -- Запоминаем оригинальные CanCollide ПЕРЕД тем как сделать false
        NoclipSavedCollide = {}
        local char = LP.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    NoclipSavedCollide[part] = part.CanCollide
                end
            end
        end

        NoclipConn = RunService.Stepped:Connect(function()
            local char = LP.Character
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    -- Запоминаем, если часть новая (аксессуар наделся, tool взялся)
                    if NoclipSavedCollide[part] == nil then
                        NoclipSavedCollide[part] = part.CanCollide
                    end
                    part.CanCollide = false
                end
            end
        end)
    end)
end

RegisterCleanup("Noclip", function()
    if NoclipConn then NoclipConn:Disconnect() NoclipConn = nil end
    local char = LP.Character
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                local orig = NoclipSavedCollide[part]
                if orig ~= nil then
                    part.CanCollide = orig
                else
                    -- Если оригинала нет — ставим true (дефолт для тела)
                    part.CanCollide = true
                end
            end
        end
    end
    NoclipSavedCollide = {}
    if Toggles.NoclipToggleEx then SafeSetValue(Toggles.NoclipToggleEx, false) end
    if Toggles.NoclipToggle then SafeSetValue(Toggles.NoclipToggle, false) end
end)

-- ============================================================
-- SPEED BOOST
-- ============================================================
-- База в игре = 15 (не 16)
local BASE_SPEED = 15
local SpeedBoostConn = nil        -- RenderStepped loop
local SpeedBoostPropConn = nil    -- WalkSpeed change listener

local SpeedBoostToggle = ExploitsLeft:AddToggle("SpeedBoostToggle", {
    Text = "Speed Boost", Default = false,
    Tooltip = "Увеличивает скорость передвижения."
})

if SpeedBoostToggle and SpeedBoostToggle.AddKeyPicker then
    SpeedBoostToggle:AddKeyPicker("SpeedBoostKeybind", {
        Default = "X",
        Mode = "Toggle",
        SyncToggleState = true,
        Text = "Speed Boost",
        NoUI = false,
    })
end

getgenv().RegisterKeyBind("SpeedBoost", "Speed Boost", function()
    local kp = Library and Library.Options and Library.Options.SpeedBoostKeybind
    if kp then
        if kp.ValueString then return kp.ValueString end
        if kp.Value then return tostring(kp.Value) end
    end
    return "X"
end, function()
    return SpeedBoostToggle and SpeedBoostToggle.Value == true
end, SpeedBoostToggle, Library and Library.Options and Library.Options.SpeedBoostKeybind)

SpeedBoostToggle = SpeedBoostToggle or (Toggles and Toggles.SpeedBoostToggle)

local SpeedBoostSlider = AddResettableSlider(ExploitsLeft, "SpeedBoostValue", {
    Text = "Speed Boost",
    Min = 0, Max = 100, Default = 0,
    Rounding = 0, Compact = true
})

-- ============================================================
-- REMOVE ACCELERATION (убирает скольжение при повороте)
-- ============================================================
local RemoveAccelToggle = ExploitsLeft:AddToggle("RemoveAccelToggle", {
    Text = "Remove Acceleration",
    Default = false,
    Tooltip = "Убирает скольжение при резком повороте камеры на скорости."
})
RemoveAccelToggle = RemoveAccelToggle or (Toggles and Toggles.RemoveAccelToggle)

local RemoveAccelState = {
    Enabled = false,
    Conn = nil,
}

local function RemoveAccel_Tick()
    if not RemoveAccelState.Enabled then return end

    local char = LP and LP.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum then return end

    local moveDir = hum.MoveDirection
    -- Игрок не жмёт WASD — не трогаем velocity
    if moveDir.Magnitude < 0.01 then return end

    local vel = hrp.AssemblyLinearVelocity
    local horizSpeed = math.sqrt(vel.X * vel.X + vel.Z * vel.Z)
    if horizSpeed < 0.1 then return end

    -- Направление = MoveDirection, длина = текущая скорость
    -- Y оставляем как есть (прыжки/падение не ломаем)
    local dir = moveDir.Unit
    hrp.AssemblyLinearVelocity = Vector3.new(
        dir.X * horizSpeed,
        vel.Y,
        dir.Z * horizSpeed
    )
end

local function RemoveAccel_Enable()
    if RemoveAccelState.Enabled then return end
    RemoveAccelState.Enabled = true
    if RemoveAccelState.Conn then RemoveAccelState.Conn:Disconnect() end
    RemoveAccelState.Conn = RunService.Heartbeat:Connect(RemoveAccel_Tick)
    print("[RemoveAccel] === ON ===")
end

local function RemoveAccel_Disable()
    if not RemoveAccelState.Enabled then return end
    RemoveAccelState.Enabled = false
    if RemoveAccelState.Conn then
        RemoveAccelState.Conn:Disconnect()
        RemoveAccelState.Conn = nil
    end
    print("[RemoveAccel] === OFF ===")
end

if RemoveAccelToggle then
    RemoveAccelToggle:OnChanged(function(Value)
        if Value then RemoveAccel_Enable() else RemoveAccel_Disable() end
    end)
end

RegisterCleanup("RemoveAccel", function()
    pcall(RemoveAccel_Disable)
    if Toggles and Toggles.RemoveAccelToggle then
        SafeSetValue(Toggles.RemoveAccelToggle, false)
    end
end)

local function GetSpeedBoostValue()
    local v = nil
    if SpeedBoostSlider and SpeedBoostSlider.Value then
        v = SpeedBoostSlider.Value
    elseif SliderRefs and SliderRefs.SpeedBoostValue and SliderRefs.SpeedBoostValue.Value then
        v = SliderRefs.SpeedBoostValue.Value
    elseif Library and Library.Options and Library.Options.SpeedBoostValue then
        local opt = Library.Options.SpeedBoostValue.Value
        if typeof(opt) == "number" then v = opt end
    end
    if not v or v < 0 then v = 0 end
    -- Возвращаем ДОБАВКУ к базовой скорости (0 = базовая, 100 = +100)
    return v
end

local function ForceSpeed()
    if not SpeedBoostToggle or not SpeedBoostToggle.Value then return end
    local char = LP and LP.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- Слайдер = добавка к базовой (0 = базовая, 100 = +100)
    local bonus = GetSpeedBoostValue()
    local target = BASE_SPEED + bonus

    if math.abs(hum.WalkSpeed - target) > 0.01 then
        hum.WalkSpeed = target
    end
end

local function AttachSpeedHooks()
    local char = LP and LP.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    -- 1) Ловим любую запись WalkSpeed и сразу перебиваем
    if SpeedBoostPropConn then SpeedBoostPropConn:Disconnect() end
    SpeedBoostPropConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if not SpeedBoostToggle or not SpeedBoostToggle.Value then return end
        local bonus = GetSpeedBoostValue()
        local target = BASE_SPEED + bonus
        if math.abs(hum.WalkSpeed - target) > 0.01 then
            hum.WalkSpeed = target
        end
    end)
end

if SpeedBoostToggle then
    SpeedBoostToggle:OnChanged(function(Value)
        -- Чистим прошлые соединения
        if SpeedBoostConn then SpeedBoostConn:Disconnect() SpeedBoostConn = nil end
        if SpeedBoostPropConn then SpeedBoostPropConn:Disconnect() SpeedBoostPropConn = nil end

        if Value then
            -- 2) Луп на RenderStepped — срабатывает после физики и после Heartbeat
            SpeedBoostConn = RunService.RenderStepped:Connect(ForceSpeed)

            -- Цепляем хуки на текущего персонажа
            if LP.Character then
                AttachSpeedHooks()
            end

            -- Следим за респавном
            LP.CharacterAdded:Connect(function(newChar)
                task.wait(1)
                if SpeedBoostToggle.Value then
                    AttachSpeedHooks()
                end
            end)
        else
            local char = LP and LP.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then hum.WalkSpeed = BASE_SPEED end
            end
        end
    end)
end

RegisterCleanup("SpeedBoost", function()
    if SpeedBoostConn then SpeedBoostConn:Disconnect() SpeedBoostConn = nil end
    if SpeedBoostPropConn then SpeedBoostPropConn:Disconnect() SpeedBoostPropConn = nil end
    local char = LP and LP.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then hum.WalkSpeed = BASE_SPEED end
    end
    if Toggles and Toggles.SpeedBoostToggle then
        SafeSetValue(Toggles.SpeedBoostToggle, false)
    end
end)

-- ============================================================
-- ALLOW JUMP
-- ============================================================
local AllowJumpState = {
    Enabled = false,
    Conn = nil,
    CharConn = nil,
    Saved = {},   -- [char] = { CanJump = ..., JumpPower = ..., JumpHeight = ..., states = {...} }
}

local function SaveCharState(char)
    if AllowJumpState.Saved[char] then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    AllowJumpState.Saved[char] = {
        CanJump = char:GetAttribute("CanJump"),
        JumpPower = hum.JumpPower,
        JumpHeight = hum.JumpHeight,
        UseJumpPower = hum.UseJumpPower,
        States = {
            Jumping   = hum:GetStateEnabled(Enum.HumanoidStateType.Jumping),
            Freefall  = hum:GetStateEnabled(Enum.HumanoidStateType.Freefall),
            Landed    = hum:GetStateEnabled(Enum.HumanoidStateType.Landed),
        },
    }
end

local function RestoreCharState(char)
    local saved = AllowJumpState.Saved[char]
    if not saved then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    pcall(function() char:SetAttribute("CanJump", saved.CanJump) end)
    pcall(function() hum.JumpPower = saved.JumpPower end)
    pcall(function() hum.JumpHeight = saved.JumpHeight end)
    pcall(function() hum.UseJumpPower = saved.UseJumpPower end)
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping,  saved.States.Jumping) end)
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, saved.States.Freefall) end)
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Landed,   saved.States.Landed) end)

    AllowJumpState.Saved[char] = nil
end

local function ForceJumpAbility(char)
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    if char:GetAttribute("CanJump") ~= true then
        char:SetAttribute("CanJump", true)
    end
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true) end)
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Freefall, true) end)
    pcall(function() hum:SetStateEnabled(Enum.HumanoidStateType.Landed, true) end)

    if hum.UseJumpPower then
        if hum.JumpPower <= 0 then hum.JumpPower = 50 end
    else
        if hum.JumpHeight <= 0 then hum.JumpHeight = 7.2 end
    end
end

local function StartAllowJump()
    if AllowJumpState.Conn then return end

    -- Сохраняем оригиналы ОДИН РАЗ
    if LP.Character then SaveCharState(LP.Character) end

    AllowJumpState.Conn = RunService.Heartbeat:Connect(function()
        if not AllowJumpState.Enabled then return end
        local char = LP and LP.Character
        if not char then return end
        SaveCharState(char)
        ForceJumpAbility(char)
    end)

    if LP.Character then
        ForceJumpAbility(LP.Character)
    end

    AllowJumpState.CharConn2 = LP.CharacterAdded:Connect(function(newChar)
        task.wait(0.5)
        if AllowJumpState.Enabled then
            SaveCharState(newChar)
            ForceJumpAbility(newChar)
        end
    end)
end

local function StopAllowJump()
    if AllowJumpState.Conn then
        AllowJumpState.Conn:Disconnect()
        AllowJumpState.Conn = nil
    end
    if AllowJumpState.CharConn2 then
        AllowJumpState.CharConn2:Disconnect()
        AllowJumpState.CharConn2 = nil
    end
    -- Возвращаем состояние всем сохранённым персонажам
    for char in pairs(AllowJumpState.Saved) do
        if char and char.Parent then
            RestoreCharState(char)
        end
    end
    AllowJumpState.Saved = {}
end

local AllowJumpToggle = ExploitsLeft:AddToggle("AllowJumpToggle", {
    Text = "Allow Jump",
    Default = false,
    Tooltip = "Позволяет игроку прыгать."
})
AllowJumpToggle = AllowJumpToggle or (Toggles and Toggles.AllowJumpToggle)

if AllowJumpToggle then
    AllowJumpToggle:OnChanged(function(Value)
        AllowJumpState.Enabled = Value
        if Value then StartAllowJump() else StopAllowJump() end
    end)
end

RegisterCleanup("AllowJump", function()
    StopAllowJump()
    AllowJumpState.Enabled = false
    if Toggles and Toggles.AllowJumpToggle then
        SafeSetValue(Toggles.AllowJumpToggle, false)
    end
end)

-- ============================================================
-- INFINITY JUMP — бесконечные прыжки БЕЗ усиления
-- ============================================================
local InfJumpState = { Enabled = false, Conn = nil }

local InfJumpToggle = ExploitsLeft:AddToggle("InfinityJumpToggle", {
    Text = "Infinity Jump",
    Default = false,
    Tooltip = "Бесконечные прыжки в воздухе."
})
InfJumpToggle = InfJumpToggle or (Toggles and Toggles.InfinityJumpToggle)

local function StartInfJump()
    if InfJumpState.Conn then return end
    InfJumpState.Conn = RunService.Heartbeat:Connect(function()
        if not InfJumpState.Enabled then return end
        -- Только если Allow Jump включён
        if not AllowJumpToggle or not AllowJumpToggle.Value then return end
        if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then return end

        local char = LP.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not hum then return end

        -- Просто разрешаем прыжок в воздухе — БЕЗ изменения скорости/силы
        pcall(function()
            hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end)
    end)
end

local function StopInfJump()
    if InfJumpState.Conn then InfJumpState.Conn:Disconnect() InfJumpState.Conn = nil end
end

if InfJumpToggle then
    InfJumpToggle:OnChanged(function(Value)
        InfJumpState.Enabled = Value
        if Value then StartInfJump() else StopInfJump() end
    end)
end

RegisterCleanup("InfinityJump", function()
    StopInfJump()
    InfJumpState.Enabled = false
    if Toggles and Toggles.InfinityJumpToggle then
        SafeSetValue(Toggles.InfinityJumpToggle, false)
    end
end)

-- ============================================================
-- RESET CHARACTER
-- ============================================================
ExploitsLeft:AddButton({
    Text = "Reset Character",
    DoubleClick = false,
    Tooltip = "Мгновенно убивает персонажа.",
    Func = function()
        local char = LP and LP.Character
        if not char then return end

        -- Способ 1: Humanoid.Health = 0 (основной)
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.Health = 0
        end

        -- Способ 2: BreakJoints (если первый не сработал)
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp and hum and hum.Health > 0 then
            char:BreakJoints()
        end

        -- Способ 3: сброс через урон
        if hum and hum.Health > 0 then
            pcall(function()
                local dmg = char:FindFirstChildOfClass("Humanoid")
                dmg:TakeDamage(99999)
            end)
        end

        Library:Notify("Character reset", 2)
    end
})

-- ============================================================
-- BYPASS GLARE (kill spawn)
-- ============================================================
local BypassGlareToggle = ExploitsRight:AddToggle("BypassGlareToggle", {
    Text = "Bypass Glare", Default = false,
    Tooltip = "Предотвращает появление Глейра"
})
BypassGlareToggle = BypassGlareToggle or Toggles.BypassGlareToggle

local BypassGlareState = {
    Enabled = false,
    Connections = {},
    LoopConn = nil,
    SlowConn = nil,     -- ← новый
    Hooked = false,
}

-- ═══════════════════════════════════════════════════════
-- 1. ХУК __namecall — блокируем FireServer на GlareEvent
-- ═══════════════════════════════════════════════════════
if not BypassGlareState.Hooked then
    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
mt.__namecall = newcclosure(function(self, ...)
    -- Быстрая проверка: Enabled + Instance
    if BypassGlareState.Enabled and typeof(self) == "Instance" then
        -- Сначала читаем имя (кэшируется в C)
        local selfName = self.Name
        -- Проверяем имя ДО вызова getnamecallmethod (дорогая операция)
        if selfName == "Glare" or selfName == "GlareDmg" or selfName == "GlareServer" then
            local method = getnamecallmethod()
            if method == "FireServer" or method == "InvokeServer" or method == "Fire" then
                return
            end
        else
            local method = getnamecallmethod()
            if method == "Shake" or method == "ShakeOnce"
               or method == "ShakeSustain" or method == "ShakeOnceClient" then
                return
            end
        end
    end
    return oldNamecall(self, ...)
end)
    setreadonly(mt, true)
    BypassGlareState.Hooked = true
end

-- ═══════════════════════════════════════════════════════
-- 2. Уничтожаем Glare entity когда появляется
-- ═══════════════════════════════════════════════════════
local function BG_StartKillLoop()
    if BypassGlareState.LoopConn then
        BypassGlareState.LoopConn:Disconnect()
    end

    -- БЫСТРЫЙ ЛУП: только удаление Glare-модели (простой FindFirstChild)
    BypassGlareState.LoopConn = RunService.Heartbeat:Connect(function()
        if not BypassGlareState.Enabled then return end
        local ents = workspace:FindFirstChild("Entities")
        if not ents then return end

        local glare = ents:FindFirstChild("Glare")
        if glare then
            pcall(function() glare:Destroy() end)
        end
    end)

    -- МЕДЛЕННЫЙ ЛУП: раз в 2 секунды чистим connections у GlareDmg
    if BypassGlareState.SlowConn then
        BypassGlareState.SlowConn:Disconnect()
    end
    BypassGlareState.SlowConn = task.spawn(function()
        while BypassGlareState.Enabled do
            task.wait(2)  -- раз в 2 секунды вместо каждого кадра
            if not BypassGlareState.Enabled then break end

            local RS = game:GetService("ReplicatedStorage")
            local assets = RS:FindFirstChild("Assets")
            local events = assets and assets:FindFirstChild("Events")
            local entities = events and events:FindFirstChild("Entities")
            if entities then
                local gd = entities:FindFirstChild("GlareDmg")
                if gd and gd:IsA("RemoteEvent") then
                    local ok, conns = pcall(getconnections, gd.OnClientEvent)
                    if ok and conns then
                        for _, c in ipairs(conns) do
                            pcall(function() c:Disconnect() end)
                        end
                    end
                end
            end
        end
    end)
end

local function BG_StopKillLoop()
    if BypassGlareState.LoopConn then
        BypassGlareState.LoopConn:Disconnect()
        BypassGlareState.LoopConn = nil
    end
    if BypassGlareState.SlowConn then
        task.cancel(BypassGlareState.SlowConn)
        BypassGlareState.SlowConn = nil
    end
end

-- ═══════════════════════════════════════════════════════
-- 3. Слушаем спавн Glare (ChildAdded)
-- ═══════════════════════════════════════════════════════
local function BG_StartSpawnWatcher()
    local ents = workspace:FindFirstChild("Entities")
    if not ents then return end

    local conn = ents.ChildAdded:Connect(function(obj)
        if not BypassGlareState.Enabled then return end
        if obj.Name == "Glare" then
            task.wait(0.05)
            pcall(function() obj:Destroy() end)
            print("[BypassGlare] Destroyed spawned Glare")
        end
    end)
    table.insert(BypassGlareState.Connections, conn)
end

-- ═══════════════════════════════════════════════════════
-- 4. ENABLE / DISABLE
-- ═══════════════════════════════════════════════════════
local function BypassGlare_Enable()
    if BypassGlareState.Enabled then return end
    BypassGlareState.Enabled = true

    BG_StartSpawnWatcher()
    BG_StartKillLoop()

    print("[BypassGlare] === ON ===")
end

local function BypassGlare_Disable()
    if not BypassGlareState.Enabled then return end
    BypassGlareState.Enabled = false

    BG_StopKillLoop()

    for _, c in ipairs(BypassGlareState.Connections) do
        pcall(function() c:Disconnect() end)
    end
    BypassGlareState.Connections = {}

    print("[BypassGlare] === OFF ===")
end

if BypassGlareToggle then
    BypassGlareToggle:OnChanged(function(Value)
        if Value then BypassGlare_Enable() else BypassGlare_Disable() end
    end)
end

RegisterCleanup("BypassGlare", function()
    pcall(BypassGlare_Disable)
    if Toggles and Toggles.BypassGlareToggle then
        SafeSetValue(Toggles.BypassGlareToggle, false)
    end
end)

-- ============================================================
-- BYPASS GLITCH (rename all)
-- ============================================================
local BypassGlitchToggle = ExploitsRight:AddToggle("BypassGlitchToggle", {
    Text = "Bypass Glitch", Default = false,
    Tooltip = "Предотвращает появление Глитча."
})
BypassGlitchToggle = BypassGlitchToggle or Toggles.BypassGlitchToggle

local BypassGlitchState = {
    Enabled = false,
    Renamed = {},
    DisabledScripts = {},
}

local function BypassGlitch_Enable()
    if BypassGlitchState.Enabled then return end
    BypassGlitchState.Enabled = true
    BypassGlitchState.Renamed = {}

    local RS = game:GetService("ReplicatedStorage")
    local assets = RS:FindFirstChild("Assets")
    local events = assets and assets:FindFirstChild("Events")

    -- 1. Bindables.Glitch (BindableEvent)
    if events then
        local bindables = events:FindFirstChild("Bindables")
        if bindables then
            local g = bindables:FindFirstChild("Glitch")
            if g and g:IsA("BindableEvent") then
                BypassGlitchState.Renamed[g] = g.Name
                g.Name = "Glitch_MyHubDisabled"
                print("[BypassGlitch] Renamed Bindables.Glitch")
            end
        end

        -- 2. RemoteServer.GlitchServer (RemoteEvent)
        local rsrv = events:FindFirstChild("RemoteServer")
        if rsrv then
            local gs = rsrv:FindFirstChild("GlitchServer")
            if gs and gs:IsA("RemoteEvent") then
                BypassGlitchState.Renamed[gs] = gs.Name
                gs.Name = "GlitchServer_MyHubDisabled"
                print("[BypassGlitch] Renamed GlitchServer")
            end
        end

        -- 3. Entities.GlareDmg — это Glare, не Glitch, но пусть будет
    end

    -- 5. Kill все Glitch-related LocalScripts
    BypassGlitchState.DisabledScripts = {}
    local LP = game.Players.LocalPlayer
    local pg = LP:FindFirstChild("PlayerGui")
    if pg then
        for _, obj in ipairs(pg:GetDescendants()) do
            if obj:IsA("LocalScript") and not obj.Disabled then
                local n = string.lower(obj.Name)
                if string.find(n, "glitch") then
                    obj.Disabled = true
                    table.insert(BypassGlitchState.DisabledScripts, obj)
                    print("[BypassGlitch] Disabled: " .. obj:GetFullName())
                end
            end
        end
    end

    print("[BypassGlitch] === ON ===")
end

local function BypassGlitch_Disable()
    if not BypassGlitchState.Enabled then return end
    BypassGlitchState.Enabled = false

    -- Возвращаем имена RemoteEvent/BindableEvent
    for obj, origName in pairs(BypassGlitchState.Renamed) do
        if obj and obj.Parent then
            obj.Name = origName
        end
    end
    BypassGlitchState.Renamed = {}

    -- Возвращаем LocalScripts
    for _, obj in ipairs(BypassGlitchState.DisabledScripts) do
        if obj and obj.Parent then
            obj.Disabled = false
            print("[BypassGlitch] Re-enabled: " .. obj:GetFullName())
        end
    end
    BypassGlitchState.DisabledScripts = {}

    print("[BypassGlitch] === OFF ===")
end

if BypassGlitchToggle then
    BypassGlitchToggle:OnChanged(function(Value)
        if Value then BypassGlitch_Enable() else BypassGlitch_Disable() end
    end)
end

RegisterCleanup("BypassGlitch", function()
    pcall(BypassGlitch_Disable)
    if Toggles and Toggles.BypassGlitchToggle then
        SafeSetValue(Toggles.BypassGlitchToggle, false)
    end
end)

-- ============================================================
-- BYPASS SHADE (barrier)
-- ============================================================
do
local BypassShadeToggle = ExploitsRight:AddToggle("BypassShadeToggle", {
    Text = "Bypass Shade", Default = false,
    Tooltip = "Предотвращает столкновние с Шейдом."
})
BypassShadeToggle = BypassShadeToggle or Toggles.BypassShadeToggle

-- ═══════════════════════════════════════════════
-- НАСТРОЙКА: Радиус барьера вокруг Shade
local BARRIER_RADIUS = 6
-- ═══════════════════════════════════════════════

local BypassShadeState = {
    Enabled = false,
    Barriers = {},
    LoopConn = nil,
}

local function BypassShade_CreateBarrier(shade)
    local pp = shade.PrimaryPart
    if not pp then
        for _, p in ipairs(shade:GetDescendants()) do
            if p:IsA("BasePart") then pp = p break end
        end
    end
    if not pp then return nil end

    local barrier = Instance.new("Part")
    barrier.Name = "MyHub_ShadeBarrier"
    barrier.Anchored = true
    barrier.CanCollide = true
    barrier.CanQuery = true
    barrier.CanTouch = true
    barrier.CastShadow = false
    barrier.Transparency = 1
    barrier.Size = Vector3.new(BARRIER_RADIUS * 2, 20, BARRIER_RADIUS * 2)
    barrier.CFrame = CFrame.new(pp.Position)
    barrier.Parent = workspace

    return barrier
end

local function BypassShade_StartLoop()
    if BypassShadeState.LoopConn then
        BypassShadeState.LoopConn:Disconnect()
    end

    BypassShadeState.LoopConn = RunService.Heartbeat:Connect(function()
        if not BypassShadeState.Enabled then return end

        local rooms = workspace:FindFirstChild("CurrentRooms")
        if not rooms then return end

        -- Собираем активные Shade
        local activeShades = {}
        for _, room in ipairs(rooms:GetChildren()) do
            if tonumber(room.Name) then
                local shade = room:FindFirstChild("Shade")
                if shade and shade:IsA("Model") then
                    activeShades[shade] = true
                end
            end
        end

        -- Удаляем барьеры для удалённых Shade
        local newBarriers = {}
        for _, entry in ipairs(BypassShadeState.Barriers) do
            if entry.shade and entry.shade.Parent and activeShades[entry.shade] then
                table.insert(newBarriers, entry)
            else
                pcall(function() entry.part:Destroy() end)
            end
        end
        BypassShadeState.Barriers = newBarriers

        -- Создаём барьеры для новых Shade
        for shade in pairs(activeShades) do
            local has = false
            for _, entry in ipairs(BypassShadeState.Barriers) do
                if entry.shade == shade then has = true break end
            end
            if not has then
                local barrier = BypassShade_CreateBarrier(shade)
                if barrier then
                    table.insert(BypassShadeState.Barriers, { part = barrier, shade = shade })
                    print("[BypassShade] Барьер создан для " .. shade:GetFullName())
                end
            end
        end
    end)
end

local function BypassShade_StopLoop()
    if BypassShadeState.LoopConn then
        BypassShadeState.LoopConn:Disconnect()
        BypassShadeState.LoopConn = nil
    end
    -- Удаляем все барьеры
    for _, entry in ipairs(BypassShadeState.Barriers) do
        pcall(function() entry.part:Destroy() end)
    end
    BypassShadeState.Barriers = {}
end

local function BypassShade_Enable()
    if BypassShadeState.Enabled then return end
    BypassShadeState.Enabled = true
    BypassShade_StartLoop()
    print("[BypassShade] === ON ===")
end

local function BypassShade_Disable()
    if not BypassShadeState.Enabled then return end
    BypassShadeState.Enabled = false
    BypassShade_StopLoop()
    print("[BypassShade] === OFF ===")
end

if BypassShadeToggle then
    BypassShadeToggle:OnChanged(function(Value)
        if Value then BypassShade_Enable() else BypassShade_Disable() end
    end)
end

RegisterCleanup("BypassShade", function()
    pcall(BypassShade_Disable)
    if Toggles and Toggles.BypassShadeToggle then
        SafeSetValue(Toggles.BypassShadeToggle, false)
    end
end)
end

-- ============================================================
-- BYPASS A-90 (events + scripts + modules)
-- ============================================================
do
local BypassA90Toggle = ExploitsRight:AddToggle("BypassA90Toggle", {
    Text = "Bypass TA-90",
    Default = false,
    Tooltip = "Предотвращает появление TA-90"
})
BypassA90Toggle = BypassA90Toggle or Toggles.BypassA90Toggle

local BypassA90State = {
    Enabled = false,
    DisabledScripts = {},
    DisabledModules = {},
    KillLoop = nil,
    RescanConn = nil,
    Hooked = false,
}

-- ═══════════════════════════════════════════════════════
-- 1. ХУК __namecall — блокируем ВСЕ A-90 события
-- ═══════════════════════════════════════════════════════
if not BypassA90State.Hooked then
    local mt = getrawmetatable(game)
    local oldNamecall = mt.__namecall
    setreadonly(mt, false)
    mt.__namecall = newcclosure(function(self, ...)
        if BypassA90State.Enabled and typeof(self) == "Instance" then
            local method = getnamecallmethod()
            local nl = string.lower(self.Name or "")
            if string.find(nl, "a90", 1, true)
               or string.find(nl, "a-90", 1, true)
               or string.find(nl, "ransom", 1, true) then
                if method == "Fire" or method == "FireServer"
                   or method == "InvokeServer" or method == "Invoke" then
                    print("[BypassA90] Blocked " .. self.Name .. ":" .. method)
                    return
                end
            end
        end
        return oldNamecall(self, ...)
    end)
    setreadonly(mt, true)
    BypassA90State.Hooked = true
end

-- ═══════════════════════════════════════════════════════
-- 2. Собираем все A-90 объекты в PlayerGui
-- ═══════════════════════════════════════════════════════
local function BypassA90_FindAll()
    local scripts = {}   -- ТОЛЬКО LocalScripts
    local assets = {}    -- эффекты
    local LP = game.Players.LocalPlayer
    local pg = LP:FindFirstChild("PlayerGui")
    if not pg then return scripts, assets end

    local lab = pg:FindFirstChild("Initiate")
        and pg.Initiate:FindFirstChild("Library")
        and pg.Initiate.Library:FindFirstChild("Entities")
        and pg.Initiate.Library.Entities:FindFirstChild("Lab")
    if not lab then return scripts, assets end

    for _, name in ipairs({"A90", "A90B"}) do
        local root = lab:FindFirstChild(name)
        if root then
            -- Только LocalScript — у него есть Disabled
            if root:IsA("LocalScript") then
                table.insert(scripts, root)
            end
            -- Все эффекты внутри (включая ModuleScript-контейнеры)
            for _, d in ipairs(root:GetDescendants()) do
                if d:IsA("ColorCorrectionEffect")
                   or d:IsA("BlurEffect")
                   or d:IsA("Sound") then
                    table.insert(assets, d)
                end
            end
        end
    end

    return scripts, assets
end

-- ═══════════════════════════════════════════════════════
-- 3. Kill-loop — глушим эффекты A-90 каждый кадр
-- ═══════════════════════════════════════════════════════
local function BypassA90_KillLoop_Start()
    if BypassA90State.KillLoop then
        BypassA90State.KillLoop:Disconnect()
    end
    BypassA90State.KillLoop = RunService.Heartbeat:Connect(function()
        if not BypassA90State.Enabled then return end

        local LP = game.Players.LocalPlayer
        local pg = LP:FindFirstChild("PlayerGui")
        if not pg then return end

        local lab = pg:FindFirstChild("Initiate")
            and pg.Initiate:FindFirstChild("Library")
            and pg.Initiate.Library:FindFirstChild("Entities")
            and pg.Initiate.Library.Entities:FindFirstChild("Lab")
        if not lab then return end

        for _, name in ipairs({"A90", "A90B"}) do
            local root = lab:FindFirstChild(name)
            if root then
                -- Держим LocalScript выключенным
                if root:IsA("LocalScript") and not root.Disabled then
                    root.Disabled = true
                end
                -- Глушим эффекты (не трогаем ModuleScript!)
                for _, d in ipairs(root:GetDescendants()) do
                    if d:IsA("ColorCorrectionEffect") then
                        if d.Enabled then d.Enabled = false end
                    elseif d:IsA("BlurEffect") then
                        if d.Enabled then d.Enabled = false end
                        if d.Size > 0 then d.Size = 0 end
                    elseif d:IsA("Sound") then
                        if d.Playing then pcall(function() d:Stop() end) end
                        if d.Volume > 0 then d.Volume = 0 end
                    end
                end
            end
        end

        -- Убиваем UI A-90
        for _, obj in ipairs(pg:GetChildren()) do
            local n = string.lower(obj.Name)
            if n == "a90" or n == "a-90" or n == "a90b"
               or n == "ransomui" or n == "stopsignui" then
                pcall(function() obj:Destroy() end)
            end
        end
    end)
end

local function BypassA90_KillLoop_Stop()
    if BypassA90State.KillLoop then
        BypassA90State.KillLoop:Disconnect()
        BypassA90State.KillLoop = nil
    end
end

-- ═══════════════════════════════════════════════════════
-- 4. ENABLE / DISABLE
-- ═══════════════════════════════════════════════════════
local function BypassA90_Enable()
    if BypassA90State.Enabled then return end
    BypassA90State.Enabled = true
    BypassA90State.DisabledScripts = {}

    local scripts, assets = BypassA90_FindAll()
    for _, s in ipairs(scripts) do
        if s:IsA("LocalScript") and not s.Disabled then
            s.Disabled = true
            table.insert(BypassA90State.DisabledScripts, s)
        end
    end
    for _, a in ipairs(assets) do
        if a:IsA("ColorCorrectionEffect") then a.Enabled = false
        elseif a:IsA("BlurEffect") then a.Enabled = false a.Size = 0
        elseif a:IsA("Sound") then pcall(function() a:Stop() end) a.Volume = 0 end
    end

    BypassA90_KillLoop_Start()

    if BypassA90State.RescanConn then
        task.cancel(BypassA90State.RescanConn)
    end
    BypassA90State.RescanConn = task.spawn(function()
        while BypassA90State.Enabled do
            task.wait(1)
            local s2 = BypassA90_FindAll()
            for _, s in ipairs(s2) do
                if s:IsA("LocalScript") and not s.Disabled then
                    s.Disabled = true
                    table.insert(BypassA90State.DisabledScripts, s)
                end
            end
        end
    end)

    print("[BypassA90] === ON | scripts: " .. #BypassA90State.DisabledScripts .. " ===")
end

local function BypassA90_Disable()
    if not BypassA90State.Enabled then return end
    BypassA90State.Enabled = false

    BypassA90_KillLoop_Stop()

    if BypassA90State.RescanConn then
        task.cancel(BypassA90State.RescanConn)
        BypassA90State.RescanConn = nil
    end

    -- Возвращаем LocalScripts
    for _, s in ipairs(BypassA90State.DisabledScripts) do
        if s and s.Parent then
            pcall(function() s.Disabled = false end)
        end
    end
    BypassA90State.DisabledScripts = {}

    print("[BypassA90] === OFF ===")
end

if BypassA90Toggle then
    BypassA90Toggle:OnChanged(function(Value)
        if Value then BypassA90_Enable() else BypassA90_Disable() end
    end)
end

RegisterCleanup("BypassA90", function()
    pcall(BypassA90_Disable)
    if Toggles and Toggles.BypassA90Toggle then
        SafeSetValue(Toggles.BypassA90Toggle, false)
    end
end)
end
end


-- ==== Visuals Tab ====
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

do
local ESPFolder = Instance.new("Folder")
ESPFolder.Name = "MyHub_ESP"
ESPFolder.Parent = game:GetService("CoreGui")

-- ============================================================
-- СКРЫТИЕ ESP-БИЛБОРДОВ ПРИ FREECAM (отдельный цикл)
-- ============================================================
task.spawn(function()
    while true do
        task.wait(0.1)
        local hidden = getgenv().FreeCamActive == true

        -- Обычные ESP (шкафы, кейкарды, леверы)
        for _, obj in ipairs(ESPFolder:GetChildren()) do
            if obj:IsA("BillboardGui") then
                obj.Enabled = not hidden
            end
        end

        -- Двери
        if getgenv().DoorESPState and getgenv().DoorESPState.Objects then
            for _, data in pairs(getgenv().DoorESPState.Objects) do
                if data.Billboard then
                    data.Billboard.Enabled = not hidden
                end
            end
        end

        -- Сущности (на всякий случай)
        if getgenv().EntityESPState and getgenv().EntityESPState.Objects then
            for _, data in pairs(getgenv().EntityESPState.Objects) do
                if data.Billboard then
                    data.Billboard.Enabled = not hidden
                end
                if data.BillboardText then
                    data.BillboardText.Enabled = not hidden
                end
            end
        end
    end
end)
-- ============================================================
-- FOV COMPENSATION for ESP text
-- ============================================================
-- Базовый FOV, при котором всё выглядит правильно
local ESP_DEFAULT_FOV = 70

-- Множитель для ОФФСЕТА (чтобы текст не отдалялся — умеренно)
local function GetFOVOffsetMultiplier()
    local cam = workspace.CurrentCamera
    if not cam then return 1 end
    local fov = cam.FieldOfView
    if fov <= 0 then return 1 end
    return math.clamp(ESP_DEFAULT_FOV / fov, 0.6, 1)
end

-- Множитель для РАЗМЕРА (чтобы текст не уменьшался)
local function GetFOVSizeMultiplier()
    local cam = workspace.CurrentCamera
    if not cam then return 1 end
    local fov = cam.FieldOfView
    if fov <= 0 then return 1 end
    -- Степень 1.8: при 120 FOV → 1.71^1.8 ≈ 2.66 (вместо 1.71)
    local ratio = fov / ESP_DEFAULT_FOV
    return math.clamp(ratio ^ 1.8, 1, 4.0)
end


local CACHE_INTERVAL = 1
local CurrentRooms = workspace:FindFirstChild("CurrentRooms")

local VisualsPlayer = Tabs.Visuals:AddLeftGroupbox("Player")
local VisualsLeft  = Tabs.Visuals:AddLeftGroupbox("ESP")

-- ============================================================
-- ХЕЛПЕРЫ
-- ============================================================
local function GetRoomNumber(inst)
    local p = inst.Parent
    local depth = 0
    while p and p ~= workspace and depth < 10 do
        local n = tonumber(p.Name)
        if n then return n end
        p = p.Parent
        depth = depth + 1
    end
    return nil
end

local function GetPlayerRoom()
    if not CurrentRooms then return 0 end
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return 0 end

    local best, bestDist = 0, math.huge
    for _, room in ipairs(CurrentRooms:GetChildren()) do
        local num = tonumber(room.Name)
        if num then
            local pivot = room:FindFirstChild("RoomExit")
                or room:FindFirstChild("RoomEntrance")
                or room:FindFirstChild("Door")
                or room.PrimaryPart
            if pivot then
                local d = (hrp.Position - pivot.Position).Magnitude
                if d < bestDist and d < 300 then
                    best, bestDist = num, d
                end
            end
        end
    end
    return best
end

local function IsFurniture(inst)
    local p = inst.Parent
    local depth = 0
    while p and p ~= workspace and depth < 8 do
        local n = p.Name
        if n == "Furniture" or n == "HidingLocker" or n == "HidingLockers"
           or n == "Locker" or n == "Lockers" or n == "Cabinet" then
            return true
        end
        p = p.Parent
        depth = depth + 1
    end
    return false
end

local function IsObjOpen(inst)
    for _, attr in ipairs({ "Opened", "Open", "IsOpen", "IsOpened" }) do
        local ok, v = pcall(function() return inst:GetAttribute(attr) end)
        if ok and v == true then return true end
    end
    return false
end

local function MakeSimpleESP(inst, textColor, outlineColor, labelText, hrp)
    if typeof(outlineColor) ~= "Color3" then
        hrp = labelText
        labelText = outlineColor
        outlineColor = textColor
    end

    local part = inst:IsA("BasePart") and inst or (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart"))
    if not part then return nil end

    -- ЗАЩИТА ОТ ДУБЛЕЙ
    for _, c in ipairs(ESPFolder:GetChildren()) do
        if c:IsA("BillboardGui") and c.Adornee == part then
            c:Destroy()
        elseif c:IsA("Highlight") and c.Adornee == inst then
            c:Destroy()
        end
    end

    local hl = Instance.new("Highlight")
    hl.Adornee = inst
    hl.FillColor = outlineColor
    hl.FillTransparency = 0.85
    hl.OutlineColor = outlineColor
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Parent = ESPFolder

    local bb = Instance.new("BillboardGui")
    bb.Name = "MyHub_SimpleBillboard"
    bb.Adornee = part
    bb.Size = UDim2.new(0, 120, 0, 30)
    -- Разный offset для разных типов объектов
    local offsetY = 0.2   -- дефолт (для Locker, Lever)
    local offsetX = 0     -- по умолчанию — по центру

    if labelText == "Keycard" then
        offsetY = 2.5
        offsetX = 1    -- (минус = влево, плюс = вправо)
    end

    bb.StudsOffset = Vector3.new(offsetX, offsetY, 0)
    bb.ExtentsOffsetWorldSpace = Vector3.new(offsetX, offsetY, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 800
    bb.LightInfluence = 0
    bb.Parent = ESPFolder

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = textColor
    lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
    lbl.TextStrokeTransparency = 0.3
    lbl.TextSize = 14
    lbl.Font = Enum.Font.GothamBold
    lbl.Parent = bb

        return { Highlight = hl, Billboard = bb, Label = lbl, Part = part, Inst = inst, CachedPart = part }
end

local function GetClosestPart(inst, pos)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    if not inst:IsA("Model") then return nil end

    local closest, dist = nil, math.huge
    for _, p in ipairs(inst:GetDescendants()) do
        if p:IsA("BasePart") and p.Transparency < 1 then
            local d = (pos - p.Position).Magnitude
            if d < dist then
                dist = d
                closest = p
            end
        end
    end
    if not closest then
        closest = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
    end
    return closest
end

local function UpdateSimpleESP(data, inst, textColor, outlineColor, labelText, hrp)
    if typeof(outlineColor) ~= "Color3" then
        hrp = labelText
        labelText = outlineColor
        outlineColor = textColor
    end

    if not data then return end
    local colorOpt = nil
    if labelText == "Keycard" then
        colorOpt = Library and Library.Options and Library.Options.KeycardESPColor
    elseif labelText == "Lever" then
        colorOpt = Library and Library.Options and Library.Options.LeverESPColor
    elseif labelText == "Locker" then
        colorOpt = Library and Library.Options and Library.Options.LockerESPColor
    end
    if colorOpt and typeof(colorOpt.Value) == "Color3" then
        textColor = colorOpt.Value
        outlineColor = colorOpt.Value
    end
    if data.Highlight then
        data.Highlight.FillColor = outlineColor
        data.Highlight.OutlineColor = outlineColor
    end
    if data.Label then data.Label.TextColor3 = textColor end

    -- Скрытие при FreeCam
    if data.Billboard then
        data.Billboard.Enabled = not (getgenv().FreeCamActive == true)
    end

    if hrp and data.Billboard then
        -- Не пересчитываем GetClosestPart каждый кадр — используем кэш
        local part = data.CachedPart
        if not part or not part.Parent then
            part = GetClosestPart(inst, hrp.Position)
                or (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart"))
            data.CachedPart = part
        end
        if part then
            if data.Billboard.Adornee ~= part then
                data.Billboard.Adornee = part
            end
            local cam = workspace.CurrentCamera
            local camPos = cam and cam.CFrame.Position or hrp.Position
            local dist = math.floor((camPos - part.Position).Magnitude)
            data.Label.Text = labelText .. " [" .. dist .. "]"

            local sizeMul = GetFOVSizeMultiplier()
            data.Billboard.Size = UDim2.new(0, 120 * sizeMul, 0, 30 * sizeMul)

            if dist < 40 then
                data.Label.TextStrokeTransparency = 0
                data.Label.TextSize = 16 * sizeMul
            else
                data.Label.TextStrokeTransparency = 0.3
                data.Label.TextSize = 14 * sizeMul
            end
        end
    else
        if data.Label then data.Label.Text = labelText end
    end
end

-- ============================================================
-- ENTITY 3D BOX + SCALABLE LABEL (только для сущностей)
-- ============================================================
local ENTITY_EDGE_THICK = 0.6  -- толщина линии (studs)

local EDGE_PAIRS = {
    {1,2},{2,3},{3,4},{4,1},   -- передняя грань
    {5,6},{6,7},{7,8},{8,5},   -- задняя
    {1,5},{2,6},{3,7},{4,8},   -- боковые
}

local function MakeEntityESP(inst, textColor, outlineColor, labelText, hrp)
    local part = inst:IsA("BasePart") and inst or (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart"))
    if not part then return nil end

    local bb = Instance.new("BillboardGui")
    bb.Name = "MyHub_EntityCircle"
    bb.Adornee = part
    bb.Size = UDim2.new(8, 0, 8, 0)
    bb.StudsOffset = Vector3.new(0, 0, 0)
    bb.AlwaysOnTop = true
    bb.MaxDistance = 800
    bb.LightInfluence = 0
    bb.Parent = ESPFolder

    -- Круглая обводка + лёгкий закрас
    local circle = Instance.new("Frame")
    circle.Name = "Circle"
    circle.AnchorPoint = Vector2.new(0.5, 0.5)
    circle.Position = UDim2.new(0.5, 0, 0.5, 0)
    circle.Size = UDim2.new(0.8, 0, 0.8, 0)
    circle.BackgroundColor3 = outlineColor
    circle.BackgroundTransparency = 0.85     -- лёгкий закрас (0.85 = почти прозрачный)
    circle.BorderSizePixel = 0
    circle.Parent = bb

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0.5, 0)   -- 0.5 = идеальный круг
    corner.Parent = circle

    local stroke = Instance.new("UIStroke")
    stroke.Color = outlineColor
    stroke.Thickness = 3
    stroke.Transparency = 0
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Parent = circle

    local bbText = Instance.new("BillboardGui")
    bbText.Name = "MyHub_EntityText"
    bbText.Adornee = part
    bbText.Size = UDim2.new(8, 0, 2, 0)
    bbText.StudsOffset = Vector3.new(0, 0, 0)                      -- ← 0!
    bbText.ExtentsOffsetWorldSpace = Vector3.new(0, 2.5, 0)        -- ← добавил?
    bbText.AlwaysOnTop = true
    bbText.MaxDistance = 800
    bbText.LightInfluence = 0
    bbText.Parent = ESPFolder
	
    local lbl = Instance.new("TextLabel")
    lbl.Name = "Label"
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = labelText
    lbl.TextColor3 = textColor
    lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
    lbl.TextStrokeTransparency = 0
    lbl.TextScaled = true
    lbl.Font = Enum.Font.GothamBlack
    lbl.Parent = bbText

    return {
        Billboard = bb,
        BillboardText = bbText,
        Circle = circle,
        Stroke = stroke,
        Label = lbl,
        Part = part,
        Inst = inst,
        OriginalY = part.Position.Y,   -- запоминаем начальную высоту
        IsEntity = true,
    }
end

local function UpdateEntityESP(data, inst, textColor, outlineColor, labelText, hrp)
    if not data then return end

    if data.Stroke then data.Stroke.Color = outlineColor end
    if data.Circle then data.Circle.BackgroundColor3 = outlineColor end
    if data.Label then data.Label.TextColor3 = textColor end

if hrp and data.Billboard and data.Label then
    local part = GetClosestPart(inst, hrp.Position)
    if part then
        if data.Billboard.Adornee ~= part then data.Billboard.Adornee = part end
        if data.BillboardText and data.BillboardText.Adornee ~= part then
            data.BillboardText.Adornee = part
        end
        data.Part = part

            -- Расстояние считаем от КАМЕРЫ (нужно только для отображения в тексте)
            local cam = workspace.CurrentCamera
            local camPos = cam and cam.CFrame.Position or hrp.Position
            local dist = (camPos - part.Position).Magnitude

            -- Размер ФИКСИРОВАННЫЙ в пикселях — не трогаем вообще
            -- (BillboardGui.Size уже задан в MakeEntityESP как UDim2.new(0, 100, 0, 100))
			            -- Размер текста: у LightBulb — фиксированный, у остальных — скейлится с дистанцией
            if data.BillboardText then
                local offsetMul = GetFOVOffsetMultiplier()
                local sizeMul = GetFOVSizeMultiplier()
                local baseOffsetY = (inst.Name == "LightBulb") and 1.8 or 2.5
                data.BillboardText.StudsOffset = Vector3.new(0, 0, 0)
                data.BillboardText.ExtentsOffsetWorldSpace = Vector3.new(0, baseOffsetY * offsetMul, 0)

                if inst.Name == "LightBulb" then
                    data.BillboardText.Size = UDim2.new(8 * sizeMul, 0, 2 * sizeMul, 0)
                else
                    local textStuds = 5 + dist * 0.05
                    if textStuds < 5 then textStuds = 5 end
                    if textStuds > 25 then textStuds = 25 end
                    data.BillboardText.Size = UDim2.new(textStuds * sizeMul, 0, textStuds * 0.25 * sizeMul, 0)
                end
            end
        end
    end
 end

local function RemoveSimpleESP(state, inst)
    local data = state.Objects[inst]
    if not data then return end
    pcall(function() if data.Highlight then data.Highlight:Destroy() end end)
    pcall(function() if data.Billboard then data.Billboard:Destroy() end end)
    pcall(function() if data.BillboardText then data.BillboardText:Destroy() end end)
    pcall(function() if data.Box then data.Box:Destroy() end end)
    pcall(function() if data.Container then data.Container:Destroy() end end)
    pcall(function() if data.Edges then
        for _, e in ipairs(data.Edges) do e:Destroy() end
    end end)
    pcall(function() if data.Anchor then data.Anchor:Destroy() end end)
    pcall(function() if data.Circle then data.Circle:Destroy() end end)
    pcall(function() if data.Stroke then data.Stroke:Destroy() end end)
    state.Objects[inst] = nil
end

-- ============================================================
-- CUSTOM FOV
-- ============================================================
local CustomFovConn = nil
local DefaultFOV = 70  -- стандартный в Roblox, если не переопределится

-- Запомним дефолтный FOV из камеры на старте
pcall(function()
    if workspace.CurrentCamera then
        DefaultFOV = workspace.CurrentCamera.FieldOfView
    end
end)

local CustomFovToggle = VisualsPlayer:AddToggle("CustomFovToggle", {
    Text = "Custom FOV", Default = false,
    Tooltip = "Изменяет угол обзора камеры."
})
CustomFovToggle = CustomFovToggle or Toggles.CustomFovToggle

local CustomFovSlider = AddResettableSlider(VisualsPlayer, "CustomFovValue", {
    Text = "FOV",
    Min = DefaultFOV, Max = 120, Default = DefaultFOV,
    Rounding = 0, Compact = true
})

local function GetCustomFovValue()
    if CustomFovSlider and CustomFovSlider.Value then
        return CustomFovSlider.Value
    end
    if SliderRefs and SliderRefs.CustomFovValue and SliderRefs.CustomFovValue.Value then
        return SliderRefs.CustomFovValue.Value
    end
    if Library and Library.Options and Library.Options.CustomFovValue then
        local v = Library.Options.CustomFovValue.Value
        if typeof(v) == "number" then return v end
    end
    return DefaultFOV
end

if CustomFovToggle then
    CustomFovToggle:OnChanged(function(Value)
        if CustomFovConn then CustomFovConn:Disconnect() CustomFovConn = nil end

        if Value then
            -- Луп каждый кадр, игра может перебивать FOV
            CustomFovConn = RunService.RenderStepped:Connect(function()
                local cam = workspace.CurrentCamera
                if not cam then return end
                local target = GetCustomFovValue()
                if math.abs(cam.FieldOfView - target) > 0.1 then
                    cam.FieldOfView = target
                end
            end)
        else
            local cam = workspace.CurrentCamera
            if cam then cam.FieldOfView = DefaultFOV end
        end
    end)
end

RegisterCleanup("CustomFov", function()
    if CustomFovConn then CustomFovConn:Disconnect() CustomFovConn = nil end
    local cam = workspace.CurrentCamera
    if cam then cam.FieldOfView = DefaultFOV end
    if Toggles and Toggles.CustomFovToggle then
        SafeSetValue(Toggles.CustomFovToggle, false)
    end
end)

-- ============================================================
-- CUSTOM VIEWMODEL (руки через Shoulder.C0 + RenderStepped)
-- ============================================================

local ViewmodelState = {
    Active = false,
    Conn = nil,
    Arms = {
        Left = {
            Shoulder = nil,
            OrigC0 = nil,
            X = 0, Y = 0, Z = 0,
            RX = 0, RY = 0, RZ = 0,
        },
        Right = {
            Shoulder = nil,
            OrigC0 = nil,
            X = 0, Y = 0, Z = 0,
            RX = 0, RY = 0, RZ = 0,
        },
    },
}

getgenv().ViewmodelState = ViewmodelState

local ViewmodelToggle = VisualsPlayer:AddToggle("ViewmodelToggle", {
    Text = "Custom Viewmodel", Default = false,
    Tooltip = "Меняет положение рук от первого лица."
})
ViewmodelToggle = ViewmodelToggle or Toggles.ViewmodelToggle

-- Дропдаун выбора рук (Multi)
local ViewmodelArmsDropdown = VisualsPlayer:AddDropdown("ViewmodelArms", {
    Text = "Arms",
    Values = { "LeftHand", "RightHand" },
    Multi = true,
    AllowNull = true,
    Default = {},
})
ViewmodelArmsDropdown = ViewmodelArmsDropdown or (Options and Options.ViewmodelArms)

-- Хелпер: получить выбранные руки как массив строк
local function GetSelectedArms()
    local result = {}
    local opt = Library and Library.Options and Library.Options.ViewmodelArms
    local val = opt and opt.Value
    if typeof(val) ~= "table" then return result end
    -- Obsidian возвращает и {LeftHand=true}, и массив — поддержим оба
    if val["LeftHand"] then table.insert(result, "LeftHand") end
    if val["RightHand"] then table.insert(result, "RightHand") end
    if #result == 0 then
        for _, v in ipairs(val) do
            if v == "LeftHand" or v == "RightHand" then
                table.insert(result, v)
            end
        end
    end
    return result
end

-- Слайдеры для обеих рук создаём один раз, но видимость будем включать/выключать
local Sliders = {}

-- Функция создания набора слайдеров для конкретной руки
local function CreateArmSliders(armKey, prefix)
    Sliders[armKey] = {}
    local group = prefix
    Sliders[armKey].X  = AddResettableSlider(VisualsPlayer, armKey .. "_X",  { Text = prefix .. " X",  Min = -3, Max = 3, Default = 0, Rounding = 2, Compact = true })
    Sliders[armKey].Y  = AddResettableSlider(VisualsPlayer, armKey .. "_Y",  { Text = prefix .. " Y",  Min = -3, Max = 3, Default = 0, Rounding = 2, Compact = true })
    Sliders[armKey].Z  = AddResettableSlider(VisualsPlayer, armKey .. "_Z",  { Text = prefix .. " Z",  Min = -3, Max = 3, Default = 0, Rounding = 2, Compact = true })
    Sliders[armKey].RX = AddResettableSlider(VisualsPlayer, armKey .. "_RX", { Text = prefix .. " Rot X", Min = -180, Max = 180, Default = 0, Rounding = 0, Compact = true })
    Sliders[armKey].RY = AddResettableSlider(VisualsPlayer, armKey .. "_RY", { Text = prefix .. " Rot Y", Min = -180, Max = 180, Default = 0, Rounding = 0, Compact = true })
    Sliders[armKey].RZ = AddResettableSlider(VisualsPlayer, armKey .. "_RZ", { Text = prefix .. " Rot Z", Min = -180, Max = 180, Default = 0, Rounding = 0, Compact = true })
end

CreateArmSliders("Left",  "L")
CreateArmSliders("Right", "R")

-- Функция видимости слайдеров
local function UpdateSliderVisibility()
    local selected = GetSelectedArms()
    local leftOn = false
    local rightOn = false
    for _, s in ipairs(selected) do
        if s == "LeftHand" then leftOn = true end
        if s == "RightHand" then rightOn = true end
    end
    -- Если ничего не выбрано — оба набора скрыты
    local function setVisible(armKey, visible)
        for _, key in ipairs({"X","Y","Z","RX","RY","RZ"}) do
            local sl = Sliders[armKey][key]
            if sl and sl.SetVisible then
                sl:SetVisible(visible)
            elseif sl and sl.Toggle then
                sl:Toggle(visible)
            elseif sl and sl.Frame then
                -- Fallback: скрываем фрейм напрямую
                sl.Frame.Visible = visible
            end
        end
    end
    setVisible("Left",  leftOn)
    setVisible("Right", rightOn)
end

-- Функция чтения значения слайдера
local function GetSliderValue(armKey, prop)
    local sl = Sliders[armKey] and Sliders[armKey][prop]
    if sl and sl.Value ~= nil then return sl.Value end
    if SliderRefs and SliderRefs[armKey .. "_" .. prop] then
        local v = SliderRefs[armKey .. "_" .. prop].Value
        if typeof(v) == "number" then return v end
    end
    if Library and Library.Options and Library.Options[armKey .. "_" .. prop] then
        local v = Library.Options[armKey .. "_" .. prop].Value
        if typeof(v) == "number" then return v end
    end
    return 0
end

local function GetArmOffset(armKey)
    return Vector3.new(
        GetSliderValue(armKey, "X"),
        GetSliderValue(armKey, "Y"),
        GetSliderValue(armKey, "Z")
    )
end

local function GetArmRotation(armKey)
    return Vector3.new(
        GetSliderValue(armKey, "RX"),
        GetSliderValue(armKey, "RY"),
        GetSliderValue(armKey, "RZ")
    )
end

local function FindShoulders()
    local char = LocalPlayer and LocalPlayer.Character
    if not char then return nil, nil end
    local lua_ = char:FindFirstChild("LeftUpperArm")
    local rua_ = char:FindFirstChild("RightUpperArm")
    if not lua_ or not rua_ then return nil, nil end
    local lSh = lua_:FindFirstChild("LeftShoulder")
    local rSh = rua_:FindFirstChild("RightShoulder")
    return lSh, rSh
end

local function BuildArmCFrame(armKey, baseC0)
    local pos = GetArmOffset(armKey)
    local rot = GetArmRotation(armKey)
    local cf = CFrame.new(pos) * CFrame.Angles(
        math.rad(rot.X),
        math.rad(rot.Y),
        math.rad(rot.Z)
    )
    return baseC0 * cf
end

local function StartViewmodelLoop()
    if ViewmodelState.Conn then
        ViewmodelState.Conn:Disconnect()
        ViewmodelState.Conn = nil
    end

    local lSh, rSh = FindShoulders()
    if not lSh or not rSh then return end

    local L = ViewmodelState.Arms.Left
    local R = ViewmodelState.Arms.Right

    -- Сохраняем OrigC0 ТОЛЬКО если это новый сустав (или ещё не сохранён)
    if L.Shoulder ~= lSh or not L.OrigC0 then
        L.Shoulder = lSh
        L.OrigC0 = lSh.C0
    end
    if R.Shoulder ~= rSh or not R.OrigC0 then
        R.Shoulder = rSh
        R.OrigC0 = rSh.C0
    end

    ViewmodelState.Conn = RunService.RenderStepped:Connect(function()
        if not ViewmodelState.Active then return end

        local LL = ViewmodelState.Arms.Left
        local RR = ViewmodelState.Arms.Right

        -- Перепривязка при респавне
        if not LL.Shoulder or not LL.Shoulder.Parent or not RR.Shoulder or not RR.Shoulder.Parent then
            local nl, nr = FindShoulders()
            if nl and nr then
                LL.Shoulder = nl
                RR.Shoulder = nr
                LL.OrigC0 = nl.C0
                RR.OrigC0 = nr.C0
            end
            return
        end

        -- ВСЕГДА применяем оффсеты — выбор в дропдауне только для UI,
        -- чтобы можно было скрыть слайдеры, не теряя настройки
        LL.Shoulder.C0 = BuildArmCFrame("Left", LL.OrigC0)
        RR.Shoulder.C0 = BuildArmCFrame("Right", RR.OrigC0)
    end)
end

local function StopViewmodelLoop()
    ViewmodelState.Active = false
    if ViewmodelState.Conn then
        ViewmodelState.Conn:Disconnect()
        ViewmodelState.Conn = nil
    end
    local L = ViewmodelState.Arms.Left
    local R = ViewmodelState.Arms.Right
    if L.Shoulder and L.Shoulder.Parent and L.OrigC0 then
        L.Shoulder.C0 = L.OrigC0
    end
    if R.Shoulder and R.Shoulder.Parent and R.OrigC0 then
        R.Shoulder.C0 = R.OrigC0
    end
end

-- Обновляем выбранные руки при смене дропдауна
if ViewmodelArmsDropdown then
    ViewmodelArmsDropdown:OnChanged(function()
        UpdateSliderVisibility()
        -- Луп перезапускать не надо — он сам видит изменения через GetSelectedArms() каждый кадр
    end)
end

if ViewmodelToggle then
    ViewmodelToggle:OnChanged(function(Value)
        ViewmodelState.Active = Value
        if Value then
            StartViewmodelLoop()
            UpdateSliderVisibility()
        else
            StopViewmodelLoop()
        end
    end)
end

-- При респавне — перепривязка
if LocalPlayer then
    LocalPlayer.CharacterAdded:Connect(function()
        if ViewmodelState.Active then
            task.wait(1)
            StartViewmodelLoop()
        end
    end)
end

-- Инициализируем видимость слайдеров при старте
task.spawn(function()
    task.wait(1)
    UpdateSliderVisibility()
end)

RegisterCleanup("Viewmodel", function()
    StopViewmodelLoop()
    if Toggles and Toggles.ViewmodelToggle then
        SafeSetValue(Toggles.ViewmodelToggle, false)
    end
end)


-- ============================================================
-- HIDE PLAYER HANDS / HIDE PLAYER BODY (FINAL)
-- ============================================================
local HideState = { Hands = false, Body = false, CharConn = nil, C0Conn = nil }

-- При переинжекте отключаем луп от прошлой версии скрипта
pcall(function()
    if getgenv().MyHub_HideLoopConn then
        getgenv().MyHub_HideLoopConn:Disconnect()
        getgenv().MyHub_HideLoopConn = nil
    end
end)

local HAND_PARTS = {
    LeftUpperArm = true, RightUpperArm = true,
    LeftLowerArm = true, RightLowerArm = true,
    LeftHand = true, RightHand = true,
}
local BODY_PARTS = {
    UpperTorso = true, LowerTorso = true,
    LeftUpperLeg = true, RightUpperLeg = true,
    LeftLowerLeg = true, RightLowerLeg = true,
    LeftFoot = true, RightFoot = true,
}

getgenv().MyHub_HandParts = HAND_PARTS
getgenv().MyHub_BodyParts = BODY_PARTS

local function UpdateParts()
    local char = LocalPlayer and LocalPlayer.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") then
            local isHand = HAND_PARTS[part.Name]
            local isBody = BODY_PARTS[part.Name]
            if isHand or isBody then
                local hide = false
                if isHand and HideState.Hands then hide = true end
                if isBody and HideState.Body then hide = true end
                if hide then
                    if part.Transparency ~= 1 then part.Transparency = 1 end
                    if part.LocalTransparencyModifier ~= 1 then
                        part.LocalTransparencyModifier = 1
                    end
                else
                    if part.Transparency ~= 0 then part.Transparency = 0 end
                    if part.LocalTransparencyModifier ~= 0 then
                        part.LocalTransparencyModifier = 0
                    end
                end
            end
        end
    end
end
getgenv().MyHub_UpdateParts = UpdateParts

-- Фоновый луп: держит состояние (игра перебивает LTM каждый кадр)
local HideLoopConn = RunService.RenderStepped:Connect(function()
    UpdateParts()
end)
getgenv().MyHub_HideLoopConn = HideLoopConn

local HideHandsToggle = VisualsPlayer:AddToggle("HideHandsToggle", {
    Text = "Hide Player Hands", Default = false,
    Tooltip = "Скрывает руки."
})
HideHandsToggle = HideHandsToggle or (Toggles and Toggles.HideHandsToggle)
if HideHandsToggle then
    HideHandsToggle:OnChanged(function(v)
        HideState.Hands = v
        UpdateParts()
    end)
end

local HideBodyToggle = VisualsPlayer:AddToggle("HideBodyToggle", {
    Text = "Hide Player Body", Default = false,
    Tooltip = "Скрывает тело."
})
HideBodyToggle = HideBodyToggle or (Toggles and Toggles.HideBodyToggle)
if HideBodyToggle then
    HideBodyToggle:OnChanged(function(v)
        HideState.Body = v
        UpdateParts()
    end)
end

-- C0-синхронизация для приседа (не трогает видимость)
local OrigLC0, OrigRC0
HideState.C0Conn = RunService.Heartbeat:Connect(function()
    local char = LocalPlayer and LocalPlayer.Character
    if not char then OrigLC0 = nil OrigRC0 = nil return end
    local vOwns = getgenv().ViewmodelState and getgenv().ViewmodelState.Active
    if vOwns then return end
    local lua_ = char:FindFirstChild("LeftUpperArm")
    local rua_ = char:FindFirstChild("RightUpperArm")
    local lSh = lua_ and lua_:FindFirstChild("LeftShoulder")
    local rSh = rua_ and rua_:FindFirstChild("RightShoulder")
    if lSh then
        if not OrigLC0 then OrigLC0 = lSh.C0 end
        lSh.C0 = OrigLC0
    end
    if rSh then
        if not OrigRC0 then OrigRC0 = rSh.C0 end
        rSh.C0 = OrigRC0
    end
end)

-- Респавн — переустановить состояние
if LocalPlayer then
    LocalPlayer.CharacterAdded:Connect(function()
        OrigLC0 = nil OrigRC0 = nil
        task.wait(0.5)
        UpdateParts()
    end)
end

RegisterCleanup("HidePlayerParts", function()
    HideState.Hands = false
    HideState.Body = false
    -- ВАЖНО: НЕ отключаем HideLoopConn — пусть работает вечно и держит T=0
    UpdateParts()
    if Toggles.HideHandsToggle then SafeSetValue(Toggles.HideHandsToggle, false) end
    if Toggles.HideBodyToggle then SafeSetValue(Toggles.HideBodyToggle, false) end
end)



-- ============================================================
-- DOOR ESP
-- ============================================================
local DoorESPState = { Objects = {}, Cache = {}, Loop = nil, AddedConn = nil, RoomConn = nil, RoomAddedConn = nil }
getgenv().DoorESPState = DoorESPState

local DOOR_MAX_DIST = 400
local CACHE_INTERVAL = 1

local function GetRoomNumberFromDoors(doorsFolder)
    local p = doorsFolder.Parent
    local depth = 0
    while p and p ~= workspace and depth < 12 do
        local n = tonumber(p.Name)
        if n then return n + 1 end
        p = p.Parent
        depth = depth + 1
    end
    return nil
end

local function IsDoorPart(inst)
    if not inst or typeof(inst) ~= "Instance" then return false end

    -- Вспомогалка: проверка что это не мебель
    local function NotFurniture(obj)
        local p = obj.Parent
        local depth = 0
        while p and p ~= workspace and depth < 12 do
            local n = p.Name
            if n == "Furniture" or n == "HidingLocker" or n == "HidingLockers"
               or n == "Locker" or n == "Lockers" or n == "Cabinet"
               or n == "LootLocker" or n == "Warehouse_LootLocker" then
                return false
            end
            p = p.Parent
            depth = depth + 1
        end
        return true
    end

    -- Вспомогалка: проверка на подкомнату (не подсвечиваем)
    local function IsSubroom(obj)
        local p = obj
        local depth = 0
        while p and p ~= workspace and depth < 8 do
            for _, attr in ipairs({ "Subroom", "IsSubroom" }) do
                local ok, v = pcall(function() return p:GetAttribute(attr) end)
                if ok and v == true then return true end
            end
            p = p.Parent
            depth = depth + 1
        end
        return false
    end

    -- GateFrame (Model) — где угодно в дереве комнаты
    if inst.Name == "GateFrame" and inst:IsA("Model") then
        if not NotFurniture(inst) then return false end
        if IsSubroom(inst) then return false end
        -- Отсеиваем декор: если внутри только стены (Wall) — это не дверь
        if inst:FindFirstChild("Wall", true) then return false end
        return true
    end

    -- Gate (Model) — только если родитель Door / DoorWarehouseGate / Assets
    if inst.Name == "Gate" and inst:IsA("Model") then
        local pp = inst.Parent
        if pp and (pp.Name == "Door" or pp.Name == "DoorWarehouseGate" or pp.Name == "Assets") then
            if not NotFurniture(inst) then return false end
            if IsSubroom(inst) then return false end
            if inst:FindFirstChild("Wall", true) then return false end
            return true
        end
        return false
    end

    -- DoorWarehouseGate (Model)
    if inst.Name == "DoorWarehouseGate" and inst:IsA("Model") then
        if not NotFurniture(inst) then return false end
        if IsSubroom(inst) then return false end
        return true
    end

    -- Door (Model-обёртка с Gate/PrimaryPart внутри)
    if inst.Name == "Door" and inst:IsA("Model") then
        if not (inst:FindFirstChild("Gate") or inst:FindFirstChild("PrimaryPart")) then
            return false
        end
        if not NotFurniture(inst) then return false end
        if IsSubroom(inst) then return false end
        return true
    end

    -- GateDoor (Main-XXXX) — MeshPart
    if inst.Name == "GateDoor" and inst:IsA("BasePart") then
        local parent = inst.Parent
        if not (parent and parent:IsA("Model") and parent.Name == "Door") then
            return false
        end
        if not NotFurniture(parent) then return false end
        if IsSubroom(parent) then return false end
        local p = parent.Parent
        local depth = 0
        local foundScriptables, foundFake, foundAssets = false, false, false
        while p and p ~= workspace and depth < 12 do
            local n = p.Name
            if n == "Furniture" or n == "HidingLocker" or n == "HidingLockers" then return false end
            if n == "Scriptables" then foundScriptables = true end
            if n == "DoorLaboratoryFake" then foundFake = true end
            if n == "Assets" then foundAssets = true end
            p = p.Parent
            depth = depth + 1
        end
        return not foundScriptables and not foundFake and not foundAssets
    end

    -- Стандартные двери (DoorLeft / DoorRight)
    if not inst:IsA("BasePart") then return false end
    if inst.Name ~= "DoorLeft" and inst.Name ~= "DoorRight" then return false end
    local parent = inst.Parent
    if not parent or not parent:IsA("Model") then return false end
    if parent.Name ~= "DoorLeft" and parent.Name ~= "DoorRight" then return false end
    if not NotFurniture(parent) then return false end
    if IsSubroom(parent) then return false end

    local p = parent.Parent
    local depth = 0
    local foundDoors, foundScriptables, foundFake, foundAssets = false, false, false, false
    while p and p ~= workspace and depth < 12 do
        local n = p.Name
        if n == "Furniture" or n == "HidingLocker" or n == "HidingLockers" then return false end
        if n == "Doors" then foundDoors = true end
        if n == "Scriptables" then foundScriptables = true end
        if n == "DoorLaboratoryFake" then foundFake = true end
        if n == "Assets" then foundAssets = true end
        p = p.Parent
        depth = depth + 1
    end
    return foundDoors and not foundScriptables and not foundFake and not foundAssets
end

local function FindDoorsFolder(inst)
    -- Модели-двери — возвращаем сам объект как "папку"
    if inst.Name == "GateFrame" and inst:IsA("Model") then
        return inst
    end
    if inst.Name == "DoorWarehouseGate" and inst:IsA("Model") then
        return inst
    end
    if inst.Name == "Door" and inst:IsA("Model") then
        -- ВАЖНО: если внутри есть папка Doors (тип 1) — возвращаем именно её
        local doorsSub = inst:FindFirstChild("Doors")
        if doorsSub and doorsSub:IsA("Folder") then
            return doorsSub
        end
        -- Иначе (Gate/PrimaryPart) — тип 3
        if inst:FindFirstChild("Gate") or inst:FindFirstChild("PrimaryPart") then
            return inst
        end
    end
    if inst.Name == "Gate" and inst:IsA("Model") then
        return inst.Parent
    end
    -- GateDoor — родитель Door
    if inst.Name == "GateDoor" and inst:IsA("BasePart") then
        if inst.Parent and inst.Parent:IsA("Model") and inst.Parent.Name == "Door" then
            return inst.Parent
        end
    end
    -- Стандартные двери — папка Doors
    local p = inst.Parent
    while p and p ~= workspace do
        if p:IsA("Folder") and p.Name == "Doors" then return p end
        p = p.Parent
    end
    return nil
end

local function ComputeDoorCenter(doorsFolder)
    if not doorsFolder then return nil end

    -- Модели-двери
    if doorsFolder:IsA("Model") then
        if doorsFolder.Name == "DoorWarehouseGate" then
            local frame = doorsFolder:FindFirstChild("Frame")
            local gateFrame = frame and frame:FindFirstChild("GateFrame")
            if gateFrame then
                local ok, cf = pcall(function() return gateFrame:GetBoundingBox() end)
                if ok and cf then return cf.Position end
            end
        end
        if doorsFolder.Name == "Door" then
            local gateDoor = doorsFolder:FindFirstChild("GateDoor")
            if gateDoor and gateDoor:IsA("BasePart") then return gateDoor.Position end
            local gate = doorsFolder:FindFirstChild("Gate")
            if gate then
                local ok, cf = pcall(function() return gate:GetBoundingBox() end)
                if ok and cf then return cf.Position end
            end
            if doorsFolder.PrimaryPart then return doorsFolder.PrimaryPart.Position end
        end
        -- Общий случай — bbox модели
        local ok, cf = pcall(function() return doorsFolder:GetBoundingBox() end)
        if ok and cf then return cf.Position end
    end

    -- GateDoor (Main-XXXX)
    local gate = doorsFolder:FindFirstChild("GateDoor")
    if gate and gate:IsA("BasePart") then return gate.Position end

    -- Стандартные двери (DoorLeft/DoorRight в папке Doors)
    local leftPart, rightPart
    for _, m in ipairs(doorsFolder:GetChildren()) do
        if m:IsA("Model") then
            if m.Name == "DoorLeft" then leftPart = m:FindFirstChildWhichIsA("BasePart")
            elseif m.Name == "DoorRight" then rightPart = m:FindFirstChildWhichIsA("BasePart") end
        end
    end
    if leftPart and rightPart then return (leftPart.Position + rightPart.Position) / 2 end
    if leftPart then return leftPart.Position end
    if rightPart then return rightPart.Position end
    return nil
end

local function IsDoorOpened(doorsFolder)
    for _, attr in ipairs({ "Opened", "Open", "IsOpen", "IsOpened" }) do
        local ok, v = pcall(function() return doorsFolder:GetAttribute(attr) end)
        if ok and v == true then return true end
    end
    return false
end

local function AddDoorESP(doorsFolder, color, cachedInfo)
    if DoorESPState.Objects[doorsFolder] then return end

    local center = (cachedInfo and cachedInfo.Center) or ComputeDoorCenter(doorsFolder)
    if not center then return end

    local anchor = Instance.new("Part")
    anchor.Name = "DoorESP_Anchor"
    anchor.Anchored = true
    anchor.CanCollide = false
    anchor.CanQuery = false
    anchor.CanTouch = false
    anchor.Transparency = 1
    anchor.Size = Vector3.new(0.1, 0.1, 0.1)
    anchor.CFrame = CFrame.new(center)
    anchor.Parent = workspace

    local highlights = {}

    local function addHL(target)
        if not target then return end
        if typeof(target) ~= "Instance" then return end
        if not (target:IsA("Model") or target:IsA("BasePart")) then return end
        local hl = Instance.new("Highlight")
        hl.Adornee = target
        hl.FillColor = color
        hl.FillTransparency = 0.85
        hl.OutlineColor = color
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Parent = ESPFolder
        table.insert(highlights, hl)
    end

    -- ==== ТИП 1: стандартные двери (папка Doors) ====
    if doorsFolder:IsA("Folder") and doorsFolder.Name == "Doors" then
        for _, m in ipairs(doorsFolder:GetChildren()) do
            if m:IsA("Model") then
                -- Ищем MeshPart с именем модели (DoorLeft -> DoorLeft)
                local mesh = m:FindFirstChild(m.Name)
                if mesh and mesh:IsA("BasePart") then
                    addHL(mesh)
                else
                    -- Fallback — модель целиком
                    addHL(m)
                end
            elseif m:IsA("BasePart") then
                addHL(m)
            end
        end
    -- ==== ТИП 3: GateDoor (Main-XXXX) ====
    elseif doorsFolder:FindFirstChild("GateDoor") then
        addHL(doorsFolder:FindFirstChild("GateDoor"))
    -- ==== ТИП 3b: GateFrame / Gate ====
    elseif doorsFolder.Name == "GateFrame" or doorsFolder.Name == "Gate" then
        addHL(doorsFolder)
    -- ==== ТИП 2: DoorWarehouseGate (Sector) ====
    elseif doorsFolder.Name == "DoorWarehouseGate" then
        local target = doorsFolder:FindFirstChild("GateFrame", true)
            or doorsFolder:FindFirstChild("Gate", true)
            or doorsFolder:FindFirstChild("PrimaryPart", true)
        addHL(target or doorsFolder)
    -- ==== Модель Door с Gate/PrimaryPart ====
    elseif doorsFolder.Name == "Door" and doorsFolder:IsA("Model") then
        local target = doorsFolder:FindFirstChild("Gate")
            or doorsFolder:FindFirstChild("PrimaryPart")
            or doorsFolder:FindFirstChild("GateDoor")
        addHL(target or doorsFolder)
    -- ==== Fallback ====
    else
        if doorsFolder:IsA("Model") or doorsFolder:IsA("BasePart") then
            addHL(doorsFolder)
        end
    end

    -- Страховка: если ни одной подсветки не создалось — светим модель целиком
    if #highlights == 0 and (doorsFolder:IsA("Model") or doorsFolder:IsA("BasePart")) then
        addHL(doorsFolder)
    end

    local bb = Instance.new("BillboardGui")
    bb.Adornee = anchor                                    -- ← было part (nil!)
    bb.Size = UDim2.new(0, 120, 0, 30)
    bb.StudsOffset = Vector3.new(0, 2, 0)
    bb.ExtentsOffsetWorldSpace = Vector3.new(0, 2, 0)      -- ← чтобы не уходил под землю при повороте камеры
    bb.AlwaysOnTop = true
    bb.MaxDistance = 800
    bb.Parent = ESPFolder

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "Door"
    lbl.TextColor3 = color
    lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
    lbl.TextStrokeTransparency = 0.3
    lbl.TextSize = 14
    lbl.Font = Enum.Font.GothamBold
    lbl.Parent = bb

DoorESPState.Objects[doorsFolder] = {
    Highlights = highlights,
    Anchor = anchor,
    Billboard = bb,
    Label = lbl,
    DisplayRoom = cachedInfo and cachedInfo.DisplayRoom,
}
end

local function UpdateDoorESP(doorsFolder, color, hrp)
    local data = DoorESPState.Objects[doorsFolder]
    if not data then return end
    if data.ShadeHighlight then return end
    -- Всегда берём актуальный цвет из палитры, чтобы не было отката к дефолту
    if Library and Library.Options and Library.Options.DoorESPColor then
        color = Library.Options.DoorESPColor.Value
    end
    for _, hl in ipairs(data.Highlights) do
        hl.FillColor = color
        hl.OutlineColor = color
    end
    data.Label.TextColor3 = color

    -- Скрытие при FreeCam
    if data.Billboard then
        data.Billboard.Enabled = not (getgenv().FreeCamActive == true)
    end

    if hrp then
        local cam = workspace.CurrentCamera
        local camPos = cam and cam.CFrame.Position or hrp.Position
        local dist = math.floor((camPos - data.Anchor.Position).Magnitude)

        -- Компенсация FOV
        local sizeMul = GetFOVSizeMultiplier()
        if data.Billboard then
            data.Billboard.Size = UDim2.new(0, 120 * sizeMul, 0, 30 * sizeMul)
        end

        -- TextSize тоже скейлим
        if dist < 40 then
            data.Label.TextSize = 16 * sizeMul
        else
            data.Label.TextSize = 14 * sizeMul
        end

        if data.DisplayRoom then
            data.Label.Text = "Door " .. data.DisplayRoom .. " [" .. dist .. "]"
        else
            data.Label.Text = "Door [" .. dist .. "]"
        end
    end
end

local function RemoveDoorESP(doorsFolder)
    local data = DoorESPState.Objects[doorsFolder]
    if not data then return end
    for _, hl in ipairs(data.Highlights) do
        pcall(function() hl:Destroy() end)
    end
    pcall(function() data.Billboard:Destroy() end)
    pcall(function() data.Anchor:Destroy() end)
    DoorESPState.Objects[doorsFolder] = nil
end

DoorESPToggle = VisualsLeft:AddToggle("DoorESPToggle", {
    Text = "Door ESP", Default = false,
    Tooltip = "Подсвечивает двери."
})
DoorESPToggle = DoorESPToggle or Toggles.DoorESPToggle
if DoorESPToggle then
    DoorESPToggle:AddColorPicker("DoorESPColor", {
        Text = "Door Color", Default = Color3.fromRGB(0, 200, 255), Transparency = 0
    })
end

local function ScanRoomIntoCache(room)
    if not room then return end
    for _, inst in ipairs(room:GetDescendants()) do
        if IsDoorPart(inst) then
            local folder = FindDoorsFolder(inst)
            if folder and not DoorESPState.Cache[folder] then
                local center = ComputeDoorCenter(folder)
                if center then
                    local rn = GetRoomNumberFromDoors(folder)

                    -- ДЕДУП: только если есть дверь С ТАКИМ ЖЕ DisplayRoom рядом
                    -- (это одна и та же дверь найдена через разные ноды: Gate + Door + GateFrame)
                    local isDuplicate = false
                    for _, info in pairs(DoorESPState.Cache) do
                        if info.DisplayRoom == rn and info.Center
                           and (info.Center - center).Magnitude < 15 then
                            isDuplicate = true
                            break
                        end
                    end

                    if not isDuplicate then
                        DoorESPState.Cache[folder] = { Center = center, DisplayRoom = rn }
                    end
                end
            end
        end
    end
end


-- Определяем комнату игрока по позиции (Start / Exit / PrimaryPart)
local function GetPlayerRoomByPos()
    local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end
    local rooms = workspace:FindFirstChild("CurrentRooms")
    if not rooms then return nil end

    local best, bestDist = nil, math.huge
    for _, room in ipairs(rooms:GetChildren()) do
        local num = tonumber(room.Name)
        if num then
            local pivot = room:FindFirstChild("Start")
                or room:FindFirstChild("Exit")
                or room.PrimaryPart
            if pivot then
                local d = (hrp.Position - pivot.Position).Magnitude
                if d < bestDist then
                    bestDist = d
                    best = num
                end
            end
        end
    end
    return best
end

local function RebuildDoorCache()
    local rooms = workspace:FindFirstChild("CurrentRooms")
    if not rooms then return end

    -- Чистим мёртвые (через буфер — не мутируем во время pairs)
    local dead = {}
    for folder in pairs(DoorESPState.Cache) do
        if not folder.Parent then table.insert(dead, folder) end
    end
    for _, folder in ipairs(dead) do
        RemoveDoorESP(folder)
        DoorESPState.Cache[folder] = nil
    end

    -- Берём cur из атрибута. Если невалидный — считаем по позиции игрока.
    -- ЭТО ФИКС: после re-inject атрибут может быть nil/0 несколько секунд,
    -- и тогда первые двери не находятся.
    local cur = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))
    if not cur or cur <= 0 then
        cur = GetPlayerRoomByPos()
        if cur then
            print("[DoorESP] CurrentRoom attr был nil/0, взял по позиции:", cur)
        end
    end
    if not cur or cur <= 0 then cur = 0 end

    for _, rn in ipairs({ cur - 2, cur - 1, cur, cur + 1, cur + 2, cur + 3 }) do
        local r = rooms:FindFirstChild(tostring(rn))
        if r then ScanRoomIntoCache(r) end
    end
end


local function StartDoorLoop()
    if DoorESPState.Loop then return end

    RebuildDoorCache()
    
    -- Форс-ребилды после инжекта — комнаты/двери впереди могут прогрузиться с задержкой
    task.delay(1.5, function()
        if DoorESPToggle and DoorESPToggle.Value then RebuildDoorCache() end
    end)
    task.delay(3, function()
        if DoorESPToggle and DoorESPToggle.Value then RebuildDoorCache() end
    end)
    task.delay(5, function()
        if DoorESPToggle and DoorESPToggle.Value then RebuildDoorCache() end
    end)

    if DoorESPState.RoomAddedConn then DoorESPState.RoomAddedConn:Disconnect() end
    local rooms = workspace:FindFirstChild("CurrentRooms")
    if rooms then
        DoorESPState.RoomAddedConn = rooms.ChildAdded:Connect(function(room)
            task.wait(0.6)
            if DoorESPToggle and DoorESPToggle.Value and tonumber(room.Name) then
                ScanRoomIntoCache(room)
            end
            task.delay(2, function()
                if DoorESPToggle and DoorESPToggle.Value and room.Parent then
                    ScanRoomIntoCache(room)
                end
            end)
        end)
    end

    if DoorESPState.AddedConn then DoorESPState.AddedConn:Disconnect() end
    local DoorAddedQueue = {}
    local DoorAddedScheduled = false
    DoorESPState.AddedConn = workspace.DescendantAdded:Connect(function(inst)
        if not DoorESPToggle or not DoorESPToggle.Value then return end
        -- Мгновенный отсев по классу и имени (без IsA-цепочек)
        local n = inst.Name
        if n ~= "DoorLeft" and n ~= "DoorRight"
           and n ~= "GateDoor" and n ~= "GateFrame"
           and n ~= "Gate" and n ~= "DoorWarehouseGate"
           and n ~= "Door" then return end
        table.insert(DoorAddedQueue, inst)
        if DoorAddedScheduled then return end
        DoorAddedScheduled = true
        task.delay(0.8, function()
            DoorAddedScheduled = false
            for i = #DoorAddedQueue, 1, -1 do
                local obj = DoorAddedQueue[i]
                if obj and obj.Parent and IsDoorPart(obj) then
                    local folder = FindDoorsFolder(obj)
                    if folder and not DoorESPState.Cache[folder] then
                        local center = ComputeDoorCenter(folder)
                        if center then
                            local rn = GetRoomNumberFromDoors(folder)
                            DoorESPState.Cache[folder] = { Center = center, DisplayRoom = rn }
                        end
                    end
                end
            end
            table.clear(DoorAddedQueue)
        end)
    end)

    if DoorESPState.RoomConn then DoorESPState.RoomConn:Disconnect() end
    local LastRoom = -1
    DoorESPState.RoomConn = LocalPlayer:GetAttributeChangedSignal("CurrentRoom"):Connect(function()
        local cur = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))
        if not cur or cur == LastRoom then return end
        LastRoom = cur
        task.wait(0.4)
        if DoorESPToggle and DoorESPToggle.Value then
            RebuildDoorCache()
        end
    end)

    local DoorFrame = 0
    local MAX_DOOR_DIST = 400   -- studs — радиус подсветки

    DoorESPState.Loop = RunService.Heartbeat:Connect(function()
        if not DoorESPToggle or not DoorESPToggle.Value then return end
        DoorFrame = DoorFrame + 1
        if DoorFrame % 5 ~= 0 then return end

        local normalColor = (Library and Library.Options and Library.Options.DoorESPColor and Library.Options.DoorESPColor.Value) or Color3.fromRGB(0, 200, 255)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

-- Собираем мёртвые ключи в буфер, чтобы не мутировать во время pairs
local deadKeys = {}
for folder in pairs(DoorESPState.Cache) do
    if not folder.Parent then table.insert(deadKeys, folder) end
end
for _, folder in ipairs(deadKeys) do
    RemoveDoorESP(folder)
    DoorESPState.Cache[folder] = nil
end

for folder, info in pairs(DoorESPState.Cache) do
    if folder.Parent then
        local data = DoorESPState.Objects[folder]
        local pos = data and data.Anchor.Position or info.Center

        -- Shade-двери игнорируют дистанцию
        local isShade = data and data.ShadeHighlight

        local inRange = true
        if pos and hrp and not isShade then
            if (hrp.Position - pos).Magnitude > MAX_DOOR_DIST then
                inRange = false
            end
        end

        if not inRange then
            if data then RemoveDoorESP(folder) end
        else
            if not data then
                pcall(AddDoorESP, folder, normalColor, info)
            else
                if data.ShadeHighlight then
                    -- Дверь с Shade — обновляем только текст (цвет не трогаем)
                    if hrp then
                        local dist = math.floor((hrp.Position - data.Anchor.Position).Magnitude)
                        local dr = info.DisplayRoom or "?"
                        local newText = "SHADE " .. tostring(dr) .. " [" .. dist .. "]"
                        if data.Label.Text ~= newText then
                            data.Label.Text = newText
                        end
                    end
                else
                    UpdateDoorESP(folder, normalColor, hrp)
                end
            end
        end
    end
end
    end)
end


local function StopDoorLoop()
    if DoorESPState.Loop then DoorESPState.Loop:Disconnect() DoorESPState.Loop = nil end
    if DoorESPState.RoomConn then DoorESPState.RoomConn:Disconnect() DoorESPState.RoomConn = nil end
    if DoorESPState.RoomAddedConn then DoorESPState.RoomAddedConn:Disconnect() DoorESPState.RoomAddedConn = nil end
    if DoorESPState.AddedConn then DoorESPState.AddedConn:Disconnect() DoorESPState.AddedConn = nil end
end

if DoorESPToggle then
    DoorESPToggle:OnChanged(function(Value)
        if Value then
            StartDoorLoop()
        else
            StopDoorLoop()
            for folder in pairs(DoorESPState.Objects) do RemoveDoorESP(folder) end
        end
    end)
end

RegisterCleanup("DoorESP", function()
    StopDoorLoop()
    for folder in pairs(DoorESPState.Objects) do RemoveDoorESP(folder) end
    table.clear(DoorESPState.Objects)
    table.clear(DoorESPState.Cache)
    if getgenv().ShadeState then
        getgenv().ShadeState.ColoredDoors = {}
    end
    if Toggles.DoorESPToggle then SafeSetValue(Toggles.DoorESPToggle, false) end
end)



local KeycardESPState = { Objects = {}, Cache = {}, LastCache = 0, Loop = nil }

KeycardESPToggle = VisualsLeft:AddToggle("KeycardESPToggle", {
    Text = "Keycard ESP", Default = false,
    Tooltip = "Подсвечивает Карты."
})
KeycardESPToggle = KeycardESPToggle or Toggles.KeycardESPToggle
if KeycardESPToggle then
    KeycardESPToggle:AddColorPicker("KeycardESPColor", {
        Text = "Keycard Color", Default = Color3.fromRGB(255, 200, 0), Transparency = 0
    })
end

local function IsKeycard(inst)
    if not inst or typeof(inst) ~= "Instance" then return false end
    if not (inst:IsA("Model") or inst:IsA("BasePart") or inst:IsA("Tool")) then return false end
    if not string.find(string.lower(inst.Name), "keycard", 1, true) then return false end

    -- Пропускаем карту в руках / на персонаже игрока
    local char = LocalPlayer.Character
    if char then
        local p = inst
        local depth = 0
        while p and depth < 8 do
            if p == char then return false end
            p = p.Parent
            depth = depth + 1
        end
    end

    -- 1) Настоящий подбираемый кейкарт — это Tool, или объект с Handle внутри
    local isPickup = inst:IsA("Tool") or inst:FindFirstChild("Handle") ~= nil

    -- 2) Исключаем всё, что лежит внутри двери
    local p = inst.Parent
    local depth = 0
    local insideDoor = false
    while p and p ~= workspace and depth < 8 do
        local n = p.Name
        if n == "Door" or n == "Doors" or n == "DoorLeft" or n == "DoorRight"
           or n == "DoorSlot" or n == "KeycardSlot" or n == "Slot" then
            insideDoor = true
            break
        end
        p = p.Parent
        depth = depth + 1
    end

    if insideDoor and not isPickup then return false end

    -- 3) Если это BasePart-пустышка без Handle внутри модели — отсеиваем
    if inst:IsA("BasePart") and not inst.Parent:FindFirstChild("Handle") then
        -- но если это именно Tool с Handle — оставляем
        if not inst:IsA("Tool") then
            -- проверяем есть ли выше Tool
            local y = inst
            local isInTool = false
            local d2 = 0
            while y and y ~= workspace and d2 < 5 do
                if y:IsA("Tool") then isInTool = true break end
                y = y.Parent
                d2 = d2 + 1
            end
            if not isInTool then return false end
        end
    end

    return true
end

local function RebuildKeycardCache()
    local newCache = {}
    local root = Workspace:FindFirstChild("CurrentRooms") or Workspace
    for _, inst in ipairs(root:GetDescendants()) do
        if IsKeycard(inst) then newCache[inst] = true end
    end
    KeycardESPState.Cache = newCache
end

local KeycardRoomConn = nil

local function StartKeycardLoop()
    if KeycardESPState.Loop then return end

    RebuildKeycardCache()

        if KeycardESPState.AddedConn then KeycardESPState.AddedConn:Disconnect() end
    local KAddedQueue = {}
    local KAddedScheduled = false
    KeycardESPState.AddedConn = Workspace.DescendantAdded:Connect(function(inst)
        if not KeycardESPToggle or not KeycardESPToggle.Value then return end
        table.insert(KAddedQueue, inst)
        if KAddedScheduled then return end
        KAddedScheduled = true
        task.delay(0.8, function()
            KAddedScheduled = false
            for _, obj in ipairs(KAddedQueue) do
                if obj.Parent and IsKeycard(obj) then
                    KeycardESPState.Cache[obj] = true
                end
            end
            table.clear(KAddedQueue)
        end)
    end)

    local KLastRebuild = 0
    if KeycardRoomConn then KeycardRoomConn:Disconnect() end
    KeycardRoomConn = LocalPlayer:GetAttributeChangedSignal("CurrentRoom"):Connect(function()
        if tick() - KLastRebuild < 1.5 then return end
        KLastRebuild = tick()
        task.wait(0.4)
        if KeycardESPToggle and KeycardESPToggle.Value then
            RebuildKeycardCache()
        end
    end)

    local KFrame = 0
    KeycardESPState.Loop = RunService.Heartbeat:Connect(function()
        if not KeycardESPToggle or not KeycardESPToggle.Value then return end
        KFrame = KFrame + 1
        if KFrame % 5 ~= 0 then return end

        local color = (Library and Library.Options and Library.Options.KeycardESPColor and Library.Options.KeycardESPColor.Value) or Color3.fromRGB(255, 200, 0)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

        for inst in pairs(KeycardESPState.Cache) do
            if not inst.Parent then
                RemoveSimpleESP(KeycardESPState, inst)
                KeycardESPState.Cache[inst] = nil
            elseif not KeycardESPState.Objects[inst] then
                local data = MakeSimpleESP(inst, color, "Keycard", hrp)
                KeycardESPState.Objects[inst] = data
            else
                UpdateSimpleESP(KeycardESPState.Objects[inst], inst, color, "Keycard", hrp)
            end
        end
    end)
end

local function StopKeycardLoop()
    if KeycardESPState.Loop then
        KeycardESPState.Loop:Disconnect()
        KeycardESPState.Loop = nil
    end
    if KeycardESPState.AddedConn then
        KeycardESPState.AddedConn:Disconnect()
        KeycardESPState.AddedConn = nil
    end
    if KeycardRoomConn then
        KeycardRoomConn:Disconnect()
        KeycardRoomConn = nil
    end
end

if KeycardESPToggle then
    KeycardESPToggle:OnChanged(function(Value)
        if Value then
            StartKeycardLoop()
        else
            StopKeycardLoop()
            for inst in pairs(KeycardESPState.Objects) do RemoveSimpleESP(KeycardESPState, inst) end
        end
    end)
end


RegisterCleanup("KeycardESP", function()
    StopKeycardLoop()
    for inst in pairs(KeycardESPState.Objects) do RemoveSimpleESP(KeycardESPState, inst) end
    table.clear(KeycardESPState.Objects)
    table.clear(KeycardESPState.Cache)
    if Toggles.KeycardESPToggle then SafeSetValue(Toggles.KeycardESPToggle, false) end
end)


-- ============================================================
-- LEVER ESP
-- ============================================================
local LeverESPState = { Objects = {}, Cache = {}, Loop = nil, RoomAddedConn = nil, AddedConn = nil, RoomConn = nil }

local function IsLever(inst)
    if not inst or typeof(inst) ~= "Instance" then return false end
    if not inst:IsA("Model") then return false end
    return inst.Name == "MainLever"
end

local function ScanLeverRoom(room)
    for _, inst in ipairs(room:GetDescendants()) do
        if IsLever(inst) then
            LeverESPState.Cache[inst] = true
        end
    end
end

local function RebuildLeverCache()
    local rooms = Workspace:FindFirstChild("CurrentRooms")
    if not rooms then return end
    for inst in pairs(LeverESPState.Cache) do
        if not inst.Parent then LeverESPState.Cache[inst] = nil end
    end
    for _, room in ipairs(rooms:GetChildren()) do
        if tonumber(room.Name) then ScanLeverRoom(room) end
    end
end

LeverESPToggle = VisualsLeft:AddToggle("LeverESPToggle", {
    Text = "Lever ESP", Default = false,
    Tooltip = "Подсвечивает рычаги."
})
LeverESPToggle = LeverESPToggle or Toggles.LeverESPToggle
if LeverESPToggle then
    LeverESPToggle:AddColorPicker("LeverESPColor", {
        Text = "Lever Color", Default = Color3.fromRGB(0, 255, 0), Transparency = 0
    })
end

local function StartLeverLoop()
    if LeverESPState.Loop then return end

    RebuildLeverCache()

    if LeverESPState.RoomAddedConn then LeverESPState.RoomAddedConn:Disconnect() end
    local rooms = Workspace:FindFirstChild("CurrentRooms")
    if rooms then
        LeverESPState.RoomAddedConn = rooms.ChildAdded:Connect(function(room)
            task.wait(0.5)
            if LeverESPToggle and LeverESPToggle.Value and tonumber(room.Name) then
                ScanLeverRoom(room)
            end
        end)
    end

    if LeverESPState.AddedConn then LeverESPState.AddedConn:Disconnect() end
    local LeverAddedQueue = {}
    local LeverAddedScheduled = false
    LeverESPState.AddedConn = Workspace.DescendantAdded:Connect(function(inst)
        if not LeverESPToggle or not LeverESPToggle.Value then return end
        if inst.Name ~= "MainLever" then return end
        table.insert(LeverAddedQueue, inst)
        if LeverAddedScheduled then return end
        LeverAddedScheduled = true
        task.delay(0.8, function()
            LeverAddedScheduled = false
            for _, obj in ipairs(LeverAddedQueue) do
                if obj.Parent then LeverESPState.Cache[obj] = true end
            end
            table.clear(LeverAddedQueue)
        end)
    end)

    if LeverESPState.RoomConn then LeverESPState.RoomConn:Disconnect() end
    local LastRoom = -1
    LeverESPState.RoomConn = LocalPlayer:GetAttributeChangedSignal("CurrentRoom"):Connect(function()
        local current = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))
        if not current or current == LastRoom then return end
        LastRoom = current
        task.wait(0.4)
        if not LeverESPToggle or not LeverESPToggle.Value then return end
        local rooms2 = Workspace:FindFirstChild("CurrentRooms")
        if not rooms2 then return end
        for _, rn in ipairs({ current, current + 1 }) do
            local r = rooms2:FindFirstChild(tostring(rn))
            if r then ScanLeverRoom(r) end
        end
    end)

    local LeverFrame = 0
    LeverESPState.Loop = RunService.Heartbeat:Connect(function()
        if not LeverESPToggle or not LeverESPToggle.Value then return end
        LeverFrame = LeverFrame + 1
        if LeverFrame % 5 ~= 0 then return end

        local color = (Library and Library.Options and Library.Options.LeverESPColor and Library.Options.LeverESPColor.Value) or Color3.fromRGB(0, 255, 0)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

        -- Чистим осиротевшие (нет в Cache, Parent = nil, или билборд уничтожен)
        for inst, data in pairs(LeverESPState.Objects) do
            if not inst.Parent
               or not LeverESPState.Cache[inst]
               or not data.Billboard
               or not data.Billboard.Parent then
                RemoveSimpleESP(LeverESPState, inst)
            end
        end

        -- Чистим дубликаты билбордов висящих на тех же позициях
        local seenPositions = {}
        for inst, data in pairs(LeverESPState.Objects) do
            if not inst.Parent then
                RemoveSimpleESP(LeverESPState, inst)
            elseif data.Billboard and data.Billboard.Parent then
                -- Позиция для дедупа: округляем до 3 студов
                local p = (inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true))
                if p then
                    local key = string.format("%d_%d_%d",
                        math.floor(p.Position.X / 3),
                        math.floor(p.Position.Y / 3),
                        math.floor(p.Position.Z / 3))
                    if seenPositions[key] then
                        -- Дубликат — убиваем
                        RemoveSimpleESP(LeverESPState, inst)
                    else
                        seenPositions[key] = true
                    end
                end
            end
        end

        -- Рисуем
        for inst in pairs(LeverESPState.Cache) do
            if not inst.Parent then
                RemoveSimpleESP(LeverESPState, inst)
                LeverESPState.Cache[inst] = nil
            elseif not LeverESPState.Objects[inst] then
                local data = MakeSimpleESP(inst, color, "Lever", hrp)
                if data then LeverESPState.Objects[inst] = data end
            else
                UpdateSimpleESP(LeverESPState.Objects[inst], inst, color, "Lever", hrp)
            end
        end
    end)
end

local function StopLeverLoop()
    if LeverESPState.Loop then
        LeverESPState.Loop:Disconnect()
        LeverESPState.Loop = nil
    end
    if LeverESPState.RoomAddedConn then
        LeverESPState.RoomAddedConn:Disconnect()
        LeverESPState.RoomAddedConn = nil
    end
    if LeverESPState.AddedConn then
        LeverESPState.AddedConn:Disconnect()
        LeverESPState.AddedConn = nil
    end
    if LeverESPState.RoomConn then
        LeverESPState.RoomConn:Disconnect()
        LeverESPState.RoomConn = nil
    end
end

if LeverESPToggle then
    LeverESPToggle:OnChanged(function(Value)
        if Value then
            StartLeverLoop()
        else
            StopLeverLoop()
            for inst in pairs(LeverESPState.Objects) do RemoveSimpleESP(LeverESPState, inst) end
        end
    end)
end

RegisterCleanup("LeverESP", function()
    StopLeverLoop()
    for inst in pairs(LeverESPState.Objects) do RemoveSimpleESP(LeverESPState, inst) end
    table.clear(LeverESPState.Objects)
    table.clear(LeverESPState.Cache)
    if Toggles.LeverESPToggle then SafeSetValue(Toggles.LeverESPToggle, false) end
end)


-- ============================================================
-- LOCKER ESP
-- ============================================================
local LockerESPState = { Objects = {}, Cache = {}, Loop = nil, AddedConn = nil }

LockerESPToggle = VisualsLeft:AddToggle("LockerESPToggle", {
    Text = "Locker ESP", Default = false,
    Tooltip = "Подсвечивает шкафчики для прятания."
})
LockerESPToggle = LockerESPToggle or Toggles.LockerESPToggle
if LockerESPToggle then
    LockerESPToggle:AddColorPicker("LockerESPColor", {
        Text = "Locker Color", Default = Color3.fromRGB(255, 170, 0), Transparency = 0
    })
end

local function IsLocker(inst)
    if not inst or not inst:IsA("Model") then return false end
    -- Ищем только HidingLocker
    local ok, mod = pcall(function() return inst:GetAttribute("Module") end)
    local isHiding = (ok and mod == "HidingLocker") or inst.Name == "HidingLocker"
    if not isHiding then return false end

    -- Должен быть ProximityPrompt — значит можно взаимодействовать
    local prompt = inst:FindFirstChild("ProximityPrompt", true)
        or inst:FindFirstChild("HidePrompt", true)
        or inst:FindFirstChild("HidingPrompt", true)
        or inst:FindFirstChildWhichIsA("ProximityPrompt", true)
    if not prompt then return false end

    return true
end

local function ScanLockerRoom(room)
    if not room then return end
    for _, inst in ipairs(room:GetDescendants()) do
        if IsLocker(inst) then
            LockerESPState.Cache[inst] = true
        end
    end
end

local function RebuildLockerCache()
    local rooms = workspace:FindFirstChild("CurrentRooms")
    if not rooms then return end
    for inst in pairs(LockerESPState.Cache) do
        if not inst.Parent then LockerESPState.Cache[inst] = nil end
    end
    for _, room in ipairs(rooms:GetChildren()) do
        if tonumber(room.Name) then ScanLockerRoom(room) end
    end
end

local function StartLockerLoop()
    if LockerESPState.Loop then return end

    RebuildLockerCache()

    if LockerESPState.AddedConn then LockerESPState.AddedConn:Disconnect() end
    local LockerAddedQueue = {}
    local LockerAddedScheduled = false
    LockerESPState.AddedConn = Workspace.DescendantAdded:Connect(function(inst)
        if not LockerESPToggle or not LockerESPToggle.Value then return end
        -- Быстрый отсев: имя HidingLocker или шанс что это Model
        if inst.Name ~= "HidingLocker" and not inst:IsA("Model") then return end
        table.insert(LockerAddedQueue, inst)
        if LockerAddedScheduled then return end
        LockerAddedScheduled = true
        task.delay(0.8, function()
            LockerAddedScheduled = false
            for _, obj in ipairs(LockerAddedQueue) do
                if obj.Parent and IsLocker(obj) then
                    LockerESPState.Cache[obj] = true
                end
            end
            table.clear(LockerAddedQueue)
        end)
    end)

    local LockerFrame = 0
    LockerESPState.Loop = RunService.Heartbeat:Connect(function()
        if not LockerESPToggle or not LockerESPToggle.Value then return end
        LockerFrame = LockerFrame + 1
        if LockerFrame % 6 ~= 0 then return end
        local color = (Library and Library.Options and Library.Options.LockerESPColor and Library.Options.LockerESPColor.Value) or Color3.fromRGB(255, 170, 0)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        local MAX_DIST = 80    -- шкафчики дальше не рисуем
        local MAX_DIST_SQ = MAX_DIST * MAX_DIST

        -- Сначала: чистим всё что далеко (включая прошлые комнаты)
        for inst, data in pairs(LockerESPState.Objects) do
            if not inst.Parent then
                RemoveSimpleESP(LockerESPState, inst)
                LockerESPState.Cache[inst] = nil
            else
                local p = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
                if p then
                    local delta = hrp.Position - p.Position
                    if delta.X*delta.X + delta.Y*delta.Y + delta.Z*delta.Z > MAX_DIST_SQ then
                        RemoveSimpleESP(LockerESPState, inst)
                    end
                end
            end
        end

        -- Потом: создаём/обновляем только близкие
        for inst in pairs(LockerESPState.Cache) do
            if not inst.Parent then
                LockerESPState.Cache[inst] = nil
            else
                local p = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
                if p then
                    local delta = hrp.Position - p.Position
                    if delta.X*delta.X + delta.Y*delta.Y + delta.Z*delta.Z <= MAX_DIST_SQ then
                        if not LockerESPState.Objects[inst] then
                            local data = MakeSimpleESP(inst, color, "Locker", hrp)
                            if data then LockerESPState.Objects[inst] = data end
                        else
                            UpdateSimpleESP(LockerESPState.Objects[inst], inst, color, "Locker", hrp)
                        end
                    end
                end
            end
        end
    end)
end

local function StopLockerLoop()
    if LockerESPState.Loop then LockerESPState.Loop:Disconnect() LockerESPState.Loop = nil end
    if LockerESPState.AddedConn then LockerESPState.AddedConn:Disconnect() LockerESPState.AddedConn = nil end
end

if LockerESPToggle then
    LockerESPToggle:OnChanged(function(Value)
        if Value then
            StartLockerLoop()
        else
            StopLockerLoop()
            for inst in pairs(LockerESPState.Objects) do RemoveSimpleESP(LockerESPState, inst) end
        end
    end)
end

RegisterCleanup("LockerESP", function()
    StopLockerLoop()
    for inst in pairs(LockerESPState.Objects) do RemoveSimpleESP(LockerESPState, inst) end
    table.clear(LockerESPState.Objects)
    table.clear(LockerESPState.Cache)
    if Toggles.LockerESPToggle then SafeSetValue(Toggles.LockerESPToggle, false) end
end)


-- ============================================================
-- ENTITY ESP + NOTIFY
-- ============================================================
local EntityESPState = { Objects = {}, Cache = {}, LastCache = 0, Loop = nil, RescanConn = nil, RoomAddedConn = nil, NotifiedRooms = {} }
getgenv().EntityESPState = EntityESPState
local EntityNames = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Список сущностей этой игры
EntityNames["Shade"] = true
EntityNames["LightBulb"] = true
EntityNames["Glare"] = true
EntityNames["Route"] = true
EntityNames["Cue"] = true

local EntityListArray = {}
for name in pairs(EntityNames) do
    table.insert(EntityListArray, name)
end
table.sort(EntityListArray)

-- ============================================================
-- ENTITY ESP
-- ============================================================
local EntityESPToggle = VisualsLeft:AddToggle("EntityESPToggle", {
    Text = "Entity ESP", Default = false,
    Tooltip = "Подсвечивает сущностей."
})
EntityESPToggle = EntityESPToggle or Toggles.EntityESPToggle
getgenv().MyHub_EntityESPToggle = EntityESPToggle
if EntityESPToggle then
    EntityESPToggle:AddColorPicker("EntityESPColor", {
        Text = "Text Color",
        Default = Color3.fromRGB(255, 0, 0),
        Transparency = 0,
    })
    EntityESPToggle:AddColorPicker("EntityESPOutlineColor", {
        Text = "Fill Color",
        Default = Color3.fromRGB(255, 0, 0),
        Transparency = 0,
    })
end

VisualsLeft:AddDropdown("EntityESPList", {
    Text = "Entity List",
    Values = EntityListArray,
    Multi = true,
    AllowNull = true,
})


RegisterCleanup("EntityESP", function()
    if EntityESPState.Loop then EntityESPState.Loop:Disconnect() EntityESPState.Loop = nil end
    for inst in pairs(EntityESPState.Objects) do RemoveSimpleESP(EntityESPState, inst) end
    table.clear(EntityESPState.Objects)
    table.clear(EntityESPState.Cache)
    if Toggles.EntityESPToggle then SafeSetValue(Toggles.EntityESPToggle, false) end
end)



-- ============================================================
-- NOTIFY ENTITY
-- ============================================================
local NotifyEntityToggle = VisualsLeft:AddToggle("NotifyEntityToggle", {
    Text = "Notify Entity", Default = false,
    Tooltip = "Уведомляет при появлении сущности."
})
NotifyEntityToggle = NotifyEntityToggle or Toggles.NotifyEntityToggle
getgenv().MyHub_NotifyEntityToggle = NotifyEntityToggle

VisualsLeft:AddDropdown("NotifyEntityList", {
    Text = "Notify List",
    Values = EntityListArray,
    Multi = true,
    AllowNull = true,
})

if NotifyEntityToggle then
    NotifyEntityToggle:OnChanged(function(Value)
        if getgenv().ShadeState then
            getgenv().ShadeState.Active = false
            getgenv().ShadeState.WasNotified = false
            getgenv().ShadeState.LastNotify = 0
        end
        -- Сбрасываем "уже уведомляли" — чтобы можно было снова ловить комнаты
        if EntityESPState and EntityESPState.NotifiedRooms then
            EntityESPState.NotifiedRooms = {}
        end
        print("[NotifyEntity] флаги сброшены (toggle:", Value, ")")
    end)
end


RegisterCleanup("NotifyEntity", function()
    if NotifyEntityToggle then SafeSetValue(NotifyEntityToggle, false) end
end)


-- ============================================================
-- ФИЛЬТРЫ
-- ============================================================
local function IsEntity(inst)
    if not inst or not inst:IsA("Model") then return false end
    for _, pl in ipairs(game:GetService("Players"):GetPlayers()) do
        if pl.Character == inst then return false end
    end
    -- Обычная лампа — не сущность
    -- Обычная лампа — не сущность. Заряженная (Shocker = true или ShockPart) — сущность
    if inst.Name == "LightBulb" then
        -- Если есть GlassShards — лампа разбилась
        if inst:FindFirstChild("GlassShards") then return false end
        -- Если есть видимая часть с именем "Shard" — тоже разбилась
        for _, c in ipairs(inst:GetDescendants()) do
            if c.Name == "Shard" then return false end
        end
        local ok, val = pcall(function() return inst:GetAttribute("Shocker") end)
        if ok and val == true then return true end
        return inst:FindFirstChild("ShockPart") ~= nil
    end
    -- Glare — особый случай: она в Workspace.Entities, активируется через атрибут
    if inst.Name == "Glare" then
        return inst:GetAttribute("glare_active") == true
    end
    return EntityNames[inst.Name] == true
end

local function ShouldShow(name)
    local opt = Library and Library.Options and Library.Options.EntityESPList
    if not opt then return false end
    local list = opt.Value
    if typeof(list) ~= "table" or not next(list) then return false end
    if list[name] then return true end
    for _, n in ipairs(list) do
        if n == name then return true end
    end
    return false
end
getgenv().MyHub_ShouldShow = ShouldShow

local function ShouldNotify(name)
    local opt = Library and Library.Options and Library.Options.NotifyEntityList
    if not opt then return false end
    local list = opt.Value
    if typeof(list) ~= "table" or not next(list) then return false end
    if list[name] then return true end
    for _, n in ipairs(list) do
        if n == name then return true end
    end
    return false
end
getgenv().MyHub_ShouldNotify = ShouldNotify

-- Сканирует ОДНУ комнату (для событий загрузки новых комнат)
local function ScanEntityRoom(room)
    if not room then return end
    local lampCount = 0
    local roomNum = tonumber(room.Name)
    -- Лампы — идём только в room.Lights (быстро)
    local lights = room:FindFirstChild("Lights")
    if lights then
        for _, lamp in ipairs(lights:GetChildren()) do
            if lamp.Name == "LightBulb" and lamp:IsA("Model") and IsEntity(lamp) then
                EntityESPState.Cache[lamp] = true
                lampCount = lampCount + 1
            end
        end
    end
    -- Остальные сущности (Route/Cue/Shade) — полный скан, но их мало
    for _, inst in ipairs(room:GetChildren()) do
        if inst.Name == "Shade" and inst:IsA("Model") and IsEntity(inst) then
            EntityESPState.Cache[inst] = true
        end
    end
    -- Notify про комнату с лампами
    if lampCount > 0 and roomNum then
        if NotifyEntityToggle and NotifyEntityToggle.Value and ShouldNotify("LightBulb") then
            if not EntityESPState.NotifiedRooms[roomNum] then
                EntityESPState.NotifiedRooms[roomNum] = true
                local text = (lampCount == 1)
                    and "1 заряженная лампочка"
                    or (tostring(lampCount) .. " заряженных лампочек")
                pcall(function()
                    Library:Notify({
                        Title = "⚡ Комната " .. tostring(roomNum),
                        Description = text,
                        Time = 5
                    })
                end)
            end
        end
    end
end

getgenv().MyHub_LampOriginalY = getgenv().MyHub_LampOriginalY or {}

local function IsLampFallen(lamp)
    if not lamp or not lamp.Parent then return true end

    -- Если есть GlassShards — лампа разбита
    if lamp:FindFirstChild("GlassShards") then return true end
    for _, c in ipairs(lamp:GetDescendants()) do
        if c.Name == "Shard" then return true end
    end

    -- Проверка через OriginalY
    local pp = lamp.PrimaryPart
    if not pp then return false end
    local currentY = pp.Position.Y
    local tracker = getgenv().MyHub_LampOriginalY
    if not tracker[lamp] then
        tracker[lamp] = currentY
        return false
    end
    return (tracker[lamp] - currentY) > 3
end


local function RebuildEntityCache()
    -- Чистим мёртвые
    local dead = {}
    for inst in pairs(EntityESPState.Cache) do
        if not inst.Parent then table.insert(dead, inst) end
    end
    for _, inst in ipairs(dead) do
        RemoveSimpleESP(EntityESPState, inst)
        EntityESPState.Cache[inst] = nil
    end

    -- Определяем cur комнату
    local roomsToScan = {}
    local rooms = workspace:FindFirstChild("CurrentRooms")
    if rooms then
        local cur = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))
        if not cur or cur <= 0 then cur = GetPlayerRoomByPos() end
        if not cur or cur <= 0 then cur = 0 end
        for _, rn in ipairs({ cur - 2, cur - 1, cur, cur + 1, cur + 2, cur + 3 }) do
            local r = rooms:FindFirstChild(tostring(rn))
            if r then table.insert(roomsToScan, r) end
        end
    end

    -- ============================================================
    -- ЧАСТЬ 1: ESP — только выбранные в Entity List (ShouldShow)
    -- ============================================================

    -- Workspace.Entities (Route/Cue/Shade и др.)
    local entities = workspace:FindFirstChild("Entities")
    if entities then
        for _, inst in ipairs(entities:GetChildren()) do
            if inst:IsA("Model") and IsEntity(inst) then
                if ShouldShow(inst.Name) then
                    EntityESPState.Cache[inst] = true
                end
            end
        end
    end

    -- Комнаты — для ESP
    for _, room in ipairs(roomsToScan) do
        for _, inst in ipairs(room:GetDescendants()) do
            if inst:IsA("Model") and IsEntity(inst) then
                if ShouldShow(inst.Name) then
                    EntityESPState.Cache[inst] = true
                end
            end
        end
    end
	end

-- ============================================================
-- ESP LOOP
-- ============================================================

local function StartEntityLoop()
    if EntityESPState.Loop then return end

    RebuildEntityCache()

    -- Следим за новыми сущностями (БЕЗ notify — он теперь в RebuildEntityCache)
    if EntityESPState.AddedConn then EntityESPState.AddedConn:Disconnect() end
    local EntityAddedQueue = {}
    local EntityAddedScheduled = false
    EntityESPState.AddedConn = workspace.DescendantAdded:Connect(function(inst)
        if not EntityESPToggle or not EntityESPToggle.Value then return end
        local n = inst.Name
        if n ~= "LightBulb" and n ~= "Route" and n ~= "Cue"
           and n ~= "Glare" and n ~= "Shade" then return end
        if not inst:IsA("Model") then return end
        table.insert(EntityAddedQueue, inst)
        if EntityAddedScheduled then return end
        EntityAddedScheduled = true
        task.delay(0.3, function()
            EntityAddedScheduled = false
            for _, obj in ipairs(EntityAddedQueue) do
                if obj.Parent and IsEntity(obj) then
                    EntityESPState.Cache[obj] = true
                end
            end
            table.clear(EntityAddedQueue)
        end)
        -- Дополнительная проверка через 1.5 сек — Shocker может выставиться позже
        if n == "LightBulb" then
            task.delay(1.5, function()
                if inst.Parent and EntityESPToggle and EntityESPToggle.Value then
                    if IsEntity(inst) then
                        EntityESPState.Cache[inst] = true
                    end
                end
            end)
        end
    end)

    -- Glare
    if EntityESPState.GlareConn then EntityESPState.GlareConn:Disconnect() end
    EntityESPState.GlareConn = RunService.Heartbeat:Connect(function()
        if not EntityESPToggle or not EntityESPToggle.Value then return end
        local ents = workspace:FindFirstChild("Entities")
        if not ents then return end
        local glare = ents:FindFirstChild("Glare")
        if not glare then return end
        if glare:GetAttribute("glare_active") == true then
            EntityESPState.Cache[glare] = true
        else
            if EntityESPState.Objects[glare] then
                RemoveSimpleESP(EntityESPState, glare)
            end
            EntityESPState.Cache[glare] = nil
        end
    end)

    -- Рескан при смене комнаты
    if EntityESPState.RoomConn then EntityESPState.RoomConn:Disconnect() end
    local LastRoom = -1
    EntityESPState.RoomConn = LocalPlayer:GetAttributeChangedSignal("CurrentRoom"):Connect(function()
        local cur = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))
        if not cur or cur == LastRoom then return end
        LastRoom = cur
        task.wait(0.4)
        if EntityESPToggle and EntityESPToggle.Value then
            RebuildEntityCache()
        end
    end)

    local Frame = 0
    EntityESPState.Loop = RunService.Heartbeat:Connect(function()
        if not EntityESPToggle or not EntityESPToggle.Value then return end
        Frame = Frame + 1
        if Frame % 2 ~= 0 then return end

        local textColor = (Library and Library.Options and Library.Options.EntityESPColor and Library.Options.EntityESPColor.Value) or Color3.fromRGB(255, 0, 0)
        local outlineColor = (Library and Library.Options and Library.Options.EntityESPOutlineColor and Library.Options.EntityESPOutlineColor.Value) or Color3.fromRGB(255, 0, 0)
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")

        -- Собираем мёртвые (включая упавшие лампы)
        local dead = {}
        for inst in pairs(EntityESPState.Cache) do
            local removeIt = false
            if not inst.Parent then
                removeIt = true
            elseif not ShouldShow(inst.Name) then
                removeIt = true
            elseif inst.Name == "LightBulb" then
                local ok, sh = pcall(function() return inst:GetAttribute("Shocker") end)
                local isCharged = (ok and sh == true) or inst:FindFirstChild("ShockPart") ~= nil

                -- Проверка: упала ли лампа (через bounding box модели)
                if isCharged and IsLampFallen(inst) then
                    isCharged = false
                end

                if not isCharged then removeIt = true end
            elseif inst.Name == "Glare" then
                if inst:GetAttribute("glare_active") ~= true then removeIt = true end
            end
            if removeIt then table.insert(dead, inst) end
        end
        for _, inst in ipairs(dead) do
            RemoveSimpleESP(EntityESPState, inst)
            EntityESPState.Cache[inst] = nil
        end

        -- Рисуем
        for inst in pairs(EntityESPState.Cache) do
            if inst.Name == "Shade" then
                -- пропускаем
            elseif not ShouldShow(inst.Name) then
                -- Не выбрано в Entity List — если висит ESP, удаляем
                if EntityESPState.Objects[inst] then
                    RemoveSimpleESP(EntityESPState, inst)
                end
            elseif not EntityESPState.Objects[inst] then
                local data = MakeEntityESP(inst, textColor, outlineColor, inst.Name, hrp)
                if data then EntityESPState.Objects[inst] = data end
            else
                UpdateEntityESP(EntityESPState.Objects[inst], inst, textColor, outlineColor, inst.Name, hrp)
            end
        end
    end)

    -- Лёгкий рескан раз в 1 сек — только лампы через папку Lights (быстро, без фризов)
    if EntityESPState.RescanConn then
        task.cancel(EntityESPState.RescanConn)
    end
    EntityESPState.RescanConn = task.spawn(function()
        while EntityESPState.Loop do
            task.wait(1)
            if not EntityESPToggle or not EntityESPToggle.Value then continue end
            local rooms = workspace:FindFirstChild("CurrentRooms")
            if not rooms then continue end
            local cur = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))
            if not cur or cur <= 0 then cur = GetPlayerRoomByPos() end
            if not cur or cur <= 0 then continue end
            for _, rn in ipairs({ cur - 1, cur, cur + 1, cur + 2 }) do
                local room = rooms:FindFirstChild(tostring(rn))
                if room then
                    local lights = room:FindFirstChild("Lights")
                    if lights then
                        for _, lamp in ipairs(lights:GetChildren()) do
                            if lamp.Name == "LightBulb" and not EntityESPState.Cache[lamp] then
                                if IsEntity(lamp) then
                                    EntityESPState.Cache[lamp] = true
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
end

-- ============================================================
-- NOTIFY LOOP (независим от Entity ESP)
-- ============================================================
local NotifyLastTick = 0

local function StartNotifyLoop()
    if EntityESPState.NotifyLoop then return end
    EntityESPState.NotifyLoop = RunService.Heartbeat:Connect(function()
        if not NotifyEntityToggle or not NotifyEntityToggle.Value then return end
        if not ShouldNotify("LightBulb") then return end

        local now = tick()
        if now - NotifyLastTick < 1 then return end
        NotifyLastTick = now

        local rooms = workspace:FindFirstChild("CurrentRooms")
        if not rooms then return end

        local cur = tonumber(LocalPlayer:GetAttribute("CurrentRoom"))
        if not cur or cur <= 0 then cur = GetPlayerRoomByPos() end
        if not cur or cur <= 0 then return end

        for _, rn in ipairs({ cur, cur + 1, cur + 2 }) do
            local room = rooms:FindFirstChild(tostring(rn))
            if room then
                local lights = room:FindFirstChild("Lights")
                if lights then
                    local count = 0
                    for _, lamp in ipairs(lights:GetChildren()) do
                        if lamp.Name == "LightBulb" and lamp:IsA("Model") then
                            if IsEntity(lamp) and not IsLampFallen(lamp) then
                                count = count + 1
                            end
                        end
                    end
                    if count > 0 and not EntityESPState.NotifiedRooms[rn] then
                        EntityESPState.NotifiedRooms[rn] = true
                        local text = (count == 1)
                            and "1 заряженная лампочка"
                            or (tostring(count) .. " заряженных лампочек")
                        pcall(function()
                            Library:Notify({
                                Title = "⚡ Комната " .. tostring(rn),
                                Description = text,
                                Time = 5
                            })
                        end)
                    end
                end
            end
        end
    end)
end

local function StopNotifyLoop()
    if EntityESPState.NotifyLoop then
        EntityESPState.NotifyLoop:Disconnect()
        EntityESPState.NotifyLoop = nil
    end
end

task.spawn(function()
    task.wait(1)
    StartNotifyLoop()
end)

local function StopEntityLoop()
    if EntityESPState.Loop then
        EntityESPState.Loop:Disconnect()
        EntityESPState.Loop = nil
    end
    if EntityESPState.RescanConn then
        task.cancel(EntityESPState.RescanConn)
        EntityESPState.RescanConn = nil
    end
    if EntityESPState.RoomAddedConn then
        EntityESPState.RoomAddedConn:Disconnect()
        EntityESPState.RoomAddedConn = nil
    end
    if EntityESPState.AddedConn then
        EntityESPState.AddedConn:Disconnect()
        EntityESPState.AddedConn = nil
    end
    if EntityESPState.RoomConn then
        EntityESPState.RoomConn:Disconnect()
        EntityESPState.RoomConn = nil
    end
end

if EntityESPToggle then
    EntityESPToggle:OnChanged(function(Value)
        if Value then
            StartEntityLoop()
        else
            StopEntityLoop()
            for inst in pairs(EntityESPState.Objects) do RemoveSimpleESP(EntityESPState, inst) end
        end
    end)
end

-- ============================================================
-- SHADE ESP + NOTIFY (через модель Workspace.CurrentRooms.<N>.Shade)
-- ============================================================
local ShadeState = {
    Active = false,
    LastNotify = 0,
    WasNotified = false,
    ColoredDoors = {},
    CurrentModel = nil,
}
getgenv().ShadeState = ShadeState

local function FindShadeModel()
    local rooms = workspace:FindFirstChild("CurrentRooms")
    if not rooms then return nil end
    for _, room in ipairs(rooms:GetChildren()) do
        local shade = room:FindFirstChild("Shade")
        if shade and shade:IsA("Model") then
            return shade, room
        end
    end
    return nil
end

local function GetShadePosition(shadeModel)
    if not shadeModel then return nil end
    local pp = shadeModel.PrimaryPart or shadeModel:FindFirstChildWhichIsA("BasePart", true)
    if pp then return pp.Position end
    return nil
end

-- Красит ближайшую к Shade дверь в красный
local function ApplyShadeHighlight(shadeModel)
    local shadePos = GetShadePosition(shadeModel)
    if not shadePos then return end

    -- Ищем ближайшую дверь из DoorESPState.Cache
    local nearest, nearestDist = nil, math.huge
    for folder, info in pairs(DoorESPState.Cache) do
        if info.Center then
            local d = (info.Center - shadePos).Magnitude
            if d < nearestDist then
                nearestDist = d
                nearest = { folder = folder, info = info }
            end
        end
    end

    if not nearest or nearestDist > 150 then
        return  -- дверь слишком далеко от Shade
    end

    local folder = nearest.folder
    local data = DoorESPState.Objects[folder]

    -- Принудительно создаём ESP если нет
    if not data then
        pcall(AddDoorESP, folder, Color3.fromRGB(255, 30, 30), nearest.info)
        data = DoorESPState.Objects[folder]
    end

    if data then
        local shadeTextColor = (Library and Library.Options and Library.Options.EntityESPColor
            and Library.Options.EntityESPColor.Value) or Color3.fromRGB(255, 0, 0)
        local shadeFillColor = (Library and Library.Options and Library.Options.EntityESPOutlineColor
            and Library.Options.EntityESPOutlineColor.Value) or Color3.fromRGB(255, 0, 0)

        for _, hl in ipairs(data.Highlights) do
            hl.FillColor = shadeFillColor
            hl.OutlineColor = shadeFillColor
            hl.FillTransparency = 0.6
        end
        data.Label.TextColor3 = shadeTextColor

        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local dist = "?"
        if hrp then
            dist = math.floor((hrp.Position - data.Anchor.Position).Magnitude)
        end
        data.Label.Text = "Shade " .. tostring(nearest.info.DisplayRoom or "?") .. " [" .. dist .. "]"
        data.ShadeHighlight = true
        ShadeState.ColoredDoors[folder] = true
    end
end

local function ClearShadeHighlight()
    for folder in pairs(ShadeState.ColoredDoors) do
        local data = DoorESPState.Objects[folder]
        if data then data.ShadeHighlight = nil end
    end
    ShadeState.ColoredDoors = {}
end

local function NotifyShade(shadeModel, shadeRoom)
    print("[NotifyShade] вызвана. Toggle:", 
        NotifyEntityToggle and NotifyEntityToggle.Value, 
        "| WasNotified:", ShadeState.WasNotified)

    if not NotifyEntityToggle or not NotifyEntityToggle.Value then 
        print("[NotifyShade] отмена: NotifyEntityToggle выключен")
        return 
    end

    -- Проверка что Shade в списке Notify (словарь Obsidian)
    local opt = Library and Library.Options and Library.Options.NotifyEntityList
    local list = opt and opt.Value
    local hasShade = false
    if typeof(list) == "table" then
        if list["Shade"] then
            hasShade = true
        else
            for _, n in ipairs(list) do
                if n == "Shade" then hasShade = true break end
            end
        end
    end
    print("[NotifyShade] hasShade:", hasShade, "| list:", typeof(list))

    if not hasShade then 
        print("[NotifyShade] отмена: Shade не выбран в Notify List")
        return 
    end

    if ShadeState.WasNotified then 
        print("[NotifyShade] отмена: уже уведомляли")
        return 
    end
    if tick() - ShadeState.LastNotify < 5 then 
        print("[NotifyShade] отмена: кулдаун")
        return 
    end
    ShadeState.LastNotify = tick()
    ShadeState.WasNotified = true

    local roomName = shadeRoom and shadeRoom.Name or "?"
    local msg = "Shade в комнате " .. tostring(roomName)
    print("[NotifyShade] отправляем уведомление:", msg)
    pcall(function()
        Library:Notify({ Title = "⚠ SHADE", Description = msg, Time = 5 })
    end)
    print("[SHADE] Notify sent | room:", tostring(roomName))
end

local ShadeWatchConn = nil

local function StartShadeWatch()
    if ShadeWatchConn then ShadeWatchConn:Disconnect() end
    -- Форс-сброс при старте
    ShadeState.Active = false
    ShadeState.WasNotified = false
    ShadeState.LastNotify = 0
    ShadeWatchConn = RunService.Heartbeat:Connect(function()
        local shadeModel, shadeRoom = FindShadeModel()

        -- ESP: привязано к Entity ESP + Shade в Entity List
        local espOn = EntityESPToggle and EntityESPToggle.Value
        local optE = Library and Library.Options and Library.Options.EntityESPList
        local list = optE and optE.Value
        local shadeInESP = false
        if typeof(list) == "table" then
            -- Obsidian хранит Multi-dropdown как словарь {["Shade"]=true}, а не массив
            if list["Shade"] then
                shadeInESP = true
            else
                -- fallback на массив, если структура другая
                for _, n in ipairs(list) do
                    if n == "Shade" then shadeInESP = true break end
                end
            end
        end

        if shadeModel and espOn and shadeInESP then
            ApplyShadeHighlight(shadeModel)
        else
            if next(ShadeState.ColoredDoors) ~= nil then
                ClearShadeHighlight()
            end
        end

        -- NOTIFY
        if shadeModel then
            if not ShadeState.Active then
                ShadeState.Active = true
                ShadeState.WasNotified = false
                NotifyShade(shadeModel, shadeRoom)
            end
        else
            ShadeState.Active = false
            ShadeState.WasNotified = false
        end
    end)
end

StartShadeWatch()



-- ============================================================
-- GLARE NOTIFY (следим за glare_active)
-- ============================================================
local GlareWasActive = false
local GlareLastNotify = 0

local GlareWatchConn = nil

-- Проверка: явно ли Glare выбран в NotifyEntityList
local function IsGlareSelected()
    local opt = Library and Library.Options and Library.Options.NotifyEntityList
    if not opt then return false end
    local list = opt.Value
    if typeof(list) ~= "table" then return false end
    if list["Glare"] then return true end
    for _, n in ipairs(list) do
        if n == "Glare" then return true end
    end
    return false
end

local function StartGlareWatch()
    if GlareWatchConn then GlareWatchConn:Disconnect() end
    GlareWatchConn = RunService.Heartbeat:Connect(function()
        if not NotifyEntityToggle or not NotifyEntityToggle.Value then
            GlareWasActive = false
            return
        end
        if not IsGlareSelected() then
            GlareWasActive = false
            return
        end

        local ents = workspace:FindFirstChild("Entities")
        if not ents then return end
        local glare = ents:FindFirstChild("Glare")
        if not glare then return end

        local active = glare:GetAttribute("glare_active") == true

        if active and not GlareWasActive then
            GlareWasActive = true
            if tick() - GlareLastNotify > 5 then
                GlareLastNotify = tick()
                local room = glare:GetAttribute("Room")
                local msg = "Glare активна"
                if room then msg = msg .. " | Комната: " .. tostring(room) end
                pcall(function()
                    Library:Notify({ Title = "⚠ GLARE", Description = msg, Time = 5 })
                end)
                print("[GLARE] Notify sent | room:", tostring(room))
            end
        elseif not active and GlareWasActive then
            GlareWasActive = false
        end
    end)
end

StartGlareWatch()
end

-- ============================================================
-- ROUTE + CUE NOTIFY
-- ============================================================
local RouteCueWatchConn = nil

local function HandleRouteCue(inst, entityName)
    if not inst or not inst.Parent then return end

    local EET = getgenv().MyHub_EntityESPToggle
    local NET = getgenv().MyHub_NotifyEntityToggle
    local SS  = getgenv().MyHub_ShouldShow
    local SN  = getgenv().MyHub_ShouldNotify

    print("[RouteCue]", entityName,
        "| EE:", tostring(EET and EET.Value),
        "| NE:", tostring(NET and NET.Value),
        "| Show:", tostring(SS and SS(entityName)),
        "| Notify:", tostring(SN and SN(entityName)))

    -- Notify
    if NET and NET.Value and SN and SN(entityName) then
        if inst:GetAttribute("MyHub_Notified") then return end
        inst:SetAttribute("MyHub_Notified", true)

        local target = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
        local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        local dist = "?"
        if hrp and target then
            dist = math.floor((hrp.Position - target.Position).Magnitude)
        end

        pcall(function()
            Library:Notify({
                Title = "⚠ " .. entityName:upper(),
                Description = "Появился | " .. tostring(dist) .. " studs",
                Time = 5
            })
        end)
    end
end

local function StartRouteCueWatch()
    if RouteCueWatchConn then RouteCueWatchConn:Disconnect() end

    RouteCueWatchConn = workspace.DescendantAdded:Connect(function(inst)
        local name = inst.Name
        if name ~= "Route" and name ~= "Cue" then return end
        task.wait(0.3)
        if not inst.Parent then return end
        HandleRouteCue(inst, name)
    end)

    local ents = workspace:FindFirstChild("Entities")
    if ents then
        for _, inst in ipairs(ents:GetChildren()) do
            if inst.Name == "Route" or inst.Name == "Cue" then
                HandleRouteCue(inst, inst.Name)
            end
        end
    end
end

StartRouteCueWatch()



do
-- ==== Timer (правая колонка Visuals) ====

-- UI таймера на экране
local ShiverUI = Instance.new("ScreenGui")
ShiverUI.Name = "MyHub_ShiverTimer"
ShiverUI.ResetOnSpawn = false
ShiverUI.IgnoreGuiInset = true
ShiverUI.Parent = CoreGui

local ShiverLabel = Instance.new("TextLabel")
ShiverLabel.Name = "ShiverLabel"
ShiverLabel.AnchorPoint = Vector2.new(0.5, 0.5)
ShiverLabel.Position = UDim2.new(0.5, 0, 0.08, 0)
ShiverLabel.Size = UDim2.new(0, 300, 0, 40)
ShiverLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
ShiverLabel.BackgroundTransparency = 0.3
ShiverLabel.BorderSizePixel = 0
ShiverLabel.Font = Enum.Font.GothamBold
ShiverLabel.TextSize = 22
ShiverLabel.TextColor3 = Color3.fromRGB(120, 200, 255)
ShiverLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
ShiverLabel.TextStrokeTransparency = 0.3
ShiverLabel.Text = "COLDNESS: 100%"
ShiverLabel.Visible = false
ShiverLabel.Parent = ShiverUI


local ShiverPosX = 50
local ShiverPosY = 8

local function ApplyShiverPosition()
    ShiverLabel.Position = UDim2.new(ShiverPosX / 100, 0, ShiverPosY / 100, 0)
end
ApplyShiverPosition()

-- Надёжное чтение значения слайдера (любой способ сработает)
local function GetSliderValue(sliderObj, key, fallback)
    if sliderObj and sliderObj.Value ~= nil then return sliderObj.Value end
    if SliderRefs[key] and SliderRefs[key].Value ~= nil then return SliderRefs[key].Value end
    if Library and Library.Options and Library.Options[key] then
        local v = Library.Options[key].Value
        if typeof(v) == "number" then return v end
    end
    if _G.Options and _G.Options[key] then
        local v = _G.Options[key].Value
        if typeof(v) == "number" then return v end
    end
    return fallback
end


local ShiverCorner = Instance.new("UICorner")
ShiverCorner.CornerRadius = UDim.new(0, 6)
ShiverCorner.Parent = ShiverLabel

local VisualsRight = Tabs.Visuals:AddRightGroupbox("Screen")

-- ============================================================
-- FREE CAMERA
-- ============================================================
local FreeCamState = {
    Enabled = false,
    Conn = nil,
    CameraCFrame = nil,
    SavedCharWalkSpeed = nil,
    SavedCharJumpPower = nil,
    SavedCharJumpHeight = nil,
    LastCamPos = nil,
    SavedHRPCFrame = nil,
    SavedAutoRotate = nil,
    SavedCameraSubject = nil,
    BodyLockConn = nil,
    SavedBodyCFrames = {},
    AnimatorWasEnabled = nil,
}

-- ============================================================
-- FREE CAMERA — UI в правильном порядке
-- ============================================================

-- 1. Тоггл
local FreeCameraToggle = VisualsRight:AddToggle("FreeCameraToggle", {
    Text = "FreeCamera",
    Default = false,
    Tooltip = "Свободная камера. WASD — движение, Space/Ctrl — вверх/вниз, Shift — ускорение.",
})
FreeCameraToggle = FreeCameraToggle or (Toggles and Toggles.FreeCameraToggle)

-- 2. Keybind (G по умолчанию)
if FreeCameraToggle and FreeCameraToggle.AddKeyPicker then
    FreeCameraToggle:AddKeyPicker("FreeCameraKeybind", {
        Default = "G",
        Mode = "Toggle",
        SyncToggleState = true,
        Text = "FreeCamera",
        NoUI = false,
    })
end

getgenv().RegisterKeyBind("FreeCamera", "FreeCamera", function()
    local kp = Library and Library.Options and Library.Options.FreeCameraKeybind
    if kp then
        if kp.ValueString then return kp.ValueString end
        if kp.Value then return tostring(kp.Value) end
    end
    return "G"
end, function()
    return FreeCameraToggle and FreeCameraToggle.Value == true
end, FreeCameraToggle, Library and Library.Options and Library.Options.FreeCameraKeybind)

-- 3. Dropdown режимов
local FreeCamModeDropdown = VisualsRight:AddDropdown("FreeCamMode", {
    Text = "Mode",
    Values = { "Smooth", "Instant" },
    Multi = true,
    AllowNull = true,
    Default = { "Smooth" },
})
FreeCamModeDropdown = FreeCamModeDropdown or (Options and Options.FreeCamMode)

-- 4. Слайдер скорости (теперь ВНИЗУ)
local FreeCamSpeedSlider = AddResettableSlider(VisualsRight, "FreeCamSpeed", {
    Text = "Camera Speed",
    Min = 5, Max = 200, Default = 50,
    Rounding = 0, Compact = true,
})

local function FreeCam_GetSpeed()
    if FreeCamSpeedSlider and FreeCamSpeedSlider.Value then
        return FreeCamSpeedSlider.Value
    end
    if SliderRefs and SliderRefs.FreeCamSpeed and SliderRefs.FreeCamSpeed.Value then
        return SliderRefs.FreeCamSpeed.Value
    end
    return 50
end

-- Хелпер: получить выбранные режимы как массив
local function FreeCam_GetModes()
    local result = { Smooth = false, Instant = false }
    local opt = Library and Library.Options and Library.Options.FreeCamMode
    local val = opt and opt.Value
    if typeof(val) ~= "table" then return result end

    if val["Smooth"] or (type(val[1]) == "string" and table.find(val, "Smooth")) then
        result.Smooth = true
    end
    if val["Instant"] or (type(val[1]) == "string" and table.find(val, "Instant")) then
        result.Instant = true
    end
    -- Fallback: если val — массив строк
    for _, v in ipairs(val) do
        if v == "Smooth" then result.Smooth = true end
        if v == "Instant" then result.Instant = true end
    end
    return result
end

local FreeCam_LastToggled = "Smooth"   -- какой был активен ДО текущего изменения

if FreeCamModeDropdown then
    FreeCamModeDropdown:OnChanged(function(value)
        local modes = FreeCam_GetModes()

        -- Если оба Smooth и Instant включены — оставляем ТОЛЬКО что включённый
        if modes.Smooth and modes.Instant then
            local keep = nil
            if FreeCam_LastToggled == "Smooth" then
                keep = "Instant"
            elseif FreeCam_LastToggled == "Instant" then
                keep = "Smooth"
            else
                keep = "Smooth"
            end

            local newVal = {}
            if keep == "Instant" then
                newVal.Instant = true
            else
                newVal.Smooth = true
            end

            FreeCam_LastToggled = keep

            task.defer(function()
                pcall(function() FreeCamModeDropdown:SetValue(newVal) end)
            end)
            return
        end

        if modes.Smooth and not modes.Instant then
            FreeCam_LastToggled = "Smooth"
        elseif modes.Instant and not modes.Smooth then
            FreeCam_LastToggled = "Instant"
        end
    end)
end

-- Обработка движения мыши для FreeCam (свой контроллер)
local FreeCamMouseConn = nil
local FreeCamYaw = 0
local FreeCamPitch = 0
local FreeCamSensitivity = 0.3

local function FreeCam_StartMouseTracking()
    if FreeCamMouseConn then FreeCamMouseConn:Disconnect() end

    local cam = workspace.CurrentCamera
    if not cam then return end

    -- Инициализируем yaw/pitch от текущего направления камеры
    local cf = cam.CFrame
    local look = cf.LookVector
    FreeCamYaw = math.atan2(-look.X, -look.Z)
    FreeCamPitch = math.asin(look.Y)

    FreeCamMouseConn = UserInputService.InputChanged:Connect(function(input, gpe)
        if gpe then return end
        if not FreeCamState.Enabled then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement then
            local sens = FreeCamSensitivity / 100
            FreeCamYaw = FreeCamYaw - input.Delta.X * sens
            FreeCamPitch = math.clamp(FreeCamPitch - input.Delta.Y * sens, -math.rad(89), math.rad(89))
        end
    end)
end

local function FreeCam_StopMouseTracking()
    if FreeCamMouseConn then
        FreeCamMouseConn:Disconnect()
        FreeCamMouseConn = nil
    end
end

-- Обновление CFrame камеры по вводу
local function FreeCam_UpdateCamera(dt)
    local cam = workspace.CurrentCamera
    if not cam then return end

    local speed = FreeCam_GetSpeed()
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then
        speed = speed * 3
    end

    -- Строим CFrame из yaw/pitch (не из cam.CFrame — иначе мышь не работает)
    local rotCF = CFrame.fromEulerAnglesYXZ(FreeCamPitch, FreeCamYaw, 0)
    local current = CFrame.new(FreeCamState.CameraCFrame and FreeCamState.CameraCFrame.Position or cam.CFrame.Position) * rotCF

    local move = Vector3.zero
    local look = rotCF.LookVector
    local right = rotCF.RightVector
    local up = Vector3.new(0, 1, 0)

    if UserInputService:IsKeyDown(Enum.KeyCode.W) then move = move + look end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then move = move - look end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then move = move - right end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then move = move + right end
    if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move = move + up end
    if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move = move - up end

    if move.Magnitude > 0 then
        current = current + move.Unit * speed * dt
    end

    FreeCamState.CameraCFrame = current
    cam.CFrame = current
end

-- Кэш prompts (обновляется редко)
local FreeCam_PromptCache = {}
local FreeCam_PromptCacheDirty = true
local FreeCam_PromptWatcherConn = nil

local function FreeCam_InitPromptCache()
    if FreeCam_PromptWatcherConn then return end
    -- Обновляем кэш раз в 2 секунды (не каждый тик!)
    task.spawn(function()
        while true do
            task.wait(2)
            if not FreeCamState.Enabled then continue end
            local newCache = {}
            for _, obj in ipairs(workspace:GetDescendants()) do
                if obj:IsA("ProximityPrompt") and obj.Parent then
                    table.insert(newCache, obj)
                end
            end
            FreeCam_PromptCache = newCache
        end
    end)
    FreeCam_PromptWatcherConn = true
end

-- Enable
local function FreeCam_Enable()
    if FreeCamState.Enabled then return end
    FreeCamState.Enabled = true

    local cam = workspace.CurrentCamera
    if not cam then return end

    -- Стартуем с текущего CFrame камеры
    FreeCamState.CameraCFrame = cam.CFrame

    -- === ФИКСАЦИЯ ТЕЛА ===
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")

    if hum and hrp then
        -- Запоминаем текущий CFrame тела ДО отвязки
        FreeCamState.SavedHRPCFrame = hrp.CFrame
        FreeCamState.SavedAutoRotate = hum.AutoRotate
        FreeCamState.SavedCameraSubject = cam.CameraSubject

        -- Отключаем автоповорот — Humanoid больше не подстраивает тело под камеру
        hum.AutoRotate = false

        -- Отвязываем камеру от персонажа
        cam.CameraSubject = nil
    end

    -- Переводим камеру в Scriptable (ты сам ей управляешь)
    cam.CameraType = Enum.CameraType.Scriptable
	
	    getgenv().FreeCamActive = true
		
		    -- Подтягиваем тело к камере, чтобы fireproximityprompt проходил серверную проверку
    if FreeCamState.HRP then
        FreeCamState.HRP.CFrame = CFrame.new(cam.CFrame.Position)
        FreeCamState.HRP.AssemblyLinearVelocity = Vector3.zero
    end

    -- Стартуем mouse-tracking
    FreeCam_StartMouseTracking()

    -- СТОП персонажу (полный)
    local char = LP.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hum then
            FreeCamState.SavedCharWalkSpeed = hum.WalkSpeed
            FreeCamState.SavedCharJumpPower = hum.JumpPower
            FreeCamState.SavedCharJumpHeight = hum.JumpHeight
            hum.WalkSpeed = 0
            hum.JumpPower = 0
            hum.JumpHeight = 0
        end
        -- Дополнительно: жёстко стопаем движение каждый кадр
        if hrp then
            FreeCamState.HRP = hrp
            FreeCamState.SavedHRPVelocity = hrp.AssemblyLinearVelocity
        end
    end
	
    -- Сохраняем CFrame всех частей + отключаем Animator (не Motor6D!)
    FreeCamState.SavedBodyCFrames = {}
    if char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                FreeCamState.SavedBodyCFrames[part] = part.CFrame
            end
        end

        -- НЕ отключаем Animator — просто останавливаем треки каждый кадр
        -- (это безопасно, анимации восстановятся сами)
    end

    -- === ФИКСАЦИЯ ТЕЛА (RenderStepped + обнуление Motor6D.Transform) ===
    if FreeCamState.BodyLockConn then
        FreeCamState.BodyLockConn:Disconnect()
    end
    FreeCamState.BodyLockConn = RunService.RenderStepped:Connect(function()
        if not FreeCamState.Enabled then return end
        local c = LP.Character
        if not c then return end
        local hum = c:FindFirstChildOfClass("Humanoid")
        local hrp = c:FindFirstChild("HumanoidRootPart")
        if not hum or not hrp then return end

        -- 1. Стоп движения
        if hum.WalkSpeed ~= 0 then hum.WalkSpeed = 0 end
        if hum.AutoRotate ~= false then hum.AutoRotate = false end
        hum:Move(Vector3.zero, false)

        -- 2. Обнуляем Transform у ВСЕХ Motor6D — сбрасываем анимации в нулевую позу
        -- (Motor6D остаются включёнными, скелет не рвётся, но поза становится базовой)
        for _, motor in ipairs(c:GetDescendants()) do
            if motor:IsA("Motor6D") and motor.Transform ~= CFrame.new() then
                motor.Transform = CFrame.new()
            end
        end

        -- 3. Фиксируем HRP
        if FreeCamState.SavedHRPCFrame then
            hrp.CFrame = FreeCamState.SavedHRPCFrame
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
        end

        -- Останавливаем анимации — но НЕ отключаем Animator, чтобы после FreeCam они сами восстановились
        local animator = c:FindFirstChildOfClass("Animator")
        if animator then
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                if track.IsPlaying then
                    track:Stop(0)
                end
            end
        end
    end)

    -- Главный loop для камеры
    local lastTick = tick()
    FreeCamState.Conn = RunService.RenderStepped:Connect(function()
        if not FreeCamState.Enabled then return end
        local now = tick()
        local dt = now - lastTick
        if dt > 0.1 then dt = 0.1 end
        lastTick = now

        FreeCam_UpdateCamera(dt)
    end)
	
	    -- Инициализируем кэш prompts для Cheat mode
    FreeCam_InitPromptCache()

    print("[FreeCamera] === ON ===")
end

-- Disable
local function FreeCam_Disable()
    if not FreeCamState.Enabled then return end
    FreeCamState.Enabled = false
    getgenv().FreeCamActive = false

    if FreeCamState.Conn then
        FreeCamState.Conn:Disconnect()
        FreeCamState.Conn = nil
    end
    -- Отключаем фиксацию тела
    if FreeCamState.BodyLockConn then
        FreeCamState.BodyLockConn:Disconnect()
        FreeCamState.BodyLockConn = nil
    end

    -- Снимаем Anchored со всех частей
    local charForUnanchor = LP.Character
    if charForUnanchor then
        for _, part in ipairs(charForUnanchor:GetDescendants()) do
            if part:IsA("BasePart") and part.Anchored then
                part.Anchored = false
            end
        end
    end
    FreeCamState.SavedBodyCFrames = nil

    -- Возвращаем AutoRotate и CameraSubject
    local char = LP.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local cam = workspace.CurrentCamera

    if hum and FreeCamState.SavedAutoRotate ~= nil then
        hum.AutoRotate = FreeCamState.SavedAutoRotate
    end
    if cam and FreeCamState.SavedCameraSubject ~= nil then
        cam.CameraSubject = FreeCamState.SavedCameraSubject
    elseif cam and hum then
        cam.CameraSubject = hum
    end

    FreeCamState.SavedHRPCFrame = nil
    FreeCamState.SavedAutoRotate = nil
    FreeCamState.SavedCameraSubject = nil

    local cam = workspace.CurrentCamera
    local modes = FreeCam_GetModes()

    -- Возврат камеры
    local char = LP.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")

    if cam and hrp then
        if modes.Instant then
            -- Мгновенно
            cam.CameraType = Enum.CameraType.Custom
            cam.CFrame = CFrame.new(hrp.Position + Vector3.new(0, 2, 0)) * (cam.CFrame - cam.CFrame.Position)
        elseif modes.Smooth then
            -- Плавно: от текущей позиции к персонажу за ~0.4 сек
            local startCF = cam.CFrame
            local startPos = startCF.Position
            local endPos = hrp.Position + Vector3.new(0, 2, 0)
            local startTick = tick()
            local duration = 0.4

            local smoothConn
            smoothConn = RunService.RenderStepped:Connect(function()
                local elapsed = tick() - startTick
                local a = math.clamp(elapsed / duration, 0, 1)
                a = a * a * (3 - 2 * a)   -- smoothstep

                local newPos = startPos:Lerp(endPos, a)
                if cam then
                    cam.CFrame = CFrame.new(newPos) * (startCF - startCF.Position)
                end

                if a >= 1 then
                    smoothConn:Disconnect()
                    if cam then
                        cam.CameraType = Enum.CameraType.Custom
                    end
                end
            end)

            -- Если рендер не идёт (например, скрипт свернулся) — таймаут
            task.delay(duration + 0.5, function()
                if smoothConn then
                    smoothConn:Disconnect()
                    if cam then
                        cam.CameraType = Enum.CameraType.Custom
                    end
                end
            end)
        else
            -- Ничего не выбрано — мгновенный возврат по умолчанию
            cam.CameraType = Enum.CameraType.Custom
        end
    elseif cam then
        cam.CameraType = Enum.CameraType.Custom
    end

    -- Восстановление WalkSpeed
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            if FreeCamState.SavedCharWalkSpeed then
                hum.WalkSpeed = FreeCamState.SavedCharWalkSpeed
            else
                hum.WalkSpeed = 15
            end
        end
    end

    FreeCamState.CameraCFrame = nil
    FreeCamState.SavedCharWalkSpeed = nil

    print("[FreeCamera] === OFF ===")
end

if FreeCameraToggle then
    FreeCameraToggle:OnChanged(function(Value)
        if Value then
            FreeCam_Enable()
        else
            FreeCam_Disable()
        end
    end)
end

RegisterCleanup("FreeCamera", function()
    pcall(FreeCam_Disable)
    if Toggles and Toggles.FreeCameraToggle then
        SafeSetValue(Toggles.FreeCameraToggle, false)
    end
end)

-- ============================================================
-- FULLBRIGHT (независимая копия в Screen)
-- ============================================================
local FB_Screen = { Saved = false, Conn = nil }
local Lighting_S = game:GetService("Lighting")

local FullbrightToggleScreen = VisualsRight:AddToggle("FullbrightToggleScreen", {
    Text = "Fullbright", Default = false,
    Tooltip = "Освещает всё пространство."
})
FullbrightToggleScreen = FullbrightToggleScreen or Toggles.FullbrightToggleScreen

local FullbrightBrightnessScreen = AddResettableSlider(VisualsRight, "FullbrightBrightnessScreen", {
    Text = "Brightness",
    Min = 0, Max = 10, Default = 2,
    Rounding = 1, Compact = true
})

local function FB_Save()
    if FB_Screen.Saved then return end
    FB_Screen.Ambient        = Lighting_S.Ambient
    FB_Screen.OutdoorAmbient = Lighting_S.OutdoorAmbient
    FB_Screen.Brightness     = Lighting_S.Brightness
    FB_Screen.ClockTime      = Lighting_S.ClockTime
    FB_Screen.GlobalShadows  = Lighting_S.GlobalShadows
    FB_Screen.FogEnd         = Lighting_S.FogEnd
    FB_Screen.FogStart       = Lighting_S.FogStart
    FB_Screen.EnvDiff        = Lighting_S.EnvironmentDiffuseScale
    FB_Screen.EnvSpec        = Lighting_S.EnvironmentSpecularScale
    FB_Screen.Saved = true
end

local function FB_Restore()
    if not FB_Screen.Saved then return end
    Lighting_S.Ambient        = FB_Screen.Ambient
    Lighting_S.OutdoorAmbient = FB_Screen.OutdoorAmbient
    Lighting_S.Brightness     = FB_Screen.Brightness
    Lighting_S.ClockTime      = FB_Screen.ClockTime
    Lighting_S.GlobalShadows  = FB_Screen.GlobalShadows
    Lighting_S.FogEnd         = FB_Screen.FogEnd
    Lighting_S.FogStart       = FB_Screen.FogStart
    Lighting_S.EnvironmentDiffuseScale  = FB_Screen.EnvDiff
    Lighting_S.EnvironmentSpecularScale = FB_Screen.EnvSpec
end

local function FB_Apply()
    local bri = 2
    if FullbrightBrightnessScreen and FullbrightBrightnessScreen.Value then
        bri = FullbrightBrightnessScreen.Value
    end
    Lighting_S.Ambient        = Color3.fromRGB(200, 200, 200)
    Lighting_S.OutdoorAmbient = Color3.fromRGB(200, 200, 200)
    Lighting_S.Brightness     = bri
    Lighting_S.ClockTime      = 12
    Lighting_S.GlobalShadows  = false
    Lighting_S.FogEnd         = 100000
    Lighting_S.FogStart       = 0
    Lighting_S.EnvironmentDiffuseScale  = 1
    Lighting_S.EnvironmentSpecularScale = 1
    for _, v in ipairs(Lighting_S:GetChildren()) do
        if v:IsA("Atmosphere") then v.Density = 0 end
    end
end

if FullbrightToggleScreen then
    FullbrightToggleScreen:OnChanged(function(v)
        if v then
            FB_Save()
            FB_Apply()
            if FB_Screen.Conn then FB_Screen.Conn:Disconnect() end
            FB_Screen.Conn = RunService.RenderStepped:Connect(function()
                if not FullbrightToggleScreen.Value then return end
                FB_Apply()
            end)
        else
            if FB_Screen.Conn then FB_Screen.Conn:Disconnect() FB_Screen.Conn = nil end
            FB_Restore()
        end
    end)
end

if FullbrightBrightnessScreen then
    FullbrightBrightnessScreen:OnChanged(function()
        if FullbrightToggleScreen and FullbrightToggleScreen.Value then
            FB_Apply()
        end
    end)
end

RegisterCleanup("FullbrightScreen", function()
    if FB_Screen.Conn then FB_Screen.Conn:Disconnect() FB_Screen.Conn = nil end
    FB_Restore()
    if Toggles and Toggles.FullbrightToggleScreen then SafeSetValue(Toggles.FullbrightToggleScreen, false) end
end)

local ShiverTimerToggle = VisualsRight:AddToggle("ShiverTimerToggle", {
    Text = "Shiver Timer",
    Default = false,
    Tooltip = "Показывает сколько процентов осталось до смерти от Шивера."
})
ShiverTimerToggle = ShiverTimerToggle or Toggles.ShiverTimerToggle

local SHIVER_MAX = 60  -- при каком значении Coldness наступает смерть

local function GetColdness()
    local char = LocalPlayer.Character
    if not char then return nil end
    local ok, val = pcall(function() return char:GetAttribute("Coldness") end)
    if ok and typeof(val) == "number" then return val end
    return nil
end

local ShiverState = { Active = false, LastPercent = 100, LastUpdate = 0 }
local ShiverLoop = nil

local function UpdateShiverUI(percent, secondsLeft)
    ShiverLabel.Text = string.format("COLDNESS: %d%%", math.floor(percent))
    if percent > 60 then
        ShiverLabel.TextColor3 = Color3.fromRGB(120, 220, 140)
    elseif percent > 30 then
        ShiverLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
    else
        ShiverLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
    end
    ShiverLabel.Visible = true
end

local function StartShiverLoop()
    if ShiverLoop then return end
    
    -- Считаем скорость роста Coldness для прогноза секунд
    local lastColdness = 0
    local lastTick = tick()
    local coldnessRate = 0
    
    ShiverLoop = RunService.Heartbeat:Connect(function()
        if ShiverXSlider then
            ShiverPosX = GetSliderValue(ShiverXSlider, "ShiverTimerX", ShiverPosX)
        end
        if ShiverYSlider then
            ShiverPosY = GetSliderValue(ShiverYSlider, "ShiverTimerY", ShiverPosY)
        end
        ApplyShiverPosition()

        if not ShiverTimerToggle or not ShiverTimerToggle.Value then
            ShiverLabel.Visible = false
            return
        end

        local coldness = GetColdness()
        if not coldness then
            ShiverLabel.Visible = false
            return
        end

        -- Обновляем скорость раз в 0.2 сек
        local now = tick()
        if now - lastTick > 0.2 then
            coldnessRate = (coldness - lastColdness) / (now - lastTick)
            lastColdness = coldness
            lastTick = now
            if coldnessRate < 0 then coldnessRate = 0 end
        end

        if coldness <= 0.01 then
            ShiverLabel.Visible = false
            lastColdness = 0
        else
            local percent = math.clamp((1 - coldness / SHIVER_MAX) * 100, 0, 100)
            local secondsLeft = "?"
            if coldnessRate > 0.01 then
                secondsLeft = (SHIVER_MAX - coldness) / coldnessRate
            end
            UpdateShiverUI(percent, secondsLeft)
        end
    end)
end

local function StopShiverLoop()
    if ShiverLoop then
        ShiverLoop:Disconnect()
        ShiverLoop = nil
    end
    ShiverLabel.Visible = false
    ShiverState.Active = false
    ShiverState.LastPercent = 100
end

if ShiverTimerToggle then
    ShiverTimerToggle:OnChanged(function(Value)
        if Value then StartShiverLoop() else StopShiverLoop() end
    end)
end

RegisterCleanup("ShiverTimer", function()
    if ShiverLoop then ShiverLoop:Disconnect() ShiverLoop = nil end
    if ShiverLabel then ShiverLabel.Visible = false end
    if Toggles.ShiverTimerToggle then SafeSetValue(Toggles.ShiverTimerToggle, false) end
end)


local ShiverXSlider = AddResettableSlider(VisualsRight, "ShiverTimerX", {
    Text = "Timer X",
    Min = 0, Max = 100, Default = 50,
    Rounding = 0, Compact = true
})
local ShiverYSlider = AddResettableSlider(VisualsRight, "ShiverTimerY", {
    Text = "Timer Y",
    Min = 0, Max = 100, Default = 8,
    Rounding = 0, Compact = true
})


-- ============================================================
-- KEYBIND LIST TOGGLE
-- ============================================================
local KeyBindListToggle = VisualsRight:AddToggle("KeyBindListToggle", {
    Text = "KeyBindList", Default = false,
    Tooltip = "Список активных биндов."
})
KeyBindListToggle = KeyBindListToggle or (Toggles and Toggles.KeyBindListToggle)

if KeyBindListToggle then
    KeyBindListToggle:OnChanged(function(Value)
        SetKeyBindListEnabled(Value)
    end)
end

RegisterCleanup("KeyBindList", function()
    SetKeyBindListEnabled(false)
    if KeyBindListState.UI then
        pcall(function() KeyBindListState.UI:Destroy() end)
        KeyBindListState.UI = nil
    end
    if Toggles and Toggles.KeyBindListToggle then
        SafeSetValue(Toggles.KeyBindListToggle, false)
      end
   end)
end

-- ============================================================
-- DYNAMIC TAB VISIBILITY (Lobby vs In-Game)
-- ============================================================
local function SetTabVisible(tab, visible)
    if not tab then return end
    -- Трогаем ТОЛЬКО кнопку в сайдбаре. Container не трогаем —
    -- он может быть общим и ломает рендер контента.
    pcall(function()
        if tab.TabButton then
            if tab.TabButton.Frame then tab.TabButton.Frame.Visible = visible end
            if tab.TabButton.Button then tab.TabButton.Button.Visible = visible end
            if tab.TabButton.Holder then tab.TabButton.Holder.Visible = visible end
        end
    end)
    pcall(function()
        if tab.Button and tab.Button.Visible ~= nil then
            tab.Button.Visible = visible
        end
    end)
end

local function IsInLobby()
    local lp = game:GetService("Players").LocalPlayer
    local room = lp:GetAttribute("CurrentRoom")
    local roomNum = room and tonumber(room) or 0
    if roomNum > 0 then return false end
    local rooms = workspace:FindFirstChild("CurrentRooms")
    if rooms and #rooms:GetChildren() > 0 then return false end
    return true
end

local LastLobbyState = nil
task.spawn(function()
    task.wait(0.3)
    while task.wait(0.3) do
        local inLobby = IsInLobby()
        if inLobby ~= LastLobbyState then
            LastLobbyState = inLobby
            if inLobby then
                SetTabVisible(Tabs.Info,     true)
                SetTabVisible(Tabs.Lobby,    true)
                SetTabVisible(Tabs.Exploits, false)
                SetTabVisible(Tabs.Visuals,  false)
                SetTabVisible(Tabs.Rofls,    true)
                SetTabVisible(Tabs.Settings, true)
            else
                SetTabVisible(Tabs.Info,     true)
                SetTabVisible(Tabs.Lobby,    false)
                SetTabVisible(Tabs.Exploits, true)
                SetTabVisible(Tabs.Visuals,  true)
                SetTabVisible(Tabs.Rofls,    true)
                SetTabVisible(Tabs.Settings, true)
            end

            -- Разные папки для конфигов — и авто-загрузка при смене
            pcall(function()
                local newFolder = inLobby and "MyHub/Lobby" or "MyHub/InGame"

                -- Если переходим в InGame и там нет автолоада — создаём дефолтный
                if not inLobby then
                    local ingameAutoload = "MyHub/InGame/settings/autoload.txt"
                    if isfile and not isfile(ingameAutoload) then
                        SaveManager:SetFolder("MyHub/InGame")
                        SaveManager:SaveConfig("default")
                        SaveManager:SaveAutoloadConfig("default")
                    end
                end

                SaveManager:SetFolder(newFolder)
                if SaveManager.RefreshConfigList then
                    SaveManager:RefreshConfigList()
                end

                -- Загружаем автолоад (если файл есть)
                local autoloadPath = newFolder .. "/settings/autoload.txt"
                if isfile and isfile(autoloadPath) then
                    if SaveManager.LoadAutoloadConfig then
                        SaveManager:LoadAutoloadConfig()
                    end
                    print("[TabSwitch] Loaded autoload from:", newFolder)
                else
                    print("[TabSwitch] No autoload in:", newFolder)
                end
            end)
        end
    end
end)

-- ============================================================
-- SETTINGS
-- ============================================================

local Menu = Tabs.Settings:AddLeftGroupbox("Menu")
Menu:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", { Default = "RightShift", NoUI = true, Text = "Menu keybind" })
Menu:AddButton("Unload", function() Library:Unload() end)

Library.ToggleKeybind = Library.Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
ThemeManager:SetFolder("MyHub")
-- Стартуем с InGame папки — если игрок в лобби, переключимся ниже
SaveManager:SetFolder("MyHub/InGame")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)

-- Создаём пустой InGame-конфиг default, если его нет (это будут "дефолтные" настройки для игры)
task.spawn(function()
    task.wait(1)
    pcall(function()
        if isfile and isfile("MyHub/InGame/settings/autoload.txt") then
            SaveManager:LoadAutoloadConfig()
        else
            -- Создаём дефолтный конфиг из текущих (дефолтных) настроек
            SaveManager:SaveConfig("default")
            SaveManager:SaveAutoloadConfig("default")
            SaveManager:LoadAutoloadConfig()
        end
    end)
end)

Library:Notify("Loaded. Press RightShift to toggle.", 5)

-- ============================================================
-- ROFLS TAB — весёлые функции
-- ============================================================
do
local RoflsLeft = Tabs.Rofls:AddLeftGroupbox("Character")

-- ============================================================
-- T-REX HANDS (R15)
-- ============================================================
local TRexState = {
    Enabled = false,
    Conn = nil,
    SavedC0 = {},
}

-- Поза T-Rex: руки согнуты к груди, кисти висят
local function TRex_GetPose(origC0)
    -- Смещение ВНИЗ + НАЗАД к груди + поворот "внутрь"
    return origC0
        * CFrame.new(0, -0.4, 0.3)                       -- вниз и назад (Z положительный = назад для R15 плеча)
        * CFrame.Angles(math.rad(60), math.rad(30), 0)   -- вперёд + внутрь
end

local function TRex_GetElbowPose(origC0)
    -- Сгибаем локоть под 90°
    return origC0 * CFrame.Angles(math.rad(-90), 0, 0)
end

local function TRex_GetWristPose(origC0)
    -- Сжимаем кисть
    return origC0 * CFrame.Angles(math.rad(-30), 0, 0)
end

-- Сохранить оригиналы C0 (один раз)
local function TRex_SaveC0()
    local char = LP.Character
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("Motor6D") then
            if part.Name == "LeftShoulder" or part.Name == "RightShoulder"
               or part.Name == "LeftElbow" or part.Name == "RightElbow"
               or part.Name == "LeftWrist" or part.Name == "RightWrist" then
                if not TRexState.SavedC0[part] then
                    TRexState.SavedC0[part] = part.C0
                end
            end
        end
    end
end

-- Применить позу через C0 (не Transform — C0 надёжнее)
local function TRex_Apply()
    local char = LP.Character
    if not char then return end

    -- Плечи
    local lua_ = char:FindFirstChild("LeftUpperArm")
    local rua_ = char:FindFirstChild("RightUpperArm")
    if lua_ then
        local lSh = lua_:FindFirstChild("LeftShoulder")
        if lSh and TRexState.SavedC0[lSh] then
            lSh.C0 = TRex_GetPose(TRexState.SavedC0[lSh])
        end
    end
    if rua_ then
        local rSh = rua_:FindFirstChild("RightShoulder")
        if rSh and TRexState.SavedC0[rSh] then
            rSh.C0 = TRex_GetPose(TRexState.SavedC0[rSh])
        end
    end

    -- Локти
    local lla = char:FindFirstChild("LeftLowerArm")
    local rla = char:FindFirstChild("RightLowerArm")
    if lla then
        local lElbow = lla:FindFirstChild("LeftElbow")
        if lElbow and TRexState.SavedC0[lElbow] then
            lElbow.C0 = TRex_GetElbowPose(TRexState.SavedC0[lElbow])
        end
    end
    if rla then
        local rElbow = rla:FindFirstChild("RightElbow")
        if rElbow and TRexState.SavedC0[rElbow] then
            rElbow.C0 = TRex_GetElbowPose(TRexState.SavedC0[rElbow])
        end
    end

    -- Кисти
    local lh = char:FindFirstChild("LeftHand")
    local rh = char:FindFirstChild("RightHand")
    if lh then
        local lWrist = lh:FindFirstChild("LeftWrist")
        if lWrist and TRexState.SavedC0[lWrist] then
            lWrist.C0 = TRex_GetWristPose(TRexState.SavedC0[lWrist])
        end
    end
    if rh then
        local rWrist = rh:FindFirstChild("RightWrist")
        if rWrist and TRexState.SavedC0[rWrist] then
            rWrist.C0 = TRex_GetWristPose(TRexState.SavedC0[rWrist])
        end
    end
end

-- Восстановить оригиналы
local function TRex_Restore()
    for motor, origC0 in pairs(TRexState.SavedC0) do
        if motor and motor.Parent then
            pcall(function() motor.C0 = origC0 end)
        end
    end
    TRexState.SavedC0 = {}
end

local function TRex_Enable()
    if TRexState.Enabled then return end
    TRexState.Enabled = true

    TRex_SaveC0()

    if TRexState.Conn then TRexState.Conn:Disconnect() end
    -- Heartbeat (после физики) — перебивает Animator каждый кадр
    TRexState.Conn = RunService.Heartbeat:Connect(function()
        if not TRexState.Enabled then return end
        TRex_Apply()
    end)

    TRex_Apply()
    print("[TRex] === ON ===")
end

local function TRex_Disable()
    if not TRexState.Enabled then return end
    TRexState.Enabled = false

    if TRexState.Conn then
        TRexState.Conn:Disconnect()
        TRexState.Conn = nil
    end

    TRex_Restore()
    print("[TRex] === OFF ===")
end

local TRexToggle = RoflsLeft:AddToggle("TRexToggle", {
    Text = "T-Rex Hands",
    Default = false,
    Tooltip = "Делает руки как у тираннозавра."
})
TRexToggle = TRexToggle or (Toggles and Toggles.TRexToggle)

if TRexToggle then
    TRexToggle:OnChanged(function(Value)
        if Value then TRex_Enable() else TRex_Disable() end
    end)
end

-- Переприменять при респавне
if LP then
    LP.CharacterAdded:Connect(function()
        task.wait(1)
        TRexState.SavedC0 = {}
        if TRexState.Enabled then
            TRex_Enable()
        end
    end)
end

RegisterCleanup("TRex", function()
    pcall(TRex_Disable)
    if Toggles and Toggles.TRexToggle then
        SafeSetValue(Toggles.TRexToggle, false)
    end
end)
end

do
-- ============================================================
-- UNLOAD CLEANUP
-- ============================================================
local origUnload = Library.Unload

Library.Unload = function(...)
    pcall(function() RunAllCleanups() end)

    -- === ПРИНУДИТЕЛЬНАЯ ОЧИСТКА ===
    -- Отключаем циклы, которые не попали в CleanupRegistry
    pcall(function()
        if getgenv().MyHub_FlyConn then
            getgenv().MyHub_FlyConn:Disconnect()
            getgenv().MyHub_FlyConn = nil
        end
    end)
    pcall(function()
        if getgenv().MyHub_HideLoopConn then
            getgenv().MyHub_HideLoopConn:Disconnect()
            getgenv().MyHub_HideLoopConn = nil
        end
    end)
    pcall(function()
        if getgenv().HideState and getgenv().HideState.C0Conn then
            getgenv().HideState.C0Conn:Disconnect()
            getgenv().HideState.C0Conn = nil
        end
    end)

    -- Удаляем ESP-контейнеры
    pcall(function()
        local cg = game:GetService("CoreGui")
        for _, name in ipairs({
            "MyHub_ESP", "MyHub_ESP_Screen",
            "MyHub_KeyBindList", "MyHub_ShiverTimer"
        }) do
            local obj = cg:FindFirstChild(name)
            if obj then obj:Destroy() end
        end
    end)

    -- Удаляем якоря из Workspace
    pcall(function()
        local toRemove = {}
        for _, obj in ipairs(workspace:GetDescendants()) do
            local n = obj.Name
            if n == "DoorESP_Anchor" or n == "MyHub_ShadeBarrier"
               or n == "MyHub_EntityAnchor" or n == "MyHub_EntityBox"
               or n:match("^Edge%d+$") then
                table.insert(toRemove, obj)
            end
        end
        for _, obj in ipairs(toRemove) do
            pcall(function() obj:Destroy() end)
        end
    end)
	
	    -- Сброс флага anti-reinject
    getgenv().__MellstroyHub_Loaded = false
    getgenv().__MellstroyHub_Library = nil
    getgenv().__MellstroyHub_Unload = nil

    local cg = game:GetService("CoreGui")
    local esp = cg:FindFirstChild("MyHub_ESP")
    if esp then pcall(function() esp:Destroy() end) end
    local shiv = cg:FindFirstChild("MyHub_ShiverTimer")
    if shiv then pcall(function() shiv:Destroy() end) end

    for _, obj in ipairs(workspace:GetDescendants()) do
        local n = obj.Name
        if n == "DoorESP_Anchor" or n == "RouteCue_Anchor"
           or n == "MyHub_EntityAnchor" or n == "MyHub_EntityBox"
           or n:match("^Edge%d+$") then
            pcall(function() obj:Destroy() end)
        end
    end

    if origUnload then
        return origUnload(...)
    end
end
end