{- An operator sdk scaffolding helper -}
let Configuration =
      { year : Text
      , author : Text
      , version : Text
      , image : Text
      , group : Text
      , crd : { kind : Text, plural : Text, singular : Text, role : Text }
      }

let dhall-json =
      { url =
          "https://github.com/dhall-lang/dhall-haskell/releases/download/1.29.0/dhall-json-1.6.1-x86_64-linux.tar.bz2"
      , hash =
          "7e65f933fb215629d18d23bc774688c598d4c11b62865f3546ee23ae36b25290"
      }

let download =
      https://raw.githubusercontent.com/podenv/hub/master/runtimes/download.dhall sha256:a3e07c636b33b03ac372c3dd9eb250ea5936c7759e636e98ca0f43574546af63

let HOME = "/opt/ansible"

in  { Configuration = { Type = Configuration, default = {=} }
    , DirectoryTree =
            \(conf : Configuration)
        ->  let header =
                  ''
                  # This file is managed by the configuration.dhall file, all changes will be lost.
                  #
                  # Copyright ${conf.year} ${conf.author}
                  #
                  # Licensed under the Apache License, Version 2.0 (the "License"); you may
                  # not use this file except in compliance with the License. You may obtain
                  # a copy of the License at
                  #
                  #      http://www.apache.org/licenses/LICENSE-2.0
                  #
                  # Unless required by applicable law or agreed to in writing, software
                  # distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
                  # WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
                  # License for the specific language governing permissions and limitations
                  # under the License.
                  #
                  ''

            let service-account = "${conf.crd.role}-operator"

            in  { deploy =
                    { `crd.yaml` =
                        ''
                        ${header}
                        apiVersion: apiextensions.k8s.io/v1beta1
                        kind: CustomResourceDefinition
                        metadata:
                          name: ${conf.crd.plural}.${conf.group}
                        spec:
                          group: ${conf.group}
                          names:
                            kind: ${conf.crd.kind}
                            listKind: ${conf.crd.kind}List
                            plural: ${conf.crd.plural}
                            singular: ${conf.crd.singular}
                            shortNames:
                              - ${conf.crd.role}
                          scope: Namespaced
                          subresources:
                            status: {}
                          versions:
                          - name: v1alpha1
                            served: true
                            storage: true
                        ''
                    , `operator.yaml` =
                        ''
                        ${header}
                        apiVersion: apps/v1
                        kind: Deployment
                        metadata:
                          name: ${service-account}
                        spec:
                          replicas: 1
                          selector:
                            matchLabels:
                              name: ${service-account}
                          template:
                            metadata:
                              labels:
                                name: ${service-account}
                            spec:
                              serviceAccountName: ${service-account}
                              containers:
                                - name: ansible
                                  command:
                                  - /usr/local/bin/ao-logs
                                  - /tmp/ansible-operator/runner
                                  - stdout
                                  image: "${conf.image}"
                                  imagePullPolicy: "IfNotPresent"
                                  volumeMounts:
                                  - mountPath: /tmp/ansible-operator/runner
                                    name: runner
                                    readOnly: true
                                - name: operator
                                  image: "${conf.image}"
                                  imagePullPolicy: "IfNotPresent"
                                  volumeMounts:
                                  - mountPath: /tmp/ansible-operator/runner
                                    name: runner
                                  env:
                                    - name: WATCH_NAMESPACE
                                      valueFrom:
                                        fieldRef:
                                          fieldPath: metadata.namespace
                                    - name: POD_NAME
                                      valueFrom:
                                        fieldRef:
                                          fieldPath: metadata.name
                                    - name: OPERATOR_NAME
                                      value: "${service-account}"
                              volumes:
                                - name: runner
                                  emptyDir: {}
                        ''
                    , `rbac.yaml` =
                        ''
                        ${header}
                        apiVersion: v1
                        kind: ServiceAccount
                        metadata:
                          name: ${service-account}

                        ---

                        apiVersion: rbac.authorization.k8s.io/v1
                        kind: Role
                        metadata:
                          name: ${service-account}
                        rules:
                        - apiGroups:
                          - ""
                          resources:
                          - pods
                          - services
                          - services/finalizers
                          - endpoints
                          - persistentvolumeclaims
                          - events
                          - configmaps
                          - secrets
                          - ingresses
                          verbs:
                          - create
                          - delete
                          - get
                          - list
                          - patch
                          - update
                          - watch
                        - apiGroups:
                          - apps
                          resources:
                          - deployments
                          - daemonsets
                          - replicasets
                          - statefulsets
                          verbs:
                          - create
                          - delete
                          - get
                          - list
                          - patch
                          - update
                          - watch
                        - apiGroups:
                          - ${conf.group}
                          resources:
                          - '*'
                          verbs:
                          - create
                          - delete
                          - get
                          - list
                          - patch
                          - update
                          - watch

                        ---

                        kind: RoleBinding
                        apiVersion: rbac.authorization.k8s.io/v1
                        metadata:
                          name: ${service-account}
                        subjects:
                        - kind: ServiceAccount
                          name: ${service-account}
                        roleRef:
                          kind: Role
                          name: ${service-account}
                          apiGroup: rbac.authorization.k8s.io
                        ''
                    , `scc.yaml` =
                        ''
                        ${header}
                        apiVersion: security.openshift.io/v1
                        kind: SecurityContextConstraints
                        metadata:
                          annotations:
                            kubernetes.io/description: 'enable zuul executor bwrap usage'
                          name: zuul-executor
                        users:
                        # TODO: figure how to install this only for the current namespace...
                        - system:serviceaccount:myproject:${service-account}
                        - system:serviceaccount:default:${service-account}

                        allowPrivilegedContainer: true

                        # cannot set `allowPrivilegeEscalation` to false and `privileged` to true
                        allowPrivilegeEscalation: true

                        allowHostDirVolumePlugin: false
                        allowHostIPC: false
                        allowHostNetwork: false
                        allowHostPID: false
                        allowHostPorts: false
                        runAsUser:
                          type: MustRunAsRange
                        seLinuxContext:
                          type: MustRunAs
                        supplementalGroups:
                          type: RunAsAny
                        volumes:
                        - configMap
                        - emptyDir
                        - persistentVolumeClaim
                        - secret
                        ''
                    }
                , build =
                    { Containerfile =
                        ''
                        ${header}
                        FROM quay.io/operator-framework/ansible-operator:v0.13.0

                        # Install extra requirements
                        USER root

                        # See: https://github.com/operator-framework/operator-sdk/issues/2384
                        RUN pip3 install --upgrade openshift

                        # unarchive: bzip2 and tar
                        # generate zuul ssh-keys or certificate: openssh and openssl
                        # manage configuration: git
                        RUN dnf install -y bzip2 tar openssh openssl git

                        # Install dhall-to-json
                        ${download
                            "~/.cache/"
                            (     dhall-json
                              //  { dest = "/bin"
                                  , archive = Some
                                      "--strip-components=2 -j --mode='a+x'"
                                  }
                            )} && rm -Rf ~/.cache/

                        # Back to the default operator user
                        USER 1001

                        # Install dhall libraries
                        RUN git clone --depth 1 https://github.com/dhall-lang/dhall-lang ${HOME}/dhall-lang && git clone --depth 1 https://github.com/dhall-lang/dhall-kubernetes ${HOME}/dhall-kubernetes
                        ENV DHALL_PRELUDE=/opt/ansible/dhall-lang/Prelude/package.dhall
                        ENV DHALL_KUBERNETES=/opt/ansible/dhall-kubernetes/package.dhall
                        ENV DHALL_K8S=/opt/ansible/dhall-kubernetes/typesUnion.dhall

                        # Copy configuration
                        COPY conf/ ${HOME}/conf/

                        # Cache dhall objects
                        RUN echo 'let Prelude = ~/conf/Prelude.dhall let Kubernetes = ~/conf/Kubernetes.dhall let k8s = ~/conf/KubernetesUnion.dhall in "OK"' | \
                            env DHALL_PRELUDE=/opt/ansible/dhall-lang/Prelude/package.dhall   \
                                DHALL_KUBERNETES=/opt/ansible/dhall-kubernetes/package.dhall  \
                                DHALL_K8S=/opt/ansible/dhall-kubernetes/typesUnion.dhall dhall-to-json


                        # Copy ansible operator requirements
                        COPY watches.yaml ${HOME}/watches.yaml
                        COPY roles ${HOME}/roles
                        ''
                    }
                , `watches.yaml` =
                    ''
                    ${header}
                    - version: v1alpha1
                      group: ${conf.group}
                      kind: ${conf.crd.kind}
                      role: ${HOME}/roles/${conf.crd.role}
                    ''
                , Makefile =
                    ''
                    ${header}
                    build:
                    	podman build -f build/Containerfile -t ${conf.image} .

                    install:
                    	kubectl apply -f deploy/crd.yaml -f deploy/rbac.yaml -f deploy/operator.yaml

                    install-scc:
                    	kubectl apply -f deploy/scc.yaml

                    config-update:
                    	@dhall to-directory-tree --output . <<< '(./conf/operator/functions/scaffoldSdk.dhall).DirectoryTree ./configuration.dhall'
                    ''
                }
    }
