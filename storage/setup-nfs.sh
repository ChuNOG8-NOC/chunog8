#!/bin/bash
# infra-VM(10.8.30.20)で実行する想定
sudo apt update
sudo apt install -y nfs-kernel-server
sudo mkdir -p /srv/nfs/k8s
sudo chown nobody:nogroup /srv/nfs/k8s
sudo chmod 777 /srv/nfs/k8s
echo "/srv/nfs/k8s 10.8.30.0/24(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
sudo systemctl enable nfs-kernel-server
