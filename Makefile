NAMESPACE  := moonpay
OVERLAY    := k8s/overlays/production
MIGRATION  := $(OVERLAY)/migration

# CI passes these explicitly; locally, derive from the running deployment.
REGISTRY ?= $(shell kubectl -n $(NAMESPACE) get deployment nextjs \
    -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's|/nextjs:.*||')
TAG      ?= $(shell kubectl -n $(NAMESPACE) get deployment nextjs \
    -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -o '[^:]*$$')

.DEFAULT_GOAL := help
.PHONY: create destroy deploy migrate rollout-wait show-ip \
       cd-test-apply cd-test-revert cd-test-k8s-apply cd-test-k8s-revert help

create: ## Provision infrastructure (state bucket + Terraform + GKE creds)
	@bash scripts/create.sh

destroy: ## Tear down all infrastructure and delete state bucket
	@bash scripts/destroy.sh

help: ## Show available targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-22s %s\n", $$1, $$2}'

deploy: ## Set image tag and apply main manifests
	cd $(OVERLAY) && kustomize edit set image \
		nextjs=$(REGISTRY)/nextjs:$(TAG)
	kubectl apply -k $(OVERLAY)

migrate: ## Run Prisma migration Job
	kubectl -n $(NAMESPACE) delete job prisma-migrate --ignore-not-found
	cd $(MIGRATION) && kustomize edit set image \
		migrator=$(REGISTRY)/migrator:$(TAG)
	kubectl apply -k $(MIGRATION)

rollout-wait: ## Wait for nextjs deployment rollout
	kubectl -n $(NAMESPACE) rollout status deployment/nextjs --timeout=300s

show-ip: ## Print the external LoadBalancer IP
	@IP=$$(kubectl -n $(NAMESPACE) get svc nextjs \
		-o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null); \
	if [ -n "$$IP" ]; then \
		echo "Application is live at http://$$IP"; \
	else \
		echo "External IP not yet assigned"; \
	fi

cd-test-apply: ## Push a test change (new currency + heading) to trigger CD
	@bash scripts/cd-test-apply.sh

cd-test-revert: ## Revert the test change and trigger CD
	@bash scripts/cd-test-revert.sh

cd-test-k8s-apply: ## Push a k8s-only change (scale + probe), no approval
	@bash scripts/cd-test-k8s-apply.sh

cd-test-k8s-revert: ## Revert the k8s-only change, no approval
	@bash scripts/cd-test-k8s-revert.sh
