.PHONY: help fmt lint test test-terraform

help:
	@echo "make fmt             tofu fmt, recursively"
	@echo "make lint            fmt check and tflint"
	@echo "make test            Terratest with tofu"
	@echo "make test-terraform  Terratest with terraform"

fmt:
	tofu fmt -recursive

lint:
	tofu fmt -check -recursive
	tflint --init && tflint --recursive --config "$(CURDIR)/.tflint.hcl"

test:
	cd test && TF_BINARY=tofu go test ./... -count=1 -timeout 30m

test-terraform:
	cd test && TF_BINARY=terraform go test ./... -count=1 -timeout 30m
