# 🔹 Vulnerability Management with Amazon Inspector — Full Project

This repository contains **end‑to‑end, GitHub‑ready code and steps** to stand up a demo of **Amazon Inspector v2** across **EC2** and **ECR**, wire up **Security Hub** + **SNS** for alerts, generate findings with an intentionally vulnerable container image, and then **remediate** via **AWS Systems Manager (SSM)**.

> ⚠️ **Safety & Cost Notice**  
> • Run this only in a **non‑production AWS account**.  
> • You may incur charges (EC2, ECR, SNS, Security Hub).  
> • Use the included `scripts/99-cleanup.sh` to tear down resources when you’re done.  
> • You are responsible for your account security and costs.

---

## 📦 What you’ll build

- **EC2** instance (Amazon Linux) with SSM and a basic web server (to have packages to scan).
- **Amazon Inspector v2** enabled for **EC2, ECR, Lambda**.
- **ECR** private repo with a **known vulnerable image** (e.g., Juice Shop).
- **Security Hub** integrated and an **EventBridge → SNS** alerting pipeline.
- **SSM Run Command** based remediation for EC2.
- Simple **CLI scripts** to orchestrate the entire flow.

---

## 🧰 Prerequisites

- macOS/Linux terminal (Windows WSL is fine).
- **AWS CLI v2**, **Docker**, **jq** installed and configured.
- AWS credentials with permissions for: EC2, IAM, SSM, ECR, SNS, Events, Inspector2, SecurityHub.
- Default region set (`aws configure get region`). You can override via `AWS_REGION` env var in all scripts.

---

## 🚀 Quickstart

```bash
git clone https://github.com/atulkamble/aws-inspector.git
cd aws-inspector-project/scripts

# 1) Bootstrap: IAM role/profile, SG, EC2 (t3.micro), httpd, SSM, etc.
chmod +x 01-bootstrap.sh
./01-bootstrap.sh

# 2) Enable Inspector (EC2/ECR/Lambda) and verify account status
chmod +x 02-enable-inspector.sh
./02-enable-inspector.sh

# 3) Push a vulnerable image to ECR to generate container findings
#    (uses bkimminich/juice-shop:latest by default)
chmod +x 03-push-vuln-image.sh
./03-push-vuln-image.sh

# 4) Wire up Security Hub + EventBridge → SNS alerts (set your email)
export ALERT_EMAIL="atul_kamble@hotmail.com"
chmod +x 04-setup-sns-securityhub.sh
./04-setup-sns-securityhub.sh

# 5) List findings (Inspector v2 and Security Hub views)
chmod +x 05-list-findings.sh
./05-list-findings.sh

# 6) Remediate EC2 (via SSM Run Command), then re-check findings
chmod +x 06-remediate-ec2.sh
./06-remediate-ec2.sh
./05-list-findings.sh

# 7) Clean up (optionally keep Security Hub by default)
chmod +x 99-cleanup.sh
./99-cleanup.sh
```

> 💡 Tip: open the **Amazon Inspector**, **ECR**, and **Security Hub** consoles to watch resources and findings appear in near‑real time (a few minutes after each step).

---

## 🗂️ Repository Structure

```
aws-inspector-project/
├── README.md
├── remediation-guide.md
├── Makefile
├── .gitignore
└── scripts/
    ├── 01-bootstrap.sh
    ├── 02-enable-inspector.sh
    ├── 03-push-vuln-image.sh
    ├── 04-setup-sns-securityhub.sh
    ├── 05-list-findings.sh
    ├── 06-remediate-ec2.sh
    └── 99-cleanup.sh
```

---

## 📝 Notes & Best Practices

- **Inspector v2** continuously scans supported resources; findings may take a few minutes to appear.  
- For **EC2**, ensure the instance is **SSM‑managed** (role + agent) and keep it online long enough for scans.  
- For **ECR**, any image you push will be **automatically scanned** (no manual trigger required).  
- **EventBridge → SNS** pipeline here targets **Security Hub imported findings** (including Inspector).  
- Use **non‑prod** accounts and tear down with `99-cleanup.sh` when done.

See [`remediation-guide.md`](./remediation-guide.md) for additional tips.
