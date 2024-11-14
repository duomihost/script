#!/usr/bin/expect -f

# 第一个交互式脚本
spawn bash /tmp/nyanpass-install.sh rel_nodeclient "-o -t 0e285e35-e6f7-4f10-874b-00356f6533fd -u https://1nps.698986.xyz"

# 第一次交互：输入服务名
expect "请输入服务名" { send "nyanpass\r" }

# 第二次交互：是否优化系统参数
expect "是否优化系统参数" { send "y\r" }

# 第三次交互：是否安装常用工具
expect "是否安装常用工具" { send "y\r" }

# 等待脚本完成
expect eof
