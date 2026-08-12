local Journal = {}

local MAGIC = "APRLOG02"
local RECORD_MAGIC = "RECD"
local DEFAULT_TILE_SIZE = 64
local DEFAULT_MEMORY_BUDGET = 256 * 1024 * 1024
local DEFAULT_CHECKPOINT_RECORDS = 1000
local DEFAULT_CHECKPOINT_BYTES = 64 * 1024 * 1024

local FLAG_CHECKPOINT = 1
local FLAG_FROM_UNDO = 2
local CODEC_RAW = 0
local CODEC_PIXEL_RLE = 1

local Writer = {}
Writer.__index = Writer

local function packUnsigned32(value)
  return string.pack("<I4", value)
end

local function readAll(filename)
  local file, openError = io.open(filename, "rb")
  if file == nil then
    return nil, openError
  end
  local contents = file:read("*a")
  file:close()
  return contents
end

local function writeAll(filename, contents)
  local file, openError = io.open(filename, "wb")
  if file == nil then
    return false, openError
  end
  local ok, writeError = file:write(contents)
  if not ok then
    file:close()
    return false, writeError
  end
  file:flush()
  file:close()
  return true
end

local function pixelRunLength(bytes, position, pixelCount)
  local pixel = bytes:sub(position, position + 3)
  local runLength = 1
  while runLength < 128 and runLength < pixelCount do
    local nextPosition = position + runLength * 4
    if bytes:sub(nextPosition, nextPosition + 3) ~= pixel then
      break
    end
    runLength = runLength + 1
  end
  return runLength, pixel
end

local function encodePixelRle(bytes)
  local output = {}
  local outputBytes = 0
  local position = 1
  local remainingPixels = #bytes // 4

  while remainingPixels > 0 do
    local runLength, pixel = pixelRunLength(bytes, position, remainingPixels)
    if runLength >= 3 then
      local token = string.char(0x80 + runLength - 1) .. pixel
      output[#output + 1] = token
      outputBytes = outputBytes + #token
      position = position + runLength * 4
      remainingPixels = remainingPixels - runLength
    else
      local literalStart = position
      local literalCount = 0
      while literalCount < 128 and literalCount < remainingPixels do
        local candidatePosition = position + literalCount * 4
        local candidateRun = pixelRunLength(
          bytes,
          candidatePosition,
          remainingPixels - literalCount)
        if candidateRun >= 3 and literalCount > 0 then
          break
        end
        if candidateRun >= 3 then
          break
        end
        literalCount = literalCount + 1
      end

      if literalCount == 0 then
        literalCount = math.min(runLength, 128)
      end

      local literalBytes = bytes:sub(
        literalStart,
        literalStart + literalCount * 4 - 1)
      local token = string.char(literalCount - 1) .. literalBytes
      output[#output + 1] = token
      outputBytes = outputBytes + #token
      position = position + literalCount * 4
      remainingPixels = remainingPixels - literalCount
    end
  end

  return table.concat(output), outputBytes
end

local function extractTile(bytes, rowStride, bytesPerPixel, x, y, width, height)
  local rows = {}
  local visibleBytes = width * bytesPerPixel
  for row = 0, height - 1 do
    local first = (y + row) * rowStride + x * bytesPerPixel + 1
    rows[#rows + 1] = bytes:sub(first, first + visibleBytes - 1)
  end
  return table.concat(rows)
end

local function tileChanged(
  previousBytes,
  currentBytes,
  rowStride,
  bytesPerPixel,
  x,
  y,
  width,
  height)
  local visibleBytes = width * bytesPerPixel
  for row = 0, height - 1 do
    local first = (y + row) * rowStride + x * bytesPerPixel + 1
    local last = first + visibleBytes - 1
    if previousBytes:sub(first, last) ~= currentBytes:sub(first, last) then
      return true
    end
  end
  return false
end

local function encodeTile(tileBytes)
  local rleBytes, rleSize = encodePixelRle(tileBytes)
  if rleSize < #tileBytes then
    return CODEC_PIXEL_RLE, rleBytes
  end
  return CODEC_RAW, tileBytes
end

local function buildTileRecord(x, y, width, height, codec, payload)
  return string.pack(
    "<I4I4I4I4I4I4",
    x,
    y,
    width,
    height,
    codec,
    #payload) .. payload
end

local function normalizedMemoryBudget(value)
  local numericValue = tonumber(value)
  if numericValue == nil or numericValue < 64 * 1024 * 1024 then
    return DEFAULT_MEMORY_BUDGET
  end
  return math.floor(numericValue)
end

function Journal.newWriter(filename, options)
  options = options or {}
  local file, openError = io.open(filename, "wb")
  if file == nil then
    return nil, openError
  end

  local memoryBudget = normalizedMemoryBudget(options.memoryBudgetBytes)
  local writeChunkBytes = math.floor(memoryBudget / 8)
  writeChunkBytes = math.max(4 * 1024 * 1024, writeChunkBytes)
  writeChunkBytes = math.min(64 * 1024 * 1024, writeChunkBytes)

  local writer = setmetatable({
    filename = filename,
    file = file,
    tileSize = options.tileSize or DEFAULT_TILE_SIZE,
    memoryBudgetBytes = memoryBudget,
    writeChunkBytes = options.writeChunkBytes or writeChunkBytes,
    checkpointRecords = options.checkpointRecords or DEFAULT_CHECKPOINT_RECORDS,
    checkpointBytes = options.checkpointBytes or DEFAULT_CHECKPOINT_BYTES,
    pending = {},
    pendingBytes = 0,
    bytesWritten = 0,
    recordCount = 0,
    checkpointCount = 0,
    changedTileCount = 0,
    rawPixelBytes = 0,
    encodedPixelBytes = 0,
    bytesSinceCheckpoint = 0,
    previousBytes = nil,
    previousWidth = nil,
    previousHeight = nil,
    previousRowStride = nil,
    previousBytesPerPixel = nil,
    firstTimestampMs = nil,
    lastTimestampMs = nil,
    closed = false
  }, Writer)

  local header = MAGIC .. string.pack(
    "<I4I4I4I4I4I4",
    writer.tileSize,
    2,
    0,
    0,
    0,
    0)
  local ok, writeError = file:write(header)
  if not ok then
    file:close()
    return nil, writeError
  end
  writer.bytesWritten = #header
  return writer
end

function Writer:_flushPending(forceFileFlush)
  if self.pendingBytes > 0 then
    local contents = table.concat(self.pending)
    local ok, writeError = self.file:write(contents)
    if not ok then
      error(writeError or "Could not write the process journal.")
    end
    self.bytesWritten = self.bytesWritten + #contents
    self.pending = {}
    self.pendingBytes = 0
  end
  if forceFileFlush then
    self.file:flush()
  end
end

function Writer:flush()
  if not self.closed then
    self:_flushPending(true)
  end
end

function Writer:_queueRecord(record)
  if #record >= self.writeChunkBytes then
    self:_flushPending(false)
    local ok, writeError = self.file:write(record)
    if not ok then
      error(writeError or "Could not write the process journal.")
    end
    self.bytesWritten = self.bytesWritten + #record
    return
  end

  self.pending[#self.pending + 1] = record
  self.pendingBytes = self.pendingBytes + #record
  if self.pendingBytes >= self.writeChunkBytes then
    self:_flushPending(true)
  end
end

function Writer:appendImage(image, record)
  if self.closed then
    error("The process journal is already closed.")
  end
  if image.bytesPerPixel ~= 4 then
    error("The process journal requires flattened RGBA images.")
  end

  record = record or {}
  local currentBytes = image.bytes
  local width = image.width
  local height = image.height
  local rowStride = image.rowStride
  local bytesPerPixel = image.bytesPerPixel
  local dimensionsChanged = self.previousWidth ~= width
    or self.previousHeight ~= height
    or self.previousRowStride ~= rowStride
    or self.previousBytesPerPixel ~= bytesPerPixel
  local checkpoint = self.previousBytes == nil
    or dimensionsChanged
    or (self.recordCount > 0 and self.recordCount % self.checkpointRecords == 0)
    or self.bytesSinceCheckpoint >= self.checkpointBytes

  local tiles = {}
  local tileCount = 0
  local rawPixelBytes = 0
  local encodedPixelBytes = 0

  for y = 0, height - 1, self.tileSize do
    local tileHeight = math.min(self.tileSize, height - y)
    for x = 0, width - 1, self.tileSize do
      local tileWidth = math.min(self.tileSize, width - x)
      local changed = checkpoint or tileChanged(
        self.previousBytes,
        currentBytes,
        rowStride,
        bytesPerPixel,
        x,
        y,
        tileWidth,
        tileHeight)
      if changed then
        local tileBytes = extractTile(
          currentBytes,
          rowStride,
          bytesPerPixel,
          x,
          y,
          tileWidth,
          tileHeight)
        local codec, payload = encodeTile(tileBytes)
        tiles[#tiles + 1] = buildTileRecord(
          x,
          y,
          tileWidth,
          tileHeight,
          codec,
          payload)
        tileCount = tileCount + 1
        rawPixelBytes = rawPixelBytes + #tileBytes
        encodedPixelBytes = encodedPixelBytes + #payload
      end
    end
  end

  if tileCount == 0 then
    self.previousBytes = currentBytes
    return false, {
      checkpoint = false,
      tileCount = 0,
      encodedBytes = 0,
      rawBytes = 0
    }
  end

  local flags = checkpoint and FLAG_CHECKPOINT or 0
  if record.fromUndo == true then
    flags = flags | FLAG_FROM_UNDO
  end
  local eventName = tostring(record.eventName or "change")
  local timestampMs = math.max(0, math.floor(tonumber(record.timestampMs) or 0))
  local sourceFrameNumber = math.max(
    1,
    math.floor(tonumber(record.sourceFrameNumber) or 1))
  local body = string.pack(
    "<I8I4I4I4I4I4I4I4I4",
    timestampMs,
    sourceFrameNumber,
    width,
    height,
    0,
    0,
    flags,
    tileCount,
    #eventName)
    .. eventName
    .. table.concat(tiles)
  local recordBytes = RECORD_MAGIC .. packUnsigned32(#body) .. body

  self:_queueRecord(recordBytes)
  self.recordCount = self.recordCount + 1
  self.changedTileCount = self.changedTileCount + tileCount
  self.rawPixelBytes = self.rawPixelBytes + rawPixelBytes
  self.encodedPixelBytes = self.encodedPixelBytes + encodedPixelBytes
  self.bytesSinceCheckpoint = checkpoint
    and #recordBytes
    or self.bytesSinceCheckpoint + #recordBytes
  if checkpoint then
    self.checkpointCount = self.checkpointCount + 1
  end
  self.firstTimestampMs = self.firstTimestampMs or timestampMs
  self.lastTimestampMs = timestampMs
  self.previousBytes = currentBytes
  self.previousWidth = width
  self.previousHeight = height
  self.previousRowStride = rowStride
  self.previousBytesPerPixel = bytesPerPixel

  return true, {
    checkpoint = checkpoint,
    tileCount = tileCount,
    encodedBytes = encodedPixelBytes,
    rawBytes = rawPixelBytes,
    recordBytes = #recordBytes
  }
end

function Writer:stats()
  return {
    filename = self.filename,
    bytesWritten = self.bytesWritten + self.pendingBytes,
    pendingBytes = self.pendingBytes,
    memoryBudgetBytes = self.memoryBudgetBytes,
    writeChunkBytes = self.writeChunkBytes,
    recordCount = self.recordCount,
    checkpointCount = self.checkpointCount,
    changedTileCount = self.changedTileCount,
    rawPixelBytes = self.rawPixelBytes,
    encodedPixelBytes = self.encodedPixelBytes,
    firstTimestampMs = self.firstTimestampMs,
    lastTimestampMs = self.lastTimestampMs
  }
end

function Writer:close()
  if self.closed then
    return self:stats()
  end
  self:_flushPending(true)
  self.file:close()
  self.file = nil
  self.closed = true
  self.previousBytes = nil
  return self:stats()
end

function Writer:discard()
  if not self.closed then
    self:close()
  end
  os.remove(self.filename)
end

function Journal.readJson(filename)
  local contents, readError = readAll(filename)
  if contents == nil then
    return nil, readError
  end
  local ok, decoded = pcall(json.decode, contents)
  if not ok then
    return nil, decoded
  end
  return decoded
end

function Journal.writeJsonAtomic(filename, value)
  local temporaryFilename = filename .. ".tmp"
  local ok, encoded = pcall(json.encode, value)
  if not ok then
    return false, encoded
  end
  local wrote, writeError = writeAll(temporaryFilename, encoded)
  if not wrote then
    return false, writeError
  end
  os.remove(filename)
  local renamed, renameError = os.rename(temporaryFilename, filename)
  if not renamed then
    os.remove(temporaryFilename)
    return false, renameError
  end
  return true
end

function Journal.writeSegmentList(filename, manifest)
  local lines = {
    "APRSEGMENTS2",
    tostring(manifest.sourceFilename or ""),
    tostring(manifest.sourceTitle or ""),
    tostring(manifest.elapsedMs or 0),
    tostring(manifest.recordCount or 0),
    tostring(manifest.recordInterval or 1)
  }
  for _, segment in ipairs(manifest.segments or {}) do
    local outputStride = math.max(
      1,
      math.floor(tonumber(segment.outputStride) or 1))
    lines[#lines + 1] = tostring(outputStride) .. "\t" .. segment.filename
  end
  return writeAll(filename, table.concat(lines, "\n") .. "\n")
end

Journal.MAGIC = MAGIC
Journal.FLAG_CHECKPOINT = FLAG_CHECKPOINT
Journal.FLAG_FROM_UNDO = FLAG_FROM_UNDO
Journal.CODEC_RAW = CODEC_RAW
Journal.CODEC_PIXEL_RLE = CODEC_PIXEL_RLE

return Journal
