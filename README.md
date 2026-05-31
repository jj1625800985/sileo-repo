# sxllm Sileo Repo

sxllm 的个人 Cydia / Sileo 软件源。

## 源地址

```
https://jj1625800985.github.io/sileo-repo/
```

## 使用方法

### 在 Sileo 中添加源

1. 打开 Sileo
2. 点击底部「**源**」标签
3. 点击右上角「**+**」
4. 输入源地址：`https://jj1625800985.github.io/sileo-repo/`
5. 点击「**添加**」

### 在 Cydia 中添加源

1. 打开 Cydia
2. 点击底部「**管理**」标签 →「**软件源**」
3. 点击右上角「**编辑**」→「**添加**」
4. 输入源地址：`https://jj1625800985.github.io/sileo-repo/`
5. 点击「**添加源**」

---

## 修改 .deb 包内容

`.deb` 文件结构：
```
xxx.deb
├── debian-binary       # 版本标记（纯文本：2.0）
├── control.tar.xz      # 包信息（包名、版本、依赖、描述等）
│   └── control         # 元信息文件（可编辑）
└── data.tar.xz         # 实际文件（dylib、plist、资源等）
```

工具脚本：`./deb.sh`，支持 `extract`（解包）和 `pack`（重打包）。

---

### 场景一：修改包名和描述（只改 control）

比如把 `com.axs.stheno` 改成你自己的包名。

**1. 解包**

```bash
cd /var/mobile/Containers/Shared/AppGroup/.jbroot-1782B84B33D0EC69/var/mobile/sileo-repo
./deb.sh extract debs/com.axs.stheno_77.1.4.8_iphoneos-arm64e.deb
```

输出会显示 control 文件内容，大概是这样的：

```
=== control 文件 ===
Package: com.axs.stheno
Name: Stheno
Version: 77.1.4.8
Architecture: iphoneos-arm64e
Description: 一个很酷的插件
Depends: mobilesubstrate
...
```

**2. 修改 control 文件**

```bash
vi /tmp/deb_work/control/control
```

将内容改为：

```
Package: com.sxllm.myplugin    ← 改包名
Name: MyPlugin                 ← 改显示名
Version: 1.0.0                 ← 改版本号
Architecture: iphoneos-arm64e
Description: 我的自定义插件     ← 改描述
Depends: mobilesubstrate
```

保存退出（vi: `Esc` → `:wq` → `Enter`）。

**3. 重打包**

```bash
./deb.sh pack debs/com.axs.stheno_77.1.4.8_iphoneos-arm64e.deb
```

注意：原文件名不变，但 Sileo 读取的是 control 里的包名，所以不影响。

---

### 场景二：修改插件文件本身（改 data）

比如改 dylib 里的字符串、替换资源图片、修改 plist 配置等。

**1. 解包**

```bash
./deb.sh extract debs/com.axs.stheno_77.1.4.8_iphoneos-arm64e.deb
```

输出会显示 data 里的文件列表，例如：

```
=== data 内容 ===
./Library/MobileSubstrate/DynamicLibraries/Stheno.dylib
./Library/MobileSubstrate/DynamicLibraries/Stheno.plist
./Library/PreferenceBundles/SthenoPrefs.bundle/...
./usr/lib/...
```

**2. 查看 data 目录结构**

```bash
# 查看所有文件
find /tmp/deb_work/data -type f

# 查看目录树（更直观）
find /tmp/deb_work/data -type f | sed 's|/tmp/deb_work/data||'
```

**3. 修改需要的文件**

```bash
# 修改 plist 配置文件
vi /tmp/deb_work/data/Library/MobileSubstrate/DynamicLibraries/Stheno.plist

# 替换资源文件（比如图标、图片）
cp /path/to/new/icon.png /tmp/deb_work/data/Library/PreferenceBundles/SthenoPrefs.bundle/icon.png

# 修改 dylib 里的文本字符串
# 先用 strings 查看字符串位置
strings /tmp/deb_work/data/Library/MobileSubstrate/DynamicLibraries/Stheno.dylib | grep -i "要改的文字"
# 用 sed 直接替换二进制里的文本
sed -i 's/旧文字/新文字/g' /tmp/deb_work/data/Library/MobileSubstrate/DynamicLibraries/Stheno.dylib
```

**4. 重打包**

```bash
./deb.sh pack debs/com.axs.stheno_77.1.4.8_iphoneos-arm64e.deb
```

---

### 场景三：修改包名 + 同时修改插件文件

最常见的情况：换个皮变成自己的插件。

```bash
# 1. 解包
./deb.sh extract debs/com.axs.stheno_77.1.4.8_iphoneos-arm64e.deb

# 2. 改 control（包名、版本、描述等）
vi /tmp/deb_work/control/control

# 3. 改 dylib 里的包名字符串（让插件读取你自己的配置）
sed -i 's/com.axs.stheno/com.sxllm.myplugin/g' /tmp/deb_work/data/Library/MobileSubstrate/DynamicLibraries/*.dylib

# 4. 改 plist 里的包名
sed -i 's/com.axs.stheno/com.sxllm.myplugin/g' /tmp/deb_work/data/Library/MobileSubstrate/DynamicLibraries/*.plist

# 5. 重打包
./deb.sh pack debs/com.axs.stheno_77.1.4.8_iphoneos-arm64e.deb
```

---

### 场景四：替换整个插件文件（移花接木）

用别人的基础包结构，换成自己的 dylib。

```bash
# 1. 解包基础包
./deb.sh extract debs/com.example.base_1.0_iphoneos-arm64e.deb

# 2. 替换 control（改成你自己的信息）
vi /tmp/deb_work/control/control

# 3. 删除旧文件，放入你自己的文件
rm -rf /tmp/deb_work/data/Library/MobileSubstrate/DynamicLibraries/*
cp /path/to/YourTweak.dylib /tmp/deb_work/data/Library/MobileSubstrate/DynamicLibraries/
cp /path/to/YourTweak.plist /tmp/deb_work/data/Library/MobileSubstrate/DynamicLibraries/

# 4. 重打包
./deb.sh pack debs/com.example.base_1.0_iphoneos-arm64e.deb
```

---

## 发布插件

修改完 deb 后，用 `deploy.sh` 一键更新源：

```bash
./deploy.sh
```

或者手动：

```bash
./update.sh              # 生成 Packages/Release
git add -A
git commit -m "update"
git push
```

## GitHub Pages 配置

1. 前往仓库 **Settings → Pages**
2. **Source** 选择 **Deploy from a branch**
3. **Branch** 选择 `main`，`/(root)`
4. 点击 **Save**
5. 等待几分钟，源即可通过以下地址访问：
   ```
   https://jj1625800985.github.io/sileo-repo/
   ```

## 目录结构

```
sileo-repo/
├── debs/           # 存放 .deb 插件包
├── CydiaIcon.png   # 源图标 (60x60)
├── Packages        # 包索引（自动生成）
├── Release         # 源发布信息（自动生成）
├── update.sh       # 自动化更新脚本
├── deploy.sh       # 一键部署脚本（更新+提交+推送）
├── deb.sh          # .deb 解包/重包工具
├── .gitignore
└── README.md
```

## 依赖

```bash
sudo apt install dpkg-dev
```
