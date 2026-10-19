# Changelog

## 0.1.10 — 2026-10-19

- Lead BBR status with a prominent enabled/not-enabled summary based on the running congestion control, with terminal colors and readable parameter labels instead of raw JSON.
- Distinguish active BBR from available algorithms or a saved configuration; status remains read-only after viewing, enabling or restoring settings.

## 0.1.9 — 2026-10-19

- Allow structurally validated independent Fail2ban nftables TCP input bans to coexist with UFW initialization, preserving IPv4/IPv6 address sets and existing bans.
- Preview coexistence, verify ban structure after activation or rollback, tolerate dynamic ban/counter updates, and keep custom/unknown/iptables firewall rules guarded.
- Add reported-layout and adversarial regressions plus real UFW/nft TCP checks in private network and mount namespaces in CI.

## 0.1.8 — 2026-10-19

- Group firewall menu actions as 1–5 and BBR actions as 6–8, with one action per line and updated recovery references.
- Add UFW submenu 3 to purge its package and rule configuration, including residual configuration after package removal, with explicit confirmation and matching read-only preflight.
- Fix empty optional firewall arguments under Bash 3.2 when allowing all node ports.
- Verify the purged package state, report partial cleanup failures, and cover cancellation, disable failures, config-only cleanup and bilingual menu dispatch without changing the host firewall.

## 0.1.7 — 2026-10-19

- Add menu 12 → 8 for disabling UFW or removing only its package while retaining rule configuration, with targeted warnings and explicit confirmation.
- Check package state/dependencies before disabling, verify inactivity before removal, refuse forced dependency changes, and report partial removal failures without automatic re-enable.
- Add isolated state/order/cancellation/failure regressions and a real dpkg no-act integration check that leaves the CI UFW package installed.

## 0.1.6 — 2026-10-19

- Fix first-run UFW rule insertion with prepend instead of insert 1; add real distribution frontend compatibility checks with an isolated backend.
- Report failed UFW commands, exit codes and safe error categories instead of generic core errors. CI installs the distro UFW package for frontend regression checks.

- Fix UFW initialization false positives from empty nft/iptables tables, default ACCEPT chains and unreferenced empty user chains, including tables created by iptables-nft inspection.
- Inspect nft JSON and report the exact command/table/chain or object that blocks setup; keep actual rules, DROP policies and unknown state protected.
- Add regressions for repeated inspection, ACCEPT/NAT/DROP conflicts, malformed output and safe diagnostic labels.

## 0.1.5 — 2026-10-19

- Add menu 12 → 7 to install missing UFW via APT and explicitly initialize/enable it after previewing confirmed SSH, current SSH session, node and extra TCP ports.
- Stage allow rules before applying deny-incoming/allow-outgoing defaults and activation. Refuse active firewalls, existing netfilter rules, restrictive stored UFW rules and unsafe IPv6 configuration.
- Attempt to disable a failed initial activation, report console recovery if rollback fails, and retain package/configuration for inspection. Add isolated activation-order, cancellation, package failure and SSH regressions.

## 0.1.4 — 2026-10-19

- Add menu 13 for stable-release manager updates with version preview, explicit confirmation, pinned repository/tag, release-asset and manifest SHA256 verification, syntax/version/self-check validation and atomic replacement.
- Preserve a previous-script backup and restore it on post-install validation failure; refuse foreign paths and downgrades against both running and installed versions.
- Preserve node credentials, core, services, firewall and BBR settings; exit the old menu after successful update. Add isolated integrity, replacement and bilingual menu regressions.

## 0.1.3 — 2026-10-19

- Add menu 12 for active UFW/firewalld status and explicit inbound TCP allows for managed or selected ports, without firewall enable/disable/reset or global reload.
- Add BBR status, existing-kernel enablement and restoration of saved runtime defaults through a guarded dedicated sysctl file; detect failed application and attempt rollback.
- Add isolated firewall, kernel parameter and bilingual confirmation regressions; preserve TCP/Reality Vision defaults and unchanged XHTTP exports.

## 0.1.2 — 2026-10-19

- Edit installed node addresses, TCP ports and XHTTP paths while preserving credentials and TLS certificates.
- Validate changed ports, regenerate client exports and reuse configuration rollback; keep stopped services stopped and skip empty edits.
- Add editing, export consistency, bilingual menu and failed-restart recovery regressions.

## 0.1.1 — 2026-10-15

- Add the SKYBYTE YouTube subscription invitation and owner-supplied VPS affiliate links to both READMEs.
- Require the public client address, re-prompt empty input and check TCP port availability before target probes or core downloads.
- Explain occupied ports, permissions, missing files, disk space and download/TLS failures without exposing external exception secrets; preserve existing services and configurations.
- Add installation-input, port-conflict and diagnostic-redaction regressions; publish matching source archives and installer metadata.

## 0.1.0 — 2026-10-15

- Independent Bash manager with Chinese/English SKYBYTE interfaces.
- Reality/Vision, XHTTP-Reality and verified domain XHTTP-TLS/CDN configuration.
- Official SHA256-verified core downloads; separate ownership, paths and service.
- Credential-preserving rename/certificate refresh; local URI, Base64, Xray JSON and QR exports.
- Service controls, configuration/core rollback, recovery journal, private backups and guarded uninstall.
- Standalone one-command installer with pinned payload SHA256 verification and guarded xr shortcut.
- Resolve hostname destinations before private-IP routing checks; authenticated regression coverage for private IP and hostname blocking.
- Installer integrity, ownership preservation, shortcut and uninstall regressions; source-only release packaging with checksums.
- Chinese/English deployment guidance and explicit XHTTP, H3 and client compatibility boundaries.
- Ubuntu 24.04, Debian 12 and Debian 13 CI with verified official core and authenticated proxy tests.
