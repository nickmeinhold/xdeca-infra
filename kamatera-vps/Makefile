.PHONY: init plan apply destroy deploy ssh

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
	../scripts/deploy-to.sh $$(cd terraform && terraform output -raw instance_public_ip) all

deploy-%:
	../scripts/deploy-to.sh $$(cd terraform && terraform output -raw instance_public_ip) $*

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
	@echo "  export KAMATERA_API_CLIENT_ID=..."
	@echo "  export KAMATERA_API_SECRET=..."
	@echo ""
	@echo "Commands:"
	@echo "  make init          - Initialize Terraform"
	@echo "  make plan          - Preview infrastructure changes"
	@echo "  make apply         - Create/update infrastructure"
	@echo "  make destroy       - Destroy infrastructure"
	@echo "  make ip            - Show instance public IP"
	@echo "  make ssh           - SSH to instance"
	@echo ""
	@echo "Deploy:"
	@echo "  make deploy        - Deploy all services"
	@echo "  make deploy-caddy  - Deploy Caddy only"
	@echo ""
	@echo "Operations:"
	@echo "  make logs-caddy    - View Caddy logs"
	@echo "  make restart-twenty - Restart Twenty"
