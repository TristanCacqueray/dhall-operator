let Prelude = ../Prelude.dhall

let Kubernetes = ../Kubernetes.dhall

let k8s = ../KubernetesUnion.dhall

let Port = ../types/Port.dhall

let Service = ../types/Service.dhall

let ServiceType = ../types/ServiceType.dhall

let Volume = ../types/Volume.dhall

let Labels = List { mapKey : Text, mapValue : Text }

let renderResources =
          \(app : ../types/Application.dhall)
      ->  let app-labels =
                [ { mapKey = "app.kubernetes.io/name", mapValue = app.name }
                , { mapKey = "app.kubernetes.io/instance", mapValue = app.name }
                , { mapKey = "app.kubernetes.io/part-of", mapValue = app.kind }
                ]

          let service-label =
                    \(service-name : Text)
                ->    app-labels
                    # [ { mapKey = "app.kubernetes.io/component"
                        , mapValue = service-name
                        }
                      ]

          let service-name = \(service-name : Text) -> service-name

          let mkServicePort =
                    \(port : Port)
                ->  Kubernetes.ServicePort::{
                    , name = Some port.name
                    , protocol = Some port.protocol
                    , targetPort = Some
                        (Kubernetes.IntOrString.String port.name)
                    , port = port.container
                    }

          let mkService =
                    \(service : Service)
                ->  let labels = service-label service.name

                    in  Kubernetes.Service::{
                        , metadata = Kubernetes.ObjectMeta::{
                          , name = service-name service.name
                          , labels = labels
                          }
                        , spec = Some Kubernetes.ServiceSpec::{
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
                        , metadata = Kubernetes.ObjectMeta::{
                          , name = app.name ++ "-secret-" ++ volume.name
                          }
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
                    ->  Kubernetes.Volume::{
                        , name = volume.name
                        , secret = Some Kubernetes.SecretVolumeSource::{
                          , secretName = Some
                              (app.name ++ "-secret-" ++ volume.name)
                          }
                        }
                  )

          let mkSecretsVolume =
                Prelude.List.map
                  ../types/Volume.dhall
                  Kubernetes.Volume.Type
                  (     \(volume : ../types/Volume.dhall)
                    ->  Kubernetes.Volume::{
                        , name = volume.name
                        , secret = Some Kubernetes.SecretVolumeSource::{
                          , secretName = Some volume.name
                          }
                        }
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

          let mkContainerPorts =
                    \(service : Service)
                ->  Prelude.Optional.fold
                      (List Port)
                      service.ports
                      (List Kubernetes.ContainerPort.Type)
                      ( Prelude.List.map
                          Port
                          Kubernetes.ContainerPort.Type
                          (     \(port : Port)
                            ->  Kubernetes.ContainerPort::{
                                , name = Some port.name
                                , containerPort = port.container
                                }
                          )
                      )
                      ([] : List Kubernetes.ContainerPort.Type)

          let mkContainerEnv =
                Prelude.List.map
                  ../types/Env.dhall
                  Kubernetes.EnvVar.Type
                  (     \(env : ../types/Env.dhall)
                    ->  Kubernetes.EnvVar::{
                        , name = env.mapKey
                        , value = Some env.mapValue
                        }
                  )

          let mkContainerSecretEnv =
                Prelude.List.map
                  ../types/EnvSecret.dhall
                  Kubernetes.EnvVar.Type
                  (     \(env : ../types/EnvSecret.dhall)
                    ->  Kubernetes.EnvVar::{
                        , name = env.name
                        , valueFrom = Kubernetes.EnvVarSource::{
                          , secretKeyRef = Some Kubernetes.SecretKeySelector::{
                            , key = env.key
                            , name = Some env.secret
                            }
                          }
                        }
                  )

          let mkServiceContainer =
                    \(service : ../types/Service.dhall)
                ->  \(container : ../types/Container.dhall)
                ->  Kubernetes.Container::{
                    , name = service.name
                    , image = Some container.image
                    , imagePullPolicy = Some "IfNotPresent"
                    , ports = mkContainerPorts service
                    , args = ../functions/getCommand.dhall container
                    , env =
                          mkContainerEnv (app.environs service.type)
                        # mkContainerSecretEnv (app.env-secrets service.type)
                    , volumeMounts =
                        mkContainerVolume
                          (   app.volumes service.type
                            # app.secrets service.type
                            # service.data-dir
                          )
                    , securityContext =
                              if service.privileged

                        then  Some
                                Kubernetes.SecurityContext::{
                                , privileged = Some True
                                }

                        else  None Kubernetes.SecurityContext.Type
                    }

          let mkServiceMetadata =
                    \(service : Service)
                ->  \(labels : Labels)
                ->  Kubernetes.ObjectMeta::{
                    , name = app.name ++ "-" ++ service.name
                    , labels = labels
                    }

          let mkServiceSelector =
                    \(labels : Labels)
                ->  Kubernetes.LabelSelector::{ matchLabels = labels }

          let mkServicePod =
                    \(service : Service)
                ->  let IndexedContainer
                        : Type
                        = { index : Natural, value : ../types/Container.dhall }

                    let mkDataVolume =
                          Prelude.List.map
                            Volume
                            Kubernetes.Volume.Type
                            (     \(data-dir : Volume)
                              ->  Kubernetes.Volume::{
                                  , name = data-dir.name
                                  , emptyDir = Kubernetes.EmptyDirVolumeSource::{
                                    , medium = Some ""
                                    }
                                  }
                            )

                    in  Kubernetes.PodSpec::{
                        , volumes =
                              mkServiceVolume (app.volumes service.type)
                            # mkSecretsVolume (app.secrets service.type)
                            # mkDataVolume service.data-dir
                        , containers =
                          [ mkServiceContainer service service.container ]
                        , initContainers =
                            Prelude.List.map
                              IndexedContainer
                              Kubernetes.Container.Type
                              (     \(indexed-container : IndexedContainer)
                                ->  mkServiceContainer
                                      (     service
                                        //  { name =
                                                    service.name
                                                ++  "-init"
                                                ++  Natural/show
                                                      indexed-container.index
                                            }
                                      )
                                      indexed-container.value
                              )
                              ( Prelude.List.indexed
                                  ../types/Container.dhall
                                  ( Optional/fold
                                      (List ../types/Container.dhall)
                                      service.init-containers
                                      (List ../types/Container.dhall)
                                      (     \ ( some
                                              : List ../types/Container.dhall
                                              )
                                        ->  some
                                      )
                                      ([] : List ../types/Container.dhall)
                                  )
                              )
                        , automountServiceAccountToken = Some False
                        , serviceAccountName =
                                  if service.privileged

                            then  Some (app.kind ++ "-operator")

                            else  None Text
                        }

          let mkServicePodTemplate =
                    \(service : Service)
                ->  \(labels : Labels)
                ->  Kubernetes.PodTemplateSpec::{
                    , metadata = Kubernetes.ObjectMeta::{
                      , name = service.name
                      , labels = labels
                      }
                    , spec = Some (mkServicePod service)
                    }

          let mkDeployment =
                    \(service : Service)
                ->  let labels = service-label service.name

                    in  Kubernetes.Deployment::{
                        , metadata = mkServiceMetadata service labels
                        , spec = Some Kubernetes.DeploymentSpec::{
                          , replicas = Some service.count
                          , selector = mkServiceSelector labels
                          , template = mkServicePodTemplate service labels
                          }
                        }

          let mkServiceVolumeClaim =
                    \(service : Service)
                ->  \(size : Natural)
                ->  Kubernetes.PersistentVolumeClaim::{
                    , apiVersion = ""
                    , kind = ""
                    , metadata = mkServiceMetadata service ([] : Labels)
                    , spec = Some Kubernetes.PersistentVolumeClaimSpec::{
                      , accessModes = [ "ReadWriteOnce" ]
                      , resources = Some Kubernetes.ResourceRequirements::{
                        , requests =
                            toMap { storage = Natural/show size ++ "Gi" }
                        }
                      }
                    }

          let mkServiceVolumeClaimTemplates =
                    \(service : Service)
                ->  let empty = [] : List Kubernetes.PersistentVolumeClaim.Type

                    in  Prelude.Optional.fold
                          Natural
                          service.volume-size
                          (List Kubernetes.PersistentVolumeClaim.Type)
                          (     \(some : Natural)
                            ->        if Prelude.Natural.isZero some

                                then  empty

                                else  [ mkServiceVolumeClaim service some ]
                          )
                          empty

          let mkStatefulset =
                    \(service : Service)
                ->  let labels = service-label service.name

                    in  Kubernetes.StatefulSet::{
                        , metadata = mkServiceMetadata service labels
                        , spec = Some Kubernetes.StatefulSetSpec::{
                          , serviceName = service.name
                          , replicas = Some service.count
                          , selector = mkServiceSelector labels
                          , template = mkServicePodTemplate service labels
                          , volumeClaimTemplates =
                              mkServiceVolumeClaimTemplates service
                          }
                        }

          let {- the list of port that have an host attribute -} ingress-ports
              : forall (service : Service) -> List Natural
              =     \(service : Service)
                ->  Prelude.List.map
                      Port
                      Natural
                      (     \(port : Port)
                        ->  Optional/fold
                              Natural
                              port.host
                              Natural
                              (\(host : Natural) -> host)
                              42
                      )
                      ( Prelude.List.filter
                          Port
                          (     \(port : Port)
                            ->  False == Prelude.Optional.null Natural port.host
                          )
                          ( Optional/fold
                              (List Port)
                              service.ports
                              (List Port)
                              (\(some : List Port) -> some)
                              ([] : List Port)
                          )
                      )

          let mkIngress =
                    \(service : Service)
                ->  let labels = service-label service.name

                    let {- TODO: support more than one ingress per service
                        -} port =
                          Optional/fold
                            Natural
                            (Prelude.List.head Natural (ingress-ports service))
                            Natural
                            (\(some : Natural) -> some)
                            42

                    in  Kubernetes.Ingress::{
                        , metadata = mkServiceMetadata service labels
                        , spec = Some Kubernetes.IngressSpec::{
                          , rules =
                            [ Kubernetes.IngressRule::{
                              , http = Some Kubernetes.HTTPIngressRuleValue::{
                                , paths =
                                  [ Kubernetes.HTTPIngressPath::{
                                    , backend = Kubernetes.IngressBackend::{
                                      , serviceName = service-name service.name
                                      , servicePort =
                                          Kubernetes.IntOrString.Int port
                                      }
                                    , path = Some "/"
                                    }
                                  ]
                                }
                              }
                            ]
                          }
                        }

          let secrets = mkSecret (app.volumes ServiceType._All)

          let isStateful =
                    \(service : Service)
                ->  Optional/fold
                      Natural
                      service.volume-size
                      Bool
                      (\(some : Natural) -> True)
                      False

          let notStateful = \(service : Service) -> isStateful service == False

          let services-with-port =
                Prelude.List.filter
                  Service
                  (     \(service : Service)
                    ->  False == Prelude.Optional.null (List Port) service.ports
                  )
                  app.services

          let deployments =
                Prelude.List.map
                  Service
                  Kubernetes.Deployment.Type
                  mkDeployment
                  (Prelude.List.filter Service notStateful app.services)

          let statefulsets =
                Prelude.List.map
                  Service
                  Kubernetes.StatefulSet.Type
                  mkStatefulset
                  (Prelude.List.filter Service isStateful app.services)

          let services =
                Prelude.List.map
                  Service
                  Kubernetes.Service.Type
                  mkService
                  services-with-port

          let ingresses =
                Prelude.List.map
                  Service
                  Kubernetes.Ingress.Type
                  mkIngress
                  ( Prelude.List.filter
                      Service
                      (     \(service : Service)
                        ->      False
                            ==  Prelude.Natural.isZero
                                  ( Prelude.List.length
                                      Natural
                                      (ingress-ports service)
                                  )
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

          let transformStatefulset =
                Prelude.List.map
                  Kubernetes.StatefulSet.Type
                  k8s
                  (\(cm : Kubernetes.StatefulSet.Type) -> k8s.StatefulSet cm)
                  statefulsets

          let transformDeployments =
                Prelude.List.map
                  Kubernetes.Deployment.Type
                  k8s
                  (\(cm : Kubernetes.Deployment.Type) -> k8s.Deployment cm)
                  deployments

          let transformIngresses =
                Prelude.List.map
                  Kubernetes.Ingress.Type
                  k8s
                  (\(cm : Kubernetes.Ingress.Type) -> k8s.Ingress cm)
                  ingresses

          in    transformSecrets
              # transformServices
              # transformDeployments
              # transformStatefulset
              # transformIngresses

in      \(app : ../types/Application.dhall)
    ->  { apiVersion = "v1", kind = "List", items = renderResources app }
