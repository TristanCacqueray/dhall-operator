install:
	kubectl apply -f operator/deploy/dhall-crd.yaml -f operator/deploy/operator.yaml

build:
	operator-sdk build --image-builder podman quay.io/software-factory/dhall-operator:0.0.1

build-local:
	sudo ~/.local/bin/operator-sdk build --image-build-args "--root /var/lib/silverkube/storage --storage-driver vfs" --image-builder podman quay.io/software-factory/dhall-operator:0.0.1
