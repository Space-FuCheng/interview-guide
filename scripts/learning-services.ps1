param(
  [ValidateSet('start', 'status', 'stop', 'stop-all')]
  [string]$Command = 'status'
)

$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$learningScript = Join-Path $PSScriptRoot 'learning.ps1'
$stateDirectory = Join-Path $repoRoot '.learning'
$statePath = Join-Path $stateDirectory 'services.json'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$backendPort = 18080
$frontendPort = 5173
$envPath = Join-Path $repoRoot '.env'
if (Test-Path -LiteralPath $envPath) {
  foreach ($line in Get-Content -LiteralPath $envPath -Encoding UTF8) {
    if ($line -match '^SERVER_PORT=(\d+)\s*$') { $backendPort = [int]$Matches[1] }
    if ($line -match '^FRONTEND_PORT=(\d+)\s*$') { $frontendPort = [int]$Matches[1] }
  }
}
$backendUrl = "http://127.0.0.1:$backendPort/actuator/health"
$frontendUrl = "http://127.0.0.1:$frontendPort/"

function Read-State {
  if (-not (Test-Path -LiteralPath $statePath)) {
    return [pscustomobject]@{ Version = 1; RepoRoot = $repoRoot; Backend = $null; Frontend = $null }
  }
  $value = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($value.Version -ne 1 -or $value.RepoRoot -ne $repoRoot) {
    throw 'The launcher state belongs to a different workspace or version.'
  }
  return $value
}

function Save-State {
  [IO.Directory]::CreateDirectory($stateDirectory) | Out-Null
  [IO.File]::WriteAllText($statePath, ($script:state | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
}

function Get-CommandHash([string]$Text) {
  $hash = [Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))).Replace('-', '') }
  finally { $hash.Dispose() }
}

function Get-ProcessIdentity([int]$ProcessId) {
  $process = Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
  if (-not $process -or -not $process.CommandLine) { return $null }
  return [pscustomobject]@{
    ProcessId = $process.ProcessId
    StartedUtc = $process.CreationDate.ToUniversalTime().ToString('o')
    CommandHash = Get-CommandHash $process.CommandLine
  }
}

function Test-Identity($Identity) {
  if (-not $Identity) { return $false }
  $current = Get-ProcessIdentity ([int]$Identity.ProcessId)
  if (-not $current -or $current.CommandHash -ne $Identity.CommandHash) { return $false }
  try {
    $currentTime = [DateTimeOffset]::Parse($current.StartedUtc).UtcDateTime.Ticks
    $savedTime = [DateTimeOffset]::Parse([string]$Identity.StartedUtc).UtcDateTime.Ticks
    return ($currentTime -eq $savedTime)
  } catch { return $false }
}

function Test-ResumeHealth([string]$BaseUrl) {
  $response = Invoke-RestMethod -Uri ($BaseUrl + '/api/resumes/health') -TimeoutSec 2
  return ($response.code -eq 200 -and $response.data.status -eq 'UP' -and $response.data.service -ceq 'AI Interview Platform - Resume Service')
}

function Test-Health([string]$Service) {
  try {
    if ($Service -eq 'Backend') {
      $response = Invoke-RestMethod -Uri $backendUrl -TimeoutSec 2
      return ($response.status -eq 'UP' -and (Test-ResumeHealth "http://127.0.0.1:$backendPort"))
    }
    $response = Invoke-WebRequest -Uri $frontendUrl -UseBasicParsing -TimeoutSec 2
    return ($response.StatusCode -eq 200 -and $response.Content -match '/src/main.tsx' -and (Test-ResumeHealth "http://127.0.0.1:$frontendPort"))
  } catch { return $false }
}

function Test-Port([int]$Port) {
  $client = New-Object Net.Sockets.TcpClient
  try {
    $connection = $client.ConnectAsync('127.0.0.1', $Port)
    return ($connection.Wait(500) -and $client.Connected)
  } catch { return $false }
  finally { $client.Dispose() }
}

function Invoke-Learning([string]$Action) {
  & $powershell -NoProfile -ExecutionPolicy Bypass -File $learningScript $Action
  if ($LASTEXITCODE -ne 0) { throw "Learning command failed: $Action" }
}

function Test-Docker {
  try {
    if (-not (Get-Process -Name 'Docker Desktop', 'com.docker.backend' -ErrorAction SilentlyContinue)) { return $false }
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = (Get-Command docker.exe -ErrorAction Stop).Source
    # Compose needs container listing, which may fail briefly after Docker info succeeds.
    $info.Arguments = 'ps --all --quiet --filter label=com.docker.compose.project=interview-guide-learning'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $process = [Diagnostics.Process]::Start($info)
    if (-not $process.WaitForExit(5000)) { $process.Kill(); return $false }
    return ($process.ExitCode -eq 0)
  } catch { return $false }
}

function Test-DockerWslRunning {
  $previousEncoding = [Console]::OutputEncoding
  try {
    [Console]::OutputEncoding = [Text.Encoding]::Unicode
    $names = @(& wsl.exe --list --running --quiet 2>$null)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect WSL state.' }
    return [bool]($names | Where-Object { (($_ -replace "`0", '').Trim()) -eq 'docker-desktop' })
  } finally { [Console]::OutputEncoding = $previousEncoding }
}

function Ensure-Docker {
  if (Test-Docker) {
    Start-Sleep -Seconds 2
    if (Test-Docker) { return }
  }
  if (-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
    $script:state | Add-Member -NotePropertyName DockerStartedByLauncher -NotePropertyValue $true -Force
    $script:state | Add-Member -NotePropertyName DockerWslWasRunning -NotePropertyValue (Test-DockerWslRunning) -Force
    Save-State
  }
  $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
  if (-not (Test-Path -LiteralPath $desktop)) { throw 'Docker Desktop was not found. Install or start Docker, then retry.' }
  if (-not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
    Write-Host 'Starting Docker Desktop...'
    Start-Process -FilePath $desktop -WindowStyle Hidden | Out-Null
  } else {
    Write-Host 'Waiting for Docker Desktop to be ready...'
  }
  $deadline = [DateTime]::UtcNow.AddSeconds(90)
  while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Docker) {
      Start-Sleep -Seconds 2
      if (Test-Docker) { return }
    }
    Start-Sleep -Seconds 3
  }
  throw 'Docker is not ready after 90 seconds. Check Docker Desktop and retry.'
}

function Test-Descendant([int]$ProcessId, [int]$RootId) {
  $currentId = $ProcessId
  for ($level = 0; $level -lt 20 -and $currentId -gt 0; $level++) {
    if ($currentId -eq $RootId) { return $true }
    $current = Get-CimInstance Win32_Process -Filter "ProcessId=$currentId" -ErrorAction SilentlyContinue
    if (-not $current) { return $false }
    $currentId = [int]$current.ParentProcessId
  }
  return $false
}

function Start-ServiceProcess([string]$Service, [int]$Port) {
  $old = $script:state.$Service
  if (Test-Health $Service) {
    $ownership = if ($old -and (Test-Identity $old.Listener)) { 'launcher-owned' } else { 'existing process; not managed' }
    Write-Host "$Service is already healthy ($ownership)."
    if ($Service -eq 'Backend') { Write-Host 'Existing backend was reused; check its own debug configuration before attaching.' }
    return
  }
  if ($Service -eq 'Backend' -and (Test-Port 5005)) { throw 'Backend debug port 5005 is already in use. Stop the other debugger target and retry.' }
  if (Test-Port $Port) { throw "$Service port $Port is occupied but its health check failed. Inspect that process; the launcher will not stop it." }
  if ($old -and (Test-Identity $old.Root)) { throw "$Service is already starting or unhealthy. Inspect its logs or run .\dev.cmd stop before retrying." }
  $launchId = [guid]::NewGuid().ToString('N')
  $action = $Service.ToLowerInvariant()
  $stdout = Join-Path $stateDirectory "$action.stdout.log"
  $stderr = Join-Path $stateDirectory "$action.stderr.log"
  $previousId = $env:INTERVIEW_GUIDE_LAUNCH_ID
  try {
    $env:INTERVIEW_GUIDE_LAUNCH_ID = $launchId
    $process = Start-Process -FilePath $powershell -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $learningScript + '" ' + $action) -WorkingDirectory $repoRoot -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
  } finally { $env:INTERVIEW_GUIDE_LAUNCH_ID = $previousId }
  $rootIdentity = Get-ProcessIdentity $process.Id
  if (-not $rootIdentity) { throw "$Service launcher exited immediately. Inspect $stderr" }
  $record = [pscustomobject]@{ LaunchId = $launchId; Root = $rootIdentity; Listener = $null; Stdout = $stdout; Stderr = $stderr }
  $script:state.$Service = $record
  Save-State
  Write-Host "Waiting for $Service (logs: $stdout, $stderr)..."
  $deadline = [DateTime]::UtcNow.AddSeconds(180)
  while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Health $Service) {
      $listenerId = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction Stop | Select-Object -First 1 -ExpandProperty OwningProcess
      $listener = Get-CimInstance Win32_Process -Filter "ProcessId=$listenerId"
      $owned = if ($Service -eq 'Backend') {
        $listener.CommandLine -like '*interview.guide.App*' -and $listener.CommandLine.Contains('--learning.launch-id=' + $launchId)
      } else {
        $listener.CommandLine -like '*vite*' -and (Test-Descendant ([int]$listenerId) ([int]$process.Id))
      }
      if (-not $owned) { throw "$Service became healthy through a different process. It was not adopted; inspect the launcher logs." }
      $record.Listener = Get-ProcessIdentity ([int]$listenerId)
      Save-State
      Write-Host "$Service is ready."
      return
    }
    if (-not (Test-Identity $rootIdentity)) { throw "$Service launcher exited before becoming healthy. Inspect $stdout and $stderr" }
    Start-Sleep -Seconds 2
  }
  throw "$Service did not become healthy within 180 seconds. Inspect $stdout and $stderr; managed processes are retained for diagnosis."
}

function Show-Status {
  foreach ($service in @('Backend', 'Frontend')) {
    $record = $script:state.$service
    $health = if (Test-Health $service) { 'ready' } else { 'not ready' }
    $ownership = if ($record -and ((Test-Identity $record.Root) -or (Test-Identity $record.Listener))) { 'launcher-owned' } else { 'not managed' }
    Write-Host "$service`: $health; $ownership"
  }
  Write-Host "Application: http://localhost:$frontendPort"
  Write-Host "Backend: http://localhost:$backendPort"
  Write-Host 'Backend debugger: 127.0.0.1:5005 (attach from IDEA)'
  Write-Host "Logs/state: $stateDirectory"
}

function Find-OwnedBackendProcesses($Record) {
  if (-not $Record.Root -or $Record.LaunchId -notmatch '^[a-f0-9]{32}$') {
    throw 'The backend launcher record does not contain a valid ownership marker.'
  }
  $rootStarted = [DateTime]::Parse($Record.Root.StartedUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
  $markerPattern = '(?<!\S)"?--learning\.launch-id=' + [regex]::Escape($Record.LaunchId) + '"?(?=\s|$)'
  foreach ($candidate in Get-CimInstance Win32_Process -Filter "Name = 'java.exe' OR Name = 'javaw.exe'") {
    if ($candidate.CommandLine -notmatch '(?<!\S)interview\.guide\.App(?=\s|$)' -or $candidate.CommandLine -notmatch $markerPattern) { continue }
    if ($candidate.CreationDate.ToUniversalTime() -lt $rootStarted.ToUniversalTime()) { continue }
    $identity = Get-ProcessIdentity ([int]$candidate.ProcessId)
    if ($identity -and $identity.StartedUtc -eq $candidate.CreationDate.ToUniversalTime().ToString('o') -and $identity.CommandHash -eq (Get-CommandHash $candidate.CommandLine)) {
      $identity
    }
  }
}

function Stop-OwnedProcesses {
  foreach ($service in @('Frontend', 'Backend')) {
    $record = $script:state.$service
    if (-not $record) { continue }
    $ownedListeners = @()
    if ($record.Listener) { $ownedListeners += $record.Listener }
    # A Gradle daemon can launch Java outside the wrapper's process tree, even before health succeeds.
    if ($service -eq 'Backend') { $ownedListeners += @(Find-OwnedBackendProcesses $record) }
    foreach ($identity in $ownedListeners | Group-Object ProcessId | ForEach-Object { $_.Group[0] }) {
      if (Test-Identity $identity) { Stop-Process -Id ([int]$identity.ProcessId) -ErrorAction Stop }
    }
    if (Test-Identity $record.Root) {
      $previousPreference = $ErrorActionPreference
      try {
        $ErrorActionPreference = 'Continue'
        & taskkill.exe /PID ([int]$record.Root.ProcessId) /T /F 2>$null | Out-Null
      } finally { $ErrorActionPreference = $previousPreference }
      if ($LASTEXITCODE -ne 0 -and (Test-Identity $record.Root)) { throw "Could not stop the owned $service launcher." }
    }
    $script:state.$service = $null
    Write-Host "$service launcher-owned processes stopped or already exited."
  }
  Save-State
  Write-Host 'Existing external/IDEA processes and infrastructure were retained. Use stop-infra separately when needed.'
}

$hash = Get-CommandHash $repoRoot.ToLowerInvariant()
$mutex = New-Object Threading.Mutex($false, ('Local\InterviewGuideLearning_' + $hash.Substring(0, 20)))
$locked = $false
try {
  try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
  if (-not $locked) { throw 'Another learning start/status/stop command is still running.' }
  $state = Read-State
  switch ($Command) {
    'start' {
      Invoke-Learning 'init'
      [IO.Directory]::CreateDirectory($stateDirectory) | Out-Null
      if (-not (Test-Path -LiteralPath (Join-Path $repoRoot 'frontend\node_modules'))) { throw 'Frontend dependencies are missing. In frontend/, run pnpm.cmd install --frozen-lockfile first.' }
      Ensure-Docker
      Invoke-Learning 'infra'
      Start-ServiceProcess 'Backend' $backendPort
      Start-ServiceProcess 'Frontend' $frontendPort
      Show-Status
    }
    'status' { Show-Status }
    'stop' { Stop-OwnedProcesses; Show-Status }
    'stop-all' {
      Stop-OwnedProcesses
      if (Test-Docker) {
        Invoke-Learning 'stop-infra'
        $remainingContainers = @(& docker.exe ps -q)
        if ($LASTEXITCODE -ne 0) { throw 'Could not inspect Docker containers.' }
      } else {
        $remainingContainers = @()
        Write-Host 'Docker engine is not running; learning containers are already stopped.'
      }
      $dockerCli = Join-Path $env:ProgramFiles 'Docker\Docker\DockerCli.exe'
      if ($script:state.DockerStartedByLauncher -and $remainingContainers.Count -eq 0 -and (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
        if (-not (Test-Path -LiteralPath $dockerCli)) { throw 'DockerCli.exe was not found; Docker Desktop could not be stopped.' }
        & $dockerCli -Shutdown
        if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop shutdown failed.' }
        $deadline = [DateTime]::UtcNow.AddSeconds(60)
        while ((Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Seconds 1 }
        if (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue) { throw 'Docker Desktop did not exit within 60 seconds.' }
        Write-Host 'Docker Desktop stopped.'
      } else {
        Write-Host 'Docker Desktop retained if it was already running or other containers are active.'
      }
      if ($script:state.DockerStartedByLauncher -and -not $script:state.DockerWslWasRunning -and $remainingContainers.Count -eq 0 -and -not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue) -and (Test-DockerWslRunning)) {
        & wsl.exe --terminate docker-desktop
        if ($LASTEXITCODE -ne 0) { throw 'Could not stop the Docker WSL distribution.' }
        Write-Host 'Docker WSL distribution stopped.'
      }
      if ($script:state.DockerStartedByLauncher -and $remainingContainers.Count -eq 0 -and -not (Get-Process -Name 'Docker Desktop' -ErrorAction SilentlyContinue)) {
        $script:state.DockerStartedByLauncher = $false
        Save-State
      }
      Write-Host 'Other WSL distributions are retained.'
    }
  }
} finally {
  if ($locked) { $mutex.ReleaseMutex() }
  $mutex.Dispose()
}
