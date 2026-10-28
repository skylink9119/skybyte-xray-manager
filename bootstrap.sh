#!/usr/bin/env bash
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
(
 set -Eeuo pipefail
 [[ $(id -u) == 0 ]] || { printf 'Please run as root / 请以 root 账户运行\n' >&2;exit 1; }
 os_id=$(awk -F= '$1=="ID" {gsub(/"/,"",$2);print $2}' "${OS_RELEASE:-/etc/os-release}")
 case $os_id in ubuntu|debian) :;; *) printf 'Ubuntu/Debian only / 仅支持 Ubuntu/Debian\n' >&2;exit 1;; esac
 if ! command -v curl >/dev/null;then
  printf 'Installing curl and CA certificates / 正在安装 curl 与 CA 证书……\n'
  if ! apt-get -o APT::Update::Error-Mode=any update;then
   printf 'APT refresh failed / APT 索引更新失败，已停止下载\n' >&2;exit 1
  fi
  if ! DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates;then
   printf 'curl installation failed / curl 安装失败，已停止下载\n' >&2;exit 1
  fi
  command -v curl >/dev/null || { printf 'curl is still unavailable / 安装后仍找不到 curl\n' >&2;exit 1; }
 fi
 staging=$(mktemp -d "${TMPDIR:-/tmp}/skybyte-xray-bootstrap.XXXXXX")
 trap 'rm -rf -- "$staging"' EXIT
 curl -q -fsSL --proto '=https' --proto-redir '=https' --retry 2 --connect-timeout 10 --max-time 120 'https://github.com/skylink9119/skybyte-xray-manager/releases/download/v0.1.21/install.sh' -o "$staging/install.sh"
 bash -n "$staging/install.sh"
 bash "$staging/install.sh"
)
