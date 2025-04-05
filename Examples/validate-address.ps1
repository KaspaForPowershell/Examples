<#  
    .SYNOPSIS
        Validates one or more Kaspa cryptocurrency addresses.
    
    .DESCRIPTION
        This script validates the format and checksum of one or more Kaspa wallet addresses.
        It leverages the PWSH.Kaspa module's address validation attribute to ensure each
        provided address conforms to the Kaspa address specification.
        
        When executed, the script will:
        1. Validate each address in the provided array
        2. Output a confirmation message if all addresses pass validation
        3. Throw an error if any address fails validation
        
        The validation includes checking:
        - Proper prefix (starts with "kaspa:")
        - Correct character set
        - Proper length
    
    .PARAMETER Addresses
        An array of one or more Kaspa addresses to validate. This parameter is mandatory and 
        must be provided as a string array. If any address in the array fails validation,
        the script will throw an error.
        
        Example: `-Addresses 'kaspa:address1', 'kaspa:address2'`
    
    .EXAMPLE
        .\validate-address.ps1 -Addresses 'kaspa:qpzpfwcsqsxhxwup26r55fd0ghqlhyugz8cp6y3wxuddc02vcxtjg75pspnwz'
        
        Validates a single Kaspa address and outputs "OK" in green text if successful.
    
    .EXAMPLE
        .\validate-address.ps1 -Addresses 'kaspa:qpzpfwcsqsxhxwup26r55fd0ghqlhyugz8cp6y3wxuddc02vcxtjg75pspnwz', 'kaspa:qpj2x2qfmvj4g6fn0xadv6hafdaqv4fwd3t4uvyw3walwfn50rzysa4lafpma'
        
        Validates multiple Kaspa addresses and outputs "OK" in green text if all addresses are valid.
    
    .OUTPUTS
        Outputs "OK" in green text to the console if all addresses are valid.
        If any address is invalid, the script will terminate with an error message.
    
    .NOTES
        Requires the PWSH.Kaspa module to be installed and imported.
        The validation is performed using the PWSH.Kaspa.Base.Attributes.ValidateKaspaAddress attribute.
#>

param 
(
    [PWSH.Kaspa.Base.Attributes.ValidateKaspaAddress()]
    [Parameter(Mandatory=$true)]
    [string[]] $Addresses
)

Write-Host 'OK' -ForegroundColor Green