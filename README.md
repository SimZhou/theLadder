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

## 查看信息

```bash
sudo ./ladder.sh show xray
sudo ./ladder.sh show hysteria2
sudo ./ladder.sh show best
```

`show` 输出会附带可直接用于 mihomo 的 `proxies` 配置片段。

## 查看状态

```bash
sudo ./ladder.sh status xray
sudo ./ladder.sh status hysteria2
sudo ./ladder.sh status best
```

也可以直接查看系统服务：

```bash
systemctl status theladder-xray --no-pager
systemctl status theladder-hysteria2 --no-pager
```

## 重启

```bash
sudo systemctl restart theladder-xray
sudo systemctl restart theladder-hysteria2
```

## 停止

```bash
sudo systemctl stop theladder-xray
sudo systemctl stop theladder-hysteria2
```

## 卸载

```bash
sudo ./ladder.sh uninstall xray
sudo ./ladder.sh uninstall hysteria2
sudo ./ladder.sh uninstall best
```

## 端口

常用默认值：

```text
Xray: 443/tcp
Hysteria2: 8443/udp
```

如果机器有云平台安全组，需要在云平台控制台放行对应端口。

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
