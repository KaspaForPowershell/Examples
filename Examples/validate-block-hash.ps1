<#  
    .SYNOPSIS
        Validates one or more Kaspa blockchain block hashes.
    
    .DESCRIPTION
        This script validates the format and structure of one or more Kaspa block hashes.
        It uses the PWSH.Kaspa module's validation attribute to ensure each provided hash
        conforms to the Kaspa blockchain's block hash specification.
        
        When executed, the script will:
        1. Validate each block hash in the provided array
        2. Output a confirmation message if all hashes pass validation
        3. Throw an error if any hash fails validation
        
        The validation includes checking:
        - Hash string length (should be 64 hexadecimal characters)
        - Valid hexadecimal character set (0-9, a-f)
        - Proper format according to Kaspa block hash standards
    
    .PARAMETER BlockHash
        An array of one or more Kaspa block hashes to validate. This parameter is mandatory and 
        must be provided as a string array. If any hash in the array fails validation,
        the script will throw an error through the validation attribute.
        
        Example: `-BlockHash '12a765b31cb904c415962da54589546aab13b5914ce9c2a64479cf4e96a9e4f9'`
    
    .EXAMPLE
        .\validate-block-hash.ps1 -BlockHash '12a765b31cb904c415962da54589546aab13b5914ce9c2a64479cf4e96a9e4f9'
        
        Validates a single Kaspa block hash and outputs "OK" in green text if successful.
    
    .EXAMPLE
        .\validate-block-hash.ps1 -BlockHash '12a765b31cb904c415962da54589546aab13b5914ce9c2a64479cf4e96a9e4f9', 'b87a4e51ac0351c38bb4d7d399294f08d4dce4f3669fe9334bc8f4407aecc382'
        
        Validates multiple Kaspa block hashes and outputs "OK" in green text if all hashes are valid.
    
    .OUTPUTS
        Outputs "OK" in green text to the console if all block hashes are valid.
        If any hash is invalid, the script will terminate with an error message.
    
    .NOTES
        Requires the PWSH.Kaspa module to be installed and imported.
        The validation is performed using the PWSH.Kaspa.Base.Attributes.ValidateKaspaBlockHash attribute.
#>

param 
(
    [PWSH.Kaspa.Base.Attributes.ValidateKaspaBlockHash()]
    [Parameter(Mandatory=$true)]
    [string[]] $BlockHashes
)

Write-Host 'OK' -ForegroundColor Green