#!/usr/bin/env bash
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
(if ! command -v curl >/dev/null; then apt-get update && apt-get install -y curl ca-certificates; fi && script=$(curl -q -fsSL --max-time 60 https://raw.githubusercontent.com/skylink9119/skybyte-xray-manager/main/bootstrap.sh) && bash -c "$script")
