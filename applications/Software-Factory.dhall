{- This file just contains podenv definition to generate Containerfiles

Rebuild with:

export PODENV_HUB=~/git/github.com/podenv/hub/package.dhall
export PODENV_PRELUDE=~/git/github.com/podenv/podenv/podenv/dhall/package.dhall
dhall text <<< '(./Software-Factory.dhall).Generate' | tee containers.sh
bash -ex containers.sh
-}
let Podenv =
        env:PODENV_PRELUDE
      ? ~/git/github.com/podenv/podenv/podenv/dhall/package.dhall

let Hub = env:PODENV_HUB ? ~/git/github.com/podenv/hub/package.dhall

let sf-version = { major = 3, minor = 4 }

let sf-version-sep =
          \(sep : Text)
      ->  Natural/show sf-version.major ++ sep ++ Natural/show sf-version.minor

let sf-version-str = sf-version-sep "-"

let sf-version-tag = sf-version-sep "."

let sf-version-repo =
          "https://softwarefactory-project.io/repos/sf-release-"
      ++  sf-version-sep "."
      ++  ".rpm"

let repo = "software-factory"

let base-image-name = "${repo}/base:${sf-version-tag}"

let python-image-name = "${repo}/base-python:${sf-version-tag}"

let install = Hub.Runtimes.Centos.Install

let NL = "\n"

let comment =
          \(comment : Text)
      ->  Podenv.Schemas.Task::{ command = Some "${NL}# ${comment}" }

let systemdComment = comment "Import systemd service configuration"

let env = \(env : Text) -> Podenv.Schemas.Task::{ command = Some "ENV ${env}" }

let user =
      \(user : Text) -> Podenv.Schemas.Task::{ command = Some "USER ${user}" }

let run = \(cmd : Text) -> Podenv.Schemas.Task::{ shell = Some "${cmd}" }

let cmd = \(cmd : Text) -> Podenv.Schemas.Task::{ command = Some "CMD ${cmd}" }

let getImage =
          \(image : Optional Text)
      ->  Hub.Prelude.Optional.fold Text image Text (\(some : Text) -> some) ""

let mapEnv = Hub.Prelude.List.map Podenv.Types.Env Text

let mkChildEnv =
          \(parent : Text)
      ->  \(name : Text)
      ->  \(tasks : List Podenv.Types.Task)
      ->  Podenv.Schemas.Env::{
          , name = "sf-${sf-version-str}-${name}"
          , image = Some "localhost/${repo}/${name}:${sf-version-tag}"
          , description = Some "Software Factory ${name}"
          , hostname = Some "localhost"
          , container-file =
              Some
                (   [ Podenv.Schemas.Task::{
                      , command =
                          Some "FROM ${repo}/${parent}:${sf-version-tag}"
                      }
                    ]
                  # tasks
                )
          }

let noPre = [] : List Podenv.Types.Task

let noExtra = [] : List Text

let mkSubService =
          \(parent : Text)
      ->  \(name : Text)
      ->  \(pre : List Podenv.Types.Task)
      ->  \(extras : List Text)
      ->  \(tasks : List Podenv.Types.Task)
      ->  mkChildEnv
            "${parent}"
            "${parent}-${name}"
            (   pre
              # [ install ([ "${parent}-${name}" ] # extras) ]
              # tasks
              # [ user "${parent}" ]
            )

let {- The main base image
    -} Base =
      (     \(env : Podenv.Types.Env)
        ->      env
            //  { container-file =
                    Hub.Functions.addTasks
                      env.container-file
                      [ Hub.Runtimes.Centos.Update ]
                }
      )
        ( Hub.Runtimes.Centos.Create.EL7
            Podenv.Schemas.Env::{
            , name = "sf-${sf-version-str}-base"
            , image = Some "localhost/${base-image-name}"
            , description = Some "Software Factory base image"
            , packages = Some [ sf-version-repo ]
            }
        )

let Zookeeper =
      mkChildEnv
        "base"
        "zookeeper"
        [ install [ "zookeeper-lite" ]
        , systemdComment
        , env
            "CLASSPATH=/usr/share/java/jline.jar:/usr/share/java/log4j.jar:/usr/share/java/slf4j/slf4j-api.jar:/usr/share/java/slf4j/slf4j-log4j12.jar:/usr/share/java/zookeeper.jar"
        , env "ZK_HEAP_LIMIT=2g"
        , user "zookeeper"
        , cmd "/usr/libexec/zookeeper"
        ]

let {- An intermediate image to share common python dependencies
    -} Python =
      mkChildEnv
        "base"
        "base-python"
        [ install [ "Cython", "python3-kazoo", "python3-statsd" ] ]

let mkZuulService = mkSubService "zuul"

let Zuul =
      { Base =
          mkChildEnv
            "base-python"
            "zuul"
            [ install [ "zuul", "git-daemon" ]
            , run "rm -f /etc/zuul/main.yaml /etc/zuul/zuul.conf"
            ]
      , Scheduler =
          mkZuulService
            "scheduler"
            noPre
            [ "http://koji.softwarefactory-project.io/kojifiles/packages/python3-psycopg2/2.5.1/4.el7/x86_64/python3-psycopg2-2.5.1-4.el7.x86_64.rpm"
            ]
            [ cmd "/usr/bin/zuul-scheduler -d" ]
      , Web =
          mkZuulService
            "web"
            noPre
            [ "zuul-webui"
            , "http://koji.softwarefactory-project.io/kojifiles/packages/python3-psycopg2/2.5.1/4.el7/x86_64/python3-psycopg2-2.5.1-4.el7.x86_64.rpm"
            ]
            [ run
                (     "sed -e 's/top:51px//' -e 's/margin-top:72px//' "
                  ++  "-i /usr/share/zuul/static/css/main.*.css && "
                  ++  "sed -e 's#<script type=.text/javascript. src=./static/js/topmenu.js.></script>##' "
                  ++  "-i /usr/share/zuul/index.html && "
                  ++  "ln -s /usr/share/zuul/ /usr/share/zuul/zuul && "
                  ++  "ln -s /usr/share/zuul/ /usr/lib/python3.6/site-packages/zuul/web/zuul && "
                  ++  "ln -s /usr/share/zuul/ /usr/lib/python3.6/site-packages/zuul/web/static"
                )
            , cmd "/usr/bin/zuul-web -d"
            ]
      , Merger =
          mkZuulService
            "merger"
            [ install [ "centos-release-scl-rh" ] ]
            noExtra
            [ cmd "/usr/bin/zuul-merger -d" ]
      , Executor =
          mkZuulService
            "executor"
            [ install
                [ "centos-release-openshift-origin311"
                , "centos-release-scl-rh"
                ]
            ]
            [ "ara", "origin-clients" ]
            [ cmd "/usr/bin/zuul-executor -d" ]
      }

let mkNodepoolService = mkSubService "nodepool"

let Nodepool =
      { Base =
          mkChildEnv
            "base-python"
            "nodepool"
            [ install [ "nodepool" ], run "rm -f /etc/nodepool/nodepool.yaml" ]
      , Launcher =
          mkNodepoolService
            "launcher"
            [ install [ "centos-release-openshift-origin311" ] ]
            [ "origin-clients" ]
            [ cmd "/usr/bin/nodepool-launcher -d" ]
      }

let {- an image to run zuul-jobs
    -} pod-centos-7 =
          Hub.Runtimes.Centos.Create.EL7
            Podenv.Schemas.Env::{
            , name = "pod-centos-7"
            , image = Some "localhost/${repo}/pod-centos-7"
            , hostname = Some "localhost"
            }
      //  { container-file =
              Hub.Functions.fromText
                ''
                FROM registry.centos.org/centos:7
                # Remove cr once CentOS-7.7 is released
                RUN yum-config-manager --enable cr && yum update -y && \
                  yum install -y sudo rsync git traceroute iproute \
                  python3-setuptools python2-setuptools \
                  python3 python3-devel gcc gcc-c++ unzip bzip2 make cmake


                # Zuul except /bin/pip to be available
                RUN ln -sf /bin/pip3 /bin/pip && /bin/pip3 install --user "tox>=3.8.0"

                # Zuul uses revoke-sudo. We can simulate that by moving the default sudoers to zuul
                # And this will prevent root from using sudo when the file is removed by revoke-sudo
                RUN mv /etc/sudoers /etc/sudoers.d/zuul && grep includedir /etc/sudoers.d/zuul > /etc/sudoers && sed -e 's/.*includedir.*//' -i /etc/sudoers.d/zuul && chmod 440 /etc/sudoers

                # Create fake zuul users
                RUN echo "zuul:x:0:0:root:/root:/bin/bash" >> /etc/passwd

                # Enable root local bin
                ENV PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
                WORKDIR /root

                ''
          }

let Envs =
      [ Base
      , Zookeeper
      , Python
      , Zuul.Base
      , Zuul.Scheduler
      , Zuul.Executor
      , Zuul.Merger
      , Zuul.Web
      , Nodepool.Base
      , Nodepool.Launcher
      , pod-centos-7
      ]

in  { Envs = Envs
    , Generate =
        Hub.Prelude.Text.concatSep
          NL
          (   [ "#!/bin/sh -ex"
              , "# Build Software Factory containers"
              , "# Regenerate the file by running: dhall text <<< '(./Software-Factory.dhall).Generate'"
              , "function generate_containerfiles () {"
              , "  mkdir -p containers/"
              ]
            # mapEnv
                (     \(env : Podenv.Types.Env)
                  ->      "  podenv --expr '(./Software-Factory.dhall).Envs' "
                      ++  "--show-containerfile ${env.name} "
                      ++  "> containers/Containerfile.${env.name}"
                )
                Envs
            # [ "}", "function build_containers () {" ]
            # mapEnv
                (     \(env : Podenv.Types.Env)
                  ->      "  buildah bud -f Containerfile.${env.name} "
                      ++  "-t \$(echo ${getImage
                                          env.image} | sed s/localhost.//) "
                      ++  "containers/ && "
                      ++  "podman tag ${getImage env.image} "
                      ++  "\$(echo ${getImage
                                       env.image} | sed s/localhost/quay.io/)"
                )
                Envs
            # [ "}", "function publish_containers () {" ]
            # mapEnv
                (     \(env : Podenv.Types.Env)
                  ->      "  podman push ${getImage env.image} "
                      ++  "docker://quay.io/"
                      ++  "\$(echo ${getImage env.image} | sed s/localhost.//)"
                )
                Envs
            # [ "}"
              , "generate_containerfiles"
              , "build_containers"
              , "publish_containers"
              , ""
              ]
          )
    }
