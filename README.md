# minivps-db-appliance

[mini-vps-platform](https://github.com/0x69d/mini-vps-platform)上で、seg2にDB層を提供するDBアプライアンスVM用のゴールデンイメージ・VM spec・ゲスト内設定一式。

## これは何のためのリポジトリか

mini-vps-platformにはこれまで、実際のワークロードを載せて層ごとにセグメントを分ける構成の実例が無かった。本リポジトリは[minivps-web-appliance](https://github.com/0x69d/minivps-web-appliance)と対になり、web層(seg1)とDB層(seg2)をrouter-1で分離して、web層からしかDBに到達できない構成を実現する。

db-1が担うのはMySQLの稼働と、seg1からの接続のみを受け付けること。この到達制御は二重で、router-1のforward chainがセグメント間を、db-1自身のnftables input chainが受信を絞る。

## 前提条件

- mini-vps-platformがセットアップ済み(`~/.ssh/minivps_ed25519.pub`公開鍵、`seg2`ネットワーク、`images`ストレージプール、`ubuntu-26.04.img`が`images`プールに存在すること)。
- [minivps-router-appliance](https://github.com/0x69d/minivps-router-appliance)のrouter-1が稼働し、3306の許可ルールが追記されていること。無いとforward chainの既定拒否でweb-1から届かない([router-1側の許可ルール](#router-1側の許可ルール)参照)。

## アーキテクチャ

```mermaid
flowchart TB
    DEF(["default<br/>192.168.122.0/24<br/>NAT・DHCP"])
    W["web-1<br/>Apache<br/>別リポジトリ"]
    S1(["seg1<br/>192.168.201.0/24"])
    R["router-1<br/>別リポジトリ"]
    S2(["seg2<br/>192.168.202.0/24"])
    D["db-1<br/>MySQL"]

    DEF ---|"管理NIC .50"| D
    D ---|"サービスNIC .50"| S2
    S2 ---|".10"| R
    R ---|".10"| S1
    S1 ---|".40"| W
```

| ネットワーク | CIDR | db-1のIP | 用途 |
|---|---|---|---|
| default | 192.168.122.0/24 | 192.168.122.50 | 管理(SSH) |
| seg2 | 192.168.202.0/24 | 192.168.202.50 | MySQL提供 |

db-1はseg2への単一配置とし、web-1(192.168.201.40)からはrouter-1経由で到達させる。このためspecにseg1宛の戻り経路(`static_routes: via 192.168.202.10`)を宣言している。これが無いと、接続はweb-1→router-1→db-1と届くのに、応答がデフォルトルートへ非対称に流れて返らない。

受信制御: specの`filters`は未設定とし、router-1/dns-1と同様、ゴールデンイメージに焼き込んだゲスト内nftablesのinput chainが受信制御を担う。3306はseg1(192.168.201.0/24)から、22/tcpは管理ネット(192.168.122.0/24)からのみ許可、診断用ICMP許可、他はデフォルト拒否。

MySQLの`bind-address`は0.0.0.0のままにしている。mysql.serviceの依存は`network.target`止まりで`network-online.target`を待たないため、seg2側IPに絞るとnetplanがアドレスを付ける前の起動でbindに失敗しうるため。到達制御は上記のinput chainが担う。`image/etc/mysql/mysql.conf.d/zz-minivps.cnf`と`image/etc/nftables.conf`は一組で、片方だけ変更するとどこからでも接続できる状態になる。

rootはUbuntu既定の`unix_socket`認証のままで、パスワードは焼き込まない。ローカルのSSH経由でのみ使うため。

名前解決は管理NICの`nameservers`でdefaultセグメントのlibvirt dnsmasqを指定している。全NICが静的だとnetplanがリゾルバを持たず、運用者がaptを叩けなくなるため。

## クイックスタート

1. ゴールデンイメージをビルドする:
   ```bash
   ./build/build-golden-image.sh
   ```
   完了すると `images` プールに `minivps-db-golden-YYYYMMDD.qcow2` という名前で配置される。出力メッセージで実際のファイル名を確認する。

2. `specs/db-1.yaml` の `base_image` を、ビルドで得られたファイル名に書き換える。

3. VMを作成する(mini-vps-platform側で):
   ```bash
   uv run mini-vps create /path/to/minivps-db-appliance/specs/db-1.yaml
   ```

4. 管理アクセスを確認する:
   ```bash
   uv run mini-vps status db-1   # ip: 192.168.122.50 が返る
   ssh -i ~/.ssh/minivps_ed25519 ubuntu@192.168.122.50
   sudo ss -lntp | grep 3306     # 0.0.0.0:3306 でリッスンしている
   ```

5. [秘密情報の初期化](#秘密情報の初期化)を行う。これを終えるまでweb-1から接続できない。

## 秘密情報の初期化

ゴールデンイメージにはアプリ用DBユーザーを焼き込んでいない。これは、イメージやgit履歴に秘密が残るのを防ぐため。VM初回起動後にdb-1で以下を実行する:

```bash
# 接続元はweb-1のIPに限定する。seg1全体を許可する場合は 'appuser'@'192.168.201.%'
sudo mysql -e "
  CREATE USER 'appuser'@'192.168.201.40' IDENTIFIED BY '<自分で決めたパスワード>';
  CREATE DATABASE appdb;
  GRANT ALL ON appdb.* TO 'appuser'@'192.168.201.40';
  FLUSH PRIVILEGES;"
```

パスワードはリポジトリにもspecにも書かない。動作確認はweb-1から行う:

```bash
mysql -h 192.168.202.50 -u appuser -p appdb -e 'select 1'
```

## router-1側の許可ルール

web-1からdb-1(192.168.202.50)の3306へ到達させるには、router-1の許可リストであるminivps-router-applianceの `/etc/nftables.d/90-segment-allow.conf`に運用者が以下を追記する:

```
add rule inet filter forward ip saddr 192.168.201.0/24 ip daddr 192.168.202.50 tcp dport 3306 accept
```

逆方向(db-1→web-1)のルールは追加しない。forward chainの`ct state established,related accept`が応答を拾うため、新規セッションの向き1本で足りる。

追記後は必ずメインファイル経由でreloadする:

```bash
sudo systemctl reload nftables
```

このルールは稼働中のrouter-1に対する手編集のため、router-1をゴールデンイメージから作り直すと失われる。

## tests

- `tests/lint-nftables.sh` — nftables.confの構文チェック。

## トラブルシューティング

- ビルドがタイムアウトした場合: `virsh console <ビルドVM名>` でシリアルコンソールに接続して調査する。ビルド用ドメインはtransientで、シャットダウンと同時に消滅する点に注意。
- ホスト(192.168.202.1)から `mysql -h 192.168.202.50` がタイムアウトするのは仕様。ホストは管理ネットにもseg1にも該当しないため、db-1のinput chainで落ちる。動作確認はweb-1から行う。
- web-1から繋がらない: 経路とフィルタを切り分ける。web-1で`ip route get 192.168.202.50`を確認し、届かない場合は[router-1側の許可ルール](#router-1側の許可ルール)の追記漏れを疑う。DBユーザーの接続元指定(`'appuser'@'192.168.201.40'`)がweb-1のIPと一致しているかも確認する。
- `mini-vps status`が管理IP以外を返す場合: `specs/db-1.yaml`の`networks`の並び順(`default`が先頭かつ静的IPになっているか)を確認する。
- ゴールデンイメージには`/etc/mysql/debian.cnf`にパッケージ生成の`debian-sys-maint`パスワードが含まれる。`.gitignore`が`*.qcow2`を除外するのでgitには入らないが、イメージファイル自体を配布する場合は注意する。
- DHCPレンジとの重複: 192.168.202.50/192.168.122.50はいずれもlibvirt DHCPレンジ(.2〜.254)内にある。db-1は常時起動の運用を前提とし、長期停止させる場合は同アドレスのDHCP払い出しと衝突しうる点に注意する。
