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

安装到当前用户目录：

```bash
./ladder.sh install lan-proxy --user
```

安装到用户目录，并把 B 机器作为上游代理中转：

```bash
./ladder.sh install lan-proxy --user --upstream http://user:pass@1.2.3.4:7890 --port 17890
```

指定监听地址、端口和账号密码：

```bash
sudo ./ladder.sh install lan-proxy --listen 0.0.0.0 --port 7890 --username theladder --password 'change-me'
```

用户态安装不会写入 `/etc` 或 `/usr/local/bin`，会写入当前用户目录和用户级 systemd，文件位置为：

```text
~/.local/bin/sing-box
~/.config/theladder/lan-proxy.json
~/.config/theladder/lan-proxy-client.txt
~/.config/systemd/user/theladder-lan-proxy.service
```

重复执行安装时，如果 `~/.local/bin/sing-box` 已存在，会复用现有二进制。

## 查看信息

```bash
sudo ./ladder.sh show xray
sudo ./ladder.sh show hysteria2
sudo ./ladder.sh show lan-proxy
./ladder.sh show lan-proxy --user
sudo ./ladder.sh show best
```

`show` 输出会附带可直接用于 mihomo 的 `proxies` 配置片段。
`show lan-proxy` 输出的是给内网机器使用的 HTTP/SOCKS5 代理地址和环境变量。

## 查看状态

```bash
sudo ./ladder.sh status xray
sudo ./ladder.sh status hysteria2
sudo ./ladder.sh status lan-proxy
./ladder.sh status lan-proxy --user
sudo ./ladder.sh status best
```

也可以直接查看系统服务：

```bash
systemctl status theladder-xray --no-pager
systemctl status theladder-hysteria2 --no-pager
systemctl status theladder-lan-proxy --no-pager
systemctl --user status theladder-lan-proxy --no-pager
```

## 重启

```bash
sudo systemctl restart theladder-xray
sudo systemctl restart theladder-hysteria2
sudo systemctl restart theladder-lan-proxy
./ladder.sh restart lan-proxy --user
```

## 停止

```bash
sudo systemctl stop theladder-xray
sudo systemctl stop theladder-hysteria2
sudo systemctl stop theladder-lan-proxy
./ladder.sh stop lan-proxy --user
```

## 卸载

```bash
sudo ./ladder.sh uninstall xray
sudo ./ladder.sh uninstall hysteria2
sudo ./ladder.sh uninstall lan-proxy
./ladder.sh uninstall lan-proxy --user
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

如果带 `--upstream`，`lan-proxy` 会进入中转模式：在本机开放一个新的 mixed 代理入口，再把流量转发到上游 `http://` 或 `socks5://` 代理。未额外指定 `--username/--password` 时，会默认复用上游地址中的账号密码作为本地对外认证。

`install lan-proxy` 默认做系统级安装：会创建 systemd 服务并尝试放行防火墙端口。带 `--user`，或在非 root 下直接执行 `./ladder.sh install lan-proxy` 时，会改为用户级安装：只使用当前用户目录，并通过用户级 systemd 管理。若希望机器重启后自动拉起用户级服务，通常需要管理员提前执行 `loginctl enable-linger <user>`。

以 `A` 机器已经开放 `mihomo mixed-port` 为例，如果：

- `A` 的代理地址是 `http://alice:secret@10.0.0.10:7890`
- `B` 机器需要以用户级方式开放 `17890`
- `C` 机器只能访问 `B`，再由 `B` 转发到 `A`

那么在 `B` 上执行：

```bash
./ladder.sh install lan-proxy --user \
  --upstream http://alice:secret@10.0.0.10:7890 \
  --port 17890
```

安装完成后查看对外地址：

```bash
./ladder.sh show lan-proxy --user
```

如果 `B` 的内网地址是 `10.0.0.20`，则 `C` 机器可以直接使用：

```bash
export http_proxy="http://alice:secret@10.0.0.20:17890"
export https_proxy="http://alice:secret@10.0.0.20:17890"
export all_proxy="socks5://alice:secret@10.0.0.20:17890"
```

在内网机器上临时使用：

```bash
export http_proxy="http://用户:密码@出口机内网IP:7890"
export https_proxy="http://用户:密码@出口机内网IP:7890"
export all_proxy="socks5://用户:密码@出口机内网IP:7890"
```

只在可信内网开放该端口；如果出口机有防火墙或云安全组，需要仅向内网来源放行 `7890/tcp`。

如果提示端口已占用，换一个高位端口重新安装：

```bash
./ladder.sh install lan-proxy --user --port 18080
```

查看用户级日志：

```bash
journalctl --user -u theladder-lan-proxy.service -n 50 --no-pager
```

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
