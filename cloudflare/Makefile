.PHONY: init plan apply destroy secrets-create secrets-edit state-pull state-push import

# Age encryption config
AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt
AGE_PUBKEY = age1mkelwyppmll44ehjnarunmtamcxpee7jljyl475mlvxma7dm4f3q6lnmks

# Load secrets from encrypted YAML
define load_secrets
	$(eval export SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE))
	$(eval export TF_VAR_cloudflare_api_token=$(shell SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE) sops -d secrets.yaml 2>/dev/null | yq -r '.cloudflare_api_token'))
	$(eval export TF_VAR_github_token=$(shell SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE) sops -d secrets.yaml 2>/dev/null | yq -r '.github_token'))
	$(eval export TF_VAR_webhook_secret=$(shell SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE) sops -d secrets.yaml 2>/dev/null | yq -r '.webhook_secret'))
	$(eval export TF_VAR_gcal_webhook_secret=$(shell SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE) sops -d secrets.yaml 2>/dev/null | yq -r '.gcal_webhook_secret'))
endef

# State file management (encrypted with age)
STATE_FILE=terraform.tfstate
STATE_ENC=terraform.tfstate.age

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
	terraform init
	@rm -f $(STATE_FILE) $(STATE_FILE).backup

plan: state-pull
	$(call load_secrets)
	terraform plan
	@rm -f $(STATE_FILE) $(STATE_FILE).backup

apply: state-pull
	$(call load_secrets)
	terraform apply
	@$(MAKE) state-push

destroy: state-pull
	$(call load_secrets)
	terraform destroy
	@$(MAKE) state-push

# Import existing worker into Terraform state
import: state-pull
	$(call load_secrets)
	terraform import cloudflare_workers_script.openproject_calendar_webhook fc0bb404a04968a041ca7d8475e2ffad/openproject-calendar-webhook
	@$(MAKE) state-push

# Secrets management
secrets-create:
	@if [ ! -f secrets.yaml ]; then \
		cp secrets.yaml.example secrets.yaml; \
		echo "Edit secrets.yaml with your credentials, then run: sops -e -i secrets.yaml"; \
	else \
		echo "secrets.yaml already exists"; \
	fi

secrets-edit:
	SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE) sops secrets.yaml

# Show webhook URL
webhook-url:
	@$(call load_secrets)
	@echo "https://openproject-calendar-webhook.nick-meinhold.workers.dev?token=$$TF_VAR_webhook_secret"

# Help
help:
	@echo "Cloudflare Workers for xdeca"
	@echo ""
	@echo "Setup:"
	@echo "  make secrets-create  - Create secrets file from template"
	@echo "  # Edit secrets.yaml with credentials"
	@echo "  sops -e -i secrets.yaml  - Encrypt secrets"
	@echo ""
	@echo "Commands:"
	@echo "  make init          - Initialize Terraform"
	@echo "  make plan          - Preview infrastructure changes"
	@echo "  make apply         - Create/update infrastructure"
	@echo "  make destroy       - Destroy infrastructure"
	@echo "  make import        - Import existing worker into state"
	@echo ""
	@echo "State (auto-managed):"
	@echo "  make state-pull    - Decrypt state from git"
	@echo "  make state-push    - Encrypt state to git"
	@echo ""
	@echo "Utilities:"
	@echo "  make webhook-url   - Show full webhook URL with token"
	@echo "  make secrets-edit  - Edit encrypted credentials"
