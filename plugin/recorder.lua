local Journal = require("journal")

local Recorder = {}
Recorder.__index = Recorder

local PLUGIN_KEY = "process-recorder/aseprite-process-recorder"
local DEFAULT_OUTPUT_FOLDER = "Aseprite Process Recordings"
local DATA_FOLDER = ".process-recorder-data"
local MANIFEST_SUFFIX = ".process-recorder.json"
local PROCESS_MARKER = "ASEPR_TIMELAPSE"
local MAX_FRAME_DURATION_MS = 65535
local DEFAULT_MAX_PART_FRAMES = 50000
local DEFAULT_MAX_PART_BYTES = 1536 * 1024 * 1024
local DEFAULT_MEMORY_BUDGET = 256 * 1024 * 1024
local DEFAULT_RECORD_INTERVAL = 1
local MAX_RECORD_INTERVAL = 128
local OPEN_OUTPUT_FRAME_LIMIT = 2000
local OPEN_OUTPUT_BYTE_LIMIT = 128 * 1024 * 1024
local OPEN_OUTPUT_DECODED_LIMIT = 256 * 1024 * 1024
local DEFAULT_CAPTURE_PROFILE = "automatic"

local function defaultHelperPath()
  local source = debug.getinfo(1, "S").source or ""
  if source:sub(1, 1) ~= "@" then
    return nil
  end
  local directory = app.fs.filePath(source:sub(2))
  local helperName = nil
  if app.os.macos then
    helperName = app.os.arm64
      and "process-recorder-helper-macos-arm64"
      or (app.os.x64 and "process-recorder-helper-macos-x64" or nil)
  elseif app.os.windows and app.os.x64 then
    helperName = "process-recorder-helper-windows-x64.exe"
  end
  if helperName == nil then
    return nil
  end
  local filename = app.fs.joinPath(directory, "native/bin/" .. helperName)
  return app.fs.isFile(filename) and filename or nil
end

local CAPTURE_EVENTS = {
  "change",
  "layerblendmode",
  "layeropacity",
  "layervisibility"
}

local function roundMilliseconds(seconds)
  return math.floor(seconds * 1000 + 0.5)
end

local function clampFrameDuration(milliseconds)
  return math.max(1, math.min(MAX_FRAME_DURATION_MS, milliseconds))
end

local function normalizePlaybackSpeed(value)
  local numericValue = tonumber(value)
  if numericValue == nil or numericValue <= 0 then
    return 1
  end
  return numericValue
end

local function normalizeMemoryBudget(value)
  local numericValue = tonumber(value)
  if numericValue == nil or numericValue < 64 * 1024 * 1024 then
    return DEFAULT_MEMORY_BUDGET
  end
  return math.floor(numericValue)
end

local function normalizeRecordInterval(value)
  local numericValue = tonumber(value)
  if numericValue == nil then
    return DEFAULT_RECORD_INTERVAL
  end
  return math.max(1, math.min(MAX_RECORD_INTERVAL, math.floor(numericValue)))
end

local function normalizeCaptureProfile(value)
  if value == "complete" or value == "performance" then
    return value
  end
  return DEFAULT_CAPTURE_PROFILE
end

local function captureDelaySeconds(sprite, profile)
  if profile == "complete" then
    return 0
  end
  local pixelCount = math.max(1, sprite.width * sprite.height)
  if profile == "performance" then
    if pixelCount <= 256 * 256 then
      return 0.05
    elseif pixelCount <= 512 * 512 then
      return 0.10
    elseif pixelCount <= 1024 * 1024 then
      return 0.18
    end
    return 0.25
  end
  if pixelCount <= 256 * 256 then
    return 0
  elseif pixelCount <= 512 * 512 then
    return 0.05
  elseif pixelCount <= 1024 * 1024 then
    return 0.10
  end
  return 0.15
end

local function normalizeOutputStride(value)
  local numericValue = tonumber(value)
  if numericValue == nil then
    return 1
  end
  return math.max(1, math.min(0xffffffff, math.floor(numericValue)))
end

local function scaleFrameDuration(milliseconds, playbackSpeed)
  return math.max(1, math.floor(milliseconds / playbackSpeed + 0.5))
end

local function renderFrame(sprite, frameNumber)
  local spec = ImageSpec {
    width = sprite.width,
    height = sprite.height,
    colorMode = ColorMode.RGB
  }
  if sprite.colorSpace ~= nil then
    spec.colorSpace = sprite.colorSpace
  end

  local image = Image(spec)
  image:drawSprite(sprite, frameNumber)
  return image
end

local function activeFrameNumberFor(sprite, fallback)
  if app.sprite == sprite and app.frame ~= nil then
    return app.frame.frameNumber
  end
  return fallback or 1
end

local function sanitizeFilename(filename)
  local sanitized = filename:gsub("[\\/:*?\"<>|]", "_")
  sanitized = sanitized:gsub("^%s+", ""):gsub("%s+$", "")
  if sanitized == "" then
    return "Untitled"
  end
  return sanitized
end

local function defaultOutputDirectory()
  return app.fs.joinPath(app.fs.userDocsPath, DEFAULT_OUTPUT_FOLDER)
end

local function normalizedPath(filename)
  if filename == nil or filename == "" then
    return ""
  end
  return app.fs.normalizePath(filename)
end

local function isGeneratedOutputPath(filename, outputDirectory)
  if filename == nil or filename == "" or outputDirectory == nil then
    return false
  end
  local normalizedFilename = normalizedPath(filename)
  local normalizedOutput = normalizedPath(outputDirectory)
  if normalizedFilename:sub(1, #normalizedOutput + 1)
      ~= normalizedOutput .. app.fs.pathSeparator then
    return false
  end
  return app.fs.fileTitle(filename):match("_timelapse") ~= nil
end

local function shellQuote(value)
  if app.os.windows then
    return '"' .. tostring(value):gsub('"', '""') .. '"'
  end
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local BASE64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function base64Encode(value)
  local encoded = {}
  for index = 1, #value, 3 do
    local first = value:byte(index)
    local second = value:byte(index + 1)
    local third = value:byte(index + 2)
    local combined = first * 65536 + (second or 0) * 256 + (third or 0)
    local firstIndex = math.floor(combined / 262144) % 64
    local secondIndex = math.floor(combined / 4096) % 64
    local thirdIndex = math.floor(combined / 64) % 64
    local fourthIndex = combined % 64
    encoded[#encoded + 1] = BASE64_ALPHABET:sub(firstIndex + 1, firstIndex + 1)
    encoded[#encoded + 1] = BASE64_ALPHABET:sub(secondIndex + 1, secondIndex + 1)
    encoded[#encoded + 1] = second
      and BASE64_ALPHABET:sub(thirdIndex + 1, thirdIndex + 1)
      or "="
    encoded[#encoded + 1] = third
      and BASE64_ALPHABET:sub(fourthIndex + 1, fourthIndex + 1)
      or "="
  end
  return table.concat(encoded)
end

local function osCommandSucceeded(first, second, third)
  if type(first) == "boolean" then
    return first and (third == nil or third == 0)
  end
  if type(first) == "number" then
    return first == 0
  end
  return second == "exit" and third == 0
end

local commandSequence = 0

local function executeWindowsCommand(arguments)
  commandSequence = commandSequence + 1
  local encodedArguments = {}
  for _, argument in ipairs(arguments) do
    encodedArguments[#encodedArguments + 1] = "'"
      .. base64Encode(tostring(argument)) .. "'"
  end
  local scriptFilename = app.fs.joinPath(
    app.fs.tempPath,
    string.format(
      "aseprite-process-recorder-%s-%d-%d.ps1",
      os.date("%Y%m%d%H%M%S"),
      commandSequence,
      math.random(0, 0x7fffffff)))
  local script, scriptError = io.open(scriptFilename, "wb")
  if script == nil then
    return false, scriptError
  end
  script:write("$ErrorActionPreference='Stop'\r\n")
  script:write("$d=[Text.Encoding]::UTF8\r\n")
  script:write("$a=@()\r\n")
  script:write(
    "foreach($v in @(",
    table.concat(encodedArguments, ","),
    ")){$a+=$d.GetString([Convert]::FromBase64String($v))}\r\n")
  script:write(
    "try{$e=$a[0];$r=$a[1..($a.Count-1)];& $e @r;",
    "exit $LASTEXITCODE}",
    "catch{[Console]::Error.WriteLine($_.Exception.Message);exit 1}\r\n")
  script:close()
  local first, second, third = os.execute(
    "powershell.exe -NoLogo -NoProfile -NonInteractive "
      .. "-ExecutionPolicy Bypass -File " .. scriptFilename)
  os.remove(scriptFilename)
  return osCommandSucceeded(first, second, third)
end

local function executeCommand(arguments)
  if app.os.windows then
    return executeWindowsCommand(arguments)
  end
  local quoted = {}
  for index, argument in ipairs(arguments) do
    quoted[index] = shellQuote(argument)
  end
  local first, second, third = os.execute(table.concat(quoted, " "))
  return osCommandSucceeded(first, second, third)
end

local function startsWith(value, prefix)
  return type(value) == "string" and value:sub(1, #prefix) == prefix
end

local function isProcessOutput(sprite)
  if sprite == nil then
    return false
  end
  local ok, result = pcall(function()
    local properties = sprite.properties(PLUGIN_KEY)
    return (properties ~= nil and properties.schemaVersion ~= nil)
      or startsWith(sprite.data, PROCESS_MARKER)
  end)
  return ok and result
end

local function parseKeyValueText(value)
  local parsed = {}
  if type(value) ~= "string" then
    return parsed
  end
  for key, item in value:gmatch("([%w_]+)=([^;\n]+)") do
    parsed[key] = item
  end
  return parsed
end

local function recordingCandidateIndex(filename, prefix)
  if filename == prefix .. ".aseprite" then
    return 1
  end
  if filename:sub(1, #prefix + 1) ~= prefix .. "_"
      or filename:sub(-9) ~= ".aseprite" then
    return 0
  end
  return tonumber(filename:sub(#prefix + 2, -10)) or 0
end

local function findLegacyRecordingForSource(outputDirectory, sourceTitle, sourceFilename)
  if sourceFilename == "" or not app.fs.isDirectory(outputDirectory) then
    return nil
  end

  local prefix = sanitizeFilename(sourceTitle) .. "_timelapse"
  local normalizedSource = normalizedPath(sourceFilename)
  local bestFilename = nil
  local bestIndex = 0

  for _, relativeFilename in ipairs(app.fs.listFiles(outputDirectory)) do
    local candidateIndex = recordingCandidateIndex(relativeFilename, prefix)
    if candidateIndex > 0 and candidateIndex >= bestIndex then
      local candidateFilename = app.fs.joinPath(outputDirectory, relativeFilename)
      local ok, matches = pcall(function()
        local candidate = Sprite { fromFile = candidateFilename }
        local properties = candidate.properties(PLUGIN_KEY)
        local candidateSource = normalizedPath(properties.sourceFilename)
        local legacy = properties.schemaVersion == 1
        candidate:close()
        return legacy and candidateSource == normalizedSource
      end)

      if ok and matches then
        bestFilename = candidateFilename
        bestIndex = candidateIndex
      end
    end
  end

  return bestFilename
end

local function manifestFilenameForBase(base)
  return base .. MANIFEST_SUFFIX
end

local function makeAvailableBase(outputDirectory, sourceTitle)
  local root = app.fs.joinPath(
    outputDirectory,
    sanitizeFilename(sourceTitle) .. "_timelapse")
  local base = root
  local suffix = 2

  while app.fs.isFile(manifestFilenameForBase(base))
      or app.fs.isFile(base .. ".aseprite") do
    base = root .. "_" .. suffix
    suffix = suffix + 1
  end
  return base
end

local function findManifestForSource(outputDirectory, sourceFilename)
  if sourceFilename == "" or not app.fs.isDirectory(outputDirectory) then
    return nil, nil
  end
  local normalizedSource = normalizedPath(sourceFilename)
  local bestManifest = nil
  local bestFilename = nil
  local bestElapsed = -1

  for _, relativeFilename in ipairs(app.fs.listFiles(outputDirectory)) do
    if relativeFilename:sub(-#MANIFEST_SUFFIX) == MANIFEST_SUFFIX then
      local filename = app.fs.joinPath(outputDirectory, relativeFilename)
      local manifest = Journal.readJson(filename)
      if manifest ~= nil
          and manifest.schemaVersion == 2
          and normalizedPath(manifest.sourceFilename) == normalizedSource
          and tonumber(manifest.elapsedMs or 0) >= bestElapsed then
        bestManifest = manifest
        bestFilename = filename
        bestElapsed = tonumber(manifest.elapsedMs or 0)
      end
    end
  end
  return bestManifest, bestFilename
end

local function makeSessionId(sprite)
  local random = math.random(0, 0x7fffffff)
  return string.format(
    "%s-%s-%08x",
    os.date("%Y%m%d-%H%M%S"),
    tostring(sprite.id or 0),
    random)
end

local function copySegments(segments)
  local copied = {}
  for index, segment in ipairs(segments or {}) do
    copied[index] = {
      filename = segment.filename,
      recordCount = segment.recordCount,
      firstTimestampMs = segment.firstTimestampMs,
      lastTimestampMs = segment.lastTimestampMs,
      bytes = segment.bytes,
      checkpointCount = segment.checkpointCount,
      changedTileCount = segment.changedTileCount,
      rawPixelBytes = segment.rawPixelBytes,
      encodedPixelBytes = segment.encodedPixelBytes,
      captureInterval = normalizeRecordInterval(segment.captureInterval),
      outputStride = normalizeOutputStride(segment.outputStride)
    }
  end
  return copied
end

local function parseReport(filename)
  local file = io.open(filename, "rb")
  if file == nil then
    return nil
  end
  local report = { files = {} }
  for line in file:lines() do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key == "file" then
      report.files[#report.files + 1] = value
    elseif key ~= nil then
      report[key] = tonumber(value) or value
    end
  end
  file:close()
  return report
end

local function fileBase(filename)
  if filename:sub(-9) == ".aseprite" then
    return filename:sub(1, -10)
  end
  return filename
end

function Recorder.new(options)
  options = options or {}
  return setmetatable({
    session = nil,
    helperPath = options.helperPath or defaultHelperPath(),
    memoryBudgetBytes = normalizeMemoryBudget(options.memoryBudgetBytes)
  }, Recorder)
end

function Recorder:setHelperPath(filename)
  self.helperPath = filename
end

function Recorder:setMemoryBudget(bytes)
  self.memoryBudgetBytes = normalizeMemoryBudget(bytes)
  if self.session ~= nil then
    self.session.memoryBudgetBytes = self.memoryBudgetBytes
  end
end

function Recorder:isRecording()
  return self.session ~= nil
end

function Recorder:sourceSprite()
  if self.session == nil then
    return nil
  end
  return self.session.sourceSprite
end

function Recorder:setPlaybackSpeed(speed)
  if self.session ~= nil then
    self.session.playbackSpeed = normalizePlaybackSpeed(speed)
  end
end

function Recorder:setCaptureProfile(profile)
  local normalizedProfile = normalizeCaptureProfile(profile)
  if self.session == nil then
    return normalizedProfile
  end
  local session = self.session
  self:_flushDeferredCapture(session)
  session.captureProfile = normalizedProfile
  session.captureDelaySeconds = captureDelaySeconds(
    session.sourceSprite,
    normalizedProfile)
  session.settingsChanged = true
  return normalizedProfile
end

function Recorder:setRecordInterval(interval, explicitChange)
  local recordInterval = normalizeRecordInterval(interval)
  if self.session == nil then
    return recordInterval
  end

  local session = self.session
  if session.recordInterval == recordInterval then
    return recordInterval
  end

  local baseInterval = session.baseManifest ~= nil
    and normalizeRecordInterval(session.baseManifest.recordInterval)
    or DEFAULT_RECORD_INTERVAL
  session.recordInterval = recordInterval
  session.changesSinceCapture = 0
  session.settingsChanged = explicitChange == true or session.settingsChanged
  session.thinExistingStride = session.baseManifest ~= nil
      and recordInterval > 1
      and recordInterval ~= baseInterval
    and recordInterval
    or 1
  if session.writer ~= nil or session.pendingCapture ~= nil then
    session.currentSegmentOutputStride = recordInterval > 1
      and recordInterval
      or 1
  end
  return recordInterval
end

function Recorder.isProcessOutput(sprite)
  return isProcessOutput(sprite)
end

function Recorder.outputCelMetadata(cel)
  if cel == nil then
    return {}
  end
  local properties = cel.properties(PLUGIN_KEY)
  if properties ~= nil and properties.timestampMs ~= nil then
    return {
      timestampMs = tonumber(properties.timestampMs),
      intervalMs = tonumber(properties.intervalMs),
      sourceFrameNumber = tonumber(properties.sourceFrameNumber) or 1,
      fromUndo = properties.fromUndo == true,
      eventName = properties.eventName
    }
  end
  local parsed = parseKeyValueText(cel.data)
  return {
    timestampMs = tonumber(parsed.timestamp_ms),
    intervalMs = tonumber(parsed.interval_ms),
    sourceFrameNumber = tonumber(parsed.source_frame) or 1,
    fromUndo = tonumber(parsed.from_undo) == 1,
    eventName = parsed.event
  }
end

function Recorder.outputMetadata(sprite)
  if sprite == nil or not isProcessOutput(sprite) then
    return nil
  end
  local properties = sprite.properties(PLUGIN_KEY)
  if properties ~= nil
      and properties.schemaVersion == 1
      and properties.timestampsMs ~= nil then
    return properties
  end

  local marker = parseKeyValueText(sprite.data)
  local timestamps = {}
  local durationWasClamped = false
  local playbackSpeed = tonumber(properties.playbackSpeed)
    or tonumber(marker.playback)
    or 1
  for index, frame in ipairs(sprite.frames) do
    local cel = sprite.layers[1]:cel(frame)
    local metadata = Recorder.outputCelMetadata(cel)
    timestamps[index] = metadata.timestampMs or 0
    if metadata.intervalMs ~= nil then
      local requested = scaleFrameDuration(metadata.intervalMs, playbackSpeed)
      durationWasClamped = durationWasClamped
        or requested ~= clampFrameDuration(requested)
    end
  end
  return {
    schemaVersion = 2,
    frameCount = #sprite.frames,
    sourceFilename = marker.source or properties.sourceFilename,
    playbackSpeed = playbackSpeed,
    recordInterval = tonumber(marker.record_interval)
      or tonumber(properties.recordInterval)
      or 1,
    timestampsMs = timestamps,
    durationWasClamped = durationWasClamped,
    externalJournal = true
  }
end

function Recorder.retimeOutput(sprite, speed)
  if sprite == nil or not isProcessOutput(sprite) then
    return false, "请先打开过程记录文件，再修改播放速度。"
  end

  local playbackSpeed = normalizePlaybackSpeed(speed)
  local durationWasClamped = false

  app.transaction("Change process playback speed", function()
    for _, frame in ipairs(sprite.frames) do
      local cel = sprite.layers[1]:cel(frame)
      if cel ~= nil then
        local properties = cel.properties(PLUGIN_KEY)
        local textValues = parseKeyValueText(cel.data)
        local originalIntervalMs = tonumber(properties.intervalMs)
          or tonumber(textValues.interval_ms)
          or math.floor(frame.duration * 1000 + 0.5)
        local playbackDurationMs = scaleFrameDuration(
          originalIntervalMs,
          playbackSpeed)
        local storedDurationMs = clampFrameDuration(playbackDurationMs)
        local wasClamped = playbackDurationMs ~= storedDurationMs

        durationWasClamped = durationWasClamped or wasClamped
        frame.duration = (storedDurationMs + 0.5) / 1000
        properties.intervalMs = originalIntervalMs
        properties.intervalWasClamped = wasClamped
        properties.playbackIntervalMs = playbackDurationMs
        properties.playbackSpeed = playbackSpeed
      end
    end

    local metadata = sprite.properties(PLUGIN_KEY)
    metadata.schemaVersion = metadata.schemaVersion or 2
    metadata.durationWasClamped = durationWasClamped
    metadata.playbackSpeed = playbackSpeed
    metadata.externalJournal = startsWith(sprite.data, PROCESS_MARKER)
  end)

  return true, {
    frameCount = #sprite.frames,
    playbackSpeed = playbackSpeed
  }
end

function Recorder:_elapsedMilliseconds()
  return roundMilliseconds(os.clock() - self.session.startedAt)
end

function Recorder:_segmentDirectory(session)
  return app.fs.joinPath(session.outputDirectory, DATA_FOLDER)
end

function Recorder:_ensureWriter(session)
  if session.writer ~= nil then
    return session.writer
  end
  local directory = self:_segmentDirectory(session)
  if not app.fs.isDirectory(directory)
      and not app.fs.makeAllDirectories(directory) then
    error("无法创建过程数据目录：" .. directory)
  end
  local filename = app.fs.joinPath(directory, session.sessionId .. ".aprlog")
  local writer, writerError = Journal.newWriter(filename, {
    memoryBudgetBytes = session.memoryBudgetBytes,
    tileSize = 64,
    checkpointRecords = 1000,
    checkpointBytes = 64 * 1024 * 1024
  })
  if writer == nil then
    error("无法创建过程日志：" .. tostring(writerError))
  end
  session.writer = writer
  session.segmentFilename = filename

  local baselineAdded, baselineStats = writer:appendImage(session.initialImage, {
    timestampMs = session.resumeOffsetMs,
    sourceFrameNumber = session.initialFrameNumber,
    eventName = session.historyCount > 0 and "resume" or "initial",
    fromUndo = false
  })
  if not baselineAdded then
    error("无法写入过程记录的初始画面。")
  end
  session.lastCaptureStats = baselineStats
  return writer
end

function Recorder:_appendCapture(session, image, record)
  local writer = self:_ensureWriter(session)
  local added, captureStats = writer:appendImage(image, record)
  if not added then
    return false
  end
  session.lastCaptureStats = captureStats
  return true
end

function Recorder:_flushPendingCapture(session)
  if session.pendingCapture == nil then
    return false
  end
  local pending = session.pendingCapture
  session.pendingCapture = nil
  session.changesSinceCapture = 0
  return self:_appendCapture(session, pending.image, pending.record)
end

function Recorder:_stopCaptureTimer(session)
  if session.captureTimer ~= nil then
    pcall(function()
      session.captureTimer:stop()
    end)
    session.captureTimer = nil
  end
end

function Recorder:_flushDeferredCapture(session)
  if session.deferredCapture == nil then
    return false
  end
  self:_stopCaptureTimer(session)
  local deferred = session.deferredCapture
  session.deferredCapture = nil
  return self:_capture(deferred.eventName, {
    fromUndo = deferred.fromUndo
  })
end

function Recorder:_scheduleCapture(eventName, event)
  local session = self.session
  if session.captureDelaySeconds <= 0 then
    return self:_capture(eventName, event)
  end

  if session.deferredCapture ~= nil then
    session.coalescedEvents = session.coalescedEvents + 1
  end
  session.deferredCapture = {
    eventName = eventName,
    fromUndo = event ~= nil and event.fromUndo == true
  }
  if session.captureTimer ~= nil then
    return true
  end

  session.captureTimer = Timer {
    interval = session.captureDelaySeconds,
    ontick = function()
      if self.session ~= session then
        self:_stopCaptureTimer(session)
        return
      end
      self:_handleDeferredCapture(session)
    end
  }
  session.captureTimer:start()
  return true
end

function Recorder:_capture(eventName, event)
  self:_updateSourceIdentity()
  local session = self.session
  local timestampMs = session.resumeOffsetMs + self:_elapsedMilliseconds()
  local frameNumber = activeFrameNumberFor(session.sourceSprite, session.sourceFrameNumber)
  local image = renderFrame(session.sourceSprite, frameNumber)

  session.sourceFrameNumber = frameNumber
  if session.currentImage:isEqual(image) then
    session.duplicateEvents = session.duplicateEvents + 1
    return false
  end

  local record = {
    timestampMs = timestampMs,
    sourceFrameNumber = frameNumber,
    eventName = eventName,
    fromUndo = event ~= nil and event.fromUndo == true
  }
  session.currentImage = image
  session.hasSessionChanges = true
  session.sessionChangeCount = session.sessionChangeCount + 1
  session.changesSinceCapture = session.changesSinceCapture + 1
  session.pendingCapture = {
    image = image,
    record = record
  }

  if session.recordInterval == 1
      or session.changesSinceCapture >= session.recordInterval then
    self:_flushPendingCapture(session)
  end
  return true
end

function Recorder:_stopFlushTimer(session)
  if session.flushTimer ~= nil then
    pcall(function()
      session.flushTimer:stop()
    end)
    session.flushTimer = nil
  end
end

function Recorder:_discardSessionWriter(session)
  if session.writer ~= nil then
    session.writer:discard()
  end
  local directory = self:_segmentDirectory(session)
  if app.fs.isDirectory(directory) and #app.fs.listFiles(directory) == 0 then
    app.fs.removeDirectory(directory)
  end
end

function Recorder:_detachListeners()
  local session = self.session
  if session == nil then
    return
  end
  self:_stopFlushTimer(session)
  self:_stopCaptureTimer(session)
  for _, listenerCode in ipairs(session.listenerCodes) do
    pcall(function()
      session.sourceSprite.events:off(listenerCode)
    end)
  end
  session.listenerCodes = {}
end

function Recorder:_updateSourceIdentity()
  local session = self.session
  if session == nil then
    return
  end

  pcall(function()
    local displayedFilename = session.sourceSprite.filename or ""
    if displayedFilename ~= "" then
      session.sourceTitle = app.fs.fileTitle(displayedFilename)
    end
    if session.sourceSprite.hasAssociatedFile == true then
      session.sourceFilename = normalizedPath(displayedFilename)
    end
    if isGeneratedOutputPath(displayedFilename, session.outputDirectory) then
      session.becameProcessOutput = true
    end
  end)
end

function Recorder:_handleCaptureEvent(eventName, event)
  local ok, captureError = pcall(function()
    self:_scheduleCapture(eventName, event)
  end)

  if ok then
    return
  end

  self.session.captureError = tostring(captureError)
  self:_detachListeners()
  app.alert {
    title = "绘画过程记录器",
    text = {
      "发生错误，过程记录已暂停。",
      self.session.captureError,
      "错误发生前的记录已经安全写入磁盘。"
    },
    buttons = "OK"
  }
end

function Recorder:_handleDeferredCapture(session)
  local ok, captureError = pcall(function()
    self:_flushDeferredCapture(session)
  end)
  if ok then
    return
  end
  session.captureError = tostring(captureError)
  self:_detachListeners()
  app.alert {
    title = "绘画过程记录器",
    text = {
      "发生错误，过程记录已暂停。",
      session.captureError,
      "错误发生前的记录已经安全写入磁盘。"
    },
    buttons = "OK"
  }
end

function Recorder:_attachListeners()
  local session = self.session
  for _, eventName in ipairs(CAPTURE_EVENTS) do
    local capturedEventName = eventName
    local listenerCode = session.sourceSprite.events:on(eventName, function(event)
      self:_handleCaptureEvent(capturedEventName, event)
    end)
    table.insert(session.listenerCodes, listenerCode)
  end

  local filenameListenerCode = session.sourceSprite.events:on("filenamechange", function()
    self:_updateSourceIdentity()
  end)
  table.insert(session.listenerCodes, filenameListenerCode)

  session.flushTimer = Timer {
    interval = 5.0,
    ontick = function()
      if self.session == session and session.writer ~= nil then
        pcall(function()
          session.writer:flush()
        end)
      end
    end
  }
  session.flushTimer:start()
end

function Recorder:_migrateLegacyRecording(
  outputDirectory,
  sourceTitle,
  sourceFilename,
  recordingFilename)
  local recording = Sprite { fromFile = recordingFilename }
  local metadata = recording.properties(PLUGIN_KEY)
  local timestamps = metadata.timestampsMs or {}
  local dataDirectory = app.fs.joinPath(outputDirectory, DATA_FOLDER)
  if not app.fs.isDirectory(dataDirectory)
      and not app.fs.makeAllDirectories(dataDirectory) then
    recording:close()
    return nil, nil, "Could not create the process data directory."
  end

  local sessionId = makeSessionId(recording) .. "-migration"
  local segmentFilename = app.fs.joinPath(dataDirectory, sessionId .. ".aprlog")
  local writer, writerError = Journal.newWriter(segmentFilename, {
    memoryBudgetBytes = self.memoryBudgetBytes
  })
  if writer == nil then
    recording:close()
    return nil, nil, writerError
  end

  local reconstructedTimestamp = 0
  for index, frame in ipairs(recording.frames) do
    local cel = recording.layers[1]:cel(frame)
    if cel ~= nil then
      local properties = cel.properties(PLUGIN_KEY)
      local timestampMs = tonumber(timestamps[index])
        or tonumber(properties.timestampMs)
        or reconstructedTimestamp
      writer:appendImage(Image(cel.image), {
        timestampMs = timestampMs,
        sourceFrameNumber = tonumber(properties.sourceFrameNumber) or 1,
        eventName = properties.eventName or (index == 1 and "initial" or "history"),
        fromUndo = properties.fromUndo == true
      })
      reconstructedTimestamp = timestampMs
        + math.floor(frame.duration * 1000 + 0.5)
    end
  end
  local stats = writer:close()
  local elapsedMs = tonumber(metadata.elapsedMs) or reconstructedTimestamp
  recording:close()

  local base = fileBase(recordingFilename)
  local manifestFilename = manifestFilenameForBase(base)
  local manifest = {
    schemaVersion = 2,
    captureMode = "visible-work-process",
    sourceFilename = normalizedPath(sourceFilename),
    sourceTitle = sourceTitle,
    outputBase = base,
    manifestFilename = manifestFilename,
    elapsedMs = elapsedMs,
    recordCount = stats.recordCount,
    playbackSpeed = normalizePlaybackSpeed(metadata.playbackSpeed),
    recordInterval = 1,
    memoryBudgetBytes = self.memoryBudgetBytes,
    migratedFromSchema = 1,
    segments = { {
      filename = segmentFilename,
      recordCount = stats.recordCount,
      firstTimestampMs = stats.firstTimestampMs,
      lastTimestampMs = stats.lastTimestampMs,
      bytes = stats.bytesWritten,
      checkpointCount = stats.checkpointCount,
      changedTileCount = stats.changedTileCount,
      rawPixelBytes = stats.rawPixelBytes,
      encodedPixelBytes = stats.encodedPixelBytes,
      captureInterval = 1,
      outputStride = 1
    } },
    outputFiles = { recordingFilename }
  }
  local wrote, writeError = Journal.writeJsonAtomic(manifestFilename, manifest)
  if not wrote then
    return nil, nil, writeError
  end
  return manifest, manifestFilename
end

function Recorder:start(sprite, options)
  if self.session ~= nil then
    return false, "当前已经有正在进行的过程记录。"
  end
  if sprite == nil then
    return false, "请先打开一个 Sprite。"
  end
  if isProcessOutput(sprite) then
    return false, "过程记录文件不会被再次记录。"
  end

  options = options or {}
  local outputDirectory = options.outputDirectory or defaultOutputDirectory()
  local playbackSpeed = normalizePlaybackSpeed(options.playbackSpeed)
  local recordInterval = normalizeRecordInterval(options.recordInterval)
  local captureProfile = normalizeCaptureProfile(options.captureProfile)
  local memoryBudgetBytes = normalizeMemoryBudget(
    options.memoryBudgetBytes or self.memoryBudgetBytes)
  if not app.fs.isDirectory(outputDirectory)
      and not app.fs.makeAllDirectories(outputDirectory) then
    return false, "无法创建记录目录：" .. outputDirectory
  end

  local displayedFilename = sprite.filename or ""
  local sourceFilename = ""
  if sprite.hasAssociatedFile == true then
    sourceFilename = normalizedPath(displayedFilename)
  end
  local sourceTitle = displayedFilename ~= ""
    and app.fs.fileTitle(displayedFilename)
    or "Untitled_" .. os.date("%Y%m%d-%H%M%S")

  local manifest, manifestFilename = findManifestForSource(
    outputDirectory,
    sourceFilename)
  if manifest == nil and sourceFilename ~= "" then
    local legacyFilename = findLegacyRecordingForSource(
      outputDirectory,
      sourceTitle,
      sourceFilename)
    if legacyFilename ~= nil then
      local migrated, migratedFilename, migrationError = self:_migrateLegacyRecording(
        outputDirectory,
        sourceTitle,
        sourceFilename,
        legacyFilename)
      if migrated == nil then
        return false, "无法迁移已有过程记录："
          .. tostring(migrationError)
      end
      manifest = migrated
      manifestFilename = migratedFilename
    end
  end

  local frameNumber = activeFrameNumberFor(sprite, 1)
  pcall(function()
    app.sprite = sprite
  end)
  local currentImage = renderFrame(sprite, frameNumber)
  local historyCount = manifest ~= nil and tonumber(manifest.recordCount or 0) or 0
  local resumeOffsetMs = manifest ~= nil and tonumber(manifest.elapsedMs or 0) or 0

  self.memoryBudgetBytes = memoryBudgetBytes
  self.session = {
    sessionId = makeSessionId(sprite),
    sourceSprite = sprite,
    sourceFilename = sourceFilename,
    sourceTitle = sourceTitle,
    sourceFrameNumber = frameNumber,
    outputDirectory = outputDirectory,
    playbackSpeed = playbackSpeed,
    recordInterval = recordInterval,
    captureProfile = captureProfile,
    captureDelaySeconds = captureDelaySeconds(sprite, captureProfile),
    memoryBudgetBytes = memoryBudgetBytes,
    baseManifest = manifest,
    baseManifestFilename = manifestFilename,
    recordingSourceFilename = sourceFilename,
    resumeOffsetMs = resumeOffsetMs,
    startedAt = os.clock(),
    historyCount = historyCount,
    currentImage = currentImage,
    initialImage = Image(currentImage),
    initialFrameNumber = frameNumber,
    writer = nil,
    segmentFilename = nil,
    hasSessionChanges = false,
    sessionChangeCount = 0,
    changesSinceCapture = 0,
    pendingCapture = nil,
    settingsChanged = false,
    thinExistingStride = manifest ~= nil
        and recordInterval > 1
        and recordInterval ~= normalizeRecordInterval(manifest.recordInterval)
      and recordInterval
      or 1,
    currentSegmentOutputStride = 1,
    listenerCodes = {},
    flushTimer = nil,
    captureTimer = nil,
    deferredCapture = nil,
    coalescedEvents = 0,
    duplicateEvents = 0,
    captureError = nil,
    becameProcessOutput = false,
    lastCaptureStats = nil
  }

  local ok, captureError = pcall(function()
    self:_attachListeners()
  end)
  if not ok then
    self:_detachListeners()
    self.session = nil
    return false, "无法初始化过程记录：" .. tostring(captureError)
  end

  return true, {
    resumed = historyCount > 0,
    existingFrameCount = historyCount,
    outputDirectory = outputDirectory,
    sourceTitle = sourceTitle,
    memoryBudgetBytes = memoryBudgetBytes,
    recordInterval = recordInterval,
    captureProfile = captureProfile,
    captureDelayMs = math.floor(
      captureDelaySeconds(sprite, captureProfile) * 1000 + 0.5),
    captureMode = "visible-work-process"
  }
end

function Recorder:_buildManifest(session, elapsedMs, writerStats)
  local continuesExisting = session.baseManifest ~= nil
    and session.sourceFilename == session.recordingSourceFilename
  local base
  local manifestFilename
  local segments
  local previousOutputs = {}

  if continuesExisting then
    base = session.baseManifest.outputBase
    manifestFilename = session.baseManifestFilename
    segments = copySegments(session.baseManifest.segments)
    previousOutputs = session.baseManifest.outputFiles or {}
  else
    base = makeAvailableBase(session.outputDirectory, session.sourceTitle)
    manifestFilename = manifestFilenameForBase(base)
    segments = session.baseManifest ~= nil
      and copySegments(session.baseManifest.segments)
      or {}
  end

  local thinExistingStride = normalizeRecordInterval(session.thinExistingStride)
  if thinExistingStride > 1 then
    for _, segment in ipairs(segments) do
      segment.outputStride = normalizeOutputStride(segment.outputStride)
        * thinExistingStride
    end
  end

  if writerStats ~= nil then
    segments[#segments + 1] = {
      filename = session.segmentFilename,
      recordCount = writerStats.recordCount,
      firstTimestampMs = writerStats.firstTimestampMs,
      lastTimestampMs = writerStats.lastTimestampMs,
      bytes = writerStats.bytesWritten,
      checkpointCount = writerStats.checkpointCount,
      changedTileCount = writerStats.changedTileCount,
      rawPixelBytes = writerStats.rawPixelBytes,
      encodedPixelBytes = writerStats.encodedPixelBytes,
      captureInterval = session.recordInterval,
      outputStride = normalizeOutputStride(session.currentSegmentOutputStride)
    }
  end

  local recordCount = 0
  local journalBytes = 0
  for _, segment in ipairs(segments) do
    recordCount = recordCount + tonumber(segment.recordCount or 0)
    journalBytes = journalBytes + tonumber(segment.bytes or 0)
  end

  return {
    schemaVersion = 2,
    captureMode = "visible-work-process",
    recordingProfile = session.captureProfile,
    sourceFilename = session.sourceFilename,
    sourceTitle = session.sourceTitle,
    outputBase = base,
    manifestFilename = manifestFilename,
    elapsedMs = elapsedMs,
    recordCount = recordCount,
    playbackSpeed = session.playbackSpeed,
    recordInterval = session.recordInterval,
    memoryBudgetBytes = session.memoryBudgetBytes,
    coalescedEvents = (session.baseManifest
      and tonumber(session.baseManifest.coalescedEvents or 0)
      or 0) + session.coalescedEvents,
    duplicateEventsSkipped = (session.baseManifest
      and tonumber(session.baseManifest.duplicateEventsSkipped or 0)
      or 0) + session.duplicateEvents,
    journalBytes = journalBytes,
    segments = segments,
    outputFiles = previousOutputs
  }, continuesExisting
end

function Recorder:_runAsepriteExport(manifest)
  if self.helperPath == nil or not app.fs.isFile(self.helperPath) then
    return false, "当前平台缺少原生流式处理助手。"
  end
  local segmentList = manifest.manifestFilename .. ".segments.tmp"
  local reportFilename = manifest.manifestFilename .. ".export.tmp"
  local wroteList, listError = Journal.writeSegmentList(segmentList, manifest)
  if not wroteList then
    return false, listError
  end

  local command = {
    self.helperPath,
    "aseprite",
    "--segments", segmentList,
    "--output-base", manifest.outputBase,
    "--report", reportFilename,
    "--max-frames", tostring(DEFAULT_MAX_PART_FRAMES),
    "--max-bytes", tostring(DEFAULT_MAX_PART_BYTES),
    "--speed", tostring(manifest.playbackSpeed)
  }
  local succeeded = executeCommand(command)
  os.remove(segmentList)
  if not succeeded then
    os.remove(reportFilename)
    return false, "原生流式 Aseprite 导出失败。"
  end

  local report = parseReport(reportFilename)
  os.remove(reportFilename)
  if report == nil or #report.files == 0 then
    return false, "原生导出器没有生成任何输出文件。"
  end
  return true, report
end

function Recorder:_openSmallOutput(report)
  local frameCount = tonumber(report.frame_count or 0)
  local width = tonumber(report.width or 0)
  local height = tonumber(report.height or 0)
  if frameCount > OPEN_OUTPUT_FRAME_LIMIT then
    return nil
  end
  if frameCount * width * height * 4 > OPEN_OUTPUT_DECODED_LIMIT then
    return nil
  end
  local filename = report.files[1]
  if filename == nil or not app.fs.isFile(filename) then
    return nil
  end
  if app.fs.fileSize(filename) > OPEN_OUTPUT_BYTE_LIMIT then
    return nil
  end
  local ok, sprite = pcall(function()
    return Sprite { fromFile = filename }
  end)
  return ok and sprite or nil
end

local function automaticVideoScale(manifest)
  local width = math.max(1, math.floor(tonumber(manifest.outputWidth) or 0))
  local height = math.max(1, math.floor(tonumber(manifest.outputHeight) or 0))
  if width <= 1 or height <= 1 then
    return 4
  end

  local shorter = math.min(width, height)
  local longer = math.max(width, height)
  local desiredScale = math.ceil(1024 / shorter)
  local safeScale = math.max(1, math.floor(2048 / longer))
  return math.max(1, math.min(10, desiredScale, safeScale))
end

function Recorder:stop(options)
  options = options or {}
  if self.session == nil then
    return false, "当前没有正在进行的过程记录。"
  end

  local session = self.session
  self:_updateSourceIdentity()
  self:_flushDeferredCapture(session)
  local elapsedMs = session.resumeOffsetMs + self:_elapsedMilliseconds()
  self:_detachListeners()

  if session.becameProcessOutput then
    self:_discardSessionWriter(session)
    self.session = nil
    return true, {
      cancelled = true,
      reason = "process_output",
      frameCount = session.historyCount
    }
  end

  if not session.hasSessionChanges
      and not (session.settingsChanged and session.baseManifest ~= nil) then
    self:_discardSessionWriter(session)
    self.session = nil
    return true, {
      cancelled = true,
      reason = "no_changes",
      frameCount = session.historyCount
    }
  end

  if session.sourceFilename == "" then
    self:_discardSessionWriter(session)
    self.session = nil
    return true, {
      cancelled = true,
      reason = "source_not_saved",
      frameCount = session.historyCount
    }
  end

  if session.hasSessionChanges then
    self:_flushPendingCapture(session)
  end
  local writerStats = session.writer ~= nil and session.writer:close() or nil
  if writerStats ~= nil and writerStats.recordCount <= 1
      and not session.settingsChanged then
    self:_discardSessionWriter(session)
    self.session = nil
    return true, {
      cancelled = true,
      reason = "no_sampled_changes",
      frameCount = session.historyCount
    }
  end
  local manifest, continuesExisting = self:_buildManifest(
    session,
    session.hasSessionChanges and elapsedMs or session.resumeOffsetMs,
    writerStats)
  local wroteManifest, manifestError = Journal.writeJsonAtomic(
    manifest.manifestFilename,
    manifest)
  if not wroteManifest then
    return false, "过程日志已保存，但清单写入失败："
      .. tostring(manifestError)
  end

  local exported, reportOrError = self:_runAsepriteExport(manifest)
  if not exported then
    self.session = nil
    return false, "过程日志已安全保存在 " .. manifest.manifestFilename
      .. "，但导出失败：" .. tostring(reportOrError)
  end

  local report = reportOrError
  local newOutputSet = {}
  for _, filename in ipairs(report.files) do
    newOutputSet[normalizedPath(filename)] = true
  end
  for _, filename in ipairs(manifest.outputFiles or {}) do
    if not newOutputSet[normalizedPath(filename)] then
      os.remove(filename)
    end
  end
  manifest.outputFiles = report.files
  manifest.outputFrameCount = report.frame_count
  manifest.recordCount = report.frame_count
  manifest.journalRecordCount = 0
  for _, segment in ipairs(manifest.segments) do
    manifest.journalRecordCount = manifest.journalRecordCount
      + tonumber(segment.recordCount or 0)
  end
  manifest.outputPartCount = report.part_count
  manifest.outputWidth = report.width
  manifest.outputHeight = report.height
  Journal.writeJsonAtomic(manifest.manifestFilename, manifest)

  local outputSprite = nil
  if options.openOutput ~= false then
    outputSprite = self:_openSmallOutput(report)
  end
  self.session = nil
  return true, {
    branched = session.baseManifest ~= nil and not continuesExisting,
    cancelled = false,
    continued = continuesExisting,
    elapsedMs = elapsedMs,
    frameCount = report.frame_count,
    sessionFrameCount = writerStats ~= nil and writerStats.recordCount or 0,
    playbackSpeed = session.playbackSpeed,
    outputFilename = report.files[1],
    outputFiles = report.files,
    outputPartCount = #report.files,
    outputSprite = outputSprite,
    manifestFilename = manifest.manifestFilename,
    journalBytes = manifest.journalBytes,
    duplicateEventsSkipped = session.duplicateEvents,
    writerStats = writerStats,
    recordInterval = session.recordInterval,
    captureProfile = session.captureProfile,
    coalescedEvents = session.coalescedEvents
  }
end

function Recorder:_sourceFilenameFor(sprite)
  if sprite == nil then
    return ""
  end
  if isProcessOutput(sprite) then
    local metadata = sprite.properties(PLUGIN_KEY)
    if metadata.sourceFilename ~= nil then
      return normalizedPath(metadata.sourceFilename)
    end
    return normalizedPath(parseKeyValueText(sprite.data).source)
  end
  if sprite.hasAssociatedFile == true then
    return normalizedPath(sprite.filename)
  end
  return ""
end

function Recorder:exportVideo(sprite, options)
  options = options or {}
  if self.session ~= nil then
    return false, "请先停止当前记录，再导出视频。"
  end
  if self.helperPath == nil or not app.fs.isFile(self.helperPath) then
    return false, "当前平台缺少原生流式处理助手。"
  end
  local sourceFilename = self:_sourceFilenameFor(sprite)
  if sourceFilename == "" then
    return false, "请先打开已保存的原图，或对应的过程文件。"
  end
  local outputDirectory = options.outputDirectory or defaultOutputDirectory()
  local manifest = findManifestForSource(outputDirectory, sourceFilename)
  if manifest == nil then
    return false, "没有找到与当前原图对应的磁盘过程日志。"
  end

  local ffmpegPath = options.ffmpegPath
  if ffmpegPath == nil or not app.fs.isFile(ffmpegPath) then
    return false, "没有找到 FFmpeg；请先在记录器设置中选择有效的可执行文件。"
  end
  local scale = options.scale == "auto"
    and automaticVideoScale(manifest)
    or math.max(1, math.min(10, math.floor(tonumber(options.scale) or 4)))
  local fps = math.max(1, math.floor(tonumber(options.fps) or 30))
  local outputFilename = options.outputFilename
    or (manifest.outputBase .. "_process_" .. scale .. "x.mp4")
  local segmentList = manifest.manifestFilename .. ".video-segments.tmp"
  local reportFilename = manifest.manifestFilename .. ".video-export.tmp"
  local wroteList, listError = Journal.writeSegmentList(segmentList, manifest)
  if not wroteList then
    return false, listError
  end

  local command = {
    self.helperPath,
    "video",
    "--segments", segmentList,
    "--ffmpeg", ffmpegPath,
    "--output", outputFilename,
    "--report", reportFilename,
    "--scale", tostring(scale),
    "--fps", tostring(fps)
  }
  local startedAt = os.clock()
  local succeeded = executeCommand(command)
  local exportMilliseconds = roundMilliseconds(os.clock() - startedAt)
  os.remove(segmentList)
  if not succeeded then
    os.remove(reportFilename)
    return false, "FFmpeg 视频导出失败。"
  end
  local report = parseReport(reportFilename)
  os.remove(reportFilename)
  if report == nil or not app.fs.isFile(outputFilename) then
    return false, "FFmpeg 已结束，但没有生成预期的视频文件。"
  end
  report.outputFilename = outputFilename
  report.exportMilliseconds = exportMilliseconds
  return true, report
end

return Recorder
