param(
  [ValidateSet('help', 'init', 'doctor', 'infra', 'stop-infra', 'backend', 'frontend', 'check', 'start', 'status', 'stop', 'stop-all')]
  [string]$Command = 'help'
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$envPath = Join-Path $repoRoot '.env'
$localConfig = @{}
if (Test-Path -LiteralPath $envPath) {
  foreach ($line in Get-Content -LiteralPath $envPath -Encoding UTF8) {
    $text = $line.Trim()
    if (-not $text -or $text.StartsWith('#')) { continue }
    $separator = $text.IndexOf('=')
    if ($separator -lt 1) { continue }
    $name = $text.Substring(0, $separator).Trim()
    $value = $text.Substring($separator + 1).Trim()
    if ($value.Length -ge 2 -and (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'")))) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $localConfig[$name] = $value
  }
}

function Get-ConfigValue([string]$Name, [string]$Fallback = '') {
  if ($localConfig.ContainsKey($Name)) { return $localConfig[$Name] }
  $value = [Environment]::GetEnvironmentVariable($Name)
  if ($null -ne $value) { return $value }
  return $Fallback
}

function New-RandomSecret([switch]$Base64) {
  $bytes = New-Object byte[] 32
  $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
  try { $generator.GetBytes($bytes) }
  finally { $generator.Dispose() }
  if ($Base64) { return [Convert]::ToBase64String($bytes) }
  return [BitConverter]::ToString($bytes).Replace('-', '').ToLowerInvariant()
}

function Write-NewLocalFile([string]$Path, [string]$Content) {
  $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
  try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
    $stream.Write($bytes, 0, $bytes.Length)
  } finally { $stream.Dispose() }
}

function Get-JavaMajor([string]$Directory) {
  if (-not $Directory) { return $null }
  $java = Join-Path $Directory 'bin\java.exe'
  if (-not (Test-Path -LiteralPath $java)) { return $null }
  try {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $versionText = (& $java -version 2>&1 | Out-String)
    if ($LASTEXITCODE -eq 0 -and $versionText -match '(?:openjdk|java) version "(\d+)') {
      return [int]$Matches[1]
    }
  } finally {
    $ErrorActionPreference = $previousPreference
  }
  return $null
}

function Find-Java25 {
  if ($env:LEARNING_JAVA_HOME) {
    if ((Get-JavaMajor $env:LEARNING_JAVA_HOME) -ne 25) {
      throw 'LEARNING_JAVA_HOME must point to a JDK 25 installation.'
    }
    return $env:LEARNING_JAVA_HOME
  }
  if ((Get-JavaMajor $env:JAVA_HOME) -eq 25) { return $env:JAVA_HOME }
  $searchRoots = @(
    (Join-Path $env:ProgramFiles 'Eclipse Adoptium'),
    (Join-Path $env:ProgramFiles 'Java'),
    (Join-Path $env:USERPROFILE '.jdks')
  )
  foreach ($searchRoot in $searchRoots) {
    if (-not (Test-Path -LiteralPath $searchRoot)) { continue }
    foreach ($candidate in Get-ChildItem -LiteralPath $searchRoot -Directory) {
      if ((Get-JavaMajor $candidate.FullName) -eq 25) { return $candidate.FullName }
    }
  }
  return $null
}

function Use-Java25 {
  $selectedJdk = Find-Java25
  if (-not $selectedJdk) { throw 'JDK 25 was not found. Install it or set LEARNING_JAVA_HOME.' }
  $env:JAVA_HOME = $selectedJdk
  $env:PATH = (Join-Path $selectedJdk 'bin') + [IO.Path]::PathSeparator + $env:PATH
  Write-Host "Using JDK 25: $selectedJdk"
}

function Require-Command([string]$Name) {
  $resolved = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $resolved) { throw "Required command not found: $Name" }
  return $resolved.Source
}

function Invoke-Checked([string]$Executable, [string[]]$Arguments) {
  & $Executable @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Command failed with exit code $LASTEXITCODE`: $Executable" }
}

function Require-LocalConfig {
  if (-not (Test-Path -LiteralPath $envPath)) {
    throw 'Local .env is missing. Run .\dev.cmd init to create the learning configuration.'
  }
}

Push-Location $repoRoot
try {
  switch ($Command) {
    'help' {
      Write-Host 'InterviewGuide learning environment'
      Write-Host '  .\dev.cmd start       Start infrastructure, backend and frontend in the background'
      Write-Host '  .\dev.cmd status      Show application health and launcher ownership'
      Write-Host '  .\dev.cmd stop        Stop only applications started by this launcher'
      Write-Host '  .\dev.cmd stop-all    Stop learning services and launcher-started Docker when safe'
      Write-Host '  .\dev.cmd init        Create local configuration if it is missing'
      Write-Host '  .\dev.cmd doctor      Check tools and configuration presence'
      Write-Host '  .\dev.cmd infra       Start the isolated learning infrastructure'
      Write-Host '  .\dev.cmd stop-infra  Stop infrastructure and retain its data'
      Write-Host '  .\dev.cmd backend     Run the Java backend in this terminal'
      Write-Host '  .\dev.cmd frontend    Run the React frontend in this terminal'
      Write-Host '  .\dev.cmd check       Compile the backend and build the frontend'
    }
    'init' {
      if (Test-Path -LiteralPath $envPath) {
        Write-Host 'Local .env already exists; its contents were preserved.'
      } else {
        $templatePath = Join-Path $repoRoot '.env.learning.example'
        $configDirectory = [IO.Path]::GetFullPath((Join-Path $repoRoot '.learning\config'))
        [IO.Directory]::CreateDirectory($configDirectory) | Out-Null
        $content = [IO.File]::ReadAllText($templatePath)
        $content = $content.Replace('__ENCRYPTION_KEY__', (New-RandomSecret -Base64))
        $content = $content.Replace('__POSTGRES_PASSWORD__', (New-RandomSecret))
        $content = $content.Replace('__STORAGE_SECRET__', (New-RandomSecret))
        $content = $content.Replace('__RPC_SECRET__', (New-RandomSecret))
        $content = $content.Replace('__CONFIG_DIR__', $configDirectory.Replace('\', '/'))
        Write-NewLocalFile $envPath $content
        Write-Host 'Created local .env with random secrets and an empty model key.'
      }
      $frontendEnvPath = Join-Path $repoRoot 'frontend\.env.local'
      if (Test-Path -LiteralPath $frontendEnvPath) {
        Write-Host 'Frontend .env.local already exists; its contents were preserved.'
      } else {
        Write-NewLocalFile $frontendEnvPath "VITE_API_PROXY_TARGET=http://127.0.0.1:18080`r`n"
        Write-Host 'Created frontend .env.local for the learning backend.'
      }
      Write-Host 'No configuration values or secrets are printed.'
    }
    'doctor' {
      $jdk = Find-Java25
      Write-Host "JDK 25 available: $([bool]$jdk)"
      if ($jdk) { Write-Host "JDK directory: $jdk" }
      foreach ($tool in @('node.exe', 'pnpm.cmd', 'docker.exe')) {
        Write-Host "$tool available: $([bool](Get-Command $tool -ErrorAction SilentlyContinue))"
      }
      Write-Host "Local .env exists: $(Test-Path -LiteralPath $envPath)"
      Write-Host "Learning compose exists: $(Test-Path -LiteralPath (Join-Path $repoRoot 'compose.learning.yml'))"
      Write-Host "Frontend dependencies installed: $(Test-Path -LiteralPath (Join-Path $repoRoot 'frontend\node_modules'))"
      Write-Host "Cloud model key configured: $(-not [string]::IsNullOrWhiteSpace((Get-ConfigValue 'AI_BAILIAN_API_KEY')))"
      Write-Host 'No configuration values or secrets are printed.'
    }
    { $_ -in @('infra', 'stop-infra') } {
      Require-LocalConfig
      $docker = Require-Command 'docker.exe'
      $composeArguments = @('compose', '-p', 'interview-guide-learning', '-f', 'compose.learning.yml', '--env-file', '.env')
      if ($Command -eq 'infra') { $composeArguments += @('up', '-d', '--wait', '--wait-timeout', '120') }
      else { $composeArguments += 'stop' }
      Invoke-Checked $docker $composeArguments
    }
    'backend' {
      Require-LocalConfig
      Use-Java25
      $applicationArguments = @('--app.voice-interview.opening-audio-warmup-enabled=false')
      if ($env:INTERVIEW_GUIDE_LAUNCH_ID) {
        $applicationArguments += ('--learning.launch-id=' + $env:INTERVIEW_GUIDE_LAUNCH_ID)
      }
      if ([string]::IsNullOrWhiteSpace((Get-ConfigValue 'AI_BAILIAN_API_KEY'))) {
        Write-Host 'DashScope environment key is empty; using startup-only voice placeholders. Chat providers can be configured in app settings.'
        $applicationArguments += @(
          '--app.voice-interview.qwen.asr.api-key=local-unconfigured',
          '--app.voice-interview.qwen.tts.api-key=local-unconfigured'
        )
      }
      Invoke-Checked (Join-Path $repoRoot 'gradlew.bat') @(':app:bootRun', ('--args=' + ($applicationArguments -join ' ')))
    }
    'frontend' {
      $pnpm = Require-Command 'pnpm.cmd'
      $backendPort = Get-ConfigValue 'SERVER_PORT' '18080'
      if (-not $backendPort) { $backendPort = '18080' }
      $frontendPort = Get-ConfigValue 'FRONTEND_PORT' '5173'
      if (-not $frontendPort) { $frontendPort = '5173' }
      $env:VITE_API_PROXY_TARGET = "http://127.0.0.1:$backendPort"
      Set-Location (Join-Path $repoRoot 'frontend')
      Invoke-Checked $pnpm @('dev', '--host', '127.0.0.1', '--port', $frontendPort, '--strictPort')
    }
    'check' {
      Use-Java25
      $pnpm = Require-Command 'pnpm.cmd'
      Invoke-Checked (Join-Path $repoRoot 'gradlew.bat') @(':app:compileJava', '--no-daemon')
      Set-Location (Join-Path $repoRoot 'frontend')
      Invoke-Checked $pnpm @('run', 'build')
    }
    { $_ -in @('start', 'status', 'stop', 'stop-all') } {
      & (Join-Path $PSScriptRoot 'learning-services.ps1') -Command $Command
    }
  }
} catch {
  Write-Error $_.Exception.Message -ErrorAction Continue
  exit 1
} finally {
  Pop-Location
}
