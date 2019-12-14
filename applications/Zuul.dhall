let Container = ../schemas/Container.dhall

let Service = ../schemas/Service.dhall

let ServiceType = ../types/ServiceType.dhall

let org = "quay.io/software-factory"

let sf-version = "3.4"

let zk-image = "${org}/zookeeper:${sf-version}"

let zuul-base = "${org}/zuul:${sf-version}"

let zuul-image = \(name : Text) -> "${org}/zuul-${name}:${sf-version}"

let nodepool-image = \(name : Text) -> "${org}/nodepool-${name}:${sf-version}"

let waitFor =
          \(hostname : Text)
      ->  \(port : Natural)
      ->  let test =
                    "python -c '"
                ++  "import socket; "
                ++  "socket.socket(socket.AF_INET, socket.SOCK_STREAM)"
                ++  ".connect((\\\"${hostname}\\\", ${Natural/show port}))'"

          let debug = "waiting for ${hostname}:${Natural/show port}"

          in  [ "sh", "-c", "until ${test}; do echo '${debug}'; sleep 1; done" ]

let {- the list of zuul services -} control-plane-services =
          \(port : Natural)
      ->  [ Service::{
            , name = "zk"
            , container = Container::{ image = zk-image }
            }
          , Service::{
            , name = "db"
            , type = ServiceType.Database
            , container =
                Container::{ image = "docker.io/library/postgres:12.1" }
            }
          , Service::{
            , name = "config"
            , type = ServiceType.Config
            , container =
                { image = zuul-base
                , command =
                    Some
                      [ "sh"
                      , "-c"
                      ,     "cd /config/config ;"
                        ++  "git config --global user.email zuul@localhost ;"
                        ++  "git config --global user.name Zuul ;"
                        ++  "git init . ;"
                        ++  "git add -A . ;"
                        ++  "git commit -m init ;"
                        ++  "git daemon --export-all --reuseaddr --verbose --base-path=/config/ /config/"
                      ]
                }
            }
          , Service::{
            , name = "scheduler"
            , type = ServiceType.Scheduler
            , init-containers =
                Some
                  [ { image = zuul-base
                    , command = Some (waitFor "config" 9418)
                    }
                  , { image = zuul-base, command = Some (waitFor "db" 5432) }
                  ]
            , container =
                { image = zuul-image "scheduler"
                , command = Some [ "zuul-scheduler", "-d" ]
                }
            }
          , Service::{
            , name = "merger"
            , type = ServiceType.Worker
            , init-containers =
                Some
                  [ { image = zuul-base
                    , command = Some (waitFor "scheduler" 4730)
                    }
                  ]
            , container =
                { image = zuul-image "merger"
                , command = Some [ "zuul-merger", "-d" ]
                }
            }
          , Service::{
            , name = "executor"
            , type = ServiceType.Executor
            , privileged = True
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
          , Service::{
            , name = "web"
            , type = ServiceType.Gateway
            , ports = Some [ { host = port, container = 9000 } ]
            , init-containers =
                Some
                  [ { image = zuul-base
                    , command = Some (waitFor "scheduler" 4730)
                    }
                  ]
            , container =
                { image = zuul-image "web"
                , command = Some [ "zuul-web", "-d" ]
                }
            }
          , Service::{
            , name = "launcher"
            , type = ServiceType.Launcher
            , container =
                { image = nodepool-image "launcher"
                , command = Some [ "nodepool-launcher", "-d" ]
                }
            }
          ]

let {- the service envs -} control-plane-environ =
          \(db-password : Text)
      ->  let db-env
              : List ../types/Env.dhall
              = toMap
                  { POSTGRES_USER = "zuul", POSTGRES_PASSWORD = db-password }

          let kube-env
              : List ../types/Env.dhall
              = toMap { KUBECONFIG = "/etc/nodepool/kube.config" }

          let empty = [] : List ../types/Env.dhall

          let {- associate environment to each service type
              -} result =
                    \(serviceType : ServiceType)
                ->  merge
                      { _All = db-env
                      , Database = db-env
                      , Config = empty
                      , Scheduler = empty
                      , Launcher = kube-env
                      , Executor = empty
                      , Gateway = empty
                      , Worker = empty
                      , Other = empty
                      }
                      serviceType

          in  result

let {- the service confs -} control-plane-config =
          \(db-password : Text)
      ->  \(ssh-key : Text)
      ->  \(zuul-config-files : List ../types/File.dhall)
      ->  \(kube-config : Text)
      ->  \(context-name : Text)
      ->  let zuul-conf =
                { name = "etc-zuul"
                , dir = "/etc/zuul"
                , files =
                    [ { path = "zuul.conf"
                      , content =
                          ''
                          [gearman]
                          server=scheduler

                          [gearman_server]
                          start=true

                          [zookeeper]
                          hosts=zk

                          [scheduler]
                          tenant_config=/etc/zuul/main.yaml

                          [connection "sql"]
                          driver=sql
                          dburi=postgresql://zuul:${db-password}@db/zuul

                          [web]
                          listen_address=0.0.0.0

                          [executor]
                          private_key_file=/etc/zuul/id_rsa

                          [connection "local-git"]
                          driver=git
                          baseurl=git://config/
                          ''
                      }
                    , { path = "main.yaml"
                      , content =
                          ''
                          - tenant:
                              name: local
                              source:
                                local-git:
                                  config-projects:
                                    - config
                          ''
                      }
                    , { path = "id_rsa", content = ssh-key }
                    ]
                }

          let nodepool =
                ''
                labels:
                  - name: pod-centos-7
                providers:
                  - name: kube-cluster
                    driver: openshiftpods
                    context: ${context-name}
                    max-pods: 4
                    pools:
                    - name: main
                      labels:
                        - name: pod-centos-7
                          image: quay.io/software-factory/pod-centos-7:${sf-version}
                          python-path: /bin/python2
                ''

          let nodepool-conf =
                { name = "etc-nodepool"
                , dir = "/etc/nodepool"
                , files =
                    [ { path = "nodepool.yaml"
                      , content =
                              ''
                              zookeeper-servers:
                                - host: zk
                                  port: 2181
                              webapp:
                                port: 5000
                              ''
                          ++  nodepool
                      }
                    , { path = "kube.config", content = kube-config }
                    ]
                }

          let config-repo =
                { name = "config", dir = "/config", files = zuul-config-files }

          let empty = [] : List ../types/Volume.dhall

          let all = [ zuul-conf, nodepool-conf, config-repo ]

          let {- Associate volumes to each service type
              -} result =
                    \(serviceType : ServiceType)
                ->  merge
                      { _All = all
                      , Database = empty
                      , Scheduler = [ zuul-conf ]
                      , Launcher = [ nodepool-conf ]
                      , Executor = [ zuul-conf ]
                      , Gateway = [ zuul-conf ]
                      , Worker = [ zuul-conf ]
                      , Config = [ config-repo ]
                      , Other = empty
                      }
                      serviceType

          in  result

let {- An example cluster that just runs a job every minute...
    -} LocalCluster =
          \(name : Text)
      ->  let db-password = "secret"

          let port = 9000

          let kube-config =
                ''
                apiVersion: v1
                kind: Config
                clusters:
                - name: local
                  cluster:
                    server: http://localhost:8043
                users:
                - name: local
                  user:
                    token: 42
                contexts:
                - name: /test-cluster/
                  context:
                    cluster: local
                    user: local
                current-context: /test-cluster/

                ''

          let default-context = "/test-cluster/"

          let executor-key = ./data/id_rsa as Text

          let zuul-config =
                [ { path = "config/zuul.yaml"
                  , content =
                      ''
                      - pipeline:
                          name: periodic
                          manager: independent
                          trigger:
                            timer:
                              - time: '* * * * * *'
                          success:
                            sql:
                          failure:
                            sql:

                      - job:
                          name: base
                          parent: null
                          run: base.yaml

                      - job:
                          name: test-job

                      - project:
                          periodic:
                            jobs:
                              - test-job
                      ''
                  }
                , { path = "config/base.yaml"
                  , content =
                      ''
                      - hosts: localhost
                        tasks:
                          - debug: msg='Demo job is running'
                          - pause: seconds=30
                      ''
                  }
                ]

          in    { name = name
                , services = control-plane-services port
                , environs = control-plane-environ db-password
                , volumes =
                    control-plane-config
                      db-password
                      executor-key
                      zuul-config
                      kube-config
                      default-context
                }
              : ../types/Application.dhall

in  { LocalCluster = LocalCluster }
