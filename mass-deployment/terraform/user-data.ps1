<powershell>
# Azure Arc Auto-Onboarding User Data Script
# This runs on first boot of each EC2 instance.

$ErrorActionPreference = "Continue"
$logFile = "C:\arc-onboard-log.txt"
Start-Transcript -Path $logFile

Write-Output "=== Azure Arc Auto-Onboarding ==="
Write-Output "Machine: $env:COMPUTERNAME"
Write-Output "Time: $(Get-Date)"

# Wait for SQL Server to be ready
Write-Output "Waiting for SQL Server service..."
$attempts = 0
while ($attempts -lt 30) {
    $sqlService = Get-Service -Name "MSSQL`$SQLEXPRESS" -ErrorAction SilentlyContinue
    if ($sqlService -and $sqlService.Status -eq "Running") { break }
    Start-Sleep -Seconds 10
    $attempts++
}

# Download and install Azure Arc agent
Write-Output "Downloading Arc agent..."
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$installer = "C:\AzureConnectedMachineAgent.msi"
Invoke-WebRequest -Uri "https://aka.ms/AzureConnectedMachineAgent" -OutFile $installer -UseBasicParsing

Write-Output "Installing Arc agent..."
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$installer`" /quiet /l*v C:\arc-install.log"

# Connect to Azure Arc
Write-Output "Connecting to Azure Arc..."
& "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" connect `
    --service-principal-id "${sp_app_id}" `
    --service-principal-secret "${sp_secret}" `
    --resource-group "${resource_group}" `
    --tenant-id "${tenant_id}" `
    --location "${location}" `
    --subscription-id "${subscription_id}" `
    --cloud "AzureCloud" `
    --tags "Platform=AWS,DeployMethod=Terraform,OnboardDate=$(Get-Date -Format 'yyyy-MM-dd')"

if ($LASTEXITCODE -eq 0) {
    Write-Output "SUCCESS: Connected to Azure Arc!"
} else {
    Write-Output "ERROR: Arc connection failed. See logs at C:\ProgramData\AzureConnectedMachineAgent\Log"
}

# Cleanup installer
Remove-Item $installer -Force -ErrorAction SilentlyContinue

Stop-Transcript
</powershell>
