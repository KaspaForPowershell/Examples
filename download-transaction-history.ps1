
<#
    .SYNOPSIS
        Concurrently retrieves transaction history for a Kaspa address.

    .DESCRIPTION
        This script fetches the complete transaction history for a specified Kaspa address by making
        concurrent API calls in batches. It handles pagination automatically and combines all results
        into a single collection. The script supports customizing fields returned, limiting concurrency,
        and resolving previous outpoints for comprehensive transaction data.

    .PARAMETER Address
        The Kaspa address to query transactions for. Must be a valid Kaspa address format.

    .PARAMETER ConcurrencyLimit
        The maximum number of concurrent API requests to make.
        Range: 1 to maximum unsigned integer value.
        Default: 5

    .PARAMETER Fields
        Specific fields to retrieve for each transaction. Leave empty for all fields.
        Default: "" (empty string, returns all fields)

    .PARAMETER CleanConsole
        If specified, clears the console before execution.

    .EXAMPLE
        PS> .\download-transaction-history.ps1
        Retrieves all transactions for the default address with default settings.

    .EXAMPLE
        PS> .\download-transaction-history.ps1 -Address "kaspa:qqscm7geuuc26ffneeyslsfcytg0vzf9848slkxchzdkgx3mn5mdx4dcavk2r" -ConcurrencyLimit 10
        Retrieves all transactions for the specified address with increased concurrency.

    .EXAMPLE
        PS> .\download-transaction-history.ps1 -Address "kaspa:qqscm7geuuc26ffneeyslsfcytg0vzf9848slkxchzdkgx3mn5mdx4dcavk2r" -Fields "subnetwork_id,transaction_id,block_time"
        Retrieves only specific fields (subnetwork_id, transaction_id, block_time) for all transactions.
#>

param
(
    [PWSH.Kaspa.Base.Attributes.ValidateKaspaAddress()]
    [Parameter(Mandatory=$true)]
    [string] $Address,

    [ValidateRange(1, [uint]::MaxValue)]
    [Parameter(Mandatory=$false)]
    [uint] $ConcurrencyLimit = 5,

    [ValidateNotNullOrEmpty()]
    [Parameter(Mandatory=$false)]
    [string] $Fields = "",

    [Parameter(Mandatory=$false)]
    [switch] $CleanConsole
)

<# -----------------------------------------------------------------
DEFAULTS                                                           |
----------------------------------------------------------------- #>

# Clear console if the CleanConsole switch is provided.
if ($CleanConsole.IsPresent) { Clear-Host }

# Maximum transactions per job.
$batchSize = 500

<# -----------------------------------------------------------------
MAIN                                                               |
----------------------------------------------------------------- #>

$allResults = @()

$transactionsCount = Get-TransactionsCountForAddress -Address $Address
if ($transactionsCount.Total -gt 0) 
{
    $page = 0
    $shouldContinue = $true

    $taskCountLimit = $ConcurrencyLimit - 1
    if ($transactionsCount.Total -le 500) 
    { 
        $taskCountLimit = 0 
        Write-Host "Transaction count <= 500, using single job mode." -ForegroundColor Yellow
    }

    Write-Host "Starting parallel transaction retrieval with $($taskCountLimit + 1) concurrent job(s)..." -ForegroundColor Cyan

    while ($shouldContinue)
    {
        Write-Host "`nStarting batch at page $($page)..." -ForegroundColor Magenta

        $tasks = 0..($taskCountLimit) | ForEach-Object {
            $i = $_
            $currentOffset = ($page + $i) * $batchSize
            Write-Host "  Starting job for transactions $($currentOffset) to $($currentOffset + $batchSize - 1)..." -ForegroundColor Blue

            if ($Fields -eq [string]::Empty) { Get-FullTransactionsForAddress -Address $Address -Limit $batchSize -ResolvePreviousOutpoints Light -Offset:$currentOffset -AsJob }
            else { Get-FullTransactionsForAddress -Address $Address -Limit $batchSize -ResolvePreviousOutpoints Light -Offset:$currentOffset -Fields:$Fields -AsJob }
        }

        Write-Host "Waiting for $($tasks.Count) job(s) to complete..." -ForegroundColor Cyan
        $null = $tasks | Wait-Job

        $currentPage = $page
        foreach ($job in $tasks) 
        {
            if ($job.State -eq 'Failed') 
            { 
                Write-Warning "Job $($job.Id) failed: $($job.Error)" 
                # Write-Warning "Job $($job.Id) failed: $($job.ChildJobs[0].JobStateInfo.Reason.Message)"
                Remove-Job -Id $job.Id -Force
                continue
            }

            Write-Host "Processing results from job ID $($job.Id) (page $($currentPage))..." -ForegroundColor Blue
            $pageResult = Receive-Job -Job $job
            Remove-Job -Job $job -Force

            if ($null -ne $pageResult) 
            {
                Write-Host "  Retrieved $($pageResult.Count) transactions" -ForegroundColor Green
                $allResults += $pageResult
        
                if ($pageResult.Count -lt $batchSize) 
                {
                    Write-Host "  Less than $($batchSize) transactions returned. Assuming end of data." -ForegroundColor Yellow
                    $shouldContinue = $false
                    break
                }
            }

            $currentPage++
        }

        $page = $page + $ConcurrencyLimit;

        # Delay to prevent overwhelming the server.
        Start-Sleep -Seconds 1
    }
}

<# -----------------------------------------------------------------
OUTPUT                                                             |
----------------------------------------------------------------- #>

return [PSCustomObject]@{
    TransactionsCount = $allResults.Count
    Transactions = $allResults
}