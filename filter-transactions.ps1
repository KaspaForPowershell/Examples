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
    PS> .\filter-transactions.ps1 -Address "kaspa:qz0atyd994hyt5cqyhjkun4s5efs5c807a9j4vj80xu2kmwx8jlxzwjte4k27"
    
    Retrieves transactions for the specified address using the default transaction limit.

.EXAMPLE
    PS> .\filter-transactions.ps1 -Address "kaspa:qz0atyd994hyt5cqyhjkun4s5efs5c807a9j4vj80xu2kmwx8jlxzwjte4k27" -TransactionLimit 100
    
    Retrieves up to 100 transactions for the specified address.

.EXAMPLE
    PS> .\filter-transactions.ps1 -Address "kaspa:qz0atyd994hyt5cqyhjkun4s5efs5c807a9j4vj80xu2kmwx8jlxzwjte4k27" -CleanConsole
    
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

    [ValidateRange(50, 500)]
    [Parameter(Mandatory=$false)]
    [uint] $TransactionLimit = 500,

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

# Prepare fields property.
$queryFields = ""
if (-not $FullTransactions.IsPresent) { $queryFields = "subnetwork_id,block_time,transaction_id" }

<# -----------------------------------------------------------------
HELPERS                                                            |
----------------------------------------------------------------- #>

function Start-TransactionRetrievalJob 
{
    <#
    .SYNOPSIS
        Creates and starts a background job to retrieve transactions for a Kaspa address.
    
    .DESCRIPTION
        This function determines the appropriate method to retrieve transactions based on
        the total number of transactions for the address. For addresses with 500 or fewer
        transactions, it uses Get-FullTransactionsForAddress. For addresses with more
        transactions, it uses Get-FullTransactionsForAddressPage with the specified limit.
    
    .PARAMETER Address
        The Kaspa address to retrieve transactions for.
    
    .PARAMETER TransactionLimit
        The maximum number of transactions to retrieve in a single request.
    
    .OUTPUTS
        Returns a background job object if transactions are found, or $null if no
        transactions are found for the address.
    #>

    param 
    (
        [Parameter(Mandatory=$true)]
        [string] $Address,

        [Parameter(Mandatory=$true)]
        [uint] $TransactionLimit,

        [AllowEmptyString()]
        [Parameter(Mandatory=$true)]
        [string] $QueryFields
    )

    Write-Host ("Checking transactions for address: {0}" -f $Address) -ForegroundColor Cyan

    $transactionsCount = Get-TransactionsCountForAddress -Address $Address
    if ($transactionsCount.Total -gt 0) { Write-Host "  Found transactions for this address" -ForegroundColor DarkYellow }
    else 
    {
        Write-Host "  No transactions found for this address" -ForegroundColor DarkYellow
        return $null
    }

    if ($transactionsCount.Total -le 500) 
    { 
        Write-Host "  Created transaction retrieval job using Get-FullTransactionsForAddress" -ForegroundColor Gray
        return Get-FullTransactionsForAddress -Address $Address -Limit 500 -Fields $QueryFields -ResolvePreviousOutpoints Light -AsJob
    } 
    else 
    { 
        Write-Host ("  Created transaction retrieval job using Get-FullTransactionsForAddressPage with limit {0}" -f $TransactionLimit) -ForegroundColor Gray
        return Get-FullTransactionsForAddressPage -Address $Address -Limit $TransactionLimit -Fields $QueryFields -Timestamp 0 -BeforeTimestamp -ResolvePreviousOutpoints Light -AsJob
    }
}

<# -----------------------------------------------------------------
MAIN                                                               |
----------------------------------------------------------------- #>

$job = Start-TransactionRetrievalJob -Address:$Address -TransactionLimit:$TransactionLimit -QueryFields:$QueryFields
if ($null -eq $job) 
{
    Write-Host "No job was created. Exiting." -ForegroundColor Red
    return
}

$waitCounter = 0

while ($true)
{   
    $currState = $job.State

    if ($currState -eq "Completed")
    {
        Write-Host ("  Transaction retrieval job for address {0} completed" -f $Address) -ForegroundColor Green
        $transactions = Receive-Job -Job $job
        Remove-Job -Job $job
        
        if ($transactions.Count -le 0) { return }

        $minerTxs = @()
        $otherTxs = @()

        Write-Host "  Processing $($transactions.Count) transactions..." -ForegroundColor Cyan
        foreach ($tx in $transactions)
        {
            if ($tx.SubnetworkID -eq "0100000000000000000000000000000000000000") { $minerTxs += $tx } # This is mining subnetwork https://github.com/kaspa-ng/kaspa-rest-server/pull/63/files
            else { $otherTxs += $tx }
        }

        Write-Host ("  Found {0} mining transactions and {1} other transactions" -f $minerTxs.Count, $otherTxs.Count)-ForegroundColor Cyan

        $oldestTimestamp = ($transactions | Sort-Object -Property BlockTime | Select-Object -First 1).BlockTime
        $oldestDate = ConvertFrom-Timestamp -Timestamp $oldestTimestamp
        Write-Host ("  Oldest transaction: {0} ({1})" -f $oldestDate.LocalDateTime, $oldestTimestamp) -ForegroundColor DarkCyan

        $newestTimestamp = ($transactions | Sort-Object -Property BlockTime | Select-Object -Last 1).BlockTime
        $newestDate = ConvertFrom-Timestamp -Timestamp $newestTimestamp
        Write-Host ("  Newest transaction: {0} ({1})" -f $newestDate.LocalDateTime, $newestTimestamp) -ForegroundColor DarkCyan
        
        # Return both categories as a grouped object.
        return [PSCustomObject]@{
            MinerTransactions  = $minerTxs
            OtherTransactions = $otherTxs
        }
    }
    elseif ($currState -eq "Failed")
    {
        Write-Host ("  Transaction retrieval job for address {0} failed" -f $Address) -ForegroundColor Red
        Remove-Job -Job $job
        break
    }
    else 
    { 
        # If we have job running, then wait a bit for job to complete.
        $waitCounter++
        $dots = "." * ($waitCounter % 4)
        Write-Host ("Waiting for transaction retrieval job to complete{0}" -f $dots.PadRight(3)) -ForegroundColor DarkCyan -NoNewline
        Write-Host "`r" -NoNewline

        Start-Sleep -Seconds 1
        continue
    }
}