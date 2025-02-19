# TCP-Optimization-Tool 

## 简介
一个较为灵活的TCP调优工具，依据iperf3测试结果进行调优

技术细节请移步：https://www.nodeseek.com/post-197087-1

更新日志请移步：https://www.nodeseek.com/post-200517-1

## 快速使用

### 1. 客户端安装iperf3

Windows：https://github.com/ar51an/iperf3-win-builds/releases/download/3.18/iperf-3.18-win64.zip

其他系统：https://iperf.fr/iperf-download.php

解压后在 iperf3.exe 所在目录运行cmd即可

### 2. 服务端运行脚本

```
wget -q https://raw.githubusercontent.com/BlackSheep-cry/TCP-Optimization-Tool/main/tool.sh -O tool.sh && chmod +x tool.sh && ./tool.sh
````

***下面是仅调节发送缓冲区的版本，如果你不了解其中的含义，请务必使用上面的版本***
```
wget -q https://raw.githubusercontent.com/BlackSheep-cry/TCP-Optimization-Tool/main/toolx.sh -O toolx.sh && chmod +x toolx.sh && ./toolx.sh
````
## 功能特点
- 一键启用bbr+fq算法

- 提高单线程速度、降低重传数

- 简便易用、自由灵活

- 基于iperf3测试结果

## 许可证
MIT License
