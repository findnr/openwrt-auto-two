#!/bin/bash

# 设置日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a v2ray-install.log
}

# 错误处理函数
handle_error() {
    log "错误: $1"
    exit 1
}

# 检查expect是否已安装
if ! command -v expect &> /dev/null; then
    log "正在安装expect..."
    sudo apt-get update
    sudo apt-get install -y expect
fi

# 从环境变量获取密码，如果未设置则使用默认值
ROOT_PASSWORD=${ROOT_PASSWORD:-"123456"}

# 使用固定的UUID
UUID="3228ad31-eff6-4a21-99d3-065f7b677a53"

# 直接创建一个可执行的脚本，以root权限运行
cat > setup_v2ray.sh << EOF
#!/bin/bash

# 启用IP转发
log "配置IP转发..."
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

# 安装V2Ray
log "安装V2Ray..."
curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh | bash
if [ $? -ne 0 ]; then
    handle_error "V2Ray安装失败"
fi

# 创建V2Ray配置文件
log "创建V2Ray配置文件..."
cat > /usr/local/etc/v2ray/config.json << 'ENDOFFILE'
{
  "inbounds": [
    {
      "port": 10086,
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "alterId": 0
          }
        ]
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
ENDOFFILE

# 替换UUID
sed -i "s/\\${UUID}/${UUID}/g" /usr/local/etc/v2ray/config.json

# 设置iptables规则
log "配置iptables规则..."
INTERFACE=\$(ip route | grep default | awk '{print \$5}')
if [ -z "\$INTERFACE" ]; then
    handle_error "获取网络接口失败"
fi

iptables -t nat -A POSTROUTING -o \$INTERFACE -j MASQUERADE
if [ $? -ne 0 ]; then
    handle_error "设置iptables规则失败"
fi

# 安装iptables-persistent以保存规则
apt-get install -y iptables-persistent
if [ $? -ne 0 ]; then
    log "警告: 安装iptables-persistent失败"
fi

# 启动V2Ray服务
log "启动V2Ray服务..."
systemctl enable v2ray || handle_error "启用V2Ray服务失败"
systemctl restart v2ray
if [ $? -ne 0 ]; then
    handle_error "启动V2Ray服务失败"
fi

# 检查服务状态
if ! systemctl is-active --quiet v2ray; then
    log "错误: V2Ray服务未能正常启动"
    exit 1
fi

log "V2Ray安装完成"
log "服务器地址: 需要通过frp映射的公网IP"
log "端口: 10086"
log "用户ID: ${UUID}"
log "协议: vmess"
log "传输协议: tcp"
EOF

# 设置脚本可执行权限
chmod +x setup_v2ray.sh

# 创建expect脚本来以root权限运行setup脚本
cat > run_as_root.exp << EOF
#!/usr/bin/expect -f

set timeout 300

# 使用su切换到root用户
spawn su root -c "./setup_v2ray.sh"
expect "Password:"
send "$ROOT_PASSWORD\r"
expect eof
EOF

# 设置expect脚本可执行权限
chmod +x run_as_root.exp

# 运行expect脚本
./run_as_root.exp

# 保存配置信息到本地文件
log "保存配置信息到v2ray_info.txt..."
cat > v2ray_info.txt << EOF
=============================
V2Ray 安装完成
服务器地址: 需要通过frp映射的公网IP
端口: 10086
用户ID: $UUID
协议: vmess
传输协议: tcp
=============================
EOF

log "脚本执行完毕，配置信息已保存到 v2ray_info.txt"

# 清理临时脚本
rm -f setup_v2ray.sh run_as_root.exp
