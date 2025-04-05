<#
	.SYNOPSIS
		Validates environment configurations by executing a series of test tasks.

	.DESCRIPTION
		This PowerShell script is designed to validate and execute a set of environment tests.
		It processes a JSON input containing test tasks, attempts to execute them, and handles
		failures gracefully. The script supports custom test configurations passed as JSON,
		provides detailed error handling for different exception types, and returns comprehensive
		results about test execution status.

	.PARAMETER CustomSettings
		A JSON string containing custom settings that will override the default settings file.
		Each test in the JSON should include a TASK_NAME and EXPRESSION object with TRY and CATCH commands.

	.PARAMETER CleanConsole
		When specified, clears the console before executing the script.

	.EXAMPLE
		.\test-environment.ps1 -CustomSettings $jsonConfig
		Runs environment tests using the specified JSON configuration.

	.EXAMPLE
		.\test-environment.ps1 -CustomSettings $jsonConfig -CleanConsole
		Clears the console and runs environment tests using the specified JSON configuration.

	.INPUTS
		System.String. You can pipe a JSON string to this script.

	.OUTPUTS
		PSObject. Returns an object with IsValid (boolean) and TestResult (hashtable) properties.
#>

param
(
	# Optional: JSON string containing custom settings to override the default settings file.
	[Parameter(Mandatory=$false, HelpMessage="Pass custom settings that will override settings file")]
	[System.String] $CustomSettings,

	# Optional: If specified, clears the console before running the script.
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

# Try to parse the JSON input.
try { $settingsJSON = ConvertFrom-Json -InputObject $CustomSettings }
catch [System.Exception]
{
	Write-Host $_.Exception.Message
	return
}

# Start testing environment setup.
Write-Host "-- Testing environment"
$envTests = @{}
$isValid = $true

# Loop through JSON object containing test tasks https://stackoverflow.com/questions/33520699/iterating-through-a-json-file-powershell
for ( $index = 0; $index -lt $settingsJSON.count; $index++)
{
	# Display task name without a newline to append success/failure message.
	Write-Host $settingsJSON[$index].TASK_NAME -NoNewline

	try
	{ 
		# Try executing the test command defined in JSON.
		Invoke-Expression -Command $settingsJSON[$index].EXPRESSION.TRY
		$envTests[$settingsJSON[$index].TASK_NAME] = $true  
	}
	catch [System.Management.Automation.CommandNotFoundException]
	{
		# Handle missing command errors.
		Write-Host ""
		Invoke-Expression -Command $settingsJSON[$index].EXPRESSION.CATCH
		$isValid = $false 
		$envTests[$settingsJSON[$index].TASK_NAME] = $isValid 
	}
	catch [System.Exception]
	{
		# General exception handling.
		Write-Host ""
			
		if ($_.GetType() -eq [System.Management.Automation.ErrorRecord]) 
		{ 
			# Handle specific missing file or directory cases.
			if (($_.Exception.GetType() -eq [System.IO.DirectoryNotFoundException]) -or ($_.Exception.Message -eq 'System.IO.DirectoryNotFoundException')) { Invoke-Expression -Command $settingsJSON[$index].EXPRESSION.CATCH }
			elseif (($_.Exception.GetType() -eq [System.IO.FileNotFoundException]) -or ($_.Exception.Message -eq 'System.IO.FileNotFoundException')) { Invoke-Expression -Command $settingsJSON[$index].EXPRESSION.CATCH }

			# Handle missing PowerShell module cases.
			elseif (($_.Exception.GetType() -eq [System.Management.Automation.ItemNotFoundException]) -or ($_.Exception.Message -eq 'System.Management.Automation.ItemNotFoundException')) { Invoke-Expression -Command $settingsJSON[$index].EXPRESSION.CATCH }
			else
			{
				# If no specific handler exists, output error type and message.
				Write-Host "There is no TRY response for this exception type: " -ForegroundColor Red	
				Write-Host ("[{0}]/[{1}]" -f $_.Exception.GetType().ToString(), $_.Exception.Message)	
			}
		}
		else 
		{
			# General error handler for unknown exception types.
			Write-Host "There is no TRY response for this exception type: " -ForegroundColor Red	
			Write-Host ("[{0}]/[{1}]" -f $_.Exception.GetType().ToString(), $_.Exception.Message)	
		}

		$isValid = $false 
		$envTests[$settingsJSON[$index].TASK_NAME] = $isValid 
	}

	# Print success message in green if test passes.
	if ($envTests[$settingsJSON[$index].TASK_NAME] -eq $true) { Write-Host " OK" -ForegroundColor Green }
}

# Return an object containing the overall validation status and test results.
return New-Object -TypeName PSObject -Property @{IsValid=$isValid; TestResult=$envTests}