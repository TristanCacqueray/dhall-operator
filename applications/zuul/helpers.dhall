let Container = ../../schemas/Container.dhall

let Service = ../../schemas/Service.dhall

let Port = ../../schemas/Port.dhall

let Env = ../../types/Env.dhall

let ServiceType = ../../types/ServiceType.dhall

let waitFor = ../../functions/waitFor.dhall

let org = "quay.io/software-factory"

let sf-version = "3.4"

let zk-image = "${org}/zookeeper:${sf-version}"

let zuul-base = "${org}/zuul:${sf-version}"

let zuul-image = \(name : Text) -> "${org}/zuul-${name}:${sf-version}"

let nodepool-image = \(name : Text) -> "${org}/nodepool-${name}:${sf-version}"

let Services =
      { ZooKeeper =
          Service::{
          , name = "zk"
          , container = Container::{ image = zk-image }
          , volume-size = Some 1
          , ports = Some [ Port::{ container = 2181, name = "zk" } ]
          }
      , Postgres =
          Service::{
          , name = "db"
          , type = ServiceType.Database
          , ports = Some [ Port::{ container = 5432, name = "pg" } ]
          , volume-size = Some 1
          , container = Container::{ image = "docker.io/library/postgres:12.1" }
          }
      , InternalConfig =
          Service::{
          , name = "config"
          , type = ServiceType.Config
          , ports = Some [ Port::{ container = 9418, name = "git" } ]
          , container =
              { image = zuul-base
              , command =
                  Some
                    [ "sh"
                    , "-c"
                    ,     "mkdir -p /git/config; cp /config/* /git/config;"
                      ++  "cd /git/config ;"
                      ++  "git config --global user.email zuul@localhost ;"
                      ++  "git config --global user.name Zuul ;"
                      ++  "git init . ;"
                      ++  "git add -A . ;"
                      ++  "git commit -m init ;"
                      ++  "git daemon --export-all --reuseaddr --verbose --base-path=/git/ /git/"
                    ]
              }
          }
      , Scheduler =
          Service::{
          , name = "scheduler"
          , type = ServiceType.Scheduler
          , ports = Some [ Port::{ container = 4730, name = "gearman" } ]
          , volume-size = Some 5
          , container =
              { image = zuul-image "scheduler"
              , command = Some [ "zuul-scheduler", "-d" ]
              }
          }
      , Merger =
          Service::{
          , name = "launcher"
          , type = ServiceType.Launcher
          , container =
              { image = nodepool-image "launcher"
              , command = Some [ "nodepool-launcher", "-d" ]
              }
          }
      , Executor =
          Service::{
          , name = "executor"
          , type = ServiceType.Executor
          , volume-size = Some 0
          , privileged = True
          , ports = Some [ Port::{ container = 7900, name = "finger" } ]
          , init-containers =
              Some
                [ { image = zuul-base
                  , command = Some (waitFor "scheduler" 4730)
                  }
                ]
          , container =
              { image = zuul-image "executor"
              , command = Some [ "zuul-executor", "-d" ]
              }
          }
      , Web =
          Service::{
          , name = "web"
          , type = ServiceType.Gateway
          , ports =
              Some
                [ Port::{ host = Some 9000, container = 9000, name = "api" } ]
          , init-containers =
              Some
                [ { image = zuul-base
                  , command = Some (waitFor "scheduler" 4730)
                  }
                ]
          , container =
              { image = zuul-image "web", command = Some [ "zuul-web", "-d" ] }
          }
      , Launcher =
          Service::{
          , name = "launcher"
          , type = ServiceType.Launcher
          , container =
              { image = nodepool-image "launcher"
              , command = Some [ "nodepool-launcher", "-d" ]
              }
          }
      }

let waitFor =
          \(endpoint : { host : Text, port : Natural })
      ->  \(service : Service.Type)
      ->      service
          //  { init-containers =
                  Some
                    [ { image = zuul-base
                      , command =
                          Some
                            ( ../../functions/waitFor.dhall
                                endpoint.host
                                endpoint.port
                            )
                      }
                    ]
              }

in  { Services = Services
    , Images = { Base = zuul-base }
    , waitForDb = waitFor { host = "db", port = 5432 }
    , DefaultEnv =
            \(db-password : Text)
        ->  let db-env =
                  toMap
                    { POSTGRES_USER = "zuul", POSTGRES_PASSWORD = db-password }

            let nodepool-env =
                  toMap
                    { KUBECONFIG = "/etc/nodepool/kube.config"
                    , OS_CLIENT_CONFIG_FILE = "/etc/nodepool/clouds.yaml"
                    }

            let empty = [] : List Env

            let {- associate environment to each service type
                -} result =
                      \(serviceType : ServiceType)
                  ->  merge
                        { _All = db-env
                        , Database = db-env
                        , Config = empty
                        , Scheduler = empty
                        , Launcher = nodepool-env
                        , Executor = empty
                        , Gateway = empty
                        , Worker = empty
                        , Other = empty
                        }
                        serviceType

            in  result
    , Config =
        { Zuul =
            ''
            [gearman]
            server=scheduler

            [gearman_server]
            start=true

            [zookeeper]
            hosts=zk

            [scheduler]
            tenant_config=/etc/zuul/main.yaml

            [web]
            listen_address=0.0.0.0

            [executor]
            private_key_file=/etc/zuul/id_rsa

            ''
        , Nodepool =
            ''
            zookeeper-servers:
              - host: zk
                port: 2181
            webapp:
              port: 5000

            ''
        }
    }
