package test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform/v2"
)

func TestExamplesValidate(t *testing.T) {
	t.Parallel()

	examples, err := filepath.Glob("../examples/*")
	if err != nil {
		t.Fatal(err)
	}
	if len(examples) == 0 {
		t.Fatal("no examples found")
	}

	for _, dir := range examples {
		dir := dir
		t.Run(filepath.Base(dir), func(t *testing.T) {
			t.Parallel()
			terraform.InitAndValidateContext(t, t.Context(), &terraform.Options{
				TerraformDir:    dir,
				TerraformBinary: binary(),
				NoColor:         true,
			})
		})
	}
}

func binary() string {
	if b := os.Getenv("TF_BINARY"); b != "" {
		return b
	}
	return "tofu"
}
