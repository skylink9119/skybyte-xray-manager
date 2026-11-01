# lib/help.sh — build-time module; assembled by scripts/build.py.
guide(){
 say 'Copyright © 2026 SKYBYTE (skylink9119)。GPLv3，无担保；可按许可证修改和再分发。' 'Copyright © 2026 SKYBYTE (skylink9119). GPLv3, no warranty; modification and redistribution permitted under the license.'
 say '完整许可证：https://github.com/skylink9119/skybyte-xray-manager/blob/main/LICENSE' 'Full license: https://github.com/skylink9119/skybyte-xray-manager/blob/main/LICENSE'
 say 'Reality/Vision 和 XHTTP-Reality 使用不同 TCP 端口；XHTTP-TLS 需要已有可信域名证书。' 'Vision and XHTTP-Reality use separate TCP ports; XHTTP-TLS needs an existing trusted domain certificate.'
 say 'XHTTP-Reality 无需自己的域名和证书；默认不添加 Vision flow。先使用核心的 XMUX 默认值，不叠加 mux.cool；速度和抗干扰效果须实测。' 'XHTTP-Reality needs no personal domain/certificate and has no Vision flow. Start with core XMUX defaults, without mux.cool; measure performance on your route.'
 say '当前提供 Xray 直接终止 TLS 的入口；Nginx/Caddy、证书自动续期和 H3 选择尚未集成。H3 需要对端支持和 UDP 可达，不保证改善丢包线路。' 'TLS currently terminates in Xray. Nginx/Caddy, automatic renewal and H3 selection are not integrated. H3 needs peer support and reachable UDP; improvements are not guaranteed.'
 say 'CDN 模式需设置 DNS、可代理 HTTPS 端口及严格的回源证书验证；不替你配置 CDN。' 'For CDN, configure DNS, a supported HTTPS port and strict origin verification; CDN setup is manual.'
 say '客户端必须支持对应传输。节点文件是本地导出，不是在线订阅 URL。' 'Clients must support the transport. Exports are local files, not online subscription URLs.'
 say '证书为私密副本，外部续期后用“更新 TLS 证书”刷新；不自动签发或续期。' 'Certificates are private copies. After external renewal use Refresh TLS certificate; issuance/renewal is not automatic.'
 say '安装前检测：a → 4；检查不代表公网入站可达。短安装入口为 sky9119.cc/xr.sh。' 'Installation checks: a → 4; checks do not prove public inbound access. Short install entry: sky9119.cc/xr.sh.'
 say 'Reality 握手网站检测：主菜单 o，可检查当前节点或自定义目标，也可在检测通过后确认更换；检测通过不代表公网节点已连通。' 'Reality target checks: main menu o, check configured/custom targets or confirm a replacement after checks pass; checks do not prove public node connectivity.'
 say '安装后输入 xr 可重新打开菜单。' 'After installation, run xr to reopen the menu.'
}
