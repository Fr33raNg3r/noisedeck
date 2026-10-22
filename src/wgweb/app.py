"""Flask 应用：登录、客户端管理、二维码与在线状态接口。"""
import functools
import hmac
import json
import os
import secrets
import subprocess
import time

from flask import (Flask, Response, jsonify, redirect, request, session)
from werkzeug.security import check_password_hash

from . import core, ui
from .store import Store

# 登录失败后的延迟秒数，用于减缓暴力破解；测试中会置 0
LOGIN_FAIL_DELAY = 1

CONFIG_PATH = "/etc/wg-web/config.json"
DATA_DIR = "/etc/wg-web"
WG_CONF_PATH = "/etc/wireguard/wg0.conf"


def read_version(path=None):
    """读取随程序打包的 VERSION 文件；开发环境下没有该文件，返回空串。"""
    path = path or os.path.join(os.path.dirname(__file__), "VERSION")
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return ""


def make_qr_svg(text, runner):
    return runner(["qrencode", "-t", "SVG", "-o", "-"], text)


def get_status(store, runner, now):
    """返回 {客户端名: {online, ago}}；wg 命令失败时全部视为离线。"""
    try:
        output = runner(["wg", "show", "wg0", "latest-handshakes"], None)
    except Exception:
        output = ""
    handshakes = core.parse_handshakes(output)
    try:
        transfers = core.parse_transfers(
            runner(["wg", "show", "wg0", "transfer"], None))
    except Exception:
        transfers = {}
    status = {}
    for c in store.list_clients():
        ts = handshakes.get(c["public_key"], 0)
        rx, tx = transfers.get(c["public_key"], (0, 0))
        status[c["name"]] = {
            "online": core.is_online(ts, now),
            "ago": core.format_ago(ts, now),
            "rx": rx,  # 客户端上传的累计字节数
            "tx": tx,  # 客户端下载的累计字节数
        }
    return status


def create_app(store, config, runner, version=None):
    version = read_version() if version is None else version
    app = Flask(__name__)
    app.secret_key = config["secret_key"]
    app.config.update(SESSION_COOKIE_SAMESITE="Lax", SESSION_COOKIE_HTTPONLY=True)

    @app.after_request
    def no_cache(resp):
        # 响应里可能含私钥，禁止缓存
        resp.headers["Cache-Control"] = "no-store"
        return resp

    def login_required(view):
        @functools.wraps(view)
        def wrapper(*args, **kwargs):
            if not session.get("user"):
                if request.path.startswith("/api/"):
                    return jsonify(error="未登录"), 401
                return redirect("/login")
            return view(*args, **kwargs)
        return wrapper

    def csrf_ok():
        token = request.form.get("csrf") or request.headers.get("X-CSRF-Token") or ""
        expected = session.get("csrf") or ""
        # compare_digest 对非 ASCII 的 str 会抛 TypeError，先编码为字节
        return bool(expected) and hmac.compare_digest(token.encode(), expected.encode())

    def render_home(flash=None, status=200):
        now = int(time.time())
        states = get_status(store, runner, now)
        clients = [dict(c, **states.get(c["name"], {"online": False, "ago": "从未连接"}))
                   for c in store.list_clients()]
        # 成功提示在重定向后显示一次
        notice = session.pop("notice", None)
        html = ui.render_index(clients, session["csrf"], session["user"], flash,
                               version=version, settings=store.get_settings(),
                               notice=notice)
        return Response(html, status=status, mimetype="text/html")

    @app.route("/login", methods=["GET", "POST"])
    def login():
        if request.method == "GET":
            return ui.render_login(None, "")
        user = request.form.get("username", "")
        password = request.form.get("password", "")
        user_ok = hmac.compare_digest(user.encode(), config["admin_user"].encode())
        pass_ok = check_password_hash(config["admin_hash"], password)
        if user_ok and pass_ok:
            session.clear()
            session["user"] = user
            session["csrf"] = secrets.token_hex(16)
            return redirect("/")
        time.sleep(LOGIN_FAIL_DELAY)
        return ui.render_login("用户名或密码错误", "")

    @app.route("/logout", methods=["POST"])
    @login_required
    def logout():
        if not csrf_ok():
            return "请求无效", 400
        session.clear()
        return redirect("/login")

    @app.route("/")
    @login_required
    def index():
        return render_home()

    @app.route("/clients", methods=["POST"])
    @login_required
    def add_client():
        if not csrf_ok():
            return render_home("请求无效，请刷新页面重试", 400)
        try:
            store.add_client(request.form.get("name", "").strip())
        except core.PoolExhausted as e:
            return render_home(str(e), 400)
        except ValueError as e:
            return render_home(str(e), 400)
        return redirect("/")

    @app.route("/clients/<name>")
    @login_required
    def client_detail(name):
        client = store.get_client(name)
        if client is None:
            return jsonify(error="客户端不存在"), 404
        conf = _client_conf(client)
        return jsonify(conf=conf, qr_svg=make_qr_svg(conf, runner))

    @app.route("/clients/<name>/download")
    @login_required
    def client_download(name):
        client = store.get_client(name)
        if client is None:
            return jsonify(error="客户端不存在"), 404
        # 文件名决定客户端里的隧道名，Windows / Linux 只接受 ASCII，
        # 因此统一用内网 IP 生成，不使用（可能是中文的）客户端名称
        filename = f"wg-{client['ip']}.conf"
        return Response(
            _client_conf(client), mimetype="text/plain",
            headers={"Content-Disposition": f'attachment; filename="{filename}"'})

    @app.route("/clients/<name>/edit", methods=["POST"])
    @login_required
    def client_edit(name):
        if not csrf_ok():
            return render_home("请求无效，请刷新页面重试", 400)
        old = store.get_client(name)
        if old is None:
            return jsonify(error="客户端不存在"), 404
        new_name = request.form.get("name", "").strip()
        dns = request.form.get("dns", "")
        routes = request.form.get("allowed_ips", "")
        try:
            updated = store.update_client(name, new_name=new_name, dns=dns,
                                          allowed_ips=routes)
        except KeyError:
            return jsonify(error="客户端不存在"), 404
        except ValueError as e:
            return render_home(str(e), 400)
        # 名称只是服务端标签；DNS / 路由写在设备上，改了要让设备重新导入配置
        changed = (updated.get("dns", "") != old.get("dns", "")
                   or updated.get("allowed_ips", "") != old.get("allowed_ips", ""))
        session["notice"] = ("已保存。DNS / 路由范围的修改需要让该设备重新导入配置才会生效"
                             if changed else "已保存")
        return redirect("/")

    @app.route("/settings", methods=["POST"])
    @login_required
    def settings():
        if not csrf_ok():
            return render_home("请求无效，请刷新页面重试", 400)
        try:
            old_port = store.get_settings()["wg_port"]
            store.update_settings(dns=request.form.get("dns", ""),
                                  endpoint=request.form.get("endpoint", ""),
                                  wg_port=request.form.get("wg_port"))
        except ValueError as e:
            return render_home(str(e), 400)
        note = ("全局设置已保存。新增客户端和未单独设置 DNS 的客户端会使用新值；"
                "已有设备需重新导入配置才会生效")
        if store.get_settings()["wg_port"] != old_port:
            note += "。WireGuard 端口已更改，请确认防火墙已放行新的 UDP 端口"
        session["notice"] = note
        return redirect("/")

    @app.route("/clients/<name>/delete", methods=["POST"])
    @login_required
    def client_delete(name):
        if not csrf_ok():
            return render_home("请求无效，请刷新页面重试", 400)
        try:
            store.delete_client(name)
        except KeyError:
            return jsonify(error="客户端不存在"), 404
        return redirect("/")

    @app.route("/api/status")
    @login_required
    def api_status():
        return jsonify(get_status(store, runner, int(time.time())))

    def _client_conf(client):
        # 单独设置优先，留空则使用全局默认 / 全局代理
        return core.render_client_conf(
            private_key=client["private_key"], address=client["ip"],
            dns=client.get("dns") or config["dns"],
            server_public_key=config["server_public_key"],
            psk=client["psk"], endpoint=config["endpoint"], port=config["wg_port"],
            allowed_ips=client.get("allowed_ips") or "0.0.0.0/0")

    return app


def _real_runner(args, stdin=None):
    return subprocess.run(args, input=stdin, capture_output=True,
                          text=True, check=True).stdout


def main():
    with open(CONFIG_PATH, encoding="utf-8") as f:
        config = json.load(f)
    store = Store(DATA_DIR, WG_CONF_PATH, config, _real_runner)
    app = create_app(store, config, _real_runner)
    app.run(host=config["listen_host"], port=config["listen_port"], threaded=True)


if __name__ == "__main__":
    main()
