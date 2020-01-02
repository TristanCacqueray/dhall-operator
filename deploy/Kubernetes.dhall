let Prelude = ../Prelude.dhall

let Kubernetes = ../Kubernetes.dhall

let k8s = ./kubernetes-types-union.dhall

let Port = ../types/Port.dhall

let Service = ../types/Service.dhall

let ServiceType = ../types/ServiceType.dhall

let renderResources =
          \(app : ../types/Application.dhall)
      ->  let app-labels =
                [ { mapKey = "app.kubernetes.io/name", mapValue = app.name } ]

          let service-label =
                    \(service-name : Text)
                ->    app-labels
                    # [ { mapKey = "app.kubernetes.io/component"
                        , mapValue = service-name
                        }
                      ]

          let mkServicePort =
                    \(port : Port)
                ->  Kubernetes.ServicePort::{
                    , name = Some port.name
                    , protocol = Some port.protocol
                    , targetPort =
                        Some (Kubernetes.IntOrString.String port.name)
                    , port = port.container
                    }

          let mkService =
                    \(service : Service)
                ->  let labels = service-label service.name

                    in  Kubernetes.Service::{
                        , metadata =
                            Kubernetes.ObjectMeta::{
                            , name = app.name ++ "-service-" ++ service.name
                            , labels = labels
                            }
                        , spec =
                            Some
                              Kubernetes.ServiceSpec::{
                              , type = Some "ClusterIP"
                              , selector = labels
                              , ports =
                                  Prelude.List.map
                                    Port
                                    Kubernetes.ServicePort.Type
                                    mkServicePort
                                    ( Prelude.Optional.fold
                                        (List Port)
                                        service.ports
                                        (List Port)
                                        (\(some : List Port) -> some)
                                        ([] : List Port)
                                    )
                              }
                        }

          let mkSecret =
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

          let mkDeployment =
                    \(service : Service)
                ->  let labels = service-label service.name

                    in  Kubernetes.Deployment::{
                        , metadata =
                            Kubernetes.ObjectMeta::{
                            , name = app.name ++ "-" ++ service.name
                            , labels = labels
                            }
                        , spec =
                            Some
                              Kubernetes.DeploymentSpec::{
                              , replicas = Some 1
                              , selector =
                                  Kubernetes.LabelSelector::{
                                  , matchLabels = labels
                                  }
                              , template =
                                  Kubernetes.PodTemplateSpec::{
                                  , metadata =
                                      Kubernetes.ObjectMeta::{
                                      , name = service.name
                                      , labels = labels
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
                  mkDeployment
                  app.services

          let services =
                Prelude.List.map
                  Service
                  Kubernetes.Service.Type
                  mkService
                  ( Prelude.List.filter
                      Service
                      (     \(service : Service)
                        ->      False
                            ==  Prelude.Optional.null (List Port) service.ports
                      )
                      app.services
                  )

          let transformSecrets =
                Prelude.List.map
                  Kubernetes.Secret.Type
                  k8s
                  (\(cm : Kubernetes.Secret.Type) -> k8s.Secret cm)
                  secrets

          let transformServices =
                Prelude.List.map
                  Kubernetes.Service.Type
                  k8s
                  (\(cm : Kubernetes.Service.Type) -> k8s.Service cm)
                  services

          let transformDeployments =
                Prelude.List.map
                  Kubernetes.Deployment.Type
                  k8s
                  (\(cm : Kubernetes.Deployment.Type) -> k8s.Deployment cm)
                  deployments

          in  transformSecrets # transformServices # transformDeployments

in      \(app : ../types/Application.dhall)
    ->  { apiVersion = "v1", kind = "List", items = renderResources app }
