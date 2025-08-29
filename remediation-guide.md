# 🛡️ Remediation Guide

This guide lists quick steps to reduce or clear common Inspector findings.

## EC2 (OS/Package CVEs)

- **Patch OS packages**: Run `scripts/06-remediate-ec2.sh` (SSM Run Command → `dnf/yum update -y`).  
- **Restart services** if updates affect runtime libs.  
- **Re-scan**: Inspector will auto-refresh; wait a few minutes and re-check `scripts/05-list-findings.sh`.

## ECR (Container Image CVEs)

- **Pull latest base images** and **rebuild** your image.  
- **Pin minimal versions** and regularly rebuild CI.  
- **Retag** and **push** to ECR; Inspector container scan will refresh.

## Network Exposure / Posture

- Close wide‑open security groups (0.0.0.0/0) unless strictly required.  
- Use **WAF / ALB** and **private subnets** where possible.  
- Adopt **least privilege** security groups and NACLs.

## Security Hub

- Use the Security Hub dashboard to **triage and prioritize** across services.  
- Create **custom insights** and **automations** (Lambda/EventBridge) for recurring classes of issues.
