<#
.SYNOPSIS
    PASTE THIS INTO POWERSHELL ON YOUR EC2 INSTANCE
    This will install the Azure Arc agent and register this machine + SQL Server with Azure.

.NOTES
    Run as Administrator on the EC2 instance (via RDP).
    Takes approximately 5 minutes.
#>

# ============================================================
# CONFIGURATION - Pre-filled with your Azure details
# ============================================================
$subscriptionId = "68152312-00a2-446b-b762-21750bd1440f"
$resourceGroup  = "arc-demo-rg"
$tenantId       = "17ab6ae4-62da-43e0-9140-dddeb0a17bf0"
$location       = "eastus"
$machineName    = "ArcDemo-SQLServer"
# Load from environment or prompt user
$servicePrincipalId = $env:AZURE_SP_APP_ID
$servicePrincipalSecret = $env:AZURE_SP_SECRET
if (-not $servicePrincipalId) { $servicePrincipalId = Read-Host "Enter Service Principal App ID" }
if (-not $servicePrincipalSecret) { $servicePrincipalSecret = Read-Host "Enter Service Principal Secret" -AsSecureString | ConvertFrom-SecureString -AsPlainText }

# ============================================================
# STEP 1: Download and install the Azure Connected Machine agent
# ============================================================
Write-Host "=== Step 1: Installing Azure Arc Agent ===" -ForegroundColor Cyan

$agentInstaller = "$env:TEMP\AzureConnectedMachineAgent.msi"
Write-Host "Downloading Arc agent..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri "https://aka.ms/AzureConnectedMachineAgent" -OutFile $agentInstaller -UseBasicParsing

Write-Host "Installing Arc agent..."
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$agentInstaller`" /quiet /l*v `"$env:TEMP\arc-install.log`""
Write-Host "Arc agent installed!" -ForegroundColor Green

# ============================================================
# STEP 2: Connect this machine to Azure Arc
# ============================================================
Write-Host ""
Write-Host "=== Step 2: Connecting to Azure Arc ===" -ForegroundColor Cyan

& "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" connect `
    --service-principal-id $servicePrincipalId `
    --service-principal-secret $servicePrincipalSecret `
    --resource-group $resourceGroup `
    --tenant-id $tenantId `
    --location $location `
    --subscription-id $subscriptionId `
    --cloud "AzureCloud" `
    --tags "Purpose=ArcDemo,Platform=AWS,OS=WindowsServer2022,SQL=Express2022"

# Verify connection
$status = & "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" show
Write-Host $status
Write-Host "Machine connected to Azure Arc!" -ForegroundColor Green

# ============================================================
# STEP 3: Install SQL Server extension for Arc
# ============================================================
Write-Host ""
Write-Host "=== Step 3: Installing SQL Server Extension ===" -ForegroundColor Cyan
Write-Host "This enables Azure to discover and manage your SQL Server instance."
Write-Host "(This step takes 2-3 minutes...)"

# Install Azure CLI for extension management
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Azure CLI..."
    $cliInstaller = "$env:TEMP\AzureCLI.msi"
    Invoke-WebRequest -Uri "https://aka.ms/installazurecliwindows" -OutFile $cliInstaller -UseBasicParsing
    Start-Process msiexec.exe -Wait -ArgumentList "/I `"$cliInstaller`" /quiet"
    $env:Path += ";C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin;C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin"
}

# Login with service principal
az login --service-principal -u $servicePrincipalId -p $servicePrincipalSecret --tenant $tenantId 2>$null | Out-Null
az account set --subscription $subscriptionId

# Install the SQL Server extension
az connectedmachine extension create `
    --machine-name $machineName `
    --resource-group $resourceGroup `
    --name "WindowsAgent.SqlServer" `
    --type "WindowsAgent.SqlServer" `
    --publisher "Microsoft.AzureData" `
    --location $location `
    --settings '{\"SqlManagement\":{\"IsEnabled\":true}}'

# ============================================================
# DONE!
# ============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  ONBOARDING COMPLETE!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "Verify in Azure Portal:" -ForegroundColor Yellow
Write-Host "  Arc Servers: https://portal.azure.com/#blade/HubsExtension/BrowseResource/resourceType/Microsoft.HybridCompute%2Fmachines"
Write-Host "  Arc SQL:     https://portal.azure.com/#blade/HubsExtension/BrowseResource/resourceType/Microsoft.AzureArcData%2FsqlServerInstances"
Write-Host ""
Write-Host "Your SQL Server will appear in the portal within 5 minutes."
