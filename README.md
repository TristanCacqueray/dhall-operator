# dhall-operator: abstract application deployment

> This is a work in progress, integration work is being implemented in
> https://review.opendev.org/#/q/topic:zuul-crd and
> https://softwarefactory-project.io/r/#/q/topic:sf-crd

Given an [Application](types/Application.dhall) object, a deploy function can generate deployment recipe for:

* Podman (using a docker-compose style shell script)
* Ansible playbook
* Kubernetes

The dhall-operator can also be installed as a Kubernetes operator, and the Dhall resources can be used to
deploy an [Application](types/Application.dhall) or any Dhall expression that evaluate to Kubernetes object(s):

```yaml
apiVersion: softwarefactory-project.io/v1alpha1
kind: Dhall
metadata:
  name: demo-app
spec:
  expression: |
    https://raw.githubusercontent.com/TristanCacqueray/dhall-operator/master/deploy/Kubernetes.dhall
    https://raw.githubusercontent.com/TristanCacqueray/dhall-operator/master/examples/Demo.dhall
```


# Abstract application

An Application is composed of:

* [Services](./types/Service.dhall)
* [Volumes](./types/Volume.dhall)
* [Environment](./types/Env.dhall)

Configuration objects are associated to services using an abstract [ServiceType](./types/ServiceType.dhall).


# Demo

A demo application composed of a database and a fake worker:

```dhall
Application::{
, name = "demo"
, services =
    [ Service::{
      , name = "postgres"
      , ports = Some [ Port::{ container = 5432, name = "pg" } ]
      , container = Container::{ image = "docker.io/library/postgres:12.1" }
      }
    , Service::{
      , name = "worker"
      , container =
          Container::{
          , image = "registry.fedoraproject.org/fedora:31"
          , command =
              Some
                [ "sh"
                , "-c"
                ,     "python3 -c '"
                  ++  "import socket, sys; "
                  ++  "socket.socket(socket.AF_INET, socket.SOCK_STREAM)"
                  ++  ".connect((sys.argv[1], 5432))' postgres &&"
                  ++  "echo Connected && sleep infinity"
                ]
          }
      }
    ]
}
```

Deployed with podman:

```console
$ dhall text <<< '(./deploy/Podman.dhall).RenderCommands ./examples/Demo.dhall'
#!/bin/bash -ex
podman pod create --name demo

podman run --pod demo --name demo-dns --detach --add-host=postgres:127.0.0.1 --add-host=worker:127.0.0.1 registry.fedoraproject.org/fedora:31 sleep infinity
podman run --pod demo --name demo-postgres --detach --rm docker.io/library/postgres:12.1
podman run --pod demo --name demo-worker --detach --rm registry.fedoraproject.org/fedora:31 "sh" "-c" "python3 -c 'import socket, sys; socket.socket(socket.AF_INET, socket.SOCK_STREAM).connect((sys.argv[1], 5432))' postgres &&echo Connected && sleep infinity"
podman pod start demo
```

Deployed with ansible:

```yaml
# dhall-to-yaml <<< '(./deploy/Ansible.dhall).Localhost ./examples/Demo.dhall'
- hosts: localhost
  tasks:
    - command: "podman create --name demo-postgres --network=host docker.io/library/postgres:12.1"
      name: "Create container"
    - file:
        path: "{{ ansible_user_dir }}/.config/systemd/user"
        state: directory
    - name: "Create systemd unit"
      shell: "podman generate systemd --name demo-postgres > {{ ansible_user_dir }}/.config/systemd/user/demo-postgres.service"
    - systemd:
        daemon_reload: true
        name: demo-postgres
        scope: user
        state: started
    - command: "podman create --name demo-worker --network=host registry.fedoraproject.org/fedora:31 \"sh\" \"-c\" \"python3 -c 'import socket, sys; socket.socket(socket.AF_INET, socket.SOCK_STREAM).connect((sys.argv[1], 5432))' postgres &&echo Connected && sleep infinity\""
      name: "Create container"
    - file:
        path: "{{ ansible_user_dir }}/.config/systemd/user"
        state: directory
    - name: "Create systemd unit"
      shell: "podman generate systemd --name demo-worker > {{ ansible_user_dir }}/.config/systemd/user/demo-worker.service"
    - systemd:
        daemon_reload: true
        name: demo-worker
        scope: user
        state: started
```

Deployed with kubernetes:

```yaml
# dhall-to-yaml --omit-empty --explain <<< './deploy/Kubernetes.dhall ./examples/Demo.dhall'
apiVersion: v1
items:
  - apiVersion: v1
    kind: Service
    metadata:
      labels:
        app.kubernetes.io/component: postgres
        app.kubernetes.io/instance: demo
        app.kubernetes.io/name: demo
        app.kubernetes.io/part-of: app
      name: postgres
    spec:
      ports:
        - name: pg
          port: 5432
          protocol: TCP
          targetPort: pg
      selector:
        app.kubernetes.io/component: postgres
        app.kubernetes.io/instance: demo
        app.kubernetes.io/name: demo
        app.kubernetes.io/part-of: app
      type: ClusterIP
  - apiVersion: apps/v1
    kind: Deployment
    metadata:
      labels:
        app.kubernetes.io/component: postgres
        app.kubernetes.io/instance: demo
        app.kubernetes.io/name: demo
        app.kubernetes.io/part-of: app
      name: demo-postgres
    spec:
      replicas: 1
      selector:
        matchLabels:
          app.kubernetes.io/component: postgres
          app.kubernetes.io/instance: demo
          app.kubernetes.io/name: demo
          app.kubernetes.io/part-of: app
      template:
        metadata:
          labels:
            app.kubernetes.io/component: postgres
            app.kubernetes.io/instance: demo
            app.kubernetes.io/name: demo
            app.kubernetes.io/part-of: app
          name: postgres
        spec:
          containers:
            - image: docker.io/library/postgres:12.1
              imagePullPolicy: IfNotPresent
              name: postgres
              ports:
                - containerPort: 5432
                  name: pg
  - apiVersion: apps/v1
    kind: Deployment
    metadata:
      labels:
        app.kubernetes.io/component: worker
        app.kubernetes.io/instance: demo
        app.kubernetes.io/name: demo
        app.kubernetes.io/part-of: app
      name: demo-worker
    spec:
      replicas: 1
      selector:
        matchLabels:
          app.kubernetes.io/component: worker
          app.kubernetes.io/instance: demo
          app.kubernetes.io/name: demo
          app.kubernetes.io/part-of: app
      template:
        metadata:
          labels:
            app.kubernetes.io/component: worker
            app.kubernetes.io/instance: demo
            app.kubernetes.io/name: demo
            app.kubernetes.io/part-of: app
          name: worker
        spec:
          containers:
            - args:
                - sh
                - "-c"
                - "python3 -c 'import socket, sys; socket.socket(socket.AF_INET, socket.SOCK_STREAM).connect((sys.argv[1], 5432))' postgres &&echo Connected && sleep infinity"
              image: registry.fedoraproject.org/fedora:31
              imagePullPolicy: IfNotPresent
              name: worker
kind: List
```
