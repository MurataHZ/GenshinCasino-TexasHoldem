-- 原神赌场：德州扑克 / 开发阶段的客户端通信测试。
-- 挂载到客户端“容器节点” PokerRoot，不是外层服务器控件容器。
-- PokerRoot 必须直接包含 StatusText（文本框）和 TestButton（预设按钮）。
-- 服务器信号配置见 docs/02-signal-contract.md。此脚本不处理任何资产。

local REQUEST_SIGNAL = "GC_DevPing"
local RESPONSE_SIGNAL = "GC_DevPong"
local TIMEOUT_SECONDS = 5

local root
local statusText
local testButton
local requestId = 0
local awaitingReply = false
local elapsed = 0
local bound = false

local function setStatus(message)
    if statusText and statusText.alive then
        statusText.text = message
    end
end

local function finishWaiting(message)
    awaitingReply = false
    elapsed = 0
    script:EnableUpdate(false)
    if testButton and testButton.alive then
        testButton.interactable = true
    end
    setStatus(message)
end

local function onServerReply(signalName, params)
    if signalName ~= RESPONSE_SIGNAL or not awaitingReply then
        return
    end
    if type(params) ~= "table" or not root or not root.alive then
        return
    end
    -- 这两个编号只关联一次测试请求，不是玩家身份凭据。
    if params[1] ~= root.id or params[2] ~= requestId then
        return
    end
    if type(params[3]) ~= "string" then
        return
    end
    finishWaiting("服务器已回应第 " .. requestId .. " 次请求：\n" .. params[3])
    print("[GC Probe] server reply", requestId)
end

local function onTestClick()
    if awaitingReply or not root or not root.alive then
        return
    end
    requestId = requestId + 1
    awaitingReply = true
    elapsed = 0
    testButton.interactable = false
    setStatus("按钮点击正常；已尝试发送第 " .. requestId .. " 次请求，等待服务器……")
    script:EnableUpdate(true)

    local ok, err = pcall(function()
        local signal = game.ServerSignal(REQUEST_SIGNAL)
        signal:AddInt(root.id)
        signal:AddInt(requestId)
        signal:SendSignal()
    end)
    if not ok then
        finishWaiting("按钮点击正常，但信号发送失败。请检查信号定义与客户端日志。")
        printerr("[GC Probe] send failed: " .. tostring(err))
    end
end

function OnStart()
    script:EnableUpdate(false)
    if bound then
        return
    end

    root = script.object
    if not root or not root.alive then
        printerr("[GC Probe] 脚本应挂载到 PokerRoot 客户端容器节点。")
        return
    end
    statusText = root:GetChild("StatusText")
    testButton = root:GetChild("TestButton")
    if not statusText or not testButton then
        printerr("[GC Probe] PokerRoot 下缺少直接子控件 StatusText 或 TestButton；检查名称、类型和层级。")
        return
    end

    root.showCursor = true
    statusText:SetActive(true)
    statusText:SetVisible(true)
    testButton:SetActive(true)
    testButton:SetVisible(true)
    testButton.raycastTarget = true
    testButton.interactable = true
    testButton:AddCursorEventListener(Enum.CursorEventType.CursorClick, onTestClick)
    script:RegisterServerSignalHandler(RESPONSE_SIGNAL, onServerReply)
    bound = true
    setStatus("客户端脚本已加载。点击“测试连接”检查服务器回应。")
    print("[GC Probe] UI ready", root.id)
end

function OnUpdate(dt)
    if not awaitingReply or type(dt) ~= "number" or dt <= 0 then
        return
    end
    elapsed = elapsed + dt
    if elapsed >= TIMEOUT_SECONDS then
        finishWaiting("按钮点击正常，但 5 秒内未收到服务器回应。\n若尚未接服务器节点，这是预期结果；可再次点击。")
    end
end

function OnDisable()
    if awaitingReply then
        finishWaiting("测试已暂停，请重新点击“测试连接”。")
    end
end

function OnDestroy()
    if bound then
        if testButton and testButton.alive then
            testButton:RemoveCursorEventListener(Enum.CursorEventType.CursorClick, onTestClick)
        end
        script:UnregisterServerSignalHandler(RESPONSE_SIGNAL)
    end
    bound = false
    awaitingReply = false
    root = nil
    statusText = nil
    testButton = nil
end
