# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""SKYBYTE Xray Manager: private configuration, exports and transactions.

Only generated runtime state contains credentials. No imported content is executed.
"""
import argparse
import base64
import copy
import concurrent.futures
import errno
import hashlib
import io
import ipaddress
import json
import os
import platform
import re
import shlex
import shutil
import socket
import ssl
import subprocess
import sys
import tarfile
import tempfile
import urllib.parse
import urllib.error
import urllib.request
import uuid
import zipfile
from pathlib import Path

VERSION = "0.1.33"
CORE_VERSION = "v26.10.31"
OWNER = "SKYBYTE-XRAY/1\n"
UNIT_MARK = "# SKYBYTE Xray Manager unit v1\n"
KINDS = ("vision", "xhttp-reality", "xhttp-tls")
WARP_PROFILES = {
    "netflix": ["netflix.com", "netflix.net", "nflxext.com", "nflximg.com", "nflximg.net", "nflxso.net", "nflxvideo.net"],
    "disney": ["disneyplus.com", "disney-plus.net", "dssott.com", "bamgrid.com"],
    "chatgpt": ["openai.com", "chatgpt.com", "oaistatic.com", "oaiusercontent.com"],
    "gemini": ["gemini.google.com", "aistudio.google.com", "generativelanguage.googleapis.com"],
}
MODES = ("auto", "packet-up", "stream-up", "stream-one")
MAX_ARCHIVE = 16 * 1024 * 1024


# @include core_storage.py


# @include core_validation.py


# @include core_nodes.py


# @include core_transactions.py


# @include core_download.py


# @include core_overview.py


# @include core_firewall.py


# @include core_bbr.py


# @include core_update.py


# @include core_cli.py
