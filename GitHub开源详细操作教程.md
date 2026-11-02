# GitHub 开源保姆级操作教程

本指南专门为您编写，手把手教您如何将当前工程开源发布至 GitHub，并获取符合竞赛要求的 GitHub 链接。

---

## 步骤一：在 GitHub 上创建新的公开仓库

1. 打开浏览器，登录您的 GitHub 账号：[https://github.com](https://github.com)；
2. 点击网页右上角的 **`+`** 号，选择 **`New repository`**；
3. 填写仓库基础信息：
   - **Repository name**（仓库名称）：建议命名为 `EG4S20-HDMI-Multimedia-Player` 或 `Anlogic-EG4S20-Player`；
   - **Description**（项目描述）：可填写 `基于国产安路EG4S20 FPGA的高保真文博展陈与应急播控多媒体系统`；
   - **Public / Private**（可见性）：**必须选择 `Public`（公开）**，以便评委专家免登录访问查看；
   - **⭐ 关键注意事项（极重要）**：
     - **不要勾选** `Add a README file`；
     - **不要勾选** `Add .gitignore`；
     - **不要选择** `Choose a license`；
     - *（原因：本地工程已为您配置好顶级的 README.md、.gitignore 和 Apache-2.0 LICENSE，若在网页端勾选会导致远程分支冲突）*；
4. 点击最下方的绿色按钮 **`Create repository`**；
5. 创建成功后，页面会显示仓库的 Git 地址，点击复制按钮复制 HTTPS 地址（格式通常为 `https://github.com/您的用户名/仓库名.git`）。

---

## 步骤二：将工程推送到 GitHub（两种方式任选其一）

### 推荐方案 A：使用一键批处理脚本（最快最简单）

1. 进入解压后的 `GitHub开源工程_EG4S20_HDMI_Player` 文件夹；
2. 鼠标双击运行 **`一键推送到GitHub.bat`**；
3. 当终端提示 `请输入您的 GitHub 仓库地址:` 时，将刚刚在 GitHub 复制的地址右键粘贴进去，按回车；
4. 系统会自动完成 `git init`、`git add`、`git commit`，并推送到 GitHub；
5. 若浏览器弹出 GitHub 授权窗口，点击 `Authorize GitCredentialManager` 授权即可完成推送！

---

### 方案 B：使用 Git 命令行操作（适合熟悉终端的用户）

打开终端（PowerShell 或 CMD），进入该工程目录，逐行输入执行：

```bash
cd "GitHub开源工程_EG4S20_HDMI_Player"

# 1. 初始化 Git 仓库
git init

# 2. 将所有文件加入暂存区
git add .

# 3. 提交本地版本
git commit -m "feat: initial commit of Anlogic EG4S20 HDMI multimedia player open source project"

# 4. 指定主分支为 main
git branch -M main

# 5. 关联您的 GitHub 远程仓库 (将下方地址替换为您实际的 GitHub 仓库地址)
git remote add origin https://github.com/您的用户名/您的仓库名.git

# 6. 推送到 GitHub
git push -u origin main
```

---

## 步骤三：验证与国赛系统填报

1. 推送完成后，刷新您的 GitHub 仓库页面，即可看到排版优雅美观的 Markdown 主页、完备的源码结构及 LICENSE 许可；
2. 复制浏览器地址栏的 URL（例如：`https://github.com/your-username/EG4S20-HDMI-Multimedia-Player`）；
3. 打开国赛作品提交系统，将该链接填入 **【五、项目工程github链接】** 栏目即可！
