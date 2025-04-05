<#
	.SYNOPSIS
		Locates, compiles if necessary, and loads a compiled PowerShell module.

	.DESCRIPTION
		This PowerShell script is designed to locate and load a compiled module.
		If the module is not found, it attempts to compile it using the .NET CLI and then load it.
		The script ensures that the correct version of the module is available for use,
		focusing on modules with the '.Verbs.dll' pattern in their filename. It handles
		various edge cases such as already-loaded assemblies and provides appropriate error handling.

	.PARAMETER Force
		When specified, forces re-compilation of the module even if it already exists.

	.EXAMPLE
		.\this-initialize-environment.ps1
		Locates and loads the module, compiling it only if not found.

	.EXAMPLE
		.\this-initialize-environment.ps1 -Force
		Forces re-compilation of the module before loading it, regardless of whether it exists.
#>

param
(
	# Optional: If specified, forces re-compilation of the module even if it exists.
	[Parameter(Mandatory=$false)]
	[switch] $Force
)

<# -----------------------------------------------------------------
DEFAULTS                                                           |
----------------------------------------------------------------- #>

# This script path.
$this = (Split-Path -Parent ($MyInvocation.MyCommand.Path))

<# -----------------------------------------------------------------
MAIN                                                               |
----------------------------------------------------------------- #>

# Navigate to the root directory containing the module.
$dirInfo = Get-Item -Path ("{0}/../../" -f $this)

# Ensure it is really module directory.
$solutionFile = Resolve-Path ("{0}/{1}.sln" -f $dirInfo.FullName, $dirInfo.Name) -ErrorAction SilentlyContinue -ErrorVariable resolveErr
if (-not($solutionFile)) { $solutionFile = $resolveErr[0].TargetObject }

if (Test-Path -Path $solutionFile -PathType Leaf)
{
	# Define module file filter pattern.
	$fileFilter = '*.Verbs.dll' #("{0}.Verbs.dll" -f $dirInfo.Name)

	# Search for the compiled module files.
	$files = Get-ChildItem -Path $dirInfo.FullName -Recurse -File -Filter $fileFilter

	# If no module is found or force recompilation is requested, compile the module.
	if ($files.Count -lt 1 -or $Force)
	{
		# If we didn't found module, we need to compile it first
		Write-Host '-- Compiling module: ' -NoNewline        
		Write-Host ($dirInfo.Name) -ForegroundColor Cyan
				
		# Compile the module using .NET.
		& dotnet build $dirInfo.FullName --configuration Release  
	
		# Search again after compilation.
		$files = Get-ChildItem -Path $dirInfo.FullName -Recurse -File -Filter $fileFilter			
	}
	
	# Filter and load only modules from the release bin directory.
	$files | 
	ForEach-Object {
		if ($_.FullName.Contains('Release') -and $_.FullName.Contains('bin')) 
		{
			# Ensure the module is not already loaded.
			try 
			{ if (-not (Get-Module $_.Name)) { Import-Module -Name $_.FullName -DisableNameChecking } }
			catch [System.Exception]
			{
				# That version is for cases when we look for PWSH modules availability in SDK below 7.0
				if ($_.GetType() -eq [System.Management.Automation.ErrorRecord]) 
				{ 
					if ($_.Exception.Message -ne "Assembly with same name is already loaded") 
					{
						Write-Host "Unhandled response to this exception type: " -ForegroundColor Red	
						Write-Host ("[{0}]" -f $_.Exception.Message)	
					}
				}
				else 
				{
					Write-Host "Unhandled exception type: " -ForegroundColor Red	
					Write-Host ("[{0}]" -f $_.Exception.Message)
				}
			}
		}
	}
}