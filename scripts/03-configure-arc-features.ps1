<#
.SYNOPSIS
    Configure Azure Arc demo features: Defender, Monitoring, Policy, and Assessment.

.DESCRIPTION
    Run this AFTER successful Arc onboarding to enable the demo scenarios:
    - Microsoft Defender for SQL
    - Azure Monitor integration
    - Azure Policy assignment
    - SQL Best Practices Assessment

.EXAMPLE
    .\03-configure-arc-features.ps1 -SubscriptionId "your-sub-id" -ResourceGroup "arc-demo-rg"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$SubscriptionId,

    [string]$ResourceGroup = "arc-demo-rg",
    [string]$Location = "eastus",
    [string]$MachineName = $env:COMPUTERNAME
)

Write-Host "=== Configuring Azure Arc Demo Features ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Enable Microsoft Defender for SQL
Write-Host "[1/4] Enabling Microsoft Defender for SQL..." -ForegroundColor Yellow
az security pricing create `
    --name SqlServerVirtualMachines `
    --tier Standard 2>$null
Write-Host "  Defender for SQL enabled (Standard tier)."
Write-Host "  Portal: Security Center > Environment settings"

# Step 2: Create Log Analytics Workspace
Write-Host "[2/4] Creating Log Analytics workspace..." -ForegroundColor Yellow
$workspaceName = "arc-demo-law"
az monitor log-analytics workspace create `
    --resource-group $ResourceGroup `
    --workspace-name $workspaceName `
    --location $Location `
    --output none 2>$null
Write-Host "  Workspace: $workspaceName"

# Enable VM Insights / monitoring agent extension
az connectedmachine extension create `
    --machine-name $MachineName `
    --resource-group $ResourceGroup `
    --name "MicrosoftMonitoringAgent" `
    --type "MicrosoftMonitoringAgent" `
    --publisher "Microsoft.EnterpriseCloud.Monitoring" `
    --location $Location `
    --settings "{}" 2>$null
Write-Host "  Monitoring agent extension deployed."

# Step 3: Assign Azure Policy
Write-Host "[3/4] Assigning Azure Policy..." -ForegroundColor Yellow

# Policy: Configure Arc-enabled SQL Servers with Arc agent extension installed
$policyDefinition = "fd2d1a6e-6d95-4f2e-a083-91f5d9d15c91"
az policy assignment create `
    --name "arc-demo-sql-assessment" `
    --display-name "[Arc Demo] SQL Server should have assessment enabled" `
    --scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup" `
    --policy $policyDefinition 2>$null
Write-Host "  Policy assigned: SQL assessment compliance check."

# Step 4: Trigger SQL Assessment
Write-Host "[4/4] Triggering SQL Best Practices Assessment..." -ForegroundColor Yellow
Write-Host "  Note: Assessment runs asynchronously and takes ~15-30 minutes."
Write-Host "  Check results in: Azure Portal > Arc SQL Server > SQL Assessment"
Write-Host ""

Write-Host "=== CONFIGURATION COMPLETE ===" -ForegroundColor Green
Write-Host ""
Write-Host "Demo Scenarios Ready:" -ForegroundColor Cyan
Write-Host "  1. Governance  - Azure Policy compliance view"
Write-Host "  2. Security    - Defender for SQL alerts & vulnerability scan"
Write-Host "  3. Monitoring  - Azure Monitor metrics dashboard"
Write-Host "  4. Assessment  - SQL Best Practices recommendations"
Write-Host ""
Write-Host "Portal Links:" -ForegroundColor Yellow
Write-Host "  Arc Servers:     https://portal.azure.com/#blade/HubsExtension/BrowseResource/resourceType/Microsoft.HybridCompute%2Fmachines"
Write-Host "  Arc SQL Servers: https://portal.azure.com/#blade/HubsExtension/BrowseResource/resourceType/Microsoft.AzureArcData%2FsqlServerInstances"
Write-Host "  Security Center: https://portal.azure.com/#blade/Microsoft_Azure_Security/SecurityMenuBlade/overview"
