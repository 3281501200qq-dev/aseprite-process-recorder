param([Parameter(Mandatory = $true)][string]$JobFilename)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$job = [IO.File]::ReadAllText($JobFilename, $utf8) | ConvertFrom-Json
$mutex = New-Object Threading.Mutex($false, 'Local\AsepriteProcessRecorderExport')
$acquired = $false
try {
    try {
        $acquired = $mutex.WaitOne()
    } catch [Threading.AbandonedMutexException] {
        $acquired = $true
    }
    if (-not [IO.File]::Exists($JobFilename) -or [IO.File]::Exists($job.statusFilename)) { return }
    $manifest = [IO.File]::ReadAllText($job.manifest.manifestFilename, $utf8) | ConvertFrom-Json
    $exitCode = 99
    if ($manifest.exportRevision -eq $job.manifest.exportRevision) {
        $arguments = @('aseprite', '--segments', $job.segmentList,
            '--output-base', $job.manifest.outputBase, '--report', $job.reportFilename,
            '--max-frames', [string]$job.maxFrames, '--max-bytes', [string]$job.maxBytes,
            '--speed', [string]$job.manifest.playbackSpeed)
        & $job.helperPath @arguments 2>&1 | Out-File -LiteralPath $job.errorFilename -Encoding utf8
        $exitCode = $LASTEXITCODE
        if ($null -eq $exitCode) { $exitCode = 1 }
    }
    [IO.File]::WriteAllText($job.statusFilename + '.tmp', [string]$exitCode, $utf8)
    [IO.File]::Move($job.statusFilename + '.tmp', $job.statusFilename)
} catch {
    [IO.File]::WriteAllText($job.errorFilename, $_.Exception.ToString(), $utf8)
    if (-not [IO.File]::Exists($job.statusFilename)) {
        [IO.File]::WriteAllText($job.statusFilename + '.tmp', '1', $utf8)
        [IO.File]::Move($job.statusFilename + '.tmp', $job.statusFilename)
    }
} finally {
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
