SHELL := /bin/bash
.DEFAULT_GOAL := help

REGION ?= $(shell aws configure get region 2>/dev/null || echo us-east-1)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' Makefile | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

bootstrap: ## Create IAM/SG/EC2 and prepare environment
	bash scripts/01-bootstrap.sh

enable-inspector: ## Enable Inspector v2 resource types
	bash scripts/02-enable-inspector.sh

push-vuln: ## Push vulnerable image to ECR for scanning
	bash scripts/03-push-vuln-image.sh

alerts: ## Set up Security Hub + EventBridge -> SNS
	bash scripts/04-setup-sns-securityhub.sh

findings: ## List Inspector and Security Hub findings
	bash scripts/05-list-findings.sh

remediate: ## Patch EC2 via SSM Run Command
	bash scripts/06-remediate-ec2.sh

cleanup: ## Tear down resources (keeps Security Hub by default)
	bash scripts/99-cleanup.sh
