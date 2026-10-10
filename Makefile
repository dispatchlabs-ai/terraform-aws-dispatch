TOFU ?= tofu
TERRAFORM ?= terraform

.PHONY: check check-tofu check-terraform validation-caller
check: check-tofu check-terraform
	python3 scripts/test_select_artifacts.py
	python3 scripts/test_run_operator.py
	python3 scripts/test_publish_frontend.py
	node --check templates/activate.cjs
	node scripts/test_edge_functions.cjs

validation-caller:
	python3 scripts/validation-caller.py

check-tofu: validation-caller
	$(TOFU) fmt -check -recursive
	TF_DATA_DIR=.local/tofu $(TOFU) init -backend=false
	$(TOFU) -chdir=.local/validation init -backend=false
	$(TOFU) -chdir=.local/validation validate
	TF_DATA_DIR=.local/tofu $(TOFU) test

check-terraform: validation-caller
	$(TERRAFORM) fmt -check -recursive
	TF_DATA_DIR=.local/terraform $(TERRAFORM) init -backend=false
	$(TERRAFORM) -chdir=.local/validation init -backend=false
	$(TERRAFORM) -chdir=.local/validation validate
	# Terraform defers mock defaults until apply unless explicitly overridden.
	# OpenTofu supplies these defaults at plan and does not accept that option.
	python3 -c 'from pathlib import Path; p=Path(".local/terraform-tests"); p.mkdir(parents=True, exist_ok=True); [(p/f.name).write_text(f.read_text().replace("mock_provider \"aws\" {", "mock_provider \"aws\" {\n  override_during = plan")) for f in Path("tests").glob("*.tftest.hcl") ]'
	TF_DATA_DIR=.local/terraform $(TERRAFORM) test -test-directory=.local/terraform-tests
