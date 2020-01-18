# This file is managed by the configuration.dhall file, all changes will be lost.
#
# Copyright 2020 Red Hat
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

image:
	podman build -f build/Containerfile -t quay.io/software-factory/dhall-operator:0.0.2 .

install:
	kubectl apply -f deploy/crd.yaml -f deploy/rbac.yaml -f deploy/operator.yaml

install-scc:
	kubectl apply -f deploy/scc.yaml

config-update:
	@dhall to-directory-tree --output . <<< '(./conf/operator/functions/scaffoldSdk.dhall).DirectoryTree ./configuration.dhall'
