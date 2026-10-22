"""纯逻辑：名称校验、地址分配、配置渲染、握手解析。不做任何 IO。"""
import ipaddress
import re

_NAME_RE = re.compile(r"[A-Za-z0-9_一-鿿-]{1,32}")


class PoolExhausted(Exception):
    """网段内已没有可分配的客户端地址。"""


def validate_name(name: str) -> str:
    # 使用 fullmatch，避免 "$" 匹配末尾换行
    if not isinstance(name, str) or not _NAME_RE.fullmatch(name):
        raise ValueError("名称只能包含汉字、字母、数字、下划线和短横线，长度 1-32")
    return name


def allocate_ip(subnet: str, used: set) -> str:
    """返回最小的空闲主机地址；第一个主机地址留给服务端。"""
    hosts = list(ipaddress.ip_network(subnet).hosts())
    for host in hosts[1:]:
        ip = str(host)
        if ip not in used:
            return ip
    raise PoolExhausted("地址池已用尽，无法再添加客户端")


_ENDPOINT_RE = re.compile(r"[A-Za-z0-9.-]{1,253}")
MAX_ROUTES = 20  # 单个客户端最多可设置的路由网段数


def validate_endpoint(text: str) -> str:
    text = text.strip()
    if not _ENDPOINT_RE.fullmatch(text):
        raise ValueError("Endpoint 只能是公网 IP 或域名")
    return text


def validate_port(text) -> int:
    """校验端口号（1024-65535，避开系统保留端口；仅十进制 ASCII 数字），返回整数。"""
    text = str(text).strip()
    if not (text.isascii() and text.isdigit()) or not 1024 <= int(text) <= 65535:
        raise ValueError("端口必须是 1024-65535 的整数（1024 以下为系统保留端口）")
    return int(text)


def validate_dns(text: str, allow_empty: bool = False) -> str:
    """校验并规范化 DNS 列表（仅 IPv4，英文逗号分隔），输出形如 "a, b"。"""
    text = text.strip()
    if not text:
        if allow_empty:
            return ""
        raise ValueError("DNS 不能为空")
    try:
        return ", ".join(str(ipaddress.IPv4Address(p.strip())) for p in text.split(","))
    except ValueError:
        raise ValueError("DNS 必须是 IPv4 地址，多个用英文逗号分隔") from None


def validate_allowed_ips(text: str) -> str:
    """校验并规范化路由范围；空串表示全局代理（0.0.0.0/0）。"""
    text = text.strip()
    if not text:
        return ""
    parts = [p.strip() for p in text.split(",")]
    try:
        nets = [str(ipaddress.IPv4Network(p, strict=False)) for p in parts]
    except ValueError:
        raise ValueError("路由范围必须是 IPv4 网段，如 10.8.0.0/24，多个用英文逗号分隔") from None
    if len(nets) > MAX_ROUTES:
        raise ValueError(f"路由范围最多填写 {MAX_ROUTES} 个网段")
    return ", ".join(nets)


def render_client_conf(*, private_key, address, dns, server_public_key,
                       psk, endpoint, port, allowed_ips="0.0.0.0/0") -> str:
    return (
        "[Interface]\n"
        f"PrivateKey = {private_key}\n"
        f"Address = {address}/32\n"
        f"DNS = {dns}\n"
        "\n"
        "[Peer]\n"
        f"PublicKey = {server_public_key}\n"
        f"PresharedKey = {psk}\n"
        f"Endpoint = {endpoint}:{port}\n"
        f"AllowedIPs = {allowed_ips}\n"
        "PersistentKeepalive = 25\n"
    )


def render_server_conf(*, private_key, address_cidr, port, out_iface,
                       clients) -> str:
    lines = [
        "[Interface]",
        f"PrivateKey = {private_key}",
        f"Address = {address_cidr}",
        f"ListenPort = {port}",
        # 转发与 NAT 规则放在固定名称的表里，卸载时整表删除
        "PostUp = nft add table inet wg_web",
        "PostUp = nft 'add chain inet wg_web forward "
        "{ type filter hook forward priority 0 ; policy accept ; }'",
        "PostUp = nft add rule inet wg_web forward iifname wg0 accept",
        "PostUp = nft add rule inet wg_web forward oifname wg0 accept",
        "PostUp = nft 'add chain inet wg_web postrouting "
        "{ type nat hook postrouting priority 100 ; }'",
        f"PostUp = nft add rule inet wg_web postrouting oifname {out_iface} masquerade",
        "PostDown = nft delete table inet wg_web || true",
    ]
    for c in clients:
        lines += [
            "",
            f"# {c['name']}",
            "[Peer]",
            f"PublicKey = {c['public_key']}",
            f"PresharedKey = {c['psk']}",
            f"AllowedIPs = {c['ip']}/32",
        ]
    return "\n".join(lines) + "\n"


def parse_handshakes(output: str) -> dict:
    """解析 `wg show wg0 latest-handshakes` 的输出：公钥<TAB>时间戳。"""
    result = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1].isdigit():
            result[parts[0]] = int(parts[1])
    return result


def parse_transfers(output: str) -> dict:
    """解析 `wg show wg0 transfer`：公钥<TAB>接收字节<TAB>发送字节。

    接收 = 客户端上传，发送 = 客户端下载。格式不对的行被忽略。
    """
    result = {}
    for line in output.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[1].isdigit() and parts[2].isdigit():
            result[parts[0]] = (int(parts[1]), int(parts[2]))
    return result


def is_online(ts: int, now: int, window: int = 180) -> bool:
    return ts != 0 and 0 <= now - ts <= window


def format_ago(ts: int, now: int) -> str:
    if ts == 0:
        return "从未连接"
    delta = max(0, now - ts)  # 时钟偏差时按 0 秒处理
    if delta < 60:
        return f"{delta} 秒前"
    if delta < 3600:
        return f"{delta // 60} 分钟前"
    if delta < 86400:
        return f"{delta // 3600} 小时前"
    return f"{delta // 86400} 天前"
