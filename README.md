# sxllm Sileo Repo

sxllm 的个人 Cydia / Sileo 软件源。

## 源地址

```
https://sxllm.github.io/sileo-repo/
```

## 使用方法

### 在 Sileo 中添加源

1. 打开 Sileo
2. 点击底部「**源**」标签
3. 点击右上角「**+**」
4. 输入源地址：`https://sxllm.github.io/sileo-repo/`
5. 点击「**添加**」

### 在 Cydia 中添加源

1. 打开 Cydia
2. 点击底部「**管理**」标签 →「**软件源**」
3. 点击右上角「**编辑**」→「**添加**」
4. 输入源地址：`https://sxllm.github.io/sileo-repo/`
5. 点击「**添加源**」

## 发布插件

1. 将 `.deb` 文件放入 `debs/` 目录
2. 执行更新脚本：
   ```bash
   ./update.sh
   ```
3. 提交并推送到 GitHub：
   ```bash
   git add -A
   git commit -m "update packages"
   git push
   ```

## GitHub Pages 配置

1. 前往仓库 **Settings → Pages**
2. **Source** 选择 **Deploy from a branch**
3. **Branch** 选择 `main`，`/(root)`
4. 点击 **Save**
5. 等待几分钟，源即可通过以下地址访问：
   ```
   https://sxllm.github.io/sileo-repo/
   ```

## 目录结构

```
sileo-repo/
├── debs/           # 存放 .deb 插件包
├── CydiaIcon.png   # 源图标 (60x60)
├── Packages        # 包索引（自动生成）
├── Release         # 源发布信息（自动生成）
├── update.sh       # 自动化更新脚本
├── .gitignore
└── README.md
```

## 依赖

更新脚本需要 `dpkg-dev`：

```bash
sudo apt install dpkg-dev
```
