let Prelude = ../Prelude.dhall

let Volume = ../types/Volume.dhall

let Service = ../types/Service.dhall

let ServiceType = ../types/ServiceType.dhall

let Env = ../types/Env.dhall

let service-image = "registry.fedoraproject.org/fedora:31"

let renderCommands
    : forall (app : ../types/Application.dhall) -> Text
    =     \(app : ../types/Application.dhall)
      ->  let pod-name = "${app.name}"

          let spaceSep = Prelude.Text.concatSep " "

          let newlineSep = Prelude.Text.concatSep "\n"

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
                                  ${conf.content}EOF
                                  ''
                            )
                            volume.files
                      )

          let writeVolumes =
                    \(volumes : List Volume)
                ->  newlineSep (Prelude.List.map Volume Text writeConf volumes)

          let setEnv =
                Prelude.List.map
                  Env
                  Text
                  (\(env : Env) -> "--env=${env.mapKey}='${env.mapValue}'")

          let setVolume =
                Prelude.List.map
                  Volume
                  Text
                  (     \(volume : Volume)
                    ->  "--volume=${app.name}-${volume.name}:${volume.dir}"
                  )

          let setHosts =
                Prelude.List.map
                  Service
                  Text
                  (     \(service : Service)
                    ->  "--add-host=${service.name}:127.0.0.1"
                  )

          let serviceCommandRun =
                    \(service : ../types/Service.dhall)
                ->  \(container : ../types/Container.dhall)
                ->  \(detach : Bool)
                ->  let isPrivileged =
                          Prelude.Bool.fold
                            service.privileged
                            (List Text)
                            [ "--privileged" ]
                            ([] : List Text)

                    let isDetached =
                          Prelude.Bool.fold
                            detach
                            (List Text)
                            [ "--detach" ]
                            ([] : List Text)

                    in  spaceSep
                          (   [ "podman"
                              , "run"
                              , "--pod"
                              , "${app.name}"
                              , "--name"
                              , "${app.name}-${service.name}"
                              ]
                            # isPrivileged
                            # isDetached
                            # setVolume (app.volumes service.type)
                            # setEnv (app.environs service.type)
                            # [ "--rm", container.image ]
                            # ../functions/getCommandQuoted.dhall container
                          )

          let serviceCommandsInit =
                    \(service : ../types/Service.dhall)
                ->  Prelude.List.map
                      ../types/Container.dhall
                      Text
                      (     \(container : ../types/Container.dhall)
                        ->  serviceCommandRun service container False
                      )
                      ( ../functions/getInitContainers.dhall
                          service.init-containers
                      )

          let serviceCommand =
                    \(service : ../types/Service.dhall)
                ->  newlineSep
                      (   serviceCommandsInit service
                        # [ serviceCommandRun service service.container True ]
                      )

          let setPort =
                    \(port : ../types/Port.dhall)
                ->  Prelude.Optional.fold
                      Natural
                      port.host
                      Text
                      (     \(port-host : Natural)
                        ->      "--publish ${Natural/show port-host}:"
                            ++  "${Natural/show port.container}"
                      )
                      ""

          let getPort
              : forall (service : ../types/Service.dhall) -> List Text
              =     \(service : ../types/Service.dhall)
                ->  Prelude.Optional.fold
                      (List ../types/Port.dhall)
                      service.ports
                      (List Text)
                      (     \(some : List ../types/Port.dhall)
                        ->  Prelude.List.map
                              ../types/Port.dhall
                              Text
                              setPort
                              some
                      )
                      ([] : List Text)

          let getPorts =
                Prelude.Text.concatSep
                  " "
                  ( Prelude.List.fold
                      (List Text)
                      ( Prelude.List.map
                          ../types/Service.dhall
                          (List Text)
                          getPort
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
                , "podman pod create --name ${app.name} " ++ getPorts
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
                Prelude.List.map Service Text serviceCommand app.services

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
                  # servicesCommand
                  # start
                  # [ "" ]
                )

in  renderCommands
