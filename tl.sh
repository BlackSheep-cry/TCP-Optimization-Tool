#!/bin/bash   

echo "注意：半自动调参功能不再进行维护，建议使用自由调整"
echo "选择方案："
echo "1. 半自动调参A(直接调参)"
echo "2. 半自动调参B(TC限速+大参数)"
echo "0. 退出脚本"

read -p "请输入方案编号: " choice

case "$choice" in
  1)
    echo "方案一：半自动调参A(直接调参)"
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

    # 初始 new_value 赋值
    new_value=$bdp

    # 调整tcp_wmem 和 tcp_rmem
    sysctl -w net.ipv4.tcp_wmem="4096 16384 $new_value"
    sysctl -w net.ipv4.tcp_rmem="4096 87380 $new_value"
    echo "--------------------------------------------------"

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
    echo "请在客户端执行以下命令测试："
    echo "iperf3 -c $local_ip -R -t 30 -p $iperf_port"
    echo "--------------------------------------------------"

    # 获取用户输入的Retr数值，并确保输入有效
    while true; do
        read -p "请输入iperf3测试结果中的Retr数目: " retr
        # 验证输入是否为大于或等于0的数字
        if [[ "$retr" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "无效输入，请输入一个大于或等于零的整数作为Retr数目"
        fi
    done

    # 步骤一：重传≤100时，上调3MiB
    while [ "$retr" -le 100 ]; do
        echo "重传≤100，上调3MiB"
        new_value=$((new_value + 3 * 1024 * 1024))  # 每次上调3MiB
        sysctl -w net.ipv4.tcp_wmem="4096 16384 $new_value"
        sysctl -w net.ipv4.tcp_rmem="4096 87380 $new_value"
        echo "请执行以下命令进行iperf3测试："
        echo "iperf3 -c $local_ip -R -t 30 -p $iperf_port"
        read -p "请输入Retr数: " retr
        echo "--------------------------------------------------"
        
        # 确保Retr数有效
        while [[ ! "$retr" =~ ^[0-9]+$ ]] || [ "$retr" -lt 0 ]; do
            echo "无效输入，请输入一个大于或等于零的整数作为Retr数目"
            read -p "请输入Retr数: " retr
        done

        # 如果重传数超过100，进入步骤二
        if [ "$retr" -gt 100 ]; then
            break
        fi
    done

    # 步骤二：重传>100时，下调1MiB
    while [ "$retr" -gt 100 ]; do
        echo "重传>100，下调1MiB"
        new_value=$((new_value - 1024 * 1024))  # 每次下调1MiB
        sysctl -w net.ipv4.tcp_wmem="4096 16384 $new_value"
        sysctl -w net.ipv4.tcp_rmem="4096 87380 $new_value"
        echo "请执行以下命令进行iperf3测试："
        echo "iperf3 -c $local_ip -R -t 30 -p $iperf_port"
        read -p "请输入Retr数: " retr
        echo "--------------------------------------------------"

        # 确保Retr数有效
        while [[ ! "$retr" =~ ^[0-9]+$ ]] || [ "$retr" -lt 0 ]; do
            echo "无效输入，请输入一个大于或等于零的整数作为Retr数目"
            read -p "请输入Retr数: " retr
        done

        # 如果重传数≤ 100，跳出循环进入下一环节
        if [ "$retr" -le 100 ]; then
            break
        fi
    done

    # 写入sysctl.conf
    echo "net.ipv4.tcp_wmem=4096 16384 $new_value" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_rmem=4096 87380 $new_value" >> /etc/sysctl.conf
    sysctl -p

    # 停止iperf3服务端进程
    echo "停止iperf3服务端进程..."
    pkill iperf3

    echo "--------------------------------------------------"
    echo "脚本执行完毕！"
    ;;
  2)
    echo "方案二：半自动调参B(TC限速+大参数)"

    # 获取用户输入的带宽并确保输入有效
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

    echo "--------------------------------------------------"
    echo "本机带宽：$local_bandwidth Mbps"
    echo "对端带宽：$server_bandwidth Mbps"
    echo "--------------------------------------------------"

    # 修改 sysctl.conf 并应用
    echo "net.ipv4.tcp_wmem=4096 16384 67108864" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_rmem=4096 87380 67108864" >> /etc/sysctl.conf
    sysctl -p

    # 显示当前网卡信息，让用户选择
    echo "当前网卡列表："
    ip link show
    echo "请根据以上列表输入用于互联网通信的网卡名称（一般名为 eth0，通常是第二个）"
    read -p "请输入网卡名称：" second_nic
    echo "--------------------------------------------------"

    # 检查网卡是否存在
    while true; do
        if ip link show "$second_nic" &>/dev/null; then
            break
        else
            # 提示用户输入错误并重新输入
            echo "错误：网卡 $second_nic 不存在，请检查输入并确保网卡已启用！"
            read -p "请输入正确的网卡名称: " second_nic
        fi
    done

    # 获取带宽值
    bandwidth_new=$((local_bandwidth < server_bandwidth ? local_bandwidth : server_bandwidth))
    echo "配置 Traffic Control，带宽为：${bandwidth_new} Mbps"

    # 配置 Traffic Control
    echo "配置Traffic Control..."
    tc qdisc del dev $second_nic root
    tc qdisc add dev $second_nic root handle 1:0 htb default 10
    tc class add dev $second_nic parent 1:0 classid 1:1 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit
    tc filter add dev $second_nic protocol ip parent 1:0 prio 1 u32 match ip src 0.0.0.0/0 flowid 1:1
    tc class add dev $second_nic parent 1:0 classid 1:2 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit
    tc filter add dev $second_nic protocol ip parent 1:0 prio 1 u32 match ip dst 0.0.0.0/0 flowid 1:2

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
    echo "请在客户端执行以下命令测试："
    echo "iperf3 -c $local_ip -R -t 30 -p $iperf_port"
    echo "--------------------------------------------------"

    # 获取用户输入的Retr数值，并确保输入有效
    while true; do
        read -p "请输入iperf3测试结果中的Retr数目: " retr
        # 验证输入是否为大于或等于0的数字
        if [[ "$retr" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "无效输入，请输入一个大于或等于零的整数作为Retr数目"
        fi
    done

    echo "--------------------------------------------------"

    # 步骤一：如果 Retr ≤ 100，上调限速值
    while [ "$retr" -le 100 ]; do
        bandwidth_new=$((bandwidth_new + 100))
        echo "重传≤100，限速值+100Mbps"

        # 配置新的限速值
        tc class change dev $second_nic classid 1:1 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit
        tc class change dev $second_nic classid 1:2 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit

        # 显示限速值调整结果
        echo "已调整限速值，新的限速值为：$bandwidth_new Mbps"
        
        # 等待用户输入新的 Retr 值
        read -p "请重新执行 iperf3 测试，并输入新的 Retr 值：" retr

        # 确保Retr数有效
        while [[ ! "$retr" =~ ^[0-9]+$ ]] || [ "$retr" -lt 0 ]; do
            echo "无效输入，请输入一个大于或等于零的整数作为Retr数目"
            read -p "请输入Retr数: " retr
        done

        echo "--------------------------------------------------"

        # 如果重传数超过100，进入步骤二
        if [ "$retr" -gt 100 ]; then
            break
        fi
    done

    # 步骤二：重传>100 时，下调限速值
    while [ "$retr" -gt 100 ]; do
        bandwidth_new=$((bandwidth_new - 50))
        echo "重传>100，限速值-50Mbps"

        # 配置新的限速值
        tc class change dev $second_nic classid 1:1 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit
        tc class change dev $second_nic classid 1:2 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit

        # 显示限速值调整结果
        echo "已调整限速值，新的限速值为：$bandwidth_new Mbps"

        # 等待用户输入新的 Retr 值
        read -p "请重新执行 iperf3 测试，并输入新的 Retr 值：" retr

        # 确保Retr数有效
        while [[ ! "$retr" =~ ^[0-9]+$ ]] || [ "$retr" -lt 0 ]; do
            echo "无效输入，请输入一个大于或等于零的整数作为Retr数目"
            read -p "请输入Retr数: " retr
        done

        echo "--------------------------------------------------"

        # 如果重传数≤ 100，跳出循环进入下一环节
        if [ "$retr" -le 100 ]; then
            break
        fi
    done

    # 写入 rc.local 以实现开机自启
    echo "" | tee /etc/rc.local > /dev/null
    echo "#!/bin/bash" > /etc/rc.local
    echo "tc qdisc add dev $second_nic root handle 1:0 htb default 10" >> /etc/rc.local
    echo "tc class add dev $second_nic parent 1:0 classid 1:1 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit" >> /etc/rc.local
    echo "tc filter add dev $second_nic protocol ip parent 1:0 prio 1 u32 match ip src 0.0.0.0/0 flowid 1:1" >> /etc/rc.local
    echo "tc class add dev $second_nic parent 1:0 classid 1:2 htb rate ${bandwidth_new}mbit ceil ${bandwidth_new}mbit" >> /etc/rc.local
    echo "tc filter add dev $second_nic protocol ip parent 1:0 prio 1 u32 match ip dst 0.0.0.0/0 flowid 1:2" >> /etc/rc.local
    echo "exit 0" >> /etc/rc.local

    chmod +x /etc/rc.local

    echo "Traffic Control 配置已完成"

    # 停止 iperf3 服务端进程
    echo "停止 iperf3 服务端进程..."
    kill $iperf3_pid
    echo "iperf3 服务端进程已停止"
    echo "--------------------------------------------------"
    echo "脚本执行完毕！"
    ;;
  0)
    echo "退出脚本"
    exit 0
    ;;
  *)
    echo "无效选择"
    exit 0
    ;;
esac
