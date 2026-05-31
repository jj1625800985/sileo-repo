# sxllm Sileo Repo

sxllm 的个人 Cydia / Sileo 软件源。

## 源地址

```
https://jj1625800985.github.io/sileo-repo/
```

## 在 Sileo 中添加源

1. 打开 Sileo
2. 点击底部「**源**」标签
3. 点击右上角「**+**」
4. 输入源地址：`https://jj1625800985.github.io/sileo-repo/`
5. 点击「**添加**」

---

## 目录结构

```
sileo-repo/
├── debs/               # 存放 .deb 插件包
├── depictions/         # 插件详情页（SileoDepiction）
│   └── com.xxx.xxx/
│       ├── info.json        # 插件展示信息
│       └── screenshots/     # 截图文件
├── icon/               # 插件图标（png）
├── scripts/            # 工具脚本
│   ├── update.sh       # 更新仓库索引（生成 Packages/Release）
│   ├── editpkg.sh      # 编辑插件展示信息（交互菜单）
│   └── deb.sh          # .deb 解包/重包工具
├── CydiaIcon.png       # 源图标 (60x60)
├── Packages            # 包索引（自动生成）
├── Release             # 源发布信息（自动生成）
├── deploy.sh           # 一键部署（更新 + git 提交 + 推送）
└── README.md
```

---

## 日常使用

### 场景一：添加新插件

```
1. 将 .deb 放入 debs/
2. 运行 ./scripts/editpkg.sh     ← 设置名称、描述、截图
3. 运行 ./deploy.sh              ← 一键部署
```

### 场景二：修改插件展示信息（名称/描述/截图）

```bash
./scripts/editpkg.sh <包ID 或 .deb>
# 示例: ./scripts/editpkg.sh com.Axs.stheno
# 或:   ./scripts/editpkg.sh debs/com.axs.stheno_1.0.deb
```
进入交互菜单后：
- `[1]` 改插件名称
- `[2]` 改插件简介
- `[3]` 改详细说明（多行文本）
- `[4]` 改图标
- `[5]` 添加截图（放到 screenshots/ 目录）
- `[6]` 全部重新填
- `[0]` 完成保存

改完后运行 `./deploy.sh` 推送生效。

### 场景三：修改 .deb 包内容（改名/版本/文件）

```bash
# 解包
./scripts/deb.sh extract <编号或关键词>

# 编辑 control 文件（包名、版本、依赖等）
# （deb.sh 内有交互菜单可以直接编辑）

# 修改插件文件
# vi /tmp/deb_work/data/Library/...

# 重打包（在 deb.sh 菜单中选择 4）
```

### 场景四：一键部署

```bash
./deploy.sh
```

自动完成：更新索引 → git 提交 → git 推送。等待 1-2 分钟 GitHub Pages 更新后即可在 Sileo 中看到。

---

## 脚本说明

| 脚本 | 路径 | 功能 |
|------|------|------|
| deploy.sh | `./deploy.sh` | 一键部署入口（更新索引 + git 提交 + 推送） |
| update.sh | `./scripts/update.sh` | 扫描 debs/ 生成 Packages / Release |
| editpkg.sh | `./scripts/editpkg.sh` | 交互式编辑插件展示信息 |
| deb.sh | `./scripts/deb.sh` | .deb 解包/重包/编辑工具 |

## 依赖

| 工具 | 用途 | 安装命令 |
|------|------|---------|
| `dpkg-deb` / `ar` | 处理 .deb 文件 | 系统自带 |
| `zstd` | 解压 zstd 压缩的包 | `apt install zstd` |
| `bzip2` / `xz` | 压缩 Packages 索引 | 系统自带 / `apt install xz-utils` |
| `git` | 版本控制 | `apt install git` |

---

## 提示

- 所有脚本都支持**交互式操作**——直接运行脚本不传参数会弹出菜单
- editpkg.sh 支持**编号选择** .deb 文件，不用记包名
- deb.sh 支持**关键词搜索** .deb 文件
- 如果提示 `safe.directory` 错误，deploy.sh 会自动处理

