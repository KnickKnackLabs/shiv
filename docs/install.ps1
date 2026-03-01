#Requires -Version 7.0
# shiv quick-install for Windows — https://shiv.knacklabs.co
# Usage: irm shiv.knacklabs.co/install.ps1 | iex
$ErrorActionPreference = 'Stop'

# Configuration via environment variables
$ShivNonInteractive = $env:SHIV_NONINTERACTIVE -eq '1'
$ShivInstallPath = if ($env:SHIV_INSTALL_PATH) { $env:SHIV_INSTALL_PATH } else { Join-Path $env:LOCALAPPDATA 'shiv\self' }
$ShivBinDir = if ($env:SHIV_BIN_DIR) { $env:SHIV_BIN_DIR } else { Join-Path $env:LOCALAPPDATA 'shiv\bin' }
$ShivConfigDir = if ($env:SHIV_CONFIG_DIR) { $env:SHIV_CONFIG_DIR } else { Join-Path $env:APPDATA 'shiv' }
$ShivRegistries = $env:SHIV_REGISTRIES
$TotalSteps = 6

$ChicleUrl = 'https://github.com/KnickKnackLabs/chicle/releases/latest/download/chicle.psm1'

# Detect non-interactive environment
if (-not [Environment]::UserInteractive) {
    $ShivNonInteractive = $true
}

# --- Load chicle with graceful fallback ---
$chicleLoaded = $false
try {
    $chicleTemp = Join-Path ([System.IO.Path]::GetTempPath()) "chicle_$([guid]::NewGuid().ToString('N')).psm1"
    Invoke-WebRequest -Uri $ChicleUrl -OutFile $chicleTemp -ErrorAction Stop
    Import-Module $chicleTemp -Force -ErrorAction Stop
    $chicleLoaded = $true
} catch {
    # Fallback functions
    function Chicle-Style {
        param([switch]$Bold, [switch]$Dim, [switch]$Cyan, [switch]$Green, [switch]$Yellow, [switch]$Red, [Parameter(Position=0)][string]$Text = '')
        $Text
    }
    function Chicle-Rule { Write-Host ([string]::new([char]0x2500, 40)) }
    function Chicle-Log {
        $level = ''; $message = ''
        foreach ($a in $args) {
            switch ($a) {
                '--info'    { $level = 'info' }
                '--success' { $level = 'success' }
                '--warn'    { $level = 'warn' }
                '--error'   { $level = 'error' }
                '--step'    { $level = 'step' }
                default     { $message = $a }
            }
        }
        switch ($level) {
            'info'    { Write-Host "$([char]0x2139) $message" }
            'success' { Write-Host "$([char]0x2713) $message" }
            'warn'    { Write-Host "$([char]0x26A0) $message" }
            'error'   { Write-Host "$([char]0x2717) $message" }
            'step'    { Write-Host "$([char]0x2192) $message" }
            default   { Write-Host $message }
        }
    }
    function Chicle-Steps {
        param([int]$Current, [int]$Total, [string]$Title, [string]$Style = 'numeric')
        Write-Host "[$Current/$Total] $Title"
    }
    function Chicle-Spin {
        param([string]$Title, [Parameter(Mandatory)][scriptblock]$ScriptBlock)
        Write-Host "... $Title"
        & $ScriptBlock
    }
    function Chicle-Confirm {
        param([Parameter(Position=0)][string]$Prompt, [string]$Default = 'no')
        $hint = if ($Default -eq 'yes') { '[Y/n]' } else { '[y/N]' }
        $reply = Read-Host "$Prompt $hint"
        if ([string]::IsNullOrEmpty($reply)) { return ($Default -eq 'yes') }
        return ($reply -match '^[Yy]')
    }
    function Chicle-Choose {
        param([string]$Header, [switch]$Multi, [Parameter(ValueFromRemainingArguments)][string[]]$Options)
        if ($Header) { Write-Host $Header }
        for ($i = 0; $i -lt $Options.Count; $i++) { Write-Host "  $($i+1)) $($Options[$i])" }
        $choice = Read-Host '>'
        $Options[[int]$choice - 1]
    }
}

function Test-Interactive {
    (-not $ShivNonInteractive) -and [Environment]::UserInteractive
}

# --- Step 1: Detect environment ---
Write-Host ''
Chicle-Rule
Write-Host (Chicle-Style -Bold 'shiv installer')
Chicle-Rule
Write-Host ''

Chicle-Steps -Current 1 -Total $TotalSteps -Title 'Detecting environment' -Style dots

$osName = if ($IsWindows) { 'Windows' } elseif ($IsMacOS) { 'macOS' } else { 'Linux' }
$archName = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLower()

Chicle-Log --success "Detected $osName ($archName), shell: PowerShell $($PSVersionTable.PSVersion)"

foreach ($cmd in @('git')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Chicle-Log --error "Required tool not found: $cmd"
        Chicle-Log --info "Install $cmd and re-run the installer."
        exit 1
    }
}

Chicle-Log --success 'Prerequisites satisfied (git)'
Write-Host ''

# --- Step 2: Set up mise ---
Chicle-Steps -Current 2 -Total $TotalSteps -Title 'Setting up mise' -Style dots

if (Get-Command mise -ErrorAction SilentlyContinue) {
    $miseVersion = (mise --version 2>$null | Select-Object -First 1)
    Chicle-Log --success "mise already installed ($miseVersion)"
} else {
    Chicle-Log --info 'mise not found - installing...'

    # Try winget first, then fall back to PowerShell installer
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Chicle-Spin -Title 'Installing mise via winget' -ScriptBlock {
            winget install jdx.mise --accept-source-agreements --accept-package-agreements 2>$null
        }
    } else {
        Chicle-Spin -Title 'Installing mise' -ScriptBlock {
            & ([scriptblock]::Create((Invoke-WebRequest -Uri 'https://mise.jdx.dev/install.ps1').Content))
        }
    }

    # Refresh PATH
    $env:PATH = "$env:LOCALAPPDATA\mise;$env:PATH"

    if (Get-Command mise -ErrorAction SilentlyContinue) {
        Chicle-Log --success 'mise installed successfully'
    } else {
        Chicle-Log --error 'mise installation failed'
        exit 1
    }
}
Write-Host ''

# --- Step 3: Install shiv ---
Chicle-Steps -Current 3 -Total $TotalSteps -Title 'Installing shiv' -Style dots

if (Test-Path (Join-Path $ShivInstallPath '.git')) {
    Chicle-Log --info 'shiv already installed - updating...'
    Chicle-Spin -Title 'Pulling latest' -ScriptBlock {
        git -C $using:ShivInstallPath pull --ff-only --quiet
    }
    Chicle-Log --success 'shiv updated'
} else {
    $parentDir = Split-Path $ShivInstallPath -Parent
    if (-not (Test-Path $parentDir)) { New-Item -ItemType Directory -Path $parentDir -Force | Out-Null }
    Chicle-Spin -Title 'Cloning shiv' -ScriptBlock {
        git clone --quiet https://github.com/KnickKnackLabs/shiv.git $using:ShivInstallPath
    }
    Chicle-Log --success "shiv cloned to $ShivInstallPath"
}

Chicle-Spin -Title 'Installing shiv dependencies' -ScriptBlock {
    Set-Location $using:ShivInstallPath
    mise trust -q 2>$null
    mise install -q 2>$null
}
Chicle-Log --success 'shiv dependencies ready'
Write-Host ''

# --- Step 4: Configure registries ---
Chicle-Steps -Current 4 -Total $TotalSteps -Title 'Configuring package sources' -Style dots

$sourcesDir = Join-Path $ShivConfigDir 'sources'
if (-not (Test-Path $sourcesDir)) { New-Item -ItemType Directory -Path $sourcesDir -Force | Out-Null }

# KnickKnackLabs sources (always installed)
Copy-Item (Join-Path $ShivInstallPath 'sources.json') (Join-Path $sourcesDir 'knacklabs.json') -Force
Chicle-Log --success 'Added KnickKnackLabs packages'

function Add-RiconRegistry {
    @'
{
  "fold": "ricon-family/fold",
  "food": "ricon-family/food-life"
}
'@ | Set-Content (Join-Path $sourcesDir 'ricon-family.json') -Encoding UTF8
    Chicle-Log --success 'Added ricon-family packages'
}

if ($ShivRegistries) {
    if ($ShivRegistries -match 'ricon-family') {
        Add-RiconRegistry
    }
} elseif (Test-Interactive) {
    Write-Host ''
    $selected = Chicle-Choose -Header 'Additional package registries' -Multi 'ricon-family (fold, food)'
    if ($selected -match 'ricon-family') {
        Add-RiconRegistry
    }
}

$packageCount = 0
Get-ChildItem (Join-Path $sourcesDir '*.json') -ErrorAction SilentlyContinue | ForEach-Object {
    $packageCount += ((Get-Content $_.FullName | ConvertFrom-Json).PSObject.Properties | Measure-Object).Count
}
Chicle-Log --success "$packageCount packages available"
Write-Host ''

# --- Step 5: Shell integration ---
Chicle-Steps -Current 5 -Total $TotalSteps -Title 'Setting up shell integration' -Style dots

# Create shiv's own shim (PowerShell + cmd wrapper)
if (-not (Test-Path $ShivBinDir)) { New-Item -ItemType Directory -Path $ShivBinDir -Force | Out-Null }

$shimPs1 = Join-Path $ShivBinDir 'shiv.ps1'
@"
# managed by shiv
`$Repo = '$ShivInstallPath'
if (-not (Test-Path `$Repo)) {
    Write-Error 'shiv: repo not found at `$Repo'
    exit 1
}
mise -C `$Repo run @args
"@ | Set-Content $shimPs1 -Encoding UTF8

$shimCmd = Join-Path $ShivBinDir 'shiv.cmd'
@"
@echo off
pwsh -NoProfile -File "%~dp0shiv.ps1" %*
"@ | Set-Content $shimCmd -Encoding UTF8

# Initialize registry
$registryFile = Join-Path $ShivConfigDir 'registry.json'
if (-not (Test-Path (Split-Path $registryFile -Parent))) {
    New-Item -ItemType Directory -Path (Split-Path $registryFile -Parent) -Force | Out-Null
}
if (-not (Test-Path $registryFile)) {
    '{}' | Set-Content $registryFile -Encoding UTF8
}

# Register shiv in its own registry
$registry = Get-Content $registryFile | ConvertFrom-Json
$registry | Add-Member -NotePropertyName 'shiv' -NotePropertyValue $ShivInstallPath -Force
$registry | ConvertTo-Json | Set-Content $registryFile -Encoding UTF8

Chicle-Log --success "shiv shim created at $shimPs1"

# Add bin dir to user PATH if not present
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
if ($userPath -notlike "*$ShivBinDir*") {
    [Environment]::SetEnvironmentVariable('PATH', "$ShivBinDir;$userPath", 'User')
    $env:PATH = "$ShivBinDir;$env:PATH"
    Chicle-Log --success "Added $ShivBinDir to user PATH"
}

# Configure PowerShell profile
$evalLine = "Invoke-Expression (mise -C '$ShivInstallPath' run -q shell 2>`$null)"
$profilePath = $PROFILE.CurrentUserCurrentHost
$alreadyConfigured = $false

if ((Test-Path $profilePath) -and (Select-String -Path $profilePath -Pattern 'shiv' -Quiet -ErrorAction SilentlyContinue)) {
    $alreadyConfigured = $true
    Chicle-Log --success "Profile already configured ($profilePath)"
}

if (-not $alreadyConfigured) {
    $addProfile = {
        $profileDir = Split-Path $profilePath -Parent
        if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null }
        Add-Content -Path $profilePath -Value "`n# shiv - managed tool shims"
        Add-Content -Path $profilePath -Value $evalLine
        Chicle-Log --success "Added to $profilePath"
    }

    if (Test-Interactive) {
        Write-Host ''
        if (Chicle-Confirm "Add shiv to $profilePath?" -Default 'yes') {
            & $addProfile
        } else {
            Chicle-Log --warn 'Skipped - add manually:'
            Chicle-Log --info "  $evalLine"
        }
    } else {
        & $addProfile
    }
}
Write-Host ''

# --- Step 6: Verify ---
Chicle-Steps -Current 6 -Total $TotalSteps -Title 'Verifying installation' -Style dots

$env:PATH = "$ShivBinDir;$env:PATH"

try {
    & (Join-Path $ShivBinDir 'shiv.ps1') list 2>$null | Out-Null
    Chicle-Log --success 'shiv is working'
} catch {
    Chicle-Log --warn 'shiv installed but verification failed - check your PATH'
}

Write-Host ''
Chicle-Rule
Write-Host (Chicle-Style -Bold -Green 'Installation complete!')
Chicle-Rule
Write-Host ''
Chicle-Log --info "Installed to: $ShivInstallPath"
Chicle-Log --info "Shim at: $shimPs1"
Chicle-Log --info "Config at: $ShivConfigDir\"
Write-Host ''
Chicle-Log --step 'Next steps:'
Write-Host "  1. Restart your shell (or run: . `$PROFILE)"
Write-Host '  2. Try: shiv list'
Write-Host '  3. Install a tool: shiv install shimmer'
Write-Host ''
