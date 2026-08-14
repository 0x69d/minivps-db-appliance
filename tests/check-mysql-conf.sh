#!/usr/bin/env bash
# image/etc/mysql/mysql.conf.d/zz-minivps.cnf の構文チェック。
# 前提: mysqld(未導入なら `sudo apt install mysql-server-core`)。
#
# 実機の /etc/mysql 全体ではなく本リポジトリのファイルだけを検証したいため、
# check-apache-conf.sh(minivps-web-appliance)と同じく、対象ファイルだけを
# 読ませる形で検証する。--validate-config は設定を検証してサーバを起動せずに終わる。
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="$REPO_ROOT/image/etc/mysql/mysql.conf.d/zz-minivps.cnf"

command -v mysqld >/dev/null || {
  echo "missing: mysqld (sudo apt install mysql-server-core)" >&2
  exit 1
}

echo "==> mysqld --validate-config(本リポジトリの設定のみ読ませて検証)"
# --defaults-file は --validate-config より前に置く。後ろだと通常のオプションとして
# 解釈され「unknown variable 'defaults-file=...'」で失敗する。
mysqld --defaults-file="$TARGET" --validate-config
echo "OK: MySQL設定の構文チェックに通りました"
