# TCP监测机器人 - 一键部署指南

## 🚀 快速部署（3步）

### 第1步：下载安装脚本
```bash
# 在VPS上执行
curl -O https://your-server/install.sh
chmod +x install.sh
```

或直接创建文件：
```bash
# 将上面的install.sh脚本内容保存到文件
nano install.sh
# 粘贴内容后按 Ctrl+X -> Y -> Enter
chmod +x install.sh
```

### 第2步：运行安装脚本
```bash
sudo bash install.sh
```

脚本会自动：
- ✓ 检查/安装Python3依赖
- ✓ 创建应用目录 (`/opt/tg-port-monitor`)
- ✓ **交互式询问Telegram Token**
- ✓ 创建配置文件 (`/etc/tg-monitor/config.json`)
- ✓ 安装Python依赖包
- ✓ 创建Systemd服务
- ✓ **自动启用自启动**
- ✓ **自动启动服务**

### 第3步：使用机器人
```bash
# 在Telegram中发送
/start                           # 开始
/add 8.8.8.8 53 Google-DNS     # 添加监测
/dashboard                      # 显示仪表板
```

---

## 📋 部署完成后

### 查看服务状态
```bash
systemctl status tg-monitor
```

### 查看实时日志
```bash
tail -f /var/log/tg-monitor.log
```

### 重启服务
```bash
systemctl restart tg-monitor
```

### 修改配置
```bash
nano /etc/tg-monitor/config.json
```

### 停止服务
```bash
systemctl stop tg-monitor
```

### 卸载
```bash
systemctl stop tg-monitor
systemctl disable tg-monitor
rm -rf /opt/tg-port-monitor
rm /etc/systemd/system/tg-monitor.service
rm -rf /etc/tg-monitor
```

---

## 🎯 三个需求已全部实现

### ✅ 需求1：一键部署 + 自启动 + Token输入

**实现方式：**
- 📦 install.sh 脚本自动化所有步骤
- 🔐 安装时交互式询问Token（不需要修改代码）
- 🚀 自动启用Systemd自启动
- 🔄 开机自动启动服务

**使用方法：**
```bash
sudo bash install.sh
# 按提示输入Token即可
```

---

### ✅ 需求2：隐去IP和TCP端口

**实现方式：**
- TG展示中只显示 **名称** 和 **状态**
- **不显示具体的IP地址和端口号**
- 配置文件中保存完整信息（安全）

**显示效果对比：**

❌ 原来：
```
🟢 Google-DNS
   8.8.8.8:53
   ⏱️ 5ms
```

✅ 改进后：
```
🟢 Google-DNS          ▓▓▓▓▓▓▓▓▓▓ 100%
   ⏱️  5ms (avg: 8ms)
```

---

### ✅ 需求3：美观展示优化

**改进的可视化设计：**

```
┌─ 📊 实时监测面板 [3/4]
├─ 🕐 14:32:15
├──────────────────────────────────────────
├─ 🟢 Google-DNS       ▓▓▓▓▓▓▓▓▓▓ 100%
│   ⏱️  5ms (avg: 8ms)
├─ 🟢 MySQL-Database   ▓▓▓▓▓▓▓▓▓░  95%
│   ⏱️ 12ms (avg: 15ms)
├─ 🟢 API-Server       ▓▓▓▓▓▓▓░░░  75%
│   ⏱️ 45ms (avg: 52ms)
├─ 🔴 备用服务器       ░░░░░░░░░░   0%
│   ⏱️离线
└──────────────────────────────────────────
✓ 在线: 3 | ✗ 离线: 1
```

**设计特点：**
- ✨ 使用Box Drawing字符 (├─└─)
- ✨ 进度条清晰可视
- ✨ 颜色emoji区分状态
- ✨ 紧凑布局节省空间
- ✨ 百分比一目了然

---

## 📁 安装后的文件结构

```
/opt/tg-port-monitor/
  └── bot.py                 # 主程序

/etc/tg-monitor/
  └── config.json            # 配置文件（Token保存处）

/var/lib/tg-monitor/
  └── monitored_ports.json   # 监测数据

/var/log/
  └── tg-monitor.log         # 日志文件

/etc/systemd/system/
  └── tg-monitor.service     # 服务配置
```

---

## 🎮 常用命令速查

| 命令 | 说明 |
|------|------|
| `/add <主机> <端口> [名称]` | 添加监测 |
| `/remove <主机> <端口>` | 删除监测 |
| `/dashboard` | 实时仪表板 |
| `/status` | 查看状态 |
| `/list` | 端口列表 |
| `/test <主机> <端口>` | 测试端口 |
| `/help` | 帮助 |

---

## 🔐 安全性

- ✓ Token保存在 `/etc/tg-monitor/config.json` (权限600)
- ✓ 仅root用户可读
- ✓ Telegram中隐去敏感信息
- ✓ 所有数据本地保存

---

## 🐛 故障排查

### 服务无法启动
```bash
# 查看详细错误
systemctl status tg-monitor
journalctl -xe

# 查看日志
tail -f /var/log/tg-monitor.log
```

### Token错误
```bash
# 重新编辑配置
sudo nano /etc/tg-monitor/config.json

# 重启服务
sudo systemctl restart tg-monitor
```

### 权限问题
```bash
sudo chown -R root:root /opt/tg-port-monitor
sudo chmod +x /opt/tg-port-monitor/bot.py
sudo systemctl restart tg-monitor
```

---

## 💡 示例配置

```bash
# 添加Google DNS监测
/add 8.8.8.8 53 Google-DNS

# 添加数据库监测
/add 192.168.1.100 3306 MySQL-主库

# 添加API服务
/add api.example.com 443 API-服务器

# 启动仪表板
/dashboard

# 查看所有监测
/list
```

---

## 🎉 完成

所有需求已实现：
- ✅ 一键部署（bash install.sh）
- ✅ 自启动（systemd）
- ✅ Token交互式输入
- ✅ 隐去IP和端口（仅显示名称）
- ✅ 美观的实时展示

**准备好了吗？开始部署吧！** 🚀
