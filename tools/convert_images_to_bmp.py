import os
import sys
import argparse
from PIL import Image

def convert_single_file(input_path, output_path, target_width=640, target_height=480):
    """
    将单张图片转换为指定分辨率的无压缩 24-bit BMP 格式。
    """
    if not os.path.exists(input_path):
        print(f"[错误] 找不到输入文件: {input_path}")
        return False

    if not os.path.isfile(input_path):
        print(f"[错误] 输入路径不是一个有效文件: {input_path}")
        return False

    try:
        # 如果 output_path 是目录或以斜杠结尾，自动生成目标文件名
        if os.path.isdir(output_path) or output_path.endswith(('/', '\\')):
            base_name = os.path.splitext(os.path.basename(input_path))[0]
            output_path = os.path.join(output_path, f"{base_name}_640x480.bmp")
        elif not output_path.lower().endswith('.bmp'):
            output_path += '.bmp'

        out_dir = os.path.dirname(os.path.abspath(output_path))
        if out_dir and not os.path.exists(out_dir):
            os.makedirs(out_dir, exist_ok=True)

        with Image.open(input_path) as img:
            # 转换为 RGB 模式 (即 24-bit，无 alpha 通道)
            img_rgb = img.convert('RGB')
            
            # 调整图片大小 (LANCZOS 高质量重采样)
            img_resized = img_rgb.resize((target_width, target_height), Image.Resampling.LANCZOS)
            
            # 保存为无压缩的 BMP 文件
            img_resized.save(output_path, 'BMP')
            
            print(f"[成功] 转换完成: {input_path} -> {output_path}")
            return True
    except Exception as e:
        print(f"[失败] 转换 {input_path} 时发生错误: {e}")
        return False

def convert_to_bmp(input_dir, output_dir, target_width=640, target_height=480):
    """
    批量将图片转换为指定分辨率的无压缩 24-bit BMP 格式。
    """
    if not os.path.exists(input_dir):
        print(f"[错误] 输入目录不存在: {input_dir}")
        return 0

    if not os.path.exists(output_dir):
        os.makedirs(output_dir, exist_ok=True)

    supported_formats = ('.png', '.jpg', '.jpeg', '.bmp', '.webp', '.gif')
    files = [
        f for f in os.listdir(input_dir)
        if f.lower().endswith(supported_formats) and os.path.isfile(os.path.join(input_dir, f))
    ]

    if not files:
        print(f"在目录 '{input_dir}' 中没有找到支持的图片文件。")
        return 0

    print(f"找到 {len(files)} 个图片文件，开始转换...")
    success_count = 0

    for filename in files:
        input_path = os.path.join(input_dir, filename)
        base_name = os.path.splitext(filename)[0]
        output_filename = f"{base_name}_640x480.bmp"
        output_path = os.path.join(output_dir, output_filename)

        if convert_single_file(input_path, output_path, target_width, target_height):
            success_count += 1

    print(f"\n转换完成！共成功转换 {success_count} 个文件。")
    print(f"请将 '{output_dir}' 目录下的所有 BMP 文件复制到 TF(SD) 卡的根目录中。")
    return success_count

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="FPGA TF卡 BMP 图片转换工具 (640x480, 24位无压缩)")
    parser.add_argument('input', nargs='?', help='输入的图片文件或目录路径 (例如: 1.jpg 或 ./my_pics)')
    parser.add_argument('output', nargs='?', help='输出的BMP文件或目标目录路径 (例如: 1.bmp 或 ./output_bmp)')
    
    args = parser.parse_args()
    current_dir = os.path.dirname(os.path.abspath(__file__))

    # 场景 1: 同时指定了输入与输出
    if args.input and args.output:
        if os.path.isdir(args.input):
            convert_to_bmp(args.input, args.output)
        else:
            convert_single_file(args.input, args.output)
    # 场景 2: 仅指定了输入
    elif args.input:
        if os.path.isdir(args.input):
            # 输入为目录，输出默认写入 input_dir/output_bmp
            default_output = os.path.join(args.input, "output_bmp")
            convert_to_bmp(args.input, default_output)
        else:
            # 输入为单张图片，输出默认保存为同名前缀的 .bmp
            base_dir = os.path.dirname(os.path.abspath(args.input))
            base_name = os.path.splitext(os.path.basename(args.input))[0]
            output_path = os.path.join(base_dir, f"{base_name}_640x480.bmp")
            convert_single_file(args.input, output_path)
    # 场景 3: 未提供任何命令行参数，走交互式默认流程
    else:
        default_input = os.path.join(current_dir, "input_images")
        default_output = os.path.join(current_dir, "output_bmp")

        print("=== FPGA TF卡 BMP 图片转换工具 ===")
        print("要求：640x480, 24位无压缩 BMP")
        print("-" * 40)
        print("用法提示:")
        print("  1. 单图转换: python convert_images_to_bmp.py <输入图片> [输出图片]")
        print("  2. 目录转换: python convert_images_to_bmp.py <输入目录> [输出目录]")
        print("  3. 默认批处理: 将图片放入 input_images 文件夹后直接运行本脚本")
        print("-" * 40)

        if not os.path.exists(default_input):
            os.makedirs(default_input, exist_ok=True)
            print(f"已创建默认输入目录: {default_input}")
            print(f"请将你需要转换的图片放入该目录中，然后重新运行本脚本。")
            sys.exit(0)

        convert_to_bmp(default_input, default_output)
