local scriptFilename = debug.getinfo(1, "S").source:sub(2)
local testsDirectory = app.fs.filePath(scriptFilename)
local repositoryDirectory = app.fs.filePath(testsDirectory)
local pluginDirectory = app.fs.joinPath(repositoryDirectory, "plugin")
local outputDirectory = app.fs.joinPath(repositoryDirectory, "benchmark-output")
local resultFilename = outputDirectory .. [[\results.txt]]
package.path = pluginDirectory .. [[\?.lua;]] .. package.path

local Recorder = require("recorder")

if not app.fs.isDirectory(outputDirectory) then
  assert(app.fs.makeAllDirectories(outputDirectory))
end

local results = {}

local function elapsedMilliseconds(startedAt)
  return math.floor((os.clock() - startedAt) * 1000 + 0.5)
end

local function runCase(profile, changes)
  local name = profile .. "-512-" .. changes
  local sourceFilename = outputDirectory .. "\\" .. name .. ".aseprite"
  local sprite = Sprite(512, 512, ColorMode.RGB)
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

  local loopStartedAt = os.clock()
  for index = 1, changes do
    app.sprite = sprite
    app.transaction("benchmark-" .. index, function()
      local image = sprite.cels[1].image
      local x = (index - 1) % sprite.width
      local y = math.floor((index - 1) / sprite.width) % sprite.height
      image:drawPixel(x, y, app.pixelColor.rgba(index % 256, 80, 220, 255))
    end)
  end
  local loopMilliseconds = elapsedMilliseconds(loopStartedAt)
  local expectedFinal = Image(sprite.cels[1].image)

  local stopStartedAt = os.clock()
  local okStop, stopResult = recorder:stop { openOutput = false }
  local stopMilliseconds = elapsedMilliseconds(stopStartedAt)
  assert(okStop, stopResult)
  assert(not stopResult.cancelled, stopResult.reason)

  local finalOutput = Sprite { fromFile = stopResult.outputFilename }
  local finalCel = finalOutput.layers[1]:cel(finalOutput.frames[#finalOutput.frames])
  local finalMatches = finalCel ~= nil and finalCel.image:isEqual(expectedFinal)
  results[#results + 1] = table.concat({
    "profile=" .. profile,
    "changes=" .. changes,
    "delay_ms=" .. startResult.captureDelayMs,
    "loop_ms=" .. loopMilliseconds,
    "stop_ms=" .. stopMilliseconds,
    "total_ms=" .. (loopMilliseconds + stopMilliseconds),
    "session_frames=" .. stopResult.sessionFrameCount,
    "coalesced_events=" .. stopResult.coalescedEvents,
    "journal_bytes=" .. stopResult.journalBytes,
    "final_matches=" .. tostring(finalMatches)
  }, "\n")
  finalOutput:close()
  sprite:close()
end

runCase("complete", 200)
runCase("automatic", 200)
runCase("performance", 200)

local output = assert(io.open(resultFilename, "wb"))
output:write(table.concat(results, "\n\n"), "\n")
output:close()
