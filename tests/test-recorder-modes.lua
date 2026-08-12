local scriptFilename = debug.getinfo(1, "S").source:sub(2)
local testsDirectory = app.fs.filePath(scriptFilename)
local repositoryDirectory = app.fs.filePath(testsDirectory)
local pluginDirectory = app.fs.joinPath(repositoryDirectory, "plugin")
local outputDirectory = app.fs.joinPath(repositoryDirectory, "test-output")
local resultFilename = outputDirectory .. [[\results.txt]]
package.path = pluginDirectory .. [[\?.lua;]] .. package.path

local Recorder = require("recorder")

if not app.fs.isDirectory(outputDirectory) then
  assert(app.fs.makeAllDirectories(outputDirectory))
end

local results = {}

local function appendResult(name, values)
  results[#results + 1] = name
  for key, value in pairs(values) do
    results[#results + 1] = key .. "=" .. tostring(value)
  end
end

local function changePixel(sprite, index)
  app.sprite = sprite
  app.transaction("mode-test-" .. index, function()
    local image = sprite.cels[1].image
    local x = (index - 1) % sprite.width
    local y = math.floor((index - 1) / sprite.width) % sprite.height
    image:drawPixel(x, y, app.pixelColor.rgba(index % 256, 40, 200, 255))
  end)
end

local function runCase(name, width, height, profile, changes, flushAfterEach)
  local sourceFilename = outputDirectory .. "\\" .. name .. ".aseprite"
  local sprite = Sprite(width, height, ColorMode.RGB)
  sprite:saveAs(sourceFilename)
  local recorder = Recorder.new {
    helperPath = pluginDirectory
      .. [[\native\bin\process-recorder-helper-windows-x64.exe]]
  }
  local ok, startResult = recorder:start(sprite, {
    outputDirectory = outputDirectory,
    captureProfile = profile,
    recordInterval = 1,
    playbackSpeed = 1,
    memoryBudgetBytes = 128 * 1024 * 1024
  })
  assert(ok, startResult)

  for index = 1, changes do
    changePixel(sprite, index)
    if flushAfterEach then
      recorder:_flushDeferredCapture(recorder.session)
    end
  end

  local expectedFinal = Image(sprite.cels[1].image)
  local deferredBeforeStop = recorder.session.deferredCapture ~= nil
  local coalescedBeforeStop = recorder.session.coalescedEvents
  local okStop, stopResult = recorder:stop { openOutput = false }
  assert(okStop, stopResult)
  assert(not stopResult.cancelled, stopResult.reason)

  local finalOutput = Sprite { fromFile = stopResult.outputFilename }
  local finalCel = finalOutput.layers[1]:cel(finalOutput.frames[#finalOutput.frames])
  local finalMatches = finalCel ~= nil and finalCel.image:isEqual(expectedFinal)
  appendResult(name, {
    profile = startResult.captureProfile,
    delay_ms = startResult.captureDelayMs,
    changes = changes,
    frames = stopResult.frameCount,
    session_frames = stopResult.sessionFrameCount,
    deferred_before_stop = deferredBeforeStop,
    coalesced_before_stop = coalescedBeforeStop,
    coalesced_result = stopResult.coalescedEvents,
    final_matches = finalMatches
  })
  finalOutput:close()
  sprite:close()
end

runCase("complete-64", 64, 64, "complete", 12, false)
runCase("automatic-64", 64, 64, "automatic", 12, false)
runCase("automatic-512", 512, 512, "automatic", 20, false)
runCase("performance-64", 64, 64, "performance", 20, false)
runCase("automatic-512-separated", 512, 512, "automatic", 8, true)

local output = assert(io.open(resultFilename, "wb"))
output:write(table.concat(results, "\n"), "\n")
output:close()
