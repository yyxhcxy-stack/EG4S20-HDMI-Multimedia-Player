The following is a <SYSTEM_MESSAGE> not actually sent by the user. It is provided by the system as important information to pay attention to.

<SYSTEM_MESSAGE>
[Message] timestamp=2026-10-23T17:46:26Z sender=4dcfa3f7-7195-47df-93c6-e24e3c300981 priority=MESSAGE_PRIORITY_HIGH content=DeepInvestigator pipeline completed.

**Investigation Findings**:
# HX4S20 多媒体展示系统 —— 赛题要求与既有功能核对及精进拓展终极审查报告

**审查基准与工程基线**：
- **目标芯片与硬件平台**：国产安路科技 EG4S20BG256（HX4S20C 开发板）
- **工程源码根目录**：`C:\fpga\HX4S20_HDMI_Player_完整交付包_v2.8_方向4全适配\01_工程完整源码`
- **Git 当前验证基线**：Commit `41c6544`（Tag: `v2.21-minimal-fast-cut`）
- **物理资源与时序基准（实测 STA 与 Area 报表数据）**：
  - **LUT4 / LE**：17,673 / 19,600 (90.17%)，LE 18,567 / 19,600，MSLICE 占用率 ~98.5%
  - **BRAM9K**：43 / 64 (67.19%)，**剩余 21 块空闲**
  - **ERAM32K**：16 / 16 (100.0%)，全部 16 块已固化为 64KB 真人普通话应急广播 ROM
  - **DSP18**：25 / 29 (86.21%)，**剩余 4 个空闲**
  - **静态时序收敛 (STA)**：
    - `ext_mem_clk` (125MHz SDRAM 域)：SWNS = **+0.112ns**（零建立时间违例，闭合裕量紧致）
    - `clk` (50MHz 系统控制域)：SWNS = **+0.255ns**
    - `sd_card_clk` (100MHz TF卡域)：SWNS = **+0.216ns**
    - `video_clk` (25MHz 视频像素域)：SWNS = **+7.897ns**（单周期路径延迟长达 **31.751ns**，关键路径深度 20 级）
    - `audio_mclk` (12.288MHz 音频域)：SWNS = **+58.476ns**
    - **全时钟域建立时间零违例 (STNS = 0.000ns)，时序完全闭合**

---

## 一、 对前序调查报告（Prior Attempt）的审慎核查与证伪修正

通过对官方赛题任务书（`C:\fpga\saitijiexi.pdf`）、官方解析 PPT（`C:\fpga\saitijiexi.pptx`）、评分指南图片以及工程全部 RTL 源码的逐行比对与实证分析，发现前序调查报告存在以下 **7 项关键技术事实疏漏、逻辑偏差与重要代码未察**：

### 1. 【按键丝印与端口命名混淆】—— 现场评测致命隐患
- **前序报告说法**：声称“KEY1 手动下一张，KEY2 启停 3s 自动轮播，双击 KEY4 切换模式，长按 KEY4 触发全屏爆闪”。
- **实证代码反查**：
  查阅 [pin.adc](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/constrs/pin.adc#L21-L24) 与 [top_tf_hdmi_audio.v](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/top_tf_hdmi_audio.v#L348-L904)：
  - 板载丝印 **KEY1** 物理引脚为 `A2`，在代码中直接绑定为全局硬件复位 **`rst_n`**！现场若按丝印 KEY1，会瞬间导致整板重置；
  - 顶层端口 `key1`（引脚 `B2`）对应的板载硬件丝印实际是 **KEY2**（单击：切下一张；双击：调对比度；长按：切数码管显示模式）；
  - 顶层端口 `key3`（引脚 `B1`）对应的板载硬件丝印实际是 **KEY3**（单击：切缩放比；双击：调音量；三击：切 Alpha；长按：呼出虚拟配置菜单）；
  - 顶层端口 `key2`（引脚 `C1`）对应的板载硬件丝印实际是 **KEY4**（单击：启停自动轮播；双击：切转场特效；长按：触发真人火警广播与红蓝爆闪）。
- **修正结论**：前序报告将代码顶层端口变量名（`key1`..`key4`）与开发板物理丝印（`KEY1`..`KEY4`）生硬混用，若按其指引进行现场操作将直接误触板载复位键。

### 2. 【时序裕量误判与流水线插入陷阱】
- **前序报告说法**：“`video_clk` 时序裕量极为宽裕（WNS = +7.897ns），可自由安排 1~2 级触发器流水线；核心实施法则：新增视觉逻辑全部挂载在 +7.897ns 裕量的 25MHz 视频流水线上”。
- **实证代码反查**：
  查阅 [final_timing.rpt](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/build_ext_20261024_005455/prj/HX4S20_HDMI_Player_Runs/phy_1/final_timing.rpt#L89-L99) 与 [osd_display.v](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/osd_display.v#L2876-L3128)：
  `video_clk` 的关键路径延迟高达 **31.751ns**（40ns 时钟周期的 79.4%），包含 20 级逻辑（8个加法器 + 7个LUT4 + 3个LUT5 + 1个MULT18 DSP + 1个LUT3）！
  根本原因在于：`adj_rgb_p1` 是纯组合逻辑 `wire`（未打拍），路径直接从 `video_adjust_lut` BRAM 输出穿透色温加法器、穿透 OSD Alpha 乘法器（`hud_blended_r` DSP），再进入 23 选 1 的多路复用器。
- **修正结论**：**25MHz 视频域绝非“极为宽裕”，组合逻辑已近饱和**！严禁在该流水级追加任何深层组合逻辑，任何新增功能必须独立增加寄存器打拍流水级（Pipelined Stage），否则极易导致时序破闭。

### 3. 【未察觉的任务书悬空模块命名差异】
- **前序报告情况**：对任务描述中提及的 `video_scaler.v` 与 `inmp441_mic_receiver.v` 未做任何澄清与核验。
- **实证代码反查**：
  工程内实际不存在 `video_scaler.v` 与 `inmp441_mic_receiver.v` 这两个文件。缩放引擎实际解耦为 [`scaling_pipeline.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/scaling_pipeline.v)、[`scaling_core.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/scaling_core.v) 与 [`scaling_geometry.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/scaling_geometry.v)；麦克风与音频接收实际由 [`I2S_receiver.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/I2S_receiver.v) 承担。

### 4. 【代码死区未察：朱砂御拓（Cinnabar Rubbing）未接入】
- **前序报告说法**：“一键生成乌金墨拓（Dark Inkstone）与朱砂御拓（Cinnabar Rubbing）数字拓片”。
- **实证代码反查**：
  查阅 [video_sobel.v](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/video_sobel.v#L332-L365)：
  Line 335 定义了朱砂御拓像素 `cin_rubbing_pixel`（朱砂红 `24'h7A1414` + 御金笔画 `24'hFFE066`），但随后 Line 351~365 的 `active_color_mode` 多路选择器中，Mode 2 和 Mode 3 仅接入了 `ink_rubbing_pixel`（乌金墨拓），`cin_rubbing_pixel` 全局引用计数为 1，是一段**完全未被输出选择器引用的死代码（Dangling Wire）**！
- **修正结论**：当前工程实机并未输出朱砂御拓，将其接入正是本次精进拓展的极佳发力点。

### 5. 【官方 Slide 18 核心四阶状态码在顶层悬空（Unconnected Wire）】
- **前序报告说法**：“四阶状态码已在内部状态机处理，但可在 OSD 上显式增加状态文字”。
- **实证代码反查**：
  查阅 [bmp_read.v](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/SD/bmp_read.v#L370-L461) 与 [top_tf_hdmi_audio.v](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/top_tf_hdmi_audio.v#L98-L1168)：
  `bmp_read.v` 已经严格按照官方解析 PPT Slide 18 实现了四阶状态输出：
  - `4'd1`: 空闲 (IDLE)
  - `4'd2`: 搜索BMP (SEEK BMP)
  - `4'd3`: 写入SDRAM (BURST WRITE SDRAM)
  - `4'd4`: 完成/OSD叠加 (LOAD DONE / OSD OVERLAY)
  然而在 `top_tf_hdmi_audio.v` 中，`wire [3:0] state_code;` 仅连接在 `bmp_read` 的例化端口上，**没有任何后续代码使用它**！它既未送入 `osd_display.v`，也未送入 `seg_scan.v` 或 `lcd_st7735_telemetry.v`。
- **修正结论**：官方 PPT 第 18 页明确要求的“状态显示：1.空闲 2.搜索BMP 3.写入SDRAM 4.OSD叠加”，底层硬件早已就绪，但前端显示存在“最后一公里”的脱节。

### 6. 【音频共振特性被低估，盲目断定“音画不联动”】
- **前序报告说法**：“当前音频频谱跳动与视频画面各自独立，未能完全凸显赛题强调的‘音画节拍联动’”。
- **实证代码反查**：
  查阅 [osd_display.v](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/osd_display.v#L1499-L1550)：
  代码中不仅实现了音画联动，甚至构建了高阶的**文博五音画音共振识别**（`is_active_penta_band = (cur_img_idx == 0 && spec_bar_idx <= 2) || ...`）！当前画面的编钟阶位敲响时，对应频段顶帽会立刻高亮为黄金色，柱状条变为青铜琥珀渐变；并且当低频重音脉冲 `is_rhythm_beat` 到来时，示波器外轮廓瞬间从青色 `24'h00E5FF` 闪烁跃迁为编钟纯金 `24'hFFD700`，波形内部渐变色同步切换为青铜共鸣深翡翠色 `24'h0F2420`。
- **修正结论**：音画联动不仅早已存在，而且声学设计极为考究；精进方向应当是在全屏外边框或状态栏 Logo 级放大这种共鸣冲击力，而不是推翻重造。

### 7. 【转场特效位宽约束忽略】
- **前序报告说法**：提出在 `video_transition.v` 中直接增加“双向剧场幕布”和“菱形消融”。
- **实证代码反查**：
  查阅 [video_transition.v](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/video_transition.v#L18)：
  `input wire [1:0] mode` 仅为 2 位宽（已占满 4 种模式：0=平滑渐变, 1=百叶窗, 2=激光推进, 3=数字方块消融）。若直接添加新模式，必须将 `mode` 扩展为 3 位宽（支持最多 8 种特效），并同步修改顶层 FSM、按键切换逻辑、数码管覆盖段码与 ST7735 遥测协议；或者直接就地升级 Mode 1（将单向机械百叶窗重构为更具大剧院美感的对称双向开合幕布）。

---

## 二、 赛题官方要求与源码真实实现深度核验全貌

对照 2026 年嵌入式芯片与系统设计竞赛选题指南与官方解析 PPT，逐项深度核对源码落地点：

### 1. 【基础要求 4 项】核验全景

| 赛题基础要求 | 官方任务细则与指标要求 | 源码工程实现位置与核心证据 | 完成度与质量评估 |
| :--- | :--- | :--- | :--- |
| **基础 1：TF卡 BMP 读取与 HDMI 显示** | SPI 模式读取 TF 卡内 640×480、24-bit RGB 未压缩 BMP 图片，解析后通过 FIFO 写入 SDRAM 帧缓存，HDMI 接口实时 60Hz 稳定输出。 | - [`SD/bmp_read.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/SD/bmp_read.v#L53-L115): 严格校验 `0x424D`("BM")、DIB 40字节、`biBitCount=24`、`biCompression=0`，支持 4 字节行对齐填充补偿与扇区动态步进；<br>- [`SD/sdram.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/SD/sdram.v): 125MHz SDRAM 乒乓缓存仲裁；<br>- [`hdmi_phy_warpper.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/hdmi_phy_warpper.v): 4 路 LVDS33 驱动标准 640×480@60Hz HDMI 显示。 | **满分超越达成**<br>突破单张限制，支持上电全盘多扇区扫描，并完美适配最高 1024×768 异形非标图片硬解码。 |
| **基础 2：图片切换与轮播功能** | 支持按键手动切图与自动轮播，切换过程平稳连续，无明显闪烁、撕裂或画面异常。 | - [`top_tf_hdmi_audio.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/top_tf_hdmi_audio.v#L559-L930): 丝印 KEY2 单击下一张（30ms 脉冲）；丝印 KEY4 单击启停 3.0s 自动轮播；<br>- [`SD/frame_read_write.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/SD/frame_read_write.v): 垂直消隐期 VBLANK 原子锁步切换读基地址，配合 2 帧预充水。 | **100% 达成**<br>Commit `41c6544` 彻底去除了按键双击判定延迟，实机切图瞬时响应、零黑屏、零撕裂。 |
| **基础 3：HDMI 音频输出** | 通过 HDMI 接口输出 48kHz 音频测试音，实现音视频同步播放。 | - [`hdmi_audio_tone_i2s_64fs.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/hdmi_audio_tone_i2s_64fs.v): 48kHz 24-bit 物理建模合成；<br>- [`audio_arc_calculate.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/audio_arc_calculate.v): 动态计算 ACR `N=6144` 与 `CTS`；<br>- 官方参考设计 [`hdmi_1_4b_transmitter_core_wrapper.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/hdmi1.4b_transmitter_core/hdmi_1_4b_transmitter_core_wrapper.v): 注入音频时钟再生包与音频采样包。 | **满分超越达成**<br>不仅满足基础 48kHz 测试音，更实现曾侯乙青铜编钟五声音阶泛音物理建模与 64KB 真人普通话广播。 |
| **基础 4：系统稳定运行与工程规范** | 固化在开发板上（冷启动自启），单一完整工程（禁止多次下载拼接镜像），实用性、高规范度与低功耗。 | - `一键固化_Flash永久.bat`: 生成 713KB 比特流直接写入板载 Winbond SPI Flash，断电冷启动 1.5s 自启；<br>- 单一顶层 `top_tf_hdmi_audio.v` 整合全部模块，无多工程切换；<br>- STA 建立时间违例数 = 0，全动态时钟使能与操作数隔离低功耗设计。 | **100% 达成**<br>完全符合竞赛不可多次下载的要求，上电断电鲁棒性极高。 |

---

### 2. 【官方扩展要求 1~5 项】核验全景

| 官方扩展要求 | 官方解析 PPT 细则要求 | 源码实现位置与真实运行状态 | 现状分析与提升空间 |
| :--- | :--- | :--- | :--- |
| **扩展 1：图层叠加与字幕效果** | OSD 叠加模块实现多图层 Alpha 混合，叠加动态文字（时间戳、标语）与安路 Logo；状态显示（1.空闲 2.搜索BMP 3.写入SDRAM 4.OSD叠加）。 | - [`osd_display.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/osd_display.v): 顶部状态栏（16×16 安路红标 Logo、图片索引、60Hz 帧同步 MM:SS 秒表、音频状态、分辨率、6位 BCD 累计帧率）；底部 128 字符平滑滚屏跑马灯；3 档硬件 Alpha 混合（25% 水晶、50% 磨砂、75% 深色遮罩）；16 帧呼吸平滑淡入淡出悬浮式虚拟配置菜单。 | **高水平达成（存改进点）**<br>跑马灯已支持 UART 动态下发更新，但文字全为英文 ASCII，缺少中文点阵支持；且 PPT Slide 18 规定的 1~4 阶状态机在顶层尚未接入 OSD。 |
| **扩展 2：图片切换与转场特效** | 转场特效通过双帧缓存与 Alpha 渐变系数实现淡入淡出，或利用行缓存实现左右滑动切换，确保轮播过程画面连续、无闪烁。 | - [`video_transition.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/video_transition.v): 纯硬件 4 模流式转场引擎：<br>  1. Smoothstep Alpha 平滑渐变（16 阶 S 曲线非线性余弦淡入淡出）；<br>  2. Venetian Blinds 百叶窗（32px 垂直百叶开合）；<br>  3. Horizontal Laser Wipe 激光横向推进（带 2px 纯白高能光刃与 2px 青光光晕）；<br>  4. Digital Mosaic Dissolve 数字马赛克方块消融（16×16 Bayer 散列方块消解）；<br>- 丝印 KEY4 双击切换模式或设为 AUTO 循环交替。 | **满分达成（可精益求精）**<br>百叶窗目前为单向机械开槽，若改造为自中心对称拉开的“大剧院幕布式百叶窗”，视觉艺术冲击力将飞跃。 |
| **扩展 3：图片自适应缩放适配** | 解析 BMP 头获取宽高，双线性插值算法缩放至 HDMI 分辨率；数码管状态/参数显示：分辨率、缩放比。 | - [`scaling_geometry.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/scaling_geometry.v): 22 周期硬件恢复型除法器动态计算长宽比与累加步进；<br>- [`scaling_core.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/scaling_core.v): **真正的 2D 双线性插值 (2D Bilinear Interpolation)**，3 旋转行缓存（BRAM9K）+ 9 级流水乘法器（6 个 DSP18 宏块）同时进行小数相位 $f_x, f_y$ 4 点权重乘加；<br>- 支持 1.0X 居中、2.0X 局部放大、0.5X 缩略图、AUTO 自适应满屏。 | **极致达成（存表达盲区）**<br>底层算法远超一般的最近邻 DDA 插值，但在 OSD 上仅显示 `AUTO (SRC: 640X480)`，评委无法直观看到除法器算出的精确浮点/定点缩放比及 `2D-BILINEAR` 算法标识。 |
| **扩展 4：实时参数调节与 OSD 叠加** | 拨码开关或按键调节亮度、对比度，组合逻辑实时计算，OSD 叠加参数数值与调节状态。数码管显示亮度、对比度。 | - [`video_adjust_lut.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/video_adjust_lut.v): SW1..SW2 调 4 档移位亮度、丝印 KEY2 调 5 档 S 型高动态对比度曲线（三副本同步 BRAM 查找表）、4 档色温通道增益；<br>- [`video_sobel.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/video_sobel.v): 0-DSP BT.601 灰度化 + 双行缓存 3×3 Sobel 边缘提取，支持原画/黑白/古法墨拓/50-50分屏对比；<br>- 数码管即时覆盖显示 `b-100`..`b-150`、`C-1.00`..`C-0.75`、`CL-rGb`、`CL-Sob`、`CL-SPL`。 | **满分达成（可锦上添花）**<br>参数在 OSD 菜单中全为文字排版，若在虚拟菜单中增加图形化刻度滑块条（Progress Slider），并将死代码中的“皇家朱砂御拓”唤醒并入模式选择，UI 档次大幅提升。 |
| **扩展 5：音频可视化表现与自主创意** | 采集 24-bit PCM 音频样本，FFT 或自研 DFT 模块计算频谱能量，将柱状图或波形渲染为 RGB 叠加视频画面。 | - [`audio_spectrum_dft.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/audio_spectrum_dft.v): 自研 16 频段 Sliding DFT 实时频域分析引擎，共享 BRAM 暂存空间，四分之一周期余弦表，对数高度量化；<br>- [`osd_display.v`](file:///C:/fpga/HX4S20_HDMI_Player_%E5%AE%8C%E6%95%B4%E4%BA%A4%E4%BB%98%E5%8C%85_v2.8_%E6%96%B9%E5%90%914%E5%85%A8%E9%80%82%E9%85%8D/01_%E5%B7%A5%E7%A8%8B%E5%AE%8C%E6%95%B4%E6%BA%90%E7%A0%81/src/rtl/osd_display.v): 16 频段动态均衡器跳动频谱柱（带纯白悬浮峰值帽）+ 200 点实时示波器（超亮波峰、青色辉光、半透明能量带）；<br>- 6 位数码管显示动态 VU 峰值电平（`SP1-xx`, `SP2-xx`，瞬时跃升+20ms平滑阻尼回落）；<br>- 1.8 寸中控副屏同步呈现 128 点示波器与 8 频段跳动频谱。 | **满分达成（可震撼升级）**<br>多屏声学全景联动已极度出色。可进一步将编钟击打的低频脉冲能量扩充至整屏外边框与 Logo 的脉冲呼吸光晕（Beat Glow），实现全屏沉浸式音画律动。 |

---

## 三、 在“绝对零黑屏、零时序违例、完全时序闭合”铁律下的 5 大精进实施细则

### 1. 物理安全边界与设计铁律
1. **时钟域绝对防线**：
   - `ext_mem_clk` (125MHz SDRAM 域)：WNS 仅 **+0.112ns**！**绝对禁止在 125MHz 域追加任何哪怕 1 级门延迟的组合逻辑，严禁改动 SDRAM 仲裁机**；
   - `video_clk` (25MHz 视频域)：单周期逻辑深度已达 20 级，路径延迟 31.751ns。**新增视觉逻辑必须单独例化为后级触发器打拍流水线（Pipelined Stage），严禁在现有 Stage 2 的 23 选 1 多路选择器前串接复杂判断**；
2. **片上资源利用铁律**：
   - MSLICE 占用率已达 98.5%（仅剩百余个切片），严禁引入大型并行乘除法器；
   - **片上尚有整整 21 块 BRAM9K（67.2% 利用率）与 4 块 DSP18 处于闲置状态**！
   - **架构精髓**：**坚持“以 BRAM9K 换取复杂组合逻辑（ROM 查表法）”，新增视觉逻辑全部以后级独立打拍流水线形式接入**！

---

### 2. 5 项扩展功能高提分精进方案细则

#### 🚀 精进 1（扩展要求 1：图层叠加与字幕效果）—— 四阶状态铭牌打通与 BRAM 汉字字模库
- **背景与竞赛切入点**：
  官方解析 PPT Slide 18 醒目标注“**状态显示：1.空闲 2.搜索BMP 3.写入SDRAM 4.OSD叠加**”。底层 `bmp_read.v` 的 `state_code`（1..4）目前处于悬空状态（Unconnected Wire），同时跑马灯全为英文。
- **实施细则**：
  1. **直通四阶状态指示器 (State HUD Badge)**：
     将 `bmp_read.v` 的 `state_code` 引出并跨时钟域同步至 `video_clk`，在顶部状态栏正中央渲染带彩色框底的动态铭牌：
     `[1:IDLE]` (灰底白字) $\to$ `[2:SEEK-TF]` (蓝底白字) $\to$ `[3:BURST-RAM]` (琥珀底黑字) $\to$ `[4:OSD-DISP]` (翠绿底白字)；
     评委一对比官方 PPT，立即判定该功能 100% 满分对齐；
  2. **BRAM9K 汉字字模库 (零 LUT 逻辑消耗)**：
     利用 21 块闲置 BRAM9K 中的 **1 块 BRAM9K** 构建 16×16 中文字模 ROM（1 块 BRAM9K = 1152 字节，可容纳 36 个 16×16 汉字），固化精美文博与竞赛主题词汇：
     `【安路科技】【全国大学生芯片竞赛】【曾侯乙编钟】【大克鼎】【金石墨拓】`；
     在底部跑马灯滚动循环中穿插中文字符，彻底告别单调纯英文字符；
  3. **立体字模微投影 (Drop Shadow)**：
     字模比对逻辑同时在 `(x+1, y+1)` 产生纯黑偏移掩码，无论底层底图为高亮纯白或深黑，汉字均具备 100% 锐利可读性。

#### 🚀 精进 2（扩展要求 2：图片切换与转场特效）—— 大剧院双向对称开合幕布与 3 位宽特效库
- **背景与竞赛切入点**：
  当前百叶窗为单向机械切入，视觉风格偏向工业仪器；大剧院双向幕布开合极具舞台仪式感与文博典雅气质。
- **实施细则**：
  1. **大剧院对称幕布百叶窗 (Center-Split Theater Curtain)**：
     直接就地重构 `video_transition.v` 的 Mode 1：
     将单向模运算改为相对屏幕中央 320 像素的曼哈顿距离判断：`dx = (x >= 320) ? (x - 320) : (320 - x)`，百叶开合开缝判断基于 `(dx[4:0] < slit)`。轮播切图时，如同华丽剧场幕布自屏幕中央向两侧缓缓拉开，配合边缘微弱的暗金布料阴影，观赏度极佳；
  2. **消耗预算**：仅需 1 个加法器与 1 个比较器，增加 LUT < 15 个，0 BRAM，0 DSP；
  3. **零黑屏保障**：严格继承既有的“先闭合至全黑 $\to$ VBLANK 原子切换 SDRAM 读基地址 $\to$ 2 帧预充水 $\to$ 新画面双向徐徐展开”状态机锁步，100% 杜绝画面撕裂与残影。

#### 🚀 精进 3（扩展要求 3：图片自适应缩放适配）—— 显式标注“双线性插值算法”与精确浮点缩放比
- **背景与竞赛切入点**：
  当前系统虽然拥有业内顶级的 2D 双线性插值引擎（3 行缓存 + 9 级流水乘法器），但在 OSD 仅显示简单的 `AUTO (SRC: 640X480)`，评委难以一眼看穿底层硬件 22 周期除法器与双线性算法的强大。
- **实施细则**：
  1. **OSD 核心算法与比例显式标注**：
     在呼出虚拟配置菜单（或 HUD 常驻第二行）中，显式渲染精密的硬件遥测信息：
     `ALGO: 2D-BILINEAR (3-LINE CACHE + 6x MULT18)`
     `SRC: 1024x768 -> OUT: 640x480 (RATIO: 0.625X)`
     `SRC: 480x272  -> OUT: 640x362 (RATIO: 1.333X)`
     直接向评委证明：系统不是简单的像素丢弃或最近邻复制，而是由硬件除法器实时算出精确比例，并在 3 行缓存上执行真实的 4 点双线性插值滤波！
  2. **留白区环境光晕羽化 (Ambilight Border Glow)**：
     在缩放小图（如 0.5X 缩略图或 480x272 图片）的留白黑边区域，取有效画面边缘像素做微弱低通衰减映射，形成现代电视的“环绕氛围光”效果。

#### 🚀 精进 4（扩展要求 4：实时参数调节与 OSD 叠加）—— 唤醒“皇家朱砂御拓”与图形化刻度滑块条
- **背景与竞赛切入点**：
  代码中已有极具文化底蕴的皇家朱砂御拓定义但未接入；当前虚拟菜单参数调节全为离散文字（`100%`, `1.25X`），缺乏直观的“图形化进度条 / 刻度滑块”。
- **实施细则**：
  1. **唤醒“皇家朱砂御拓本” (Cinnabar Rubbing)**：
     将 `video_sobel.v` 中闲置的 `cin_rubbing_pixel`（皇家朱砂红 `24'h7A1414` + 御金笔画 `24'hFFE066`）正式纳入色彩模式，使色彩模式扩展为完整的文博四大典藏风貌：
     - Mode 0: 原画真彩 (Natural Vivid RGB)
     - Mode 1: 经典黑白 (Monochrome Grayscale)
     - Mode 2: 古法乌金墨拓 (Classic Inkstone Rubbing)
     - Mode 3: 皇家朱砂御拓 (Imperial Cinnabar Rubbing)
     - Mode 4: 50-50 激光分屏对比 (Split-Screen Comparison)
  2. **虚拟菜单图形化刻度滑块槽 (Graphical Sliders)**：
     在呼出的虚拟配置菜单中，为亮度、对比度、音量增加 64 像素宽度的图形化刻度槽：
     `BRIGHT: [■■■■■■□□]  75%`
     `CONTRA: [■■■■□□□□] 1.25X`
     `VOLUME: [■■■■■■■■] 100%`
     仅需判断 `(x >= bar_left && x < bar_left + fill_len)`，直观生动，大幅提升交互现代化质感。

#### 🚀 精进 5（扩展要求 5：音频可视化表现与自主创意）—— 全屏编钟音画共鸣光晕与重力落体顶帽
- **背景与竞赛切入点**：
  赛题重点强调“音画同步与音视频联动展示”。当前系统虽然示波器有节拍变色，但主画面外框未参与联动；频谱峰值帽为匀速线性下落，缺少专业级物理重力加速度动力学质感。
- **实施细则**：
  1. **全屏编钟重音外框呼吸光晕 (Beat-Synced Ambient Frame Glow)**：
     将 `audio_synth.v` 敲击编钟产生的低频瞬态冲击脉冲（`is_rhythm_beat`）引至主画面外边框；扬声器青铜钟声响起的瞬间，主屏最外层 2 像素边框与顶部安路 Logo 瞬间迸发一层青蓝色/金黄色高能脉冲光辉，并随编钟衰减包络（200ms）自然衰退。扬声器钟声响起的同时，整屏画面边框随节拍呼吸震颤，现场演示视觉冲击力拉满！
  2. **物理重力落体悬浮峰值帽 (Gravity Falloff Peak Caps)**：
     将频谱柱顶帽的下落算法改为物理自由落体模拟：顶帽在峰值处滞空 8 帧（约 130ms）保持不动，随后以初速度 0、每帧增加加速度 $g$ 垂直跌落，完全复刻专业录音棚母带电平表的视觉动力学体验；
  3. **板载麦克风/内录音频动态多路复用开关 (Live Mic vs Chime Switch)**：
     在 `pin.adc` 与顶层添加一个拨码开关通道判定：默认处于“内部曾侯乙编钟与真人语音高保真合成模式”；若答辩现场评委要求选手对着外接 INMP441 麦克风说话，拨动开关即可瞬时将音频数据源切换为排针外接真实麦克风，确保 100% 应对各种严苛答辩场景。

---

## 四、 5 大精进特性资源预算与实施风险矩阵

| 精进特性 | 对应扩展项 | 消耗 LUT | 消耗 BRAM9K | 消耗 DSP18 | 视频域时序影响 (25MHz) | 综合风险评估 | 核心提分价值 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **1. 四阶状态铭牌打通与 BRAM 汉字库** | 扩展 1 | ~35 | 1 块 | 0 | 独立增加 1 级流水打拍，Slack > +7.0ns | **极低 (零黑屏风险)** | 弥补中文短板，100% 吻合官方 PPT Slide 18 状态指标 |
| **2. 大剧院双向对称开合幕布转场** | 扩展 2 | ~15 | 0 块 | 0 | 仅修改过渡遮罩函数，不触碰 SDRAM 仲裁 | **零风险** | 电影级剧场转场，画面连贯典雅，现场演示惊艳 |
| **3. 标明双线性插值源/目标分辨率与真实比例** | 扩展 3 | ~25 | 0 块 | 0 | 字符多路选择，无关键长路径 | **零风险** | 亮出 2D 双线性插值与硬件恢复型除法器硬核算力 |
| **4. 唤醒朱砂御拓与 OSD 图形化滑块条** | 扩展 4 | ~30 | 0 块 | 0 | 坐标区间比较与已有死代码接入 | **零风险** | 补全文博数字拓片体系，显著提升消费级 UI 质感 |
| **5. 全屏编钟音画共鸣光晕与重力落体顶帽** | 扩展 5 | ~20 | 0 块 | 0 | 复用已有 beat 脉冲，外边框逻辑打拍 | **极低 (零黑屏风险)** | 彻底击穿“音画深度融合”评分点，现场视听冲击极强 |
| **合计预算** | **全项精进** | **~125** | **1 块 (余21块)** | **0 (余4块)** | **视频域 WNS 保持 > +6.5ns，125MHz 域丝毫不动** | **100% 切实可行** | **锁定全国大学生竞赛全国特等奖/一等奖竞争力** |

---

## 五、 Remaining Questions & Gaps（遗留问题与后续建议）

1. **未决问题与后续调查重点**：
   - **外接麦克风管脚复用策略**：当前固件为了支持 HC-08D 蓝牙遥测模块与隧道 SCADA 工业总线，将排针 J4 的部分引脚赋予了串口收发。若后续确定答辩必须展示外接 INMP441 物理麦克风，需进一步确认竞赛现场是否允许通过拨码开关切换引脚功能，或使用 J1 排针的其他空闲 GPIO 分配给 I2S 麦克风（目前板载 2 组 40Pin DC3 接口共有 72 个扩展 IO，资源极度充裕）。
   - **Flash 固化校验**：当前比特流为 713,432 字节，板载 SPI Flash 容量为 16MB/64MB。任何增补代码后，必须通过 `一键固化_Flash永久.bat` 执行烧录和回读校验，确保冷启动上电自启功能不受任何破坏。
2. **精进实施优先级建议**：
   - **第 1 优先级**：【精进 1：四阶状态指示器直接连通】与【精进 3：OSD 显式标注 2D 双线性插值与比例】，这两项直接对应官方解析 PPT 的文字得分点，改动量极小（各数十行 Verilog），零时序风险，提分立竿见影；
   - **第 2 优先级**：【精进 4：唤醒朱砂御拓】与【精进 2：大剧院双向对称开合幕布】，将已有死代码激活并将机械百叶窗转为艺术幕布，视觉反差极大；
   - **第 3 优先级**：【精进 5：全屏编钟音画共鸣外框光晕】与【精进 1：BRAM9K 汉字点阵库】，在答辩演示时呈现绝佳视听沉浸感。

Thoroughly review the findings above. Carefully check if they fully address every single aspect of the user's question — do not skip any part. Iterate if necessary following the **Workflow** in your system prompt.
</SYSTEM_MESSAGE>