{ Schemas = { Service = ./schemas/Service.dhall }
, Deploy =
    { Ansible = ./deploy/Ansible.dhall
    , Kubernetes = ./deploy/Kubernetes.dhall
    , Podman = ./deploy/Podman.dhall
    }
, Applications = { Demo = ./applications/Demo.dhall }
}
