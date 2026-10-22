# NoiseDeck：WireGuard 一键安装 + 网页管理（Debian 13）

**当前版本：v1.3.0** · 适用系统：Debian 13（普通主机，非容器）· 许可证：MIT

在普通（非容器）Debian 13 主机上，一条命令装好 WireGuard 服务端，并提供仅局域网可访问的管理网页：可新增多个客户端（peer），实时查看在线状态与上传 / 下载速率，直接显示二维码和可复制的配置文本。

## 一键安装

在 Debian 13 服务器上执行下面这一条命令，下载后会立即开始安装（需要 root；用 root 登录时去掉 `sudo`；精简版 Debian 没有 `wget` 时先 `apt install -y wget`）：

```bash
wget -O install.sh https://raw.githubusercontent.com/Fr33raNg3r/noisedeck/main/dist/install.sh && sudo bash install.sh
```

这个地址每次都会下载最新版。刚发布新版后 GitHub 的 `raw` 地址可能有几分钟缓存，下载到旧版时稍等再试。想固定某个版本，把地址中的 `main` 换成标签名（如 `v1.2.2`）。服务器访问不了 GitHub 时，见下方“国内下载镜像”。

用 `curl` 的等价写法：

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/Fr33raNg3r/noisedeck/main/dist/install.sh && sudo bash install.sh
```

安装过程需要按提示输入参数，所以脚本先保存为文件再运行，不要用 `curl ... | bash` 的管道写法。

### 国内下载镜像

服务器访问不了 `raw.githubusercontent.com` 时，任选下面一个镜像地址，替换上面命令里的链接（其余部分不变）：

| 镜像 | 下载地址 |
|---|---|
| gh-proxy | `https://gh-proxy.org/https://raw.githubusercontent.com/Fr33raNg3r/noisedeck/main/dist/install.sh` |
| gh-proxy（备用域名） | `https://gh-proxy.com/https://raw.githubusercontent.com/Fr33raNg3r/noisedeck/main/dist/install.sh` |
| ghfast | `https://ghfast.top/https://raw.githubusercontent.com/Fr33raNg3r/noisedeck/main/dist/install.sh` |
| jsDelivr | `https://cdn.jsdelivr.net/gh/Fr33raNg3r/noisedeck@main/dist/install.sh` |
| jsDelivr（备用） | `https://fastly.jsdelivr.net/gh/Fr33raNg3r/noisedeck@main/dist/install.sh` |

注意：

- 镜像都是第三方公共服务，可用性和速度会变化，某个不通就换下一个。脚本最终以 root 身份运行，**能直连 GitHub 时请优先直连**；用镜像时建议先 `less install.sh` 看一眼再运行。
- jsDelivr 对 `@main` 有较长缓存（可能数小时），想拿到刚发布的新版，把 `@main` 换成版本标签，如 `@v1.2.2`。

运行 `bash install.sh --version` 可查看脚本版本。已安装时再次运行，会让你选择“更新”或“完全重装”。

## 基本功能

- **一键部署**：安装 WireGuard 服务端，自动换清华 TUNA 软件源、更新系统、禁用 IPv6、开启转发并配置 NAT。
- **网页管理**：仅局域网可访问，账号密码登录；界面为卡片式布局，支持手机浏览；顶栏有“主题”按钮，可在跟随系统 / 浅色 / 深色之间切换（登录页同样有）。
- **多个客户端**：随时新增和删除，名称支持中文；每个客户端可直接显示二维码、可复制的配置文本，也可下载 `.conf`。
- **实时状态**：在线状态、最近握手时间、上传 / 下载速率和累计流量，每 3 秒自动刷新。
- **编辑与全局设置**：可改客户端名称、单独的 DNS 和路由范围；可改默认 DNS 和 Endpoint。
- **升级与维护**：保留数据升级（自动备份最近 3 份）、完全重装（保留 WireGuard 配置和客户端）、卸载并还原系统设置。
- **默认 DNS**：国内常用的 `223.5.5.5, 119.29.29.29, 114.114.114.114`，安装时可改，支持填多个。

## 手动使用与自行构建

```bash
# 在开发机生成单文件安装脚本（已生成的话可跳过）
bash build.sh

# 把 dist/install.sh 拷到 Debian 13 服务器，然后：
sudo bash install.sh              # 安装
sudo bash install.sh uninstall    # 卸载（4 步，每步需输入 yes 确认）
```

安装脚本会依次：换清华 TUNA 软件源（先备份）、`full-upgrade`、安装依赖、整机禁用 IPv6、开启 IPv4 转发、生成服务端密钥与配置、启动 `wg-quick@wg0` 和网页服务 `wg-web`。

交互参数都有默认值（回车即用）：WireGuard 端口 `51820/udp`、VPN 网段（每次随机生成 `10.X.Y.0/24`，自动避开本机已有路由并探测局域网，可手填覆盖）、DNS `223.5.5.5, 119.29.29.29, 114.114.114.114`（阿里、腾讯 DNSPod、114）、网页端口 `8080`。

客户端 DNS 可以填多个，用英文逗号分隔，如 `192.168.1.1, 223.5.5.5`。想让 VPN 客户端使用局域网内的 DNS，直接填它的地址即可（流量经本机 NAT 转发出去）。DNS 在安装时一次性设定，对所有客户端生效。

客户端名称可以用汉字、字母、数字、下划线和短横线（最长 32 个字符）。下载的配置文件名固定为 `wg-<内网IP>.conf`，这样 Windows / Linux 客户端才能导入。

注意事项：
- 公网 IP 的自动探测会访问 `https://api.ipify.org`；探测不到时需手填 Endpoint（公网 IP 或域名）。
- 需要在路由器上把 WireGuard 的 UDP 端口转发到这台服务器。
- 若内核被更新，脚本只提示重启，不会自动重启。
- 网页只监听你填写的内网 IP，使用 HTTP，没有 HTTPS。

## 网页上的编辑功能

- **编辑客户端**：卡片上的“编辑”可以修改名称（支持汉字）、单独的 DNS（可填多个）和路由范围。DNS 留空表示用全局默认；路由范围留空表示全部流量走 VPN，仅访问内网时可填如 `10.8.0.0/24, 192.168.1.0/24`。
- **全局设置**：页面顶部的“全局设置”可以修改默认 DNS、Endpoint（客户端连接地址）和 WireGuard 端口（1024-65535，避开系统保留端口）。改端口会让在线设备短暂断开，已有设备需重新导入配置，也请先在防火墙放行新的 UDP 端口。VPN 网段不能在网页修改，需要通过“完全重装”（且重装时沿用原网段）。
- 改名不影响设备；改 DNS、路由范围或 Endpoint 后，需要让对应设备重新扫码或导入配置才会生效。

## 版本与升级

版本号写在项目根目录的 `VERSION` 文件里（格式 `x.y.z`），`build.sh` 会把它写进 `dist/install.sh`：

- `bash install.sh --version` 查看脚本版本；安装开头和结尾都会显示版本号，已装版本记录在 `/etc/wg-web/version`，网页页脚也会显示。
- 发布新版本：修改 `VERSION`，再运行 `bash build.sh`。
- 升级：在服务器上运行新的 `install.sh`，选择“保留现有配置”。脚本会：
  1. 对比版本并提示“升级：v旧 → v新”；已装版本比脚本新时，需要输入 `yes` 才会降级。
  2. 先备份 `config.json`、`clients.json`、`wg0.conf` 到 `/etc/wg-web/backup/upgrade-<时间>/`，只保留最近 3 份。
  3. 清空 `/opt/wg-web` 后重新解包，覆盖旧程序，并清理残留的临时文件。
  4. 按新版本模板重新生成 `wg0.conf`，内容有变化才重启 WireGuard（连接会短暂中断）。
  5. 覆盖 systemd 服务文件并重启网页服务。
- 客户端、密钥、管理员账号在升级中保持不变。

已安装时运行脚本，会先让你选择：

- **1 更新（默认）**：如上所述，只覆盖程序，保留所有数据。
- **2 完全重装**：先备份，然后清除程序、systemd 服务、sysctl 设置、管理员账号和各项参数，重新询问并配置。**保留** `wg0.conf`（服务端密钥）、`clients.json`（全部客户端）和 `backup` 目录；VPN 网段沿用原值，不能更改。

## 目录

| 路径 | 说明 |
|---|---|
| `src/wgweb/` | Python 程序：`core.py` 纯逻辑、`store.py` 数据与同步、`app.py` 路由、`ui.py` 页面、`initcfg.py` 初始化 |
| `src/install.sh.tpl` | 安装 / 卸载脚本模板 |
| `build.sh` | 生成单文件 `dist/install.sh` |
| `dist/install.sh` | 生成好的单文件安装脚本（上面的 `wget` 命令下载的就是它） |
| `VERSION` | 版本号，格式 `x.y.z` |

## 真机验证清单（在 Debian 13 上执行）

1. `sudo wg show` 显示 `wg0`，监听端口正确。
2. `systemctl status wg-web` 为 active。
3. 在内网浏览器打开 `http://<内网IP>:8080`，登录成功，页面样式正常；换成深色模式、手机宽度也正常。
4. 新增至少两个客户端，分别用手机（扫码）和电脑（导入 / 复制配置）连接：
   - 对应卡片在几秒内变为“在线”，并显示最近握手时间；
   - 客户端下载或上传大文件时，卡片上的 ↑ / ↓ 速率随之变化，数量级与客户端测速一致，累计总量持续增加；
   - 断开约 3 分钟后变为“离线”；
   - 客户端能访问外网（VPN 出口为这台服务器）。
5. 删除一个客户端后，该设备无法再握手，其他客户端不受影响。
6. `ip -6 addr` 没有全局 IPv6 地址；`/etc/apt/sources.list.d/debian.sources` 指向 `mirrors.tuna.tsinghua.edu.cn`。
7. 重新运行 `sudo bash install.sh`，选择“保留现有配置”，客户端仍在。
8. `sudo bash install.sh uninstall` 全部确认后：服务与 `/opt/wg-web`、`/etc/wg-web` 消失，APT 源和 IPv6 设置还原。
