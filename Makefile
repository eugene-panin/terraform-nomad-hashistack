.PHONY: help fmt lint test test-terraform module-tests

help:
	@echo "make fmt             tofu fmt, recursively"
	@echo "make lint            fmt check and tflint"
	@echo "make test            Terratest with tofu"
	@echo "make test-terraform  Terratest with terraform"
	@echo "make module-tests    tofu test in every module with tests (TF_BINARY=terraform for terraform)"

fmt:
	tofu fmt -recursive

lint:
	tofu fmt -check -recursive
	tflint --init && tflint --recursive --config "$(CURDIR)/.tflint.hcl"

test: module-tests
	cd test && TF_BINARY=tofu go test ./... -count=1 -timeout 30m

test-terraform:
	$(MAKE) module-tests TF_BINARY=terraform
	cd test && TF_BINARY=terraform go test ./... -count=1 -timeout 30m

TF_BINARY ?= tofu

module-tests:
	for dir in ./ modules/*/; do \
	  if [ -d "$$dir/tests" ]; then \
	    (cd "$$dir" && $(TF_BINARY) init -backend=false -input=false >/dev/null && $(TF_BINARY) test) || exit 1; \
	  fi; \
	done
