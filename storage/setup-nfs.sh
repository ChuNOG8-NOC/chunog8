#!/bin/bash
# infra-VM(10.8.30.20)で実行する想定
sudo apt update
sudo apt install -y nfs-kernel-server
sudo mkdir -p /srv/nfs/k8s
sudo chown nobody:nogroup /srv/nfs/k8s
sudo chmod 777 /srv/nfs/k8s
# no_root_squash は外さない。PostgreSQL の initdb と kubelet の fsGroup 適用が root での chown を行うため、
# root_squash にすると Zabbix と NetBox の DB が起動できない。代わりに公開先を Worker 2台へ限定する。
echo "/srv/nfs/k8s 10.8.30.50(rw,sync,no_subtree_check,no_root_squash) 10.8.30.51(rw,sync,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
sudo systemctl enable nfs-kernel-server
