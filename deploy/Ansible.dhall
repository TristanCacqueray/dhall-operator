let Prelude = ../Prelude.dhall

let Podman = ./Podman.dhall

let TaskCommonType = { name : Text, when : Optional Text }

let TaskCommonDefault = { when = None Text }

let Tasks =
      { File = { path : Text, state : Text }
      , LineInFile = { line : Text, regexp : Text, path : Text }
      , Copy =
          { content : Text
          , dest : Text
          , serole : Text
          , setype : Text
          , seuser : Text
          }
      , Command = { name : Text, command : Text }
      , Shell =
          { name : Text
          , shell : Text
          , register : Optional Text
          , changed_when : Optional Text
          }
      , Systemd =
          { name : Text, scope : Text, state : Text, daemon_reload : Bool }
      , Service = { name : Text, state : Text }
      }

let Task =
      < Command : Tasks.Command
      | Shell : Tasks.Shell
      | File : { file : Tasks.File }
      | Copy : { copy : Tasks.Copy }
      | LineInFile : { become : Bool, lineinfile : Tasks.LineInFile }
      | Service : { service : Tasks.Service }
      | Systemd : { systemd : Tasks.Systemd }
      >

let mkTask =
      { File = \(task : Tasks.File) -> Task.File { file = task }
      , Copy = \(task : Tasks.Copy) -> Task.Copy { copy = task }
      , LineInFile =
              \(task : Tasks.LineInFile)
          ->  Task.LineInFile { become = True, lineinfile = task }
      , Command = \(task : Tasks.Command) -> Task.Command task
      , Shell = \(task : Tasks.Shell) -> Task.Shell task
      , Service = \(task : Tasks.Service) -> Task.Service { service = task }
      , Systemd = \(task : Tasks.Systemd) -> Task.Systemd { systemd = task }
      }

let Play = { Type = { hosts : Text, tasks : List Task }, default = {=} }

let Service = ../types/Service.dhall

let ServiceType = ../types/ServiceType.dhall

let Volume = ../types/Volume.dhall

let concatTasks = Prelude.List.concat Task

let mkConfig =
          \(app : ../types/Application.dhall)
      ->  \(volumes : List Volume)
      ->  let mkConfigDir =
                Prelude.List.map
                  Volume
                  Task
                  (     \(volume : Volume)
                    ->  let volume-name = "${app.name}-${volume.name}"

                        let inspect =
                              "podman volume inspect ${volume-name} --format \"{{'{{'}}.Mountpoint{{'}}'}}\""

                        in  mkTask.Shell
                              { name = "Get or create volume"
                              , register = Some "_volume_${volume.name}"
                              , changed_when = Some
                                  "_volume_${volume.name}.stderr"
                              , shell =
                                      "${inspect} || ( "
                                  ++  "podman volume create ${volume-name} && ${inspect}"
                                  ++  " )"
                              }
                  )
                  volumes

          let mkConfigCopies =
                Prelude.List.map
                  Volume
                  (List Task)
                  (     \(volume : Volume)
                    ->  let mkConfigCopy =
                              Prelude.List.map
                                ../types/File.dhall
                                Task
                                (     \(file : ../types/File.dhall)
                                  ->  Task.Copy
                                        { copy =
                                            { content = file.content
                                            , dest =
                                                    "{{ _volume_${volume.name}.stdout_lines[-1] }}/"
                                                ++  file.path
                                            , seuser = "system_u"
                                            , serole = "object_r"
                                            , setype = "container_file_t"
                                            }
                                        }
                                )

                        in  mkConfigCopy volume.files
                  )
                  volumes

          in  mkConfigDir # concatTasks mkConfigCopies

let mkEnvSecretFact =
      [ mkTask.Command
          { name = "TODO: create fact from secret env volume content"
          , command = "echo: NotImplemented"
          }
      ]

let renderPlaybook
    :     forall (local : Bool)
      ->  forall (app : ../types/Application.dhall)
      ->  List Play.Type
    =     \(local : Bool)
      ->  \(app : ../types/Application.dhall)
      ->  let mkConfig = mkConfig app

          let renderCommand = Podman.RenderCommand app [ "create" ] False True

          let mkService =
                    \(service : Service)
                ->  let service-name = app.name ++ "-" ++ service.name

                    in  [ mkTask.Command
                            { name = "Create container"
                            , command =
                                renderCommand service service.container False
                            }
                        , mkTask.File
                            { path =
                                "{{ ansible_user_dir }}/.config/systemd/user"
                            , state = "directory"
                            }
                        , mkTask.Shell
                            { name = "Create systemd unit"
                            , shell =
                                    "podman generate systemd --name ${service-name} > "
                                ++  "{{ ansible_user_dir }}/.config/systemd/user/${service-name}.service"
                            , register = None Text
                            , changed_when = None Text
                            }
                        , mkTask.Systemd
                            { name = service-name
                            , scope = "user"
                            , state = "started"
                            , daemon_reload = True
                            }
                        ]

          let mkPlay =
                    \(service : Service)
                ->  Play::{
                    , hosts = service.name
                    , tasks =
                          mkConfig (app.volumes service.type)
                        # mkEnvSecretFact
                        # mkService service
                    }

          let mkSinglePlay =
                [ Play::{
                  , hosts = "localhost"
                  , tasks =
                        [ mkTask.LineInFile
                            { path = "/etc/hosts"
                            , line =
                                    "127.0.0.2 "
                                ++  Prelude.Text.concatSep
                                      " "
                                      ( Prelude.List.map
                                          Service
                                          Text
                                          (\(service : Service) -> service.name)
                                          app.services
                                      )
                            , regexp = "^127.0.0.2 .*"
                            }
                        ]
                      # mkConfig (app.volumes ServiceType._All)
                      # mkEnvSecretFact
                      # concatTasks
                          ( Prelude.List.map
                              Service
                              (List Task)
                              mkService
                              app.services
                          )
                  }
                ]

          in        if local

              then  mkSinglePlay

              else  Prelude.List.map Service Play.Type mkPlay app.services

in  { Localhost = renderPlaybook True, Distributed = renderPlaybook False }
