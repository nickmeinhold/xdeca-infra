.PHONY: init plan apply destroy deploy ssh secrets-setup secrets-edit

# Terraform commands
init:
	cd terraform && terraform init

plan:
	cd terraform && terraform plan

apply:
	cd terraform && terraform apply

destroy:
	cd terraform && terraform destroy

# Get instance IP
ip:
	@cd terraform && terraform output -raw instance_public_ip

# SSH to instance
ssh:
	ssh ubuntu@$$(cd terraform && terraform output -raw instance_public_ip)

# Deploy services
deploy:
	./scripts/deploy.sh all

deploy-%:
	./scripts/deploy.sh $*

# SOPS/age secrets management
secrets-setup:
	@echo "Setting up age key..."
	@mkdir -p ~/.config/sops/age
	@if [ ! -f ~/.config/sops/age/keys.txt ]; then \
		age-keygen -o ~/.config/sops/age/keys.txt; \
		echo "Age key created. Add the public key to .sops.yaml"; \
		cat ~/.config/sops/age/keys.txt | grep "public key"; \
	else \
		echo "Age key already exists"; \
		cat ~/.config/sops/age/keys.txt | grep "public key"; \
	fi

secrets-edit-%:
	sops secrets/$*.yaml

secrets-create-%:
	@if [ ! -f secrets/$*.yaml ]; then \
		cp secrets/$*.yaml.example secrets/$*.yaml; \
		sops -e -i secrets/$*.yaml; \
		echo "Created and encrypted secrets/$*.yaml"; \
	else \
		echo "secrets/$*.yaml already exists"; \
	fi

# Generate random secrets
gen-secret-64:
	@openssl rand -hex 64

gen-secret-32:
	@openssl rand -hex 32

gen-secret-16:
	@openssl rand -hex 16

# View logs
logs-%:
	ssh ubuntu@$$(cd terraform && terraform output -raw instance_public_ip) "cd ~/apps/$* && docker-compose logs -f"

# Restart service
restart-%:
	ssh ubuntu@$$(cd terraform && terraform output -raw instance_public_ip) "cd ~/apps/$* && docker-compose restart"

# Help
help:
	@echo "Infrastructure as Code for xdeca OCI VPS"
	@echo ""
	@echo "Setup:"
	@echo "  make init          - Initialize Terraform"
	@echo "  make secrets-setup - Create age encryption key"
	@echo ""
	@echo "Infrastructure:"
	@echo "  make plan          - Preview infrastructure changes"
	@echo "  make apply         - Create/update infrastructure"
	@echo "  make destroy       - Destroy infrastructure"
	@echo "  make ip            - Show instance public IP"
	@echo "  make ssh           - SSH to instance"
	@echo ""
	@echo "Secrets:"
	@echo "  make secrets-create-kanbn    - Create encrypted secrets"
	@echo "  make secrets-edit-kanbn      - Edit secrets"
	@echo "  make gen-secret-64           - Generate 64-char hex secret"
	@echo ""
	@echo "Deploy:"
	@echo "  make deploy        - Deploy all services"
	@echo "  make deploy-caddy  - Deploy Caddy only"
	@echo "  make deploy-kanbn  - Deploy Kan.bn only"
	@echo "  make deploy-outline - Deploy Outline only"
	@echo ""
	@echo "Operations:"
	@echo "  make logs-caddy    - View Caddy logs"
	@echo "  make logs-kanbn    - View Kan.bn logs"
	@echo "  make logs-outline  - View Outline logs"
