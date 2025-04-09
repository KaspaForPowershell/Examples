<#
.SYNOPSIS
    Retrieves and categorizes transactions for a specified Kaspa address.

.DESCRIPTION
    This script connects to the Kaspa network and retrieves transactions for a given address.
    Transactions are categorized into mining transactions and regular transactions.
    The script handles pagination for addresses with large transaction histories and 
    provides information about the oldest and newest transactions.

.PARAMETER Address
    The Kaspa address to retrieve transactions for. This parameter is validated to ensure
    it conforms to the Kaspa address format.

.PARAMETER TransactionLimit
    The maximum number of transactions to retrieve in a single request. 
    Must be at least 50. Default is 500.
    
.PARAMETER CleanConsole
    If specified, clears the console before running the script.

.EXAMPLE
    PS> .\filter-transactions.ps1 -Address "kaspa:qqscm7geuuc26ffneeyslsfcytg0vzf9848slkxchzdkgx3mn5mdx4dcavk2r"
    
    Retrieves transactions for the specified address using the default transaction limit.

.EXAMPLE
    PS> .\filter-transactions.ps1 -Address "kaspa:qqscm7geuuc26ffneeyslsfcytg0vzf9848slkxchzdkgx3mn5mdx4dcavk2r" -TransactionLimit 100
    
    Retrieves up to 100 transactions for the specified address.

.EXAMPLE
    PS> .\filter-transactions.ps1 -Address "kaspa:qqscm7geuuc26ffneeyslsfcytg0vzf9848slkxchzdkgx3mn5mdx4dcavk2r" -CleanConsole
    
    Clears the console before retrieving transactions for the specified address.

.OUTPUTS
    Returns a custom object containing two properties:
    - MinerTransactions: An array of transactions related to mining activities
    - OtherTransactions: An array of all other transactions

.NOTES
    Requires the PWSH.Kaspa module to be installed and imported.
#>

param 
(
    [PWSH.Kaspa.Base.Attributes.ValidateKaspaAddress()]
    [Parameter(Mandatory=$true)]
    [string] $Address,

    [Parameter(Mandatory=$false)]
    [switch] $FullTransactions,

    [Parameter(Mandatory=$false)]
    [switch] $CleanConsole
)

<# -----------------------------------------------------------------
DEFAULTS                                                           |
----------------------------------------------------------------- #>

# Clear console if the CleanConsole switch is provided.
if ($CleanConsole.IsPresent) { Clear-Host }

<# -----------------------------------------------------------------
MAIN                                                               |
----------------------------------------------------------------- #>

if (-not $FullTransactions.IsPresent) { $result = ./download-transaction-history.ps1 -Address $Address -Fields "subnetwork_id,block_time,transaction_id" }
else { $result = ./download-transaction-history.ps1 -Address $Address }

if ($result.TransactionsCount -le 0)
{
    Write-Host "No transactions found. Exiting." -ForegroundColor Red
    return
}

Write-Host "  Processing $($result.TransactionsCount) transactions..." -ForegroundColor Cyan

$minerTxs = @()
$otherTxs = @()

foreach($tx in $result.Transactions)
{
    if ($tx.SubnetworkID -eq "0100000000000000000000000000000000000000") { $minerTxs += $tx } # This is mining subnetwork https://github.com/kaspa-ng/kaspa-rest-server/pull/63/files
    else { $otherTxs += $tx }
}

Write-Host ("  Found {0} mining transactions and {1} other transactions" -f $minerTxs.Count, $otherTxs.Count)-ForegroundColor Cyan

$oldestTimestamp = ($result.Transactions | Sort-Object -Property BlockTime | Select-Object -First 1).BlockTime
$oldestDate = ConvertFrom-Timestamp -Timestamp $oldestTimestamp
Write-Host ("  Oldest transaction: {0} ({1})" -f $oldestDate.LocalDateTime, $oldestTimestamp) -ForegroundColor DarkCyan

$newestTimestamp = ($result.Transactions | Sort-Object -Property BlockTime | Select-Object -Last 1).BlockTime
$newestDate = ConvertFrom-Timestamp -Timestamp $newestTimestamp
Write-Host ("  Newest transaction: {0} ({1})" -f $newestDate.LocalDateTime, $newestTimestamp) -ForegroundColor DarkCyan

<# -----------------------------------------------------------------
OUTPUT                                                             |
----------------------------------------------------------------- #>

return [PSCustomObject]@{
    MinerTransactions  = $minerTxs
    OtherTransactions = $otherTxs
}