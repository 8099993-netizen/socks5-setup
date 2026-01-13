#!/usr/bin/env bash

# 用法示例：
# curl -sSL https://raw.githubusercontent.com/8099993-netizen/socks5-setup/main/setup_socks5.sh | bash -s -- "你的IP" "你的密码"

if [ $# -ne 2 ]; then
  echo "用法: bash <(curl -sSL https://raw.githubusercontent.com/8099993-netizen/socks5-setup/main/setup_socks5.sh) \"IP\" \"密码\""
  exit 1
fi

PROXY_IP="$1"
PROXY_PASS="$2"
PROXY_USER="sockuser"
PROXY_PORT="1080"

set -e

echo "配置 SOCKS5 + BBR on $PROXY_IP"
echo "用户: $PROXY_USER   密码: $PROXY_PASS   端口: $PROXY_PORT"

# 安装
sudo apt update -yq
sudo apt install -y dante-server

# 配置 danted.conf
sudo bash -c "cat > /etc/danted.conf" << EOF
logoutput: /var/log/danted.log
internal: 0.0.0.0 port = $PROXY_PORT
external: $PROXY_IP
socksmethod: username
clientmethod: none
user.privileged: root
user.unprivileged: nobody

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

# 设置用户密码
sudo useradd -s /usr/sbin/nologin $PROXY_USER 2>/dev/null || true
echo "$PROXY_USER:$PROXY_PASS" | sudo chpasswd

# 防火墙
sudo ufw allow $PROXY_PORT/tcp || true
sudo ufw reload || true

# 服务
sudo systemctl daemon-reload
sudo systemctl restart danted.service
sudo systemctl enable danted.service

sleep 3
sudo systemctl status danted.service --no-pager | grep -E "Active:|Main PID:"

sudo ss -tuln | grep $PROXY_PORT || echo "端口未监听"

# 测试
curl --socks5 $PROXY_USER:$PROXY_PASS@127.0.0.1:$PROXY_PORT https://ifconfig.me || echo "测试失败"

# BBR
echo "开启 BBR..."
echo "net.core.default_qdisc = fq" | sudo tee -a /etc/sysctl.conf >/dev/null
echo "net.ipv4.tcp_congestion_control = bbr" | sudo tee -a /etc/sysctl.conf >/dev/null
sudo sysctl -p
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc

echo "完成！代理: socks5://$PROXY_USER:$PROXY_PASS@$PROXY_IP:$PROXY_PORT"
