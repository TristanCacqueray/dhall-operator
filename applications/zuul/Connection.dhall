let ConnectionParam = { mapKey : Text, mapValue : Text }

let Connection = { name : Text, driver : Text, params : List ConnectionParam }

let Input =
      { name : Text
      , ssh_key : Text
      , connection : Connection
      , projects : List Text
      }

let Helpers = ./helpers.dhall

let Services = Helpers.Services

let Service = ../../types/Service.dhall

let Prelude =
      https://prelude.dhall-lang.org/v12.0.0/package.dhall sha256:aea6817682359ae1939f3a15926b84ad5763c24a3740103202d2eaaea4d01f4c

let Connection/show =
          \(connection : Connection)
      ->      ''
              [connection "${connection.name}"]
              driver=${connection.driver}
              ''
          ++  Prelude.Text.concat
                ( Prelude.List.map
                    ConnectionParam
                    Text
                    (     \(some : ConnectionParam)
                      ->  ''
                          ${some.mapKey}=${some.mapValue}
                          ''
                    )
                    connection.params
                )

in  { Input = Input
    , Application =
            \(input : Input)
        ->  (../../schemas/Application.dhall)::{
            , name = input.name
            , kind = "zuul"
            , services =
                [ Services.ZooKeeper
                , Services.Postgres
                , Helpers.waitForDb Services.Scheduler
                , Services.Executor
                , Services.Web
                ]
            , environs = Helpers.DefaultEnv "db-pass"
            , volumes =
                    \(serviceType : ../../types/ServiceType.dhall)
                ->  let empty = [] : List ../../types/Volume.dhall

                    let first-project =
                          Optional/fold
                            Text
                            (List/head Text input.projects)
                            Text
                            (\(some : Text) -> some)
                            "at-least-one-project-needed"

                    let rest-project = Prelude.List.drop 1 Text input.projects

                    let zuul-conf =
                          { name = "zuul"
                          , dir = "/etc/zuul"
                          , files =
                              [ { path = "zuul.conf"
                                , content =
                                        Helpers.Config.Zuul
                                    ++  ''
                                        [connection "sql"]
                                        driver=sql
                                        dburi=postgresql://zuul:db-pass@db/zuul

                                        ''
                                    ++  Connection/show input.connection
                                }
                              , { path = "main.yaml"
                                , content =
                                        ''
                                        - tenant:
                                            name: local
                                            source:
                                              ${input.connection.name}:
                                                config-projects:
                                                  - ${first-project}
                                                untrusted-projects:
                                        ''
                                    ++  Prelude.Text.concatSep
                                          "\n"
                                          ( Prelude.List.map
                                              Text
                                              Text
                                              (     \(project : Text)
                                                ->  "          - " ++ project
                                              )
                                              rest-project
                                          )
                                    ++  "\n"
                                }
                              , { path = "id_rsa", content = input.ssh_key }
                              ]
                          }

                    in  merge
                          { _All = [ zuul-conf ]
                          , Database = empty
                          , Scheduler = [ zuul-conf ]
                          , Launcher = empty
                          , Executor = [ zuul-conf ]
                          , Gateway = [ zuul-conf ]
                          , Worker = [ zuul-conf ]
                          , Config = empty
                          , Other = empty
                          }
                          serviceType
            }
    }
