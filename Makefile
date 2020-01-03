data:
	mkdir -p applications/data/
	[ -f applications/data/id_rsa ] || ssh-keygen -f applications/data/id_rsa -N ''

podman:
	@(dhall text --explain <<< './deploy/Podman.dhall ((./applications/Zuul.dhall).LocalCluster "test01")')

k8s:
	@(dhall-to-yaml --omit-empty --explain <<< 'let lib = ./package.dhall in lib.Deploy.Kubernetes (lib.Applications.Zuul.LocalCluster "test01")')
