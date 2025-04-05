<#  
    .SYNOPSIS
        Validates one or more Kaspa blockchain transaction IDs.
    
    .DESCRIPTION
        This script validates the format and structure of one or more Kaspa transaction IDs.
        It leverages the PWSH.Kaspa module's validation attribute to ensure each provided
        transaction ID conforms to the Kaspa blockchain's specifications.
        
        When executed, the script will:
        1. Validate each transaction ID in the provided array
        2. Output a confirmation message if all transaction IDs pass validation
        3. Throw an error if any transaction ID fails validation
        
        The validation includes checking:
        - Transaction ID string length (should be 64 hexadecimal characters)
        - Valid hexadecimal character set (0-9, a-f)
        - Proper format according to Kaspa transaction ID standards
    
    .PARAMETER TransactionID
        An array of one or more Kaspa transaction IDs to validate. This parameter is mandatory and 
        must be provided as a string array. If any transaction ID in the array fails validation,
        the script will throw an error through the validation attribute.
        
        Example: `-TransactionID '82f5ea544f45681be9176672d6c6c35748c614d68c11879f78d9c84c22cd4121'`
    
    .EXAMPLE
        .\validate-transaction-id.ps1 -TransactionID '82f5ea544f45681be9176672d6c6c35748c614d68c11879f78d9c84c22cd4121'
        
        Validates a single Kaspa transaction ID and outputs "OK" in green text if successful.
    
    .EXAMPLE
        .\validate-transaction-id.ps1 -TransactionID '82f5ea544f45681be9176672d6c6c35748c614d68c11879f78d9c84c22cd4121', 'f1a24c6b42aede5e89b9ec9310c24e7c15dc885a3919289e4b5b378ea7995cb0'
        
        Validates multiple Kaspa transaction IDs and outputs "OK" in green text if all IDs are valid.
    
    .OUTPUTS
        Outputs "OK" in green text to the console if all transaction IDs are valid.
        If any transaction ID is invalid, the script will terminate with an error message.
    
    .NOTES
        Requires the PWSH.Kaspa module to be installed and imported.
        The validation is performed using the PWSH.Kaspa.Base.Attributes.ValidateKaspaTransactionID attribute.
#>

param 
(
    [PWSH.Kaspa.Base.Attributes.ValidateKaspaTransactionID()]
    [Parameter(Mandatory=$true)]
    [string[]] $TransactionIDs
)

Write-Host 'OK' -ForegroundColor Green