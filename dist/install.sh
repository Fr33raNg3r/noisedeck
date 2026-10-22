#!/usr/bin/env bash
# WireGuard 一键安装 + 网页管理（Debian 13）
# 用法：sudo bash install.sh [install|uninstall]
set -euo pipefail

# 版本号由 build.sh 根据项目根目录的 VERSION 文件替换
SCRIPT_VERSION="1.3.0"

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
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
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
