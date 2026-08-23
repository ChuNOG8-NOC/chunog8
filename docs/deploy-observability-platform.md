# 監視基盤のデプロイ

既存の Kubernetes 1.36 クラスタへ Zabbix、NetBox、Prometheus、Grafana を Helm で導入する。

## 前提

- Worker は worker01、worker02 の2台
- NFS 10.8.30.20:/srv/nfs/k8s が利用可能
- NFS export は storage/setup-nfs.sh のとおり Worker 2台限定かつ `no_root_squash` で公開する
- MetalLB が導入済み
- ansible/setup-k8s.yml を適用済み

~~~sh
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm repo add local-path-provisioner https://charts.containeroo.ch
helm repo add zabbix-community https://zabbix-community.github.io/helm-zabbix
helm repo add netbox https://charts.netbox.oss.netboxlabs.com/
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
~~~

Redis は OCI レジストリから直接取得する。HTTP repo `charts.bitnami.com/bitnami` は凍結済みで redis 20.3.0 までしか配信していない。

## Secret

Namespace と Secret を先に作成する。各 example をコピーし、placeholder をランダム値へ置換する。生成した *.env は Git 管理外となる。

~~~sh
kubectl create namespace zabbix
kubectl create namespace netbox
kubectl create namespace monitoring

install -m 0600 k8s-manifests/zabbix/secrets.env.example k8s-manifests/zabbix/secrets.env
install -m 0600 k8s-manifests/netbox/config.secrets.env.example k8s-manifests/netbox/config.secrets.env
install -m 0600 k8s-manifests/netbox/superuser.secrets.env.example k8s-manifests/netbox/superuser.secrets.env
install -m 0600 k8s-manifests/netbox/postgresql.secrets.env.example k8s-manifests/netbox/postgresql.secrets.env
install -m 0600 k8s-manifests/netbox/redis.secrets.env.example k8s-manifests/netbox/redis.secrets.env
install -m 0600 k8s-manifests/monitoring/secrets.env.example k8s-manifests/monitoring/secrets.env

kubectl -n zabbix create secret generic zabbix-db-credentials --from-env-file=k8s-manifests/zabbix/secrets.env
kubectl -n netbox create secret generic netbox-config --from-env-file=k8s-manifests/netbox/config.secrets.env
kubectl -n netbox create secret generic netbox-superuser --from-env-file=k8s-manifests/netbox/superuser.secrets.env
kubectl -n netbox create secret generic netbox-postgresql --from-env-file=k8s-manifests/netbox/postgresql.secrets.env
kubectl -n netbox create secret generic netbox-redis --from-env-file=k8s-manifests/netbox/redis.secrets.env
kubectl -n monitoring create secret generic monitoring-secrets --from-env-file=k8s-manifests/monitoring/secrets.env
~~~

## デプロイ

~~~sh
kubectl apply -f k8s-manifests/network/ip-pool.yaml

helm upgrade --install nfs-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner --version 4.0.18 -n nfs-provisioner --create-namespace -f k8s-manifests/storage/nfs-subdir-external-provisioner/values.yaml --wait
helm upgrade --install local-path-provisioner local-path-provisioner/local-path-provisioner --version 0.0.38 -n local-path-storage --create-namespace -f k8s-manifests/storage/local-path-provisioner/values.yaml --wait

helm upgrade --install zabbix zabbix-community/zabbix --version 7.1.0 -n zabbix -f k8s-manifests/zabbix/values.yaml --wait
kubectl apply -f k8s-manifests/zabbix/server-service.yaml
kubectl apply -f k8s-manifests/zabbix/policies.yaml

kubectl apply -f k8s-manifests/netbox/network-policy.yaml
helm upgrade --install netbox-redis oci://registry-1.docker.io/bitnamicharts/redis --version 28.0.10 -n netbox -f k8s-manifests/netbox/redis-values.yaml --wait
helm upgrade --install netbox netbox/netbox --version 8.3.61 -n netbox -f k8s-manifests/netbox/values.yaml --wait

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 88.5.3 -n monitoring -f k8s-manifests/monitoring/values.yaml --wait
kubectl apply -f k8s-manifests/monitoring/network-policy.yaml
~~~

適用前の確認には各コマンドの helm upgrade --install を helm template に置き換える。

## 確認

~~~sh
kubectl get pods,pvc -A
kubectl get svc -n zabbix
kubectl get svc -n netbox
kubectl get svc -n monitoring
~~~

- Zabbix: http://10.8.30.100/
- Prometheus: http://10.8.30.102/
- NetBox: http://10.8.30.103/
- Grafana: http://10.8.30.104/
- Zabbix Server: 10.8.30.105:10051/TCP（送信元は 10.8.30.0/24 と 10.8.10.0/24）
