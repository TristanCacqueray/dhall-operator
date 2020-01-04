data:
	mkdir -p applications/data/
	[ -f applications/data/id_rsa ] || ssh-keygen -f applications/data/id_rsa -N ''

demo:
	@(dhall-to-yaml --omit-empty --explain <<< 'let lib = ./package.dhall in lib.Deploy.Kubernetes lib.Applications.Demo')

ansible:
	@(dhall-to-yaml --omit-empty --explain <<< '(./deploy/Ansible.dhall).Localhost ((./applications/Zuul.dhall).LocalCluster "test01")')

ansibles:
	@(dhall-to-yaml --omit-empty --explain <<< '(./deploy/Ansible.dhall).Distributed ((./applications/Zuul.dhall).LocalCluster "test01")')

podman:
	@(dhall text --explain <<< '(./deploy/Podman.dhall).RenderCommands ((./applications/Zuul.dhall).LocalCluster "test01")')

k8s:
	@(dhall-to-yaml --omit-empty --explain <<< 'let lib = ./package.dhall in lib.Deploy.Kubernetes (lib.Applications.Zuul.LocalCluster "test01")')
