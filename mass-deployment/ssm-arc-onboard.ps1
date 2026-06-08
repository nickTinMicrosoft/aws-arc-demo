<#
.SYNOPSIS
    Arc onboarding script deployed to each EC2 instance via AWS Systems Manager.

.DESCRIPTION
    This script is executed on each target EC2 instance by SSM Run Command.
    It installs the Azure Arc agent and connects the machine to Azure.
    The machine name is automatically set to the EC2 hostname.

.NOTES
    Do NOT run this manually — it's deployed via SSM (see send-ssm-command.ps1).
    Credentials are passed via SSM parameters (encrypted in transit).
#>

param(
    [string]$SubscriptionId,
    [string]$ResourceGroup,
    [string]$TenantId,
    [string]$Location,
    [string]$ServicePrincipalId,
    [string]$ServicePrincipalSecret
)

$ErrorActionPreference = "Stop"
$machineName = $env:COMPUTERNAME

Write-Output "=== Azure Arc Onboarding via SSM ==="
Write-Output "Machine: $machineName"
Write-Output "Resource Group: $ResourceGroup"
Write-Output "Location: $Location"
Write-Output ""

# Check if already onboarded
$agentPath = "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe"
if (Test-Path $agentPath) {
    $status = & $agentPath show --json 2>$null | ConvertFrom-Json
    if ($status.status -eq "Connected") {
        Write-Output "SKIP: Machine already connected to Azure Arc."
        Write-Output "  Resource: $($status.resourceName)"
        Write-Output "  Status: $($status.status)"
        exit 0
    }
}

# Step 1: Download Arc agent
Write-Output "[1/3] Downloading Azure Connected Machine agent..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$installerPath = "$env:TEMP\AzureConnectedMachineAgent.msi"
Invoke-WebRequest -Uri "https://aka.ms/AzureConnectedMachineAgent" -OutFile $installerPath -UseBasicParsing

# Step 2: Install agent
Write-Output "[2/3] Installing agent..."
$installLog = "$env:TEMP\arc-install-$machineName.log"
$proc = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i `"$installerPath`" /quiet /l*v `"$installLog`""
if ($proc.ExitCode -ne 0) {
    Write-Output "ERROR: Agent installation failed with exit code $($proc.ExitCode)"
    Write-Output "Log: $installLog"
    exit 1
}

# Step 3: Connect to Azure Arc
Write-Output "[3/3] Connecting to Azure Arc..."
& $agentPath connect `
    --service-principal-id $ServicePrincipalId `
    --service-principal-secret $ServicePrincipalSecret `
    --resource-group $ResourceGroup `
    --tenant-id $TenantId `
    --location $Location `
    --subscription-id $SubscriptionId `
    --cloud "AzureCloud" `
    --tags "Platform=AWS,DeployMethod=SSM,OnboardDate=$(Get-Date -Format 'yyyy-MM-dd')"

if ($LASTEXITCODE -eq 0) {
    Write-Output ""
    Write-Output "SUCCESS: $machineName connected to Azure Arc!"
} else {
    Write-Output "ERROR: Connection failed. Check agent logs at: C:\ProgramData\AzureConnectedMachineAgent\Log"
    exit 1
}
