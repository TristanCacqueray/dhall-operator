let Prelude = ../Prelude.dhall

let Volume = ../types/Volume.dhall

let Service = ../types/Service.dhall

let ServiceType = ../types/ServiceType.dhall

let Env = ../types/Env.dhall

let EnvSecret = ../types/EnvSecret.dhall

let service-image = "registry.fedoraproject.org/fedora:31"

let spaceSep = Prelude.Text.concatSep " "

let newlineSep = Prelude.Text.concatSep "\n"

let getPort =
          \(local : Bool)
      ->  \(port : ../types/Port.dhall)
      ->  let local-port = Natural/show port.container

          in  Prelude.Optional.fold
                Natural
                port.host
                Text
                (     \(port-host : Natural)
                  ->  "--publish ${Natural/show port-host}:${local-port}"
                )
                (if local then "--publish ${local-port}:${local-port}" else "")

let getPorts
    : forall (local : Bool) -> forall (service : Service) -> List Text
    =     \(local : Bool)
      ->  \(service : Service)
      ->  Prelude.Optional.fold
            (List ../types/Port.dhall)
            service.ports
            (List Text)
            (     \(some : List ../types/Port.dhall)
              ->  Prelude.List.map ../types/Port.dhall Text (getPort local) some
            )
            ([] : List Text)

let serviceCommand =
          \(app : ../types/Application.dhall)
      ->  \(action : List Text)
      ->  \(rm : Bool)
      ->  \(local : Bool)
      ->  \(service : Service)
      ->  \(container : ../types/Container.dhall)
      ->  \(detach : Bool)
      ->  let setVolume =
                    \(prefix : Text)
                ->  Prelude.List.map
                      Volume
                      Text
                      (     \(volume : Volume)
                        ->  "--volume=${prefix}${volume.name}:${volume.dir}"
                      )

          let setEnv =
                Prelude.List.map
                  Env
                  Text
                  (\(env : Env) -> "--env=${env.mapKey}='${env.mapValue}'")

          let toggle =
                    \(toggle : Bool)
                ->  \(value : Text)
                ->  Prelude.Bool.fold
                      toggle
                      (List Text)
                      [ value ]
                      ([] : List Text)

          let setSecretEnv =
                Prelude.List.map
                  EnvSecret
                  Text
                  (     \(env : EnvSecret)
                    ->  let value =
                              Prelude.Bool.fold
                                rm
                                Text
                                "\$${env.secret}_${env.key}"
                                "{{ _${env.secret}_${env.key}.stdout }}"

                        in  "\"--env=${env.name}='${value}'\""
                  )

          in  spaceSep
                (   [ "podman" ]
                  # action
                  # [ "--name", "${app.name}-${service.name}" ]
                  # toggle service.privileged "--privileged"
                  # toggle detach "--detach"
                  # setVolume "${app.name}-" (app.volumes service.type)
                  # setVolume "" (app.secrets service.type)
                  # setEnv (app.environs service.type)
                  # setSecretEnv (app.env-secrets service.type)
                  # toggle local "--network=host"
                  # toggle rm "--rm"
                  # [ container.image ]
                  # ../functions/getCommandQuoted.dhall container
                )

let renderCommands
    : forall (app : ../types/Application.dhall) -> Text
    =     \(app : ../types/Application.dhall)
      ->  let pod-name = "${app.name}"

          let serviceCommandRun =
                serviceCommand app [ "run", "--pod", app.name ] True False

          let volume-path =
                    \(volume : Text)
                ->  "\$(podman volume inspect ${volume} --format '{{.Mountpoint}}')"

          let writeConf =
                    \(volume : Volume)
                ->  Prelude.Text.concat
                      (   [ ''
                            # Volume ${volume.name}
                            podman volume create ${app.name}-${volume.name} || true
                            VOLPATH=$(podman volume inspect ${app.name}-${volume.name} --format '{{.Mountpoint}}')
                            ''
                          ]
                        # Prelude.List.map
                            ../types/File.dhall
                            Text
                            (     \(conf : ../types/File.dhall)
                              ->  ''
                                  mkdir -p $VOLPATH/$(dirname ${conf.path})
                                  cat << EOF > $VOLPATH/${conf.path}
                                  ${conf.content}
                                  EOF
                                  ''
                            )
                            volume.files
                      )

          let writeVolumes =
                    \(volumes : List Volume)
                ->  newlineSep (Prelude.List.map Volume Text writeConf volumes)

          let readSecret =
                    \(env : EnvSecret)
                ->  let volume-path = volume-path env.secret

                    in  "${env.secret}_${env.key}=\$(cat ${volume-path}/${env.key})'"

          let readEnvSecrets =
                Prelude.List.map
                  EnvSecret
                  Text
                  readSecret
                  (app.env-secrets ServiceType._All)

          let setHosts =
                Prelude.List.map
                  Service
                  Text
                  (     \(service : Service)
                    ->  "--add-host=${service.name}:127.0.0.1"
                  )

          let serviceCommandsInit =
                    \(service : Service)
                ->  Prelude.List.map
                      ../types/Container.dhall
                      Text
                      (     \(container : ../types/Container.dhall)
                        ->  serviceCommandRun service container False
                      )
                      ( ../functions/getInitContainers.dhall
                          service.init-containers
                      )

          let serviceCommands =
                    \(service : Service)
                ->  newlineSep
                      (   serviceCommandsInit service
                        # [ serviceCommandRun service service.container True ]
                      )

          let getAllPorts =
                Prelude.Text.concatSep
                  " "
                  ( Prelude.List.fold
                      (List Text)
                      ( Prelude.List.map
                          Service
                          (List Text)
                          (getPorts False)
                          app.services
                      )
                      (List Text)
                      (     \(ports : List Text)
                        ->  \(acc : List Text)
                        ->  ports # acc
                      )
                      ([] : List Text)
                  )

          let init =
                [ "#!/bin/bash -ex"
                , "podman pod create --name ${app.name} " ++ getAllPorts
                ]

          let {- podman pod doesn't seems to set dns, create a first pod for that...
              -}
              dnsFix =
                [ Prelude.Text.concatSep
                    " "
                    (   [ "podman"
                        , "run"
                        , "--pod"
                        , pod-name
                        , "--name"
                        , "${pod-name}-dns"
                        , "--detach"
                        ]
                      # setHosts app.services
                      # [ service-image, "sleep", "infinity" ]
                    )
                ]

          let volumesCommand = [ writeVolumes (app.volumes ServiceType._All) ]

          let servicesCommand =
                Prelude.List.map Service Text serviceCommands app.services

          let start =
                [ "podman pod start ${app.name}"
                , "echo 'Press enter to stop'"
                , "read"
                , "set +x"
                , "podman pod kill ${app.name}"
                , "podman pod rm -f ${app.name}"
                , "podman volume rm -af"
                ]

          in  newlineSep
                (   init
                  # volumesCommand
                  # dnsFix
                  # readEnvSecrets
                  # servicesCommand
                  # start
                  # [ "" ]
                )

in  { RenderCommands = renderCommands, RenderCommand = serviceCommand }
