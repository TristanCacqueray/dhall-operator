let Prelude = ../Prelude.dhall

let Kubernetes = ../Kubernetes.dhall

let k8s = ./kubernetes-types-union.dhall

let Service = ../types/Service.dhall

let ServiceType = ../types/ServiceType.dhall

let renderResources =
          \(app : ../types/Application.dhall)
      ->  let mkSecret =
                Prelude.List.map
                  ../types/Volume.dhall
                  Kubernetes.Secret.Type
                  (     \(volume : ../types/Volume.dhall)
                    ->  Kubernetes.Secret::{
                        , metadata =
                            Kubernetes.ObjectMeta::{ name = volume.name }
                        , stringData =
                            Prelude.List.map
                              ../types/File.dhall
                              { mapKey : Text, mapValue : Text }
                              (     \(config : ../types/File.dhall)
                                ->  { mapKey = config.path
                                    , mapValue = config.content
                                    }
                              )
                              volume.files
                        }
                  )

          let mkServiceVolume =
                Prelude.List.map
                  ../types/Volume.dhall
                  Kubernetes.Volume.Type
                  (     \(volume : ../types/Volume.dhall)
                    ->  Kubernetes.Volume::{ name = volume.name }
                  )

          let mkContainerVolume =
                Prelude.List.map
                  ../types/Volume.dhall
                  Kubernetes.VolumeMount.Type
                  (     \(volume : ../types/Volume.dhall)
                    ->  Kubernetes.VolumeMount::{
                        , name = volume.name
                        , mountPath = volume.dir
                        }
                  )

          let mkServiceContainer =
                    \(service : ../types/Service.dhall)
                ->  \(container : ../types/Container.dhall)
                ->  Kubernetes.Container::{
                    , name = service.name
                    , image = Some container.image
                    , args = ../functions/getCommand.dhall container
                    , volumeMounts =
                        mkContainerVolume (app.volumes service.type)
                    }

          let mkService =
                    \(service : Service)
                ->  let label = toMap { run = service.name }

                    in  Kubernetes.Deployment::{
                        , metadata =
                            Kubernetes.ObjectMeta::{
                            , name = app.name ++ "-" ++ service.name
                            }
                        , spec =
                            Some
                              Kubernetes.DeploymentSpec::{
                              , replicas = Some 1
                              , selector =
                                  Kubernetes.LabelSelector::{
                                  , matchLabels = label
                                  }
                              , template =
                                  Kubernetes.PodTemplateSpec::{
                                  , metadata =
                                      Kubernetes.ObjectMeta::{
                                      , name = service.name
                                      , labels = label
                                      }
                                  , spec =
                                      Some
                                        Kubernetes.PodSpec::{
                                        , volumes =
                                            mkServiceVolume
                                              (app.volumes service.type)
                                        , containers =
                                            [ mkServiceContainer
                                                service
                                                service.container
                                            ]
                                        }
                                  }
                              }
                        }

          let secrets = mkSecret (app.volumes ServiceType._All)

          let deployments =
                Prelude.List.map
                  Service
                  Kubernetes.Deployment.Type
                  mkService
                  app.services

          let transformSecrets =
                Prelude.List.map
                  Kubernetes.Secret.Type
                  k8s
                  (\(cm : Kubernetes.Secret.Type) -> k8s.Secret cm)
                  secrets

          let transformDeployments =
                Prelude.List.map
                  Kubernetes.Deployment.Type
                  k8s
                  (\(cm : Kubernetes.Deployment.Type) -> k8s.Deployment cm)
                  deployments

          in  transformSecrets # transformDeployments

in      \(app : ../types/Application.dhall)
    ->  { apiVersion = "v1", kind = "List", items = renderResources app }
