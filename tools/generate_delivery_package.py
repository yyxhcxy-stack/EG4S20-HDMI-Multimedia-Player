import os
import sys
import shutil
import json
import zipfile
from datetime import datetime

if sys.stdout:
    sys.stdout.reconfigure(encoding='utf-8')
if sys.stderr:
    sys.stderr.reconfigure(encoding='utf-8')

ROOT_DIR = r"D:\FPGA\HX4S20_v2.6.2_d5faf4c_handoff\project"
BRAIN_DIR = r"C:\Users\14058\.gemini\antigravity\brain\fdc36b2b-df57-4546-9df0-aa5547085c72"
PACKAGE_DIR = r"D:\FPGA\HX4S20_Final_Delivery_Package_20261012"
ZIP_OUTPUT = r"D:\FPGA\HX4S20_全套工程_源码_技术文档_工作记录_20261012.zip"

def create_directory_structure():
    if os.path.exists(PACKAGE_DIR):
        shutil.rmtree(PACKAGE_DIR)
    os.makedirs(PACKAGE_DIR, exist_ok=True)
    
    dirs = [
        "01_工程完整源码/src",
        "01_工程完整源码/prj",
        "01_工程完整源码/tools",
        "02_已验证固化固件与工具/output",
        "02_已验证固化固件与工具/TF卡配套图片",
        "03_技术报告与设计文档",
        "04_研发记录与技术交流工作纪要/media"
    ]
    for d in dirs:
        os.makedirs(os.path.join(PACKAGE_DIR, d), exist_ok=True)
    print("Created package directory structure.")

def copy_source_code():
    print("Copying source code and project files...")
    src_dst = os.path.join(PACKAGE_DIR, "01_工程完整源码", "src")
    shutil.copytree(os.path.join(ROOT_DIR, "src"), src_dst, dirs_exist_ok=True)
    
    prj_dst = os.path.join(PACKAGE_DIR, "01_工程完整源码", "prj")
    # Copy prj but skip huge runs directories
    for item in os.listdir(os.path.join(ROOT_DIR, "prj")):
        sitem = os.path.join(ROOT_DIR, "prj", item)
        ditem = os.path.join(prj_dst, item)
        if item == "HX4S20_HDMI_Player_Runs":
            os.makedirs(ditem, exist_ok=True)
            for sub in ["syn_1", "phy_1"]:
                ssub = os.path.join(sitem, sub)
                dsub = os.path.join(ditem, sub)
                if os.path.exists(ssub):
                    os.makedirs(dsub, exist_ok=True)
                    for f in ["settings.cfg", "HX4S20_HDMI_Player.tcl", "HX4S20_HDMI_Player.prj"]:
                        sf = os.path.join(ssub, f)
                        df = os.path.join(dsub, f)
                        if os.path.exists(sf):
                            shutil.copyfile(sf, df)
        elif os.path.isdir(sitem):
            shutil.copytree(sitem, ditem, dirs_exist_ok=True)
        else:
            shutil.copyfile(sitem, ditem)
            
    tools_dst = os.path.join(PACKAGE_DIR, "01_工程完整源码", "tools")
    # Copy tools excluding huge cache
    for item in os.listdir(os.path.join(ROOT_DIR, "tools")):
        sitem = os.path.join(ROOT_DIR, "tools", item)
        ditem = os.path.join(tools_dst, item)
        if item in ["__pycache__"]:
            continue
        if os.path.isdir(sitem):
            shutil.copytree(sitem, ditem, dirs_exist_ok=True)
        else:
            shutil.copyfile(sitem, ditem)
            
    # Root batch scripts and key assets
    root_files = [
        "voice_emergency_64kb.mif", "voice_emergency_64kb.hex",
        "一键全流程编译.bat", "一键固化_Flash永久.bat", "一键烧录_SRAM临时.bat",
        "一键安装下载器驱动(右键以管理员身份运行).bat", "一键恢复默认签名_管理员运行.bat",
        "永久禁用驱动签名_管理员运行.bat"
    ]
    for rf in root_files:
        src = os.path.join(ROOT_DIR, rf)
        if os.path.exists(src):
            shutil.copyfile(src, os.path.join(PACKAGE_DIR, "01_工程完整源码", rf))

def copy_firmware_and_tools():
    print("Copying verified bitstreams and tools...")
    target_dir = os.path.join(PACKAGE_DIR, "02_已验证固化固件与工具")
    
    # image.bit
    shutil.copyfile(os.path.join(ROOT_DIR, "image.bit"), os.path.join(target_dir, "image.bit"))
    
    # TF卡配套图片
    shutil.copytree(os.path.join(ROOT_DIR, "TF卡配套图片"), os.path.join(target_dir, "TF卡配套图片"), dirs_exist_ok=True)
    
    # output
    shutil.copytree(os.path.join(ROOT_DIR, "output"), os.path.join(target_dir, "output"), dirs_exist_ok=True)
    
    # Root scripts for easy double-clicking
    for rf in ["一键固化_Flash永久.bat", "一键烧录_SRAM临时.bat", "一键安装下载器驱动(右键以管理员身份运行).bat", "Win10、Win11解决驱动签名问题.pdf"]:
        src = os.path.join(ROOT_DIR, rf)
        if os.path.exists(src):
            shutil.copyfile(src, os.path.join(target_dir, rf))

def copy_reports_and_docs():
    print("Copying technical reports and documents...")
    target_dir = os.path.join(PACKAGE_DIR, "03_技术报告与设计文档")
    
    # From Brain
    shutil.copyfile(
        os.path.join(BRAIN_DIR, "LOW_POWER_OPTIMIZATION_REPORT.md"),
        os.path.join(target_dir, "HX4S20多媒体系统低功耗逻辑优化与能效增强技术专题报告.md")
    )
    shutil.copyfile(
        os.path.join(BRAIN_DIR, "HX4S20_Optimization_Report.md"),
        os.path.join(target_dir, "HX4S20多媒体系统微架构优化与功能实现总报告.md")
    )
    
    # From Project & Root
    for doc in ["README_使用与交付说明.md", "README_工程交付与二次开发指南_v2.2.md", "README_使用与交付说明.txt"]:
        src = os.path.join(ROOT_DIR, doc)
        if os.path.exists(src):
            shutil.copyfile(src, os.path.join(target_dir, doc))
            
    pdf_src = r"D:\FPGA\FPGA-安路赛道.pdf"
    if os.path.exists(pdf_src):
        shutil.copyfile(pdf_src, os.path.join(target_dir, "FPGA-安路赛道_竞赛指南.pdf"))

def generate_chat_and_worklog():
    print("Parsing full conversation transcript and generating work log...")
    transcript_file = os.path.join(BRAIN_DIR, ".system_generated", "logs", "transcript_full.jsonl")
    if not os.path.exists(transcript_file):
        transcript_file = os.path.join(BRAIN_DIR, ".system_generated", "logs", "transcript.jsonl")
        
    media_dst = os.path.join(PACKAGE_DIR, "04_研发记录与技术交流工作纪要", "media")
    # Copy images from brain
    for img in ["check_pts.png", "debug_grid.png", "lcd_crop.jpg", "rectified.png", "screen_128x128.png", "sim_lcd_1_8inch_preview_4x.png"]:
        simg = os.path.join(BRAIN_DIR, img)
        if os.path.exists(simg):
            shutil.copyfile(simg, os.path.join(media_dst, img))
            
    user_upload_dir = os.path.join(BRAIN_DIR, ".user_uploaded")
    if os.path.exists(user_upload_dir):
        shutil.copytree(user_upload_dir, media_dst, dirs_exist_ok=True)
        
    turns = []
    current_turn = None
    
    with open(transcript_file, "r", encoding="utf-8") as f:
        for line in f:
            try:
                obj = json.loads(line)
            except Exception:
                continue
            source = obj.get("source")
            mtype = obj.get("type")
            content = obj.get("content", "")
            created_at = obj.get("created_at", "")
            
            if source == "USER_EXPLICIT" and mtype == "USER_INPUT":
                if current_turn:
                    turns.append(current_turn)
                current_turn = {
                    "time": created_at,
                    "user": content.strip(),
                    "responses": []
                }
            elif source == "MODEL" and mtype == "PLANNER_RESPONSE":
                if current_turn and content and content.strip():
                    current_turn["responses"].append({
                        "time": created_at,
                        "text": content.strip()
                    })
    if current_turn:
        turns.append(current_turn)
        
    # Write Markdown transcript
    md_path = os.path.join(PACKAGE_DIR, "04_研发记录与技术交流工作纪要", "项目完整研发记录与技术交流纪要.md")
    with open(md_path, "w", encoding="utf-8") as out:
        out.write("# HX4S20 多媒体系统完整技术研发与交流工作纪要\n\n")
        out.write(f"**生成时间**：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  \n")
        out.write("**项目名称**：HX4S20 HDMI 高清多媒体播放系统 (Anlogic EG4S20BG256)  \n")
        out.write("**记录范围**：自项目启动、双屏联调、按键重构、低功耗 Step 1~5 阶梯优化至 512MB/8 图容量释放与 Flash 固化的完整研发轨迹。  \n\n")
        out.write("---\n\n")
        
        for idx, turn in enumerate(turns, 1):
            out.write(f"## 【研发阶段 / 对话轮次 #{idx}】\n")
            out.write(f"- **时间**：`{turn['time']}`\n\n")
            out.write("### 👤 用户需求与指令：\n")
            out.write(f"```text\n{turn['user']}\n```\n\n")
            out.write("### 🤖 技术实现、分析与执行汇报：\n\n")
            if turn["responses"]:
                for r in turn["responses"]:
                    out.write(f"{r['text']}\n\n")
            else:
                out.write("*(内部工具链路自动执行并闭环，无额外单独文字回复)*\n\n")
            out.write("---\n\n")
            
    # Copy raw transcript as well
    shutil.copyfile(
        transcript_file,
        os.path.join(PACKAGE_DIR, "04_研发记录与技术交流工作纪要", "transcript_raw.jsonl")
    )
    print(f"Generated worklog markdown with {len(turns)} turns.")

def generate_root_readme():
    print("Writing Root README...")
    readme_path = os.path.join(PACKAGE_DIR, "00_项目交付与使用总览_README.md")
    content = """# HX4S20 HDMI 高清多媒体系统全套交付包

## 一、 项目总览与核心成果

本项目基于 **国产安路 EG4S20BG256 FPGA** 芯片，打造了集 **HDMI 640×480@60Hz 高清视频输出、TF 卡 FAT32 高清图库读取、4 种硬件流式转场特效、自研定点 DDA 图像缩放、双行缓存流式 3×3 Sobel 边缘检测、自研 Sliding DFT (SDFT) 实时音频频域分析引擎、双屏参数与遥测联动、以及五步阶梯式空域微门控低功耗优化** 于一体的高性能嵌入式多媒体系统。

本交付包为**最终定型交付版本**，已通过官方 Tang Dynasty 6.2 全流程编译与布局布线寻优，达成 **100% 正裕量时序闭合**，并已通过板载高速通道永久固化至 SPI Flash。

---

## 二、 交付包目录结构说明

```
HX4S20_Final_Delivery_Package_20261012/
├── 00_项目交付与使用总览_README.md               # 本交付总览与使用说明
├── 01_工程完整源码/                             # 完整的 RTL 源代码、IP 核与工程配置
│   ├── src/                                    # RTL Verilog 源码、时序与管脚约束 (.sdc, .adc)
│   ├── prj/                                    # Tang Dynasty 工程文件与工程配置
│   ├── tools/                                  # 自动化编译、时序寻优、烧录及测试脚本
│   ├── 一键全流程编译.bat                        # 双击即可一键启动 TD 全流程综合布线
│   ├── 一键固化_Flash永久.bat                   # 双击即可烧录固化至板载 SPI Flash
│   └── 一键烧录_SRAM临时.bat                    # 双击即可快速下载至 SRAM 进行即时验证
├── 02_已验证固化固件与工具/                      # 开箱即用的已验证比特流与免环境烧录工具
│   ├── image.bit                               # 最新固化的黄金比特流 (SHA256: a09feb67...)
│   ├── output/                                 # 交付物清单、时序报告与 Flash 校验报告
│   ├── TF卡配套图片/                           # 5 张配套高清 BMP 测试图片 (含文物、Logo、水果等)
│   ├── 一键固化_Flash永久.bat                   # 双击自动调用下载器固化
│   └── Win10、Win11解决驱动签名问题.pdf         # 下载器驱动安装图文指南
├── 03_技术报告与设计文档/                       # 完整的技术评审专题报告与竞赛规范文档
│   ├── HX4S20多媒体系统低功耗逻辑优化与能效增强技术专题报告.md # 五步阶梯低功耗详细设计
│   ├── HX4S20多媒体系统微架构优化与功能实现总报告.md         # 架构深度剖析
│   ├── README_使用与交付说明.md                 # 硬件管脚映射、操作按键指南
│   └── FPGA-安路赛道_竞赛指南.pdf               # 竞赛原题与技术指标规范
└── 04_研发记录与技术交流工作纪要/               # 完整研发过程的对话记录与技术分析归档
    ├── 项目完整研发记录与技术交流纪要.md        # 结构化 Markdown 记录 (包含 50+ 轮研发实录)
    ├── transcript_raw.jsonl                    # 原始完整通信时序日志
    └── media/                                  # 研发过程中产生的所有示波器截图、LCD 效果图与资料
```

---

## 三、 核心技术与指标达成情况

| 核心特性 | 技术方案 | 达成指标 | 评审亮点 |
| :--- | :--- | :--- | :--- |
| **时序闭合 (QoR)** | 自动种子寻优 (Seed 2) | **Setup WNS = +120ps, Hold WNS = +22ps, 0 违例** | 8 个时钟域全正裕量闭合，稳定运行 |
| **图片扫描与容量** | 512MB 深度扩展 (`1048576` 扇区) | **支持 5~8 张高清图流畅循环轮播** | 彻底解决大卡只能读 3 张图的问题 |
| **状态遥测双屏联动** | CDC 跨时钟域自适应计数同步 | **主屏 HUD 显示 `IMG: 01/05`，副屏显示 `PIC #1/5`** | 双屏完全自适应 TF 卡实际文件数 |
| **低功耗优化** | 空域时域操作数隔离 + CDC 静默 | **转场 99.9% 静默，Sobel 30.7万像素静默** | 主屏 [ECO] / 副屏 ECO L4-GATED 实时高亮 |
| **音频频域分析** | 自研 Sliding DFT (SDFT) | **仅用 2 个 DSP，O(1) 复杂度 8 频段 48kHz** | 替代臃肿 FFT IP，高能效高响应 |
| **图像流式缩放** | 自研定点化 DDA 步进累加器 | **0 气泡单拍流式插值** | 0.5X / 1.0X / 2.0X 线速高质量缩放 |

---

## 四、 快速上手与操作指南

### 1. 硬件连接
- 将 **TF 卡**（格式化为 FAT32，拷入 `02_已验证固化固件与工具/TF卡配套图片` 内的 5 张图片）插入开发板背面卡槽；
- 将 **HDMI 显示器** 连接开发板 HDMI 接口（输出 640×480@60Hz）；
- 将 **1.8寸 SPI LCD 屏 (ST7735)** 插在 J1 扩展排针（引脚 23~28，偏移量 0,0 无黑边）；
- 用 Type-C 数据线连接开发板上的 JTAG 下载器口并连接电脑。

### 2. 一键烧录
- **临时体验**：双击 `02_已验证固化固件与工具/一键烧录_SRAM临时.bat`（7 秒快速加载至 SRAM）；
- **永久固化**：双击 `02_已验证固化固件与工具/一键固化_Flash永久.bat`（自动写入板载 SPI Flash 并完成 100% 逐字节回读校验，断电不丢失）。

### 3. 按键交互说明
- **KEY1**：短按单步切图；长按调节画面对比度；
- **KEY2**：短按启停自动轮播（默认 3 秒）；长按 1.2 秒触发/解除应急广播；双击切换转场特效（淡入淡出 / 百叶窗 / 滑屏推拉 / 自动随机）；
- **KEY3**：短按调节画面缩放（1.0X $\to$ 2.0X $\to$ 0.5X $\to$ AUTO）；
- **KEY4**：单按调节音量（100% $\to$ 75% $\to$ 50% $\to$ 25% $\to$ MUTE）。
"""
    with open(readme_path, "w", encoding="utf-8") as f:
        f.write(content)

def make_zip_archive():
    print(f"Creating final distribution zip file at {ZIP_OUTPUT}...")
    if os.path.exists(ZIP_OUTPUT):
        os.remove(ZIP_OUTPUT)
        
    with zipfile.ZipFile(ZIP_OUTPUT, "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk(PACKAGE_DIR):
            for file in files:
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, os.path.dirname(PACKAGE_DIR))
                zipf.write(full_path, rel_path)
                
    size_mb = os.path.getsize(ZIP_OUTPUT) / (1024 * 1024)
    print(f"Zip package created successfully! Size: {size_mb:.2f} MB")

if __name__ == "__main__":
    create_directory_structure()
    copy_source_code()
    copy_firmware_and_tools()
    copy_reports_and_docs()
    generate_chat_and_worklog()
    generate_root_readme()
    make_zip_archive()
    print("ALL PACKAGING TASKS COMPLETED SUCCESSFULLY!")
