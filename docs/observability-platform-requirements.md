# Zabbix・NetBox・Grafana 展開要件

## 文書情報

- ステータス: 要件確定（実装待ち）
- 対象ブランチ: `add/zabbix-by-meg4ne`
- 対象環境: ChuNOG8 イベント NOC Kubernetes 基盤
- 対象ソフトウェア: Zabbix、NetBox、Grafana、Prometheus
- 最終更新日: 2026-08-23

この文書は、会話で決定した要件を継続的に記録する。未決定事項を推測で確定せず、決定後に「確定要件」へ移す。

## 背景

イベント NOC で利用する既存 Kubernetes クラスタへ、監視・メトリクス収集・可視化・ネットワーク情報管理のためのソフトウェアを追加する。

既存クラスタは、Control Plane 3台、Worker 2台、Calico CNI、MetalLB、NFS サーバを前提としている。ただし、現在のリポジトリには Kubernetes クラスタの実測リソース、Ingress Controller、StorageClass、バックアップ、Secret 管理の定義は含まれていない。

## 導入目的（暫定）

### Zabbix

- イベントネットワーク機器、サーバ、Kubernetes 基盤の死活・性能監視
- 障害の検知と NOC メンバーへの通知
- 障害解析に必要な履歴の保存

### NetBox

- 機器、ラック、接続、IP アドレス、VLAN、回線などの情報管理
- イベントネットワーク構成の Source of Truth としての利用

### Grafana

- NOC 向けダッシュボードの提供
- Zabbix、Prometheus などのデータソースを利用した状態の可視化

### Prometheus

- 初期実装では Kubernetes 基盤のメトリクスを収集
- Grafana に時系列データを提供
- DNS・DHCP のメトリクス収集は初期実装に含めず、監視基盤全体の安定稼働を確認した後の第2段階で検証する

## 現時点の確定要件

- Zabbix、NetBox、Grafana、Prometheus を既存 Kubernetes クラスタへ展開する。
- イベント本番は2日間、合計約24時間の運用を想定する。
- 本番環境の構築フェーズに入っているため、短期間で構築・検証可能な構成とする。
- ネットワーク機器約15台と、サーバ・VM約10台を監視対象とする。
- イベントネットワークへ接続するクライアント端末は最大約600台（200人、1人3台）を想定する。
- 最大600台のクライアント端末は個別登録せず、初期実装では無線 AP・スイッチの接続数などで集約監視する。DHCP リースとDNS利用状況の監視は第2段階へ延期する。
- Zabbix、NetBox、Grafana の同時利用者は最大10人とする。
- 初期実装の Prometheus は Kubernetes 基盤のみを監視対象とし、DNS・DHCP の状態およびメトリクスは収集しない。
- DNS・DHCP の監視は、Zabbix、NetBox、Grafana、Prometheus の安定稼働を確認した後に第2段階として追加を検討する。
- イベント終了後、監視データは原則として削除する。
- 必要に応じて、削除前にクラウド等へバックアップを取得する。保存先、対象、保存期間は別途決定する。
- 構成と運用手順を Git リポジトリで管理する。
- 必要な Worker Node の CPU、メモリ、ストレージ容量を要件に基づいて算定する。
- 設定作成、検証、Git へのコミットと push、Pull Request 作成までを実施範囲とする。
- 要件は本 Markdown 文書へ記録する。

## GitHub で管理する範囲

今回の要件検討と実装は、各ソフトウェアを Kubernetes 上で起動し、Web UI から利用開始できる状態にするための構成を対象とする。

GitHub で管理する対象は以下のとおり。

- Namespace
- Zabbix、NetBox、Grafana、Prometheus のデプロイ定義とバージョン
- PostgreSQL、Redis など起動に必須の依存コンポーネント
- Pod の CPU / メモリ requests・limits、replica 数、配置条件
- Service、MetalLB または Ingress によるアクセス方法
- PersistentVolumeClaim、StorageClass、必要容量
- NFS-backed StorageClass とローカルディスク用 StorageClass の使い分け
- Secret を Git に平文保存しないための管理方式
- readiness / liveness probe
- アプリを起動するために必要な初期設定
- Prometheus が Kubernetes 基盤を監視するための scrape 設定と `ServiceMonitor`
- デプロイ、更新、停止、データ削除の手順
- 各ソフトウェアは Helm chart を利用してデプロイする。
- GitHub には Helm values とデプロイ手順を保存する。
- chart とコンテナイメージのバージョンを固定し、`latest` タグは使用しない。
- Argo CD / Flux は今回の実装範囲に含めず、`helm upgrade --install` により適用する。
- Zabbix は安定性を優先し、7.0 LTS 系の検証済み最新パッチを利用する。
- NetBox は4.6系の検証済み安定パッチを利用する。
- Prometheus、Grafana、Prometheus Operator、node-exporter、kube-state-metrics は `kube-prometheus-stack` chart でまとめて導入する。
- Grafana の単独 Helm release は作成せず、`kube-prometheus-stack` に含まれる Grafana を利用する。
- chart の具体的なバージョンは Kubernetes 1.36 との互換性とレンダリング結果を検証してから固定する。
- 本番前にバージョンを凍結し、重大な脆弱性または運用を妨げる不具合がない限りアップグレードしない。
- Web UI は NOC 管理ネットワーク `10.8.30.0/24` からのみアクセス可能とする。
- 利用可能なドメイン名および HTTPS 証明書はないため、Web UI は内部ネットワーク上の固定 IPv4 アドレスへ HTTP でアクセスする。
- Ingress Controller と cert-manager は今回導入せず、各 Web UI の Service を MetalLB の `LoadBalancer` として公開する。
- Zabbix、NetBox、Grafana はアプリケーション側のログイン認証を有効にする。
- Zabbix Web UI は `10.8.30.100`、Prometheus は `10.8.30.102`、NetBox は `10.8.30.103`、Grafana は `10.8.30.104` で公開する。
- Zabbix Server の監視受信ポートは Web UI とは別の Service として `10.8.30.105` で公開する。
- Zabbix Server への接続を許可する送信元は `10.8.30.0/24` と `10.8.10.0/24` とする。
- SNMP community は利用者から別途提供された値を使用するが、認証情報のため本リポジトリおよび本要件書には平文で保存しない。
- 永続データは、Prometheus TSDB と Grafana DB を除き `infra-vm` (`10.8.30.20`) の既存 NFS サーバへ保存する。
- NFS VM のディスクは現在の8GBから200GiBへ拡張する。
- Kubernetes から NFS を動的に利用するため、NFS Subdir External Provisioner を Helm で導入して StorageClass を作成する。
- Prometheus TSDB と Grafana DB は NFS を使用せず、Worker Node のローカルディスク上の PersistentVolume へ保存する。
- ローカル PV は `local-path-provisioner` を Helm で導入し、`volumeBindingMode: WaitForFirstConsumer` の専用 StorageClass を作成する。
- Zabbix は専用の PostgreSQL 1 replica を使用する。
- NetBox は専用の PostgreSQL 1 replica と Redis 1 replica を使用する。
- Zabbix と NetBox で PostgreSQL instance を共有しない。
- Prometheus は自身の TSDB を使用し、Grafana は内蔵 SQLite を使用する。
- PostgreSQL、Redis、NetBox media の永続データは NFS-backed PVC へ保存する。
- 認証情報は Helm / kubectl を実行する管理サーバー上の Git 管理外 `.env` ファイルへ保存する。
- `.env` から `kubectl create secret --from-env-file` を使って Kubernetes Secret を作成し、Helm chart から既存 Secret を参照する。
- Secret 作成専用スクリプトは必須とせず、再現可能なコマンドをデプロイ手順書へ記載する。
- アプリケーションと依存コンポーネントは基本1 replicaとする。
- Worker Node 障害時は Kubernetes が別 Worker へPodを再配置し、数分から10分程度の一時停止を許容する。
- NFS VM 障害時は永続データを使用するアプリケーションの停止を許容し、NFS復旧後に再開する。
- データベースクラスタリング、Zabbix Server HA、Prometheus HAは今回導入しない。
- Kubernetes 基盤の監視は `kube-prometheus-stack` の標準機能を使用する。
- 初期実装では Blackbox Exporter、Stork Agent、DNS probe、Kea DHCP Exporter、BIND 9 Exporterを導入しない。
- DNS/DHCP VIP `10.8.30.60` の外形監視、Kea DHCP統計、BIND 9統計の収集は第2段階へ延期する。
- 第2段階の実装前に、Keaの統計取得用hookと管理API、BINDの`statistics-channels`、Active/Backup構成を考慮したアラート条件を検証する。
- Worker Node へ Ansible で `nfs-common` を導入し、NFS-backed PVC をマウント可能にする。
- 全ノードの時刻同期に NICT の公開 NTP サーバ `ntp.nict.jp` を使用する。
- Worker Node は各 `8 vCPU / 16Gi RAM / 200Gi disk` の2台構成とする。
- 更新は固定バージョンを変更した `helm upgrade`、不具合時は `helm rollback` で行う。
- イベント終了後のバックアップとデータ削除は自動化せず、確認を伴う手動手順で実行する。

## Web UI などで設定する範囲

次のアプリケーション内部設定は今回の GitHub 実装範囲外とし、起動後に Web UI などから設定する。

- Zabbix の監視ホスト登録、テンプレート割当、トリガー、通知先、ユーザー設定
- NetBox のデバイス、ラック、IP アドレス、VLAN、回線などの登録データ
- Grafana の詳細なダッシュボード、パネル、ユーザー設定
- 個別アラートのしきい値や通知ルール

Web UI で作成した設定や登録データはデータベースまたは PersistentVolume に保存される。Pod の再作成で失われないよう永続化するが、イベント終了後は原則として削除する。

Prometheus は標準 Web UI から監視対象を恒久的に追加する製品ではないため、初期実装では Kubernetes 基盤を収集するための最低限の監視設定を GitHub で管理する。DNS・DHCP用の収集設定は第2段階で検証後にGit管理へ追加する。収集後の詳細なダッシュボードやアラート調整は運用時に行う。

## 非機能要件として決める項目

- 想定規模: 監視対象数、監視項目数、NetBox 登録対象数、同時利用者数
- 利用期間: イベント期間のみか、準備期間・終了後も継続するか
- 可用性: 単一 Pod 障害への対応、Worker Node 障害時の復旧目標
- 性能: 監視間隔、画面応答時間、ダッシュボード更新間隔
- 時刻同期: 全ノードで NTP による時刻同期を必須とする
- データ保持: 監視履歴、トレンド、監査ログ、NetBox データの保存期間
- 永続化: データベースと添付ファイルの保存先
- バックアップ: 対象、頻度、保存先、復旧手順
- アクセス: URL、DNS、Ingress、TLS、外部公開範囲
- 認証・認可: 管理者、NOC メンバー、閲覧者、SSO の要否
- 通知: Slack、メール、その他連絡手段との連携
- セキュリティ: Secret 管理、NetworkPolicy、権限分離、外部通信制御
- 運用: バージョン固定、アップグレード、監視、障害対応、撤去方法

## 想定コンポーネント（未確定）

最終構成は要件確定後に決める。現時点では、少なくとも次のコンポーネントが必要になる可能性がある。

- Zabbix Server、Zabbix Web、Zabbix Agent または SNMP 監視
- NetBox Web、Worker、Housekeeping
- Grafana
- Prometheus
- DNS 疎通監視用 Blackbox Exporter（第2段階）
- BIND 統計取得用 Exporter（第2段階、実装方式は要検証）
- Kea DHCP 統計取得用 Exporter（第2段階、実装方式は要検証）
- PostgreSQL
- NetBox 用 Redis
- PersistentVolume / StorageClass
- バックアップ処理
- Secret 管理方式

## 未決定事項

以下の順に会話で決定する。

要件を満たす基本方針は確定済み。実装時に以下を検証して最終値を固定する。

1. Kubernetes 1.36 と互換性のある各 Helm chart の具体的なバージョン
2. chartごとの正確なvaluesキーと `existingSecret` 対応状況
3. クラウドバックアップを実施する場合の転送先と保存期間
4. Prometheus と Grafana をどの Worker へ固定するか
5. SNMP trap 受信の要否
6. 外部 NTP (123/UDP) が許可されているか、許可されない場合の中継ホスト
7. 第2段階へ進むための安定稼働判定基準と、DNS probeで問い合わせるレコード名

## 規模見積もり入力欄

| 項目 | 値 | 状態 |
| --- | ---: | --- |
| イベント本番日数 | 2日間（合計約24時間） | 確定 |
| 準備・検証期間 | 既に開始済み。本番環境構築フェーズ | 確定 |
| 監視対象ネットワーク機器数 | 約15台 | 確定 |
| 監視対象サーバ / VM 数 | 約10台 | 確定 |
| 監視対象 Kubernetes Node / Pod 数 | 未定 | 要確認 |
| Zabbix の標準監視間隔 | 未定 | 要確認 |
| NetBox 登録デバイス数 | 未定 | 要確認 |
| 同時利用者数 | 最大10人 | 確定 |
| イベント接続クライアント数 | 最大約600台（200人 x 3デバイス） | 確定 |
| 監視データ保持期間 | イベント終了後に原則削除 | 確定（削除時期は要確認） |

## Web UI 公開要件

ドメイン名と HTTPS 証明書を使用せず、MetalLB の固定 IPv4 アドレスを各 Service に割り当てて HTTP で公開する。アクセス元は `10.8.30.0/24` に制限する。

| Web UI | 固定 IP 候補 | URL候補 | 状態 |
| --- | --- | --- | --- |
| Zabbix | `10.8.30.100` | `http://10.8.30.100/` | 確定 |
| Prometheus | `10.8.30.102` | `http://10.8.30.102/` | 確定 |
| NetBox | `10.8.30.103` | `http://10.8.30.103/` | 確定 |
| Grafana | `10.8.30.104` | `http://10.8.30.104/` | 確定 |

### Zabbix Server の監視受信ポート

Zabbix Web UI と Zabbix Server は別の Deployment / Service であるため、Web UI とは別の `LoadBalancer` IP を割り当てる。Kubernetes 外の Zabbix Agent やネットワーク機器から到達できなければ監視が成立しない。

| 用途 | 固定 IP | ポート | 状態 |
| --- | --- | --- | --- |
| Zabbix Agent アクティブチェック、Zabbix Sender | `10.8.30.105` | `10051/TCP` | 確定（送信元 `10.8.30.0/24`、`10.8.10.0/24`） |
| SNMP trap 受信 | `10.8.30.105` | `162/UDP` | 条件付き確定 |

- 同一 Service で TCP と UDP を混在させる。Kubernetes 1.36 では mixed protocol の `LoadBalancer` Service が利用可能であることを前提とする。
- Zabbix Server への接続元は Web UI とは異なり、監視対象機器・サーバが属するセグメントを `loadBalancerSourceRanges` で許可する。許可する送信元範囲は `10.8.30.0/24` と `10.8.10.0/24` とする。
- SNMP trap を利用するかどうかは Zabbix 起動後に決める。利用する場合は `zabbix-snmptraps` コンテナを有効にし、トラップファイル用の共有ボリュームを Zabbix Server と共有する。
- 監視対象の Linux サーバ・VM への Zabbix Agent 2 導入は Ansible で行う。

- `loadBalancerSourceRanges` と NetworkPolicy を利用し、NOC 管理ネットワーク以外からのアクセスを制限する。
- Prometheus の Web UI は標準状態ではアプリケーションログインを提供しないため、ネットワーク制限を必須とする。
- HTTP のため通信内容は暗号化されない。信頼された隔離済み管理ネットワーク内でのみ利用する。
- MetalLB pool は固定割当用と動的割当用に分割し、固定IPが他の Service へ自動割当されないようにする。
- syslog 転送先 `10.8.30.101` を MetalLB の自動割当範囲から除外する。
- 固定割当用 pool は `10.8.30.100` および `10.8.30.102-10.8.30.105` とし、自動割当を無効にする。
- 現在の pool の残り `10.8.30.106-10.8.30.149` は、他の `LoadBalancer` Service への動的割当に利用できる構成とする。

## 永続ストレージ要件

永続データは用途に応じて 2 種類の StorageClass へ振り分ける。

- **NFS-backed StorageClass**: PostgreSQL、Redis、NetBox media など、Worker 間の再配置でデータを引き継ぎたいボリュームに使用する。既存の `infra-vm` (`10.8.30.20`) で稼働する NFS サーバを利用し、現在8GBの仮想ディスクは200GiBへ拡張する。
- **ローカル StorageClass**: Prometheus TSDB と Grafana DB に使用する。Worker Node のローカルディスクを使い、ノードをさまよう再配置はできない。

### Prometheus TSDB と Grafana DB をローカルへ置く理由

- Prometheus の TSDB は mmap と POSIX ファイルロックに依存し、公式に NFS を含む非 POSIX 準拠ファイルシステムをサポート対象外としている。NFS 上では WAL 破損や起動失敗が発生しうる。
- Grafana の内蔵 SQLite も NFS のファイルロックと相性が悪く、DB ロックエラーや DB 破損の実例が多い。
- いずれも監視基盤自体を停止させる障害であり、イベント本番中のリスクとして許容しない。

### ローカル PV の実現方式

- `local-path-provisioner` を Helm で導入し、Worker の `/var/lib/local-path-provisioner` を使う専用 StorageClass を作成する。
- `volumeBindingMode` は `WaitForFirstConsumer` とし、Pod がスケジュールされた Worker 上で PV を作成する。
- この StorageClass の `reclaimPolicy` は `Retain` とし、意図しない PVC 削除で監視データが即時消失しないようにする。
- Prometheus と Grafana の Pod は PV を作成した Worker へ固定される。デフォルトでは 2 台へ分散させるため、どちらがどの Worker に載るかを `nodeSelector` で明示的に固定する。

### 容量算定

#### NFS 上に置くボリューム

| 用途 | PVC容量の目安 | 算定方針 |
| --- | ---: | --- |
| Zabbix PostgreSQL | 80Gi | 監視対象約25台、履歴・インデックス・一時領域を多めに確保 |
| NetBox PostgreSQL | 20Gi | 約25台規模に対して十分な余裕を確保 |
| NetBox media | 10Gi | 画像、添付ファイル、生成レポート等 |
| NetBox Redis | 5Gi | キャッシュおよびジョブキュー |
| バックアップ一時領域 | 40Gi | クラウド等へ転送する前のDB dump・設定の一時保管 |
| **NFS 合計** | **約155Gi** | |
| **NFS VMディスク推奨値** | **200GiB** | OS、ファイルシステム、運用余裕を追加 |

#### Worker ローカルディスク上に置くボリューム

| 用途 | PVC容量の目安 | 算定方針 |
| --- | ---: | --- |
| Prometheus TSDB | 40Gi | PVCは余白を含めて40Giを確保し、`retentionSize: 25GiB`でTSDBの実効上限を抑える |
| Grafana | 5Gi | SQLite DB、プラグイン、ダッシュボード等 |
| **ローカル PV 合計** | **45Gi** | 2台へ分散させて配置する |

- Prometheus は `retention` と `retentionSize` の両方に上限を設定し、Worker のローカルディスクを使い切らないようにする。`kube-prometheus-stack`のHelm valuesでは`prometheus.prometheusSpec.retentionSize: 25GiB`を初期値とする。
- 40GiのPVC要求容量は保存領域の余白確保を目的とし、データ量の制御はPrometheusの`retentionSize`で行う。`local-path-provisioner`はPVC要求容量をファイルシステムquotaとして強制しないため、PVC容量だけを安全上限として扱わない。
- `retentionSize`にはWALや一部の補助データが含まれないことを考慮し、Prometheus配置Workerの実空き容量を監視する。空き容量15%で警告し、10%へ達する前に`retentionSize`の縮小または不要データ・イメージの削除を行う。
- NFS Subdir External Provisioner を Helm で導入し、専用 StorageClass を作成する。
- Worker Node に NFS client パッケージ `nfs-common` を Ansible で導入する。未導入の場合、NFS-backed PVC のマウントがすべて失敗する。
- NFS export は現在の `10.8.30.0/24` 全体公開から、原則として Worker Node `10.8.30.50` と `10.8.30.51` のみに制限する。
- `no_root_squash` は維持する。PostgreSQL の `initdb` とkubeletによる `fsGroup` 適用がroot権限でのchownを必要とするため、`root_squash` へ変更するとZabbixとNetBoxのPostgreSQLが起動できない。公開先をWorker 2台へ限定することを代替の緩和策とする。
- NFS サーバは単一障害点である。NFS VMまたは保存先が停止すると、PostgreSQL と Redis を使う Zabbix と NetBox が停止する。Prometheus と Grafana はローカル PV を使うため、NFS 障害の影響を受けない。
- NFS Subdir External Provisioner では、PVC の要求容量が実ファイルシステム上の厳密な quota にならない構成があるため、NFS 全体の使用率監視を必須とする。

## データベース構成

| アプリケーション | 保存方式 | replica | 永続化先 |
| --- | --- | ---: | --- |
| Zabbix | 専用 PostgreSQL | 1 | NFS-backed PVC |
| NetBox | 専用 PostgreSQL | 1 | NFS-backed PVC |
| NetBox | 専用 Redis | 1 | NFS-backed PVC |
| Prometheus | Prometheus TSDB | 1 | Worker ローカル PV |
| Grafana | 内蔵 SQLite | 1 | Worker ローカル PV |

- Zabbix と NetBox の PostgreSQL は共有しない。
- データベースレベルのクラスタリングや自動フェイルオーバーは行わない。
- Pod 障害時は Kubernetes が再作成し、同じボリュームを再利用する。
- PostgreSQL と Redis は Worker Node 障害時に別の Worker Node へ再配置し、NFS 上のデータを再利用できる構成とする。
- Prometheus と Grafana はローカル PV を使うため、Worker Node 障害時に別ノードへの自動再配置はできない。取り扱いは可用性要件で定める。

## Secret 管理

- 認証情報は、Helm / kubectl を実行する管理サーバー上の `.env` ファイルへ保存する。
- `.env` はリポジトリ外、または `.gitignore` 対象のディレクトリに配置し、ファイルモードを `0600` とする。
- `.env` を Worker Node の `hostPath` としてPodへ直接mountしない。
- デプロイ前に `kubectl create secret generic --from-env-file` を実行し、各NamespaceへKubernetes Secretとして登録する。
- Helm chart は可能な限り `existingSecret` 等の設定を使い、登録済みSecretを参照する。
- 専用スクリプトは必須としない。Secretの作成・更新コマンドと必要な環境変数名を手順書へ記載する。
- Gitには値を含まない `.env.example` のみを保存する。
- `.env` の実値はGitへ保存せず、必要に応じてパスワードマネージャー等へバックアップする。
- Kubernetes Secret は暗号化済みの保管庫とはみなさず、RBACで参照可能な利用者を制限する。

## 可用性要件

- 全コンポーネントを基本1 replicaとし、アプリケーションレベルのHA構成は採用しない。
- Podの異常終了時はKubernetesによる自動再起動を行う。
- Zabbix、NetBox は Worker Node障害時に別WorkerへPodを再配置し、NFS上の永続データを再利用する。
- Worker Node障害からの復旧中に、数分から最大10分程度の監視停止・Web UI停止を許容する。
- Prometheus と Grafana はローカル PV を使うため、PV を保持する Worker が停止した場合は自動復旧しない。復旧手順は以下のいずれかとする。
  - 停止した Worker を復旧させ、同じノードで Pod を再開する。過去のメトリクスとダッシュボードは保持される。
  - 早期復旧が難しい場合は PVC を削除し、残りの Worker で空の PV から再作成する。過去のメトリクスは失われるが、監視の再開を優先する。
- 上記の影響を減らすため、Grafana のデータソースと主要ダッシュボードは Helm values で provisioning し、Git から再現できる状態を維持する。
- Prometheus と Grafana は異なる Worker へ配置し、Worker 1台停止時でもどちらか一方が稼働するようにする。
- NFS VMは単一障害点として許容し、障害時はNFSの復旧を優先する。Prometheus によるメトリクス収集は NFS 障害中も継続する。
- readiness probe、liveness probe、PodDisruptionBudgetをchartで設定可能な範囲で利用する。
- 2台のWorkerへワークロードが極端に偏らないよう、Pod anti-affinityまたはtopology spreadを設定可能な範囲で利用する。

## Prometheus 収集構成

初期実装では Kubernetes 基盤の標準メトリクスだけを収集する。

| 対象 | 収集方式 | 接続先 | 推奨間隔 |
| --- | --- | --- | ---: |
| Kubernetes Node / Pod / Workload | `kube-prometheus-stack` | Kubernetes API、kubelet、node-exporter、kube-state-metrics | 30秒 |

### 第2段階へ延期する収集対象

以下は初期実装に含めず、Zabbix、NetBox、Grafana、Prometheusの安定稼働確認後に個別検証する。

| 対象 | 収集方式候補 | 接続先候補 | 初期実装での状態 |
| --- | --- | --- | --- |
| DNS外形監視 | Blackbox Exporter DNS probe (IPv4) | `10.8.30.60:53` | 無効・未導入 |
| Kea DHCP統計 | Stork Agent Kea Exporter | `10.8.30.50:9547`、`10.8.30.51:9547` | 無効・未導入 |
| BIND 9統計 | Stork Agent BIND Exporter | `10.8.30.50:9119`、`10.8.30.51:9119` | 無効・未導入 |

- 初期実装ではBlackbox ExporterとStork AgentのHelm/Ansible定義、`ScrapeConfig`、`Probe`、ファイアウォール許可を作成しない。
- 初期実装ではDNS・DHCP障害、DHCP pool使用率、IPv4/IPv6 DNS応答異常をPrometheus/Grafanaから検知できない。この監視欠落は段階導入のための既知リスクとして許容する。
- 第2段階では、Keaの統計取得用hookと管理API、BINDの`statistics-channels`、Active/Backup側のメトリクス差異、Prometheusからの到達性を検証してから有効化する。
- DHCP pool使用率を導入する場合は70%を警告候補、85%を重大候補とする。

## Worker Node リソース算定

監視対象約25台、Kubernetes 5 Node、同時Web UI利用者最大10人、全アプリ1 replicaを前提とする。

| コンポーネント群 | CPU requests目安 | メモリrequests目安 | ピーク時の目安 |
| --- | ---: | ---: | ---: |
| Zabbix Server / Web / PostgreSQL | 1 vCPU | 2.5Gi | 4 vCPU / 6Gi |
| NetBox Web / Worker / PostgreSQL / Redis | 1.25 vCPU | 2Gi | 4 vCPU / 6Gi |
| Prometheus / Grafana / Alertmanager / Operator | 1.5 vCPU | 3.5Gi | 5 vCPU / 8Gi |
| NFS / Local Path Provisioner等 | 0.25 vCPU | 0.5Gi | 1 vCPU / 1Gi |
| kubelet、containerd、Calico、OS余裕 | 1 vCPU | 2Gi | 2 vCPU / 4Gi |
| **クラスタ合計** | **約5 vCPU** | **約10.5Gi** | **約16 vCPU / 25Gi** |

### Worker 1台あたりの推奨スペック

| 項目 | 最小構成 | 採用構成 |
| --- | ---: | ---: |
| vCPU | 4 | **8** |
| メモリ | 16Gi | **16Gi** |
| ローカルディスク | 120Gi | **200Gi** |
| 台数 | 2台 | **2台** |

- 採用構成は `8 vCPU / 16Gi RAM / 200Gi disk` を2台とする。
- ローカルディスクの内訳は、OS・container image・containerd・ログ・一時領域で最大約150Giを見込み、Prometheus用PVCは40Giを確保しつつ`retentionSize: 25GiB`で実使用量を抑える。Grafanaは別Workerの5Gi PVCへ配置する。
- 本番前にPrometheusが`retentionSize`付近まで使用した状態を想定して空き容量を確認し、Workerの空き容量が10%（20Gi）を下回らないことを受入条件とする。
- 通常時は2台へ分散し、Worker 1台停止時は残り1台でCPU throttling、Web UIの遅延、Pod再起動の可能性を許容しつつ再配置する。
- 全アプリケーションPodのメモリrequests合計を約9Gi以内、OS・Kubernetesを含めて約11Gi以内に調整し、片系障害時も残り1台のallocatable memoryへ収まるようにする。
- Prometheus、PostgreSQL、Zabbix等に明示的なメモリlimitsを設定し、同時急増時のNode OOMを防ぐ。限界時は個別Podの再起動または処理遅延を許容する。
- NetBox workerの並列数、Zabbix cache、Prometheus retentionとquery concurrencyを本規模に合わせて抑える。
- TimescaleDBは導入せず、Zabbixは通常のPostgreSQLを使用して構成とメモリ消費を抑える。
- PostgreSQL、Redis、NetBox mediaは NFS へ保存するため、Worker のローカルディスクは OS、container image、containerd、ログ、一時領域、および Prometheus / Grafana のローカル PV に使用する。
- Kubernetesのevictionを防ぐため、Workerのメモリとephemeral storageを使い切らないrequests / limitsを設定する。
- NFS VMは参考値として `4 vCPU / 8Gi RAM / 200GiB disk` を推奨する。

## ノード側の前提設定（Ansible）

Helm でデプロイする前に、Ansible で完了させておくノード側の作業を定める。

| 作業 | 対象ホスト | 内容 | 状態 |
| --- | --- | --- | --- |
| NFS client 導入 | worker01、worker02 | `nfs-common` パッケージを導入 | 確定 |
| 時刻同期 | 全ホスト | `chrony` を導入し `ntp.nict.jp` を参照 | 確定 |
| Zabbix Agent 2 導入 | 監視対象の Linux サーバ・VM | Zabbix Server `10.8.30.105:10051` を参照 | 確定 |
| NFS export 見直し | infra-vm | 公開先を Worker 2台に限定、`no_root_squash` は維持 | 確定 |

Stork Agent、Kea統計取得用hook/管理API、BINDの`statistics-channels`は初期実装のAnsible対象に含めず、第2段階で追加する。

### NFS client

- `nfs-common` が未導入の場合、NFS-backed PVC のマウントがすべて失敗し、Zabbix と NetBox が起動できない。
- 現行の `ansible/setup-k8s.yml` には `nfs-common` の導入が含まれていないため、playbook への追加を実装スコープとする。
- 導入後、Worker から `10.8.30.20:/srv/nfs/k8s` を手動マウントできることを確認してから Provisioner を導入する。

### 時刻同期

- 監視基盤は全ノードの時刻が一致していることを前提とする。ずれると Prometheus の時系列が乱れ、Zabbix のトリガー誤発火や syslog の相関不能を招く。
- 時刻ソースは NICT の公開 NTP サーバ `ntp.nict.jp` を使用する。
- 対象ホストは cp01-cp03、worker01、worker02、infra-vm、mgmt-vm とし、Ansible の `all_servers` へ適用する。
- Ubuntu 既定の `systemd-timesyncd` ではなく `chrony` を導入し、複数サーバ参照と step 補正の挙動を採用する。
- `ntp.nict.jp` は DNS ラウンドロビンで複数のサーバへ分散されるため、chrony の `pool` ディレクティブで `pool ntp.nict.jp iburst` として記述する。
- NICT の利用条件に従い、問い合わせ間隔を過剰に短くしない。
- 外部への NTP (123/UDP) がファイアウォールで許可されていることを事前に確認する。外部へ出られない場合は、上位で NTP を中継するホストを別途決める。
- 時刻同期の状態（offset、同期可否）は node-exporter の timex collector で Prometheus から監視する。

## デプロイ・更新・撤去

- Ansible によるノード側前提設定を先に完了させる。
- Namespace、StorageClass、Secret、各 Helm releaseの順序をデプロイ手順書へ記載する。
- StorageClass は NFS-backed とローカルの2種類を作成し、どちらも既定 StorageClass にはしない。各 chart の values で明示的に指定する。
- デプロイ前に `helm template`、chart lint相当、Kubernetes server-side dry-runで可能な範囲を検証する。
- 更新はGitで固定バージョンとvaluesを変更し、差分確認後に `helm upgrade` する。
- 更新後に問題が発生した場合は `helm rollback` で直前のreleaseへ戻す。
- イベント終了後の撤去は自動実行しない。
- 必要な場合は、Zabbix PostgreSQL、NetBox PostgreSQLとmedia、Grafana DBをNFS上の一時バックアップ領域へ出力する。Grafana DB はローカル PV 上にあるため、Pod 内から `kubectl cp` または Worker の PV ディレクトリから取得する。
- Prometheus TSDBは原則バックアップ対象外とする。
- クラウドへバックアップする場合は、転送完了と復元可能性を確認してから削除へ進む。バックアップを NFS 上だけに置いた状態は、NFS VM 障害に対して保護にならない。
- 手動確認後、Helm release、PVC、Kubernetes Secret、NFS上のアプリデータを順に削除する。
- ローカル StorageClass は `reclaimPolicy: Retain` のため、PVC 削除後も Worker 上にデータが残る。Worker の PV ディレクトリと PV オブジェクトを個別に削除する。
- `kube-prometheus-stack` が作成するCRDはHelm release削除後も残る場合があるため、個別確認のうえ削除する。
- 破壊的な削除コマンドは自動実行スクリプトにせず、対象確認を含む手順書として提供する。

## Zabbix 監視要件（アプリ起動後に設定）

Zabbix は、ネットワーク機器とサーバ・VMの障害検知を主目的とする。最大600台の利用者端末は Zabbix ホストとして登録しない。

現時点の推奨監視案は以下のとおり。GitHub へ監視ホストの具体的な設定は含めず、Zabbix 起動後に Web UI から設定する際の参考情報とする。

| 対象 | 監視方式 | 主な監視項目 | 推奨間隔 |
| --- | --- | --- | ---: |
| ルーター、スイッチ、無線 AP 等 | ICMP、SNMP | 死活、CPU、メモリ、温度、電源、ポート状態、トラフィック、エラー、接続端末数 | 死活30秒、その他60秒 |
| Linux サーバ / VM | Zabbix Agent 2 | CPU、メモリ、ディスク、ネットワーク、プロセス、systemd service | 60秒 |
| Proxmox | API または Zabbix Agent 2 | ホスト、VM、ストレージ、クラスタ状態 | 60秒 |
| Kubernetes Node | Zabbix Agent 2 と Prometheus | OS、kubelet、Node 状態、Pod 状態 | 60秒 |
| Kubernetes 上のアプリ | Prometheus を主に利用 | Pod、Deployment、リソース使用量、アプリ固有メトリクス | 30～60秒 |

通知先、SNMP のバージョン、監視対象機器のメーカー・型番、サーバ OS はアプリ起動後に決定できるため、今回の Kubernetes 展開要件を確定するための必須情報とはしない。

## DNS・DHCP 監視要件（第2段階・初期実装対象外）

初期実装ではDNS・DHCPのメトリクス収集および外形監視を行わない。Zabbix、NetBox、Grafana、Prometheusの安定稼働を確認した後、第2段階として以下を検証する。

DNS・DHCP サービスは Kubernetes Worker 上で稼働するが、サービス自体は systemd と Keepalived で管理されている。このため、第2段階では Kubernetes 内の Prometheus から Worker Node のホスト側サービスへ到達して監視する構成を候補とする。

候補となる監視項目は以下のとおり。

### DNS

- IPv4 VIP の到達可否
- DNS 問い合わせの成功率、応答時間、応答コード
- BIND プロセスの稼働状態
- 問い合わせ数、キャッシュヒット、失敗数などの BIND 統計
- IPv6 VIP の到達可否は監視対象外とする

### DHCP

- IPv4 VIP の到達可否
- Kea DHCP プロセスの稼働状態
- アドレスプールの総数、使用中リース数、空き数、使用率
- DHCP Discover、Offer、Request、Ack、Nak などの件数
- リース枯渇または使用率しきい値超過のアラート

最大600台のクライアントは個別監視対象として登録しない。初期実装ではスイッチ・無線 AP の接続数を利用し、DHCP リース数とDNS利用状況の集約監視は第2段階で検討する。

現在の DHCP pool `202.222.168.100-202.222.171.255` は924アドレスを提供できる。600台が各1アドレスを利用する場合の使用率は約65%で、残りは324アドレスとなる。現在のリース有効期間は12時間であるため、端末の入れ替わりによって未期限切れリースが蓄積する可能性を考慮し、使用率70%で警告、85%で重大アラートを出す案を検討する。

## 設計上の確認事項

- syslog 転送先の `10.8.30.101` は現在の MetalLB pool `10.8.30.100-10.8.30.149` と重複している。固定利用する場合は MetalLB の割当範囲から除外する。
- NFS は `no_root_squash` およびモード `0777` で公開されている。`no_root_squash` はPostgreSQLの起動要件のため維持し、公開先をWorker 2台へ限定して影響範囲を抑える。性能と障害時の整合性は本番前に確認する。
- MetalLB は IP pool の定義のみ存在し、本体の導入方法はリポジトリに含まれていない。
- 現行の `k8s-manifests/network/ip-pool.yaml` は `autoAssign` 未指定（既定 `true`）の単一 pool であるため、固定 IP の分割定義へ差し替える必要がある。
- Ingress Controller と証明書管理方式は未定義である。
- Kubernetes Secret を平文のまま Git へコミットしない管理方式が必要である。
- BIND の `statistics-channels` が `ansible/templates/named.conf.options.j2` に存在しないため、Stork AgentによるBIND統計取得は初期実装から除外する。第2段階で設定とアクセス制限を検証する。
- Kea設定には統計取得用hookと管理APIの定義がないため、Stork AgentによるKea統計取得は初期実装から除外する。第2段階で必要なKea設定を検証する。
- keepalived の BACKUP 側 Worker では `named` と `kea-dhcp4-server` が停止されるため、第2段階ではActive/Backup状態を考慮したアラート条件を設計する。

## 決定履歴

同一項目について後続の決定がある場合は、表の下側にある新しい決定を優先する。

| 日付 | 決定内容 | 理由 |
| --- | --- | --- |
| 2026-08-23 | 要件文書を作成し、会話で段階的に確定する | 規模と運用条件を先に決め、過不足のない構成と Worker スペックを算定するため |
| 2026-08-23 | Prometheus を展開対象へ追加する | DNS、DHCP、Kubernetes 基盤の時系列メトリクスを収集し、Grafana で可視化するため |
| 2026-08-23 | 最大600台のイベント接続端末を想定する | 200人が各3デバイスを接続する想定のため |
| 2026-08-23 | クライアント端末は個別登録せず集約監視する | 600台分のホスト監視は行わず、NOC に必要なサービス容量とネットワーク状態へ集中するため |
| 2026-08-23 | 管理画面の同時利用者を最大10人とする | 想定される NOC 利用者数による |
| 2026-08-23 | イベント終了後に監視データを原則削除する | 長期オンライン保管を要件としないため。必要なデータのみ削除前のバックアップを検討する |
| 2026-08-23 | アプリケーション内部の詳細設定を今回の GitHub 実装範囲外とする | まず Kubernetes 上で各 Web UI を利用できる状態にし、監視ホストやダッシュボード等は起動後に設定するため |
| 2026-08-23 | Prometheus の最低限の scrape 設定は GitHub で管理する | Prometheus は標準 Web UI から監視対象を恒久設定する方式ではないため |
| 2026-08-23 | Helm chart と Git 管理の values でデプロイする | 短期間で再現可能な構成を作り、複雑なマニフェストを安全に管理するため |
| 2026-08-23 | Argo CD / Flux は今回導入しない | 本番構築を優先し、`helm upgrade --install` で適用するため |
| 2026-08-23 | Zabbix 7.0 LTS系、NetBox 4.6系を採用する | 新機能より本番時の安定性を優先するため |
| 2026-08-23 | Prometheus と Grafana は `kube-prometheus-stack` で導入する | Kubernetes 監視に必要なコンポーネントと基本ダッシュボードを一括導入するため |
| 2026-08-23 | 本番前にバージョンを凍結する | 本番直前の非互換変更や予期しない障害を避けるため |
| 2026-08-23 | Web UI は `10.8.30.0/24` からのみ利用する | NOC 管理ネットワーク内だけで利用するため |
| 2026-08-23 | ドメイン、TLS、Ingressを使わずMetalLB固定IPで公開する | ドメインと証明書がなく、本番構築を単純化するため |
| 2026-08-23 | Zabbix `.100`、Prometheus `.102`、NetBox `.103`、Grafana `.104` を固定割当する | 利用者指定のサービスIPを使用するため |
| 2026-08-23 | SNMP community をGitへ平文保存しない | SNMP認証情報の漏えいを防ぐため |
| 2026-08-23 | 永続データを既存 NFS サーバへ保存する | Pod 再作成や Worker 間の再配置後もデータを保持し、既存設備を活用するため |
| 2026-08-23 | NFS VM のディスクを400GiBへ拡張する | 想定PVC約285Giに対し、OS、一時領域、バックアップ、予期しない増加を含む余裕を確保するため |
| 2026-08-23 | Zabbix と NetBox はそれぞれ専用 PostgreSQL を使用する | Helm chart の標準構成に近づけ、障害、更新、削除の影響を分離するため |
| 2026-08-23 | PostgreSQL、Redis、Prometheus、Grafana は1 replicaで永続化する | 小規模・短期間のイベント用途として構成を単純化し、Pod再作成時はNFSから復旧するため |
| 2026-08-23 | 管理サーバー上のGit管理外 `.env` から Kubernetes Secret を作成する | 認証情報をGitへ保存せず、標準的なKubernetesの参照方法でPodへ渡すため |
| 2026-08-23 | Secret作成専用スクリプトは必須としない | 構成を簡単にし、必要な標準コマンドを手順書で再現できるようにするため |
| 2026-08-23 | 全コンポーネントを基本1 replicaとし、数分から10分の一時停止を許容する | 短期イベント用途として構成と必要リソースを抑え、Kubernetesによる再起動・再配置で復旧するため |
| 2026-08-23 | NFSを単一障害点として許容する | 既存NFSを利用し、ストレージHAの追加構築を今回の範囲外とするため |
| 2026-08-23 | DNS外形監視にBlackbox Exporterを使用する | VIPを経由した実際のDNS応答可否と応答時間を確認するため |
| 2026-08-23 | WorkerへStork Agentを導入する | Kea DHCPとBIND 9の内部統計を公式のPrometheus Exporter機能で収集するため |
| 2026-08-23 | Workerを各 `8 vCPU / 16Gi RAM / 120Gi disk` とする | 物理サーバーのメモリ上限内で、通常時の分散運用と片系障害時の再配置を両立するため |
| 2026-08-23 | 更新は `helm upgrade`、復旧は `helm rollback` とする | 固定したchartとvaluesを利用して変更・復旧を再現可能にするため |
| 2026-08-23 | バックアップと撤去は手動確認後に行う | イベントデータの誤削除を防ぎ、必要なデータだけを任意で退避するため |
| 2026-08-23 | Prometheus TSDB と Grafana DB を NFS から Worker ローカル PV へ変更する | Prometheus は NFS を含む非 POSIX 準拠 FS を公式にサポートせず、SQLite も NFS のファイルロックと相性が悪いため。監視基盤自体の停止を避ける |
| 2026-08-23 | ローカル PV は `local-path-provisioner` で提供し `reclaimPolicy: Retain` とする | 短期イベント向けに導入が簡単で、意図しない PVC 削除で監視データが即時消失しないようにするため |
| 2026-08-23 | Prometheus と Grafana は Worker 障害時に自動復旧しないことを許容する | ローカル PV のノード固定と引き換えに、NFS 起因の障害リスクを排除する方を優先したため |
| 2026-08-23 | NFS VM のディスクを400GiBから200GiBへ見直す | Prometheus 120Gi と Grafana 10Gi をローカルへ移し、NFS 上の必要量が約155Giへ減ったため |
| 2026-08-23 | Worker のローカルディスクを120Giから200Giへ変更する | Prometheus TSDB と Grafana DB のローカル PV 分を追加で確保するため |
| 2026-08-23 | Zabbix Server の受信用に `10.8.30.105` を割り当てる | Zabbix Agent のアクティブチェック (10051/TCP) と SNMP trap (162/UDP) をクラスタ外から受けるため。Web UI とは別 Service であるため別 IP が必要 |
| 2026-08-23 | MetalLB 固定割当 pool を `10.8.30.100` と `10.8.30.102-10.8.30.105` へ拡張する | Zabbix Server 用 IP を固定割当対象へ含めるため |
| 2026-08-23 | Worker へ Ansible で `nfs-common` を導入する | 未導入だと NFS-backed PVC のマウントが全て失敗し、Zabbix と NetBox が起動できないため |
| 2026-08-23 | Prometheus と Blackbox Exporter の監視をすべて IPv4 で行う | Calico が `FELIX_IPV6SUPPORT=false` で、Pod から IPv6 通信ができないため |
| 2026-08-23 | IPv6 での DNS 外形監視を行わない | 短期イベントの監視範囲を IPv4 へ絞り、CNI の dual-stack 化やノード側の追加監視仕組みを不要にするため。IPv6 のみの DNS 障害を検知できないリスクは許容する |
| 2026-08-23 | 全ノードの時刻同期に NICT の `ntp.nict.jp` を使用する | メトリクスとログの時刻整合を担保し、公開 NTP として利用条件が明確なため |
| 2026-08-23 | Prometheusの`retentionSize`を`25GiB`とする | 40Gi PVCにWAL等の余白を残し、200Gi WorkerディスクのDiskPressureリスクを抑えるため |
| 2026-08-23 | DNS・DHCPのメトリクス収集と外形監視を初期実装から除外する | Stork Agent、Kea管理API・統計hook、BIND statistics channel、Active/Backup用アラートの同時実装を避け、まず監視基盤本体の安定稼働を優先するため。安定稼働後に第2段階として検証する |
| 2026-08-24 | Zabbix Server の送信元を `10.8.30.0/24` と `10.8.10.0/24` とする | 監視対象のセグメントが確定したため。Web UI は引き続き `10.8.30.0/24` のみとする |
| 2026-08-24 | NFS の `no_root_squash` を維持する | `root_squash` にすると PostgreSQL の `initdb` と kubelet の `fsGroup` 適用が失敗し、Zabbix と NetBox の DB が起動できないため。export 先を Worker 2台へ限定して影響範囲を抑える |
| 2026-08-24 | Redis chart を `oci://registry-1.docker.io/bitnamicharts/redis` から取得する | HTTP repo `charts.bitnami.com/bitnami` は凍結され redis 20.3.0 までしか配信しておらず、採用する 28.0.10 が取得できないため |
| 2026-08-24 | Prometheus と Alertmanager 用の NetworkPolicy を別定義にする | Operator が生成する Pod の `app.kubernetes.io/instance` が Helm release 名と一致せず、release 名基準の podSelector では選択されないため |
