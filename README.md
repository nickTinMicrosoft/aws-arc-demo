# Azure Arc SQL Server Demo (AWS)

> Demonstrates managing SQL Server instances running on AWS EC2 using Azure Arc — a single pane of glass for hybrid/multicloud governance, security, and monitoring.

## 🎯 What This Demo Shows

| Scenario | What You'll Demo |
|----------|-----------------|
| **Onboarding** | Register an AWS SQL Server with Azure Arc in minutes |
| **Governance** | Apply Azure Policy to enforce compliance across clouds |
| **Security** | Microsoft Defender for SQL — threat detection & vulnerability assessment |
| **Monitoring** | Azure Monitor dashboards for performance metrics |
| **Assessment** | SQL Best Practices Assessment with actionable recommendations |

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Azure Portal                              │
│  ┌──────────┐  ┌──────────────┐  ┌─────────┐  ┌────────────┐  │
│  │  Azure   │  │  Defender    │  │  Azure  │  │   Azure    │  │
│  │  Policy  │  │  for SQL     │  │ Monitor │  │ Assessment │  │
│  └────┬─────┘  └──────┬───────┘  └────┬────┘  └─────┬──────┘  │
│       └────────────────┼───────────────┼─────────────┘          │
│                        │     Azure Arc │                         │
└────────────────────────┼───────────────┼────────────────────────┘
                         │               │
                    ┌────┴───────────────┴────┐
                    │   Arc Agent + SQL Ext   │
                    │                         │
                    │  ┌───────────────────┐  │
                    │  │  SQL Server 2022  │  │
                    │  │  Express Edition  │  │
                    │  └───────────────────┘  │
                    │                         │
                    │  Windows Server 2022    │
                    │  AWS EC2 (t3.small)     │
                    └─────────────────────────┘
                         AWS us-east-1
```

## 📋 Prerequisites

- **AWS Account** with IAM user (AdministratorAccess policy)
- **Azure Subscription** with Owner/Contributor role
- **AWS CLI** installed locally (`pip install awscli` or [download](https://aws.amazon.com/cli/))
- **Azure CLI** installed on EC2 (script handles this)
- **RDP Client** (Windows built-in `mstsc` or similar)

## 🚀 Quick Start

### 1. Clone and Configure

```bash
git clone https://github.com/nickTinMicrosoft/aws-arc-demo.git
cd aws-arc-demo
cp .env.example .env
# Edit .env with your AWS credentials
```

### 2. Provision AWS Infrastructure

```powershell
.\scripts\01-provision-aws-ec2.ps1
```

This creates:
- Security group (RDP access)
- EC2 key pair
- Windows Server 2022 + SQL Server 2022 Express instance

### 3. Onboard to Azure Arc

RDP into the EC2 instance (`mstsc /v:<your-ec2-public-ip>`, login as `Administrator`), then open **PowerShell as Administrator** and run:

```powershell
# Step A: Set your service principal credentials (from .env)
$env:AZURE_SP_APP_ID = "<your-service-principal-app-id>"
$env:AZURE_SP_SECRET = "<your-service-principal-secret>"

# Step B: Download and run the onboarding script
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nickTinMicrosoft/aws-arc-demo/master/scripts/ec2-run-this.ps1" -OutFile "C:\ec2-run-this.ps1" -UseBasicParsing
& "C:\ec2-run-this.ps1"
```

**What the script does (takes ~5 minutes):**
1. Downloads and installs the Azure Connected Machine agent
2. Connects the EC2 machine to Azure Arc using the service principal
3. Installs Azure CLI (if not present)
4. Installs the SQL Server extension so Arc discovers your SQL instance

**Verify onboarding succeeded:**
- Azure Portal → [Azure Arc > Servers](https://portal.azure.com/#blade/HubsExtension/BrowseResource/resourceType/Microsoft.HybridCompute%2Fmachines) → you should see `ArcDemo-SQLServer`
- Azure Portal → [Azure Arc > SQL Servers](https://portal.azure.com/#blade/HubsExtension/BrowseResource/resourceType/Microsoft.AzureArcData%2FsqlServerInstances) → you should see the SQL Express instance

> **Note:** The SQL Server instance may take up to 5 additional minutes to appear after the machine is registered.

#### Alternative: Manual onboarding (without script)

If you prefer step-by-step:

```powershell
# 1. Download the Arc agent
Invoke-WebRequest -Uri "https://aka.ms/AzureConnectedMachineAgent" -OutFile "$env:TEMP\AzureConnectedMachineAgent.msi" -UseBasicParsing

# 2. Install the agent
Start-Process msiexec.exe -Wait -ArgumentList "/i `"$env:TEMP\AzureConnectedMachineAgent.msi`" /quiet"

# 3. Connect to Azure Arc
& "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" connect `
    --service-principal-id "<your-sp-app-id>" `
    --service-principal-secret "<your-sp-secret>" `
    --resource-group "arc-demo-rg" `
    --tenant-id "<your-tenant-id>" `
    --location "eastus" `
    --subscription-id "<your-subscription-id>" `
    --cloud "AzureCloud" `
    --tags "Purpose=ArcDemo,Platform=AWS,OS=WindowsServer2022,SQL=Express2022"

# 4. Verify connection
& "$env:ProgramW6432\AzureConnectedMachineAgent\azcmagent.exe" show

# 5. Install SQL Server extension (requires Azure CLI)
az connectedmachine extension create `
    --machine-name "ArcDemo-SQLServer" `
    --resource-group "arc-demo-rg" `
    --name "WindowsAgent.SqlServer" `
    --type "WindowsAgent.SqlServer" `
    --publisher "Microsoft.AzureData" `
    --location "eastus" `
    --settings '{\"SqlManagement\":{\"IsEnabled\":true}}'
```

### 4. Configure Demo Features

```powershell
.\scripts\03-configure-arc-features.ps1 `
    -SubscriptionId "your-subscription-id" `
    -ResourceGroup "arc-demo-rg"
```

### 5. Demo Time! 🎬

Open the Azure Portal and walk through:
1. **Azure Arc > Servers** — See your AWS machine as an Azure resource
2. **Azure Arc > SQL Servers** — Manage the SQL instance
3. **Security Center** — Defender alerts and vulnerability scan
4. **Azure Policy > Compliance** — Governance state
5. **Azure Monitor** — Performance dashboards

### 6. Cleanup

```powershell
.\scripts\04-cleanup.ps1
```

## 💰 Cost Estimate

| Resource | Cost |
|----------|------|
| EC2 t3.small (Free Tier) | $0.00 (first 12 months) |
| EBS 80GB gp3 | ~$6.40/month |
| SQL Server Express license | Free |
| Azure Arc (basic) | Free |
| Defender for SQL | ~$15/server/month |
| **Demo total (run for 1 day)** | **< $2** |

## 📂 Project Structure

```
aws-arc-demo/
├── .env.example          # Template for environment variables
├── .env                  # Your actual credentials (git-ignored)
├── .gitignore            # Excludes secrets and keys
├── arc-demo-key.pem      # EC2 key pair (git-ignored)
├── README.md             # This file
└── scripts/
    ├── 01-provision-aws-ec2.ps1      # Create AWS resources
    ├── 02-onboard-azure-arc.ps1      # Install Arc agent on EC2
    ├── 03-configure-arc-features.ps1 # Enable Defender, Monitor, Policy
    └── 04-cleanup.ps1                # Tear down everything
```

## 🗣️ Demo Talking Points

- **"Single pane of glass"** — Manage SQL anywhere from Azure Portal
- **"No migration needed"** — Arc manages in-place, SQL stays on AWS
- **"Enterprise security everywhere"** — Same Defender, same policies, any cloud
- **"5-minute onboarding"** — Install agent, see it in Azure immediately
- **"License visibility"** — Track all SQL licenses across your estate

## ⚠️ Important Notes

- **RDP access** is open to all IPs for demo convenience. Restrict to your IP for production.
- **Tear down after demo** to avoid ongoing costs.
- **SQL Server Express** is used (free) — Arc features work identically on Standard/Enterprise.
- The `.pem` key and `.env` are git-ignored. Never commit credentials.

## 📚 References

- [Azure Arc Overview](https://learn.microsoft.com/en-us/azure/azure-arc/overview)
- [Azure Arc-enabled SQL Server](https://learn.microsoft.com/en-us/sql/sql-server/azure-arc/overview)
- [Connected Machine Agent](https://learn.microsoft.com/en-us/azure/azure-arc/servers/agent-overview)
- [Defender for SQL](https://learn.microsoft.com/en-us/azure/defender-for-cloud/defender-for-sql-introduction)
