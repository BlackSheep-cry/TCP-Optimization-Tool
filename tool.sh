#!/usr/bin/env bash  

# 提醒使用者
echo "--------------------------------------------------"
echo "TCP调优脚本-V25.04.27-BlackSheep"
echo "原帖链接：https://www.nodeseek.com/post-197087-1"
echo "更新日志：https://www.nodeseek.com/post-200517-1"
echo "--------------------------------------------------"
echo "请阅读以下注意事项："
echo "1. 此脚本的TCP调优操作对劣质线路无效"
echo "2. 小带宽或低延迟场景下，调优效果不显著"
echo "3. 请尽量在晚高峰进行调优"
echo "--------------------------------------------------"

# 检查TCP拥塞控制算法与队列管理算法
current_cc=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
current_qdisc=$(sysctl net.core.default_qdisc | awk '{print $3}')

if [[ "$current_cc" != "bbr" ]]; then
    echo "当前TCP拥塞控制算法: $current_cc，未启用BBR，尝试启用BBR..."
    sed -i '/^net\.ipv4\.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
fi

if [[ "$current_qdisc" != "fq_codel" ]]; then
    echo "当前队列管理算法: $current_qdisc，未启用fq_codel，尝试启用fq_codel..."
    sed -i '/^net\.core\.default_qdisc/d' /etc/sysctl.conf
    echo "net.core.default_qdisc=fq_codel" >> /etc/sysctl.conf
    sysctl -p
fi

# 检查iperf3是否已安装
if ! command -v iperf3 &> /dev/null; then
    echo "iperf3未安装，开始安装iperf3..."
    if [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y iperf3
    elif [ -f /etc/redhat-release ]; then
        yum install -y iperf3
    else
        echo "安装iperf3失败，请自行安装"
        exit 1
    fi
else
    echo "iperf3已安装，跳过安装过程"
fi

# 检查 nohup 是否已安装
if ! command -v nohup &> /dev/null; then
    echo "nohup 未安装，正在安装..."
    if [ -f /etc/debian_version ]; then
        apt-get update && apt-get install -y coreutils
    elif [ -f /etc/redhat-release ]; then
        yum install -y coreutils
    else
        echo "安装nohup失败，请自行安装"
        exit 1
    fi
else
    echo "nohup已安装，跳过安装过程"
fi

# 查询并输出当前的TCP缓冲区参数大小
echo "--------------------------------------------------"
echo "当前TCP缓冲区参数大小如下："
sysctl net.ipv4.tcp_wmem
sysctl net.ipv4.tcp_rmem
echo "--------------------------------------------------"

clear_conf() {
    sed -i '/^net\.ipv4\.tcp_wmem/d' /etc/sysctl.conf
    sed -i '/^net\.ipv4\.tcp_rmem/d' /etc/sysctl.conf
    if [ -n "$(tail -c1 /etc/sysctl.conf)" ]; then
        echo "" >> /etc/sysctl.conf
    fi
}

read_limit_1() {
                echo "当前网卡列表："
                ip link show
                read -p "请输入要限速的网卡名称: " nic_name
                if ! ip link show $nic_name &>/dev/null; then
                        echo "错误：网卡 $nic_name 不存在"
                        continue
                fi

                echo "选择限速方向："
                echo "1) 上传"
                echo "2) 下载"
                echo "3) 全部"
                read -p "请输入选项 [1-3]: " direction
                if [[ ! "$direction" =~ ^[1-3]$ ]]; then
                        echo "无效选项"
                        continue
                fi
                
                if [[ "$direction" -eq 1 || "$direction" -eq 3 ]]; then
                        while true; do
                                read -p "请输入上传总限速值 (Mbps): " upload_rate
                                if [[ "$upload_rate" =~ ^[0-9]+$ ]] && [ "$upload_rate" -gt 0 ]; then
                                        break
                                fi
                                echo "无效输入，请输入正整数"
                        done
                        echo "设置上传限速: ${upload_rate}Mbps"
                fi

                if [[ "$direction" -eq 2 || "$direction" -eq 3 ]]; then
                        while true; do
                                read -p "请输入下载总限速值 (Mbps): " download_rate
                                if [[ "$download_rate" =~ ^[0-9]+$ ]] && [ "$download_rate" -gt 0 ]; then
                                        break
                                fi
                                echo "无效输入，请输入正整数"
                        done
                        echo "设置下载限速: ${download_rate}Mbps"
                fi

                cat > /etc/rc.local <<EOF
#!/bin/bash
EOF
}

read_limit_2() {
                while true; do
                        read -p "是否对单个流 (可简单理解为单线程) 进行限速 ? [y/n]: " perflow_choice
                        case "$perflow_choice" in
                                [Yy]*)
                                        use_perflow=1

                                        if [[ "$direction" -eq 1 || "$direction" -eq 3 ]]; then
                                                while true; do
                                                        read -p "请输入单个流的上传限速值 (Mbps): " upload_perflow
                                                        if [[ "$upload_perflow" =~ ^[0-9]+$ ]] && [ "$upload_perflow" -gt 0 ]; then
                                                                break
                                                        fi
                                                        echo "无效输入，请输入正整数"
                                                done
                                        fi

                                        if [[ "$direction" -eq 2 || "$direction" -eq 3 ]]; then
                                                while true; do
                                                        read -p "请输入单个流的下载限速值 (Mbps): " download_perflow
                                                        if [[ "$download_perflow" =~ ^[0-9]+$ ]] && [ "$download_perflow" -gt 0 ]; then
                                                                break
                                                        fi
                                                        echo "无效输入，请输入正整数"
                                                done
                                        fi

                                        break;;
                                [Nn]*) use_perflow=0; break;;
                                *) echo "请输入 y 或 n";;
                        esac
                done
}

tc_limit() {
                case $1 in
                   cake)
                       down_rule="cake bandwidth ${download_rate}mbit besteffort"
                       up_rule="cake bandwidth ${upload_rate}mbit besteffort"
                       ;;
                   fq)
                       down_rule="fq maxrate ${download_rate}mbit"
                       up_rule="fq maxrate ${upload_rate}mbit"
                       ;;
                esac

                if [[ "$direction" -eq 2 || "$direction" -eq 3 ]]; then
                        ip link add ifb0 type ifb 2>/dev/null
                        ip link set dev ifb0 up
                        tc qdisc del dev $nic_name ingress 2>/dev/null
                        tc qdisc del dev ifb0 root 2>/dev/null
                        tc qdisc add dev $nic_name handle ffff: ingress
                        tc filter add dev $nic_name parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
                        tc filter add dev $nic_name parent ffff: protocol ipv6 u32 match u32 0 0 action mirred egress redirect dev ifb0
                        tc qdisc add dev ifb0 root $down_rule
                        cat >> /etc/rc.local <<EOD
ip link add ifb0 type ifb
ip link set dev ifb0 up
tc qdisc add dev $nic_name handle ffff: ingress
tc filter add dev $nic_name parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
tc filter add dev $nic_name parent ffff: protocol ipv6 u32 match u32 0 0 action mirred egress redirect dev ifb0
tc qdisc add dev ifb0 root $down_rule
EOD
                fi

                if [[ "$direction" -eq 1 || "$direction" -eq 3 ]]; then
                        tc qdisc del dev $nic_name root 2>/dev/null
                        tc qdisc add dev $nic_name root $up_rule
                        cat >> /etc/rc.local <<EOD
tc qdisc add dev $nic_name root $up_rule
EOD
                fi

                cat >> /etc/rc.local <<EOF
exit 0
EOF

                chmod +x /etc/rc.local
}

load_script() {
    local url="$1"
    local tmpfile=$(mktemp)
    curl -sSL "$url" > "$tmpfile"
    bash "$tmpfile"
    rm -f "$tmpfile"
}

reset_tcp() {
    clear_conf
    sysctl -w net.ipv4.tcp_wmem="4096 16384 4194304"
    sysctl -w net.ipv4.tcp_rmem="4096 87380 6291456"
    echo "已将 net.ipv4.tcp_wmem 和 net.ipv4.tcp_rmem 重置为默认值"
}

reset_tc() {
    if [ -f /etc/rc.local ]; then
      > /etc/rc.local
      echo "#!/bin/bash" > /etc/rc.local
      chmod +x /etc/rc.local
      echo "已清空 /etc/rc.local 并添加基本脚本头部"
    else
      echo "/etc/rc.local 文件不存在，无需清理"
    fi

    echo "当前网卡列表："
    ip link show
    while true; do
      read -p "请根据以上列表输入被限速的网卡名称： " iface
      if ip link show $iface &>/dev/null; then
        break
      else
        echo "网卡名称无效或不存在，请重新输入"
      fi
    done

    if command -v tc &> /dev/null; then
      tc qdisc del dev $iface root 2>/dev/null
      tc qdisc del dev $iface ingress 2>/dev/null
      echo "已尝试清除网卡 $iface 的 tc 限速规则"
    else
      echo "tc 命令不可用，未执行限速清理"
    fi

    if ip link show ifb0 &>/dev/null; then
      tc qdisc del dev ifb0 root 2>/dev/null
      ip link set dev ifb0 down
      ip link delete ifb0
      echo "已删除 ifb0 网卡"
    else
      echo "ifb0 网卡不存在，无需删除"
    fi
}

echo "选择方案："
echo "1. 自由调整"
echo "2. 调整复原"
echo "3. 半自动调参 (不再维护)"
echo "0. 退出脚本"

read -p "请输入方案编号: " choice_main

# 主程序
case "$choice_main" in
  1)
    while true; do
        echo "方案四：自由调整"
        echo "请选择操作："
        echo "1. 后台启动iperf3"
        echo "2. TCP缓冲区max值设为BDP"
        echo "3. TCP缓冲区max值设为指定值"
        echo "4. 调整TCP缓冲区参数"
        echo "5. 设置TC限速(HTB)"
        echo "6. 设置TC限速(CAKE)"
        echo "7. 设置TC限速(FQ | 仅对单个流作限制)"
        echo ""
        echo "8. 重置TCP缓冲区参数"
        echo "9. 清除TC限速"
        echo "0. 结束iperf3进程并退出"
        echo "--------------------------------------------------"

        read -p "请输入选择: " sub_choice

        case "$sub_choice" in
            1)
                # 获取本机IP地址
                local_ip=$(wget -qO- --inet4-only http://icanhazip.com 2>/dev/null)

                if [ -z "$local_ip" ]; then
                    local_ip=$(wget -qO- http://icanhazip.com)
                fi

                echo "您的出口IP是: $local_ip"
                echo "--------------------------------------------------"

                while true; do
                    # 提示用户输入端口号
                    read -p "请输入用于 iperf3 的端口号（默认 5201，范围 1-65535）： " iperf_port
                    iperf_port=${iperf_port// /}  # 去掉用户输入中的空格
                    iperf_port=${iperf_port:-5201}  # 如果用户未输入，则使用默认值

                    # 检查端口号是否有效
                    if [[ "$iperf_port" =~ ^[0-9]+$ ]] && [ "$iperf_port" -ge 1 ] && [ "$iperf_port" -le 65535 ]; then
                        echo "端口 $iperf_port 有效，继续执行下一步"
                        break
                    else
                        echo "无效的端口号！请输入 1 到 65535 范围内的数字"
                    fi
                done
                echo "--------------------------------------------------"

                # 启动 iperf3 服务端
                echo "启动 iperf3 服务端，端口：$iperf_port..."
                nohup iperf3 -s -p $iperf_port > /dev/null 2>&1 &  # 使用指定端口启动 iperf3 服务
                iperf3_pid=$!
                echo "iperf3 服务端启动，进程 ID：$iperf3_pid"
                echo "可在客户端使用以下命令测试："
                echo "iperf3 -c $local_ip -R -t 30 -p $iperf_port"
                ;;
            2)
                # 获取用户输入的带宽和延迟，并确保输入有效
                while true; do
                    read -p "请输入本机带宽 (Mbps): " local_bandwidth
                    # 验证输入是否为正整数
                    if [[ "$local_bandwidth" =~ ^[1-9][0-9]*$ ]]; then
                        break
                    else
                        echo "无效输入，请输入一个正整数作为本机带宽 (Mbps)"
                    fi
                done

                while true; do
                    read -p "请输入对端带宽 (Mbps): " server_bandwidth
                    # 验证输入是否为正整数
                    if [[ "$server_bandwidth" =~ ^[1-9][0-9]*$ ]]; then
                        break
                    else
                        echo "无效输入，请输入一个正整数作为对端带宽 (Mbps)"
                    fi
                done

                while true; do
                    read -p "请输入往返时延/Ping值 (RTT, ms): " rtt
                    # 验证输入是否为正整数
                    if [[ "$rtt" =~ ^[1-9][0-9]*$ ]]; then
                        break
                    else
                        echo "无效输入，请输入一个正整数作为往返时延 (ms)"
                    fi
                done

                echo "--------------------------------------------------"
                echo "本机带宽：$local_bandwidth Mbps"
                echo "对端带宽：$server_bandwidth Mbps"
                echo "往返时延/Ping值：$rtt ms"
                echo "--------------------------------------------------"

                # 计算BDP（带宽延迟积）
                min_bandwidth=$((local_bandwidth < server_bandwidth ? local_bandwidth : server_bandwidth))
                bdp=$((min_bandwidth * rtt * 1000 / 8))
                echo "您的理论值为: $bdp 字节"
                echo "--------------------------------------------------"

               # 设置TCP缓冲区max值为BDP
                echo "设置TCP缓冲区max值为BDP值: $bdp bytes"
                clear_conf
                echo "net.ipv4.tcp_wmem=4096 16384 $bdp" >> /etc/sysctl.conf
                echo "net.ipv4.tcp_rmem=4096 87380 $bdp" >> /etc/sysctl.conf
                sysctl -p
                ;;
            3)
                while true; do
                    read -p "请输入指定值(MiB): " tcp_value
                    if [[ "$tcp_value" =~ ^[1-9][0-9]*$ ]]; then
                        break
                    else
                        echo "无效输入，请输入一个正整数"
                    fi
                done

                value=$((tcp_value * 1024 * 1024))
                echo "设置TCP缓冲区max值为$tcp_valueMiB: $value bytes"
                clear_conf
                echo "net.ipv4.tcp_wmem=4096 16384 $value" >> /etc/sysctl.conf
                echo "net.ipv4.tcp_rmem=4096 87380 $value" >> /etc/sysctl.conf
                sysctl -p
                ;;
            4)
                # 显示当前值
                current_wmem=$(sysctl net.ipv4.tcp_wmem | awk '{print $NF}')
                current_rmem=$(sysctl net.ipv4.tcp_rmem | awk '{print $NF}')
                echo "当前TCP发送缓冲区max值：$current_wmem bytes"
                echo "当前TCP接收缓冲区max值：$current_rmem bytes"

                # 获取调整值
                while true; do
                    read -p "请输入发送缓冲区要增加或减少的值(MiB，使用正数增加，负数减少): " adjust_value
                    if [[ "$adjust_value" =~ ^[+-]?[0-9]+$ ]]; then
                        break
                    else
                        echo "无效输入，请输入一个整数"
                    fi
                done

                while true; do
                    read -p "请输入接收缓冲区要增加或减少的值(MiB，使用正数增加，负数减少): " adjust_value_2
                    if [[ "$adjust_value_2" =~ ^[+-]?[0-9]+$ ]]; then
                        break
                    else
                        echo "无效输入，请输入一个整数"
                    fi
                done
                
                # 计算新值
                new_wmem=$((current_wmem + adjust_value * 1024 * 1024))
                new_rmem=$((current_rmem + adjust_value_2 * 1024 * 1024))
                if [ $new_wmem -lt 4096 ]; then
                    echo "错误：wmem新值小于最小允许值4096，操作取消"
                    continue
                fi
                
                if [ $new_rmem -lt 4096 ]; then
                    echo "错误：rmem新值小于最小允许值4096，操作取消"
                    continue
                fi

                # 应用新值
                echo "设置新的TCP缓冲区参数:"
                clear_conf
                echo "net.ipv4.tcp_wmem=4096 16384 $new_wmem" >> /etc/sysctl.conf
                echo "net.ipv4.tcp_rmem=4096 87380 $new_rmem" >> /etc/sysctl.conf
                sysctl -p
                ;;
            5)
                read_limit_1
                read_limit_2

                if [[ "$direction" -eq 2 || "$direction" -eq 3 ]]; then
                        ip link add ifb0 type ifb 2>/dev/null
                        ip link set dev ifb0 up
                        tc qdisc del dev $nic_name ingress 2>/dev/null
                        tc qdisc del dev ifb0 root 2>/dev/null
                        tc qdisc add dev $nic_name handle ffff: ingress
                        tc filter add dev $nic_name parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
                        tc filter add dev $nic_name parent ffff: protocol ipv6 u32 match u32 0 0 action mirred egress redirect dev ifb0
                        tc qdisc add dev ifb0 root handle 1:0 htb default 1
                        tc class add dev ifb0 parent 1:0 classid 1:1 htb rate ${download_rate}mbit ceil ${download_rate}mbit
                        tc filter add dev ifb0 protocol ip parent 1:0 prio 1 u32 match u32 0 0 flowid 1:1
                        tc filter add dev ifb0 protocol ipv6 parent 1:0 prio 2 u32 match u32 0 0 flowid 1:1
                        cat >> /etc/rc.local <<EOD
ip link add ifb0 type ifb
ip link set dev ifb0 up
tc qdisc add dev $nic_name handle ffff: ingress
tc filter add dev $nic_name parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
tc filter add dev $nic_name parent ffff: protocol ipv6 u32 match u32 0 0 action mirred egress redirect dev ifb0
tc qdisc add dev ifb0 root handle 1:0 htb default 1
tc class add dev ifb0 parent 1:0 classid 1:1 htb rate ${download_rate}mbit ceil ${download_rate}mbit
tc filter add dev ifb0 protocol ip parent 1:0 prio 1 u32 match u32 0 0 flowid 1:1
tc filter add dev ifb0 protocol ipv6 parent 1:0 prio 2 u32 match u32 0 0 flowid 1:1
EOD
                        if [[ "$use_perflow" -eq 1 ]]; then
                                tc qdisc add dev ifb0 parent 1:1 handle 10: fq maxrate ${download_perflow}mbit
                                cat >> /etc/rc.local <<EOD
tc qdisc add dev ifb0 parent 1:1 handle 10: fq maxrate ${download_perflow}mbit
EOD
                        fi
                fi

                if [[ "$direction" -eq 1 || "$direction" -eq 3 ]]; then
                        tc qdisc del dev $nic_name root 2>/dev/null
                        tc qdisc add dev $nic_name root handle 1:0 htb default 1
                        tc class add dev $nic_name parent 1:0 classid 1:1 htb rate ${upload_rate}mbit ceil ${upload_rate}mbit
                        tc filter add dev $nic_name protocol ip parent 1:0 prio 1 u32 match u32 0 0 flowid 1:1
                        tc filter add dev $nic_name protocol ipv6 parent 1:0 prio 2 u32 match u32 0 0 flowid 1:1
                        cat >> /etc/rc.local <<EOD
tc qdisc add dev $nic_name root handle 1:0 htb default 1
tc class add dev $nic_name parent 1:0 classid 1:1 htb rate ${upload_rate}mbit ceil ${upload_rate}mbit
tc filter add dev $nic_name protocol ip parent 1:0 prio 1 u32 match u32 0 0 flowid 1:1
tc filter add dev $nic_name protocol ipv6 parent 1:0 prio 2 u32 match u32 0 0 flowid 1:1
EOD
                        if [[ "$use_perflow" -eq 1 ]]; then
                                tc qdisc add dev $nic_name parent 1:1 handle 10: fq maxrate ${upload_perflow}mbit
                                cat >> /etc/rc.local <<EOD
tc qdisc add dev $nic_name parent 1:1 handle 10: fq maxrate ${upload_perflow}mbit
EOD
                        fi
                fi

                cat >> /etc/rc.local <<EOF
exit 0
EOF

                chmod +x /etc/rc.local
                ;;
            6)
                read_limit_1
                tc_limit "cake"
                ;;
            7)
                read_limit_1
                tc_limit "fq"
                ;;
            8)
                reset_tcp
                ;;
            9)
                reset_tc
                ;;
            0)
                echo "停止iperf3服务端进程..."
                pkill iperf3
                echo "退出脚本"
                break
                ;;
            *)
                echo "无效选择，请输入0-9之间的数字"
                ;;
        esac
        echo "--------------------------------------------------"
        read -p "按回车键继续..."
        echo "--------------------------------------------------"
    done
    ;;
  2)
    echo "调整复原"

    reset_tcp
    reset_tc

    echo "--------------------------------------------------"
    echo "复原已完成"
    ;;
  3)
    clear_conf
    load_script "https://raw.githubusercontent.com/BlackSheep-cry/TCP-Optimization-Tool/main/tl.sh"
    ;;
  0)
    echo "退出脚本"
    exit 0
    ;;
  *)
    echo "无效选择，请输入0-3之间的数字"
    ;;
esac
