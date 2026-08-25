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

適用前は各コマンドを `helm template <release> <chart> ...` に変更し、`--wait` と `--create-namespace` を外してレンダリング結果を確認する。

## Kubernetes control-plane metrics の有効化

`kube-prometheus-stack` は controller-manager、scheduler、etcd、kube-proxy の metrics endpoint をnode IPでscrapeする。kubeadm既定構成ではこれらがloopbackだけで待ち受けるため、`ansible/enable-kubernetes-metrics.yml` でクラスタ内から到達可能にする。

playbookは次を行う。

- control-planeを `serial: 1` で1台ずつ処理する。
- controller-managerとschedulerの `--bind-address` を `0.0.0.0` に変更する。これはkubeadmのloopback probeを維持しながらnode IPでも待ち受けるために必要となる。
- etcdの `--listen-metrics-urls` に各control-plane nodeの `10.8.30.x:2381` を追加する。既存のloopback URLは維持する。
- 各static Podの再作成とReady復帰を待ち、etcd変更後はendpoint healthを確認してから次のnodeへ進む。
- kube-proxy ConfigMapの `metricsBindAddress` を `0.0.0.0:10249` に変更し、DaemonSetのrollout完了を待つ。
- static Pod manifestを変更する際はAnsibleのbackupを作成する。

metrics endpointはLoadBalancerでは公開されないが、etcdの2381/TCPとkube-proxyの10249/TCPにはアプリケーション認証がない。nodeが属する `10.8.30.0/24` を信頼済み管理ネットワークとして扱い、他セグメントからこれらのportへ到達させないこと。

まず構文と変更予定を確認する。

~~~sh
ansible-playbook --syntax-check -i ansible/inventory.ini ansible/enable-kubernetes-metrics.yml
ansible-playbook --check --diff -i ansible/inventory.ini ansible/enable-kubernetes-metrics.yml
~~~

本番反映は、各control-plane nodeを個別に適用・確認してからkube-proxyを更新する。

~~~sh
ansible-playbook -i ansible/inventory.ini ansible/enable-kubernetes-metrics.yml --tags control-plane-metrics --limit cp01
kubectl get nodes
kubectl -n kube-system get pod etcd-cp01 kube-controller-manager-cp01 kube-scheduler-cp01

ansible-playbook -i ansible/inventory.ini ansible/enable-kubernetes-metrics.yml --tags control-plane-metrics --limit cp02
kubectl get nodes
kubectl -n kube-system get pod etcd-cp02 kube-controller-manager-cp02 kube-scheduler-cp02

ansible-playbook -i ansible/inventory.ini ansible/enable-kubernetes-metrics.yml --tags control-plane-metrics --limit cp03
kubectl get nodes
kubectl -n kube-system get pod etcd-cp03 kube-controller-manager-cp03 kube-scheduler-cp03

ansible-playbook -i ansible/inventory.ini ansible/enable-kubernetes-metrics.yml --tags kube-proxy-metrics --limit mgmt-vm
kubectl -n kube-system rollout status daemonset/kube-proxy --timeout=180s
~~~

Prometheusのscrape interval 2回分（約1分）待って確認する。

~~~sh
curl -sS http://10.8.30.102:9090/api/v1/targets \
  | jq '[.data.activeTargets[] | select(.health != "up") | {job: .labels.job, url: .scrapeUrl, error: .lastError}]'
~~~

出力が空配列 `[]` になり、PrometheusのTargets画面で46/46 Upになれば完了となる。

## 確認

~~~sh
kubectl get pods,pvc -A
kubectl get svc -n zabbix
kubectl get svc -n netbox
kubectl get svc -n monitoring
~~~

- Zabbix: http://10.8.30.105/
- Prometheus: http://10.8.30.102:9090/
- NetBox: http://10.8.30.103/
- Grafana: http://10.8.30.104/
- Zabbix Server: 10.8.30.100:10051/TCP（送信元は 10.8.30.0/24 と 10.8.10.0/24）
