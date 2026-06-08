# Mass Deployment: Azure Arc at Scale

> Deploy Azure Arc to dozens or hundreds of SQL Servers simultaneously using AWS Systems Manager (SSM), CSV-driven automation, or Terraform.

## 📋 Deployment Options

| Method | Best For | Complexity |
|--------|----------|------------|
| **AWS Systems Manager (SSM)** | AWS EC2 fleets already using SSM | Low |
| **CSV + PowerShell loop** | Any environment, simple scripting | Low |
| **Terraform** | Infrastructure-as-code teams | Medium |
| **Group Policy (GPO)** | On-premises Active Directory environments | Medium |

---

## 🏗️ Architecture (At Scale)

```
┌─────────────────────────────────────────────────────────────┐
│                      Azure Portal                            │
│         ┌─────────────────────────────────────┐             │
│         │  Azure Arc (Resource Manager)        │             │
│         │  - 50+ SQL Servers visible           │             │
│         │  - Policy applied uniformly          │             │
│         │  - Defender across all instances      │             │
│         └──────────────────┬──────────────────┘             │
└────────────────────────────┼────────────────────────────────┘
                             │ Outbound HTTPS (443)
        ┌────────────────────┼──────────────────────┐
        │              AWS Account                   │
        │                    │                       │
        │  ┌─────────────────▼────────────────────┐ │
        │  │     AWS Systems Manager (SSM)         │ │
        │  │     Run Command → All tagged EC2s     │ │
        │  └─────────────────┬────────────────────┘ │
        │                    │                       │
        │    ┌───────┬───────┼───────┬───────┐      │
        │    │       │       │       │       │      │
        │  ┌─▼─┐  ┌─▼─┐  ┌─▼─┐  ┌─▼─┐  ┌─▼─┐   │
        │  │EC2│  │EC2│  │EC2│  │EC2│  │EC2│   │
        │  │SQL│  │SQL│  │SQL│  │SQL│  │SQL│   │
        │  └───┘  └───┘  └───┘  └───┘  └───┘   │
        │                                        │
        └────────────────────────────────────────┘
```

---

## 🚀 Method 1: AWS Systems Manager (Recommended for AWS)

**Prerequisites:**
- SSM Agent installed on all EC2 instances (default on Windows AMIs)
- EC2 instances tagged for targeting (e.g., `ArcOnboard=true`)
- IAM role with `AmazonSSMManagedInstanceCore` attached to instances

### Steps:

1. Tag your target EC2s in AWS Console or CLI
2. Run the SSM command (see `ssm-arc-onboard.ps1`)
3. Monitor in AWS Console → Systems Manager → Run Command
4. Verify in Azure Portal → Azure Arc → Servers

```bash
# Deploy to all EC2s tagged ArcOnboard=true
aws ssm send-command \
    --document-name "AWS-RunPowerShellScript" \
    --targets "Key=tag:ArcOnboard,Values=true" \
    --parameters file://ssm-parameters.json \
    --timeout-seconds 600 \
    --max-concurrency "10" \
    --max-errors "5"
```

---

## 🚀 Method 2: CSV-Driven PowerShell

For environments where you have a list of servers (any cloud or on-prem):

1. Fill in `servers.csv` with your server inventory
2. Run `csv-mass-deploy.ps1`
3. Script connects to each server via WinRM and installs Arc

---

## 🚀 Method 3: Terraform

For teams that want repeatable infrastructure-as-code:

1. Define your EC2 fleet in `terraform/main.tf`
2. User data script auto-installs Arc agent on boot
3. Every new server is Arc-enabled from the moment it launches

---

## 📁 Files in This Folder

| File | Description |
|------|-------------|
| `ssm-arc-onboard.ps1` | Script deployed via AWS SSM to each instance |
| `ssm-parameters.json` | SSM Run Command parameters file |
| `send-ssm-command.ps1` | Orchestrator: sends SSM command to tagged fleet |
| `csv-mass-deploy.ps1` | CSV-driven deployment over WinRM |
| `servers.csv` | Example server inventory |
| `terraform/main.tf` | Terraform for EC2 fleet with Arc auto-onboard |
| `terraform/variables.tf` | Terraform variables |
| `terraform/user-data.ps1` | EC2 user data bootstrap script |

---

## ⚠️ Important Notes

- **Service Principal** credentials must be stored securely (AWS Secrets Manager, Azure Key Vault, or SSM Parameter Store)
- **Rate limits:** Azure ARM has API throttling. Use `--max-concurrency` to limit parallel onboarding (10-20 at a time recommended)
- **Network:** All EC2s need outbound HTTPS to `*.his.arc.azure.com`, `*.guestconfiguration.azure.com`, `login.microsoftonline.com`
- **Agent auto-update:** Arc agent auto-updates by default. Pin versions if needed for change control.
