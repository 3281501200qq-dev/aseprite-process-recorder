local Recorder = require("recorder")

local PLUGIN_KEY = "process-recorder/aseprite-process-recorder"
local DEFAULT_PLAYBACK_SPEED = 1
local PLAYBACK_SPEEDS = { 1, 2, 5, 10 }
local DEFAULT_MEMORY_BUDGET_MB = 256
local MEMORY_BUDGETS_MB = { 128, 256, 512, 1024 }
local DEFAULT_CAPTURE_MODE = "automatic"
local DEFAULT_VIDEO_SCALE = "auto"
local MODE_COMPLETE_LABEL = "完整模式（每次变化）"
local MODE_AUTOMATIC_LABEL = "自动模式（推荐）"
local MODE_PERFORMANCE_LABEL = "性能模式（大图/长时间）"
local VIDEO_AUTO_LABEL = "自动安全放大（1–10倍）"
local recorder = Recorder.new()
local automationListener = nil
local automationSuppressed = false
local knownSprites = {}
local outputDirectory = nil
local playbackSpeed = DEFAULT_PLAYBACK_SPEED
local memoryBudgetMb = DEFAULT_MEMORY_BUDGET_MB
local captureMode = DEFAULT_CAPTURE_MODE
local videoScale = DEFAULT_VIDEO_SCALE
local helperPath = nil
local ffmpegPath = nil

local function showError(message)
  app.alert {
    title = "绘画过程记录器",
    text = message,
    buttons = "OK"
  }
end

local function isRecorderOutput(sprite)
  if Recorder.isProcessOutput(sprite) then
    return true
  end
  if sprite == nil or outputDirectory == nil then
    return false
  end
  local ok, filename = pcall(function()
    return sprite.filename
  end)
  if not ok or type(filename) ~= "string" or filename == "" then
    return false
  end
  local normalizedFilename = app.fs.normalizePath(filename)
  local normalizedOutput = app.fs.normalizePath(outputDirectory)
  if normalizedFilename:sub(1, #normalizedOutput + 1)
      ~= normalizedOutput .. app.fs.pathSeparator then
    return false
  end
  local title = app.fs.fileTitle(filename)
  return title:match("_timelapse") ~= nil
end

local function rememberOpenSprites()
  for _, sprite in ipairs(app.sprites) do
    knownSprites[sprite.id] = true
  end
end

local function spriteIsOpen(sprite)
  if sprite == nil then
    return false
  end
  local targetId = sprite.id
  for _, openSprite in ipairs(app.sprites) do
    if openSprite.id == targetId then
      return true
    end
  end
  return false
end

local function normalizePlaybackSpeed(value)
  local numericValue = tonumber(value)
  for _, supportedSpeed in ipairs(PLAYBACK_SPEEDS) do
    if numericValue == supportedSpeed then
      return supportedSpeed
    end
  end
  return DEFAULT_PLAYBACK_SPEED
end

local function displayedPlaybackSpeed()
  local sprite = app.sprite
  if isRecorderOutput(sprite) then
    local ok, properties = pcall(function()
      return sprite.properties(PLUGIN_KEY)
    end)
    if ok and properties ~= nil then
      local storedSpeed = tonumber(properties.playbackSpeed) or 1
      for _, supportedSpeed in ipairs(PLAYBACK_SPEEDS) do
        if storedSpeed == supportedSpeed then
          return supportedSpeed
        end
      end
    end
    local markerSpeed = tonumber((sprite.data or ""):match("playback=([^;]+)"))
    if markerSpeed ~= nil then
      return markerSpeed
    end
    return 1
  end
  return playbackSpeed
end

local function normalizeMemoryBudgetMb(value)
  local numericValue = tonumber(value)
  for _, supportedBudget in ipairs(MEMORY_BUDGETS_MB) do
    if numericValue == supportedBudget then
      return supportedBudget
    end
  end
  return DEFAULT_MEMORY_BUDGET_MB
end

local function normalizeCaptureMode(value)
  if value == "complete" or value == "every-change" then
    return "complete"
  end
  if value == "performance" or value == "interval" then
    return "performance"
  end
  return DEFAULT_CAPTURE_MODE
end

local function captureModeLabel(value)
  if value == "complete" then
    return MODE_COMPLETE_LABEL
  end
  if value == "performance" then
    return MODE_PERFORMANCE_LABEL
  end
  return MODE_AUTOMATIC_LABEL
end

local function normalizeVideoScale(value)
  if value == nil or value == "auto" then
    return DEFAULT_VIDEO_SCALE
  end
  local numericValue = tonumber(value)
  for _, supportedScale in ipairs({ 1, 2, 4, 6, 8, 10 }) do
    if numericValue == supportedScale then
      return supportedScale
    end
  end
  return DEFAULT_VIDEO_SCALE
end

local function setMemoryBudget(plugin, budgetMb)
  memoryBudgetMb = normalizeMemoryBudgetMb(budgetMb)
  plugin.preferences.memoryBudgetMb = memoryBudgetMb
  recorder:setMemoryBudget(memoryBudgetMb * 1024 * 1024)
end

local function detectHelperPath(plugin)
  local filename = nil
  if (app.os.macos and (app.os.arm64 or app.os.x64))
      or (app.os.windows and app.os.x64) then
    local pluginPath = plugin.path
    if pluginPath == nil or pluginPath == "" then
      local source = debug.getinfo(1, "S").source or ""
      if source:sub(1, 1) == "@" then
        pluginPath = app.fs.filePath(source:sub(2))
      end
    end
    local helperName
    if app.os.windows then
      helperName = "process-recorder-helper-windows-x64.exe"
    else
      helperName = app.os.arm64
        and "process-recorder-helper-macos-arm64"
        or "process-recorder-helper-macos-x64"
    end
    filename = app.fs.joinPath(
      pluginPath,
      "native/bin/" .. helperName)
  end
  if filename ~= nil and app.fs.isFile(filename) then
    return filename
  end
  return nil
end

local function detectFfmpegPath(plugin)
  local configured = plugin.preferences.ffmpegPath
  if configured ~= nil and configured ~= "" and app.fs.isFile(configured) then
    return configured
  end
  local localAppData = os.getenv("LOCALAPPDATA")
  local pluginPath = plugin.path
  if pluginPath == nil or pluginPath == "" then
    local source = debug.getinfo(1, "S").source or ""
    if source:sub(1, 1) == "@" then
      pluginPath = app.fs.filePath(source:sub(2))
    end
  end
  local candidates = {
    "/opt/homebrew/bin/ffmpeg",
    "/usr/local/bin/ffmpeg",
    app.fs.joinPath(
      app.fs.userConfigPath,
      "ffmpeg/ffmpeg"),
    app.fs.joinPath(
      app.fs.userDocsPath,
      "Library/Application Support/bilibili/ffmpeg/ffmpeg"),
    app.fs.joinPath(app.fs.userConfigPath, "ffmpeg/ffmpeg.exe"),
    "C:\\ffmpeg\\bin\\ffmpeg.exe",
    "C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe"
  }
  if localAppData ~= nil and localAppData ~= "" then
    table.insert(
      candidates,
      1,
      app.fs.joinPath(
        localAppData,
        "Programs/Aseprite Process Recorder/FFmpeg/ffmpeg.exe"))
  end
  if pluginPath ~= nil and pluginPath ~= "" then
    table.insert(
      candidates,
      1,
      app.fs.joinPath(pluginPath, "native/bin/ffmpeg.exe"))
  end
  for _, filename in ipairs(candidates) do
    if app.fs.isFile(filename) then
      return filename
    end
  end
  return nil
end

local function setPlaybackSpeed(plugin, speed)
  playbackSpeed = normalizePlaybackSpeed(speed)
  plugin.preferences.playbackSpeed = playbackSpeed
  recorder:setPlaybackSpeed(playbackSpeed)
  if isRecorderOutput(app.sprite) then
    local ok, retimeError = Recorder.retimeOutput(app.sprite, playbackSpeed)
    if not ok then
      showError(retimeError)
    end
  end
end

local function beginRecording(sprite)
  if not spriteIsOpen(sprite) or isRecorderOutput(sprite) then
    return false
  end

  automationSuppressed = true
  local ok, result = recorder:start(sprite, {
    outputDirectory = outputDirectory,
    playbackSpeed = playbackSpeed,
    memoryBudgetBytes = memoryBudgetMb * 1024 * 1024,
    captureProfile = captureMode,
    recordInterval = 1
  })
  pcall(function()
    app.sprite = sprite
  end)
  automationSuppressed = false
  if not ok then
    showError(result)
    return false
  end
  return true
end

local function finishRecording(showConfirmation, keepOutputOpen)
  automationSuppressed = true
  local ok, result = recorder:stop {
    openOutput = keepOutputOpen
  }
  rememberOpenSprites()
  automationSuppressed = false

  if not ok then
    showError(result)
    return false
  end

  if result.cancelled then
    local message
    if result.reason == "source_not_saved" then
      message = "源画布从未保存，本次记录已取消。"
    else
      message = "没有记录到有效画面变化，本次不生成过程文件。"
    end

    if showConfirmation then
      app.alert {
        title = "绘画过程记录器",
        text = message,
        buttons = "OK"
      }
    end
    return true
  end

  if not keepOutputOpen and result.outputSprite ~= nil then
    result.outputSprite:close()
  end

  if showConfirmation then
    app.alert {
      title = "绘画过程记录器",
      text = {
        "绘画过程已保存。",
        "帧数：" .. result.frameCount,
        "分卷：" .. result.outputPartCount,
        "记录时长：" .. string.format("%.3f 秒", result.elapsedMs / 1000),
        "播放速度：" .. result.playbackSpeed .. "倍",
        "记录模式：" .. captureModeLabel(result.captureProfile),
        "密集事件合并：" .. result.coalescedEvents .. " 次",
        "差分日志：" .. string.format("%.2f MB", result.journalBytes / 1024 / 1024),
        "文件：" .. result.outputFilename
      },
      buttons = "OK"
    }
  end
  return true
end

local function showRecordingSettings(plugin)
  local accepted = false
  local modeLabel = captureModeLabel(captureMode)
  local speedLabel = tostring(playbackSpeed) .. "倍"
  if playbackSpeed == DEFAULT_PLAYBACK_SPEED then
    speedLabel = speedLabel .. "（默认）"
  end
  local scaleLabel = videoScale == "auto"
    and VIDEO_AUTO_LABEL
    or tostring(videoScale) .. "倍"

  local dialog = Dialog { title = "绘画过程记录器设置" }
  dialog:combobox {
    id = "captureMode",
    label = "记录模式：",
    option = modeLabel,
    options = {
      MODE_COMPLETE_LABEL,
      MODE_AUTOMATIC_LABEL,
      MODE_PERFORMANCE_LABEL
    }
  }
  dialog:combobox {
    id = "playbackSpeed",
    label = "播放速度：",
    option = speedLabel,
    options = { "1倍（默认）", "2倍", "5倍", "10倍" }
  }
  dialog:combobox {
    id = "videoScale",
    label = "视频放大：",
    option = scaleLabel,
    options = {
      VIDEO_AUTO_LABEL,
      "1倍", "2倍", "4倍", "6倍", "8倍", "10倍"
    }
  }
  dialog:file {
    id = "ffmpegPath",
    label = "FFmpeg（安装器已配置）:",
    title = "选择 FFmpeg 可执行文件",
    open = true,
    filename = ffmpegPath or "",
    filetypes = app.os.windows and { "exe" } or nil
  }
  dialog:label {
    text = "自动模式：小画布（≤65,536 像素）逐变化；大图仅合并密集事件。"
  }
  dialog:label {
    text = "性能模式：更积极限频；停止时始终补录最终画面。"
  }
  dialog:button {
    id = "apply",
    text = "应用",
    focus = true,
    onclick = function()
      accepted = true
      dialog:close()
    end
  }
  dialog:button { text = "取消" }
  dialog:show { wait = true }
  if not accepted then
    return
  end

  local data = dialog.data
  local newCaptureMode = data.captureMode == MODE_COMPLETE_LABEL
    and "complete"
    or (data.captureMode == MODE_PERFORMANCE_LABEL
      and "performance"
      or "automatic")
  local newPlaybackSpeed = normalizePlaybackSpeed(
    tostring(data.playbackSpeed):match("^(%d+)"))
  videoScale = data.videoScale == VIDEO_AUTO_LABEL
    and DEFAULT_VIDEO_SCALE
    or normalizeVideoScale(tostring(data.videoScale):match("^(%d+)"))
  plugin.preferences.videoScale = videoScale
  local configuredFfmpeg = tostring(data.ffmpegPath or "")
  if configuredFfmpeg ~= "" and app.fs.isFile(configuredFfmpeg) then
    ffmpegPath = configuredFfmpeg
    plugin.preferences.ffmpegPath = configuredFfmpeg
  end
  captureMode = newCaptureMode
  plugin.preferences.captureMode = captureMode
  setPlaybackSpeed(plugin, newPlaybackSpeed)
  if recorder:isRecording() then
    recorder:setCaptureProfile(captureMode)
  end
end

local function exportCompactVideo()
  if recorder:isRecording() then
    local source = recorder:sourceSprite()
    if not finishRecording(false, false) then
      return
    end
    pcall(function()
      app.sprite = source
    end)
  end

  if ffmpegPath == nil or not app.fs.isFile(ffmpegPath) then
    showError {
      "没有找到 FFmpeg。",
      "请在记录器设置中选择 ffmpeg.exe（Windows）或 FFmpeg 可执行文件。"
    }
    return
  end

  local ok, result = recorder:exportVideo(app.sprite, {
    outputDirectory = outputDirectory,
    ffmpegPath = ffmpegPath,
    scale = videoScale,
    fps = 30
  })
  if not ok then
    showError(result)
    return
  end

  app.alert {
    title = "绘画过程记录器",
    text = {
      "紧凑 MP4 已导出。",
      "帧数：" .. result.frame_count,
      "硬边缘放大：" .. result.scale .. "倍",
      "耗时：" .. string.format("%.2f 秒", result.exportMilliseconds / 1000),
      "文件：" .. result.outputFilename
    },
    buttons = "OK"
  }
end

local function startRecording()
  beginRecording(app.sprite)
end

local function stopRecording()
  finishRecording(true, true)
end

local function spriteIsValid(sprite)
  local ok, isValid = pcall(function()
    return sprite.isValid
  end)
  return not ok or isValid ~= false
end

local function onSiteChange()
  local sprite = app.sprite
  if automationSuppressed then
    return
  end

  local recordedSprite = recorder:sourceSprite()
  if recordedSprite ~= nil and not spriteIsValid(recordedSprite) then
    finishRecording(false, false)
    if sprite ~= nil and spriteIsValid(sprite) and spriteIsOpen(sprite) then
      knownSprites[sprite.id] = true
    end
    return
  end

  if sprite == nil then
    if recorder:isRecording() then
      finishRecording(false, false)
    end
    return
  end


  if not spriteIsOpen(sprite) then
    return
  end

  if isRecorderOutput(sprite) then
    knownSprites[sprite.id] = true
    return
  end

  if knownSprites[sprite.id] then
    return
  end
  knownSprites[sprite.id] = true

  if recorder:isRecording() then
    finishRecording(false, false)
  end
  app.sprite = sprite
  beginRecording(sprite)
end

function init(plugin)
  if app.apiVersion < 23 then
    showError("需要 Aseprite 1.3-rc3 或更高版本（API 23）。")
    return
  end

  outputDirectory = plugin.preferences.outputDirectory
  if outputDirectory == nil or outputDirectory == "" then
    outputDirectory = app.fs.joinPath(
      app.fs.userDocsPath,
      "Aseprite Process Recordings")
    plugin.preferences.outputDirectory = outputDirectory
  end

  playbackSpeed = normalizePlaybackSpeed(plugin.preferences.playbackSpeed)
  plugin.preferences.playbackSpeed = playbackSpeed
  memoryBudgetMb = normalizeMemoryBudgetMb(plugin.preferences.memoryBudgetMb)
  plugin.preferences.memoryBudgetMb = memoryBudgetMb
  captureMode = normalizeCaptureMode(plugin.preferences.captureMode)
  plugin.preferences.captureMode = captureMode
  videoScale = normalizeVideoScale(plugin.preferences.videoScale)
  plugin.preferences.videoScale = videoScale
  helperPath = detectHelperPath(plugin)
  ffmpegPath = detectFfmpegPath(plugin)
  recorder:setHelperPath(helperPath)
  recorder:setMemoryBudget(memoryBudgetMb * 1024 * 1024)

  rememberOpenSprites()
  automationListener = app.events:on("sitechange", onSiteChange)

  plugin:newMenuGroup {
    id = "process_recorder_menu",
    title = "绘画过程记录器",
    group = "sprite_crop"
  }

  plugin:newCommand {
    id = "ProcessRecorderSettings",
    title = "记录器设置…",
    group = "process_recorder_menu",
    onclick = function()
      showRecordingSettings(plugin)
    end
  }

  plugin:newCommand {
    id = "ProcessRecorderStart",
    title = "开始记录",
    group = "process_recorder_menu",
    onclick = startRecording,
    onenabled = function()
      return not recorder:isRecording()
        and app.sprite ~= nil
        and not isRecorderOutput(app.sprite)
    end
  }

  plugin:newCommand {
    id = "ProcessRecorderStop",
    title = "停止并保存",
    group = "process_recorder_menu",
    onclick = stopRecording,
    onenabled = function()
      return recorder:isRecording()
    end
  }

  for _, speed in ipairs(PLAYBACK_SPEEDS) do
    local commandSpeed = speed
    local title = "播放速度：" .. commandSpeed .. "倍"
    if commandSpeed == 1 then
      title = "播放速度：原速（1倍）"
    end

    plugin:newCommand {
      id = "ProcessRecorderSpeed" .. commandSpeed .. "x",
      title = title,
      group = "process_recorder_menu",
      onclick = function()
        setPlaybackSpeed(plugin, commandSpeed)
      end,
      onchecked = function()
        return displayedPlaybackSpeed() == commandSpeed
      end
    }
  end

  for _, budgetMb in ipairs(MEMORY_BUDGETS_MB) do
    local commandBudget = budgetMb
    plugin:newCommand {
      id = "ProcessRecorderMemory" .. commandBudget .. "MB",
      title = "记录器内存预算：" .. commandBudget .. " MB",
      group = "process_recorder_menu",
      onclick = function()
        setMemoryBudget(plugin, commandBudget)
      end,
      onchecked = function()
        return memoryBudgetMb == commandBudget
      end
    }
  end

  plugin:newCommand {
    id = "ProcessRecorderExportMP4",
    title = "导出紧凑 MP4",
    group = "process_recorder_menu",
    onclick = exportCompactVideo,
    onenabled = function()
      return app.sprite ~= nil and ffmpegPath ~= nil
    end
  }

  if app.sprite ~= nil then
    beginRecording(app.sprite)
  end
end

function exit(plugin)
  if automationListener ~= nil then
    app.events:off(automationListener)
    automationListener = nil
  end
  if recorder:isRecording() then
    finishRecording(false, false)
  end
end
