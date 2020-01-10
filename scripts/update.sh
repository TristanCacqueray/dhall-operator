#!/bin/sh -ex

echo "Remove previous operator"
kubectl delete -f operator/deploy/operator.yaml || :

echo "Update local cri-o image"
CTX=$(sudo buildah from --root /var/lib/silverkube/storage --storage-driver vfs quay.io/software-factory/dhall-operator:0.0.1)
MNT=$(sudo buildah mount  --root /var/lib/silverkube/storage --storage-driver vfs $CTX)

sudo buildah run --root /var/lib/silverkube/storage --storage-driver vfs ${CTX} pip3 install --upgrade openshift

sudo rsync -avi operator/roles/ ${MNT}/opt/ansible/roles/
sudo cp -v *.dhall ${MNT}/opt/ansible/dhall
sudo rsync -avi defaults/ ${MNT}/opt/ansible/dhall/defaults/
sudo rsync -avi applications/ ${MNT}/opt/ansible/dhall/applications/
sudo rsync -avi deploy/ ${MNT}/opt/ansible/dhall/deploy/

# sudo buildah --root /var/lib/silverkube/storage --storage-driver vfs umount $MNT
sudo buildah commit --root /var/lib/silverkube/storage --storage-driver vfs --rm ${CTX} quay.io/software-factory/dhall-operator:0.0.1

kubectl apply -f operator/deploy/operator.yaml
