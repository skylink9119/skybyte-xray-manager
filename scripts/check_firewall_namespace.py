#!/usr/bin/env python3
# Copyright (C) 2026 SKYBYTE (skylink9119)
# SPDX-License-Identifier: GPL-3.0-only
"""CI-only real UFW/nft coexistence checks inside private mount/network namespaces."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile


def run(arguments, **kwargs):
    return subprocess.run(arguments, check=True, capture_output=True, text=True, timeout=60, **kwargs)


def probe(family, source, destination, allowed):
    with socket.socket(family) as client:
        client.settimeout(3)
        client.bind((source, 0))
        try:
            client.connect((destination, 2222))
        except OSError:
            if allowed:
                raise
        else:
            if not allowed:
                raise AssertionError('Fail2ban did not block the test source')


def main():
    if (sys.platform != 'linux' or os.geteuid() != 0 or
            os.environ.get('SKYBYTE_FIREWALL_NAMESPACE_TEST') != '1'):
        raise RuntimeError('Requires explicit CI opt-in and Linux root inside isolated namespaces')
    for kind in ['net', 'mnt']:
        if os.readlink('/proc/self/ns/'+kind) == os.readlink('/proc/1/ns/'+kind):
            raise RuntimeError('Refusing to test in the host '+kind+' namespace')
    run(['mount', '--make-rprivate', '/'])
    project = Path(__file__).resolve().parents[1]
    spec = importlib.util.spec_from_file_location('core', project/'src/core.py')
    core = importlib.util.module_from_spec(spec); spec.loader.exec_module(core)
    with tempfile.TemporaryDirectory(prefix='skybyte-firewall-ns-') as name:
        folder = Path(name)
        # UFW writes both configuration and state; give each path a private copy.
        for index, target in enumerate([Path('/etc/ufw'), Path('/etc/default/ufw'), Path('/lib/ufw').resolve()]):
            source = folder/('private-'+str(index))
            if target.is_dir(): shutil.copytree(target, source, symlinks=True)
            else: shutil.copy2(target, source)
            run(['mount', '--bind', str(source), str(target)])
        run(['mount', '-t', 'tmpfs', '-o', 'size=16m', 'tmpfs', '/run'])
        os.environ['SSH_CONNECTION'] = ''
        run(['ufw', '--force', 'reset'])
        run(['ip', 'link', 'set', 'lo', 'up'])
        for setting in ['all', 'default', 'lo']:
            run(['sysctl', '-w', 'net.ipv6.conf.'+setting+'.disable_ipv6=0'])
        run(['ip', '-6', 'addr', 'add', '::2/128', 'dev', 'lo', 'nodad'])
        run(['nft', '-f', '-'], input='''table inet f2b-table {
 set addr-set-sshd { type ipv4_addr; elements = { 127.0.0.2 }; }
 set addr6-set-sshd { type ipv6_addr; elements = { ::2 }; }
 chain f2b-chain {
  type filter hook input priority -1; policy accept;
  tcp dport 2222 ip saddr @addr-set-sshd reject with icmp type port-unreachable
  tcp dport 2222 ip6 saddr @addr6-set-sshd reject with icmpv6 type port-unreachable
 }
}
''')
        def state():
            return json.loads(run(['nft', '-j', 'list', 'table', 'inet', 'f2b-table']).stdout)['nftables']
        before = state()
        assert core.nft_fail2ban_signature(before)
        with socket.socket(socket.AF_INET) as ipv4, socket.socket(socket.AF_INET6) as ipv6:
            ipv6.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
            ipv4.bind(('0.0.0.0', 2222)); ipv4.listen(16)
            ipv6.bind(('::', 2222)); ipv6.listen(16)
            def verify_connections():
                probe(socket.AF_INET, '127.0.0.1', '127.0.0.1', True)
                probe(socket.AF_INET, '127.0.0.2', '127.0.0.1', False)
                probe(socket.AF_INET6, '::1', '::1', True)
                probe(socket.AF_INET6, '::2', '::1', False)
            verify_connections()
            assert core.firewall_setup(folder/'nodes', ['2222'], ['8443'])
            assert core.ufw_state() == 'active'
            assert state() == before, 'UFW changed the existing Fail2ban rules or bans'
            verify_connections()
            probe(socket.AF_INET, '127.0.0.3', '127.0.0.1', True)
            run(['nft', 'add', 'element', 'inet', 'f2b-table', 'addr-set-sshd', '{', '127.0.0.3', '}'])
            probe(socket.AF_INET, '127.0.0.3', '127.0.0.1', False)
            after_new_ban = state()
            assert core.ufw_disable() == 'disabled'
            assert state() == after_new_ban, 'UFW disable changed Fail2ban rules or bans'
            verify_connections()
            probe(socket.AF_INET, '127.0.0.3', '127.0.0.1', False)
        print('Real UFW enable/disable preserves IPv4/IPv6 Fail2ban bans; new bans still block TCP connections')


if __name__ == '__main__':
    main()
