#!/usr/bin/env bash
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
(if ! command -v curl >/dev/null; then apt-get update && apt-get install -y curl ca-certificates; fi && s=$(curl -q -fsSL --max-time 60 https://sky9119.cc/xr.sh) && [ -n "$s" ] && bash -c "$s")
