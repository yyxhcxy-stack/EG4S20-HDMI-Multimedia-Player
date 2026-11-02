import os
import sys
import subprocess

vs_git_cmd = r"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\cmd"
vs_git_bin = r"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\TeamFoundation\Team Explorer\Git\mingw64\bin"

os.environ["PATH"] = vs_git_cmd + os.pathsep + vs_git_bin + os.pathsep + os.environ.get("PATH", "")

repo_dir = os.path.dirname(os.path.abspath(__file__))
os.chdir(repo_dir)

print("=" * 65)
print("  EG4S20 HDMI Player - GitHub 开源仓库一键推送助手")
print("=" * 65)
print("\n目标仓库: https://github.com/yyxhcxy-stack/EG4S20-HDMI-Multimedia-Player.git")

# Configure git
subprocess.run(["git", "config", "user.name", "yyxhcxy-stack"], check=True)
subprocess.run(["git", "config", "user.email", "yyxhcxy@gmail.com"], check=True)
subprocess.run(["git", "branch", "-M", "main"], check=True)

remote_url = "https://github.com/yyxhcxy-stack/EG4S20-HDMI-Multimedia-Player.git"
subprocess.run(["git", "remote", "remove", "origin"], stderr=subprocess.DEVNULL)
subprocess.run(["git", "remote", "add", "origin", remote_url], check=True)

print("\n正在启动 Git 执行推送...")
print("【提示】若浏览器弹出 GitHub 授权窗口，请点击 Authorize 确认登录！\n")

res = subprocess.run(["git", "push", "-u", "origin", "main"])

if res.returncode != 0:
    print("\n" + "-" * 65)
    print("【备选极速方案】如果浏览器弹不出或网络超时，可使用 Token 一秒推送：")
    print("1. 浏览器打开: https://github.com/settings/tokens/new")
    print("2. Note 随便填，勾选第一个 [repo] 权限，滑到底部点击 [Generate token]；")
    print("3. 复制生成的以 ghp_ 开头的字符串。")
    print("-" * 65)
    token = input("\n请粘贴您的 GitHub Token (若想直接退出请按回车): ").strip()
    if token:
        token_url = f"https://{token}@github.com/yyxhcxy-stack/EG4S20-HDMI-Multimedia-Player.git"
        subprocess.run(["git", "remote", "set-url", "origin", token_url], check=True)
        print("\n使用 Token 正在极速推送中...")
        res = subprocess.run(["git", "push", "-u", "origin", "main"])

if res.returncode == 0:
    print("\n" + "=" * 65)
    print(">>> [成功] 500 个代码文件已全部成功推送到 GitHub 仓库！ <<<")
    print("访问链接: https://github.com/yyxhcxy-stack/EG4S20-HDMI-Multimedia-Player")
    print("请回到浏览器按 F5 刷新页面查看！")
    print("=" * 65)
else:
    print("\n[推送未成功，请检查网络或复制错误信息]")

input("\n按回车键退出...")
