.PHONY: init plan apply destroy deploy ssh secrets-create secrets-edit

# Load Kamatera credentials from encrypted secrets
define load_secrets
	$(eval export KAMATERA_API_CLIENT_ID=$(shell sops -d kamatera.yaml 2>/dev/null | yq -r '.api_client_id'))
	$(eval export KAMATERA_API_SECRET=$(shell sops -d kamatera.yaml 2>/dev/null | yq -r '.api_secret'))
endef

# Terraform commands
init:
	cd terraform && terraform init

plan:
	$(call load_secrets)
	cd terraform && terraform plan

apply:
	$(call load_secrets)
	cd terraform && terraform apply

destroy:
	$(call load_secrets)
	cd terraform && terraform destroy

# Get instance IP
ip:
	@cd terraform && terraform output -raw instance_public_ip

# SSH to instance
ssh:
	ssh ubuntu@$$(cd terraform && terraform output -raw instance_public_ip)

# Deploy services
deploy:
	../scripts/deploy-to.sh $$(cd terraform && terraform output -raw instance_public_ip) all

deploy-%:
	../scripts/deploy-to.sh $$(cd terraform && terraform output -raw instance_public_ip) $*

# Secrets management
secrets-create:
	@if [ ! -f kamatera.yaml ]; then \
		cp kamatera.yaml.example kamatera.yaml; \
		echo "Edit kamatera.yaml with your credentials, then run: sops -e -i kamatera.yaml"; \
	else \
		echo "kamatera.yaml already exists"; \
	fi

secrets-edit:
	sops kamatera.yaml

# View logs
logs-%:
	ssh ubuntu@$$(cd terraform && terraform output -raw instance_public_ip) "cd ~/apps/$* && podman-compose logs -f"

# Restart service
restart-%:
	ssh ubuntu@$$(cd terraform && terraform output -raw instance_public_ip) "cd ~/apps/$* && podman-compose restart"

# Help
help:
	@echo "Kamatera VPS for xdeca"
	@echo ""
	@echo "Setup:"
	@echo "  make secrets-create  - Create secrets file from template"
	@echo "  # Edit kamatera.yaml with credentials"
	@echo "  sops -e -i kamatera.yaml  - Encrypt secrets"
	@echo ""
	@echo "Commands:"
	@echo "  make init          - Initialize Terraform"
	@echo "  make plan          - Preview infrastructure changes"
	@echo "  make apply         - Create/update infrastructure"
	@echo "  make destroy       - Destroy infrastructure"
	@echo "  make ip            - Show instance public IP"
	@echo "  make ssh           - SSH to instance"
	@echo ""
	@echo "Secrets:"
	@echo "  make secrets-edit  - Edit encrypted credentials"
	@echo ""
	@echo "Deploy:"
	@echo "  make deploy        - Deploy all services"
	@echo "  make deploy-caddy  - Deploy Caddy only"
