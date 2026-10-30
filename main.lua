-- Luau | urban-reload.lua | Roblox client, desktop | Urban Reload 84448037861644
-- Requires an existing client-side Luau execution context; this file does not supply one.
-- Uses standard Player.Character/Humanoid rigs. Live Urban Reload compatibility is unverified.

local Config = {
    ESP = true,
    BoxStyle = "Cantos",
    ESPNames = true,
    ESPDistance = true,
    ESPHealthText = true,
    ESPHighlight = true,
    ESPSkeleton = false,
    ESPVisibleOnly = false,
    ESPThickness = 1.5,
    ESPDistanceLimit = 1200,
    CatalogKind = "Item",
    CatalogRig = "R15",

    Aim = true,
    Enabled = true,
    AimMode = "Automatico", -- Automatico or Ao segurar
    TrackingMode = "Direto", -- Direto or Suave
    AutoFire = true,
    WeaponName = "", -- bind the equipped weapon in the Disparo tab
    FireMode = "Pulsos", -- Pulsos or Continuo
    FireInterval = 0.12,
    FirePulseSeconds = 0.05,
    FireTolerancePixels = 5,
    Theme = "Azul",
    Gradient = false,
    TargetPart = "Head", -- Head, Chest, Root
    FOV = 140, -- radius in screen pixels
    ShowFOV = true,
    ResponseSeconds = 0.045, -- larger = slower convergence
    AcquireSeconds = 0.035, -- quick engagement while holding the fire button
    AccelerationSeconds = 0.018,
    MaxDegreesPerSecond = 360,
    LockAngleDegrees = 2.5, -- switch from acquisition to tight tracking near the target
    RetentionFOVMultiplier = 1.5,
    ActivationButton = Enum.UserInputType.MouseButton1,
    MaxDistance = 1200, -- studs, measured from the camera
    WallCheck = true,
    TeamCheck = false, -- Roblox Team only; does NOT identify Urban Reload crews
    CrewAttribute = "", -- only set after verifying the actual replicated attribute name
    IgnoreUserIds = {}, -- e.g. {[12345678] = true}
    ReticleOffset = Vector2.new(0, 0), -- pixels relative to viewport center
    HealthSide = "Left", -- Left or Right
    MenuKey = Enum.KeyCode.RightShift,
    UnloadKey = Enum.KeyCode.End,
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Input = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local GuiService = game:GetService("GuiService")
local LocalPlayer = Players.LocalPlayer
assert(LocalPlayer, "Execute no contexto de cliente, depois de entrar no jogo.")
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 15)
assert(PlayerGui, "PlayerGui indisponivel.")

local GUI_NAME = "ZyonUrbanReload"
local previous = PlayerGui:FindFirstChild(GUI_NAME)
if previous then previous:Destroy() end

local connections, entries = {}, {}
local stopped, held, focused = false, false, true
local selected, selectedCharacter, selectedAt = nil, nil, 0
local angularSpeed = 0
local trackingLocked = false
local resetAim, stopFire
local fireTool, fireUntil, nextFire = nil, 0, 0
local fireState = "Vincule a arma na aba Disparo"
local restoreCosmetic, updateCosmetic
local refreshUI
local binding = GUI_NAME .. HttpService:GenerateGUID(false)
local accent = Color3.fromRGB(99, 211, 255)
local targetColor = Color3.fromRGB(255, 200, 92)
local white = Color3.fromRGB(235, 240, 247)

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    table.insert(connections, connection)
    return connection
end

local function make(class, properties, parent)
    local object = Instance.new(class)
    for key, value in pairs(properties) do object[key] = value end
    object.Parent = parent
    return object
end

local gui = make("ScreenGui", {
    Name = GUI_NAME, ResetOnSpawn = false, IgnoreGuiInset = true,
    DisplayOrder = 100, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, PlayerGui)
-- ScreenInsets.None keeps the GUI coordinate space aligned with WorldToViewportPoint.
gui.ScreenInsets = Enum.ScreenInsets.None

local overlay = make("Frame", {
    Name = "Overlay", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
    BorderSizePixel = 0, Active = false,
}, gui)

local circle = make("Frame", {
    AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1,
    BorderSizePixel = 0,
}, overlay)
make("UICorner", {CornerRadius = UDim.new(1, 0)}, circle)
make("UIStroke", {Color = accent, Thickness = 1, Transparency = 0.35}, circle)


local themes = {
    Azul = Color3.fromRGB(94, 163, 255),
    Verde = Color3.fromRGB(72, 210, 159),
    Violeta = Color3.fromRGB(167, 139, 250),
    Ambar = Color3.fromRGB(244, 181, 83),
}
local background = Color3.fromRGB(16, 18, 24)
local surface = Color3.fromRGB(26, 29, 38)
local muted = Color3.fromRGB(140, 149, 168)
local themeBindings, widgetRefreshers = {}, {}
local function colored(object, property)
    table.insert(themeBindings, {object, property})
    object[property] = accent
    return object
end
local function round(object, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 8)}, object)
    return object
end
local function textLabel(parent, text, position, size, fontSize, color)
    return make("TextLabel", {
        Position = position, Size = size, BackgroundTransparency = 1, Text = text,
        Font = Enum.Font.Gotham, TextSize = fontSize or 13, TextColor3 = color or white,
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
        ZIndex = 12,
    }, parent)
end
local panel = round(make("Frame", {
    Name = "Settings", Position = UDim2.fromOffset(40, 70),
    Size = UDim2.fromOffset(760, 550), BackgroundColor3 = background,
    BorderSizePixel = 0, Active = true, ZIndex = 10,
}, gui), 14)
make("UIStroke", {Color = Color3.fromRGB(57, 63, 79), Thickness = 1}, panel)
local panelScale = make("UIScale", {Scale = 1}, panel)
local panelGradient = make("UIGradient", {Enabled = false, Rotation = 35}, panel)
colored(make("Frame", {Position = UDim2.fromOffset(16, 0),
    Size = UDim2.new(1, -32, 0, 2), BorderSizePixel = 0, ZIndex = 11}, panel), "BackgroundColor3")
local header = make("Frame", {Size = UDim2.new(1, -100, 0, 70),
    BackgroundTransparency = 1, Active = true, ZIndex = 11}, panel)
local title = colored(textLabel(header, "ZYON", UDim2.fromOffset(24, 16), UDim2.fromOffset(125, 25), 22), "TextColor3")
title.Font = Enum.Font.GothamBold
textLabel(header, "URBAN RELOAD  /  CONTROLE DE COMBATE", UDim2.fromOffset(24, 43), UDim2.fromOffset(430, 16), 10, muted)
local function headerButton(text, x)
    return round(make("TextButton", {Position = UDim2.new(1, x, 0, 22), Size = UDim2.fromOffset(30, 30),
        BackgroundColor3 = surface, BorderSizePixel = 0, Text = text, Font = Enum.Font.Gotham,
        TextColor3 = white, TextSize = 17, ZIndex = 13}, panel), 7)
end
local minimize, close = headerButton("-", -86), headerButton("x", -48)
local sidebar = make("Frame", {Position = UDim2.fromOffset(14, 80), Size = UDim2.fromOffset(172, 404),
    BackgroundTransparency = 1, ZIndex = 11}, panel)
local pages, navButtons, activePage = {}, {}, "Combate"
local pageDescriptions = {
    Combate = "Aquisicao, rastreamento e prioridade de alvo.",
    Disparo = "Acione a arma quando a mira estiver alinhada.",
    Visuais = "ESP, vida e distancia em tempo real.",
    Aparencia = "Escolha a cor e o acabamento do painel.",
    Visual = "Catalogo Roblox / previa 3D e aparencia local.",
}
local pageTitle = textLabel(panel, "Combate", UDim2.fromOffset(208, 82), UDim2.fromOffset(510, 28), 22)
pageTitle.Font = Enum.Font.GothamBold
local searchBox = round(make("TextBox", {
    Position = UDim2.fromOffset(208, 148), Size = UDim2.fromOffset(522, 30),
    BackgroundColor3 = surface, BorderSizePixel = 0, Text = "", PlaceholderText = "Buscar controles nesta aba...",
    PlaceholderColor3 = muted, ClearTextOnFocus = false, TextColor3 = white, TextSize = 12,
    Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12,
}, panel), 7)
make("UIPadding", {PaddingLeft = UDim.new(0, 12)}, searchBox)
local searchableCards = {}
local function filterCards()
    local query = string.lower(searchBox.Text)
    for _, item in ipairs(searchableCards) do item.object.Visible = query == "" or string.find(item.search, query, 1, true) ~= nil end
end
connect(searchBox:GetPropertyChangedSignal("Text"), filterCards)
local pageDescription = textLabel(panel, pageDescriptions.Combate, UDim2.fromOffset(208, 113), UDim2.fromOffset(520, 21), 12, muted)
for index, name in ipairs({"Combate", "Disparo", "Visuais", "Visual", "Aparencia"}) do
    local nav = round(make("TextButton", {Position = UDim2.fromOffset(0, (index - 1) * 48),
        Size = UDim2.fromOffset(172, 40), BackgroundColor3 = surface, BorderSizePixel = 0,
        Text = string.format("%02d   %s", index, name), Font = Enum.Font.GothamMedium,
        TextSize = 13, TextColor3 = muted, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12}, sidebar))
    make("UIPadding", {PaddingLeft = UDim.new(0, 14)}, nav)
    local page = make("ScrollingFrame", {Name = name, Position = UDim2.fromOffset(208, 188),
        Size = UDim2.fromOffset(530, 298), BackgroundTransparency = 1, BorderSizePixel = 0,
        CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollBarThickness = 3, ScrollBarImageColor3 = accent, Visible = name == activePage, ZIndex = 11}, panel)
    make("UIListLayout", {Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder}, page)
    make("UIPadding", {PaddingBottom = UDim.new(0, 6), PaddingRight = UDim.new(0, 8)}, page)
    pages[name], navButtons[name] = page, nav
    colored(page, "ScrollBarImageColor3")
    connect(nav.Activated, function()
        activePage = name
        searchBox.Text = ""
        pageTitle.Text, pageDescription.Text = name, pageDescriptions[name]
        refreshUI()
    end)
end
textLabel(sidebar, "CONTROLES", UDim2.fromOffset(10, 270), UDim2.fromOffset(150, 20), 10, muted)
textLabel(sidebar, "RightShift   Menu\nF8               Pausar\nEnd             Encerrar", UDim2.fromOffset(10, 297), UDim2.fromOffset(158, 70), 12, muted).TextWrapped = true
local status = textLabel(panel, "Inicializando...", UDim2.fromOffset(24, 504), UDim2.fromOffset(712, 30), 12, muted)
make("Frame", {Position = UDim2.fromOffset(24, 492), Size = UDim2.fromOffset(712, 1),
    BorderSizePixel = 0, BackgroundColor3 = Color3.fromRGB(45, 50, 63), ZIndex = 11}, panel)

local hud = round(make("Frame", {Position = UDim2.new(0, 22, 1, -90), Size = UDim2.fromOffset(360, 66),
    BackgroundColor3 = background, BackgroundTransparency = 0.1, BorderSizePixel = 0, ZIndex = 5}, gui), 10)
colored(make("UIStroke", {Thickness = 1, Transparency = 0.5}, hud), "Color")
local hudTitle = colored(textLabel(hud, "ZYON / EM ESPERA", UDim2.fromOffset(14, 9), UDim2.fromOffset(332, 19), 12), "TextColor3")
local hudDetail = textLabel(hud, "", UDim2.fromOffset(14, 33), UDim2.fromOffset(332, 19), 11, muted)
local reopen = round(make("TextButton", {Position = UDim2.new(1, -102, 0, 22), Size = UDim2.fromOffset(80, 32),
    BackgroundColor3 = background, BorderSizePixel = 0, Text = "ZYON", Font = Enum.Font.GothamBold,
    TextSize = 12, TextColor3 = accent, Visible = false, ZIndex = 15}, gui), 8)
colored(reopen, "TextColor3")
local function setMenu(open)
    panel.Visible, reopen.Visible = open, not open
    held = false
    if resetAim then resetAim() end
    if stopFire then stopFire() end
end
connect(minimize.Activated, function() setMenu(false) end)
connect(close.Activated, function() gui:Destroy() end)
connect(reopen.Activated, function() setMenu(true) end)

local order = 0
local function card(page, label, description, height)
    order = order + 1
    local object = round(make("Frame", {Size = UDim2.new(1, 0, 0, height or 66),
        BackgroundColor3 = surface, BorderSizePixel = 0, LayoutOrder = order, ZIndex = 12}, pages[page]), 9)
    textLabel(object, label, UDim2.fromOffset(14, 11), UDim2.new(1, -155, 0, 20), 13)
    textLabel(object, description, UDim2.fromOffset(14, 35), UDim2.new(1, -30, 0, 17), 10, muted)
    table.insert(searchableCards, {object = object, search = string.lower(label .. " " .. description)})
    return object
end
local function changed()
    if resetAim then resetAim() end
    if stopFire then stopFire() end
    refreshUI()
end
local function switch(page, label, description, key)
    local object = card(page, label, description)
    local track = round(make("TextButton", {Position = UDim2.new(1, -64, 0, 12), Size = UDim2.fromOffset(48, 24),
        BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 13}, object), 12)
    local knob = round(make("Frame", {Size = UDim2.fromOffset(18, 18), BackgroundColor3 = white,
        BorderSizePixel = 0, ZIndex = 14}, track), 9)
    table.insert(widgetRefreshers, function()
        track.BackgroundColor3 = Config[key] and accent or Color3.fromRGB(63, 68, 83)
        knob.Position = UDim2.fromOffset(Config[key] and 27 or 3, 3)
    end)
    connect(track.Activated, function() Config[key] = not Config[key]; changed() end)
end
local function choice(page, label, description, key, values)
    local object = card(page, label, description)
    local control = round(make("TextButton", {Position = UDim2.new(1, -148, 0, 9), Size = UDim2.fromOffset(132, 27),
        BackgroundColor3 = Color3.fromRGB(38, 43, 55), BorderSizePixel = 0, TextColor3 = white,
        TextSize = 11, Font = Enum.Font.GothamMedium, ZIndex = 13}, object), 6)
    table.insert(widgetRefreshers, function() control.Text = tostring(Config[key]) .. "  >" end)
    connect(control.Activated, function()
        Config[key] = values[((table.find(values, Config[key]) or 0) % #values) + 1]
        changed()
    end)
end
local activeSlider
local function slider(page, label, description, key, minimum, maximum, increment, suffix)
    local object = card(page, label, description, 90)
    local value = colored(textLabel(object, "", UDim2.new(1, -140, 0, 11), UDim2.fromOffset(124, 20), 12), "TextColor3")
    value.TextXAlignment = Enum.TextXAlignment.Right
    local hit = make("TextButton", {Position = UDim2.fromOffset(16, 57), Size = UDim2.new(1, -32, 0, 25),
        BackgroundTransparency = 1, Text = "", ZIndex = 13}, object)
    local rail = round(make("Frame", {Position = UDim2.fromOffset(0, 10), Size = UDim2.new(1, 0, 0, 4),
        BackgroundColor3 = Color3.fromRGB(55, 61, 76), BorderSizePixel = 0, ZIndex = 13}, hit), 2)
    local fill = colored(round(make("Frame", {Size = UDim2.fromScale(0, 1), BorderSizePixel = 0, ZIndex = 14}, rail), 2), "BackgroundColor3")
    local knob = round(make("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12),
        BackgroundColor3 = white, BorderSizePixel = 0, ZIndex = 15}, rail), 6)
    local function refresh()
        local fraction = math.clamp((Config[key] - minimum) / (maximum - minimum), 0, 1)
        value.Text = string.format(increment < 1 and "%.2f%s" or "%.0f%s", Config[key], suffix or "")
        fill.Size, knob.Position = UDim2.fromScale(fraction, 1), UDim2.fromScale(fraction, 0.5)
    end
    table.insert(widgetRefreshers, refresh)
    local function update(x)
        local fraction = math.clamp((x - rail.AbsolutePosition.X) / math.max(1, rail.AbsoluteSize.X), 0, 1)
        local raw = minimum + (maximum - minimum) * fraction
        Config[key] = math.clamp(math.floor(raw / increment + 0.5) * increment, minimum, maximum)
        refresh()
    end
    connect(hit.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            activeSlider = update
            update(input.Position.X)
        end
    end)
end
switch("Combate", "Sistema ativo", "F8 pausa a mira e o disparo automatico.", "Enabled")
switch("Combate", "Assistencia de mira", "Mantem a parte escolhida alinhada ao reticulo.", "Aim")
choice("Combate", "Ativacao", "Automatico acompanha sem precisar segurar o mouse.", "AimMode", {"Automatico", "Ao segurar"})
choice("Combate", "Rastreamento", "Direto corrige a rotacao completa a cada quadro.", "TrackingMode", {"Direto", "Suave"})
choice("Combate", "Parte do alvo", "Cabeça como padrao; sem troca aleatoria de parte.", "TargetPart", {"Head", "Chest", "Root"})
slider("Combate", "Raio de aquisicao", "Distancia do reticulo para escolher um novo alvo.", "FOV", 40, 350, 5, " px")
slider("Combate", "Retencao do alvo", "Amplia o raio apenas para manter o alvo atual.", "RetentionFOVMultiplier", 1, 3, 0.1, "x")
slider("Combate", "Resposta suave", "Aplicada somente no modo Suave.", "ResponseSeconds", 0.01, 0.3, 0.01, " s")
switch("Combate", "Linha de visao", "Ignora alvos atras de obstaculos na selecao.", "WallCheck")
switch("Combate", "Filtrar equipe", "Usa Roblox Team; crews customizadas nao sao reconhecidas.", "TeamCheck")
switch("Disparo", "Disparo automatico", "Requer arma vinculada, alinhamento e linha livre.", "AutoFire")
local weaponCard = card("Disparo", "Arma vinculada", "Equipe a arma desejada e pressione Vincular.", 92)
local weaponLabel = textLabel(weaponCard, "Nenhuma", UDim2.fromOffset(14, 61), UDim2.new(1, -30, 0, 18), 11, muted)
local bindWeapon = round(make("TextButton", {Position = UDim2.new(1, -108, 0, 10), Size = UDim2.fromOffset(92, 26),
    BackgroundColor3 = surface, BorderSizePixel = 0, Text = "Vincular", Font = Enum.Font.GothamBold,
    TextColor3 = accent, TextSize = 12, ZIndex = 13}, weaponCard), 6)
colored(bindWeapon, "TextColor3")
table.insert(widgetRefreshers, function() weaponLabel.Text = Config.WeaponName ~= "" and Config.WeaponName or "Nenhuma arma vinculada" end)
connect(bindWeapon.Activated, function()
    local character = LocalPlayer.Character
    local tool = character and character:FindFirstChildOfClass("Tool")
    if tool then Config.WeaponName = tool.Name; changed()
    else weaponLabel.Text = "Nenhuma Tool equipada foi encontrada" end
end)
choice("Disparo", "Acionamento", "Pulsos repete cliques; Continuo segura a ativacao.", "FireMode", {"Pulsos", "Continuo"})
slider("Disparo", "Intervalo entre pulsos", "A cadencia real ainda depende da arma.", "FireInterval", 0.05, 0.5, 0.01, " s")
slider("Disparo", "Tolerancia da mira", "O raycast tambem precisa atingir o personagem.", "FireTolerancePixels", 1, 20, 1, " px")
card("Disparo", "Compatibilidade", "Aciona Tool:Activate(). Integracao com Urban Reload nao verificada.", 68)
switch("Visuais", "ESP de jogadores", "Caixa, nome, vida e distancia.", "ESP")
choice("Visuais", "Estilo da caixa", "Cantos, caixa completa ou sem caixa.", "BoxStyle", {"Cantos", "Completa", "Sem caixa"})
switch("Visuais", "Contorno do personagem", "Destaque 3D com a cor do tema.", "ESPHighlight")
switch("Visuais", "Esqueleto", "Linhas entre as juntas do rig R6/R15.", "ESPSkeleton")
switch("Visuais", "Somente visiveis", "Oculta o ESP de personagens atras de obstaculos.", "ESPVisibleOnly")
switch("Visuais", "Nome do jogador", "Nome acima da caixa.", "ESPNames")
switch("Visuais", "Distancia", "Distancia abaixo da caixa, em studs.", "ESPDistance")
switch("Visuais", "Vida numerica", "HP atual ao lado da barra lateral.", "ESPHealthText")
slider("Visuais", "Espessura", "Linhas da caixa e do esqueleto.", "ESPThickness", 1, 3, 0.5, " px")
switch("Visuais", "Circulo de FOV", "Mostra a area de aquisicao ao fechar o menu.", "ShowFOV")
choice("Visuais", "Barra de vida", "Cor proporcional ao HP atual do Humanoid.", "HealthSide", {"Left", "Right"})
slider("Visuais", "Distancia do ESP", "Ajusta somente os indicadores visuais.", "ESPDistanceLimit", 100, 2000, 50, " st")
choice("Aparencia", "Cor de destaque", "Aplica a cor ao menu, FOV e ESP.", "Theme", {"Azul", "Verde", "Violeta", "Ambar"})
switch("Aparencia", "Degrade sutil", "Desligado: fundo grafite solido.", "Gradient")
card("Aparencia", "Janela adaptavel", "Arraste o cabecalho. O tamanho se ajusta a tela.", 68)

-- Local cosmetic replica: leaves the gameplay rig, joints and server character untouched.
do
    local Marketplace = game:GetService("MarketplaceService")
    local Assets = game:GetService("AssetService")
    local currentDescription, previewModel
    local equippedTemplate, rigGraph
    local respawnToken = 0
    local generation, busy = 0, false
    local replica, replicaCharacter, mappings, hidden = nil, nil, {}, {}
    local appearanceConnection
    choice("Visual", "Corpo do catalogo", "R15 preserva pacotes modernos; R6 para avatares classicos.", "CatalogRig", {"R15", "R6"})
    choice("Visual", "Tipo de ID", "Links identificam o tipo automaticamente.", "CatalogKind", {"Item", "Pacote", "Avatar"})
    local inputCard = card("Visual", "Item ou skin do catalogo", "Cole um link Roblox ou um ID numerico.", 105)
    local catalogInput = round(make("TextBox", {
        Position = UDim2.fromOffset(14, 60), Size = UDim2.new(1, -28, 0, 31),
        BackgroundColor3 = background, TextColor3 = white, PlaceholderColor3 = muted,
        Text = "", PlaceholderText = "https://www.roblox.com/catalog/...",
        Font = Enum.Font.Code, TextSize = 12, ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left, BorderSizePixel = 0, ZIndex = 13,
    }, inputCard), 6)
    make("UIPadding", {PaddingLeft = UDim.new(0,8), PaddingRight = UDim.new(0,8)}, catalogInput)
    local previewCard = card("Visual", "Provador 3D", "Aparencia local / nao altera seu inventario.", 335)
    local viewport = round(make("ViewportFrame", {
        Position = UDim2.fromOffset(14,60), Size = UDim2.new(1,-28,0,220), BackgroundColor3 = background,
        BorderSizePixel = 0, Ambient = Color3.fromRGB(190,190,200), LightColor = Color3.new(1,1,1),
        LightDirection = Vector3.new(-1,-1,-1), ZIndex = 13,
    }, previewCard), 8)
    local world = make("WorldModel", {}, viewport)
    local previewCamera = make("Camera", {FieldOfView = 35}, viewport)
    viewport.CurrentCamera = previewCamera
    local catalogStatus = textLabel(previewCard, "Carregue um item, pacote ou avatar.",
        UDim2.fromOffset(14,286), UDim2.new(1,-28,0,42), 11, muted)
    catalogStatus.TextWrapped = true
    catalogStatus.TextTruncate = Enum.TextTruncate.None
    local actionCard = card("Visual", "Aplicar e restaurar", "Mantem apos morrer. Remover avatar desfaz a troca.", 108)
    local function action(label, x, width)
        local object = round(make("TextButton", {Position=UDim2.new(x,8,0,63), Size=UDim2.new(width,-16,0,30),
            BackgroundColor3=background, Text=label, Font=Enum.Font.GothamMedium, TextSize=11,
            TextColor3=accent, BorderSizePixel=0, ZIndex=13}, actionCard), 6)
        colored(object,"TextColor3")
        return object
    end
    local loadButton = action("Carregar previa",0,0.34)
    local applyButton = action("Aplicar local",0.34,0.33)
    local restoreButton = action("Remover avatar",0.67,0.33)

    restoreCosmetic = function()
        if appearanceConnection then appearanceConnection:Disconnect(); appearanceConnection=nil end
        if replica then replica:Destroy(); replica=nil end
        for part, transparency in pairs(hidden) do
            if part.Parent then part.LocalTransparencyModifier=transparency end
        end
        hidden, mappings, replicaCharacter, rigGraph = {}, {}, nil, nil
    end
    local function rememberPart(part)
        if part:IsA("BasePart") and not part:FindFirstAncestorOfClass("Tool") and hidden[part] == nil then
            hidden[part]=part.LocalTransparencyModifier
        end
    end
    local function standingHeight(character, humanoid, root)
        local leg=humanoid.RigType==Enum.HumanoidRigType.R6 and character:FindFirstChild("Left Leg")
        return root.Size.Y*0.5+humanoid.HipHeight+(leg and leg.Size.Y or 0)
    end
    updateCosmetic = function(camera)
        if not replica or not rigGraph then return end
        local character=LocalPlayer.Character
        local root=character and character:FindFirstChild("HumanoidRootPart")
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        if replicaCharacter~=character or not root or not humanoid then restoreCosmetic(); return end
        local head=character:FindFirstChild("Head")
        local firstPerson=head and (camera.CFrame.Position-head.Position).Magnitude<1.2
        -- Align standing ground levels without changing either model's proportions or live HipHeight.
        local heightOffset=rigGraph.height-standingHeight(character,humanoid,root)
        rigGraph.root.CFrame=root.CFrame+Vector3.new(0,heightOffset,0)
        for _,edge in ipairs(rigGraph.edges) do
            local transform=CFrame.new()
            local joint=edge.source
            if joint and joint.Parent and joint.Part0 and joint.Part1 then
                -- Recover the animated relative rotation, not the live character's limb positions/sizes.
                transform=(joint.C0:Inverse()*joint.Part0.CFrame:ToObjectSpace(joint.Part1.CFrame)*joint.C1).Rotation
            end
            local relative=edge.c0*transform*edge.c1:Inverse()
            edge.child.CFrame=edge.parent.CFrame*(edge.reverse and relative:Inverse() or relative)
        end
        for _,binding in ipairs(mappings) do
            local part=binding.part
            if part.Parent then
                if binding.fallback then part.CFrame=rigGraph.root.CFrame*binding.fallback end
                part.Anchored=true; part.CanCollide=false; part.CanTouch=false; part.CanQuery=false
                part.LocalTransparencyModifier=firstPerson and 1 or 0
            end
        end
        for part in pairs(hidden) do
            if part.Parent then part.LocalTransparencyModifier=1 else hidden[part]=nil end
        end
        replica.Parent=camera
    end
    local numericFields = {
        [2]="GraphicTShirt",[11]="Shirt",[12]="Pants",[18]="Face",[17]="Head",
        [27]="Torso",[28]="RightArm",[29]="LeftArm",[30]="LeftLeg",[31]="RightLeg",
    }
    local rigidFields = {[8]="HatAccessory",[41]="HairAccessory",[42]="FaceAccessory",[43]="NeckAccessory",
        [44]="ShouldersAccessory",[45]="FrontAccessory",[46]="BackAccessory",[47]="WaistAccessory"}
    local layeredTypes = {[64]="TShirt",[65]="Shirt",[66]="Pants",[67]="Jacket",[68]="Sweater",
        [69]="Shorts",[70]="LeftShoe",[71]="RightShoe",[72]="DressSkirt"}
    local function addAsset(description,id,skipUnknown)
        local info=Marketplace:GetProductInfoAsync(id,Enum.InfoType.Asset)
        local kind=info.AssetTypeId
        if numericFields[kind] then description[numericFields[kind]]=id
        elseif rigidFields[kind] then
            local field=rigidFields[kind]
            local ids={}
            for value in string.gmatch(description[field],"%d+") do
                if tonumber(value)~=id then table.insert(ids,value) end
            end
            table.insert(ids,tostring(id))
            description[field]=table.concat(ids,",")
        elseif layeredTypes[kind] then
            local accessories=description:GetAccessories(true)
            for i=#accessories,1,-1 do if accessories[i].AssetId==id then table.remove(accessories,i) end end
            table.insert(accessories,{AssetId=id,AccessoryType=Enum.AccessoryType[layeredTypes[kind]],IsLayered=true,Order=#accessories+1})
            description:SetAccessories(accessories,true)
        elseif not skipUnknown then error("Tipo de item nao suportado no provador: "..tostring(kind)) end
        return info.Name or tostring(id)
    end
    local function parseID(text)
        text=string.match(text,"^%s*(.-)%s*$")
        local kind,id=Config.CatalogKind,string.match(text,"^(%d+)$")
        if not id then
            local host=string.match(string.lower(text),"^https?://([^/]+)")
            assert(host=="www.roblox.com" or host=="roblox.com","Use ID numerico ou link de roblox.com.")
            id=string.match(text,"/catalog/(%d+)")
            if id then kind="Item" else
                id=string.match(text,"/bundles/(%d+)")
                if id then kind="Pacote" else id=string.match(text,"/users/(%d+)"); kind="Avatar" end
            end
        end
        id=tonumber(id)
        assert(id and id>0 and id<9007199254740992 and id==math.floor(id),"ID ou link invalido.")
        return id,kind
    end
    local function loadPreview()
        if busy then return end
        local character=LocalPlayer.Character
        local humanoid=character and character:FindFirstChildOfClass("Humanoid")
        if not humanoid then catalogStatus.Text="Aguarde seu personagem aparecer."; return end
        generation=generation+1
        local token=generation
        local requestedText=catalogInput.Text
        local requestedRig=Enum.HumanoidRigType[Config.CatalogRig]
        busy=true
        catalogStatus.Text="Consultando catalogo e carregando aparencia..."
        task.spawn(function()
            local model,description
            local ok,result=pcall(function()
                local id,kind=parseID(requestedText)
                local name=tostring(id)
                if kind=="Avatar" then description=Players:GetHumanoidDescriptionFromUserIdAsync(id)
                else
                    description=currentDescription and currentDescription:Clone() or humanoid:GetAppliedDescription()
                    if kind=="Pacote" then
                        local details=Assets:GetBundleDetailsAsync(id)
                        name=details.Name or name
                        local outfit
                        for _,item in ipairs(details.Items or {}) do if item.Type=="UserOutfit" then outfit=item.Id; break end end
                        if outfit then
                            description:Destroy()
                            description=Players:GetHumanoidDescriptionFromOutfitIdAsync(outfit)
                        else
                            assert(#(details.Items or {})<=25,"Pacote grande demais para esta consulta.")
                            for _,item in ipairs(details.Items or {}) do if item.Type=="Asset" then addAsset(description,item.Id,true) end end
                        end
                    else name=addAsset(description,id,false) end
                end
                -- Keep the catalog rig independent from the live gameplay rig.
                model=Players:CreateHumanoidModelFromDescriptionAsync(description,requestedRig)
                for _,object in ipairs(model:GetDescendants()) do
                    if object:IsA("BaseScript") or object:IsA("ModuleScript") then object:Destroy()
                    elseif object:IsA("BasePart") then
                        object.Anchored=true; object.CanCollide=false; object.CanTouch=false; object.CanQuery=false
                    end
                end
                return name
            end)
            if stopped or token~=generation or LocalPlayer.Character~=character then
                if model then model:Destroy() end
                if description then description:Destroy() end
                if token==generation then busy=false end
                return
            end
            busy=false
            if not ok then
                if model then model:Destroy() end
                if description then description:Destroy() end
                catalogStatus.Text="Falha: "..string.sub(tostring(result),1,170)
                warn("Zyon Visual: "..tostring(result))
                return
            end
            if previewModel then previewModel:Destroy() end
            if currentDescription then currentDescription:Destroy() end
            currentDescription,previewModel=description,model
            model.Parent=world
            local bounds,size=model:GetBoundingBox()
            local distance=math.max(size.X,size.Y,size.Z)*2.2
            previewCamera.CFrame=CFrame.lookAt(bounds.Position+Vector3.new(distance*0.25,size.Y*0.12,-distance),bounds.Position)
            catalogStatus.Text=tostring(result).." / previa pronta. Aplicacao somente local."
        end)
    end
    connect(loadButton.Activated,loadPreview)
    connect(catalogInput.FocusLost,function(enter) if enter then loadPreview() end end)
    local function mountTemplate(template,character)
        local sourceRoot=character:FindFirstChild("HumanoidRootPart")
        local humanoid=character:FindFirstChildOfClass("Humanoid")
        if not sourceRoot or not humanoid or not Workspace.CurrentCamera then return false end
        local model=template:Clone()
        local root=model:FindFirstChild("HumanoidRootPart")
        local visualHumanoid=model:FindFirstChildOfClass("Humanoid")
        if not root or not visualHumanoid then model:Destroy(); return false end
        local height=standingHeight(model,visualHumanoid,root)
        local sourceByChild={}
        for _,joint in ipairs(character:GetDescendants()) do
            if joint:IsA("Motor6D") and joint.Part1 and joint.Part1.Parent==character then
                sourceByChild[joint.Part1.Name]=joint
            end
        end
        -- Cross-rig mapping transfers major joints; unmatched joints keep the catalog rest pose.
        local alternate={UpperTorso="Torso",LowerTorso="Torso",LeftUpperArm="Left Arm",RightUpperArm="Right Arm",
            LeftUpperLeg="Left Leg",RightUpperLeg="Right Leg",Torso="LowerTorso",
            ["Left Arm"]="LeftUpperArm",["Right Arm"]="RightUpperArm",
            ["Left Leg"]="LeftUpperLeg",["Right Leg"]="RightUpperLeg"}
        local adjacency={}
        local function addEdge(part,edge)
            adjacency[part]=adjacency[part] or {}; table.insert(adjacency[part],edge)
        end
        for _,joint in ipairs(model:GetDescendants()) do
            if joint:IsA("JointInstance") and joint.Part0 and joint.Part1 then
                local p0,p1=joint.Part0,joint.Part1
                local source
                if joint:IsA("Motor6D") then
                    source=sourceByChild[p1.Name] or sourceByChild[alternate[p1.Name]]
                    -- Do not apply the same R6 torso rotation twice along an R15 spine.
                    if p1.Name=="UpperTorso" and not sourceByChild.UpperTorso then source=nil end
                end
                addEdge(p0,{parent=p0,child=p1,c0=joint.C0,c1=joint.C1,source=source})
                addEdge(p1,{parent=p1,child=p0,c0=joint.C0,c1=joint.C1,source=source,reverse=true})
            end
        end
        local visited,queue,edges={[root]=true},{root},{}
        local index=1
        while index<=#queue do
            local parent=queue[index]; index=index+1
            for _,edge in ipairs(adjacency[parent] or {}) do
                if not visited[edge.child] then
                    visited[edge.child]=true; table.insert(queue,edge.child); table.insert(edges,edge)
                end
            end
        end
        local bindings={}
        for _,object in ipairs(model:GetDescendants()) do
            if object:IsA("BasePart") then
                -- No Size or mesh Scale assignments: catalog geometry is preserved verbatim.
                table.insert(bindings,{part=object,fallback=not visited[object] and root.CFrame:ToObjectSpace(object.CFrame) or nil})
                object.Anchored=true; object.CanCollide=false; object.CanTouch=false; object.CanQuery=false; object.Massless=true
            end
        end
        visualHumanoid.RequiresNeck=false; visualHumanoid.BreakJointsOnDeath=false
        for _,object in ipairs(model:GetDescendants()) do
            if object:IsA("Humanoid") or object:IsA("Animator") or object:IsA("AnimationController")
                or object:IsA("JointInstance") or object:IsA("Constraint") or object:IsA("WeldConstraint")
                or object:IsA("BodyMover") or object:IsA("BaseScript") or object:IsA("ModuleScript") then object:Destroy() end
        end
        restoreCosmetic()
        replica,replicaCharacter,mappings=model,character,bindings
        rigGraph={root=root,height=height,edges=edges}
        model.Name="ZyonLocalAppearance"
        for _,part in ipairs(character:GetDescendants()) do rememberPart(part) end
        appearanceConnection=character.DescendantAdded:Connect(rememberPart)
        updateCosmetic(Workspace.CurrentCamera)
        return true
    end
    connect(applyButton.Activated,function()
        if busy or not previewModel then catalogStatus.Text="Carregue uma previa primeiro."; return end
        local character=LocalPlayer.Character
        if not character or not mountTemplate(previewModel,character) then
            catalogStatus.Text="Aguarde o personagem e a camera ficarem prontos."; return
        end
        respawnToken=respawnToken+1
        if equippedTemplate then equippedTemplate:Destroy() end
        equippedTemplate=previewModel:Clone()
        catalogStatus.Text="Avatar aplicado com proporcoes do catalogo. Mantido apos morrer."
    end)
    connect(restoreButton.Activated,function()
        generation=generation+1; busy=false; respawnToken=respawnToken+1
        if equippedTemplate then equippedTemplate:Destroy(); equippedTemplate=nil end
        restoreCosmetic()
        catalogStatus.Text="Avatar removido. Nao sera reaplicado ao renascer."
    end)
    connect(LocalPlayer.CharacterRemoving,function()
        generation=generation+1; busy=false; respawnToken=respawnToken+1
        restoreCosmetic()
        if not stopped then catalogStatus.Text=equippedTemplate and "Aguardando renascer para reaplicar o avatar." or "Aparencia original ativa." end
    end)
    connect(LocalPlayer.CharacterAdded,function(character)
        respawnToken=respawnToken+1
        local token=respawnToken
        task.spawn(function()
            for _=1,40 do
                if stopped or token~=respawnToken or LocalPlayer.Character~=character or not equippedTemplate then return end
                local humanoid=character:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health>0 and character:FindFirstChild("Head") and character:FindFirstChild("HumanoidRootPart") then
                    if mountTemplate(equippedTemplate,character) then
                        catalogStatus.Text="Avatar reaplicado apos renascer."
                        return
                    end
                end
                task.wait(0.5)
            end
            if not stopped and token==respawnToken then catalogStatus.Text="Personagem demorou para carregar. Use Aplicar local." end
        end)
    end)
    connect(gui.Destroying,function()
        respawnToken=respawnToken+1
        if equippedTemplate then equippedTemplate:Destroy(); equippedTemplate=nil end
        generation=generation+1
        restoreCosmetic()
        if currentDescription then currentDescription:Destroy(); currentDescription=nil end
    end)
end


refreshUI = function()
    accent = themes[Config.Theme] or themes.Azul
    for _, binding in ipairs(themeBindings) do binding[1][binding[2]] = accent end
    circle:FindFirstChildOfClass("UIStroke").Color = accent
    panelGradient.Enabled = Config.Gradient
    panel.BackgroundColor3 = Config.Gradient and Color3.new(1, 1, 1) or background
    panelGradient.Color = ColorSequence.new(background:Lerp(accent, 0.16), background)
    for name, page in pairs(pages) do
        page.Visible = name == activePage
        navButtons[name].BackgroundColor3 = name == activePage and background:Lerp(accent, 0.2) or background
        navButtons[name].TextColor3 = name == activePage and accent or muted
    end
    for _, refresh in ipairs(widgetRefreshers) do refresh() end
end
refreshUI()
local dragStart, panelStart
connect(header.InputBegan, function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragStart, panelStart = input.Position, panel.Position
    end
end)
connect(Input.InputChanged, function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement then
        if activeSlider then activeSlider(input.Position.X) end
        if dragStart then
            local delta = input.Position - dragStart
            local view = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
            panel.Position = UDim2.fromOffset(
                math.clamp(panelStart.X.Offset + delta.X, 0, math.max(0, view.X - panel.AbsoluteSize.X)),
                math.clamp(panelStart.Y.Offset + delta.Y, 0, math.max(0, view.Y - panel.AbsoluteSize.Y)))
        end
    end
end)

resetAim = function()
    selected, selectedCharacter, angularSpeed, trackingLocked = nil, nil, 0, false
    if stopFire then stopFire() end
end
stopFire = function()
    local previousTool = fireTool
    fireTool, fireUntil = nil, 0
    if previousTool then
        pcall(function() previousTool:Deactivate() end)
    end
end
local function cleanup()
    if stopped then return end
    stopped = true
    if restoreCosmetic then restoreCosmetic() end
    for _, entry in pairs(entries) do entry.highlight:Destroy() end
    RunService:UnbindFromRenderStep(binding)
    for _, connection in ipairs(connections) do connection:Disconnect() end
    table.clear(connections)
    table.clear(entries)
    resetAim()
end
connect(gui.Destroying, cleanup)
connect(Input.InputBegan, function(input, processed)
    if processed or Input:GetFocusedTextBox() then return end
    if input.KeyCode == Config.UnloadKey then gui:Destroy(); return end
    if input.KeyCode == Config.MenuKey then
        setMenu(not panel.Visible)
    elseif input.KeyCode == Enum.KeyCode.F8 then
        Config.Enabled = not Config.Enabled
        held = false
        changed()
    elseif input.UserInputType == Config.ActivationButton and not panel.Visible then
        held = true
    end
end)
connect(Input.InputEnded, function(input)
    if input.UserInputType == Config.ActivationButton then
        held = false
        if Config.AimMode == "Ao segurar" then resetAim() end
    end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then dragStart, activeSlider = nil, nil end
end)
connect(Input.WindowFocusReleased, function() focused = false; held = false; dragStart, activeSlider = nil, nil; resetAim() end)
connect(Input.WindowFocused, function() focused = true end)
connect(GuiService.MenuOpened, function() held = false; resetAim() end)

local function addPlayer(player)
    if player == LocalPlayer or entries[player] then return end
    local box = make("Frame", {BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false}, overlay)
    local outline = make("UIStroke", {Color = accent, Thickness = 1.5}, box)
    local label = make("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0),
        Size = UDim2.new(1, 120, 0, 20), BackgroundTransparency = 1,
        TextColor3 = white, TextStrokeTransparency = 0.2, TextSize = 12,
        Font = Enum.Font.GothamMedium,
    }, box)
    local healthBack = make("Frame", {
        Position = UDim2.fromOffset(-7, -1), Size = UDim2.new(0, 4, 1, 2),
        BackgroundColor3 = Color3.fromRGB(5, 8, 12), BorderSizePixel = 0,
    }, box)
    local health = make("Frame", {
        AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 1, 1, -1),
        Size = UDim2.new(1, -2, 1, -2), BackgroundColor3 = Color3.fromRGB(80, 235, 110),
        BorderSizePixel = 0,
    }, healthBack)
    local segments = {}
    for i = 1, 8 do segments[i] = make("Frame", {BorderSizePixel = 0, BackgroundColor3 = accent}, box) end
    local below = make("TextLabel", {Position = UDim2.new(0.5, 0, 1, 4), AnchorPoint = Vector2.new(0.5, 0),
        Size = UDim2.fromOffset(160, 18), BackgroundTransparency = 1, TextColor3 = white,
        Font = Enum.Font.Gotham, TextSize = 11, TextStrokeTransparency = 0.2}, box)
    local hpLabel = make("TextLabel", {Size = UDim2.fromOffset(55, 18), BackgroundTransparency = 1,
        TextColor3 = white, Font = Enum.Font.Code, TextSize = 11, TextStrokeTransparency = 0.2}, box)
    local highlight = make("Highlight", {Enabled = false, FillTransparency = 0.87, OutlineTransparency = 0.12,
        DepthMode = Enum.HighlightDepthMode.AlwaysOnTop}, Workspace.CurrentCamera or Workspace)
    local skeleton = make("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false}, overlay)
    entries[player] = {segments = segments, below = below, hpLabel = hpLabel, highlight = highlight,
        skeleton = skeleton, bones = {}, joints = {}, nextVisibility = 0, isVisible = false, box = box, outline = outline, label = label, health = health,
        healthBack = healthBack, body = {}, character = nil, nextBodyUpdate = 0}
end
connect(Players.PlayerAdded, addPlayer)
connect(Players.PlayerRemoving, function(player)
    local entry = entries[player]
    if entry then entry.box:Destroy(); entry.skeleton:Destroy(); entry.highlight:Destroy(); entries[player] = nil end
    if selected == player then resetAim() end
end)
for _, player in ipairs(Players:GetPlayers()) do addPlayer(player) end

local function isExcluded(player)
    if Config.IgnoreUserIds[player.UserId] then return true end
    if Config.TeamCheck and not LocalPlayer.Neutral and not player.Neutral
        and LocalPlayer.Team ~= nil and player.Team == LocalPlayer.Team then return true end
    if Config.CrewAttribute ~= "" then
        local own = LocalPlayer:GetAttribute(Config.CrewAttribute)
        if own ~= nil and own ~= "" and own ~= 0 and own ~= false
            and own == player:GetAttribute(Config.CrewAttribute) then return true end
    end
    return false
end

local function targetPart(character)
    local names = Config.TargetPart == "Chest" and {"UpperTorso", "Torso"}
        or Config.TargetPart == "Root" and {"HumanoidRootPart"} or {"Head"}
    for _, name in ipairs(names) do
        local part = character:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    return nil -- no silent switch from Head to another body part
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.IgnoreWater = true
local function visible(camera, character, position)
    local hit = Workspace:Raycast(camera.CFrame.Position, position - camera.CFrame.Position, params)
    return hit == nil or hit.Instance:IsDescendantOf(character)
end

local corners = {}
for _, x in ipairs({-1, 1}) do
    for _, y in ipairs({-1, 1}) do
        for _, z in ipairs({-1, 1}) do table.insert(corners, Vector3.new(x, y, z)) end
    end
end
local function drawESP(entry, character, humanoid, camera, distance, player, now)
    if not Config.ESP then entry.box.Visible = false; return end
    if entry.character ~= character or now >= entry.nextBodyUpdate then
        entry.character, entry.nextBodyUpdate, entry.body = character, now + 0.5, {}
        entry.joints = {}
        for _, joint in ipairs(character:GetDescendants()) do
            if joint:IsA("Motor6D") and joint.Part0 and joint.Part1
                and joint.Part0.Parent == character and joint.Part1.Parent == character then
                table.insert(entry.joints, joint)
            end
        end
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                table.insert(entry.body, part)
            end
        end
    end
    if now >= entry.nextVisibility then
        entry.nextVisibility = now + 0.1
        local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
        entry.isVisible = head and visible(camera, character, head.Position) or false
    end
    if Config.ESPVisibleOnly and not entry.isVisible then return end
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, part in ipairs(entry.body) do
        if part.Parent == character then
            local half = part.Size * 0.5
            for _, corner in ipairs(corners) do
                local point = camera:WorldToViewportPoint(part.CFrame:PointToWorldSpace(half * corner))
                if point.Z <= 0.05 then entry.box.Visible = false; return end
                minX, minY = math.min(minX, point.X), math.min(minY, point.Y)
                maxX, maxY = math.max(maxX, point.X), math.max(maxY, point.Y)
            end
        end
    end
    local view = camera.ViewportSize
    if minX == math.huge or maxX < 0 or maxY < 0 or minX > view.X or minY > view.Y then
        entry.box.Visible = false; return
    end
    local width, height = math.max(2, maxX - minX), math.max(2, maxY - minY)
    entry.box.Position = UDim2.fromOffset(minX, minY)
    entry.box.Size = UDim2.fromOffset(width, height)
    entry.box.Visible = true
    local color = selected == player and targetColor or entry.isVisible and accent or accent:Lerp(muted, 0.55)
    entry.outline.Color, entry.outline.Thickness = color, Config.ESPThickness
    entry.outline.Enabled = Config.BoxStyle == "Completa"
    local length, thick = math.min(width, height) * 0.24, Config.ESPThickness
    local geometry = {{0,0,length,thick},{0,0,thick,length},{width-length,0,length,thick},{width-thick,0,thick,length},
        {0,height-thick,length,thick},{0,height-length,thick,length},{width-length,height-thick,length,thick},{width-thick,height-length,thick,length}}
    for i, segment in ipairs(entry.segments) do
        local g = geometry[i]
        segment.Visible = Config.BoxStyle == "Cantos"
        segment.Position, segment.Size = UDim2.fromOffset(g[1],g[2]), UDim2.fromOffset(g[3],g[4])
        segment.BackgroundColor3 = color
    end
    entry.highlight.Parent, entry.highlight.Adornee = camera, character
    entry.highlight.Enabled = Config.ESPHighlight
    entry.highlight.FillColor, entry.highlight.OutlineColor = color, color
    entry.skeleton.Visible = Config.ESPSkeleton
    for _, bone in ipairs(entry.bones) do bone.Visible = false end
    if Config.ESPSkeleton then
        for i, joint in ipairs(entry.joints) do
            local a, b = joint.Part0, joint.Part1
            if a and b then
                local p, pOn = camera:WorldToViewportPoint(a.Position)
                local q, qOn = camera:WorldToViewportPoint(b.Position)
                if pOn and qOn and p.Z > 0 and q.Z > 0 then
                    local line = entry.bones[i]
                    if not line then
                        line = make("Frame", {AnchorPoint = Vector2.new(0.5,0.5), BorderSizePixel = 0}, entry.skeleton)
                        entry.bones[i] = line
                    end
                    local delta = Vector2.new(q.X-p.X,q.Y-p.Y)
                    line.Position = UDim2.fromOffset((p.X+q.X)/2,(p.Y+q.Y)/2)
                    line.Size = UDim2.fromOffset(delta.Magnitude, Config.ESPThickness)
                    line.Rotation = math.deg(math.atan2(delta.Y,delta.X))
                    line.BackgroundColor3, line.Visible = color, true
                end
            end
        end
    end
    local ratio = math.clamp(humanoid.Health / math.max(1, humanoid.MaxHealth), 0, 1)
    entry.healthBack.Position = Config.HealthSide == "Right" and UDim2.new(1, 4, 0, -1) or UDim2.fromOffset(-7, -1)
    entry.health.Size = UDim2.new(1, -2, 0, height * ratio)
    entry.health.BackgroundColor3 = Color3.fromHSV(ratio / 3, 0.8, 1)
    entry.label.Text, entry.label.Visible = player.DisplayName, Config.ESPNames
    entry.below.Text, entry.below.Visible = string.format("%d st", math.floor(distance)), Config.ESPDistance
    entry.hpLabel.Text, entry.hpLabel.Visible = tostring(math.ceil(humanoid.Health)), Config.ESPHealthText
    entry.hpLabel.Position = Config.HealthSide == "Right" and UDim2.new(1, 9, 0, height*(1-ratio)-8)
        or UDim2.fromOffset(-62, height*(1-ratio)-8)
    entry.hpLabel.TextColor3 = entry.health.BackgroundColor3
end

local function steer(camera, part, center, dt, now)
    local origin = camera.CFrame.Position
    local displacement = part.Position - origin
    if displacement.Magnitude < 0.01 then return end
    local currentDirection = camera:ViewportPointToRay(center.X, center.Y).Direction.Unit
    local desiredDirection = displacement.Unit
    local angle = math.acos(math.clamp(currentDirection:Dot(desiredDirection), -1, 1))
    local axis = currentDirection:Cross(desiredDirection)
    if angle <= math.rad(Config.LockAngleDegrees) then trackingLocked = true end
    if angle < 0.00001 or axis.Magnitude < 0.00001 then angularSpeed = 0; return end
    if Config.TrackingMode == "Direto" then
        camera.CFrame = CFrame.new(origin) * CFrame.fromAxisAngle(axis.Unit, angle) * camera.CFrame.Rotation
        trackingLocked, angularSpeed = true, 0
        return
    end
    if trackingLocked then
        -- Follow the same live part each frame; retain the speed cap for abrupt movement.
        local step = math.min(angle, math.rad(Config.MaxDegreesPerSecond) * dt)
        camera.CFrame = CFrame.new(origin) * CFrame.fromAxisAngle(axis.Unit, step) * camera.CFrame.Rotation
        angularSpeed = 0
        return
    end
    local phase = math.clamp((now - selectedAt + dt) / math.max(0.01, Config.AcquireSeconds), 0, 1)
    local ramp = phase * phase * (3 - 2 * phase)
    local desiredSpeed = math.min(angle / math.max(0.01, Config.ResponseSeconds),
        math.rad(Config.MaxDegreesPerSecond)) * ramp
    angularSpeed = angularSpeed + (desiredSpeed - angularSpeed)
        * (1 - math.exp(-dt / math.max(0.01, Config.AccelerationSeconds)))
    local step = math.min(angle, math.max(0, angularSpeed) * dt)
    camera.CFrame = CFrame.new(origin) * CFrame.fromAxisAngle(axis.Unit, step) * camera.CFrame.Rotation
end

local function updateFire(active, choice, camera, center, now)
    local function blocked(reason)
        stopFire()
        fireState = reason
    end
    if not active then blocked("Pausado"); return end
    if not Config.AutoFire then blocked("Disparo automatico desligado"); return end
    if Config.WeaponName == "" then blocked("Vincule a arma na aba Disparo"); return end
    if not choice then blocked("Aguardando alvo"); return end
    local character = LocalPlayer.Character
    local tool = character and character:FindFirstChildOfClass("Tool")
    if not tool or tool.Name ~= Config.WeaponName then blocked("Equipe: " .. Config.WeaponName); return end
    if not tool.Enabled then blocked("Arma desabilitada / em espera"); return end
    local ammo = tool:GetAttribute("Ammo")
    if type(ammo) == "number" and ammo <= 0 then blocked("Sem municao no carregador"); return end
    local handle = tool:FindFirstChild("Handle")
    if tool.RequiresHandle and (not handle or not handle:IsA("BasePart")) then
        blocked("Arma sem Handle valido"); return
    end
    if Input:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then blocked("Disparo manual"); return end
    if choice.character:FindFirstChildOfClass("ForceField") then blocked("Alvo protegido"); return end
    local point, onScreen = camera:WorldToViewportPoint(choice.part.Position)
    if not onScreen or point.Z <= 0
        or (Vector2.new(point.X, point.Y) - center).Magnitude > Config.FireTolerancePixels then
        blocked("Alinhando reticulo"); return
    end
    -- Validate the actual reticle ray AFTER camera correction, even with WallCheck off.
    local ray = camera:ViewportPointToRay(center.X, center.Y)
    local rayLength = (choice.part.Position - ray.Origin).Magnitude + choice.part.Size.Magnitude
    local hit = Workspace:Raycast(ray.Origin, ray.Direction.Unit * rayLength, params)
    if not hit or not hit.Instance:IsDescendantOf(choice.character) then
        blocked("Linha de tiro bloqueada"); return
    end
    if handle and handle:IsA("BasePart") then
        local muzzle = handle:FindFirstChild("Muzzle")
        -- SilencerMuzzle exists too, but its active use has not been verified.
        local origin = muzzle and muzzle:IsA("Attachment") and muzzle.WorldPosition or handle.Position
        local obstruction = Workspace:Raycast(origin, choice.part.Position - origin, params)
        if obstruction and not obstruction.Instance:IsDescendantOf(choice.character) then
            blocked("Obstaculo proximo da arma"); return
        end
    end
    if fireTool and fireTool ~= tool then stopFire() end
    if fireTool and Config.FireMode == "Pulsos" and now >= fireUntil then stopFire() end
    if fireTool then fireState = "Ativacao mantida"; return end
    if now < nextFire then fireState = "Intervalo entre acionamentos"; return end
    -- Remember ownership before Activate so cleanup can always release it on failure.
    fireTool = tool
    local ok, message = pcall(function() tool:Activate() end)
    if not ok then
        blocked("Falha ao acionar Tool")
        Config.AutoFire = false
        refreshUI()
        warn("Zyon: Tool:Activate falhou: " .. tostring(message))
        return
    end
    nextFire = now + Config.FireInterval
    fireUntil = now + math.min(Config.FirePulseSeconds, Config.FireInterval * 0.5)
    fireState = "Comando enviado a arma"
end

local lastStatus = 0
local function frame(deltaTime)
    local camera = Workspace.CurrentCamera
    if not camera then
        overlay.Visible = false
        resetAim()
        return
    end
    local scale = math.clamp(math.min((camera.ViewportSize.X - 32) / 760,
        (camera.ViewportSize.Y - 32) / 550), 0.25, 1)
    panelScale.Scale = scale
    panel.Position = UDim2.fromOffset(
        math.clamp(panel.Position.X.Offset, 0, math.max(0, camera.ViewportSize.X - 760 * scale)),
        math.clamp(panel.Position.Y.Offset, 0, math.max(0, camera.ViewportSize.Y - 550 * scale)))
    hud.Visible = focused
    overlay.Visible = focused
    local center = camera.ViewportSize * 0.5 + Config.ReticleOffset
    circle.Position, circle.Size = UDim2.fromOffset(center.X, center.Y), UDim2.fromOffset(Config.FOV * 2, Config.FOV * 2)
    circle.Visible = Config.Enabled and Config.ShowFOV and Config.Aim and not panel.Visible
    local localCharacter = LocalPlayer.Character
    local ownHumanoid = localCharacter and localCharacter:FindFirstChildOfClass("Humanoid")
    local active = Config.Enabled and focused and (held or Config.AimMode == "Automatico")
        and Config.Aim and not panel.Visible and not GuiService.MenuIsOpen and not Input:GetFocusedTextBox()
        and ownHumanoid and ownHumanoid.Health > 0
        and not Input:IsKeyDown(Enum.KeyCode.LeftAlt) and not Input:IsKeyDown(Enum.KeyCode.RightAlt)
    if not active then resetAim() end
    params.FilterDescendantsInstances = localCharacter and {localCharacter, camera} or {camera}
    local now, candidates, validCount, drawList = os.clock(), {}, 0, {}
    for player, entry in pairs(entries) do
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and (character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head"))
        entry.box.Visible, entry.skeleton.Visible, entry.highlight.Enabled = false, false, false
        if focused and character and character:IsDescendantOf(Workspace) and humanoid and humanoid.Health > 0
            and root and root:IsA("BasePart") and not isExcluded(player) then
            local distance = (root.Position - camera.CFrame.Position).Magnitude
            if distance <= math.max(Config.MaxDistance, Config.ESPDistanceLimit) then
                validCount = validCount + 1
                if distance <= Config.ESPDistanceLimit then table.insert(drawList, {entry, character, humanoid, distance, player}) end
                local part = active and distance <= Config.MaxDistance and targetPart(character)
                if part and not character:FindFirstChildOfClass("ForceField") then
                    local point, onScreen = camera:WorldToViewportPoint(part.Position)
                    local radius = (Vector2.new(point.X, point.Y) - center).Magnitude
                    local limit = selected == player and Config.FOV * Config.RetentionFOVMultiplier or Config.FOV
                    if onScreen and point.Z > 0 and radius <= limit then
                        table.insert(candidates, {player = player, character = character, part = part,
                            score = selected == player and -1 or radius})
                    end
                end
            end
        end
    end
    table.sort(candidates, function(a, b) return a.score < b.score end)
    local choice
    for _, candidate in ipairs(candidates) do
        if not Config.WallCheck or visible(camera, candidate.character, candidate.part.Position) then
            choice = candidate; break
        end
    end
    if choice then
        if selected ~= choice.player or selectedCharacter ~= choice.character then
            stopFire()
            selected, selectedCharacter, selectedAt, angularSpeed = choice.player, choice.character, now, 0
            trackingLocked = false
        end
        steer(camera, choice.part, center, math.clamp(deltaTime, 0, 0.05), now)
    else
        resetAim()
    end
    updateFire(active, choice, camera, center, now)
    for _, data in ipairs(drawList) do drawESP(data[1], data[2], data[3], camera, data[4], data[5], now) end
    if updateCosmetic then updateCosmetic(camera) end
    if now - lastStatus > 0.25 then
        lastStatus = now
        status.Text = string.format("%d personagens  /  %s", validCount, fireState)
        hudTitle.Text = not Config.Enabled and "ZYON / PAUSADO" or panel.Visible and "ZYON / MENU ABERTO"
            or selected and ("ALVO / " .. selected.DisplayName) or "ZYON / AGUARDANDO ALVO"
        hudDetail.Text = fireState
    end
end

RunService:BindToRenderStep(binding, Enum.RenderPriority.Last.Value + 1, function(dt)
    if stopped then return end
    local ok, message = pcall(frame, dt)
    if not ok then
        warn("Zyon Urban Reload encerrado por erro: " .. tostring(message))
        gui:Destroy()
    end
end)
if game.PlaceId ~= 84448037861644 then
    warn("PlaceId diferente do Urban Reload informado: " .. tostring(game.PlaceId))
end
print("Zyon Urban Reload carregado. RightShift: menu. F8: pausar. End: encerrar. Vincule a arma na aba Disparo.")
