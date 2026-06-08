<#
.SYNOPSIS
    Install Azure Arc agent and register SQL Server with Azure Arc.

.DESCRIPTION
    Run this script ON THE EC2 INSTANCE (via RDP) to:
    1. Install the Azure Connected Machine agent
    2. Connect the server to Azure Arc
    3. Install the SQL Server extension for Arc

.NOTES
    Prerequisites:
    - Run on the EC2 instance (not your local machine)
    - Azure CLI installed on EC2 (script will install if missing)
    - Azure subscription with required resource providers registered

.EXAMPLE
    .\02-onboard-azure-arc.ps1 -SubscriptionId "your-sub-id" -ResourceGroup "arc-demo-rg" -TenantId "your-tenant-id"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [Parameter(Mandatory=$true)]
    [string]$TenantId,

    [string]$ResourceGroup = "arc-demo-rg",
    [string]$Location = "eastus",
    [string]$MachineName = $env:COMPUTERNAME
)

Write-Host "=== Azure Arc Onboarding for SQL Server ===" -ForegroundColor Cyan
Write-Host "Subscription: $SubscriptionId"
Write-Host "Resource Group: $ResourceGroup"
Write-Host "Location: $Location"
Write-Host "Machine Name: $MachineName"
Write-Host ""

# Step 1: Install Azure CLI if not present
Write-Host "[1/6] Checking Azure CLI..." -ForegroundColor Yellow
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host "  Installing Azure CLI..."
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi
    Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
    Remove-Item .\AzureCLI.msi
    $env:Path += ";C:\Program Files (x86)\Microsoft SDKs\Azure\CLI2\wbin"
    Write-Host "  Azure CLI installed."
} else {
    Write-Host "  Azure CLI already installed."
}

# Step 2: Login to Azure
Write-Host "[2/6] Logging into Azure..." -ForegroundColor Yellow
Write-Host "  A browser window will open for authentication."
az login --tenant $TenantId
az account set --subscription $SubscriptionId

# Step 3: Register resource providers
Write-Host "[3/6] Registering resource providers..." -ForegroundColor Yellow
az provider register --namespace Microsoft.HybridCompute --wait 2>$null
az provider register --namespace Microsoft.GuestConfiguration --wait 2>$null
az provider register --namespace Microsoft.AzureArcData --wait 2>$null
Write-Host "  Resource providers registered."

# Step 4: Create resource group (if it doesn't exist)
Write-Host "[4/6] Creating resource group..." -ForegroundColor Yellow
az group create --name $ResourceGroup --location $Location --output none 2>$null
Write-Host "  Resource group: $ResourceGroup ($Location)"

# Step 5: Install Azure Connected Machine Agent
Write-Host "[5/6] Installing Azure Arc agent..." -ForegroundColor Yellow

# Download the Arc agent installer
$agentUrl = "https://aka.ms/AzureConnectedMachineAgent"
$installerPath = "$env:TEMP\AzureConnectedMachineAgent.msi"
Write-Host "  Downloading Arc agent..."
Invoke-WebRequest -Uri $agentUrl -OutFile $installerPath -UseBasicParsing

Write-Host "  Installing Arc agent..."
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installerPath`" /quiet /l*v `"$env:TEMP\arc-agent-install.log`""

# Connect the machine to Azure Arc
Write-Host "  Connecting machine to Azure Arc..."
& "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" connect `
    --resource-group $ResourceGroup `
    --tenant-id $TenantId `
    --location $Location `
    --subscription-id $SubscriptionId `
    --cloud "AzureCloud" `
    --tags "Purpose=ArcDemo,Platform=AWS,SQL=Express2022"

Write-Host "  Machine connected to Azure Arc!"

# Step 6: Install SQL Server extension
Write-Host "[6/6] Installing SQL Server Arc extension..." -ForegroundColor Yellow
az connectedmachine extension create `
    --machine-name $MachineName `
    --resource-group $ResourceGroup `
    --name "WindowsAgent.SqlServer" `
    --type "WindowsAgent.SqlServer" `
    --publisher "Microsoft.AzureData" `
    --location $Location `
    --settings '{\"SqlManagement\":{\"IsEnabled\":true}}'

Write-Host ""
Write-Host "=== ONBOARDING COMPLETE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Verify in Azure Portal:" -ForegroundColor Cyan
Write-Host "  1. Azure Arc > Servers > $MachineName"
Write-Host "  2. Azure Arc > SQL Servers > (your SQL instance)"
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Yellow
Write-Host "  - Enable Microsoft Defender for SQL"
Write-Host "  - Run SQL Best Practices Assessment"
Write-Host "  - Apply Azure Policies"
Write-Host "  - Configure Azure Monitor"
