NAMESPACE  := moonpay

.DEFAULT_GOAL := help
.PHONY: create destroy show-ip cd-test-apply cd-test-revert cd-test-k8s-apply cd-test-k8s-revert help

create: ## Provision infrastructure (state bucket + Terraform + GKE creds)
	@bash scripts/create.sh

destroy: ## Tear down all infrastructure and delete state bucket
	@bash scripts/destroy.sh

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-22s %s\n", $$1, $$2}'

show-ip: ## Print the external LoadBalancer IP
	@kubectl -n $(NAMESPACE) get svc nextjs \
		-o jsonpath='{.status.loadBalancer.ingress[0].ip}'
	@echo

cd-test-apply: ## Push a test change (new currency + heading) to trigger CD
	@bash scripts/cd-test-apply.sh

cd-test-revert: ## Revert the test change and trigger CD
	@bash scripts/cd-test-revert.sh

cd-test-k8s-apply: ## Push a k8s-only change (scale + probe), no approval
	@bash scripts/cd-test-k8s-apply.sh

cd-test-k8s-revert: ## Revert the k8s-only change, no approval
	@bash scripts/cd-test-k8s-revert.sh
