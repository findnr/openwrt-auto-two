#!/bin/bash

# 设置日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a password-modify.log
}

# 从环境变量获取密码，如果未设置则使用默认值
PASSWORD=${PASSWORD:-"123456"}

log "开始修改root和runner用户密码..."

# 修改runner用户密码
log "修改runner用户密码..."
expect -c "
    spawn sudo passwd runner
    expect {
        \"password\" { send \"$PASSWORD\r\";}
    }
    expect {
        \"password\" { send \"$PASSWORD\r\";}
    }
expect eof" || {
    log "错误: 修改runner用户密码失败"
    exit 1
}

# 修改root用户密码
log "修改root用户密码..."
expect -c "
    spawn sudo passwd root
    expect {
        \"password\" { send \"$PASSWORD\r\";}
    }
    expect {
        \"password\" { send \"$PASSWORD\r\";}
    }
expect eof" || {
    log "错误: 修改root用户密码失败"
    exit 1
}

# log "密码修改完成，新密码已设置为: $PASSWORD"
