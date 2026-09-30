local Recorder = require("recorder")
local I18n = require("i18n")
local t = I18n.text

local PLUGIN_KEY = "process-recorder/aseprite-process-recorder"
local DEFAULT_PLAYBACK_SPEED = 1
local PLAYBACK_SPEEDS = { 1, 2, 5, 10 }
local DEFAULT_MEMORY_BUDGET_MB = 256
local MEMORY_BUDGETS_MB = { 128, 256, 512, 1024 }
local DEFAULT_CAPTURE_MODE = "automatic"
local DEFAULT_VIDEO_SCALE = "auto"
local DEFAULT_AUTO_START = true
local LANGUAGE_NAMES = { zh_CN = "简体中文", en = "English", ja = "日本語" }
local recorder = Recorder.new()
local extensionPlugin = nil
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
local exportPollTimer = nil
local autoStart = DEFAULT_AUTO_START

local function showError(message)
  app.alert {
    title = t("title"),
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
  for _, openSprite in ipairs(app.sprites) do
    if openSprite == sprite then
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
    return t("mode_complete")
  end
  if value == "performance" then
    return t("mode_performance")
  end
  return t("mode_automatic")
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

local function normalizeAutoStart(value)
  if value == nil then
    return DEFAULT_AUTO_START
  end
  return value == true
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
  local callOk, ok, result = pcall(function()
    return recorder:start(sprite, {
      outputDirectory = outputDirectory,
      playbackSpeed = playbackSpeed,
      memoryBudgetBytes = memoryBudgetMb * 1024 * 1024,
      captureProfile = captureMode,
      recordInterval = 1
    })
  end)
  pcall(function()
    app.sprite = sprite
  end)
  automationSuppressed = false
  if not callOk or not ok then
    showError(callOk and result or ok)
    return false
  end
  return true
end

local function setAutoStart(plugin, enabled)
  autoStart = normalizeAutoStart(enabled)
  plugin.preferences.autoStart = autoStart
  if autoStart then
    knownSprites = {}
    if app.sprite ~= nil and not recorder:isRecording()
        and not isRecorderOutput(app.sprite) then
      knownSprites[app.sprite.id] = true
      beginRecording(app.sprite)
    end
  end
end

local function toggleAutoStart()
  setAutoStart(extensionPlugin, not autoStart)
  app.tip(autoStart
    and t("auto_start_on")
    or t("auto_start_off"))
end

local function setLanguage(plugin, value)
  local normalized = I18n.normalize(value)
  if normalized == I18n.language() then
    return
  end
  plugin.preferences.language = I18n.setLanguage(normalized)
  app.tip(t("language_restart"))
end

local function finishRecording(showConfirmation, keepOutputOpen)
  automationSuppressed = true
  local callOk, ok, result = pcall(function()
    return recorder:stop { openOutput = keepOutputOpen }
  end)
  rememberOpenSprites()
  automationSuppressed = false

  if not callOk or not ok then
    showError(callOk and result or ok)
    return false
  end

  if result.pending then
    if showConfirmation then
      app.alert {
        title = t("title"),
        text = {
          t("pending_saved"),
          t("pending_export"),
          t("pending_update"),
          t("manifest") .. result.manifestFilename
        },
        buttons = "OK"
      }
    end
    return true
  end

  if result.cancelled then
    local message
    if result.reason == "source_not_saved" then
      message = t("unsaved_cancelled")
    else
      message = t("unchanged_cancelled")
    end

    if showConfirmation then
      app.alert {
        title = t("title"),
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
      title = t("title"),
      text = {
        t("process_saved"),
        t("frames") .. result.frameCount,
        t("parts") .. result.outputPartCount,
        t("duration") .. string.format("%.3f", result.elapsedMs / 1000) .. t("seconds"),
        t("playback_speed") .. result.playbackSpeed .. t("times"),
        t("mode") .. captureModeLabel(result.captureProfile),
        t("merged") .. result.coalescedEvents .. t("count"),
        t("journal") .. string.format("%.2f MB", result.journalBytes / 1024 / 1024),
        t("file") .. result.outputFilename
      },
      buttons = "OK"
    }
  end
  return true
end

local function showRecordingSettings(plugin)
  local accepted = false
  local modeLabel = captureModeLabel(captureMode)
  local speedLabel = tostring(playbackSpeed) .. t("times")
  if playbackSpeed == DEFAULT_PLAYBACK_SPEED then
    speedLabel = t("speed_default")
  end
  local scaleLabel = videoScale == "auto"
    and t("video_auto")
    or tostring(videoScale) .. t("times")

  local dialog = Dialog { title = t("settings_title") }
  dialog:combobox {
    id = "captureMode",
    label = t("recording_mode"),
    option = modeLabel,
    options = {
      t("mode_complete"),
      t("mode_automatic"),
      t("mode_performance")
    }
  }
  dialog:check {
    id = "autoStart",
    text = t("auto_start_setting"),
    selected = autoStart
  }
  dialog:combobox {
    id = "language",
    label = t("language_setting"),
    option = LANGUAGE_NAMES[I18n.language()],
    options = { LANGUAGE_NAMES.zh_CN, LANGUAGE_NAMES.en, LANGUAGE_NAMES.ja }
  }
  dialog:combobox {
    id = "playbackSpeed",
    label = t("playback_speed"),
    option = speedLabel,
    options = {
      t("speed_default"),
      "2" .. t("times"),
      "5" .. t("times"),
      "10" .. t("times")
    }
  }
  dialog:combobox {
    id = "videoScale",
    label = t("video_scale"),
    option = scaleLabel,
    options = {
      t("video_auto"),
      "1" .. t("times"),
      "2" .. t("times"),
      "4" .. t("times"),
      "6" .. t("times"),
      "8" .. t("times"),
      "10" .. t("times")
    }
  }
  dialog:file {
    id = "ffmpegPath",
    label = t("ffmpeg_setting"),
    title = t("select_ffmpeg"),
    open = true,
    filename = ffmpegPath or "",
    filetypes = app.os.windows and { "exe" } or nil
  }
  dialog:label {
    text = t("automatic_hint")
  }
  dialog:label {
    text = t("performance_hint")
  }
  dialog:button {
    id = "apply",
    text = t("apply"),
    focus = true,
    onclick = function()
      accepted = true
      dialog:close()
    end
  }
  dialog:button { text = t("cancel") }
  dialog:show { wait = true }
  if not accepted then
    return
  end

  local data = dialog.data
  setAutoStart(plugin, data.autoStart == true)
  local newCaptureMode = data.captureMode == t("mode_complete")
    and "complete"
    or (data.captureMode == t("mode_performance")
      and "performance"
      or "automatic")
  local newPlaybackSpeed = normalizePlaybackSpeed(
    tostring(data.playbackSpeed):match("^(%d+)"))
  videoScale = data.videoScale == t("video_auto")
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
  for code, name in pairs(LANGUAGE_NAMES) do
    if data.language == name then
      setLanguage(plugin, code)
      break
    end
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
      t("ffmpeg_missing"),
      t("ffmpeg_choose")
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
    title = t("title"),
    text = {
      t("mp4_exported"),
      t("frames") .. result.frame_count,
      t("hard_scale") .. result.scale .. t("times"),
      t("elapsed") .. string.format("%.2f", result.exportMilliseconds / 1000) .. t("seconds"),
      t("file") .. result.outputFilename
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

local function pollBackgroundExport()
  if not recorder:hasPendingExports() then
    return
  end
  automationSuppressed = true
  local callOk, exportOk, exportResult = pcall(function()
    return recorder:pollExportJob()
  end)
  rememberOpenSprites()
  automationSuppressed = false
  if not callOk then
    showError(exportOk)
  elseif exportOk == false then
    showError(exportResult)
  elseif exportOk == true and type(exportResult) == "table"
      and exportResult.outputSprite ~= nil then
    pcall(function()
      app.sprite = exportResult.outputSprite
    end)
  end
end

local function onSiteChange()
  local sprite = app.sprite
  if automationSuppressed then
    return
  end

  local recordedSprite = recorder:sourceSprite()
  if recordedSprite ~= nil and not spriteIsOpen(recordedSprite) then
    finishRecording(false, false)
    if autoStart and spriteIsOpen(sprite) then
      knownSprites[sprite.id] = true
      if not isRecorderOutput(sprite) then
        beginRecording(sprite)
      end
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

  local switchedRecording = false
  if recorder:isRecording() and recorder:sourceSprite() ~= sprite then
    finishRecording(false, false)
    switchedRecording = true
  end

  if knownSprites[sprite.id] and not switchedRecording then
    return
  end
  knownSprites[sprite.id] = true

  app.sprite = sprite
  if autoStart then
    beginRecording(sprite)
  end
end

function init(plugin)
  extensionPlugin = plugin
  plugin.preferences.language = I18n.setLanguage(plugin.preferences.language)
  if not app.isUIAvailable then
    return
  end
  if app.apiVersion < 23 then
    showError(t("api_required"))
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
  autoStart = normalizeAutoStart(plugin.preferences.autoStart)
  plugin.preferences.autoStart = autoStart
  videoScale = normalizeVideoScale(plugin.preferences.videoScale)
  plugin.preferences.videoScale = videoScale
  helperPath = detectHelperPath(plugin)
  ffmpegPath = detectFfmpegPath(plugin)
  recorder:setHelperPath(helperPath)
  recorder:setMemoryBudget(memoryBudgetMb * 1024 * 1024)
  recorder:recoverExports(outputDirectory)

  rememberOpenSprites()
  automationListener = app.events:on("sitechange", onSiteChange)
  exportPollTimer = Timer {
    interval = 0.10,
    ontick = pollBackgroundExport
  }
  exportPollTimer:start()

  plugin:newMenuGroup {
    id = "process_recorder_menu",
    title = t("title"),
    group = "sprite_crop"
  }

  plugin:newCommand {
    id = "ProcessRecorderSettings",
    title = t("settings_menu"),
    group = "process_recorder_menu",
    onclick = function()
      showRecordingSettings(plugin)
    end
  }

  plugin:newCommand {
    id = "ProcessRecorderAutoStart",
    title = t("auto_start_menu"),
    group = "process_recorder_menu",
    onclick = toggleAutoStart,
    onchecked = function()
      return autoStart
    end
  }

  plugin:newCommand {
    id = "ProcessRecorderStart",
    title = t("start_menu"),
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
    title = t("stop_menu"),
    group = "process_recorder_menu",
    onclick = stopRecording,
    onenabled = function()
      return recorder:isRecording()
    end
  }

  for _, speed in ipairs(PLAYBACK_SPEEDS) do
    local commandSpeed = speed
    local title = t("playback_speed") .. commandSpeed .. t("times")
    if commandSpeed == 1 then
      title = t("speed_original_menu")
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
      title = t("memory_menu") .. commandBudget .. " MB",
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
    title = t("export_menu"),
    group = "process_recorder_menu",
    onclick = exportCompactVideo,
    onenabled = function()
      return app.sprite ~= nil and ffmpegPath ~= nil
    end
  }

  plugin:newMenuGroup {
    id = "process_recorder_language_menu",
    title = t("language_menu"),
    group = "process_recorder_menu"
  }

  for _, option in ipairs({
    { code = "zh_CN", id = "Chinese" },
    { code = "en", id = "English" },
    { code = "ja", id = "Japanese" }
  }) do
    local code = option.code
    plugin:newCommand {
      id = "ProcessRecorderLanguage" .. option.id,
      title = LANGUAGE_NAMES[code],
      group = "process_recorder_language_menu",
      onclick = function()
        setLanguage(plugin, code)
      end,
      onchecked = function()
        return I18n.language() == code
      end
    }
  end

  if autoStart and app.sprite ~= nil then
    beginRecording(app.sprite)
  end
end

function exit(plugin)
  if exportPollTimer ~= nil then
    pcall(function()
      exportPollTimer:stop()
    end)
    exportPollTimer = nil
  end
  if automationListener ~= nil then
    app.events:off(automationListener)
    automationListener = nil
  end
  if recorder:isRecording() then
    finishRecording(false, false)
  end
  recorder:shutdownExports()
end
