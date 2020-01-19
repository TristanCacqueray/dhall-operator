# This is being deprecated and replaced by Goalfile
lint:
	@bash -c 'for f in $$(find . -name "*.dhall"); do dhall format --ascii < $$f > $$f.fmt; mv $$f.fmt $$f; done'

# Temporary make target until dhall-operator packaging is defined
image:
	podman build -f operator/build/Containerfile -t quay.io/software-factory/dhall-operator:0.0.2 .
