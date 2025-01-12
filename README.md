# TCP-Optimization-Tool 

## 简介
一个半自动化的TCP调优工具，根据iperf3的测试结果进行动态调优

技术细节请移步：https://www.nodeseek.com/post-197087-1

更新日志请移步：https://www.nodeseek.com/post-200517-1

## 快速使用

### 1. 客户端安装iperf3

Windows：https://github.com/ar51an/iperf3-win-builds/releases/download/3.17.1/iperf-3.17.1-win64.zip

其他系统：https://iperf.fr/iperf-download.php

解压后在 iperf3.exe 所在目录运行cmd即可

### 2. 服务端一键运行

```
wget -q https://raw.githubusercontent.com/BlackSheep-cry/TCP-Optimization-Tool/main/tool.sh -O tool.sh && chmod +x tool.sh && ./tool.sh
````

***下面的是仅调节发送缓冲区的版本，如果你不了解参数含义，请使用上面的版本***
```
wget -q https://raw.githubusercontent.com/BlackSheep-cry/TCP-Optimization-Tool/main/toolx.sh -O toolx.sh && chmod +x toolx.sh && ./toolx.sh
````
## 功能特点
- 一键启用bbr+fq算法

- TCP缓冲区参数调优

- 提升单线程速度

- 简便易用，跟随指示即可轻松完成调优

- 基于iperf3测试结果进行调优

## 许可证
MIT License
