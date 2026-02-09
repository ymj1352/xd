#!/bin/bash
set -e
#======== 下载xray ======== 
curl -L -f --retry 3 \
  https://dufs.f.mfs.cc.cd/data/xray.tar.gz \
  -o xray.tar.gz

tar -xzf xray.tar.gz
rm xray.tar.gz
if [ ! -f /root/config.json ]; then
    mv ./config.json /root/
fi

chmod +x xray

#======== 下载dns-proxy ======== 
curl -L -f --retry 3 \
  https://dufs.f.mfs.cc.cd/data/dns-proxy/dns-proxy \
  -o dns-proxy && chmod +x dns-proxy
curl -L -f --retry 3 \
  https://dufs.f.mfs.cc.cd/data/dns-proxy/gfwlist.txt \
  -o gfwlist.txt

ls


echo "启动 x-tunnel 客户端..."
./xray run -config /root/config.json >xray.log 2>&1 &
sleep 3

echo "启动 dns-proxy客户端..."
./dns-proxy >dns-proxy.log 2>&1 &

echo "============================================"
echo "部署成功！请访问http://IP:10000配置"
echo "代理地址请改为socks5://127.0.0.1:3000"
echo ""
echo "============================================"

tail -f xray.log  #dns-proxy.log
