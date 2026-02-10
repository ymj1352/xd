#!/bin/bash
set -e

# ==========================
# 下载地址声明
XRAY_URL="https://dufs.f.mfs.cc.cd/data/xray/xray.tar.gz"
DNS_PROXY_URL="https://dufs.f.mfs.cc.cd/data/dns-proxy/dns-proxy.tar.gz"
X_TUNNEL_URL="https://dufs.f.mfs.cc.cd/data/x-tunnel/x-tunnel.tar.gz"
CLOUDFLARED_URL="https://dufs.f.mfs.cc.cd/data/cloudflared/cloudflared.tar.gz"

# ==========================
# 默认 MODE
# MODE 支持的模式及说明：
# server_direct   -> 直连服务器模式
# server_argo     -> argo服务器模式
# client_tunnel   -> dns-proxy + x-tunnel客户端模式运行
# client_xray     -> dns-proxy + xray客户端模式运行
# x-tunnel        -> x-tunnel模式运行
# dns-proxy       -> dns-proxy模式运行
MODE="${MODE:-client_tunnel}"

# ==========================
# 下载并复制函数
fetch_and_copy() {
    local name="$1"
    local url="$2"

    if [ ! -e "/root/$name" ]; then
        cd /root
        echo "下载 $name ..."
        curl -L -f --retry 3 "$url" -o "$name.tar.gz"
        tar -xzf "$name.tar.gz"
        rm -f "$name.tar.gz"
    fi

    # 如果是目录，复制目录内容；如果是文件，直接复制
    if [ -d "/root/$name" ]; then
        cp -a "/root/$name/." "$PWD/"
    elif [ -f "/root/$name" ]; then
        cp -a "/root/$name" "$PWD/"
    else
        echo "错误: /root/$name 下载或解压失败"
        exit 1
    fi

    # 给可执行文件赋权
    if [ -f "$PWD/$name" ]; then
        chmod +x "$PWD/$name"
    elif [ -d "$PWD/$name" ]; then
        find "$PWD/$name" -type f -exec chmod +x {} \;
    fi
}

# ==========================
# 下载组件
case "$MODE" in
    server_direct)
        fetch_and_copy "x-tunnel" "$X_TUNNEL_URL"
        ;;
    server_argo)
        fetch_and_copy "x-tunnel" "$X_TUNNEL_URL"
        fetch_and_copy "cloudflared" "$CLOUDFLARED_URL"
        ;;
    client_tunnel)
        fetch_and_copy "dns-proxy" "$DNS_PROXY_URL"
        fetch_and_copy "x-tunnel" "$X_TUNNEL_URL"
        ;;
    client_xray)
        fetch_and_copy "dns-proxy" "$DNS_PROXY_URL"
        fetch_and_copy "xray" "$XRAY_URL"
        ;;
    x-tunnel)
        fetch_and_copy "x-tunnel" "$X_TUNNEL_URL"
        ;;
    dns-proxy)
        fetch_and_copy "dns-proxy" "$DNS_PROXY_URL"
        ;;
    *)
        echo "未知 MODE=$MODE"
        exit 1
        ;;
esac

# ===========================================
# 获取容器 IP
CONTAINER_IP=$(hostname -I | awk '{print $1}')

# ==============================================
# 输出启动模式信息
echo "============================================"
echo "容器启动模式 MODE=$MODE"
echo "============================================"

# 如果 dns-proxy 在当前模式下运行，则输出访问提示
if [[ "$MODE" == "client_tunnel" || "$MODE" == "client_xray" || "$MODE" == "dns-proxy" ]]; then
    echo "请登录 http://$CONTAINER_IP:10000 配置参数"
    echo "代理地址请改为socks5://127.0.0.1:3000"
fi

# ==========================
# 启动组件
# dns-proxy
if [[ "$MODE" == "client_tunnel" || "$MODE" == "client_xray" || "$MODE" == "dns-proxy" ]]; then
    echo "启动 dns-proxy 客户端..."
    ./dns-proxy >dns-proxy.log 2>&1 &
    DNS_PROXY_PID=$!
    DNS_PROXY_LOG="dns-proxy.log"
fi

# xray
if [[ "$MODE" == "client_xray" ]]; then
    echo "启动 xray 客户端..."
    ./xray run -config /root/xray/config.json >xray.log 2>&1 &
    XRAY_PID=$!
    XRAY_LOG="xray.log"
fi

# 启动 x-tunnel
if [[ "$MODE" == "server_direct" || "$MODE" == "server_argo" || "$MODE" == "client_tunnel" || "$MODE" == "x-tunnel" ]]; then
    XTUNNEL_CMD="./x-tunnel"
    XTUNNEL_CONF="./x-tunnel.txt"

    if [ -f "$XTUNNEL_CONF" ]; then
        while IFS='=' read -r key value; do
            key=$(echo "$key" | tr -d ' ')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # 跳过空行、注释、花括号
            [[ -z "$key" || "$key" == "{" || "$key" == "}" || "$key" =~ ^// ]] && continue
            [[ -z "$value" ]] && continue

            case "$key" in
                fallback|insecure)
                    XTUNNEL_CMD="$XTUNNEL_CMD -$key"
                    ;;
                *)
                    XTUNNEL_CMD="$XTUNNEL_CMD -$key $value"
                    ;;
            esac
        done < "$XTUNNEL_CONF"
    fi

    echo "启动 x-tunnel："
    echo "$XTUNNEL_CMD"

    $XTUNNEL_CMD >x-tunnel.log 2>&1 &
    XTUNNEL_LOG="x-tunnel.log"
fi

# 启动 cloudflared
if [[ "$MODE" == "server_argo" ]]; then
    CLOUDFLARED_CMD="./cloudflared"
    CLOUDFLARED_CONF="./cloudflared.txt"

    if [ -f "$CLOUDFLARED_CONF" ]; then
        while IFS='=' read -r key value; do
            key=$(echo "$key" | tr -d ' ')
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

            # 跳过空行、注释、花括号
            [[ -z "$key" || "$key" == "{" || "$key" == "}" || "$key" =~ ^// ]] && continue
            [[ -z "$value" ]] && continue

            CLOUDFLARED_CMD="$CLOUDFLARED_CMD --$key $value"
        done < "$CLOUDFLARED_CONF"
    fi

    echo "启动 cloudflared："
    echo "$CLOUDFLARED_CMD"

    $CLOUDFLARED_CMD >cloudflared.log 2>&1 &
    CLOUDFLARED_LOG="cloudflared.log"
fi


# ==========================
# 日志前台输出（优先级 x-tunnel > xray > cloudflared > dns-proxy）
if [[ -n "$XTUNNEL_LOG" ]]; then
    tail -f "$XTUNNEL_LOG"
elif [[ -n "$XRAY_LOG" ]]; then
    tail -f "$XRAY_LOG"
elif [[ -n "$CLOUDFLARED_LOG" ]]; then
    tail -f "$CLOUDFLARED_LOG"
elif [[ -n "$DNS_PROXY_LOG" ]]; then
    tail -f "$DNS_PROXY_LOG"
fi
