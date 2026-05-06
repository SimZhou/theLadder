# theLadder 简明说明

本项目用于在 Linux 机器上安装和管理若干网络服务组件。

## 准备

```bash
git clone https://github.com/SimZhou/theLadder.git
cd theLadder
chmod +x ladder.sh
```

如果已经下载过：

```bash
cd theLadder
git pull
```

## 安装

推荐组合：

```bash
sudo ./ladder.sh install best
```

仅安装 Xray 组件：

```bash
sudo ./ladder.sh install xray 443 www.microsoft.com
```

仅安装 Hysteria2 组件：

```bash
sudo ./ladder.sh install hysteria2 8443
```

安装内网直通代理：

```bash
sudo ./ladder.sh install lan-proxy
```

指定监听地址、端口和账号密码：

```bash
sudo ./ladder.sh install lan-proxy --listen 0.0.0.0 --port 7890 --user theladder --password 'change-me'
```

无 root 权限时，安装到当前用户目录并用后台进程运行：

```bash
./ladder.sh install lan-proxy-user
```

用户态安装不会写入 `/etc`、`/usr/local/bin` 或 systemd，文件位置为：

```text
~/.local/bin/sing-box
~/.config/theladder/lan-proxy.json
~/.config/theladder/lan-proxy-client.txt
~/.local/state/theladder/lan-proxy.pid
~/.local/state/theladder/log/lan-proxy.log
```

## 查看信息

```bash
sudo ./ladder.sh show xray
sudo ./ladder.sh show hysteria2
sudo ./ladder.sh show lan-proxy
./ladder.sh show lan-proxy-user
sudo ./ladder.sh show best
```

`show` 输出会附带可直接用于 mihomo 的 `proxies` 配置片段。
`show lan-proxy` 输出的是给内网机器使用的 HTTP/SOCKS5 代理地址和环境变量。

## 查看状态

```bash
sudo ./ladder.sh status xray
sudo ./ladder.sh status hysteria2
sudo ./ladder.sh status lan-proxy
./ladder.sh status lan-proxy-user
sudo ./ladder.sh status best
```

也可以直接查看系统服务：

```bash
systemctl status theladder-xray --no-pager
systemctl status theladder-hysteria2 --no-pager
systemctl status theladder-lan-proxy --no-pager
```

## 重启

```bash
sudo systemctl restart theladder-xray
sudo systemctl restart theladder-hysteria2
sudo systemctl restart theladder-lan-proxy
./ladder.sh restart lan-proxy-user
```

## 停止

```bash
sudo systemctl stop theladder-xray
sudo systemctl stop theladder-hysteria2
sudo systemctl stop theladder-lan-proxy
./ladder.sh stop lan-proxy-user
```

## 卸载

```bash
sudo ./ladder.sh uninstall xray
sudo ./ladder.sh uninstall hysteria2
sudo ./ladder.sh uninstall lan-proxy
./ladder.sh uninstall lan-proxy-user
sudo ./ladder.sh uninstall best
```

## 端口

常用默认值：

```text
Xray: 443/tcp
Hysteria2: 8443/udp
LAN Proxy: 7890/tcp
```

如果机器有云平台安全组，需要在云平台控制台放行对应端口。

## 内网直通代理

`lan-proxy` 适合把一台能访问外网的机器作为内网出口。脚本会安装 sing-box，并启动一个 HTTP/SOCKS5 混合代理。默认监听 `0.0.0.0:7890`，账号为 `theladder`，密码未指定时自动生成。

有 root 权限时用 `lan-proxy`，脚本会创建 systemd 服务并尝试放行防火墙端口。没有 root 权限时用 `lan-proxy-user`，脚本只使用当前用户目录，并通过 pid 文件管理后台进程；机器重启后需要重新执行 `./ladder.sh start lan-proxy-user`。

在内网机器上临时使用：

```bash
export http_proxy="http://用户:密码@出口机内网IP:7890"
export https_proxy="http://用户:密码@出口机内网IP:7890"
export all_proxy="socks5://用户:密码@出口机内网IP:7890"
```

只在可信内网开放该端口；如果出口机有防火墙或云安全组，需要仅向内网来源放行 `7890/tcp`。

## 旧组件清理

检查旧组件：

```bash
sudo ./ladder.sh legacy status
```

确认不再需要后清理：

```bash
sudo ./ladder.sh legacy purge
```

清理前会备份相关文件到 `/root/backup-theLadder-legacy-*`。
