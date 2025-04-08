<#  
    .SYNOPSIS
        Calculates the amount and percentage of circulating Kaspa (KAS) owned by specified addresses.
    
    .DESCRIPTION
        This script analyzes one or more Kaspa wallet addresses to determine how much of the 
        cryptocurrency's circulating supply they control. For each address, it:
        
        - Retrieves all Unspent Transaction Outputs (UTXOs)
        - Calculates the total KAS owned by converting from Sompi (Kaspa's smallest unit)
        - Determines what percentage of the total circulating supply this represents
        - Calculates the equivalent USD value based on current market price
        
        The script provides detailed output for each individual address as well as aggregate 
        totals when multiple addresses are analyzed. This tool is useful for portfolio tracking,
        supply distribution analysis, and monitoring significant holders on the Kaspa network.
        
        The calculation accounts for all confirmed UTXOs and represents the actual spendable
        balance of each address at the time of execution.

    .PARAMETER Addresses
        An array of one or more Kaspa addresses to analyze. This parameter is mandatory and must 
        be provided as a string array. Each address must be a valid Kaspa address format.
        
        Example: `-Addresses 'kaspa:address1', 'kaspa:address2'`

    .EXAMPLE
        .\calculate-owned-supply.ps1 -Addresses 'kaspa:qpzpfwcsqsxhxwup26r55fd0ghqlhyugz8cp6y3wxuddc02vcxtjg75pspnwz'
        
        Calculates the amount of circulating Kaspa owned by a single address, showing the 
        number of UTXOs, total KAS owned, USD value, and percentage of total supply.
        
    .EXAMPLE
        .\calculate-owned-supply.ps1 -Addresses 'kaspa:qpzpfwcsqsxhxwup26r55fd0ghqlhyugz8cp6y3wxuddc02vcxtjg75pspnwz', 'kaspa:qpj2x2qfmvj4g6fn0xadv6hafdaqv4fwd3t4uvyw3walwfn50rzysa4lafpma'
        
        Analyzes multiple addresses and outputs individual results for each, followed by 
        aggregate totals showing the combined holdings, value, and supply percentage.

    .OUTPUTS
        Returns an array of PSCustomObject objects with the following properties:
        
        - Address: The Kaspa address being analyzed
        - OpenUTXOs: Number of unspent transaction outputs for the address
        - OwnedKAS: Total amount of Kaspa owned by the address (in KAS)
        - ValueUSD: Current value in USD based on market price
        - Percentage: Percentage of circulating supply owned by this address
        
        When multiple addresses are analyzed, an additional summary object is returned with:
        - TotalOwnedKAS: Combined KAS holdings across all addresses
        - TotalValueUSD: Combined USD value of all holdings
        - TotalPercentage: Combined percentage of circulating supply owned
        
        Example Output:
        ```
        Address    : kaspa:qpzpfwcsqsxhxwup26r55fd0ghqlhyugz8cp6y3wxuddc02vcxtjg75pspnwz
        OpenUTXOs  : 956
        OwnedKAS   : 1093333619.84426434
        ValueUSD   : 82903115.05
        Percentage : 4.216782700699774824489128979
        ```

    .NOTES
        The script relies on the PWSH.Kaspa module for address validation and network interaction.
        Requires functions: Get-UTXOsForAddress, Get-CirculatingCoins, Get-SompiPerKaspa, and Get-Price.
        USD values are rounded to 2 decimal places for readability.
#>

param
(
    [PWSH.Kaspa.Base.Attributes.ValidateKaspaAddress()]
    [Parameter(Mandatory=$true)]
    [string[]] $Addresses
)

<# -----------------------------------------------------------------
HELPERS                                                            |
----------------------------------------------------------------- #>

function Get-AddressSupply
{
    <#
        .SYNOPSIS
            Calculates the amount of Kaspa cryptocurrency owned by a single address.
        
        .DESCRIPTION
            This function retrieves all unspent transaction outputs (UTXOs) for a specified 
            Kaspa address and calculates various metrics about its holdings:
            
            - The total number of UTXOs available to spend
            - The total amount of Kaspa owned (converted from Sompi to KAS)
            - The current value of these holdings in USD
            - The percentage of the total circulating Kaspa supply owned by this address
            
            The function displays a progress bar while processing UTXOs for addresses with 
            many transactions. If no UTXOs are found, it will output a message indicating this.
        
        .PARAMETER Address
            A single valid Kaspa address to analyze. Must be in proper Kaspa address format 
            and is validated using the PWSH.Kaspa.Base.Attributes.ValidateKaspaAddress attribute.
        
        .OUTPUTS
            Returns a PSCustomObject containing the analysis results with the following properties:
            - Address: The Kaspa address that was analyzed
            - OpenUTXOs: Number of unspent transaction outputs found
            - OwnedKAS: Total amount of Kaspa owned, in KAS units
            - ValueUSD: Current USD value of the holdings based on market price
            - Percentage: Percentage of total circulating supply owned by this address
        
        .EXAMPLE
            Get-AddressSupply -Address 'kaspa:qpzpfwcsqsxhxwup26r55fd0ghqlhyugz8cp6y3wxuddc02vcxtjg75pspnwz'
            
            Analyzes the specified address and returns detailed information about its holdings.
    #>

    param
    (
        [PWSH.Kaspa.Base.Attributes.ValidateKaspaAddress()]
        [Parameter(Mandatory=$true)]
        [string] $Address
    )

    # Ensure there are UTXOs before proceeding.
    $utxos = Get-UTXOsForAddress -Address $Address
    $sum = 0.d
    $openUTXOs = 0
    $ownedKAS = 0.d
    $valueUSD = 0.d
    $percentage = 0.d

    if ($null -ne $utxos -and $utxos.Count -gt 0) 
    {
        $openUTXOs = $utxos.Count
        $percentUnit = 100 / $utxos.Count
        $currIndex = 0

        # Process UTXOs for the current address.
        $utxos | ForEach-Object { 
            $amount = [decimal]$_.UTXOEntry.Amount
            $sum = $sum + $amount

            # Update progress bar.
            Write-Progress -Activity ("Processing UTXOs for {0}..." -f $Address) -Status $amount -PercentComplete $currIndex
            $currIndex += $percentUnit  
        }

        # Calculate percentage, total owned Kaspa, and its value in USD.
        $percentage = (($sum / (Get-CirculatingCoins)) * 100.d) / (Get-SompiPerKaspa)
        $ownedKAS = $sum / (Get-SompiPerKaspa)
        $valueUSD = [decimal]([decimal]::Truncate(($ownedKAS * (Get-Price)) * 100) / 100) # 1 USD == 99 cents, so only two decimal places.
    } 
    else { Write-Host ("No open UTXOs found for address: {0}" -f $Address) }

    # Store result as a new object.
    return [PSCustomObject]@{
        Address = $Address
        OpenUTXOs = $openUTXOs
        OwnedKAS = $ownedKAS
        ValueUSD = $valueUSD
        Percentage = $percentage
    }
}

<# -----------------------------------------------------------------
MAIN                                                               |
----------------------------------------------------------------- #>

$results = @()

$Addresses | ForEach-Object { $results += Get-AddressSupply -Address $_ }

if ($Addresses.Count -eq 1) 
{ 
    $results
    return 
}

# Initialize variables for totals.
$totalOwnedKAS = 0.d
$totalValueUSD = 0.d
$totalPercentage = 0.d

# Sum values across all addresses.
$results | ForEach-Object {
    $totalOwnedKAS += $_.OwnedKAS
    $totalValueUSD += $_.ValueUSD
    $totalPercentage += $_.Percentage
}

# Output the summed values as a custom object.
$totalResults =  [PSCustomObject]@{
    TotalOwnedKAS  = $totalOwnedKAS
    TotalValueUSD  = $totalValueUSD
    TotalPercentage = $totalPercentage
}

$results
$totalResults