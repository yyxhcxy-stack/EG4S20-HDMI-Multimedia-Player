# EG4S20-HDMI-Multimedia-Player

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![FPGA](https://img.shields.io/badge/FPGA-Anlogic_EG4S20BG256-brightgreen.svg)](https://www.anlogic.com/)
[![EDA](https://img.shields.io/badge/EDA-Tang_Dynasty_6.2+-orange.svg)](https://www.anlogic.com/)
[![Video Output](https://img.shields.io/badge/Resolution-640x480%4060Hz-purple.svg)]()
[![Audio Output](https://img.shields.io/badge/Audio-48kHz_24--bit_PCM-red.svg)]()
[![Power](https://img.shields.io/badge/Power-1.187W_Low_Power-success.svg)]()

> **基于国产安路科技 EG4S20BG256 FPGA 的高保真文博展陈与应急播控多媒体系统**  
> 全国大学生嵌入式芯片与系统设计竞赛（FPGA 赛道）开源工程

---

## 📖 项目简介

本项目完全基于国产自主可控的 **安路科技 EG4S20BG256 FPGA**（合封 64Mbit SDRAM），采用全硬件流水线设计，实现了一套面向文博展陈、金石碑拓鉴赏及应急广播的多媒体综合处理系统。

整机满载功耗仅为 **1.187W**（5V @ 237mA，静态 0.40W），无需风扇纯被动散热，硬件时序严格收敛，具备断电秒启的非易失固化运行能力。

---

## 🌟 核心特性与架构亮点

### 1. 视音频流处理引擎
* **高清视频输出**：全硬件驱动 HDMI 1.4b 接口，标准 640×480 @ 60Hz 24-bit TrueColor 输出；
* **异形分辨率自适应定比与满屏缩放**：硬件定点除法器动态解析 BMP 头信息，支持 480×272、800×600、1024×768 等非标图自适应缩放；
* **无缝流式转场特效**：硬件管线支持淡入淡出 (Fade)、百叶窗 (Blind)、左右滑动 (Slide)、方块消融 (Mosaic) 4 种无撕裂流式转场；
* **金石拓片与 ISP 色彩平衡**：集成 3×3 Sobel 实时边缘算子与可调冷暖色调、S 曲线对比度增强；
* **曾侯乙编钟雅乐 DDS 合成**：物理建模双音 DDS 雅乐播放，音画同步锁相；
* **16 频段实时滑窗频谱 (SDFT)**：自研 Sliding DFT 引擎，毫秒级响应，驱动 HDMI 动态柱状图、示波器波形及外设数码管 VU 电平联动；
* **64KB 片上真人普通话语音播控**：固化 16 块 ERAM32K 片上高保真语音，带硬件线性插值平滑滤波。

### 2. 双屏遥测与交互式中控
* **双屏联动**：主屏 HDMI 640×480 与 1.8 寸 ST7735 SPI 彩色副屏遥测数据实时同步；
* **超轻量低功耗护眼优化**：
  - ST7735 副屏：762.9Hz、50% 占空比超轻量硬件 PWM 背光调光，光线舒适柔和，电流减半；
  - 6位数码管：200Hz 动态扫描叠加 50% 占空比关断斩波，彻底消除动态鬼影并显著降耗。

---

## 🛠 硬件与引脚说明

| 外设模块 | 接口类型 | FPGA 对应引脚 / 资源 | 说明 |
| :--- | :--- | :--- | :--- |
| **片上 SDRAM** | 合封 SIP | 内部集成 64Mbit SDRAM | 32-bit @ 100MHz 乒乓双缓冲 |
| **HDMI 接口** | DVI / TMDS | `B14/A14`(CLK), `B15/A15`(D0), `B16/A16`(D1), `C16/C15`(D2) | 640×480@60Hz 像素时钟 25.175MHz |
| **TF / MicroSD 卡**| SPI 模式 | `D14`(CLK), `C14`(MOSI), `M13`(MISO), `F14`(CS) | 读取 FAT32 格式 BMP 图片 |
| **ST7735 LCD** | SPI 模式 | J1 排针：`P2`(SCL), `N3`(SDA), `N4`(RES), `M4`(DC), `M3`(CS), `K3`(BLK)| 1.8寸彩色副屏实时状态遥测 |
| **6位数码管** | 动态扫描 | 段码 `B1/C2/C1/E3/E4/D3/B2/B3`，位码 `E5/D5/D6/C5/C6/C7` | 遥测参数、VU 电平与模式显示 |
| **独立按键** | 消抖输入 | `K14`(KEY1), `K15`(KEY2), `K16`(KEY3), `J16`(KEY4) | 切换、转场模式锁定、OSD 呼出 |
| **蜂鸣器** | PWM 驱动 | `H14`(BUZZER) | 1.2kHz~2.4kHz 报警与提示音 |

---

## 🚀 快速开始

### 方式 A：免开发环境，直接烧录预编译位流（推荐体验）
1. 准备一张 MicroSD 卡，格式化为 **FAT32**，将 `sd_card_assets/` 目录下的 BMP 图片复制到 TF 卡根目录，插回开发板卡槽；
2. 连接开发板 Type-C 数据线与 HDMI 显示器；
3. 双击运行根目录下的脚本：
   - **【一键固化_Flash永久.bat】**：烧写至片外 SPI Flash，断电不丢失，冷启秒自启；
   - **【一键烧录_SRAM临时.bat】**：快速写入片上 SRAM 临时体验。

### 方式 B：使用安路 Tang Dynasty 源码编译
1. 打开 **Tang Dynasty (TD 6.2 或 6.2.1)**；
2. 点击 **Project -> Open Project**，定位并选中 `prj/HX4S20_HDMI_Player.al`；
3. 点击菜单栏 **Process -> Run All**（或在命令行双击运行【一键全流程编译.bat】）；
4. 综合与布局布线完成后，输出比特流 `HX4S20_HDMI_Player.bit`。

---

## 📁 目录结构

```
├── src/                                  # Verilog RTL 核心源代码与约束
│   ├── rtl/                              # 视音频流处理、SDRAM乒乓缓冲、DDS、OSD等
│   └── constrs/                          # 引脚约束 (pin.adc) 与时序约束 (.sdc)
├── prj/                                  # 安路 Tang Dynasty 工程定义与 IP 核
│   ├── al_ip/                            # PLL 时钟倍频、音频 ROM 等 IP 实例
│   └── HX4S20_HDMI_Player.al             # 顶层工程文件
├── tools/                                # Python 遥测算法验证与 ModelSim 仿真测试套件
├── releases/                             # 预编译黄金比特流与 SHA256 校验指纹
│   ├── HX4S20_HDMI_Player.bit            # 最新已验证比特流 (SHA256: 14D999F85A3EA59EC62F6BA4A1CFF95D8E2604BB2A4C6B3D5529908F4418A8EF)
│   └── checksums.sha256                  # 完整校验和
├── sd_card_assets/                       # TF 卡预置示例测试图片 (BMP 格式)
├── 一键全流程编译.bat                     # 一键调用 TD CLI 综合与布线
├── 一键固化_Flash永久.bat                 # 一键固化片外 SPI Flash 脚本
├── 一键烧录_SRAM临时.bat                  # 一键 SRAM 即时调试下载脚本
├── 一键推送到GitHub.bat                   # 辅助开发者一键同步推送到个人 GitHub 仓库
├── LICENSE                               # Apache-2.0 开源协议
└── README.md                             # 项目技术全景说明文档
```

---

## 📄 开源许可证

本项目基于 [Apache License 2.0](LICENSE) 协议开源。欢迎学习、交流与二次开发。
