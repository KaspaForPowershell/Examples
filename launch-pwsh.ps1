<#
	.SYNOPSIS
		Ensures required files and settings exist before executing an environment setup.

	.DESCRIPTION
		This PowerShell script validates the presence of required configuration files,
		executes environment tests to ensure system compatibility, and initializes
		the environment by launching a new PowerShell session with appropriate settings.
		It provides a foundation for consistent environment setup across different systems.

	.PARAMETER None
		This script does not accept parameters directly but reads settings from an external JSON file.
	#>

<# -----------------------------------------------------------------
DEFAULTS                                                           |
----------------------------------------------------------------- #>

# This script path.
$this = (Split-Path -Parent ($MyInvocation.MyCommand.Path))

<# -----------------------------------------------------------------
MAIN                                                               |
----------------------------------------------------------------- #>

Write-Host "-- Looking for required files"
$canContinue = $true

# Locate settings file.
$settingsPath = Resolve-Path ("{0}/{1}.settings" -f $this, ($MyInvocation.MyCommand.Name).Split('.')[0]) -ErrorAction SilentlyContinue -ErrorVariable resolveErr
if (-not($settingsPath)) { $settingsPath = $resolveErr[0].TargetObject }

Write-Host $settingsPath -NoNewline
if (Test-Path -Path $settingsPath -PathType Leaf) 
{
	Write-Host " Found" -ForegroundColor Green
	$settingsContent = Get-Content -Path $settingsPath -Raw
	$settingsJSON = ConvertFrom-Json $settingsContent
}
else 
{ 
	Write-Host " Not Found" -ForegroundColor Red
	$canContinue = $false 
}

# Locate environment testing script.
$envTestFile = Resolve-Path ("{0}/.custom/Scripts/test-environment.ps1" -f $this) -ErrorAction SilentlyContinue -ErrorVariable resolveErr
if (-not($envTestFile)) { $envTestFile = $resolveErr[0].TargetObject }

Write-Host $envTestFile -NoNewline
if (Test-Path -Path $envTestFile -PathType Leaf) { Write-Host " Found" -ForegroundColor Green }
else 
{
	Write-Host " Not Found" -ForegroundColor Red
	$canContinue = $false 
}

# Stop execution if required files are missing.
if (-not $canContinue) 
{ 
	Write-Host "Missing required files. Press any key to continue ..." -NoNewline -ForegroundColor Yellow
	$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
	return 
}

# Run environment test script.
$envTestResult = & $envTestFile -CustomSettings (ConvertTo-Json $settingsJSON.ENVIRONMENT_TESTS)
if (-not ($envTestResult.IsValid)) 
{
	Write-Host "Environmnet testing failure. Press any key to continue ..." -NoNewline -ForegroundColor Yellow
	$host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
	return 
}

# Ensure custom work directory exists.
$workDir = Resolve-Path ("{0}/{1}" -f $this, $settingsJSON.WORK_DIRECTORY) -ErrorAction SilentlyContinue -ErrorVariable resolveErr
if (-not($workDir)) { $workDir = $resolveErr[0].TargetObject }

if (-not (Test-Path -Path $workDir -PathType Container)) { $workDir = $this }

# Get environment initialization script.
$scriptsPath = Resolve-Path ("{0}/.custom/Scripts/" -f $this) -ErrorAction SilentlyContinue -ErrorVariable resolveErr
if (-not($scriptsPath)) { $scriptsPath = $resolveErr[0].TargetObject }

$pwshCommand = ""

Get-ChildItem -Path $scriptsPath | ForEach-Object {

	if ($_.Name.Contains("this-initialize-environment.ps1")) 
	{ $pwshCommand = "& {0} -Force" -f $_.Fullname }
	elseif ($_.Name.Contains("initialize-environment.ps1")) 
	{ $pwshCommand = "& {0}" -f $_.Fullname }
}

# Start PowerShell with the correct working directory and initialization script.
if ($pwshCommand.Length -le 0)
{ & pwsh -WorkingDirectory $workDir }
else
{ & pwsh -WorkingDirectory $workDir -NoExit -Command $pwshCommand }