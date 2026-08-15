#!/usr/bin/env bash
# image/etc/nftables.conf の構文チェック。
#
# image/etc/nftables.conf は絶対パス /etc/nftables.d/*.conf をincludeするため、
# 開発ホストでそのまま `nft -c -f` にかけるとホスト自身の/etc/nftables.d
# (通常空、または無関係な内容)を見てしまい、本リポジトリのallow-listドロップインを
# 検証しないまま素通りしうる。そのためパスを本リポジトリ内へ差し替えた
# 一時ファイルで検証する。minivps-router-appliance版と同型。
#
# 注意: nft -c は構文チェックのみでもCAP_NET_ADMINを要求する(コンテナ/
# サンドボックス内では 'Operation not permitted' になりうる。実機または
# sudoで実行すること)。確定的な検証は実ビルドVM上で
# `sudo nft -c -f /etc/nftables.conf` を実行する。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_CONF="$(mktemp)"
trap 'rm -f "$TMP_CONF"' EXIT

sed "s#/etc/nftables.d#${REPO_ROOT}/image/etc/nftables.d#" \
  "$REPO_ROOT/image/etc/nftables.conf" > "$TMP_CONF"

nft -c -f "$TMP_CONF"
echo "OK: nftables.conf の構文チェックに通りました"
