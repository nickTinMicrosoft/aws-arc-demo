<#
.SYNOPSIS
    Provision AWS EC2 instance with Windows Server 2022 + SQL Server 2022 Express
    for Azure Arc demo.

.DESCRIPTION
    This script creates all AWS resources needed for the Azure Arc SQL Server demo:
    - Security Group (RDP access)
    - Key Pair (for Windows password decryption)
    - EC2 Instance (Windows Server 2022 + SQL Server 2022 Express)

.NOTES
    Prerequisites:
    - AWS CLI installed and configured (aws configure)
    - IAM user with EC2 permissions (AdministratorAccess recommended for demo)

.EXAMPLE
    .\01-provision-aws-ec2.ps1
#>

# Load environment variables if .env exists
$envFile = Join-Path $PSScriptRoot "..\.env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim())
        }
    }
}

$region = $env:AWS_DEFAULT_REGION ?? "us-east-1"
$keyPairName = "arc-demo-key"
$sgName = "arc-demo-sg"
$instanceName = "ArcDemo-SQLServer"

# AMI: Windows Server 2022 + SQL Server 2022 Express (us-east-1, May 2026)
$amiId = "ami-0ffa0f075391b705d"

Write-Host "=== Azure Arc SQL Server Demo - AWS Provisioning ===" -ForegroundColor Cyan
Write-Host "Region: $region"
Write-Host ""

# Step 1: Get default VPC
Write-Host "[1/5] Getting default VPC..." -ForegroundColor Yellow
$vpcId = (aws ec2 describe-vpcs --region $region --filters "Name=isDefault,Values=true" --query "Vpcs[0].VpcId" --output text 2>$null).Trim()
Write-Host "  VPC: $vpcId"

# Step 2: Create Security Group
Write-Host "[2/5] Creating Security Group..." -ForegroundColor Yellow
$sgOutput = aws ec2 create-security-group `
    --region $region `
    --group-name $sgName `
    --description "Security group for Azure Arc SQL Server demo - allows RDP" `
    --vpc-id $vpcId `
    --output json 2>$null | ConvertFrom-Json

$sgId = $sgOutput.GroupId
Write-Host "  Security Group: $sgId"

# Add RDP rule (restrict to your IP in production!)
aws ec2 authorize-security-group-ingress `
    --region $region `
    --group-id $sgId `
    --protocol tcp `
    --port 3389 `
    --cidr "0.0.0.0/0" 2>$null | Out-Null
Write-Host "  RDP (3389) opened to 0.0.0.0/0 (restrict for production!)"

# Step 3: Create Key Pair
Write-Host "[3/5] Creating Key Pair..." -ForegroundColor Yellow
$pemPath = Join-Path $PSScriptRoot "..\arc-demo-key.pem"
aws ec2 create-key-pair `
    --region $region `
    --key-name $keyPairName `
    --query "KeyMaterial" `
    --output text 2>$null | Out-File -FilePath $pemPath -Encoding ASCII
Write-Host "  Key saved to: $pemPath"

# Step 4: Launch EC2 Instance
Write-Host "[4/5] Launching EC2 Instance..." -ForegroundColor Yellow
Write-Host "  AMI: $amiId (Windows Server 2022 + SQL Server 2022 Express)"
Write-Host "  Type: t3.small (2 vCPU, 2GB RAM, Free Tier eligible)"

$instanceJson = aws ec2 run-instances `
    --region $region `
    --image-id $amiId `
    --instance-type "t3.small" `
    --key-name $keyPairName `
    --security-group-ids $sgId `
    --block-device-mappings '[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":80,\"VolumeType\":\"gp3\"}}]' `
    --tag-specifications "[{\`"ResourceType\`":\`"instance\`",\`"Tags\`":[{\`"Key\`":\`"Name\`",\`"Value\`":\`"$instanceName\`"},{\`"Key\`":\`"Purpose\`",\`"Value\`":\`"Azure-Arc-Demo\`"}]}]" `
    --query "Instances[0].InstanceId" `
    --output text 2>$null

$instanceId = $instanceJson.Trim()
Write-Host "  Instance ID: $instanceId"

# Step 5: Wait for instance and get details
Write-Host "[5/5] Waiting for instance to be running..." -ForegroundColor Yellow
aws ec2 wait instance-running --region $region --instance-ids $instanceId 2>$null

$details = aws ec2 describe-instances `
    --region $region `
    --instance-ids $instanceId `
    --query "Reservations[0].Instances[0].{PublicIP:PublicIpAddress,State:State.Name}" `
    --output json 2>$null | ConvertFrom-Json

Write-Host "  State: $($details.State)"
Write-Host "  Public IP: $($details.PublicIP)"

# Wait for Windows password
Write-Host ""
Write-Host "Waiting for Windows password (this takes ~4 minutes)..." -ForegroundColor Yellow
$maxAttempts = 12
$attempt = 0
$password = ""
while ($attempt -lt $maxAttempts -and [string]::IsNullOrEmpty($password)) {
    Start-Sleep -Seconds 30
    $attempt++
    $pwData = aws ec2 get-password-data `
        --region $region `
        --instance-id $instanceId `
        --priv-launch-key $pemPath 2>$null | ConvertFrom-Json
    $password = $pwData.PasswordData
    Write-Host "  Attempt $attempt/$maxAttempts..."
}

Write-Host ""
Write-Host "=== PROVISIONING COMPLETE ===" -ForegroundColor Green
Write-Host ""
Write-Host "EC2 Instance Details:" -ForegroundColor Cyan
Write-Host "  Instance ID:  $instanceId"
Write-Host "  Public IP:    $($details.PublicIP)"
Write-Host "  Username:     Administrator"
Write-Host "  Password:     $password"
Write-Host ""
Write-Host "RDP Connection:" -ForegroundColor Cyan
Write-Host "  mstsc /v:$($details.PublicIP)"
Write-Host ""
Write-Host "Next: RDP in, then run the Azure Arc onboarding script." -ForegroundColor Yellow
