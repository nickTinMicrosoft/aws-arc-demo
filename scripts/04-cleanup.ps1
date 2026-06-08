<#
.SYNOPSIS
    Tear down all AWS and Azure resources created for the Arc demo.

.DESCRIPTION
    Cleans up:
    - EC2 instance
    - Security group
    - Key pair
    - Azure resource group (and all contained resources)

.EXAMPLE
    .\04-cleanup.ps1
#>

param(
    [string]$ResourceGroup = "arc-demo-rg"
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

Write-Host "=== Cleaning Up Arc Demo Resources ===" -ForegroundColor Cyan
Write-Host ""

# AWS Cleanup
Write-Host "[AWS] Terminating EC2 instance..." -ForegroundColor Yellow
$instanceId = $env:EC2_INSTANCE_ID
if ($instanceId) {
    aws ec2 terminate-instances --instance-ids $instanceId --output text 2>$null
    Write-Host "  Terminated: $instanceId"
    aws ec2 wait instance-terminated --instance-ids $instanceId 2>$null
    Write-Host "  Instance terminated."
}

Write-Host "[AWS] Deleting security group..." -ForegroundColor Yellow
$sgId = $env:AWS_SECURITY_GROUP_ID
if ($sgId) {
    Start-Sleep -Seconds 5  # Wait for ENI detachment
    aws ec2 delete-security-group --group-id $sgId 2>$null
    Write-Host "  Deleted: $sgId"
}

Write-Host "[AWS] Deleting key pair..." -ForegroundColor Yellow
aws ec2 delete-key-pair --key-name "arc-demo-key" 2>$null
Write-Host "  Deleted: arc-demo-key"

# Azure Cleanup
Write-Host ""
Write-Host "[Azure] Deleting resource group (and all Arc resources)..." -ForegroundColor Yellow
az group delete --name $ResourceGroup --yes --no-wait 2>$null
Write-Host "  Deletion initiated: $ResourceGroup (runs in background)"

Write-Host ""
Write-Host "=== CLEANUP COMPLETE ===" -ForegroundColor Green
Write-Host "Note: Azure resource group deletion may take a few minutes to fully complete."
