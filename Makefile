TOFU ?= tofu
TERRAFORM ?= terraform

.PHONY: check check-tofu check-terraform
check: check-tofu check-terraform
	python3 scripts/test_select_artifacts.py
	node --check templates/activate.cjs

check-tofu:
	$(TOFU) fmt -check -recursive
	TF_DATA_DIR=.local/tofu $(TOFU) init -backend=false
	TF_DATA_DIR=.local/tofu $(TOFU) validate
	TF_DATA_DIR=.local/tofu $(TOFU) test

check-terraform:
	$(TERRAFORM) fmt -check -recursive
	TF_DATA_DIR=.local/terraform $(TERRAFORM) init -backend=false
	TF_DATA_DIR=.local/terraform $(TERRAFORM) validate
	TF_DATA_DIR=.local/terraform $(TERRAFORM) test
