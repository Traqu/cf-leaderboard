[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$ServiceDisplayName = "CF Leaderboard Discord Bot"
$ServiceName = "CFLeaderboard"
$InstallDirectory = Join-Path $env:ProgramFiles "CF Leaderboard"
$ScriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$TargetExecutable = Join-Path $InstallDirectory "cf-leaderboard.exe"
$LogDirectory = Join-Path $InstallDirectory "logs"
$LogFile = Join-Path $LogDirectory "logger.log"

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)

    Write-Host ""
    Write-Host ("=" * 68) -ForegroundColor DarkCyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ("=" * 68) -ForegroundColor DarkCyan
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertFrom-SecureValue {
    param([Parameter(Mandatory)][Security.SecureString]$Value)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Read-ValidatedValue {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][scriptblock]$Validator,
        [string]$Default,
        [string]$ErrorMessage = "The entered value is invalid.",
        [switch]$Secret
    )

    while ($true) {
        $displayPrompt = if ($PSBoundParameters.ContainsKey("Default")) {
            if ([string]::IsNullOrEmpty($Default)) {
                "$Prompt (press Enter to leave empty)"
            }
            else {
                "$Prompt (press Enter for default: $Default)"
            }
        }
        else {
            $Prompt
        }

        if ($Secret) {
            $secureValue = Read-Host $displayPrompt -AsSecureString
            $value = ConvertFrom-SecureValue $secureValue
        }
        else {
            $value = Read-Host $displayPrompt
        }

        if ([string]::IsNullOrEmpty($value) -and $PSBoundParameters.ContainsKey("Default")) {
            $value = $Default
        }

        if (& $Validator $value) {
            return $value
        }

        Write-Host $ErrorMessage -ForegroundColor Yellow
    }
}

function Read-MenuValue {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][string[]]$Choices,
        [Parameter(Mandatory)][string]$Default,
        [switch]$AllowCustom,
        [scriptblock]$CustomValidator,
        [string]$CustomHint,
        [string]$CustomErrorMessage = "The custom value is invalid."
    )

    while ($true) {
        Write-Host ""
        Write-Host $Prompt -ForegroundColor Cyan
        for ($index = 0; $index -lt $Choices.Count; $index++) {
            $marker = if ($Choices[$index] -eq $Default) { " (default)" } else { "" }
            Write-Host ("  {0}. {1}{2}" -f ($index + 1), $Choices[$index], $marker)
        }
        if ($AllowCustom) {
            Write-Host ("  {0}. Custom value" -f ($Choices.Count + 1))
            if (-not [string]::IsNullOrWhiteSpace($CustomHint)) {
                Write-Host "     $CustomHint" -ForegroundColor DarkGray
            }
        }

        Write-Host "Enter an option number without the dot, or enter the option text." -ForegroundColor DarkGray
        $selection = Read-Host "Selection (press Enter for default: $Default)"
        if ([string]::IsNullOrWhiteSpace($selection)) {
            return $Default
        }

        $number = 0
        if ([int]::TryParse($selection, [ref]$number)) {
            if ($number -ge 1 -and $number -le $Choices.Count) {
                return $Choices[$number - 1]
            }
            if ($AllowCustom -and $number -eq ($Choices.Count + 1)) {
                return Read-ValidatedValue `
                    -Prompt "Enter the custom value" `
                    -Validator $CustomValidator `
                    -ErrorMessage $CustomErrorMessage
            }
        }

        $matchingChoice = $Choices | Where-Object { $_ -ieq $selection } | Select-Object -First 1
        if ($null -ne $matchingChoice) {
            return $matchingChoice
        }

        if ($AllowCustom -and (& $CustomValidator $selection)) {
            return $selection
        }

        Write-Host "Select one of the listed options." -ForegroundColor Yellow
    }
}

function Resolve-Nssm {
    $command = Get-Command nssm.exe -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\nssm.exe"),
        (Join-Path $env:ProgramFiles "WinGet\Links\nssm.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "WinGet\Links\nssm.exe")
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            return $candidate
        }
    }

    $packageRoots = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"),
        (Join-Path $env:ProgramFiles "WinGet\Packages")
    )
    foreach ($root in $packageRoots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) {
            continue
        }
        $match = Get-ChildItem -LiteralPath $root -Recurse -Filter nssm.exe -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($null -ne $match) {
            return $match.FullName
        }
    }

    return $null
}

function Install-Nssm {
    $nssm = Resolve-Nssm
    if ($null -ne $nssm) {
        Write-Host "NSSM found: $nssm" -ForegroundColor Green
        return $nssm
    }

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw "winget.exe was not found. Install Microsoft App Installer and run this script again."
    }

    Write-Host "Installing NSSM with winget..." -ForegroundColor Cyan
    & $winget.Source install `
        --id NSSM.NSSM `
        --exact `
        --accept-package-agreements `
        --accept-source-agreements `
        --silent
    if ($LASTEXITCODE -ne 0) {
        throw "winget failed to install NSSM. Exit code: $LASTEXITCODE"
    }

    $nssm = Resolve-Nssm
    if ($null -eq $nssm) {
        throw "NSSM was installed, but nssm.exe could not be located."
    }

    Write-Host "NSSM installed: $nssm" -ForegroundColor Green
    return $nssm
}

function Find-SourceExecutable {
    $parentDirectory = Split-Path -Parent $ScriptDirectory
    $candidates = @(
        (Join-Path $ScriptDirectory "cf-leaderboard.exe"),
        (Join-Path $ScriptDirectory "dist\cf-leaderboard.exe"),
        (Join-Path $parentDirectory "cf-leaderboard.exe"),
        (Join-Path $parentDirectory "dist\cf-leaderboard.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    $match = Get-ChildItem -LiteralPath $ScriptDirectory -Recurse -Depth 2 `
        -Filter "cf-leaderboard.exe" -File -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -ne $match) {
        return $match.FullName
    }

    Write-Host "cf-leaderboard.exe was not found next to the installer." -ForegroundColor Yellow
    Write-Host "Select the downloaded executable in the file picker."

    Add-Type -AssemblyName System.Windows.Forms
    $dialog = [System.Windows.Forms.OpenFileDialog]::new()
    $dialog.Title = "Select cf-leaderboard.exe"
    $dialog.Filter = "CF Leaderboard executable (cf-leaderboard.exe)|cf-leaderboard.exe|Executable files (*.exe)|*.exe"
    $dialog.CheckFileExists = $true
    $dialog.Multiselect = $false
    $downloadsDirectory = Join-Path ([Environment]::GetFolderPath("UserProfile")) "Downloads"
    $dialog.InitialDirectory = if (Test-Path -LiteralPath $downloadsDirectory) {
        $downloadsDirectory
    }
    else {
        [Environment]::GetFolderPath("UserProfile")
    }

    try {
        if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
            throw "No executable was selected. Installation cancelled."
        }
        return (Resolve-Path -LiteralPath $dialog.FileName).Path
    }
    finally {
        $dialog.Dispose()
    }
}

function Test-OptionalDiscordId {
    param([string]$Value)
    return [string]::IsNullOrWhiteSpace($Value) -or $Value -match "^\d{17,20}$"
}

function Test-EmbedColor {
    param([string]$Value)

    if ($Value -match "^#[0-9a-fA-F]{6}$") {
        return $true
    }

    $parts = $Value -split ","
    if ($parts.Count -ne 3) {
        return $false
    }
    foreach ($part in $parts) {
        $channel = 0
        if (-not [int]::TryParse($part.Trim(), [ref]$channel) -or $channel -lt 0 -or $channel -gt 255) {
            return $false
        }
    }
    return $true
}

function Invoke-Nssm {
    param(
        [Parameter(Mandatory)][string]$Nssm,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    & $Nssm @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "NSSM command failed: nssm $($Arguments -join ' ')"
    }
}

function Wait-ServiceStatus {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][System.ServiceProcess.ServiceControllerStatus]$ExpectedStatus,
        [int]$TimeoutSeconds = 30
    )

    $service = Get-Service -Name $Name
    try {
        $service.WaitForStatus($ExpectedStatus, [TimeSpan]::FromSeconds($TimeoutSeconds))
    }
    catch [System.ServiceProcess.TimeoutException] {
        $service.Refresh()
        return $service.Status -eq $ExpectedStatus
    }
    $service.Refresh()
    return $service.Status -eq $ExpectedStatus
}

function Show-ServiceFailureDetails {
    param([Parameter(Mandatory)][string]$Name)

    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -ne $service) {
        Write-Host "Current service status: $($service.Status)" -ForegroundColor Yellow
    }

    if (Test-Path -LiteralPath $LogFile -PathType Leaf) {
        Write-Host ""
        Write-Host "Complete log: $LogFile" -ForegroundColor Yellow
        Get-Content -LiteralPath $LogFile -ErrorAction SilentlyContinue
    }
}

function Find-ExistingBotService {
    $services = Get-CimInstance Win32_Service |
        Where-Object {
            $_.Name -eq $ServiceName -or
            $_.DisplayName -eq $ServiceDisplayName
        }

    if (@($services).Count -gt 1) {
        $names = ($services | Select-Object -ExpandProperty Name) -join ", "
        throw "Multiple CF Leaderboard services were found: $names. Remove the duplicate services before continuing."
    }

    return $services | Select-Object -First 1
}

if (-not (Test-IsAdministrator)) {
    throw "This script must be run as Administrator. Use install-service.bat."
}

Write-Section "CF Leaderboard Windows Service Installer"
Write-Host "This installer will configure the bot as an automatically started Windows service."
Write-Host "Secrets are hidden while entered, but Windows must store them for the service account."

Write-Section "NSSM"
$nssmPath = Install-Nssm

Write-Section "Application"
$sourceExecutable = Find-SourceExecutable
Write-Host "Source executable:      $sourceExecutable" -ForegroundColor Green
Write-Host "Installation directory: $InstallDirectory"

$existingServiceDefinition = Find-ExistingBotService
if ($null -ne $existingServiceDefinition) {
    if ($existingServiceDefinition.PathName -notmatch "(?i)nssm(\.exe)?") {
        throw "Service '$($existingServiceDefinition.Name)' already exists but is not managed by NSSM."
    }
    $ServiceName = $existingServiceDefinition.Name
    Write-Host "Existing service found: $ServiceName" -ForegroundColor Green
    Write-Host "The installer will update its executable, environment, and NSSM settings."
}
else {
    Write-Host "No existing service found. A new service will be created."
    Write-Host "Windows service name:   $ServiceName"
}

Write-Section "Required Discord configuration"
$discordToken = Read-ValidatedValue `
    -Prompt "Discord application token" `
    -Secret `
    -Validator { param($value) -not [string]::IsNullOrWhiteSpace($value) } `
    -ErrorMessage "The Discord application token is required."

Write-Section "Required CFTools configuration"
$cftoolsApplicationId = Read-ValidatedValue `
    -Prompt "CFTools application ID" `
    -Validator { param($value) $value -match "^[0-9a-fA-F]{24}$" } `
    -ErrorMessage "The CFTools application ID must contain exactly 24 hexadecimal characters."

$cftoolsApplicationSecret = Read-ValidatedValue `
    -Prompt "CFTools application secret" `
    -Secret `
    -Validator { param($value) -not [string]::IsNullOrWhiteSpace($value) } `
    -ErrorMessage "The CFTools application secret is required."

$cftoolsServerApiId = Read-ValidatedValue `
    -Prompt "CFTools Server API ID" `
    -Validator {
        param($value)
        $parsed = [Guid]::Empty
        [Guid]::TryParseExact($value, "D", [ref]$parsed)
    } `
    -ErrorMessage "Use the UUID shown in CFTools Cloud -> server -> API Key -> Server ID."

Write-Section "Discord behavior"
$discordGuildId = Read-ValidatedValue `
    -Prompt "Discord guild ID" `
    -Default "" `
    -Validator { param($value) Test-OptionalDiscordId $value } `
    -ErrorMessage "Use a 17-20 digit Discord guild ID or leave it empty."

$discordChannelId = Read-ValidatedValue `
    -Prompt "Discord channel ID; leave empty to allow every channel" `
    -Default "" `
    -Validator { param($value) Test-OptionalDiscordId $value } `
    -ErrorMessage "Use a 17-20 digit Discord channel ID or leave it empty."

$usageLogging = Read-MenuValue `
    -Prompt "Log every received slash command?" `
    -Choices @("true", "false") `
    -Default "true"

$localizationEnabled = Read-MenuValue `
    -Prompt "Enable Discord localization?" `
    -Choices @("true", "false") `
    -Default "true"

$responseVisibility = Read-MenuValue `
    -Prompt "Select leaderboard response visibility" `
    -Choices @("ephemeral", "public") `
    -Default "ephemeral"

$leaderboardLimit = Read-ValidatedValue `
    -Prompt "Number of leaderboard entries" `
    -Default "10" `
    -Validator {
        param($value)
        $number = 0
        [int]::TryParse($value, [ref]$number) -and $number -ge 1 -and $number -le 100
    } `
    -ErrorMessage "Enter an integer between 1 and 100."

$playerNameMaxLength = Read-ValidatedValue `
    -Prompt "Maximum displayed player-name length" `
    -Default "24" `
    -Validator {
        param($value)
        $number = 0
        [int]::TryParse($value, [ref]$number) -and $number -ge 4 -and $number -le 100
    } `
    -ErrorMessage "Enter an integer between 4 and 100."

$kdFormat = Read-MenuValue `
    -Prompt "Select the K/D display format" `
    -Choices @("float", "k/d", "k:d") `
    -Default "float"

$predefinedColors = @(
    "black",
    "blue",
    "red",
    "green",
    "orange",
    "yellow",
    "purple",
    "pink",
    "gray",
    "grey",
    "white"
)
$embedColor = Read-MenuValue `
    -Prompt "Select the Discord embed color" `
    -Choices $predefinedColors `
    -Default "black" `
    -AllowCustom `
    -CustomValidator { param($value) Test-EmbedColor $value } `
    -CustomHint "Accepted formats: #RRGGBB, for example #2F80ED; or R,G,B, for example 47,128,237." `
    -CustomErrorMessage "Use #RRGGBB or R,G,B with every channel between 0 and 255."

Write-Section "Installation summary"
Write-Host "Service name:         $ServiceName"
Write-Host "Source executable:    $sourceExecutable"
Write-Host "Installation folder:  $InstallDirectory"
Write-Host "Executable:           $TargetExecutable"
Write-Host "Log file:             $LogFile"
Write-Host "Discord guild ID:     $(if ($discordGuildId) { $discordGuildId } else { '<global command>' })"
Write-Host "Discord channel ID:   $(if ($discordChannelId) { $discordChannelId } else { '<all channels>' })"
Write-Host "Response visibility:  $responseVisibility"
Write-Host "Leaderboard limit:    $leaderboardLimit"
Write-Host "Player name limit:    $playerNameMaxLength"
Write-Host "K/D format:           $kdFormat"
Write-Host "Embed color:          $embedColor"
Write-Host "Localization:         $localizationEnabled"
Write-Host "Command usage logs:   $usageLogging"
Write-Host "Secret values:        <hidden>"

$confirmation = Read-Host "Continue with service installation? [Y/n]"
if ($confirmation -and $confirmation -notmatch "^(?i:y|yes)$") {
    Write-Host "Installation cancelled."
    exit 0
}

Write-Section "Installing service"
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($null -ne $existingService) {
    $replace = Read-Host "Service '$ServiceName' already exists. Update it? [Y/n]"
    if ($replace -and $replace -notmatch "^(?i:y|yes)$") {
        Write-Host "Installation cancelled."
        exit 0
    }
    if ($existingService.Status -ne "Stopped") {
        Write-Host "Stopping existing service..."
        Stop-Service -Name $ServiceName -Force
        if (-not (Wait-ServiceStatus -Name $ServiceName -ExpectedStatus Stopped)) {
            throw "Service '$ServiceName' did not stop within 30 seconds."
        }
    }
}

New-Item -ItemType Directory -Path $InstallDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
Get-ChildItem -LiteralPath $LogDirectory -Filter "*.log" -File -ErrorAction SilentlyContinue |
    Remove-Item -Force

$sourceFullPath = [IO.Path]::GetFullPath($sourceExecutable)
$targetFullPath = [IO.Path]::GetFullPath($TargetExecutable)
if ($sourceFullPath -ine $targetFullPath) {
    Copy-Item -LiteralPath $sourceFullPath -Destination $targetFullPath -Force
}

if ($null -eq $existingService) {
    Invoke-Nssm -Nssm $nssmPath -Arguments @("install", $ServiceName, $TargetExecutable)
}

Invoke-Nssm -Nssm $nssmPath -Arguments @("set", $ServiceName, "Application", $TargetExecutable)
Invoke-Nssm -Nssm $nssmPath -Arguments @("set", $ServiceName, "AppDirectory", $InstallDirectory)
Invoke-Nssm -Nssm $nssmPath -Arguments @("set", $ServiceName, "DisplayName", $ServiceDisplayName)
Invoke-Nssm -Nssm $nssmPath -Arguments @(
    "set",
    $ServiceName,
    "Description",
    "Discord bot that publishes a CFTools Cloud leaderboard."
)
Invoke-Nssm -Nssm $nssmPath -Arguments @("set", $ServiceName, "Start", "SERVICE_AUTO_START")
Invoke-Nssm -Nssm $nssmPath -Arguments @("set", $ServiceName, "AppExit", "Default", "Restart")
Invoke-Nssm -Nssm $nssmPath -Arguments @("set", $ServiceName, "AppRestartDelay", "5000")
Invoke-Nssm -Nssm $nssmPath -Arguments @("set", $ServiceName, "AppStdout", $LogFile)
Invoke-Nssm -Nssm $nssmPath -Arguments @("set", $ServiceName, "AppStderr", $LogFile)
Invoke-Nssm -Nssm $nssmPath -Arguments @("set", $ServiceName, "AppStdoutCreationDisposition", "4")
Invoke-Nssm -Nssm $nssmPath -Arguments @("set", $ServiceName, "AppStderrCreationDisposition", "4")
Invoke-Nssm -Nssm $nssmPath -Arguments @("set", $ServiceName, "AppRotateFiles", "0")
Invoke-Nssm -Nssm $nssmPath -Arguments @("set", $ServiceName, "AppRotateOnline", "0")

$environmentEntries = @(
    "DISCORD_APPLICATION_TOKEN=$discordToken",
    "DISCORD_GUILD_ID=$discordGuildId",
    "DISCORD_CHANNEL_ID=$discordChannelId",
    "DISCORD_COMMAND_USAGE_LOGGING_ENABLED=$usageLogging",
    "DISCORD_LOCALIZATION_ENABLED=$localizationEnabled",
    "DISCORD_RESPONSE_VISIBILITY=$responseVisibility",
    "DISCORD_LEADERBOARD_LIMIT=$leaderboardLimit",
    "DISCORD_PLAYER_NAME_MAX_LENGTH=$playerNameMaxLength",
    "DISCORD_KD_FORMAT=$kdFormat",
    "DISCORD_EMBED_COLOR=$embedColor",
    "CFTOOLS_APPLICATION_ID=$cftoolsApplicationId",
    "CFTOOLS_APPLICATION_SECRET=$cftoolsApplicationSecret",
    "CFTOOLS_SERVER_API_ID=$cftoolsServerApiId"
)
Invoke-Nssm -Nssm $nssmPath -Arguments (@("set", $ServiceName, "AppEnvironmentExtra") + $environmentEntries)

Write-Host "Starting service and waiting for it to become ready..."
try {
    Start-Service -Name $ServiceName
}
catch {
    Write-Host "Windows rejected the service start request: $($_.Exception.Message)" -ForegroundColor Red
    Show-ServiceFailureDetails -Name $ServiceName
    exit 1
}
if (-not (Wait-ServiceStatus -Name $ServiceName -ExpectedStatus Running)) {
    Write-Host "The service did not reach the Running state within 30 seconds." -ForegroundColor Red
    Show-ServiceFailureDetails -Name $ServiceName
    Write-Host ""
    Write-Host "Log: $LogFile"
    exit 1
}

Write-Section "Installation complete"
Write-Host "Service '$ServiceName' is running." -ForegroundColor Green
Write-Host "Executable: $TargetExecutable"
Write-Host "Log:        $LogFile"
Write-Host ""
Write-Host "Useful commands:"
Write-Host "  Get-Service -Name '$ServiceName'"
Write-Host "  Restart-Service -Name '$ServiceName'"
Write-Host "  Stop-Service -Name '$ServiceName'"
