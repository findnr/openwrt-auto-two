#!/bin/bash
# ZeroTier Minimal Restore Script - 仅还原关键文件，使用固定文件名
# Usage: ./zerotier-minimal-restore.sh [backup_file.tar.gz]

# 设置日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a zerotier-restore.log
}

# 检查expect是否已安装
if ! command -v expect &> /dev/null; then
    log "正在安装expect..."
    sudo apt-get update
    if [ $? -ne 0 ]; then
        log "错误: 更新包管理器失败"
        exit 1
    fi
    sudo apt-get install -y expect
    if [ $? -ne 0 ]; then
        log "错误: 安装expect失败"
        exit 1
    fi
fi

# 从环境变量获取密码，如果未设置则使用默认值
ROOT_PASSWORD=${ROOT_PASSWORD:-"123456"}

# 使用指定的备份文件或默认名称
BACKUP_FILE=${1:-"zerotier-backup.tar.gz"}

# 检查备份文件是否存在
if [ ! -f "$BACKUP_FILE" ]; then
  log "错误: 未找到备份文件: $BACKUP_FILE"
  exit 1
fi

# 创建还原脚本
cat > restore_zerotier.sh << 'EOF'
#!/bin/bash

# 设置日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a zerotier-restore.log
}

# 使用指定的备份文件或默认名称
BACKUP_FILE=${1:-"zerotier-backup.tar.gz"}

# 检查备份文件是否存在
if [ ! -f "$BACKUP_FILE" ]; then
  log "错误: 未找到备份文件: $BACKUP_FILE"
  exit 1
fi

# 创建临时解压目录
TMP_DIR=$(mktemp -d)
if [ $? -ne 0 ]; then
  log "错误: 创建临时目录失败"
  exit 1
fi
trap 'rm -rf "$TMP_DIR"' EXIT

# 解压备份文件
log "解压备份文件..."
tar -xzf "$BACKUP_FILE" -C "$TMP_DIR"
if [ $? -ne 0 ]; then
  log "错误: 解压备份文件失败"
  exit 1
fi

# 检查必要文件是否存在
if [ ! -f "$TMP_DIR/identity.secret" ] || [ ! -f "$TMP_DIR/identity.public" ]; then
  log "错误: 备份文件中缺少身份文件"
  exit 1
fi

# 安装ZeroTier（如果需要）
if ! command -v zerotier-cli &> /dev/null; then
  log "未找到ZeroTier，正在安装..."
  curl -s https://install.zerotier.com | bash
  if [ $? -ne 0 ]; then
    log "错误: ZeroTier安装失败"
    exit 1
  fi
fi

# 停止ZeroTier服务
log "停止ZeroTier服务..."
systemctl stop zerotier-one
if [ $? -ne 0 ]; then
  log "警告: 停止ZeroTier服务失败"
fi

# 还原配置
log "还原ZeroTier配置..."
mkdir -p /var/lib/zerotier-one/networks.d
if [ $? -ne 0 ]; then
  log "错误: 创建配置目录失败"
  exit 1
fi

# 删除当前身份文件
rm -f /var/lib/zerotier-one/identity.*
rm -rf /var/lib/zerotier-one/networks.d/*

# 从备份复制文件
cp -f "$TMP_DIR"/identity.* /var/lib/zerotier-one/
if [ $? -ne 0 ]; then
  log "错误: 复制身份文件失败"
  exit 1
fi

if [ -d "$TMP_DIR/networks.d" ]; then
  cp -rf "$TMP_DIR"/networks.d/* /var/lib/zerotier-one/networks.d/ 2>/dev/null || true
fi

# 设置正确权限
chown root:root /var/lib/zerotier-one/identity.*
chmod 600 /var/lib/zerotier-one/identity.secret
chmod 644 /var/lib/zerotier-one/identity.public

# 重启ZeroTier服务
log "启动ZeroTier服务..."
systemctl start zerotier-one
if [ $? -ne 0 ]; then
  log "错误: 启动ZeroTier服务失败"
  exit 1
fi
sleep 2

# 检查服务状态
if ! systemctl is-active --quiet zerotier-one; then
  log "错误: ZeroTier服务未能正常启动"
  exit 1
fi

# 显示网络信息
log "还原后的网络信息:"
# zerotier-cli status
# zerotier-cli listnetworks

log "ZeroTier配置还原成功！"
EOF

# 设置脚本可执行权限
chmod +x restore_zerotier.sh
if [ $? -ne 0 ]; then
  log "错误: 设置脚本权限失败"
  exit 1
fi

# 创建expect脚本来以root权限运行restore脚本
cat > run_as_root.exp << EOF
#!/usr/bin/expect -f

set timeout 300

# 使用su切换到root用户
spawn su root -c "./restore_zerotier.sh $BACKUP_FILE"
expect "Password:"
send "$ROOT_PASSWORD\r"
expect eof
EOF

# 设置expect脚本可执行权限
chmod +x run_as_root.exp
if [ $? -ne 0 ]; then
  log "错误: 设置expect脚本权限失败"
  exit 1
fi

# 运行expect脚本
./run_as_root.exp

# 清理临时脚本
rm -f restore_zerotier.sh run_as_root.exp
