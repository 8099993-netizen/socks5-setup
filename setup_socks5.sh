#!/usr/bin/env bash

# 用法示例：
# curl -sSL https://raw.githubusercontent.com/8099993-netizen/socks5-setup/main/setup_all.sh | bash -s -- "你的IP" "你的密码"

if [ $# -ne 2 ]; then
  echo "用法: bash <(curl -sSL https://raw.githubusercontent.com/8099993-netizen/socks5-setup/main/setup_all.sh) \"IP\" \"密码\""
  exit 1
fi

PROXY_IP="$1"
PROXY_PASS="$2"
PROXY_USER="sockuser"
PROXY_PORT="1080"

set -e

echo "开始一键配置：SSH + SOCKS5 + BBR on $PROXY_IP"
echo "SSH 将自动开启，SOCKS5 用户: $PROXY_USER  密码: $PROXY_PASS  端口: $PROXY_PORT"

# ------------------ 第一部分：开启 SSH ------------------
echo "开启 SSH 服务（22 端口）..."
sudo apt update -yq
sudo apt install -y openssh-server
sudo systemctl start ssh
sudo systemctl enable ssh

# 放行 SSH 端口
sudo ufw allow ssh || true
sudo ufw allow 22/tcp || true
sudo ufw reload || true

echo "SSH 已开启！以后可用 ssh root@$PROXY_IP 登录"

# ------------------ 第二部分：安装并配置 Dante SOCKS5 ------------------
echo "安装 dante-server..."
sudo apt install -y dante-server

# 备份旧配置
[ -f /etc/danted.conf ] && sudo mv /etc/danted.conf /etc/danted.conf.bak_$(date +%s)

# 生成新配置
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
echo "设置用户和密码..."
sudo useradd -s /usr/sbin/nologin $PROXY_USER 2>/dev/null || true
echo -e "$PROXY_PASS\n$PROXY_PASS" | sudo passwd $PROXY_USER

# 放行 SOCKS5 端口
sudo ufw allow $PROXY_PORT/tcp || true
sudo ufw reload || true

# 启动服务
sudo systemctl daemon-reload
sudo systemctl restart danted.service
sudo systemctl enable danted.service

sleep 3
sudo systemctl status danted.service --no-pager | grep -E "Active:|Main PID:"

sudo ss -tuln | grep $PROXY_PORT || echo "端口未监听"

# 测试代理
echo "本地代理测试（期望返回 $PROXY_IP）："
curl --socks5 $PROXY_USER:$PROXY_PASS@127.0.0.1:$PROXY_PORT https://ifconfig.me || echo "测试失败，请检查 /var/log/danted.log"

# ------------------ 第三部分：开启 BBR ------------------
echo "开启 BBR..."
echo "net.core.default_qdisc = fq" | sudo tee -a /etc/sysctl.conf >/dev/null
echo "net.ipv4.tcp_congestion_control = bbr" | sudo tee -a /etc/sysctl.conf >/dev/null
sudo sysctl -p
echo "BBR 验证："
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc

echo "全部完成！"
echo "SOCKS5: socks5://$PROXY_USER:$PROXY_PASS@$PROXY_IP:$PROXY_PORT"
echo "SSH: ssh root@$PROXY_IP  (用 root 密码登录)"
