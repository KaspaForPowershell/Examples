<#
.SYNOPSIS
	Synchronizes a Git repository and its submodules with remote sources.

.DESCRIPTION
	This PowerShell script performs a complete synchronization of a Git repository,
	including resetting to the remote branch, cleaning untracked files, and updating
	all submodules. The script performs environment checks before proceeding with any
	Git operations to ensure system compatibility. It provides a consistent method
	for ensuring repositories are in sync with their remote sources across different
	environments.

.PARAMETER CleanConsole
	When specified, clears the console before executing the script.

.EXAMPLE
	.\synchronize-repo.ps1
	Synchronizes the Git repository without clearing the console.

.EXAMPLE
	.\synchronize-repo.ps1 -CleanConsole
	Clears the console before synchronizing the Git repository.
#>

param
(
	[Parameter(Mandatory=$false)]
	[switch] $CleanConsole
)

<# -----------------------------------------------------------------
DEFAULTS                                                           |
----------------------------------------------------------------- #>

# Clear console if the CleanConsole switch is provided.
if ($CleanConsole.IsPresent) { Clear-Host }

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
	Write-Host "Operation aborted"
	return 
}

# Execute environment test script.
$envTestResult = & $envTestFile -CustomSettings (ConvertTo-Json $settingsJSON.ENVIRONMENT_TESTS)
if (-not ($envTestResult.IsValid)) { return }

# Execute GIT commands.
Write-Host '-- Synchronizing repository: ' -NoNewline
Write-Host $this -ForegroundColor Cyan
Set-Location -Path $this

# Reset the main repository.
Write-Host 'Reseting main repo...' -ForegroundColor Yellow
& git reset --hard

# Clean the repository (remove untracked files and directories).
Write-Host 'Cleaning main repo...' -ForegroundColor Yellow
& git clean -f -f -d -x

# Fetch latest changes from the remote repository.
Write-Host 'Pulling latest main repo changes...' -ForegroundColor Yellow
& git fetch origin

# Reset local branch to match the remote.
$command = "git reset --hard origin/{0}" -f $settingsJSON.ACTIVE_MAIN_BRANCH
Invoke-Expression -Command $command

# Should we get submodules?
if ($settingsJSON.SKIP_SUBMODULES -eq $true) { return }

# Synchronize and update Git submodules.
Write-Host 'Syncing submodules...' -ForegroundColor Yellow
& git submodule sync

# Reset all submodules to the last committed state.
Write-Host 'Reseting submodules...' -ForegroundColor Yellow
& git submodule foreach --recursive git reset --hard

# Remove untracked files and directories from submodules.
Write-Host 'Cleaning submodules...' -ForegroundColor Yellow
& git submodule foreach --recursive git clean -f -f -d -x

# Fetch and update submodules.
Write-Host 'Pulling latest submodules changes...' -ForegroundColor Yellow
& git submodule update --init --recursive --remote