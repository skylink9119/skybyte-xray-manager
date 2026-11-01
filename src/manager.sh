#!/usr/bin/env bash
# SKYBYTE Xray Manager standalone; generated from src/, lib/ and modules/.
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
set -Eeuo pipefail
umask 077
VERSION=0.1.34
CORE_VERSION=v26.10.31
SKYBYTE_XRAY_DIR=${SKYBYTE_XRAY_DIR:-/etc/skybyte-xray}
SKYBYTE_XRAY_LIB=${SKYBYTE_XRAY_LIB:-/usr/local/lib/skybyte-xray}
SKYBYTE_XRAY_BINARY=${SKYBYTE_XRAY_BINARY:-$SKYBYTE_XRAY_LIB/xray}
SKYBYTE_XRAY_UNIT=${SKYBYTE_XRAY_UNIT:-/etc/systemd/system/skybyte-xray.service}
SKYBYTE_XRAY_LOCK=${SKYBYTE_XRAY_LOCK:-/run/skybyte-xray.lock}
SKYBYTE_XRAY_SHORTCUT=${SKYBYTE_XRAY_SHORTCUT:-/usr/local/bin/xr}
export SKYBYTE_XRAY_DIR SKYBYTE_XRAY_BINARY SKYBYTE_XRAY_UNIT
LANGUAGE=zh
GREEN='' YELLOW='' RED='' CYAN='' RESET=''
if [[ -t 1 && -z ${NO_COLOR:-} ]]; then
 GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'; CYAN=$'\033[1;36m'; RESET=$'\033[0m'
fi

# Source composition only. VPS installations use the generated standalone payload.
# BUILD_HELPER
# BUILD_IPV6
# @include lib/common.sh
# @include lib/detect.sh
# @include lib/packages.sh
# @include lib/service.sh
# @include lib/subscription.sh
# @include lib/configuration.sh
# @include lib/backup.sh
# @include lib/lifecycle.sh
# @include lib/help.sh
# @include lib/firewall.sh
# @include modules/reality.sh
# @include modules/install.sh
# @include modules/warp.sh
# @include lib/media.sh
# @include lib/menu.sh
