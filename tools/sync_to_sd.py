import os
import sys
import stat
import shutil
import argparse
import ctypes

def make_writable(path):
    """确保文件或文件夹具备可写权限，避免 Windows 下因只读属性触发拒绝访问"""
    try:
        os.chmod(path, stat.S_IWRITE)
    except Exception:
        pass

def handle_remove_readonly(func, path, exc_info):
    """shutil.rmtree 错误回调：遇到只读权限拒绝时，修改属性后重试"""
    make_writable(path)
    try:
        func(path)
    except Exception as e:
        print(f"  [警告] 无法清理路径 {path}: {e}")

def is_fixed_or_system_drive(target_path):
    """
    判断目标路径是否为固定本地硬盘（非可移动介质/U盘/SD卡）或系统盘/工作区盘根目录。
    用于防止误操作格式化整盘。
    """
    drive_part = os.path.splitdrive(os.path.abspath(target_path))[0].upper()
    if not drive_part:
        return False

    root_dir = f"{drive_part}\\"
    
    # 检查是否等于系统盘 (如 C:) 或当前脚本所在工作区盘 (如 D:)
    sys_drive = os.environ.get('SystemDrive', 'C:').upper().rstrip('\\')
    cur_drive = os.path.splitdrive(os.path.abspath(__file__))[0].upper()

    # 检查目标路径是否是驱动器根目录
    norm = os.path.normpath(os.path.abspath(target_path)).upper()
    is_root = (norm == root_dir.rstrip('\\')) or (norm == root_dir)

    if is_root:
        if drive_part in (sys_drive, cur_drive):
            return True
        # Windows API 检查驱动器类型 (3 = DRIVE_FIXED 固定硬盘)
        try:
            drive_type = ctypes.windll.kernel32.GetDriveTypeW(root_dir)
            if drive_type == 3:  # DRIVE_FIXED
                return True
        except Exception:
            pass

    return False

def corrupt_old_bmp_headers(target_drive):
    """
    遍历目标驱动器下的所有 .bmp 文件，将其开头的 'BM' 魔数修改为 'XX'。
    这样 FPGA 的物理扇区扫描就不会把这些“被标记为删除但物理数据还在”的文件识别为有效图片。
    """
    print(f"正在扫描 {target_drive} 驱动器，准备清除旧图片的 BMP 识别头...")
    
    try:
        bmp_files = [
            os.path.join(target_drive, f) for f in os.listdir(target_drive)
            if f.lower().endswith('.bmp') and os.path.isfile(os.path.join(target_drive, f))
        ]
    except Exception as e:
        print(f"  [警告] 扫描目录失败: {e}")
        return
    
    corrupt_count = 0
    for bmp_file in bmp_files:
        try:
            # 去除可能存在的只读属性
            make_writable(bmp_file)
            # 以读写模式打开文件（不截断）
            with open(bmp_file, 'r+b') as f:
                header = f.read(2)
                if header == b'BM':
                    # 将指针移回开头
                    f.seek(0)
                    # 写入破坏魔数 'XX'
                    f.write(b'XX')
                    corrupt_count += 1
                    print(f"  [清除有效] 已破坏头文件: {os.path.basename(bmp_file)}")
        except Exception as e:
            print(f"  [警告] 无法处理文件 {bmp_file}: {e}")
            
    print(f"头文件清除完毕，共处理了 {corrupt_count} 个旧图片文件。")

def clean_drive(target_drive):
    """
    删除目标驱动器下的所有文件，模拟格式化/清空操作（跳过系统隐藏保护文件夹）。
    支持处理只读文件与多层子目录。
    """
    print(f"\n正在清空 {target_drive} 驱动器中的旧文件...")
    for item in os.listdir(target_drive):
        item_path = os.path.join(target_drive, item)
        # 跳过系统隐藏与受保护文件夹如 System Volume Information, $RECYCLE.BIN
        if item.startswith('.') or item.lower() in ('system volume information', '$recycle.bin'):
            continue
            
        try:
            make_writable(item_path)
            if os.path.isfile(item_path):
                os.remove(item_path)
            elif os.path.isdir(item_path):
                shutil.rmtree(item_path, onerror=handle_remove_readonly)
        except Exception as e:
            print(f"  [警告] 无法删除 {item_path}: {e}")
    print("驱动器清空完毕。")

def sync_new_images(source_dir, target_drive, max_count=5):
    """
    从源文件夹中挑选最多 max_count 张 BMP 图片，复制到目标驱动器。
    """
    if not os.path.exists(source_dir):
        print(f"\n[错误] 源文件夹不存在: {source_dir}")
        return 0

    try:
        bmp_files = [
            os.path.join(source_dir, f) for f in os.listdir(source_dir)
            if f.lower().endswith('.bmp') and os.path.isfile(os.path.join(source_dir, f))
        ]
    except Exception as e:
        print(f"\n[错误] 读取源文件夹失败: {e}")
        return 0

    if not bmp_files:
        print(f"\n[错误] 源文件夹 {source_dir} 中没有找到任何有效 BMP 图片。")
        return 0

    # 按名称排序，保证顺序一致性
    bmp_files.sort()
    
    # 限制复制的数量
    files_to_copy = bmp_files[:max_count]
    
    print(f"\n准备将 {len(files_to_copy)} 张图片同步到 {target_drive}...")
    
    success_count = 0
    for i, bmp_file in enumerate(files_to_copy):
        try:
            filename = os.path.basename(bmp_file)
            # 为了让 FPGA 物理扇区尽量连续，在文件名前加上两位序号
            target_name = f"{i:02d}_{filename}"
            target_path = os.path.join(target_drive, target_name)
            
            make_writable(target_path)
            shutil.copy2(bmp_file, target_path)
            print(f"  [同步成功] {filename} -> {target_name}")
            success_count += 1
        except Exception as e:
            print(f"  [同步失败] {filename}: {e}")
            
    print(f"\n同步完成！成功写入 {success_count} 张新图片。")
    print("你现在可以安全弹出 SD 卡，插入 FPGA 开发板了。")
    return success_count

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="FPGA SD卡 图片同步工具 (防物理残留死锁加固版)")
    parser.add_argument('drive', help='SD 卡所在的盘符或目标目录 (例如: E: 或 E:\\ 或 ./mock_sd)')
    parser.add_argument('-s', '--source', help='存放转换好 BMP 图片的源文件夹 (默认: 当前目录的 output_bmp)', default=None)
    parser.add_argument('-n', '--num', type=int, default=4, help='最多同步的图片数量 (默认: 4)')
    parser.add_argument('-y', '--yes', action='store_true', help='跳过确认提示直接执行')
    
    args = parser.parse_args()

    # 处理盘符/目录格式
    raw_drive = args.drive.strip()
    if len(raw_drive) == 1 and raw_drive.isalpha():
        target_drive = f"{raw_drive.upper()}:\\"
    elif len(raw_drive) == 2 and raw_drive[0].isalpha() and raw_drive[1] == ':':
        target_drive = f"{raw_drive.upper()}\\"
    elif raw_drive.endswith(':\\') or raw_drive.endswith(':/'):
        target_drive = f"{raw_drive[:2].upper()}\\"
    else:
        target_drive = os.path.abspath(raw_drive)

    if not os.path.exists(target_drive):
        print(f"[致命错误] 找不到指定的驱动器或目录: {target_drive}")
        print("请检查 SD 卡是否已正确插入电脑并分配了盘符，或目标目录是否存在。")
        sys.exit(1)

    # 确定源文件夹
    current_dir = os.path.dirname(os.path.abspath(__file__))
    source_dir = args.source if args.source else os.path.join(current_dir, "output_bmp")

    print("="*50)
    print(f"目标 SD 卡盘符: {target_drive}")
    print(f"图片源文件夹  : {source_dir}")
    print("="*50)
    
    # 深度安全拦截：防止误操作清空固定硬盘/系统盘/工作区盘根目录
    if is_fixed_or_system_drive(target_drive) and not args.yes:
        if sys.stdin.isatty():
            confirm = input(f"\n[危险警告] 目标路径位于固定硬盘或系统分区根目录 ({target_drive})！\n这将会清空该驱动器根目录下的文件。你确定要继续吗？(y/N): ")
            if confirm.lower() != 'y':
                print("操作已取消。")
                sys.exit(0)
        else:
            print(f"\n[致命拦截] 检测到试图操作固定硬盘/系统分区根目录 ({target_drive}) 且处于非交互终端。\n为防止意外破坏磁盘数据，操作已被中止。如确需执行请显式添加 -y 参数。")
            sys.exit(1)

    # 步骤 1: 破坏旧 BMP 的物理文件头
    corrupt_old_bmp_headers(target_drive)
    
    # 步骤 2: 清空 SD 卡（从文件系统层面）
    clean_drive(target_drive)
    
    # 步骤 3: 复制新图片
    sync_new_images(source_dir, target_drive, max_count=args.num)
