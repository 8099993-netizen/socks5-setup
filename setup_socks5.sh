#!/usr/bin/env bash

# =====================================================================
# 一键优化脚本：纯流量 SOCKS5 代理服务器（Dante + SSH + BBR + 瘦身）
# 用法：
# curl -sSL https://raw.githubusercontent.com/你的用户名/socks5-setup/main/setup_socks5_optimized.sh | bash -s -- "你的公网IP" "你的密码"
# =====================================================================

if [ $# -ne 2 ]; then
  echo "用法: bash <(curl -sSL https://raw.githubusercontent.com/8099993-netizen/socks5-setup/main/setup_socks5_optimized.sh) \"IP\" \"密码\""
  exit 1
fi

PROXY_IP="$1"
PROXY_PASS="$2"
PROXY_USER="sockuser"
PROXY_PORT="1080"

set -e

echo "开始一键配置纯流量 SOCKS5 代理 + SSH + BBR 优化"
echo "服务器 IP: $PROXY_IP"
echo "代理用户: $PROXY_USER   密码: $PROXY_PASS   端口: $PROXY_PORT"

# ------------------ 1. 安装并开启 SSH ------------------
echo "开启 SSH 服务（22 端口）..."
sudo apt update -yq
sudo apt install -y openssh-server
sudo systemctl start ssh
sudo systemctl enable ssh
sudo ufw allow ssh || true
sudo ufw allow 22/tcp || true
sudo ufw reload || true
echo "SSH 已开启！以后可使用 ssh root@$PROXY_IP 登录"

# ------------------ 2. 安装 Dante SOCKS5 ------------------
echo "安装 dante-server..."
sudo apt install -y dante-server

# 备份旧配置
[ -f /etc/danted.conf ] && sudo mv /etc/danted.conf /etc/danted.conf.bak_$(date +%s)

# 生成优化配置（最大并发、日志精简）
sudo bash -c "cat > /etc/danted.conf" << EOF
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = $PROXY_PORT
external: $PROXY_IP
socksmethod: username
clientmethod: none
user.privileged: root
user.unprivileged: nobody
max-childs: 1000
max-sessions: 5000

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: connect disconnect error
    socksmethod: username
}
EOF

# 设置用户密码（用 passwd 更可靠）
echo "设置用户和密码..."
sudo useradd -s /bin/false $PROXY_USER 2>/dev/null || true
echo "$PROXY_PASS" | sudo passwd --stdin $PROXY_USER

# 放行代理端口
sudo ufw allow $PROXY_PORT/tcp || true
sudo ufw reload || true

# 启动服务
sudo systemctl daemon-reload
sudo systemctl restart danted.service
sudo systemctl enable danted.service

sleep 3
echo "Dante 服务状态："
sudo systemctl status danted.service --no-pager | grep -E "Active:|Main PID:"

echo "端口监听："
sudo ss -tuln | grep $PROXY_PORT || echo "端口未监听"

# 本地测试代理
echo "本地代理测试（期望返回 $PROXY_IP）："
curl --socks5 $PROXY_USER:$PROXY_PASS@127.0.0.1:$PROXY_PORT https://ifconfig.me || echo "测试失败，请检查 /var/log/danted.log"

# ------------------ 3. 网络 & BBR 优化 ------------------
echo "开启 BBR + TCP 优化..."
cat <<EOF | sudo tee -a /etc/sysctl.conf >/dev/null
# BBR + 网络优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_mtu_probing = 1
vm.swappiness = 1
EOF

sudo sysctl -p

echo "BBR & 网络验证："
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
sysctl net.ipv4.tcp_fastopen

# ------------------ 4. 系统瘦身（关闭无用服务，降低资源占用） ------------------
echo "系统瘦身：关闭无用服务..."
sudo systemctl disable bluetooth cups cups-browsed avahi-daemon whoopsie apport snapd cloud-init 2>/dev/null || true
sudo systemctl stop bluetooth cups cups-browsed avahi-daemon whoopsie apport snapd cloud-init 2>/dev/null || true
sudo snap remove --purge core core20 snapd 2>/dev/null || true
sudo apt autoremove --purge -y
sudo apt clean

echo "优化完成！"
echo "SOCKS5 代理：socks5://$PROXY_USER:$PROXY_PASS@$PROXY_IP:$PROXY_PORT"
echo "SSH 登录：ssh root@$PROXY_IP"
echo "外部测试：curl --socks5 $PROXY_USER:$PROXY_PASS@$PROXY_IP:$PROXY_PORT https://ifconfig.me"
