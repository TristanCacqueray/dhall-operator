install:
	kubectl apply -f operator/deploy/dhall-crd.yaml -f operator/deploy/operator.yaml

build:
	operator-sdk build --image-builder podman quay.io/software-factory/dhall-operator:0.0.1

build-local:
	sudo ~/.local/bin/operator-sdk build --image-build-args "--root /var/lib/silverkube/storage --storage-driver vfs" --image-builder podman quay.io/software-factory/dhall-operator:0.0.1

# Generate demo deployments

ZUUL_TEST := ((./applications/zuul/Test.dhall).Application { ssh_key = (./applications/data/id_rsa as Text), name = \"uzuul\", port = Some 9090, kubeconfig = None Text, kubecontext = None Text })

demo:
	@(dhall-to-yaml --omit-empty --explain <<< 'let lib = ./package.dhall in lib.Deploy.Kubernetes lib.Applications.Demo')

ansible:
	@dhall-to-yaml --omit-empty --explain <<< "(./deploy/Ansible.dhall).Localhost $(ZUUL_TEST)"

ansibles:
	@dhall-to-yaml --omit-empty --explain <<< "(./deploy/Ansible.dhall).Distributed $(ZUUL_TEST)"

podman:
	@dhall text --explain                 <<< "(./deploy/Podman.dhall).RenderCommands $(ZUUL_TEST)"

k8s:
	@dhall-to-yaml --omit-empty --explain <<< "./deploy/Kubernetes.dhall $(ZUUL_TEST)"
