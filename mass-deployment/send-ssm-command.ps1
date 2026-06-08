<#
.SYNOPSIS
    Orchestrator script: sends the Arc onboarding command to all tagged EC2 instances via AWS SSM.

.DESCRIPTION
    Targets all EC2 instances with the tag "ArcOnboard=true" and runs the
    onboarding script on them concurrently (with throttling).

.EXAMPLE
    .\send-ssm-command.ps1 -MaxConcurrency 10

.NOTES
    Prerequisites:
    - AWS CLI configured with credentials that have SSM permissions
    - Target EC2s must have SSM Agent running and proper IAM role
    - Tag your EC2 instances: ArcOnboard=true
#>

param(
    [int]$MaxConcurrency = 10,
    [int]$MaxErrors = 5,
    [int]$TimeoutSeconds = 600
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

Write-Host "=== Mass Deployment: Azure Arc via AWS SSM ===" -ForegroundColor Cyan
Write-Host "Max Concurrency: $MaxConcurrency"
Write-Host "Max Errors: $MaxErrors"
Write-Host "Timeout: ${TimeoutSeconds}s"
Write-Host ""

# Build the inline script (replaces placeholders in parameters)
$script = @"
`$params = @{
    SubscriptionId = '$($env:AZURE_SUBSCRIPTION_ID)'
    ResourceGroup = '$($env:AZURE_RESOURCE_GROUP)'
    TenantId = '$($env:AZURE_TENANT_ID)'
    Location = '$($env:AZURE_LOCATION)'
    ServicePrincipalId = '$($env:AZURE_SP_APP_ID)'
    ServicePrincipalSecret = '$($env:AZURE_SP_SECRET)'
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/nickTinMicrosoft/aws-arc-demo/master/mass-deployment/ssm-arc-onboard.ps1' -OutFile 'C:\arc-onboard.ps1' -UseBasicParsing
& C:\arc-onboard.ps1 @params
Remove-Item C:\arc-onboard.ps1 -Force
"@

# Write temporary parameters file
$paramsFile = "$env:TEMP\ssm-arc-params.json"
$paramsJson = @{
    commands = $script -split "`n"
    executionTimeout = @("$TimeoutSeconds")
} | ConvertTo-Json -Depth 3
$paramsJson | Out-File $paramsFile -Encoding UTF8

# Send SSM command to all tagged instances
Write-Host "Sending SSM Run Command to EC2s tagged 'ArcOnboard=true'..." -ForegroundColor Yellow
$commandOutput = aws ssm send-command `
    --document-name "AWS-RunPowerShellScript" `
    --targets "Key=tag:ArcOnboard,Values=true" `
    --parameters "file://$paramsFile" `
    --timeout-seconds $TimeoutSeconds `
    --max-concurrency "$MaxConcurrency" `
    --max-errors "$MaxErrors" `
    --comment "Azure Arc mass onboarding" `
    --output json 2>&1

$command = $commandOutput | ConvertFrom-Json
$commandId = $command.Command.CommandId

Write-Host ""
Write-Host "SSM Command sent!" -ForegroundColor Green
Write-Host "  Command ID: $commandId"
Write-Host "  Targets: All EC2s with tag ArcOnboard=true"
Write-Host ""
Write-Host "Monitor progress:" -ForegroundColor Yellow
Write-Host "  AWS Console: Systems Manager > Run Command > Command history"
Write-Host "  CLI: aws ssm list-command-invocations --command-id $commandId --details"
Write-Host ""
Write-Host "After completion, verify in Azure Portal:" -ForegroundColor Yellow
Write-Host "  Azure Arc > Servers"
Write-Host ""

# Cleanup
Remove-Item $paramsFile -Force -ErrorAction SilentlyContinue

# Optionally wait and show status
Write-Host "Waiting 60s for initial results..." -ForegroundColor Yellow
Start-Sleep -Seconds 60

$invocations = aws ssm list-command-invocations `
    --command-id $commandId `
    --query "CommandInvocations[].{Instance:InstanceId,Status:Status,Detail:StatusDetails}" `
    --output table 2>&1

Write-Host $invocations
