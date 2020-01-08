{ Schemas =
    { Application = ./schemas/Application.dhall
    , Service = ./schemas/Service.dhall
    , Container = ./schemas/Container.dhall
    , Port = ./schemas/Port.dhall
    }
, Types =
    { Env = ./types/Env.dhall
    , Service = ./types/Service.dhall
    , ServiceType = ./types/ServiceType.dhall
    , Volume = ./types/Volume.dhall
    }
, Functions = { waitFor = ./functions/waitFor.dhall }
, Deploy =
    { Ansible = ./deploy/Ansible.dhall
    , Kubernetes = ./deploy/Kubernetes.dhall
    , Podman = ./deploy/Podman.dhall
    }
, Applications = { Demo = ./applications/Demo.dhall }
}
