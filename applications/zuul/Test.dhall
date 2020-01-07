{-
A test deployment that runs a dummy job every minute...

To instantiate this template, you provide:
  * a deployment name
  * an ssh key (zuul executor fail to start without one)
  * an optional kubeconfig and context name to spawn pods on kubernetes
  * an optional zuul-web port number (default to 9000)
-}

let Input =
      { name : Text
      , ssh_key : Text
      , kubeconfig : Optional Text
      , kubecontext : Optional Text
      , port : Optional Natural
      }

let Helpers = ./helpers.dhall

let Services = Helpers.Services

let Service = ../../types/Service.dhall

in  { Input = Input
    , Application =
            \(input : Input)
        ->  let db-password = "secret"

            let {- use localhost unless there is a kubeconfig
                -} nodeset =
                  Optional/fold
                    Text
                    input.kubeconfig
                    Text
                    (\(some : Text) -> "centos-pod")
                    "localhost"

            let zuul-config-repo =
                  [ { path = "zuul.yaml"
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

                        - nodeset:
                            name: localhost
                            nodes: []

                        - nodeset:
                            name: centos-pod
                            nodes:
                              - name: centos-pod
                                label: pod-centos

                        - job:
                            name: base
                            parent: null
                            run: base.yaml
                            nodeset: ${nodeset}

                        - job:
                            name: test-job

                        - project:
                            periodic:
                              jobs:
                                - test-job
                        ''
                    }
                  , { path = "base.yaml"
                    , content =
                        ''
                        - hosts: all
                          tasks:
                            - debug: msg='Demo job is running'
                            - pause: seconds=30
                        ''
                    }
                  ]

            let kube-context =
                  Optional/fold
                    Text
                    input.kubecontext
                    Text
                    (\(some : Text) -> some)
                    ""

            let nodepool-conf =
                  ''
                  labels:
                    - name: pod-centos
                  providers:
                    - name: kube-cluster
                      driver: openshiftpods
                      context: ${kube-context}
                      max-pods: 4
                      pools:
                      - name: default
                        labels:
                          - name: pod-centos
                            image: quay.io/software-factory/pod-centos-7
                            python-path: /bin/python2
                  ''

            let {- add a nodepool-launcher service when there is a kubeconfig
                -} launcher-service =
                  Optional/fold
                    Text
                    input.kubeconfig
                    (List Service)
                    (\(some : Text) -> [ Services.Launcher ])
                    ([] : List Service)

            in  (../../schemas/Application.dhall)::{
                , name = input.name
                , kind = "zuul"
                , services =
                      [ Services.InternalConfig
                      , Services.ZooKeeper
                      , Services.Postgres
                      , Helpers.waitForDb Services.Scheduler
                      , Services.Executor
                      ,     Services.Web
                        //  { ports =
                                Some
                                  [ (../../schemas/Port.dhall)::{
                                    , host =
                                        Some
                                          ( Optional/fold
                                              Natural
                                              input.port
                                              Natural
                                              (\(some : Natural) -> some)
                                              9000
                                          )
                                    , container = 9000
                                    , name = "api"
                                    }
                                  ]
                            }
                      ]
                    # launcher-service
                , environs = Helpers.DefaultEnv db-password
                , volumes =
                        \(serviceType : ../../types/ServiceType.dhall)
                    ->  let empty = [] : List ../../types/Volume.dhall

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
                                            dburi=postgresql://zuul:${db-password}@db/zuul

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
                                  , { path = "id_rsa", content = input.ssh_key }
                                  ]
                              }

                        let config-repo =
                              { name = "config"
                              , dir = "/config"
                              , files = zuul-config-repo
                              }

                        let nodepool-conf =
                              Optional/fold
                                Text
                                input.kubeconfig
                                (List ../../types/Volume.dhall)
                                (     \(kubeconfig : Text)
                                  ->  [ { name = "nodepool"
                                        , dir = "/etc/nodepool"
                                        , files =
                                            [ { path = "nodepool.yaml"
                                              , content =
                                                      Helpers.Config.Nodepool
                                                  ++  nodepool-conf
                                              }
                                            , { path = "kube.config"
                                              , content = kubeconfig
                                              }
                                            ]
                                        }
                                      ]
                                )
                                empty

                        in  merge
                              { _All =
                                  [ zuul-conf, config-repo ] # nodepool-conf
                              , Database = empty
                              , Scheduler = [ zuul-conf ]
                              , Launcher = nodepool-conf
                              , Executor = [ zuul-conf ]
                              , Gateway = [ zuul-conf ]
                              , Worker = [ zuul-conf ]
                              , Config = [ config-repo ]
                              , Other = empty
                              }
                              serviceType
                }
    }
