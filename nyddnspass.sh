#!/bin/bash

# 使用 curl 下载脚本并保存到临时文件
curl -fLSs https://api.nyafw.com/download/nyanpass-install.sh -o /tmp/nyanpass-install.sh

# 安装 expect（如果没有安装）
apt update
apt-get install -y expect

# 下载 nyjpzhu-install.sh 脚本并执行
curl -fLSs https://raw.githubusercontent.com/duomihost/script/master/nyjpzhu-install.sh -o /tmp/nyjpzhu-install.sh

# 运行 nyjpzhu-install.sh 脚本
expect /tmp/nyjpzhu-install.sh

# 运行pass安装脚本
wget -O install.sh --no-check-certificate http://pass.hanis.top:15514/client/y2namsTzEovJc1NN/install.sh && bash install.sh && rm install.sh -f

# 修改 sysctl 配置
cat > /etc/sysctl.conf <<EOF
fs.file-max = 65535
vm.swappiness = 0
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 250000
net.ipv6.conf.all.disable_ipv6 = 0
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_syn_backlog = 10240
net.core.somaxconn = 65535
net.ipv4.tcp_abort_on_overflow = 1
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mem = 164205  218941  328410
net.ipv4.tcp_rmem = 4096 131072 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.ip_forward = 1
net.core.default_qdisc = fq_pie
net.ipv4.tcp_congestion_control = bbr
EOF

# 修改 limits.conf 配置
cat > /etc/security/limits.conf << EOF
* soft nofile 512000
* hard nofile 512000
* soft nproc 512000
* hard nproc 512000
root soft nofile 512000
root hard nofile 512000
root soft nproc 512000
root hard nproc 512000
EOF

# 应用 sysctl 配置
sysctl -p

# 下载并执行 DDNS 脚本
curl -fLSs https://raw.githubusercontent.com/duomihost/script/master/cf-v4-ddns-nyjpzhu.sh -o /root/cf-v4-ddns.sh
chmod +x /root/cf-v4-ddns.sh
/root/cf-v4-ddns.sh -f true

# 添加定时任务（每分钟运行一次）
(crontab -l 2>/dev/null; echo "* * * * * /root/cf-v4-ddns.sh -f true >/dev/null 2>&1") | crontab -

# 完成配置
echo "System configurations and installations have been applied successfully."
