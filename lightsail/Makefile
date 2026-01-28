.PHONY: init plan apply destroy ssh deploy ip

TERRAFORM_DIR = terraform

init:
	cd $(TERRAFORM_DIR) && terraform init

plan:
	cd $(TERRAFORM_DIR) && terraform plan

apply:
	cd $(TERRAFORM_DIR) && terraform apply

destroy:
	cd $(TERRAFORM_DIR) && terraform destroy

ip:
	@cd $(TERRAFORM_DIR) && terraform output -raw public_ip

ssh:
	ssh ubuntu@$$(cd $(TERRAFORM_DIR) && terraform output -raw public_ip)

deploy:
	../scripts/deploy-to.sh $$(cd $(TERRAFORM_DIR) && terraform output -raw public_ip) all
