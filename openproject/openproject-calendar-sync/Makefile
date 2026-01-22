.PHONY: run sync reverse-sync watch-setup install

# Age encryption config
AGE_KEY_FILE ?= $(HOME)/.config/sops/age/keys.txt

# Load secrets from encrypted YAML
define load_secrets
	$(eval export SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE))
	$(eval export WEBHOOK_SECRET=$(shell SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE) sops -d secrets.yaml 2>/dev/null | grep '^webhook_secret:' | cut -d' ' -f2))
	$(eval export GCAL_WEBHOOK_SECRET=$(shell SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE) sops -d secrets.yaml 2>/dev/null | grep '^gcal_webhook_secret:' | cut -d' ' -f2))
	$(eval export OPENPROJECT_URL=$(shell SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE) sops -d secrets.yaml 2>/dev/null | grep '^openproject_url:' | cut -d' ' -f2))
	$(eval export OPENPROJECT_API_KEY=$(shell SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE) sops -d secrets.yaml 2>/dev/null | grep '^openproject_api_key:' | cut -d' ' -f2))
	$(eval export GOOGLE_CALENDAR_ID=$(shell SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE) sops -d secrets.yaml 2>/dev/null | grep '^google_calendar_id:' | cut -d' ' -f2))
	$(eval export GOOGLE_SERVICE_ACCOUNT_JSON=$(shell SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE) sops -d secrets.yaml 2>/dev/null | yq -r '.google_service_account_json'))
endef

install:
	npm install

# Run the webhook server
run:
	$(call load_secrets)
	npx tsx webhook-server.ts

# Manual sync commands
sync:
	$(call load_secrets)
	npx tsx sync.ts

reverse-sync:
	$(call load_secrets)
	npx tsx reverse-sync.ts

watch-setup:
	$(call load_secrets)
	npx tsx watch-setup.ts

# Create secrets file from template
secrets-create:
	@if [ ! -f secrets.yaml ]; then \
		cp secrets.yaml.example secrets.yaml; \
		echo "Edit secrets.yaml with your credentials, then run: sops -e -i secrets.yaml"; \
	else \
		echo "secrets.yaml already exists"; \
	fi

secrets-edit:
	SOPS_AGE_KEY_FILE=$(AGE_KEY_FILE) sops secrets.yaml

help:
	@echo "OpenProject Calendar Sync"
	@echo ""
	@echo "Setup:"
	@echo "  make install        - Install dependencies"
	@echo "  make secrets-create - Create secrets file from template"
	@echo "  sops -e -i secrets.yaml - Encrypt secrets"
	@echo ""
	@echo "Commands:"
	@echo "  make run            - Run webhook server"
	@echo "  make sync           - Run forward sync (OpenProject -> Calendar)"
	@echo "  make reverse-sync   - Run reverse sync (Calendar -> OpenProject)"
	@echo "  make watch-setup    - Set up Google Calendar watch"
	@echo ""
	@echo "Secrets:"
	@echo "  make secrets-edit   - Edit encrypted secrets"
