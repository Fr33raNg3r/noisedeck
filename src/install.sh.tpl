#!/usr/bin/env bash
# WireGuard 一键安装 + 网页管理（Debian 13）
# 用法：sudo bash install.sh [install|uninstall]
set -euo pipefail

# 版本号由 build.sh 根据项目根目录的 VERSION 文件替换
SCRIPT_VERSION="@@VERSION@@"

TUNA_DEBIAN="https://mirrors.tuna.tsinghua.edu.cn/debian"
TUNA_SECURITY="https://mirrors.tuna.tsinghua.edu.cn/debian-security"
CONF_DIR="/etc/wg-web"
APP_DIR="/opt/wg-web"
BACKUP_DIR="${CONF_DIR}/backup"
WG_CONF="/etc/wireguard/wg0.conf"
SERVICE_FILE="/etc/systemd/system/wg-web.service"
SYSCTL_IPV6="/etc/sysctl.d/99-wg-web-disable-ipv6.conf"
SYSCTL_FWD="/etc/sysctl.d/99-wg-web-forward.conf"
PY="${PYTHON:-python3}"
REUSE=0  # 1 表示“完全重装”：沿用原有的 WireGuard 密钥、网段和客户端

log() { echo "[$(date +%H:%M:%S)] $*"; }
die() { echo "错误：$*" >&2; exit 1; }

usage() {
  echo "用法：sudo bash $0 [install|uninstall]"
  echo "  install    安装 WireGuard 与网页管理（默认）"
  echo "  uninstall  卸载并还原系统设置"
  echo "  --version  显示脚本版本号"
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "请使用 root 权限运行（例如：sudo bash $0）"
}

# ---------------------------------------------------------------- 内嵌程序包
unpack_payload() {
  mkdir -p "$1"
  base64 -d <<'WGWEB_PAYLOAD_END' | tar xz -C "$1"
@@PAYLOAD@@
WGWEB_PAYLOAD_END
}

# ---------------------------------------------------------------- 环境检查
check_env() {
  require_root
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${ID:-}" == "debian" && "${VERSION_ID:-}" == "13" ]] \
    || die "仅支持 Debian 13，当前系统：${PRETTY_NAME:-未知}"
  local virt
  virt="$(systemd-detect-virt --container 2>/dev/null || true)"
  case "$virt" in
    lxc|lxc-libvirt|openvz|docker|podman|systemd-nspawn)
      die "检测到容器环境（$virt），WireGuard 内核功能不可用，请在普通主机上安装" ;;
  esac
}

# ---------------------------------------------------------------- 交互输入
ask() {
  # 用法：ask 变量名 提示 [默认值]
  local __var="$1" __prompt="$2" __def="${3:-}" __ans=""
  if [[ -n "$__def" ]]; then
    read -r -p "$__prompt [$__def]: " __ans || die "未获得输入"
    __ans="${__ans:-$__def}"
  else
    read -r -p "$__prompt: " __ans || die "未获得输入"
  fi
  printf -v "$__var" '%s' "$__ans"
}

ask_valid() {
  # 用法：ask_valid 变量名 提示 默认值 正则 错误说明
  local __var="$1" __prompt="$2" __def="$3" __re="$4" __msg="$5" __val=""
  while true; do
    ask __val "$__prompt" "$__def"
    if [[ "$__val" =~ $__re ]]; then
      printf -v "$__var" '%s' "$__val"
      return 0
    fi
    echo "输入无效：$__msg"
  done
}

PORT_RE='^([1-9][0-9]{0,3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$'
# WireGuard 端口：1024-65535，避开系统保留端口
WG_PORT_RE='^(102[4-9]|10[3-9][0-9]|1[1-9][0-9]{2}|[2-9][0-9]{3}|[1-5][0-9]{4}|6[0-4][0-9]{3}|65[0-4][0-9]{2}|655[0-2][0-9]|6553[0-5])$'
IPV4_RE='^([0-9]{1,3}\.){3}[0-9]{1,3}$'

# 点分 IPv4 转整数
ip2int() {
  local a b c d
  IFS=. read -r a b c d <<<"$1"
  echo $(( (a << 24) | (b << 16) | (c << 8) | d ))
}

# 随机选一个不与已有路由重叠的 10.X.Y.0/24，参数为 `ip -4 route` 的输出
# 多次尝试仍失败时返回 1，由调用方回退到默认网段
pick_free_subnet() {
  local routes="$1" try x y cand line net len ni shift_n
  for try in $(seq 1 100); do
    x=$(( RANDOM % 254 + 1 )); y=$(( RANDOM % 255 ))
    # 避开 10.0.x、10.8.0 等常见网段
    [[ $x -eq 1 || ( $x -eq 8 && $y -eq 0 ) ]] && continue
    cand="$(ip2int "10.$x.$y.0")"
    local clash=0
    while read -r line; do
      net="${line%% *}"
      [[ "$net" =~ ^[0-9.]+/[0-9]+$ ]] || continue
      len="${net#*/}"; ni="$(ip2int "${net%/*}")"
      [[ "$len" -eq 0 ]] && continue
      # 取两者中较短的前缀比较，相同即重叠
      shift_n=$(( 32 - (len < 24 ? len : 24) ))
      if (( (cand >> shift_n) == (ni >> shift_n) )); then clash=1; break; fi
    done <<<"$routes"
    # 尽力探测同一网络里其他机器是否已在用该网段：.1 有回应就换一个
    if [[ $clash -eq 0 && "${PROBE_PING:-0}" == 1 ]] && command -v ping >/dev/null 2>&1        && ping -c 1 -W 1 "10.$x.$y.1" >/dev/null 2>&1; then
      clash=1
    fi
    if [[ $clash -eq 0 ]]; then echo "10.$x.$y.0/24"; return 0; fi
  done
  return 1
}

ask_params() {
  local route lan_ip="" iface="" pub=""
  route="$(ip -4 route get 1.1.1.1 2>/dev/null || true)"
  lan_ip="$(awk '{for(i=1;i<NF;i++) if($i=="src") print $(i+1)}' <<<"$route")"
  iface="$(awk '{for(i=1;i<NF;i++) if($i=="dev") print $(i+1)}' <<<"$route")"
  if command -v curl >/dev/null 2>&1; then
    pub="$(curl -fsS -m 5 https://api.ipify.org 2>/dev/null || true)"
  fi

  ask_valid WG_PORT "WireGuard 监听端口(UDP，1024-65535)" "51820" "$WG_PORT_RE" "请输入 1024-65535 的端口号（1024 以下为系统保留端口）"
  ask_valid ENDPOINT "客户端连接地址（公网 IP 或域名）" "$pub" '^[A-Za-z0-9.-]{1,253}$' "只能是公网 IP 或域名，且不能为空"
  if [[ "$REUSE" -eq 1 ]]; then
    SUBNET="$(existing_subnet)"
    log "沿用原有 VPN 网段 ${SUBNET}"
  else
    local rand_net
    rand_net="$(PROBE_PING=1 pick_free_subnet "$(ip -4 route show 2>/dev/null; ip -4 -o addr show 2>/dev/null | awk '{print $4}')")" || rand_net=""
    if [[ -z "$rand_net" ]]; then rand_net="10.8.0.0/24"; fi
    ask_valid SUBNET "VPN 网段（已随机生成，避开本机已有网段并探测过局域网，回车接受或手填）" "$rand_net" '^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9])$' "格式如 10.8.0.0/24"
  fi
  ask_valid DNS "客户端 DNS（可填多个，用英文逗号分隔，如 192.168.1.1, 223.5.5.5）" "223.5.5.5, 119.29.29.29, 114.114.114.114" '^[0-9.]+(, *[0-9.]+)*$' "格式如 192.168.1.1 或 192.168.1.1, 223.5.5.5（多个用英文逗号分隔）"
  ask_valid OUT_IFACE "出口网卡" "$iface" '^[A-Za-z0-9_.:-]{1,15}$' "请输入网卡名，如 eth0"
  ask_valid LISTEN_HOST "网页监听的内网 IP" "$lan_ip" "$IPV4_RE" "请输入内网 IPv4 地址"
  ask_valid LISTEN_PORT "网页端口" "8080" "$PORT_RE" "请输入 1-65535 的端口号"
  ask_valid ADMIN_USER "网页管理员用户名" "admin" '^[A-Za-z0-9_.-]{1,32}$' "只能包含字母、数字、下划线、点和短横线"

  local p1 p2
  while true; do
    read -r -s -p "网页管理员密码: " p1 || die "未获得输入"; echo
    read -r -s -p "再输入一次: " p2 || die "未获得输入"; echo
    [[ -n "$p1" && "$p1" == "$p2" ]] && break
    echo "两次输入不一致或为空，请重试"
  done
  ADMIN_PASSWORD="$p1"
}

# ---------------------------------------------------------------- 软件源
rewrite_apt_sources() {
  # 同时支持 deb822 格式（URIs: ...）与旧式 sources.list；可重复执行
  sed -E -i \
    -e "s#https?://(deb|security|ftp\.[a-z]+)\.debian\.org/debian-security/?#${TUNA_SECURITY}#g" \
    -e "s#https?://(deb|ftp\.[a-z]+)\.debian\.org/debian/?#${TUNA_DEBIAN}#g" \
    "$1"
}

restore_apt_sources() {
  local b
  b="${BACKUP_DIR}/debian.sources.orig"
  if [[ -f "$b" ]]; then cp -f "$b" /etc/apt/sources.list.d/debian.sources; fi
  b="${BACKUP_DIR}/sources.list.orig"
  if [[ -f "$b" ]]; then cp -f "$b" /etc/apt/sources.list; fi
  return 0
}

# 只在目标不存在时备份，避免重复运行时覆盖原始文件。
# 不用 cp -n：不同版本的 coreutils 对“跳过已存在文件”的退出状态不一致，会被 set -e 误判为失败
backup_once() {
  if [[ ! -e "$2" ]]; then cp -p "$1" "$2"; fi
  return 0
}

switch_mirror() {
  log "备份并切换 APT 软件源到清华 TUNA"
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$CONF_DIR"
  local f
  for f in /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list; do
    [[ -f "$f" ]] || continue
    # 只在首次备份，避免重复运行时覆盖掉原始文件
    backup_once "$f" "${BACKUP_DIR}/$(basename "$f").orig"
    rewrite_apt_sources "$f"
  done
  if ! apt-get update; then
    restore_apt_sources
    die "使用 TUNA 源 apt-get update 失败，已还原原有软件源"
  fi
}

full_upgrade() {
  log "更新所有软件包（可能需要几分钟）"
  export DEBIAN_FRONTEND=noninteractive
  apt-get -y -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef full-upgrade
}

install_packages() {
  log "安装 wireguard、qrencode、python3-flask、nftables、curl"
  export DEBIAN_FRONTEND=noninteractive
  apt-get -y install wireguard qrencode python3-flask nftables curl
  # 标为手动安装，避免之后卸载内核等操作触发 autoremove 把它们当依赖清掉
  apt-mark manual wireguard wireguard-tools qrencode python3-flask nftables curl >/dev/null
}

# ---------------------------------------------------------------- 系统设置
disable_ipv6() {
  log "禁用 IPv6"
  cat > "$SYSCTL_IPV6" <<'EOF'
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
  sysctl --system >/dev/null
}

enable_forwarding() {
  log "开启 IPv4 转发"
  echo "net.ipv4.ip_forward = 1" > "$SYSCTL_FWD"
  sysctl --system >/dev/null
}

# ---------------------------------------------------------------- 版本与升级
# 比较两个 x.y.z 版本号，输出 -1（前者旧）、0（相同）、1（前者新）
version_cmp() {
  if [[ "$1" == "$2" ]]; then echo 0; return 0; fi
  if [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" ]]; then
    echo -1
  else
    echo 1
  fi
}

installed_version() {
  if [[ -f "${CONF_DIR}/version" ]]; then cat "${CONF_DIR}/version"; else echo "0.0.0"; fi
}

record_version() {
  echo "$SCRIPT_VERSION" > "${CONF_DIR}/version"
}

# 只保留最近 3 份升级备份（目录名里的时间戳可按字典序排序），不动其他备份
prune_upgrade_backups() {
  local d
  while IFS= read -r d; do
    rm -rf -- "$d"
  done < <(ls -1d "${BACKUP_DIR}"/upgrade-* 2>/dev/null | sort -r | tail -n +4)
  return 0
}

# 升级前备份用户数据，出问题时可手动还原
backup_data() {
  local dest f
  dest="${BACKUP_DIR}/upgrade-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$dest"
  chmod 700 "$dest"
  for f in "${CONF_DIR}/config.json" "${CONF_DIR}/clients.json" "$WG_CONF"; do
    if [[ -f "$f" ]]; then cp -p "$f" "$dest/"; fi
  done
  log "已备份旧数据到 ${dest}"
  prune_upgrade_backups
}

# 清掉旧版本留下的程序文件与临时文件；用户数据和备份不动
clean_old_files() {
  # 程序目录只属于本脚本，整体清空后重新解包，避免旧版本残留
  if [[ -n "$APP_DIR" && "$APP_DIR" != "/" ]]; then rm -rf -- "$APP_DIR"; fi
  # 原子写入中断时可能残留的临时文件
  find "$CONF_DIR" -maxdepth 1 -name '*.tmp' -delete 2>/dev/null || true
  find "$(dirname "$WG_CONF")" -maxdepth 1 -name 'wg0.conf.tmp' -delete 2>/dev/null || true
  return 0
}

# 用现有数据按新版本模板重新生成 wg0.conf；有变化才更新并重启 WireGuard
refresh_wg_conf() {
  local new
  new="$(mktemp)"
  if ! (cd "$APP_DIR" && "$PY" -m wgweb.initcfg --render-wg-conf) > "$new"; then
    rm -f "$new"
    die "无法根据现有配置生成 wg0.conf"
  fi
  if ! cmp -s "$new" "$WG_CONF"; then
    log "wg0.conf 与新版本不一致，已更新并重启 WireGuard（连接会短暂中断）"
    install -m 600 "$new" "$WG_CONF"
    systemctl restart wg-quick@wg0
  fi
  rm -f "$new"
}

# 已有安装时给用户的选择说明
print_existing_install_menu() {
  local old="$1" label
  if [[ "$old" == "0.0.0" ]]; then label="旧版本（未记录版本号）"; else label="v${old}"; fi
  echo "检测到已安装 ${label}，本脚本版本为 v${SCRIPT_VERSION}。"
  echo "  1（默认）更新：更新程序，保留所有客户端和配置"
  echo "  2 完全重装：保留 WireGuard 配置（密钥和客户端），其余全部清除并重新配置（会先备份旧数据）"
}

# 完全重装前的清理：删除程序、服务和系统设置；
# 保留 wg0.conf、config.json、clients.json 和 backup 目录（里面有原始 APT 源备份）
wipe_for_reinstall() {
  systemctl stop wg-web wg-quick@wg0 2>/dev/null || true
  systemctl disable wg-web 2>/dev/null || true
  nft delete table inet wg_web 2>/dev/null || true
  rm -f -- "$SERVICE_FILE" "$SYSCTL_IPV6" "$SYSCTL_FWD" "${CONF_DIR}/version"
  if [[ -n "$APP_DIR" && "$APP_DIR" != "/" ]]; then rm -rf -- "$APP_DIR"; fi
  systemctl daemon-reload 2>/dev/null || true
  sysctl --system >/dev/null 2>&1 || true
  return 0
}

# 完全重装时沿用原有的 VPN 网段（改网段会让已有客户端的 IP 失效）
existing_subnet() {
  "$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["subnet"])' "${CONF_DIR}/config.json"
}

# ---------------------------------------------------------------- 部署
deploy_app() {
  log "部署网页程序到 ${APP_DIR}（覆盖旧版本）"
  systemctl stop wg-web 2>/dev/null || true
  clean_old_files
  mkdir -p "$APP_DIR"
  unpack_payload "$APP_DIR"
}

init_config() {
  log "生成服务端密钥与配置"
  mkdir -p "$CONF_DIR" /etc/wireguard
  chmod 700 "$CONF_DIR" /etc/wireguard
  (
    cd "$APP_DIR"
    umask 077
    WGC_LISTEN_HOST="$LISTEN_HOST" WGC_LISTEN_PORT="$LISTEN_PORT" \
    WGC_ENDPOINT="$ENDPOINT" WGC_WG_PORT="$WG_PORT" WGC_SUBNET="$SUBNET" \
    WGC_DNS="$DNS" WGC_OUT_IFACE="$OUT_IFACE" WGC_ADMIN_USER="$ADMIN_USER" \
    WGC_ADMIN_PASSWORD="$ADMIN_PASSWORD" WGC_REUSE="$REUSE" "$PY" -m wgweb.initcfg
  )
}

enable_wireguard() {
  log "启动 WireGuard"
  systemctl enable --now wg-quick@wg0
}

install_service() {
  log "安装并启动网页管理服务"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=WireGuard 网页管理
After=network-online.target wg-quick@wg0.service
Wants=network-online.target

[Service]
WorkingDirectory=${APP_DIR}
Environment=PYTHONDONTWRITEBYTECODE=1
ExecStart=/usr/bin/python3 -m wgweb.app
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable wg-web
  systemctl restart wg-web
}

print_summary() {
  local info host port wgport
  info="$("$PY" -c 'import json;c=json.load(open("/etc/wg-web/config.json"));print(c["listen_host"],c["listen_port"],c["wg_port"])')"
  read -r host port wgport <<<"$info"
  echo
  echo "=============================================="
  echo " 安装完成（NoiseDeck v${SCRIPT_VERSION}）"
  echo " 网页管理地址：http://${host}:${port}"
  echo " 请在路由器上把 UDP ${wgport} 端口转发到本机"
  echo "=============================================="
  # 内核更新后建议重启
  local newest
  newest="$(ls /lib/modules 2>/dev/null | sort -V | tail -1)"
  if [[ -n "$newest" && "$newest" != "$(uname -r)" ]]; then
    echo " 提示：系统内核已更新，建议择机重启（脚本不会自动重启）"
  fi
}

install_main() {
  check_env
  log "NoiseDeck 安装脚本 v${SCRIPT_VERSION}"
  local keep=0 ans="" confirm="" old=""
  if [[ -f "${CONF_DIR}/config.json" ]]; then
    old="$(installed_version)"
    print_existing_install_menu "$old"
    read -r -p "请选择 [1/2]，直接回车为 1: " ans || ans="1"
    case "${ans:-1}" in
      1|2) ;;
      *) die "无效的选择：${ans}，已退出" ;;
    esac
    if [[ "${ans:-1}" == "2" ]]; then
      read -r -p "完全重装会清除程序、账号和各项参数并重新配置（WireGuard 配置与客户端保留，旧数据会先备份），请输入 yes 确认: " confirm || confirm=""
      [[ "$confirm" == "yes" ]] || die "已取消"
      backup_data
      wipe_for_reinstall
      REUSE=1
    else
      keep=1
      case "$(version_cmp "$old" "$SCRIPT_VERSION")" in
        -1) log "升级：v${old} → v${SCRIPT_VERSION}（旧版本若为 v0.0.0，表示当时未记录版本号）" ;;
        0)  log "已安装版本与脚本版本相同（v${old}），将重新部署程序" ;;
        1)
          read -r -p "已安装版本 v${old} 高于本脚本 v${SCRIPT_VERSION}，继续将降级。请输入 yes 确认: " confirm || confirm=""
          [[ "$confirm" == "yes" ]] || die "已取消"
          ;;
      esac
      backup_data
    fi
  fi
  if [[ $keep -eq 0 ]]; then ask_params; fi

  switch_mirror
  full_upgrade
  install_packages
  disable_ipv6
  enable_forwarding
  deploy_app
  if [[ $keep -eq 0 ]]; then init_config; else refresh_wg_conf; fi
  enable_wireguard
  install_service
  record_version
  print_summary
}

# ---------------------------------------------------------------- 卸载
confirm_yes() {
  local ans=""
  read -r -p "$1 输入 yes 确认: " ans || return 1
  [[ "$ans" == "yes" ]]
}

uninstall_main() {
  require_root
  echo "即将卸载 WireGuard 网页管理，分 4 步，每步都需要确认。"

  echo
  echo "【步骤 1】停止服务并删除程序："
  echo "  服务 wg-web、wg-quick@wg0；文件 ${SERVICE_FILE}、${APP_DIR}"
  if confirm_yes "是否执行？"; then
    systemctl disable --now wg-web 2>/dev/null || true
    systemctl disable --now wg-quick@wg0 2>/dev/null || true
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload || true
    nft delete table inet wg_web 2>/dev/null || true
    rm -rf "$APP_DIR"
  else
    echo "已跳过步骤 1"
  fi

  echo
  echo "【步骤 2】还原 APT 软件源与 IPv6 设置："
  echo "  从 ${BACKUP_DIR} 还原 APT 源；删除 ${SYSCTL_IPV6}"
  if confirm_yes "是否执行？"; then
    restore_apt_sources
    rm -f "$SYSCTL_IPV6"
    sysctl --system >/dev/null || true
  else
    echo "已跳过步骤 2"
  fi

  echo
  echo "【步骤 3】删除配置与数据（含全部客户端、密钥和第 2 步用到的备份）："
  echo "  ${CONF_DIR}、${WG_CONF}、${SYSCTL_FWD}"
  if confirm_yes "是否执行？"; then
    rm -rf "$CONF_DIR"
    rm -f "$WG_CONF" "$SYSCTL_FWD"
    sysctl --system >/dev/null || true
  else
    echo "已跳过步骤 3"
  fi

  echo
  echo "【步骤 4】卸载软件包（默认不删除）："
  echo "  wireguard qrencode python3-flask nftables"
  if confirm_yes "是否执行 apt purge？"; then
    DEBIAN_FRONTEND=noninteractive apt-get -y purge wireguard qrencode python3-flask nftables || true
  else
    echo "已跳过步骤 4"
  fi
  echo "卸载流程结束"
}

main() {
  case "${1:-install}" in
    install) install_main ;;
    uninstall) uninstall_main ;;
    -v|--version) echo "NoiseDeck ${SCRIPT_VERSION}" ;;
    -h|--help) usage ;;
    *) usage; exit 1 ;;
  esac
}

# 被 source 时（如测试）不执行主流程
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
