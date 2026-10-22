"""首次安装时生成 config.json、空的 clients.json 与初始 wg0.conf。

参数通过环境变量 WGC_* 传入，避免密码等内容经过 shell 引号处理。
"""
import ipaddress
import json
import os
import re
import secrets
import sys

from werkzeug.security import generate_password_hash

from . import core
from .store import Store

_IFACE_RE = re.compile(r"[A-Za-z0-9_.:-]{1,15}")
_USER_RE = re.compile(r"[A-Za-z0-9_.-]{1,32}")


def _port(env, key):
    value = env.get(key, "")
    if not (value.isascii() and value.isdigit() and 1 <= int(value) <= 65535):
        raise ValueError(f"{key} 必须是 1-65535 之间的端口号")
    return int(value)


def build(env, runner, existing=None, clients=None):
    """校验参数并生成 (config 字典, wg0.conf 文本)。

    existing 不为 None 时为“完全重装”：沿用原有的服务端密钥与网段，
    clients 为需要继续写入 wg0.conf 的原有客户端。
    """
    listen_host = str(ipaddress.IPv4Address(env.get("WGC_LISTEN_HOST", "")))
    listen_port = _port(env, "WGC_LISTEN_PORT")
    wg_port = _port(env, "WGC_WG_PORT")

    subnet_text = existing["subnet"] if existing else env.get("WGC_SUBNET", "")
    net = ipaddress.ip_network(subnet_text, strict=True)
    if net.version != 4 or net.prefixlen > 29:
        raise ValueError("VPN 网段必须是 IPv4，且前缀长度不超过 29")

    endpoint = core.validate_endpoint(env.get("WGC_ENDPOINT", ""))
    dns = core.validate_dns(env.get("WGC_DNS", ""))

    out_iface = env.get("WGC_OUT_IFACE", "")
    if not _IFACE_RE.fullmatch(out_iface):
        raise ValueError("出口网卡名称无效")

    admin_user = env.get("WGC_ADMIN_USER", "")
    if not _USER_RE.fullmatch(admin_user):
        raise ValueError("管理员用户名只能包含字母、数字、下划线、点和短横线")
    password = env.get("WGC_ADMIN_PASSWORD", "")
    if not password:
        raise ValueError("管理员密码不能为空")

    if existing:
        private = existing["server_private_key"]
        public = existing["server_public_key"]
    else:
        private = runner(["wg", "genkey"], None).strip()
        public = runner(["wg", "pubkey"], private).strip()
    config = {
        "listen_host": listen_host, "listen_port": listen_port,
        "endpoint": endpoint, "wg_port": wg_port, "subnet": str(net),
        "dns": dns, "out_iface": out_iface,
        "server_private_key": private, "server_public_key": public,
        "admin_user": admin_user,
        "admin_hash": generate_password_hash(password),
        "secret_key": secrets.token_hex(32),
    }
    conf = core.render_server_conf(
        private_key=private, address_cidr=f"{next(net.hosts())}/{net.prefixlen}",
        port=wg_port, out_iface=out_iface, clients=clients or [])
    return config, conf


def render_wg_conf(config_dir):
    """按现有 config.json 与 clients.json 重新渲染 wg0.conf（升级时刷新旧内容用）。"""
    with open(os.path.join(config_dir, "config.json"), encoding="utf-8") as f:
        config = json.load(f)
    with open(os.path.join(config_dir, "clients.json"), encoding="utf-8") as f:
        clients = json.load(f)
    net = ipaddress.ip_network(config["subnet"])
    return core.render_server_conf(
        private_key=config["server_private_key"],
        address_cidr=f"{next(net.hosts())}/{net.prefixlen}",
        port=config["wg_port"], out_iface=config["out_iface"], clients=clients)


def write(config_dir, wg_conf_path, env, runner, reuse=False):
    """首次安装；reuse=True 时为完全重装，保留服务端密钥、网段与 clients.json。"""
    existing = clients = None
    if reuse:
        cfg_path = os.path.join(config_dir, "config.json")
        if not os.path.exists(cfg_path):
            raise ValueError("找不到原有配置 config.json，无法沿用，请改用全新安装")
        with open(cfg_path, encoding="utf-8") as f:
            existing = json.load(f)
        clients_path = os.path.join(config_dir, "clients.json")
        clients = []
        if os.path.exists(clients_path):
            with open(clients_path, encoding="utf-8") as f:
                clients = json.load(f)
    config, conf = build(env, runner, existing, clients)
    Store._write_private(os.path.join(config_dir, "config.json"),
                         json.dumps(config, ensure_ascii=False, indent=2))
    if not reuse:
        Store._write_private(os.path.join(config_dir, "clients.json"), "[]")
    Store._write_private(wg_conf_path, conf)


def main():
    if "--render-wg-conf" in sys.argv:
        print(render_wg_conf("/etc/wg-web"), end="")
        return
    from .app import _real_runner
    try:
        write("/etc/wg-web", "/etc/wireguard/wg0.conf", os.environ, _real_runner,
              reuse=os.environ.get("WGC_REUSE") == "1")
    except ValueError as e:
        print(f"错误：{e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
