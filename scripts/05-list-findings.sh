#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-$(aws configure get region 2>/dev/null || echo us-east-1)}"

echo "================= Amazon Inspector v2 Findings (Top 20) ================="
aws inspector2 list-findings --max-results 20 --region "$AWS_REGION" 2>/dev/null | jq '.findings[] | {title, severity, resourceType, packageVulnerabilityDetails: (.packageVulnerabilityDetails | {vulnerabilityId, cvss: .cvss[].baseScore?} ) }' || echo "(none yet)"

echo
echo "================= Security Hub (Inspector) Findings (Top 20) ============="
aws securityhub get-findings --max-results 20 --filters '{"ProductName":[{"Value":"Inspector","Comparison":"EQUALS"}]}' --region "$AWS_REGION" 2>/dev/null | jq '.Findings[] | {Title, Severity: .Severity.Label, ProductName, Resource: .Resources[0].Id}' || echo "(none yet)"
