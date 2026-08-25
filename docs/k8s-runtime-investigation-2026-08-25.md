# Kubernetes 稼働・永続化調査報告書

- 調査日時: 2026-08-25 12:09-12:41 JST
- 調査元: `ssh mgmt-chunog` で接続した `mgmt-vm` (`10.8.30.21`)
- 対象クラスタ: Kubernetes v1.36.4、5 nodes
- 対象リポジトリ: `chunog8-gitops` `main` (`e348eea`)
- 調査方針: Kubernetes リソース、イベント、ログ、HTTP/API、DB metadata、PVC/PV、マウント先を読み取り専用で確認した。Pod の削除・再起動、設定変更、Secret 更新、ファイル作成・削除は行っていない。Secret の実値も記録していない。

## 結論

完全には正常稼働していない。

1. **NetBox は停止中**。`netbox` Pod は `CrashLoopBackOff`、`netbox-worker` は `Init:Error`、Helm release は `failed` である。一次原因は `netbox-config` Secret の `secret_key` が **49文字**しかなく、NetBox 4.6.8 が要求する50文字以上を満たしていないこと。さらに `api_token_peppers` の pepper 本体も **42文字**で、これも50文字以上という要件を満たしていない。
2. **Prometheus 自体は稼働し TSDB へ保存しているが、Kubernetes 監視は不完全**。46 target 中32 target が Up、14 target が Down。controller-manager、scheduler、etcd、kube-proxy の metrics endpoint が loopback にしか bind されておらず、Prometheus から接続すると `connection refused` になる。
3. **調査時点では Prometheus の公開 URL が文書と不一致だった**。実 Service の公開 port は chart 既定の `9090` で、正しく応答する URL は `http://10.8.30.102:9090/` である。手順書と要件書は調査後にこの URL へ訂正した。
4. **Zabbix、Grafana、および主要な基盤 Pod は稼働中**。ただし Zabbix Agent `dhcp-kea` に対応する host が Zabbix に登録されておらず、この対象への active check は配布できていない。
5. **PVC/PV の作成・bind・mount・実書込みは概ね成功**。Zabbix DB、Grafana DB、Prometheus TSDB には実データがある。NetBox 用 PostgreSQL/Redis も NFS へ初期データを書き込めているが、NetBox 本体が起動前に落ちるため業務データはない。

## 稼働状態

| 対象 | 状態 | 判定根拠 |
| --- | --- | --- |
| Kubernetes nodes | 正常 | `cp01`、`cp02`、`cp03`、`worker01`、`worker02` の5台すべて `Ready` |
| Calico / CoreDNS / kube-proxy | Pod 稼働 | Calico 5/5、CoreDNS 2/2、kube-proxy 5/5 が Ready。ただし kube-proxy metrics は収集不能 |
| MetalLB | 正常 | 各固定 IP を割当済み。L2 status でも対象 Worker から広告中 |
| NFS provisioner | 正常 | Deployment 1/1、`nfs-observability` 作成済み |
| local-path provisioner | 正常 | Deployment 1/1、`local-observability` 作成済み |
| Zabbix Server | 稼働 | Pod 1/1、`10.8.30.100:10051` 接続成功 |
| Zabbix Web | 稼働 | Pod 1/1、`http://10.8.30.105/` が HTTP 200 |
| Zabbix PostgreSQL | 稼働 | StatefulSet 1/1、203 tables、DB 約76 MB |
| NetBox Web | **停止** | Pod 0/1、`CrashLoopBackOff`、93回以上再起動、`10.8.30.103:80` 到達不能 |
| NetBox Worker | **停止** | Pod 0/1、init container が Web Deployment 完了待ちで失敗 |
| NetBox Housekeeping | 未実行 | CronJob は存在するが初回 schedule 前。現状の設定では NetBox と同じ設定エラーになる見込み |
| NetBox PostgreSQL | Pod 稼働 | StatefulSet 1/1。ただし NetBox migration 前のため public table は0 |
| NetBox Redis | Pod 稼働 | StatefulSet 1/1、`PING` 成功、AOF 有効。ただし0 keys |
| Prometheus | 一部異常 | Pod 2/2、API/TSDB 正常。ただし target は32/46 Up |
| Grafana | 正常 | Pod 3/3、`/api/health` は HTTP 200、`database: ok` |
| Alertmanager | 正常 | StatefulSet 1/1、Pod 2/2 |
| Prometheus Operator | 正常 | Deployment 1/1 |
| kube-state-metrics | 正常 | Deployment 1/1、Prometheus target も Up |
| node-exporter | 正常 | 全5 node で5/5、Prometheus target も Up |

Helm chart/version はリポジトリの指定と一致していた。

- Zabbix chart 7.1.0 / Zabbix 7.0.23
- NetBox chart 8.3.61 / NetBox 4.6.8
- Redis chart 28.0.10 / Redis 8.10.1
- kube-prometheus-stack 88.5.3
- local-path-provisioner 0.0.38
- nfs-subdir-external-provisioner 4.0.18

## 障害・不整合の詳細

### 1. NetBox の Secret 長不足

NetBox Pod の通常ログは次だけを表示し、原因を隠していた。

```text
Waiting on DB... (0s / 30s)
...
Waited 30s or more for the DB to become ready.
```

NetBox の entrypoint が実際に行う `manage.py showmigrations` を、再起動中の既存コンテナ内で読み取り実行した結果は次のとおり。

```text
django.core.exceptions.ImproperlyConfigured: SECRET_KEY must be at least 50 characters in length.
```

Secret の値そのものは表示せず、長さだけを確認した。

| Secret 項目 | 実測 | 要件 | 判定 |
| --- | ---: | ---: | --- |
| `netbox-config.secret_key` | 49文字 | 50文字以上 | **不適合・現在の直接原因** |
| `netbox-config.api_token_peppers["1"]` の値 | 42文字 | 50文字以上 | **不適合・次に顕在化する可能性が高い** |

リポジトリの `config.secrets.env.example` 自体は50文字以上を指示しているため、マニフェストではなく、管理 VM で実 Secret を作成した際の値が要件を満たしていない。

DB 障害に見えるログだが、PostgreSQL は接続可能であり、設定読込が DB 接続より前に失敗している。PostgreSQL の public table が0なのも、migration に到達していない結果である。Worker の停止は、Web Deployment が完了しないことによる二次障害である。

参考:

- [NetBox Docker entrypoint の DB 待機処理](https://github.com/netbox-community/netbox-docker/blob/release/docker/docker-entrypoint.sh)
- [NetBox required parameters](https://github.com/netbox-community/netbox/blob/main/docs/configuration/required-parameters.md)

### 2. Prometheus の14 targetが Down

実測値:

- active targets: 46
- healthy targets: 32
- unhealthy targets: 14
- TSDB series: 約111,000
- firing alerts: 26（`Watchdog` を含む）

Down の内訳は次のとおり。

| Job | Down | 原因の証拠 |
| --- | ---: | --- |
| `kube-controller-manager` | 3 | 3 control-plane Pod が `--bind-address=127.0.0.1` |
| `kube-scheduler` | 3 | 3 control-plane Pod が `--bind-address=127.0.0.1` |
| `kube-etcd` | 3 | 3 etcd Pod が `--listen-metrics-urls=http://127.0.0.1:2381` |
| `kube-proxy` | 5 | ConfigMap の `metricsBindAddress` が空で、各 node の `10.8.30.x:10249` は接続拒否 |

Prometheus は node IP を scrape するため、loopback のみに listen する endpoint へは到達できない。このため `etcdInsufficientMembers`、`etcdMembersDown`、各 `InstanceUnreachable`、`TargetDown` などが発火している。etcd 自体は3 Podとも Running であり、これらは metrics 到達不能による監視上のアラートで、etcd quorum が実際に失われているという意味ではない。

### 3. Prometheus 公開 port の不一致

調査時点の `docs/deploy-observability-platform.md` と要件書は `http://10.8.30.102/` を案内していた。しかし `monitoring/values.yaml` は Prometheus Service の port を80へ上書きしておらず、実リソースは次の状態だった。

```text
10.8.30.102:9090 -> HTTP 200 / Prometheus Ready
10.8.30.102:80   -> 接続不能
```

Prometheus プロセス、Service endpoint、MetalLB L2 広告はいずれも正常。アプリ停止ではなく、values と文書上のアクセス仕様の不一致だった。手順書と要件書は2026-08-25に `http://10.8.30.102:9090/` へ訂正済み。

### 4. Zabbix の未登録 active agent

Zabbix Server は稼働し DB に履歴を書き込んでいるが、ログに次の警告が約6秒間隔で継続している。

```text
cannot send list of active checks to "10.8.30.77": host [dhcp-kea] not found
```

DB 上で technical name が `dhcp-kea` の host 件数は0だった。`10.8.30.77` の Agent 側 `Hostname` と一致する host を Zabbix に登録するか、既存 host 名と Agent 設定を一致させる必要がある。この対象以外について Zabbix Server/Web 自体は正常である。

### 5. デプロイ手順との namespace 差異

手順書は NFS provisioner を `nfs-provisioner` namespace へ導入するが、実 release/Deployment は `default` namespace にある。StorageClass と動的 PV 作成は正常に機能しており、今回の停止原因ではないが、手順と実環境の drift である。

## 永続化の検証結果

### 共通設定

- すべての対象 PVC は `Bound`。
- NFS/local PV とも PV の reclaim policy は `Retain`。
- NFS は `10.8.30.20:/srv/nfs/k8s` 配下へ用途別 subdirectory を作成。
- NFS mount の実測容量は約387 GiB、空き約384 GiB。
- Prometheus/Grafana の local PV は `WaitForFirstConsumer` で意図した node に node affinity が付いている。

| データ | PVC / 容量 | 実バックエンド | ライブ検証 | 判定 |
| --- | --- | --- | --- | --- |
| Zabbix PostgreSQL | 80 GiB | NFS `/srv/nfs/k8s/zabbix/postgresql-data-zabbix-postgresql-0` | NFS4 mount、PGDATA 224 MB、203 tables、405 hosts rows、history 27,454 rows | **書込み成功** |
| NetBox PostgreSQL | 20 GiB | NFS `/srv/nfs/k8s/netbox/data-netbox-postgresql-0` | NFS4 mount、47 MB、PostgreSQL 接続成功 | **ストレージ書込み成功**。NetBox table は0 |
| NetBox Redis | 5 GiB | NFS `/srv/nfs/k8s/netbox/redis-data-netbox-redis-master-0` | `/data` に NFS4 mount、AOF base/manifest 作成、AOF status `ok` | **永続化有効**。NetBox停止中のため0 keys |
| NetBox media | 10 GiB RWX | NFS `/srv/nfs/k8s/netbox/netbox-media` | PVC Bound、Web/Worker の `/opt/netbox/netbox/media` への mount 宣言を確認 | **構成・mountは成立**。アプリ未起動のため実データ書込みは未検証 |
| Prometheus TSDB | 40 GiB | worker01 `/var/lib/local-path-provisioner/...` | node affinity=worker01、約111k series / 約230k chunks、block compaction と WAL checkpoint 成功ログ | **書込み成功** |
| Grafana SQLite | 5 GiB | worker02 `/var/lib/local-path-provisioner/...` | node affinity=worker02、`grafana.db` 約2.5 MB、mountinfo は local ext4、health は `database: ok` | **書込み成功** |

### 「再起動後も残るか」の検証限界

今回の禁止事項に従い、確認のための Pod 削除・rollout restart・PVC 再attach・試験データ作成は行っていない。そのため、**意図的な再起動を伴う end-to-end の永続性テストは未実施**である。

ただし、次の運用中証拠から、少なくとも通常書込みと PVC/PV への格納は成立している。

- 実ファイルが container root filesystem ではなく、NFS4 または local PV の mount 上に存在する。
- Prometheus は TSDB block 作成と WAL checkpoint を継続している。
- Grafana は PV 上の SQLite DB を開き `database: ok` を返している。
- Zabbix は PV 上の PostgreSQL に履歴行を継続保存している。
- Redis は PV 上の `/data` に AOF ファイルを作成している。
- 対象 PV の reclaim policy はすべて `Retain`。Prometheus/Grafana では values 上の StatefulSet/PVC retention policy も `Retain`。

注意点として、Prometheus と Grafana は設計どおり local PV なので、データは PVC/PV 削除からは保護されるが、対象 Worker のディスク故障や node 消失には耐えない。NFS-backed データも NFS サーバ自体の故障には耐えず、別媒体へのバックアップは未検証である。

## 推奨対応順

### P0: NetBox を起動可能にする

1. `secret_key` を十分な長さのランダム値（最低50文字、推奨64文字以上）へ置換する。
2. `api_token_peppers` の ID `1` の値も最低50文字へ置換する。JSON 全体の文字数ではなく pepper 値自体の長さを確認する。
3. `netbox-config` Secret を更新後、NetBox Web/Worker/Housekeeping を再展開する。
4. migration 完了、Web HTTP 200、Worker Ready、PostgreSQL table 作成、Redis key/AOF、media 書込みを再確認する。

### P1: Kubernetes metrics を到達可能にする

- controller-manager/scheduler の bind address、etcd の metrics listen URL、kube-proxy の `metricsBindAddress` を node IP から到達できる値へ変更する。
- 変更時は metrics port を管理/Kubernetes network だけに制限する。
- 対応後、Prometheus target 46/46 Up と、到達不能由来 alert の解消を確認する。
- 反映用の `ansible/enable-kubernetes-metrics.yml` を追加済み。クラスタへは未適用。

### 対応済み: Prometheus の公開仕様を統一する

- 実 Service の port 9090を維持し、手順書・要件書を `http://10.8.30.102:9090/` に修正した。

### P2: Zabbix host 名を整合させる

- `10.8.30.77` の Agent `Hostname=dhcp-kea` と一致する host を登録するか、Agent 側を既存 technical name に合わせる。

### P3: 構成 drift を解消する

- NFS provisioner の実 namespace (`default`) と手順書 (`nfs-provisioner`) のどちらを正とするか決め、次回の保守時に統一する。

## 再確認項目

設定変更が許可された後は、最低限次を再確認する。

```sh
kubectl get pods,pvc -A
helm list -A
curl -I http://10.8.30.103/
curl -sS http://10.8.30.102:9090/api/v1/targets
kubectl -n netbox logs deployment/netbox --tail=200
kubectl -n netbox logs deployment/netbox-worker --tail=200
kubectl -n zabbix logs deployment/zabbix-zabbix-server --tail=200
```

NetBox 復旧後に、テスト用オブジェクトと media ファイルを作成し、計画停止を伴う Pod 再作成後も残ることを確認すれば、アプリケーションレベルの end-to-end 永続化検証が完了する。
