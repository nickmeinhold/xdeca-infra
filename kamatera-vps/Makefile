.PHONY: init plan apply destroy deploy ssh secrets-create secrets-edit state-pull state-push

# Age encryption config
AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt
AGE_PUBKEY = age1mkelwyppmll44ehjnarunmtamcxpee7jljyl475mlvxma7dm4f3q6lnmks

# Load Kamatera credentials from encrypted secrets
define load_secrets
	$(eval export KAMATERA_API_CLIENT_ID=$(shell sops -d kamatera.yaml 2>/dev/null | yq -r '.api_client_id'))
	$(eval export KAMATERA_API_SECRET=$(shell sops -d kamatera.yaml 2>/dev/null | yq -r '.api_secret'))
endef

# State file management (encrypted with age)
STATE_FILE=terraform/terraform.tfstate
STATE_ENC=terraform/terraform.tfstate.age

state-pull:
	@if [ -f $(STATE_ENC) ]; then \
		age -d -i $(AGE_KEY_FILE) $(STATE_ENC) > $(STATE_FILE); \
		echo "State decrypted from $(STATE_ENC)"; \
	fi

state-push:
	@if [ -f $(STATE_FILE) ]; then \
		age -r $(AGE_PUBKEY) -o $(STATE_ENC) $(STATE_FILE); \
		rm -f $(STATE_FILE) $(STATE_FILE).backup; \
		echo "State encrypted and cleaned up"; \
	fi

# Terraform commands
init: state-pull
	cd terraform && terraform init
	@rm -f $(STATE_FILE) $(STATE_FILE).backup

plan: state-pull
	$(call load_secrets)
	cd terraform && terraform plan
	@rm -f $(STATE_FILE) $(STATE_FILE).backup

apply: state-pull
	$(call load_secrets)
	cd terraform && terraform apply
	@$(MAKE) state-push

destroy: state-pull
	$(call load_secrets)
	cd terraform && terraform destroy
	@$(MAKE) state-push

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
	@echo "State (auto-managed, but can run manually):"
	@echo "  make state-pull    - Decrypt state from git"
	@echo "  make state-push    - Encrypt state to git"
	@echo ""
	@echo "Secrets:"
	@echo "  make secrets-edit  - Edit encrypted credentials"
	@echo ""
	@echo "Deploy:"
	@echo "  make deploy              - Deploy all services"
	@echo "  make deploy-caddy        - Deploy Caddy only"
	@echo "  make deploy-calendar-sync - Deploy calendar sync only"
