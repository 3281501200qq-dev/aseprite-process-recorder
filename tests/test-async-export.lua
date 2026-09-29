local scriptFilename = debug.getinfo(1, "S").source:sub(2)
local repositoryDirectory = app.fs.filePath(app.fs.filePath(scriptFilename))
local pluginDirectory = app.fs.joinPath(repositoryDirectory, "plugin")
package.path = pluginDirectory .. [[\?.lua;]] .. package.path
local Recorder = dofile(app.fs.joinPath(pluginDirectory, "recorder.lua"))
local Journal = require("journal")
local outputDirectory = app.fs.joinPath(repositoryDirectory,
  "test-output/async-" .. os.date("%Y%m%d-%H%M%S") .. "-" .. math.random(10000, 99999))
assert(app.fs.makeAllDirectories(outputDirectory))
local helperPath = app.fs.joinPath(pluginDirectory, "native/bin/process-recorder-helper-windows-x64.exe")
local recorder = Recorder.new { helperPath = helperPath }
local sprite = Sprite(64, 64, ColorMode.RGB)
sprite:saveAs(app.fs.joinPath(outputDirectory, "中文 空格 $price & test.aseprite"))
local stopTimes = {}

local function recordChanges(count)
  assert(recorder:start(sprite, { outputDirectory = outputDirectory, captureProfile = "complete" }))
  for index = 1, count do
    app.transaction(function()
      sprite.cels[1].image:drawPixel(index, #stopTimes + 1,
        app.pixelColor.rgba(255, index, 80, 255))
    end)
  end
  local started = os.clock()
  local ok, result = recorder:stop { openOutput = false }
  stopTimes[#stopTimes + 1] = (os.clock() - started) * 1000
  assert(ok and result.pending)
  assert(not recorder:isRecording())
  return result
end

local function drain(target)
  local deadline = os.time() + 20
  while target:hasPendingExports() do
    local ok, result = target:pollExportJob()
    assert(ok ~= false, result)
    assert(os.time() < deadline, "background export timed out")
    if ok == nil then
      os.execute('powershell.exe -NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds 100"')
    end
  end
end

local first = recordChanges(12)
assert(recorder.activeExportJob == nil)
assert(recorder:pollExportJob() == nil)
local second = recordChanges(8)
local latest = assert(Journal.readJson(second.manifestFilename))
assert(#latest.segments == 2)
drain(recorder)
latest = assert(Journal.readJson(second.manifestFilename))
assert(#latest.segments == 2 and latest.exportPending == false)
assert(latest.recordCount == 21)
local expected = Image(sprite.cels[1].image)
local output = Sprite { fromFile = second.outputFilename }
assert(#output.frames == 21)
local finalImage = Image(ImageSpec { width = 64, height = 64, colorMode = ColorMode.RGB })
finalImage:drawSprite(output, #output.frames)
assert(finalImage:isEqual(expected))
for frameNumber = 1, 13 do
  local frameImage = Image(ImageSpec { width = 64, height = 64, colorMode = ColorMode.RGB })
  frameImage:drawSprite(output, frameNumber)
  for pixel = 1, 12 do
    local color = frameImage:getPixel(pixel, 1)
    assert(app.pixelColor.rgbaA(color) == (pixel < frameNumber and 255 or 0))
  end
end
output:close()

recordChanges(4)
local recovered = Recorder.new { helperPath = helperPath }
recovered:recoverExports(outputDirectory)
assert(recovered:hasPendingExports())
drain(recovered)
latest = assert(Journal.readJson(first.manifestFilename))
assert(#latest.segments == 3 and latest.journalRecordCount == 27
  and latest.recordCount == 25)
assert(latest.exportPending == false)
recorder = recovered
sprite:close()

local closing = Sprite(512, 512, ColorMode.RGB)
closing:saveAs(app.fs.joinPath(outputDirectory, "close-pending.aseprite"))
assert(recorder:start(closing, { outputDirectory = outputDirectory, captureProfile = "performance" }))
app.transaction(function()
  closing.cels[1].image:drawPixel(10, 10, app.pixelColor.rgba(99, 2, 3, 255))
end)
assert(recorder.session.deferredCapture ~= nil)
app.command.CloseFile()
assert(recorder.session.deferredCapture == nil)
local closedOk, closedResult = recorder:stop { openOutput = false }
assert(closedOk and closedResult.pending)
drain(recorder)
local closedOutput = Sprite { fromFile = closedResult.outputFilename }
local closedImage = Image(ImageSpec { width = 512, height = 512, colorMode = ColorMode.RGB })
closedImage:drawSprite(closedOutput, #closedOutput.frames)
assert(closedImage:getPixel(10, 10) == app.pixelColor.rgba(99, 2, 3, 255))
closedOutput:close()

local broken = Recorder.new { helperPath = helperPath }
local failedManifest = Journal.readJson(first.manifestFilename)
assert(broken:_queueAsepriteExport(failedManifest, { openOutput = false }))
local failedJob = broken.exportQueue[1]
failedJob.helperPath = app.fs.joinPath(outputDirectory, "missing-helper.exe")
assert(Journal.writeJsonAtomic(failedJob.jobFilename, failedJob))
local deadline = os.time() + 20
local failure
repeat
  local ok, result = broken:pollExportJob()
  if ok == false then failure = result end
  assert(os.time() < deadline)
  os.execute('powershell.exe -NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds 100"')
until failure
assert(app.fs.isFile(failedJob.jobFilename) and app.fs.isFile(failedJob.errorFilename))
assert(app.fs.isFile(failedManifest.segments[1].filename))

local resultFile = assert(io.open(app.fs.joinPath(outputDirectory, "PASS.txt"), "wb"))
resultFile:write("async, resume, recovery, close, failure, intermediate frames, Unicode paths: PASS\nstop_ms=", table.concat(stopTimes, ","), "\n")
resultFile:close()
print("ASYNC PASS: " .. outputDirectory .. " stop_ms=" .. table.concat(stopTimes, ","))
