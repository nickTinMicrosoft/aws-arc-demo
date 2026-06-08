<#
.SYNOPSIS
    Deploy Azure Arc to multiple servers from a CSV inventory file using WinRM.

.DESCRIPTION
    Reads servers.csv, connects to each server via WinRM (PSRemoting), and
    installs the Azure Arc agent. Works for any Windows servers you can reach
    over the network (AWS, on-prem, any cloud).

.PARAMETER CsvPath
    Path to the server inventory CSV file.

.PARAMETER MaxParallel
    Number of servers to onboard simultaneously. Default: 5.

.EXAMPLE
    .\csv-mass-deploy.ps1 -CsvPath ".\servers.csv" -MaxParallel 10

.NOTES
    Prerequisites:
    - WinRM/PSRemoting enabled on target servers (Enable-PSRemoting)
    - Network access from this machine to targets on port 5985/5986
    - Admin credentials for target servers
    - .env file with Azure credentials
#>

param(
    [string]$CsvPath = (Join-Path $PSScriptRoot "servers.csv"),
    [int]$MaxParallel = 5
)

# Load environment variables
$envFile = Join-Path $PSScriptRoot "..\.env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim())
        }
    }
}

$subscriptionId = $env:AZURE_SUBSCRIPTION_ID
$resourceGroup  = $env:AZURE_RESOURCE_GROUP
$tenantId       = $env:AZURE_TENANT_ID
$location       = $env:AZURE_LOCATION
$spId           = $env:AZURE_SP_APP_ID
$spSecret       = $env:AZURE_SP_SECRET

Write-Host "=== Mass Deployment: CSV-Driven Arc Onboarding ===" -ForegroundColor Cyan
Write-Host ""

# Read server inventory
$servers = Import-Csv $CsvPath
Write-Host "Loaded $($servers.Count) servers from $CsvPath"
Write-Host "Max parallel: $MaxParallel"
Write-Host ""

# Prompt for credentials to connect to remote servers
$cred = Get-Credential -Message "Enter admin credentials for target servers"

# Onboarding script block to run on each remote server
$onboardScript = {
    param($SubId, $RG, $Tenant, $Loc, $SpId, $SpSecret)

    $ErrorActionPreference = "Stop"
    $machineName = $env:COMPUTERNAME

    # Check if already connected
    $agentPath = "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe"
    if (Test-Path $agentPath) {
        $statusJson = & $agentPath show --json 2>$null
        if ($statusJson -match '"status"\s*:\s*"Connected"') {
            return "SKIP: $machineName already connected"
        }
    }

    # Download agent
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $installer = "$env:TEMP\AzureConnectedMachineAgent.msi"
    Invoke-WebRequest -Uri "https://aka.ms/AzureConnectedMachineAgent" -OutFile $installer -UseBasicParsing

    # Install agent
    $proc = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i `"$installer`" /quiet"
    if ($proc.ExitCode -ne 0) { throw "Install failed: exit code $($proc.ExitCode)" }

    # Connect to Arc
    & $agentPath connect `
        --service-principal-id $SpId `
        --service-principal-secret $SpSecret `
        --resource-group $RG `
        --tenant-id $Tenant `
        --location $Loc `
        --subscription-id $SubId `
        --cloud "AzureCloud" `
        --tags "Platform=AWS,DeployMethod=CSV,OnboardDate=$(Get-Date -Format 'yyyy-MM-dd')"

    if ($LASTEXITCODE -eq 0) {
        return "SUCCESS: $machineName connected to Azure Arc"
    } else {
        throw "Connection failed for $machineName"
    }
}

# Deploy in parallel batches
$results = @()
$jobs = @()

foreach ($server in $servers) {
    Write-Host "  Starting: $($server.hostname) ($($server.ip_address))..." -ForegroundColor Yellow

    $job = Invoke-Command -ComputerName $server.ip_address `
        -Credential $cred `
        -ScriptBlock $onboardScript `
        -ArgumentList $subscriptionId, $resourceGroup, $tenantId, $location, $spId, $spSecret `
        -AsJob

    $jobs += @{ Job = $job; Server = $server.hostname }

    # Throttle parallelism
    while (($jobs | Where-Object { $_.Job.State -eq "Running" }).Count -ge $MaxParallel) {
        Start-Sleep -Seconds 5
    }
}

# Wait for all to complete
Write-Host ""
Write-Host "Waiting for all jobs to complete..." -ForegroundColor Yellow
$jobs | ForEach-Object { $_.Job | Wait-Job } | Out-Null

# Collect results
Write-Host ""
Write-Host "=== RESULTS ===" -ForegroundColor Cyan
Write-Host ("{0,-20} {1,-12} {2}" -f "SERVER", "STATUS", "DETAIL")
Write-Host ("{0,-20} {1,-12} {2}" -f "------", "------", "------")

foreach ($item in $jobs) {
    $job = $item.Job
    $name = $item.Server
    if ($job.State -eq "Completed") {
        $output = Receive-Job $job
        $status = if ($output -match "SUCCESS") { "OK" } elseif ($output -match "SKIP") { "SKIPPED" } else { "UNKNOWN" }
        Write-Host ("{0,-20} {1,-12} {2}" -f $name, $status, $output) -ForegroundColor Green
    } else {
        $error = $job.ChildJobs[0].Error | Select-Object -First 1
        Write-Host ("{0,-20} {1,-12} {2}" -f $name, "FAILED", $error) -ForegroundColor Red
    }
    Remove-Job $job -Force
}

Write-Host ""
Write-Host "Done! Verify in Azure Portal: Azure Arc > Servers" -ForegroundColor Green
