NAMESPACE  := moonpay
OVERLAY    := k8s/overlays/production
MIGRATION  := $(OVERLAY)/migration

# CI passes these explicitly; locally, derive from the running deployment.
REGISTRY ?= $(shell kubectl -n $(NAMESPACE) get deployment nextjs \
    -o jsonpath='{.spec.template.spec.containers[0].image}' | sed 's|/nextjs:.*||')
TAG      ?= $(shell kubectl -n $(NAMESPACE) get deployment nextjs \
    -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -o '[^:]*$$')

.PHONY: deploy migrate rollout-wait show-ip help

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

deploy: ## Set image tag and apply main manifests
	cd $(OVERLAY) && kustomize edit set image \
		nextjs=$(REGISTRY)/nextjs:$(TAG)
	kubectl apply -k $(OVERLAY)

migrate: ## Run Prisma migration Job
	kubectl -n $(NAMESPACE) delete job prisma-migrate --ignore-not-found
	cd $(MIGRATION) && kustomize edit set image \
		migrator=$(REGISTRY)/migrator:$(TAG)
	kubectl apply -k $(MIGRATION)
	kubectl -n $(NAMESPACE) wait --for=condition=complete \
		job/prisma-migrate --timeout=120s
	kubectl -n $(NAMESPACE) logs job/prisma-migrate

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
