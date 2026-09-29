local scriptFilename = debug.getinfo(1, "S").source:sub(2)
local repositoryDirectory = app.fs.filePath(app.fs.filePath(scriptFilename))
local pluginDirectory = app.fs.joinPath(repositoryDirectory, "plugin")
package.path = pluginDirectory .. [[\?.lua;]] .. package.path
local realApp = app
local realTimer = Timer
local realExecute = os.execute
local Recorder = require("recorder")
local Journal = require("journal")
local newRecorder = Recorder.new
local recorder
Recorder.new = function(options)
  recorder = newRecorder(options)
  return recorder
end
local outputDirectory = app.fs.joinPath(repositoryDirectory,
  "test-output/lifecycle-" .. os.date("%Y%m%d-%H%M%S") .. "-" .. math.random(10000, 99999))
assert(app.fs.makeAllDirectories(outputDirectory))
local timers = {}
Timer = function(options)
  timers[#timers + 1] = options
  return realTimer(options)
end
app = setmetatable({ isUIAvailable = true, alert = function(options)
  error("Unexpected alert: " .. (type(options.text) == "table"
    and table.concat(options.text, " | ") or tostring(options.text)))
end }, { __index = realApp, __newindex = function(_, key, value) realApp[key] = value end })
local commands = {}
local plugin = {
  path = pluginDirectory,
  preferences = { outputDirectory = outputDirectory, captureMode = "performance" },
  newMenuGroup = function() end,
  newCommand = function(_, command) commands[command.id] = command end
}
dofile(app.fs.joinPath(pluginDirectory, "main.lua"))
init(plugin)
assert(commands.ProcessRecorderAutoStart ~= nil)
assert(commands.ProcessRecorderAutoStart.onchecked())
commands.ProcessRecorderAutoStart.onclick()
assert(plugin.preferences.autoStart == false)
assert(not commands.ProcessRecorderAutoStart.onchecked())
local disabled = Sprite(32, 32, ColorMode.RGB)
disabled:saveAs(app.fs.joinPath(outputDirectory, "disabled.aseprite"))
app.sprite = disabled
assert(recorder:sourceSprite() == nil)
commands.ProcessRecorderAutoStart.onclick()
assert(plugin.preferences.autoStart == true)
assert(recorder:sourceSprite() == disabled)
local disabledStopOk, disabledStopResult = recorder:stop {
  openOutput = false,
  asyncExport = false
}
assert(disabledStopOk and disabledStopResult.cancelled)
disabled:close()
os.execute = function() error("External command on document event path") end
local source = Sprite(512, 512, ColorMode.RGB)
source:saveAs(app.fs.joinPath(outputDirectory, "first.aseprite"))
assert(recorder:sourceSprite() == source)
app.transaction(function()
  source.cels[1].image:drawPixel(5, 5, app.pixelColor.rgba(20, 30, 40, 255))
end)
local second = Sprite(64, 64, ColorMode.RGB)
second:saveAs(app.fs.joinPath(outputDirectory, "second.aseprite"))
assert(recorder:sourceSprite() == second)
assert(#recorder.exportQueue == 1)
app.command.CloseFile()
second:close()
app.sprite = source
if not recorder:isRecording() then
  commands.ProcessRecorderStart.onclick()
end
assert(recorder:sourceSprite() == source)
app.transaction(function()
  source.cels[1].image:drawPixel(6, 6, app.pixelColor.rgba(30, 40, 50, 255))
end)
assert(recorder.session.deferredCapture ~= nil)
app.command.CloseFile()
source:close()
assert(not recorder:isRecording())
assert(#recorder.exportQueue == 2)
os.execute = realExecute
local deadline = os.time() + 20
while recorder:hasPendingExports() do
  timers[1].ontick()
  assert(os.time() < deadline)
  realExecute('powershell.exe -NoProfile -NonInteractive -Command "Start-Sleep -Milliseconds 100"')
end
local manifest = assert(Journal.readJson(app.fs.joinPath(outputDirectory,
  "first_timelapse.process-recorder.json")))
assert(#manifest.segments == 2 and manifest.recordCount == 3)
assert(not manifest.exportPending)
assert(app.sprite == nil)
exit(plugin)
app = realApp
Timer = realTimer
Recorder.new = newRecorder
print("LIFECYCLE PASS: open, switch, close, resume, no external command in sitechange")
