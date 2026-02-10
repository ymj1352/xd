#!/bin/bash
set -e

##################################
# 下载地址
##################################

XRAY_URL="https://dufs.f.mfs.cc.cd/data/xray/xray.tar.gz"
DNS_URL="https://dufs.f.mfs.cc.cd/data/dns-proxy/dns-proxy.tar.gz"
XTUNNEL_URL="https://dufs.f.mfs.cc.cd/data/x-tunnel/x-tunnel.tar.gz"
CLOUDFLARED_URL="https://dufs.f.mfs.cc.cd/data/cloudflared/cloudflared.tar.gz"

##################################
# 默认 MODE
##################################

MODE=${MODE:-client_tunnel}
##........支持模式..............##
##server_direct  直连服务器模式 ##
##server_argo    argo服务器模式 ##
##client_tunnel  x_tunnel客户端模式 ##
##client_xray  xray客户端模式 ##


##################################
# 下载函数
##################################

download_if_needed() {

    NAME=$1
    URL=$2

    [ -d /root/$NAME ] || (
        cd /root && \
        curl -L -f --retry 3 "$URL" -o ${NAME}.tar.gz && \
        tar -xzf ${NAME}.tar.gz && \
        rm -f ${NAME}.tar.gz
    )

    cp -a /root/$NAME/. "$PWD/"
    chmod +x $NAME
}

##################################
# x-tunnel 命令生成
##################################

generate_x_tunnel_cmd() {

    CMD="./x-tunnel"

    while IFS='=' read -r key value; do

        key=$(echo "$key" | tr -d ' {}')
        value=$(echo "$value" | xargs)

        [ -z "$key" ] && continue
        [ -z "$value" ] && continue

        case "$key" in
            fallback|insecure)
                CMD="$CMD -$key"
                ;;
            *)
                CMD="$CMD -$key $value"
                ;;
        esac

    done < <(sed '1d;$d' ./x-tunnel.txt)

    echo "$CMD"
}

##################################
# cloudflared 命令生成
##################################

generate_cloudflared_cmd() {

    TOKEN=$(grep '=' cloudflared.txt | cut -d '=' -f2 | xargs)

    [ -z "$TOKEN" ] && return

    echo "./cloudflared tunnel run --token $TOKEN"
}

##################################
# MODE -> 组件映射
##################################

USE_DNS=false
USE_XRAY=false
USE_XTUNNEL=false
USE_CLOUDFLARED=false

case "$MODE" in

server_direct)
    USE_XTUNNEL=true
    ;;

server_argo)
    USE_XTUNNEL=true
    USE_CLOUDFLARED=true
    ;;

client_tunnel)
    USE_DNS=true
    USE_XTUNNEL=true
    ;;

client_xray)
    USE_DNS=true
    USE_XRAY=true
    ;;

*)
    echo "未知 MODE: $MODE"
    exit 1
    ;;

esac


##################################
# 下载
##################################

$USE_DNS && download_if_needed "dns-proxy" "$DNS_URL"
$USE_XRAY && download_if_needed "xray" "$XRAY_URL"
$USE_XTUNNEL && download_if_needed "x-tunnel" "$XTUNNEL_URL"
$USE_CLOUDFLARED && download_if_needed "cloudflared" "$CLOUDFLARED_URL"


##################################
# 启动
##################################

LOG_FILE=""

### xray
if $USE_XRAY; then

    echo "启动 xray..."
    ./xray run -config /root/config.json >xray.log 2>&1 &
    LOG_FILE="xray.log"

fi


### dns-proxy
if $USE_DNS; then

    echo "启动 dns-proxy..."
    ./dns-proxy >dns-proxy.log 2>&1 &

fi


### x-tunnel
if $USE_XTUNNEL; then

    if [ -f "./x-tunnel.txt" ]; then

        X_CMD=$(generate_x_tunnel_cmd)

        if [ -n "$X_CMD" ]; then
            echo "启动 x-tunnel..."
            eval "$X_CMD >x-tunnel.log 2>&1 &"
            LOG_FILE="x-tunnel.log"
        fi
    else
        echo "警告: 未找到 x-tunnel.txt"
    fi

fi


### cloudflared
if $USE_CLOUDFLARED; then

    if [ -f "./cloudflared.txt" ]; then

        C_CMD=$(generate_cloudflared_cmd)

        if [ -n "$C_CMD" ]; then
            echo "启动 cloudflared..."
            eval "$C_CMD >cloudflared.log 2>&1 &"
        fi
    else
        echo "警告: 未找到 cloudflared.txt"
    fi

fi


##################################
# 获取容器IP
##################################

CONTAINER_IP=$(hostname -I | awk '{print $1}')

##################################
# 输出
##################################

echo "============================================"
echo "容器启动成功"
echo "MODE=$MODE"
echo "============================================"

if $USE_DNS; then
    echo "请登录 http://$CONTAINER_IP:10000 配置参数"
	echo "代理地址请改为socks5://127.0.0.1:3000"
fi

echo "============================================"


##################################
# 前台日志
##################################

if [ -n "$LOG_FILE" ]; then
    tail -f "$LOG_FILE"
else
    tail -f /dev/null
fi
