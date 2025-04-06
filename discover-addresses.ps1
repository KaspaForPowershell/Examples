<#
    .SYNOPSIS
        Recursively discovers related Kaspa addresses by analyzing blockchain transaction inputs and outputs from a starting address.
    
    .DESCRIPTION
        This script performs recursive address discovery for the Kaspa cryptocurrency network. Starting from an initial address, it traverses the blockchain by extracting new addresses from transaction inputs and outputs.
        
        The script implements parallel processing through PowerShell jobs, allowing multiple address lookups to run concurrently within a configurable limit. This significantly improves performance when analyzing large transaction sets. Address discovery is controlled by a maximum depth parameter that limits how far the script will traverse from the initial address.
        
        The script continues processing until all discoverable addresses within the depth limit have been analyzed. Upon completion, it returns a complete set of all discovered addresses, which can be used for blockchain analysis, wallet clustering, or transaction flow mapping.

    .PARAMETER InitialAddress
        The starting address to begin processing from. This address is validated to ensure it is a valid Kaspa address.

    .PARAMETER TransactionLimit
        The maximum number of transactions to fetch per address when an address has more than 500 transactions and pagination is required. Defaults to 500 if not specified.

    .PARAMETER MaxDepth
        The maximum depth for address discovery, i.e., how many levels deep to look for transactions. Defaults to 1 if not specified.
        MaxDepth 1: Any addresses that appear in the initial address transactions
        MaxDepth 2: All of the above + addresses from transactions of the depth 2 addresses
        MaxDepth 3: All of the above + addresses from transactions of the depth 3 addresses
        And so on...

    .PARAMETER ConcurrencyLimit
        The maximum number of concurrent jobs to run for parallel processing. Higher values improve throughput on systems with adequate resources but may increase API load. Defaults to 5 if not specified.

    .PARAMETER MaxFailedTries
        The maximum number of retry attempts for addresses from failed jobs before abandoning processing. Provides resilience against temporary network or API issues. Defaults to 3 if not specified.

    .PARAMETER SkipInputs
        If specified, the script will skip processing transaction inputs and only discover addresses from outputs.

    .PARAMETER SkipOutputs
        If specified, the script will skip processing transaction outputs and only discover addresses from inputs.

    .PARAMETER CleanConsole
        An optional switch to clear the console screen before processing the addresses. 
        If this switch is provided, the console will be cleared at the beginning of the script execution.

    .EXAMPLE
        PS> .\discover-addresses.ps1 -InitialAddress "kaspa:abcd1234..." -TransactionLimit 100 -MaxDepth 3 -ConcurrencyLimit 10
        Starts address discovery with a limit of 100 transactions per address, maximum depth of 3, and up to 10 concurrent jobs.

    .EXAMPLE
        PS> .\discover-addresses.ps1 -InitialAddress "kaspa:abcd1234..." -CleanConsole
        Starts address discovery with the console cleared before execution.

    .EXAMPLE
        PS> .\discover-addresses.ps1 -InitialAddress "kaspa:abcd1234..." -CleanConsole -SkipInputs
        Starts address discovery from the specified address with default parameters, clears the console before execution, and only processes transaction outputs.

    .OUTPUTS
        [PSCustomObject] An object with four properties:
            - DiscoveredCount: The total number of unique addresses discovered
            - DiscoveredAddresses: A collection of all discovered addresses (System.Collections.Generic.ICollection[string])
            - FailedCount: The total number of addresses that failed processing after all retry attempts
            - FailedAddresses: A collection of addresses that could not be processed (System.Collections.Generic.ICollection[string])
#>

param
(
    [PWSH.Kaspa.Base.Attributes.ValidateKaspaAddress()]
    [Parameter(Mandatory=$true)]
    [string] $InitialAddress,

    [ValidateRange(50, [uint]::MaxValue)]
    [Parameter(Mandatory=$false)]
    [uint] $TransactionLimit = 500,
    
    [ValidateRange(1, [uint]::MaxValue)]
    [Parameter(Mandatory=$false)]
    [uint] $MaxDepth = 1,

    [ValidateRange(1, [uint]::MaxValue)]
    [Parameter(Mandatory=$false)]
    [uint] $ConcurrencyLimit = 5,

    [ValidateRange(0, [uint]::MaxValue)]
    [Parameter(Mandatory=$false)]
    [uint] $MaxFailedTries = 3,

    [Parameter(Mandatory=$false)]
    [switch] $SkipInputs,

    [Parameter(Mandatory=$false)]
    [switch] $SkipOutputs,

    [Parameter(Mandatory=$false)]
    [switch] $CleanConsole
)

<# -----------------------------------------------------------------
DEFAULTS                                                           |
----------------------------------------------------------------- #>

# Clear console if the CleanConsole switch is provided.
if ($CleanConsole.IsPresent) { Clear-Host }

# Prepare fields property.
$queryFields = "inputs,outputs"
if ($SkipInputs.IsPresent) { $queryFields = "outputs" }
if ($SkipOutputs.IsPresent) { $queryFields = "inputs" }
if ($SkipInputs.IsPresent -and $SkipOutputs.IsPresent) { $queryFields = "" }

<# -----------------------------------------------------------------
HELPERS                                                            |
----------------------------------------------------------------- #>

function Resolve-FailedJobs
{
    <#
    .SYNOPSIS
        Processes failed PowerShell jobs and moves their associated addresses to the retry queue.
    
    .DESCRIPTION
        This function identifies any failed jobs in the jobs collection, removes them, and transfers their
        associated address data to the failed queue for potential retry. It provides visual feedback about
        the failed jobs through console output.
    
    .PARAMETER JobsCollection
        A hashtable containing all active jobs with their associated metadata, keyed by job ID.
    
    .PARAMETER FailedQueue
        A queue that will store information about addresses that need to be retried due to job failures.
    
    .EXAMPLE
        PS> Resolve-FailedJobs -JobsCollection $jobs -FailedQueue $retryQueue
        Processes all failed jobs, removing them from the $jobs collection and adding their addresses to $retryQueue.
    #>

    param 
    (
        [Parameter(Mandatory=$true, Position = 0)]
        [System.Collections.Hashtable] $JobsCollection,

        [Parameter(Mandatory=$true)]
        [System.Collections.Queue] $FailedQueue
    )
    
    $jobs = Get-Job | Where-Object { $_.State -eq "Failed" -and $JobsCollection.ContainsKey($_.Id) }
    if ($jobs.Count -le 0) { return }

    Write-Host "Processing $($jobs.Count) failed jobs..." -ForegroundColor Magenta

    foreach ($job in $jobs) 
    {
        Remove-Job -Job $job
        $jobData = $JobsCollection[$job.Id]
        $JobsCollection.Remove($job.Id) 

        Write-Host "  Job for address $($jobData.Address) at depth $($jobData.Depth) failed" -ForegroundColor Red
        $FailedQueue.Enqueue(@{
            Address = $jobData.Address
            Depth = $jobData.Depth
        })
    }
}

function Redo-RetryQueue
{
    <#
    .SYNOPSIS
        Handles retrying failed address processing operations within configured retry limits.
    
    .DESCRIPTION
        This function manages the retry mechanism for addresses whose processing jobs have failed. It implements
        a configurable retry policy based on the MaxFailedTries parameter, requeuing addresses that haven't 
        exceeded the retry limit and abandoning those that have. It provides status feedback through the console
        and ensures addresses are properly tracked in the processing system.
    
    .PARAMETER RetryQueue
        A queue containing information about addresses whose processing jobs have failed.
    
    .PARAMETER RetryCount
        A reference parameter that tracks the current retry attempt number.
    
    .PARAMETER AddressQueue
        The main queue of addresses to be processed.
    
    .PARAMETER ProcessedAddresses
        A HashSet containing all addresses that have been processed or are currently in processing.
    
    .OUTPUTS
        [Boolean] Returns $true if there are addresses that have been requeued for retry, 
        $false if no more retries are possible or needed.
    
    .EXAMPLE
        PS> $shouldContinue = Redo-RetryQueue -RetryQueue $retryQueue -RetryCount ([ref]$retryCount) -AddressQueue $addressQueue -ProcessedAddresses $processedAddresses
        If $shouldContinue is true, there are requeued addresses that need processing.
    #>

    param
    (
        [Parameter(Mandatory=$true, Position = 0)]
        [System.Collections.Queue] $RetryQueue,

        [Parameter(Mandatory=$true, Position = 1)]
        [ref] $RetryCount,

        [Parameter(Mandatory=$true)]
        [System.Collections.Queue] $AddressQueue,

        [Parameter(Mandatory=$true)]
        [System.Collections.Generic.HashSet[string]] $ProcessedAddresses
    )

    $shouldContinue = $false

    if ($RetryQueue.Count -gt 0)
    {
        if ($RetryCount.Value -lt $MaxFailedTries)
        {
            $RetryCount.Value = $RetryCount.Value + 1

            $RetryQueue | ForEach-Object {
                $AddressQueue.Enqueue($_)
                $ProcessedAddresses.Remove($_.Address) | Out-Null
                Write-Host "  Re-queued failed address $($_.Address) for retry attempt $($RetryCount.Value)/$($MaxFailedTries)" -ForegroundColor Yellow 
            }

            $RetryQueue.Clear()
            $shouldContinue = $true
        }
        else 
        { 
            $RetryQueue | ForEach-Object { 
                Write-Host "  Skipping address $($_.Address) after $($MaxFailedTries) failed attempts" -ForegroundColor Red 
            }

            $shouldContinue = $false
        }
    }

    return $shouldContinue
}

function Resolve-CompletedJobs
{
    <#
    .SYNOPSIS
        Processes completed jobs, extracts transaction data, and discovers new addresses.
    
    .DESCRIPTION
        This function handles the core address discovery logic by processing completed jobs, extracting transaction 
        data, and identifying new Kaspa addresses from both inputs and outputs. It respects the SkipInputs and 
        SkipOutputs parameters to control which transaction components are analyzed, tracks address depth, 
        and maintains the discovered addresses collection. It provides detailed feedback about the discovery 
        process through console output.
    
    .PARAMETER JobsCollection
        A hashtable containing all active jobs with their associated metadata, keyed by job ID.
    
    .PARAMETER AddressQueue
        The queue to which newly discovered addresses will be added for processing.
    
    .PARAMETER DiscoveredAddresses
        A dictionary tracking all discovered addresses and their depths from the initial address.
    
    .EXAMPLE
        PS> Resolve-CompletedJobs -JobsCollection $jobs -AddressQueue $addressQueue -DiscoveredAddresses $discoveredAddresses
        Processes all completed jobs, extracts transaction data, and adds newly discovered addresses to the process queue.
    #>

    param
    (
        [Parameter(Mandatory=$true, Position = 0)]
        [System.Collections.Hashtable] $JobsCollection,

        [Parameter(Mandatory=$true)]
        [System.Collections.Queue] $AddressQueue,

        [AllowEmptyCollection()]
        [Parameter(Mandatory=$true)]
        [System.Collections.Generic.Dictionary[string,int]] $DiscoveredAddresses
    )

    $jobs = Get-Job | Where-Object { $_.State -eq "Completed" -and $JobsCollection.ContainsKey($_.Id) }
    if ($jobs.Count -le 0) { return }
    
    Write-Host "Processing $($jobs.Count) completed jobs..." -ForegroundColor Magenta
    
    foreach ($job in $jobs) 
    {
        $result = Receive-Job -Job $job
        Remove-Job -Job $job
        $jobData = $JobsCollection[$job.Id]
        $JobsCollection.Remove($job.Id)
        
        Write-Host "  Job for address $($jobData.Address) at depth $($jobData.Depth) completed" -ForegroundColor Green
       
        if ($null -eq $result) 
        { 
            Write-Host "  No results returned for this job" -ForegroundColor DarkYellow
            continue 
        }

        # Extract addresses from transactions.    
        if ($SkipInputs.IsPresent -and $SkipOutputs.IsPresent) { continue }

        $newAddressesCount = 0

        foreach ($tx in $result) 
        {
            if (-not($SkipInputs.IsPresent))
            {
                foreach ($input in $tx.Inputs) 
                {
                    $newAddress = $input.PreviousOutpointAddress
                    $newDepth = $jobData.Depth + 1

                    if ([string]::IsNullOrEmpty($newAddress)) { continue }
                    if (-not $discoveredAddresses.ContainsKey($newAddress) -or $discoveredAddresses[$newAddress] -gt $newDepth)
                    {
                        $discoveredAddresses[$newAddress] = $newDepth
                        $AddressQueue.Enqueue(@{ Address = $newAddress; Depth = $newDepth })
                        $newAddressesCount++
                    }
                }
            }

            if (-not($SkipOutputs.IsPresent))
            {
                foreach ($output in $tx.Outputs) 
                {
                    $newAddress = $output.ScriptPublicKeyAddress
                    $newDepth = $jobData.Depth + 1

                    if ([string]::IsNullOrEmpty($newAddress)) { continue }
                    if (-not $discoveredAddresses.ContainsKey($newAddress) -or $discoveredAddresses[$newAddress] -gt $newDepth)
                    {
                        $discoveredAddresses[$newAddress] = $newDepth
                        $AddressQueue.Enqueue(@{ Address = $newAddress; Depth = $newDepth })
                        $newAddressesCount++
                    }
                }
            }
        }
        
        Write-Host "  Added $($newAddressesCount) new addresses to queue from depth $($jobData.Depth) to depth $($jobData.Depth + 1)" -ForegroundColor DarkGreen
    }
}

function Start-QueuedAddressesJobs
{
   <#
    .SYNOPSIS
        Creates and initiates new jobs to process queued addresses within concurrency limits.
    
    .DESCRIPTION
        This function manages the job creation and scheduling logic by processing addresses from the queue,
        respecting concurrency limits, tracking address processing state, and using appropriate transaction
        retrieval methods based on transaction volume. It adapts its approach depending on whether an address 
        has more than 500 transactions (requiring pagination) and respects the MaxDepth parameter to limit 
        recursive processing.
    
    .PARAMETER JobsCollection
        A hashtable that will store information about all created jobs, keyed by job ID.
    
    .PARAMETER AddressQueue
        The queue containing addresses waiting to be processed.
    
    .PARAMETER ProcessedAddresses
        A HashSet containing all addresses that have been processed or are currently in processing.
    
    .PARAMETER QueryFields
        A string specifying which fields to retrieve from the transactions (inputs, outputs, or both).
    
    .EXAMPLE
        PS> Start-QueuedAddressesJobs -JobsCollection $jobs -AddressQueue $addressQueue -ProcessedAddresses $processedAddresses -QueryFields "inputs,outputs"
        Processes addresses from the queue and creates jobs to retrieve transaction data with both inputs and outputs.
    #>

    param
    (
        [Parameter(Mandatory=$true, Position = 0)]
        [System.Collections.Hashtable] $JobsCollection,

        [Parameter(Mandatory=$true)]
        [System.Collections.Queue] $AddressQueue,

        [AllowEmptyCollection()]
        [Parameter(Mandatory=$true)]
        [System.Collections.Generic.HashSet[string]] $ProcessedAddresses,

        [AllowEmptyString()]
        [Parameter(Mandatory=$true)]
        [string] $QueryFields
    )

    $addressesProcessed = 0
    
    if ($AddressQueue.Count -gt 0 -and $JobsCollection.Count -lt $ConcurrencyLimit) { Write-Host "Processing queue: $($AddressQueue.Count) addresses waiting, capacity for $($ConcurrencyLimit - $JobsCollection.Count) more jobs" -ForegroundColor Blue }
    
    while ($AddressQueue.Count -gt 0 -and $JobsCollection.Count -lt $ConcurrencyLimit) 
    {
        $current = $AddressQueue.Dequeue()
        $addressesProcessed++

        # Mark as processed.
        if ($ProcessedAddresses.Contains($current.Address)) 
        {
            Write-Host "  Skipping already processed address: $($current.Address)" -ForegroundColor DarkGray
            continue 
        }
        if ($current.Depth -ge $MaxDepth) { 
            Write-Host "  Skipping address at max depth: $($current.Address) (Depth: $($current.Depth))" -ForegroundColor DarkGray
            continue 
        }

        $ProcessedAddresses.Add($current.Address) | Out-Null
        Write-Host "Processing address: " -ForegroundColor Yellow -NoNewline
        Write-Host ("{0} (Depth: {1} of {2})" -f $current.Address, $current.Depth, $MaxDepth)

        # Fetch transactions as a job.
        $transactionsCount = Get-TransactionsCountForAddress -Address $current.Address
        Write-Host "  Found transactions for this address" -ForegroundColor DarkYellow

        if ($transactionsCount.Total -le 500) 
        { 
            if ([string]::IsNullOrEmpty($QueryFields) -eq $true) { $job = Get-FullTransactionsForAddress -Address $current.Address -Limit 500 -ResolvePreviousOutpoints Light -AsJob  }
            else { $job = Get-FullTransactionsForAddress -Address $current.Address -Limit 500 -Fields:$QueryFields -ResolvePreviousOutpoints Light -AsJob  }
            
            Write-Host "  Created job using Get-FullTransactionsForAddress" -ForegroundColor Gray
        } 
        else 
        { 
            if ([string]::IsNullOrEmpty($QueryFields) -eq $true) { $job = Get-FullTransactionsForAddressPage -Address $current.Address -Limit $TransactionLimit -Timestamp 0 -BeforeTimestamp -ResolvePreviousOutpoints Light -AsJob }
            else { $job = Get-FullTransactionsForAddressPage -Address $current.Address -Limit $TransactionLimit -Timestamp 0 -BeforeTimestamp -Fields:$QueryFields -ResolvePreviousOutpoints Light -AsJob }
            
            Write-Host "  Created job using Get-FullTransactionsForAddressPage with limit $($TransactionLimit)" -ForegroundColor Gray
        }

        $JobsCollection[$job.Id] = @{
            Job = $job
            Address = $current.Address
            Depth = $current.Depth
        }
        
        Write-Host "  Started job #$($job.Id) for address at depth $($current.Depth)" -ForegroundColor DarkBlue
    }
    
    if ($addressesProcessed -gt 0) { Write-Host "Processed $($addressesProcessed) addresses from queue in this iteration" -ForegroundColor Blue }
}

<# -----------------------------------------------------------------
MAIN                                                               |
----------------------------------------------------------------- #>

# Variables for output.
$discoveredAddresses = New-Object 'System.Collections.Generic.Dictionary[string,int]'

# For addresses which transaction requests failed.
$retryQueue = New-Object 'System.Collections.Queue'
$retryCount = 0

# For addresses which transactions will be processed.
$processedAddresses = New-Object 'System.Collections.Generic.HashSet[string]'

$addressQueue = New-Object 'System.Collections.Queue'
$addressQueue.Enqueue(@{ Address = $InitialAddress; Depth = 0 })

# Job tracking list for transactions request jobs.
$jobs = @{}

# Main loop.
while ($addressQueue.Count -gt 0 -or $jobs.Count -gt 0) 
{
    Write-Host "Main loop status: Queue size: $($addressQueue.Count), Active jobs: $($jobs.Count), Failed count: $($retryQueue.Count)" -ForegroundColor Cyan
    
    # Process jobs to free up capacity.
    Resolve-FailedJobs $jobs -FailedQueue:$retryQueue
    Resolve-CompletedJobs $jobs -AddressQueue:$addressQueue -DiscoveredAddresses:$discoveredAddresses

    # Start new jobs for queued addresses if we have capacity.
    Start-QueuedAddressesJobs $jobs -AddressQueue:$addressQueue -ProcessedAddresses:$processedAddresses -QueryFields:$queryFields

    # If we have jobs running, but can't add more jobs (either queue is empty or at concurrency limit), then wait a bit for jobs to complete.
    if ($jobs.Count -gt 0 -and ($addressQueue.Count -eq 0 -or $jobs.Count -ge $ConcurrencyLimit)) 
    {
        if ($addressQueue.Count -eq 0) { Write-Host "Waiting for jobs to complete (queue empty, $($jobs.Count) jobs running)" -ForegroundColor DarkCyan } 
        else { Write-Host "Waiting for jobs to complete (at concurrency limit, $($jobs.Count)/$($ConcurrencyLimit) jobs running, $($addressQueue.Count) in queue)" -ForegroundColor DarkCyan }

        Start-Sleep -Seconds 1
    }
    
    if ($jobs.Count -eq 0 -and $addressQueue.Count -eq 0) 
    {
        # If we failed to process some addresses, be it because of API rate limits or other reasons, we should try to process them again.
        $shouldContinue = Redo-RetryQueue $retryQueue ([ref]$retryCount) -AddressQueue:$addressQueue -ProcessedAddresses:$processedAddresses
        if ($shouldContinue -eq $true) { continue }

        # If we somehow end up with no jobs and no queue items, make sure we log it.
        Write-Host "No jobs running and queue empty - processing complete!" -ForegroundColor Green 
    }
}

<# -----------------------------------------------------------------
OUTPUT                                                             |
----------------------------------------------------------------- #>

# Return all discovered addresses and addresses for which requests failed.
$failedAddresses = $retryQueue | Select-Object -ExpandProperty Address

return [PSCustomObject]@{
    DiscoveredCount = $discoveredAddresses.Keys.Count
    DiscoveredAddresses = $discoveredAddresses.Keys
    FailedCount = $failedAddresses.Count
    FailedAddresses = $failedAddresses
}