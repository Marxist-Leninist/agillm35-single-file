param(
  [string]$GethHost = "5.75.217.57",
  [string]$GethUser = "root",
  [string]$KeyPath = "$env:USERPROFILE\.ssh\agillm35_laptop_reverse_ed25519",
  [string]$RemoteRoot = "/root/agillm4_opportunistic",
  [string]$LocalRoot = "C:\agillm4_worker",
  [string]$WorkerId = "laptop-auto",
  [string]$Python = "python",
  [string]$Device = "auto",
  [int]$Threads = 0,
  [int]$PollSeconds = 300,
  [switch]$Once,
  [switch]$Force,
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$sshBase = @("-i", $KeyPath, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3")
$scpBase = @("-i", $KeyPath, "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=20", "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=6")
$remote = "$GethUser@$GethHost"

function Resolve-Threads {
  if ($Threads -gt 0) { return $Threads }
  try {
    $logical = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    if ($logical -and $logical -gt 0) { return [int]$logical }
  } catch {}
  return [Math]::Max(1, [Environment]::ProcessorCount)
}

$resolvedThreads = Resolve-Threads

function New-Dirs {
  foreach ($name in @("code", "runtime", "packages", "updates", "logs", "state")) {
    New-Item -ItemType Directory -Force -Path (Join-Path $LocalRoot $name) | Out-Null
  }
}

function Invoke-SSH([string]$Command) {
  & ssh @sshBase $remote $Command
  if ($LASTEXITCODE -ne 0) { throw "ssh failed rc=$LASTEXITCODE command=$Command" }
}

function Read-SSH([string]$Command) {
  $out = & ssh @sshBase $remote $Command
  if ($LASTEXITCODE -ne 0) { return "" }
  return ($out -join "`n")
}

function Invoke-SCPFrom([string]$RemotePath, [string]$LocalPath) {
  & scp @scpBase "${remote}:$RemotePath" $LocalPath
  if ($LASTEXITCODE -ne 0) { throw "scp from $RemotePath failed rc=$LASTEXITCODE" }
}

function Invoke-SCPTo([string]$LocalPath, [string]$RemotePath) {
  & scp @scpBase $LocalPath "${remote}:$RemotePath"
  if ($LASTEXITCODE -ne 0) { throw "scp to $RemotePath failed rc=$LASTEXITCODE" }
}

function Write-Heartbeat([string]$State, [hashtable]$Extra = @{}) {
  $hb = @{
    worker_id = $WorkerId
    host = $env:COMPUTERNAME
    state = $State
    device = $Device
    threads = $resolvedThreads
    at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  }
  foreach ($k in $Extra.Keys) { $hb[$k] = $Extra[$k] }
  $tmp = Join-Path $LocalRoot "state\heartbeat.json"
  ($hb | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $tmp -Encoding ascii
  Invoke-SSH "mkdir -p '$RemoteRoot/heartbeats'"
  Invoke-SCPTo $tmp "$RemoteRoot/heartbeats/$WorkerId.json.tmp"
  Invoke-SSH "mv '$RemoteRoot/heartbeats/$WorkerId.json.tmp' '$RemoteRoot/heartbeats/$WorkerId.json'"
}

function Get-RemoteStat([string]$Path) {
  $text = Read-SSH "if [ -s '$Path' ]; then stat -c '%Y %s' '$Path'; fi"
  if (-not $text.Trim()) { return $null }
  $parts = $text.Trim().Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
  if ($parts.Count -lt 2) { return $null }
  return @{ Stamp = "$($parts[0])-$($parts[1])"; Mtime = $parts[0]; Size = [int64]$parts[1] }
}

function Copy-IfSizeDiffers([string]$RemotePath, [string]$LocalPath) {
  $stat = Get-RemoteStat $RemotePath
  if ($null -eq $stat) { throw "missing remote path $RemotePath" }
  if ((Test-Path -LiteralPath $LocalPath) -and ((Get-Item -LiteralPath $LocalPath).Length -eq $stat.Size)) {
    return
  }
  Invoke-SCPFrom $RemotePath $LocalPath
}

function Run-Worker([string]$RunDevice, [string]$LeaseStamp) {
  $worker = Join-Path $LocalRoot "code\agillm4_slice_bench_worker.py"
  $package = Join-Path $LocalRoot "packages\lease_$WorkerId.pt"
  $shared = Join-Path $LocalRoot "packages\shared_frozen.pt"
  $runtime = Join-Path $LocalRoot "runtime\nB300_agillm4.py"
  $out = Join-Path $LocalRoot "updates\$WorkerId`_$LeaseStamp.pt"
  $log = Join-Path $LocalRoot "logs\$WorkerId`_$LeaseStamp`_$($RunDevice.Replace(':','_')).log"
  Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
  $env:OMP_NUM_THREADS = [string]$resolvedThreads
  $env:MKL_NUM_THREADS = [string]$resolvedThreads
  $env:OPENBLAS_NUM_THREADS = [string]$resolvedThreads
  $args = @(
    "-u", $worker,
    "--package", $package,
    "--shared", $shared,
    "--runtime", $runtime,
    "--out", $out,
    "--device", $RunDevice,
    "--threads", [string]$resolvedThreads
  )
  Write-Heartbeat "running" @{ lease = $LeaseStamp; run_device = $RunDevice }
  & $Python @args > $log 2>&1
  $rc = $LASTEXITCODE
  if ($rc -ne 0) {
    Write-Heartbeat "worker_failed" @{ lease = $LeaseStamp; run_device = $RunDevice; rc = $rc; log = $log }
    return $null
  }
  if (-not (Test-Path -LiteralPath $out)) { throw "worker completed but did not create $out" }
  return $out
}

function One-Poll {
  New-Dirs
  if (-not (Test-Path -LiteralPath $KeyPath)) { throw "missing SSH key $KeyPath" }
  Invoke-SSH "mkdir -p '$RemoteRoot/updates' '$RemoteRoot/heartbeats'"
  $leaseRemote = "$RemoteRoot/current/lease_$WorkerId.pt"
  $leaseStat = Get-RemoteStat $leaseRemote
  if ($null -eq $leaseStat) {
    Write-Heartbeat "idle_no_lease"
    return
  }
  $leaseStamp = $leaseStat.Stamp
  $doneFile = Join-Path $LocalRoot "state\done_$WorkerId.txt"
  if ((-not $Force) -and (Test-Path -LiteralPath $doneFile) -and ((Get-Content -LiteralPath $doneFile -Raw).Trim() -eq $leaseStamp)) {
    Write-Heartbeat "idle_already_done" @{ lease = $leaseStamp }
    return
  }

  Write-Heartbeat "pulling" @{ lease = $leaseStamp }
  Copy-IfSizeDiffers "$RemoteRoot/runtime/nB300_agillm4.py" (Join-Path $LocalRoot "runtime\nB300_agillm4.py")
  Copy-IfSizeDiffers "$RemoteRoot/runtime/dblocks_train.py" (Join-Path $LocalRoot "runtime\dblocks_train.py")
  Copy-IfSizeDiffers "$RemoteRoot/runtime/fused_ce.py" (Join-Path $LocalRoot "runtime\fused_ce.py")
  $anchorStat = Get-RemoteStat "$RemoteRoot/runtime/anchor_memory.py"
  if ($null -ne $anchorStat) {
    Copy-IfSizeDiffers "$RemoteRoot/runtime/anchor_memory.py" (Join-Path $LocalRoot "runtime\anchor_memory.py")
  }
  Copy-IfSizeDiffers "$RemoteRoot/code/agillm4_slice_bench_worker.py" (Join-Path $LocalRoot "code\agillm4_slice_bench_worker.py")
  Copy-IfSizeDiffers "$RemoteRoot/current/shared_frozen.pt" (Join-Path $LocalRoot "packages\shared_frozen.pt")
  Copy-IfSizeDiffers $leaseRemote (Join-Path $LocalRoot "packages\lease_$WorkerId.pt")

  if ($DryRun) {
    Write-Heartbeat "dry_run_ready" @{ lease = $leaseStamp }
    return
  }

  $devices = @()
  if ($Device -eq "auto") {
    $devices = @("cuda:0", "cpu")
  } else {
    $devices = @($Device)
    if ($Device.StartsWith("cuda")) { $devices += "cpu" }
  }

  $out = $null
  foreach ($runDevice in $devices) {
    $out = Run-Worker $runDevice $leaseStamp
    if ($null -ne $out) { break }
  }
  if ($null -eq $out) { throw "all requested devices failed for lease $leaseStamp" }

  Write-Heartbeat "uploading" @{ lease = $leaseStamp; bytes = (Get-Item -LiteralPath $out).Length }
  $remoteOut = "$RemoteRoot/updates/$WorkerId`_$LeaseStamp.pt"
  Invoke-SCPTo $out "$remoteOut.tmp"
  Invoke-SSH "mv '$remoteOut.tmp' '$remoteOut'"
  Set-Content -LiteralPath $doneFile -Encoding ascii -Value $leaseStamp
  Write-Heartbeat "done" @{ lease = $leaseStamp; remote_update = $remoteOut; bytes = (Get-Item -LiteralPath $out).Length }
}

$lockPath = Join-Path $LocalRoot "state\worker.lock"
New-Dirs
if (Test-Path -LiteralPath $lockPath) {
  try {
    $existing = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json
    $pid = [int]$existing.pid
    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
    if ($proc) {
      Write-Output "AGILLM4 opportunistic worker already running as PID $pid"
      exit 0
    }
  } catch {}
}
@{
  pid = $PID
  worker_id = $WorkerId
  started_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
} | ConvertTo-Json | Set-Content -LiteralPath $lockPath -Encoding ascii

try {
while ($true) {
  try {
    One-Poll
  } catch {
    try { Write-Heartbeat "error" @{ error = "$_" } } catch {}
    Write-Error $_
    if ($Once) { exit 1 }
  }
  if ($Once) { break }
  Start-Sleep -Seconds $PollSeconds
}
} finally {
  Remove-Item -LiteralPath $lockPath -ErrorAction SilentlyContinue
}
