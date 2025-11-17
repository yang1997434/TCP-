#!/bin/bash

# ============================================================================
# TCP端口监测机器人 - 一键部署安装脚本
# 使用方法: bash install.sh
# ============================================================================

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    print_error "此脚本需要root权限运行"
    echo "请使用: sudo bash install.sh"
    exit 1
fi

print_header "TCP实时监测机器人 - 一键部署"

# 1. 检查依赖
print_header "检查系统依赖"

# 检查Python3
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version 2>&1)
    print_success "Python3 已安装 ($PYTHON_VERSION)"
else
    print_error "未找到Python3，正在安装..."
    apt-get update
    apt-get install -y python3 python3-pip
fi

# 2. 创建安装目录
print_header "创建应用目录"

APP_DIR="/opt/tg-port-monitor"
mkdir -p $APP_DIR
print_success "应用目录: $APP_DIR"

# 3. 创建主程序文件
print_info "创建主程序..."

cat > $APP_DIR/bot.py << 'EOF'
import socket
import json
import os
import sys
import time
import logging
from datetime import datetime
from typing import Dict, Tuple
import asyncio
from collections import deque

from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes
from telegram.error import TelegramError

logging.basicConfig(
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    level=logging.INFO,
    handlers=[
        logging.FileHandler('/var/log/tg-monitor.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

# 配置
CONFIG_FILE = "/etc/tg-monitor/config.json"
PORTS_FILE = "/var/lib/tg-monitor/monitored_ports.json"
CHECK_INTERVAL = 30

# ============================================================================
# 配置加载
# ============================================================================

def load_config():
    """加载配置文件"""
    if not os.path.exists(CONFIG_FILE):
        print(f"错误: 配置文件不存在 {CONFIG_FILE}")
        sys.exit(1)
    
    with open(CONFIG_FILE, 'r') as f:
        return json.load(f)

config = load_config()
BOT_TOKEN = config.get('token')

if not BOT_TOKEN:
    print("错误: 配置文件中没有token")
    sys.exit(1)

# ============================================================================
# 端口监测类
# ============================================================================

class PortMonitor:
    def __init__(self, data_file=PORTS_FILE):
        self.data_file = data_file
        self.ports = {}
        self.response_times = {}
        self.load_data()
    
    def load_data(self):
        os.makedirs(os.path.dirname(self.data_file), exist_ok=True)
        if os.path.exists(self.data_file):
            try:
                with open(self.data_file, 'r') as f:
                    self.ports = json.load(f)
            except Exception as e:
                logger.error(f"加载数据失败: {e}")
    
    def save_data(self):
        try:
            os.makedirs(os.path.dirname(self.data_file), exist_ok=True)
            with open(self.data_file, 'w') as f:
                json.dump(self.ports, f, indent=2, ensure_ascii=False)
        except Exception as e:
            logger.error(f"保存数据失败: {e}")
    
    def add_port(self, host: str, port: int, name: str = "") -> Tuple[bool, str]:
        if not name:
            name = f"{host}:{port}"
        
        key = f"{host}:{port}"
        
        start = time.time()
        online, _ = self.test_connection(host, port)
        response_time = int((time.time() - start) * 1000)
        
        status = "✓ 在线" if online else "✗ 离线"
        
        self.ports[key] = {
            'host': host,
            'port': port,
            'name': name,
            'status': status,
            'response_time': response_time,
            'last_check': datetime.now().isoformat(),
            'uptime_24h': 100 if online else 0,
            'avg_response_time': response_time,
            'history': []
        }
        
        if key not in self.response_times:
            self.response_times[key] = deque(maxlen=48)
        self.response_times[key].append(response_time if online else None)
        
        self.save_data()
        return True, f"✓ {name} 已添加 ({status})"
    
    def remove_port(self, host: str, port: int) -> Tuple[bool, str]:
        key = f"{host}:{port}"
        if key in self.ports:
            name = self.ports[key]['name']
            del self.ports[key]
            if key in self.response_times:
                del self.response_times[key]
            self.save_data()
            return True, f"✓ {name} 已删除"
        return False, "端口不存在"
    
    def test_connection(self, host: str, port: int, timeout: int = 3) -> Tuple[bool, str]:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(timeout)
            result = sock.connect_ex((host, port))
            sock.close()
            return result == 0, "OK"
        except:
            return False, "Error"
    
    def check_all_ports(self):
        for key, port_info in self.ports.items():
            host = port_info['host']
            port = port_info['port']
            
            start = time.time()
            online, _ = self.test_connection(host, port)
            response_time = int((time.time() - start) * 1000)
            
            status = "✓ 在线" if online else "✗ 离线"
            port_info['status'] = status
            port_info['response_time'] = response_time
            port_info['last_check'] = datetime.now().isoformat()
            
            if key not in self.response_times:
                self.response_times[key] = deque(maxlen=48)
            
            self.response_times[key].append(response_time if online else None)
            
            if self.response_times[key]:
                online_count = sum(1 for t in self.response_times[key] if t is not None)
                port_info['uptime_24h'] = int((online_count / len(self.response_times[key])) * 100)
                
                valid_times = [t for t in self.response_times[key] if t is not None]
                if valid_times:
                    port_info['avg_response_time'] = int(sum(valid_times) / len(valid_times))
        
        self.save_data()
    
    def get_dashboard_text(self) -> str:
        if not self.ports:
            return "暂无监测的端口 使用 /add 添加"
        
        online_count = sum(1 for p in self.ports.values() if "在线" in p['status'])
        total_count = len(self.ports)
        
        text = f"┌─ *📊 实时监测面板* [{online_count}/{total_count}]\n"
        text += f"├─ 🕐 {datetime.now().strftime('%H:%M:%S')}\n"
        text += f"├─" + "─" * 40 + "\n"
        
        for key, port_info in sorted(self.ports.items(), 
                                     key=lambda x: (x[1]['status'] != "✓ 在线", x[0])):
            name = port_info['name']
            status = port_info['status']
            response_time = port_info['response_time']
            uptime = port_info.get('uptime_24h', 0)
            avg_response = port_info.get('avg_response_time', 0)
            
            if "在线" in status:
                indicator = "🟢"
                status_bar = "▓" * int(uptime/10) + "░" * (10 - int(uptime/10))
            else:
                indicator = "🔴"
                status_bar = "░" * 10
            
            text += f"├─ {indicator} {name:<15} {status_bar} {uptime:>3}%\n"
            text += f"│   ⏱️  {response_time:>3}ms (avg: {avg_response:>3}ms)\n"
        
        text += f"└─" + "─" * 40 + "\n"
        text += f"✓ 在线: *{online_count}* | ✗ 离线: *{total_count - online_count}*"
        
        return text

monitor = PortMonitor()
dashboard_message_ids = {}

# ============================================================================
# Telegram Commands
# ============================================================================

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = """
*🤖 TCP实时监测机器人*

📝 *命令:*
/add <主机> <端口> [名称]
/remove <主机> <端口>
/dashboard - 实时仪表板
/status - 查看状态
/list - 端口列表
/test <主机> <端口>
/help - 帮助

✨ 功能: 每30秒自动检查 | 实时更新
    """
    await update.message.reply_text(text, parse_mode='Markdown')

async def add_port(update: Update, context: ContextTypes.DEFAULT_TYPE):
    try:
        if len(context.args) < 2:
            await update.message.reply_text("用法: /add <主机> <端口> [名称]")
            return
        
        host = context.args[0]
        port = int(context.args[1])
        name = " ".join(context.args[2:]) if len(context.args) > 2 else ""
        
        success, message = monitor.add_port(host, port, name)
        await update.message.reply_text(message)
    except ValueError:
        await update.message.reply_text("❌ 端口必须是数字")

async def remove_port(update: Update, context: ContextTypes.DEFAULT_TYPE):
    try:
        if len(context.args) < 2:
            await update.message.reply_text("用法: /remove <主机> <端口>")
            return
        
        host = context.args[0]
        port = int(context.args[1])
        success, message = monitor.remove_port(host, port)
        await update.message.reply_text(message)
    except ValueError:
        await update.message.reply_text("❌ 端口必须是数字")

async def test_port(update: Update, context: ContextTypes.DEFAULT_TYPE):
    try:
        if len(context.args) < 2:
            await update.message.reply_text("用法: /test <主机> <端口>")
            return
        
        host = context.args[0]
        port = int(context.args[1])
        
        start = time.time()
        online, _ = monitor.test_connection(host, port)
        response_time = int((time.time() - start) * 1000)
        
        status = "✓ 在线" if online else "✗ 离线"
        text = f"🔍 *测试结果*\n状态: {status}\n响应: {response_time}ms"
        
        await update.message.reply_text(text, parse_mode='Markdown')
    except ValueError:
        await update.message.reply_text("❌ 端口必须是数字")

async def show_dashboard(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = monitor.get_dashboard_text()
    message = await update.message.reply_text(text, parse_mode='Markdown')
    
    chat_id = update.message.chat_id
    if chat_id not in dashboard_message_ids:
        dashboard_message_ids[chat_id] = []
    dashboard_message_ids[chat_id].append(message.message_id)

async def show_status(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = monitor.get_dashboard_text()
    await update.message.reply_text(text, parse_mode='Markdown')

async def list_ports(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not monitor.ports:
        await update.message.reply_text("暂无监测的端口")
        return
    
    text = "*📋 监测列表*\n\n"
    for i, (key, port_info) in enumerate(monitor.ports.items(), 1):
        status_icon = "✓" if "在线" in port_info['status'] else "✗"
        uptime = port_info.get('uptime_24h', 0)
        text += f"{i}. {status_icon} {port_info['name']} ({uptime}%)\n"
    
    await update.message.reply_text(text, parse_mode='Markdown')

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = """*📖 使用说明*

*/add 示例:*
/add 8.8.8.8 53 Google-DNS

*/status 查看所有端口状态*

*/dashboard 显示实时仪表板*

*/list 显示监测列表*

*/test 测试单个端口*
    """
    await update.message.reply_text(text, parse_mode='Markdown')

async def periodic_check(application):
    logger.info("✓ 启动定时检查 (间隔: 30秒)")
    
    while True:
        try:
            monitor.check_all_ports()
            online = sum(1 for p in monitor.ports.values() if '在线' in p['status'])
            logger.info(f"检查完成 - 在线: {online}/{len(monitor.ports)}")
            
            text = monitor.get_dashboard_text()
            
            for chat_id, message_ids in list(dashboard_message_ids.items()):
                for message_id in message_ids[-1:]:
                    try:
                        await application.bot.edit_message_text(
                            chat_id=chat_id,
                            message_id=message_id,
                            text=text,
                            parse_mode='Markdown'
                        )
                    except TelegramError as e:
                        logger.warning(f"更新失败 {chat_id}:{message_id}")
                        if message_id in message_ids:
                            message_ids.remove(message_id)
        
        except Exception as e:
            logger.error(f"检查出错: {e}")
        
        await asyncio.sleep(CHECK_INTERVAL)

async def main():
    application = Application.builder().token(BOT_TOKEN).build()
    
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("add", add_port))
    application.add_handler(CommandHandler("remove", remove_port))
    application.add_handler(CommandHandler("test", test_port))
    application.add_handler(CommandHandler("dashboard", show_dashboard))
    application.add_handler(CommandHandler("status", show_status))
    application.add_handler(CommandHandler("list", list_ports))
    application.add_handler(CommandHandler("help", help_command))
    
    asyncio.create_task(periodic_check(application))
    
    logger.info("✓ 机器人已启动")
    await application.run_polling()

if __name__ == '__main__':
    asyncio.run(main())
EOF

print_success "主程序创建完成"

# 4. 创建配置文件目录和模板
print_info "创建配置目录..."

mkdir -p /etc/tg-monitor
mkdir -p /var/lib/tg-monitor
mkdir -p /var/log

# 5. 获取Telegram Token
print_header "配置Telegram Bot Token"

echo "请输入你的Telegram Bot Token:"
echo "(从 @BotFather 获取)"
read -p "Token: " BOT_TOKEN

if [ -z "$BOT_TOKEN" ]; then
    print_error "Token不能为空"
    exit 1
fi

# 创建配置文件
cat > /etc/tg-monitor/config.json << EOF
{
  "token": "$BOT_TOKEN",
  "check_interval": 30,
  "log_file": "/var/log/tg-monitor.log"
}
EOF

print_success "配置文件已创建: /etc/tg-monitor/config.json"

# 6. 安装Python依赖
print_header "安装Python依赖"

pip3 install python-telegram-bot -q

print_success "依赖安装完成"

# 7. 创建Systemd服务文件
print_info "创建系统服务..."

cat > /etc/systemd/system/tg-monitor.service << EOF
[Unit]
Description=Telegram TCP Port Monitor Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR
ExecStart=/usr/bin/python3 $APP_DIR/bot.py
Restart=always
RestartSec=10
StandardOutput=append:/var/log/tg-monitor.log
StandardError=append:/var/log/tg-monitor.log

[Install]
WantedBy=multi-user.target
EOF

print_success "服务文件已创建"

# 8. 配置权限
print_info "配置文件权限..."

chmod +x $APP_DIR/bot.py
chmod 600 /etc/tg-monitor/config.json
chmod 755 /var/lib/tg-monitor
chmod 755 /var/log

print_success "权限配置完成"

# 9. 启用自启动
print_info "启用自启动..."

systemctl daemon-reload
systemctl enable tg-monitor.service

print_success "自启动已启用"

# 10. 启动服务
print_header "启动服务"

systemctl start tg-monitor.service

# 检查服务状态
sleep 2

if systemctl is-active --quiet tg-monitor.service; then
    print_success "✓ 服务运行中"
else
    print_error "✗ 服务启动失败"
    echo "查看日志: tail -f /var/log/tg-monitor.log"
    exit 1
fi

# 完成
print_header "✓ 安装完成"

echo "📋 接下来的步骤:"
echo "1. 在Telegram中找你的机器人"
echo "2. 发送: /start"
echo "3. 添加监测端口: /add 8.8.8.8 53 Google-DNS"
echo "4. 查看仪表板: /dashboard"
echo ""
echo "🔧 常用命令:"
echo "  查看日志: tail -f /var/log/tg-monitor.log"
echo "  重启服务: systemctl restart tg-monitor"
echo "  查看状态: systemctl status tg-monitor"
echo "  编辑配置: nano /etc/tg-monitor/config.json"
echo "  停止服务: systemctl stop tg-monitor"
echo ""
print_success "机器人已启动，祝使用愉快！🚀"
