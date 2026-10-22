#!/usr/bin/env bash
# 把 src/wgweb 打包为 base64，嵌入安装脚本模板，生成单文件 dist/install.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/dist"

ver="$(tr -d '[:space:]' < "$ROOT/VERSION")"
[[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION 文件格式应为 x.y.z，当前为：$ver" >&2; exit 1; }

payload="$(mktemp)"
stage="$(mktemp -d)"
trap 'rm -rf "$payload" "$stage"' EXIT

# 把版本号一并打进程序包，网页页脚据此显示
cp -r "$ROOT/src/wgweb" "$stage/wgweb"
printf '%s\n' "$ver" > "$stage/wgweb/VERSION"
# 在 Windows 上工作区可能被 git 转成 CRLF，统一转回 LF，保证产物在任何机器上构建结果一致
find "$stage/wgweb" -type f -exec sed -i 's/\r$//' {} +
tar czf - --exclude='__pycache__' --exclude='*.pyc' -C "$stage" wgweb | base64 > "$payload"

# 替换版本号占位符，并把占位符所在行替换为 base64 内容
tr -d '\r' < "$ROOT/src/install.sh.tpl" \
  | sed -e "s#@@VERSION@@#${ver}#" -e '/@@PAYLOAD@@/{' -e "r $payload" -e 'd' -e '}' \
  > "$ROOT/dist/install.sh"
chmod +x "$ROOT/dist/install.sh"

echo "已生成 $ROOT/dist/install.sh（版本 $ver）"
