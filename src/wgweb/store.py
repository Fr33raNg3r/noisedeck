"""持久化客户端数据，并把变更同步到 WireGuard。"""
import ipaddress
import json
import os
import threading
import time

from . import core


class Store:
    def __init__(self, data_dir, wg_conf_path, config, runner):
        self._dir = data_dir
        self._conf_path = wg_conf_path
        self._config = config
        self._run = runner
        self._lock = threading.Lock()
        self._clients_path = os.path.join(data_dir, "clients.json")

    # ---- 读取 ----
    def list_clients(self):
        if not os.path.exists(self._clients_path):
            return []
        with open(self._clients_path, encoding="utf-8") as f:
            return json.load(f)

    def get_client(self, name):
        return next((c for c in self.list_clients() if c["name"] == name), None)

    # ---- 变更 ----
    def add_client(self, name):
        core.validate_name(name)
        with self._lock:
            clients = self.list_clients()
            if any(c["name"] == name for c in clients):
                raise ValueError("该名称已存在")
            ip = core.allocate_ip(self._config["subnet"],
                                  {c["ip"] for c in clients})
            private = self._run(["wg", "genkey"], None).strip()
            public = self._run(["wg", "pubkey"], private).strip()
            psk = self._run(["wg", "genpsk"], None).strip()
            client = {
                "name": name, "ip": ip, "private_key": private,
                "public_key": public, "psk": psk,
                "created": time.strftime("%Y-%m-%d %H:%M:%S"),
            }
            clients.append(client)
            self._apply(clients)
            return client

    def get_settings(self):
        return {"dns": self._config["dns"], "endpoint": self._config["endpoint"],
                "wg_port": self._config["wg_port"]}

    def update_client(self, name, *, new_name=None, dns=None, allowed_ips=None):
        """修改名称、单独 DNS、路由范围；传 None 表示不改，传空串表示清除单独设置。"""
        # 先校验全部输入，再改数据，失败时不留下半成品
        if new_name is not None:
            core.validate_name(new_name)
        if dns is not None:
            dns = core.validate_dns(dns, allow_empty=True)
        if allowed_ips is not None:
            allowed_ips = core.validate_allowed_ips(allowed_ips)
        with self._lock:
            clients = self.list_clients()
            target = next((c for c in clients if c["name"] == name), None)
            if target is None:
                raise KeyError(name)
            if (new_name is not None and new_name != name
                    and any(c["name"] == new_name for c in clients)):
                raise ValueError("该名称已存在")
            if new_name is not None:
                target["name"] = new_name
            if dns is not None:
                target["dns"] = dns
            if allowed_ips is not None:
                target["allowed_ips"] = allowed_ips
            self._apply(clients)
            return target

    def update_settings(self, *, dns, endpoint, wg_port=None):
        """修改全局默认 DNS、Endpoint 与 WireGuard 端口，并写回 config.json。

        wg_port 传 None 表示不改；端口变化时重写 wg0.conf 并热加载。
        """
        dns = core.validate_dns(dns)
        endpoint = core.validate_endpoint(endpoint)
        port = core.validate_port(wg_port) if wg_port is not None else None
        with self._lock:
            old_port = self._config["wg_port"]
            self._config["dns"] = dns
            self._config["endpoint"] = endpoint
            if port is not None and port != old_port:
                self._config["wg_port"] = port
                try:
                    self._apply(self.list_clients())
                except Exception:
                    # 重载失败时回退内存中的端口，避免与运行状态不一致
                    self._config["wg_port"] = old_port
                    raise
            self._write_private(
                os.path.join(self._dir, "config.json"),
                json.dumps(self._config, ensure_ascii=False, indent=2))

    def delete_client(self, name):
        with self._lock:
            clients = self.list_clients()
            remaining = [c for c in clients if c["name"] != name]
            if len(remaining) == len(clients):
                raise KeyError(name)
            self._apply(remaining)

    # ---- 内部 ----
    def _apply(self, clients):
        """先落盘，再重写 wg0.conf 并热加载，使配置文件与运行状态同源。"""
        self._write_private(self._clients_path,
                            json.dumps(clients, ensure_ascii=False, indent=2))
        net = ipaddress.ip_network(self._config["subnet"])
        server_addr = f"{next(net.hosts())}/{net.prefixlen}"
        conf = core.render_server_conf(
            private_key=self._config["server_private_key"],
            address_cidr=server_addr,
            port=self._config["wg_port"],
            out_iface=self._config["out_iface"],
            clients=clients,
        )
        self._write_private(self._conf_path, conf)
        self._run(["systemctl", "reload", "wg-quick@wg0"], None)

    @staticmethod
    def _write_private(path, text):
        """原子写入，文件权限 600。"""
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(text)
        os.replace(tmp, path)
