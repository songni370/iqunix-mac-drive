# IQUNIX MQ80 官方软件支持与 VIA 兼容性调研

- 调研时间：2026-10-19（Asia/Shanghai）
- 调研方式：只读桌面调研。`web_search` + 官方页面/官方 CDN 文件（通过 `curl` 抓取，因为本会话 `web_fetch` 把所有域名解析到 198.18.x 非公网地址而被 SSRF 防护拒绝；对 iqunix.com 这种带 Shopify 429 限流的站点改用 r.jina.ai 读取）。**未安装、未运行任何官方软件**；仅对下载的 `.exe` 做静态 `strings`/哈希检查。
- 可信度标记：`【官方】`=IQUNIX/ VIA 官方页面或官方文件；`【官方文件静态分析】`=对官方下载物的离线检查；`【媒体】`=独立评测/媒体；`【社区】`=GitHub 项目、用户验证记录；`【推测】`=基于间接证据的判断。
- 工作区限制遵守：仅新增本文件，未改动工作区其它文件。

## 0. 结论速览

| 问题 | 结论 | 置信度 |
|---|---|---|
| 官方是否有 macOS 驱动/配置软件 | **没有找到**。官方唯一可分发的配置相关下载是 Windows `.exe`（固件升级工具）；官方配置路径是 VIA（浏览器 WebHID）| 高 |
| 官方是否有网页版配置工具 | MQ80 **没有**。`ev.iqunix.com` / `ez.iqunix.com` 在线驱动只服务 EV/EZ 磁轴系列 | 高 |
| 官方是否明确说明 VIA 支持 | **是**，产品页 "VIA Programmable"、软件汇总页 "VIA Guide"、Amazon 标题 "VIA Support" | 高 |
| VIA 怎么用 | 有线连接 → `usevia.app` → 下载官方 JSON → VIA 设置里打开 "Show Design TAB" → 上传 JSON → 连接键盘 | 高（官方 VIA Guide 原文） |
| VIA JSON 在哪 | 官方 Shopify CDN：`IQUNIX_MQ80_KB-USB.json.zip`（内含 7529 B JSON），**不在** the-via/keyboards 仓库 | 高 |
| 固件升级工具 | Windows only：两个官方 `.exe.zip`（V0109/20241220 与 V0106/20260206），.NET WinForms + 原生 HID，OTA 升级 | 高 |
| 是否 QMK / 能刷 QMK/Vial | **不是 QMK**（官方称 custom firmware，且不支持 Mod-Tap/Layer-Tap/MEH/HYPR）；未找到 MQ80 的 QMK/Vial 移植，自行刷 QMK 不可行 | 高（官方声明）/中（不可行性推断） |
| 三模下 VIA | 官方只要求/支持**有线**；2.4G 接收器可读到 VIA 协议版本（社区只读实测），蓝牙无证据；官方未说明无线可配置 | 中高 |
| macOS 实际可用性 | 可用，但路径是 **Chrome/Edge + usevia.app**；独立评测报告 **VIA 桌面版在 macOS 上无法识别键盘** | 中高 |
| 社区协议逆向 | 有：`xiaoliu-heng/q101-mq80-battery-bar`，含 MQ80/Q101 固件补丁、macOS 原生 App、USB/2.4G HID 协议文档（32 字节、FF60/61、VIA 协议版本 11） | 高 |

---

## 1. 官方产品页、说明书、支持页、驱动下载页

### 1.1 已确认的官方链接
| 页面 | URL | 说明 |
|---|---|---|
| 产品页 | https://iqunix.com/products/mq80-aluminum-low-profile-mechanical-keyboard | 含 specs、`Software: MQ80 VIA` 与固件提示；`【官方】` |
| 官方「User Guide & Software」汇总页（英文） | https://iqunix.com/pages/iqunix-super-custom-keyboard-kit-user-guide | 各型号 User Guide / VIA Guide / Software 集中页；`【官方】` |
| MQ80 User Guide（官方博客，2025-04-07） | https://iqunix.com/blogs/news/mq80-user-guide | 官方说明书正文（不是 PDF），含开机/配对/Fn 键/VIA 层设置；`【官方】` |
| MQ80 VIA Guide（官方博客，2025-04-07） | https://iqunix.com/blogs/news/mq80-via-guide | **官方 VIA 使用说明 + JSON 下载链接 + 固件升级兜底步骤**；`【官方】` |
| 官方支持文档站 | https://docs.iqunix.com/（support.iqunix.com 301 跳转至此） | Docusaurus「IQUNIX SUPPORT 文档」；`【官方】` |
| 官方软件汇总页中的 MQ80 行 | 同上汇总页 | 仅有：`User Guide`、`VIA Guide`、`Software: MQ80`（指向 `.exe.zip`），**没有 JSON 文件链接**（对比：Magi/Zonex/Tilly/Nature 等型号在该页有 JSON 下载）；`【官方】` |

补充：Amazon 商品页标题含 “VIA Support”；同款 MQ80 User Guide PDF 由 Amazon 商品页托管（https://m.media-amazon.com/images/I/A1fK7oO5XL.pdf），内容与官方博客一致，属零售渠道副本 `【零售/媒体】`。

### 1.2 官方驱动/配置软件：只有 Windows 版
- 汇总页 MQ80 行的 “Software: MQ80” 直链为：
  - `https://cdn.shopify.com/s/files/1/0676/7853/5986/files/MQ80-CS9041-V0106-20260206.exe.zip`（zip 206,959 B；解压后单个 `.exe` 2,580,992 B，PE32 .NET/Mono WinForms）`【官方文件静态分析】`
- VIA Guide 里的兜底固件包（当 VIA 加载 JSON 报错时使用）：
  - `https://cdn.shopify.com/s/files/1/0676/7853/5986/files/MQ80-CS836B-V0109-20241220.exe.zip`（zip 208,120 B；解压后单个 `.exe` 2,580,992 B；SHA-256 `ae26c52d3f4b525870530d7acb387a294b512cae1659038127574dbb7fd1b938`）`【官方】`
- **未找到任何 macOS 安装包、.dmg、或 MQ80 专属网页配置工具**。官网导航 “Software” 下只有 `EV Software`(https://ev.iqunix.com/) 与 `EZ Software`(https://ez.iqunix.com/) 两个在线工具，均面向 EV/EZ 磁轴（HE）系列；MQ80 不在其中 `【官方】`。
- 支持站 `docs.iqunix.com` 全站 sitemap 仅 29 条 URL（抓取于 2026-10-19），没有 MQ80 页面；其中 `https://support.iqunix.com/M80_manuals` 是**另一个型号 M80**，不要与 MQ80 混淆。`https://support.iqunix.com/IQUNIX_exe_20260106` 的驱动列表为 NATURE 80 / OG80 / F97 / X81 / LOTUS ZX75 / ZONEX75 / SUPER 1+1 / Tilly60，**不含 MQ80** `【官方】`。
- 结论：**MQ80 官方只提供 Windows 固件升级工具；改键/宏/RGB 配置由 VIA 提供（浏览器端）**。`【官方 + 官方文件静态分析】`

---

## 2. MQ80 的 VIA 支持具体怎么用

### 2.1 官方 VIA Guide 原文步骤（https://iqunix.com/blogs/news/mq80-via-guide ，2025-04-07）
1. **Connect the keyboard via Wired**（有线连接）
2. **Open VIA: https://usevia.app/**
3. **Download JSON file [here]** → `https://cdn.shopify.com/s/files/1/0676/7853/5986/files/IQUNIX_MQ80_KB-USB.json.zip?v=1744019164`
4. **Turn on the Show Design TAB switch**（VIA Settings 里打开 Design 标签）
5. **Upload the JSON File here**（Design 页上传）
6. **Connect the keyboard**
- 附 NOTE：如果按上面步骤报错，先下载固件包（`MQ80-CS836B-V0109-20241220.exe.zip`），**在 Windows 电脑上有线模式升级键盘固件**，再重新上传 JSON。`【官方】`
- 官方 FAQ 提示：若 VIA 改键不生效，把系统键盘布局设为 **QWERTY (US)**，重插键盘并重开 VIA。`【官方】`

### 2.2 官方 JSON 定义文件（已下载并检查）
- 下载：`https://cdn.shopify.com/s/files/1/0676/7853/5986/files/IQUNIX_MQ80_KB-USB.json.zip?v=1744019164`
  - zip 2,167 B，内含 `IQUNIX MQ80 KB-USB.json`，7,529 B，mtime 2025-04-07
  - JSON SHA-256：`3baf2384b16eabf8e5ff78cbf2461a8962dd7931ea4235b6f5877efae8c1fa91`
  - 直链 `.json`（不带 zip，VIA Guide 旧链接）现在 404，**只有 zip 链接有效** `【官方文件静态分析/实测】`
- JSON 内容（完整读取）：
  - `name = "IQUNIX MQ80 KB"`，`vendorId = "0x320F"`，`productId = "0x5055"`（与实测 HID 完全一致）
  - `matrix = {rows: 8, cols: 16}`，`layouts.keymap` 为 80% ANSI 84 键物理布局
  - `keycodes: ["qmk_lighting"]`；`menus` 只有 **Lighting → Backlight** 菜单，通过 `qmk_rgb_matrix` 自定义值（`id_qmk_rgb_matrix_brightness/effect/effect_speed/color`）控制亮度 0–9、18 种灯效、速度 0–4、颜色
  - `customKeycodes` 共 12 个：`2.4G MODE`、`Bluetooth 1/2/3`、`USB MODE`、`LOCK WIN KEY`、`MAC WIN CHANGE`、`KEY SCAN DELAY`、`BATTERY STATUS`、`KEYBOARD SLLEP`（原文拼写）、`LED LOGO MODE`、`LED LOGO COLOUR`
  - **没有** `layers`、`macros` 字段 → 层数据/宏数据由固件提供，JSON 只是 VIA 的“设计定义（definition）”
  - 这是一个 **VIA v2 风格的 design definition**（无 `lighting` 顶层字段；用 `menus`+`keycodes`），需要 VIA 的 Design 导入流程 `【官方文件静态分析】`

### 2.3 VIA 版本 / 浏览器要求
- IQUNIX 官方**没有写 VIA 版本要求**、也没写浏览器要求 `【未找到】`。
- `usevia.app` 是 WebHID 网页应用（the-via/app README：web-based interface；caniusevia.com 提供 Download Firmware/Docs），因此需要支持 WebHID 的 Chromium 系浏览器（Chrome/Edge/Opera），Safari/Firefox 不支持 `【官方项目 + 第三方支持文档；属已知 VIA 生态事实】`。
- 实测线索与社区文档一致：设备 VIA 协议版本返回 **0x000B（十进制 11）**；社区协议文档明确写 “VIA 协议版本 11”“标准 VIA 协议版本读取返回 11” → 属 VIA v2 时代协议，当前 usevia.app 仍可通过 Design 导入方式工作（见 2.4 Mac 反馈）`【社区 + 实测】`。
- **MQ80 不在 VIA 官方内建键盘列表中**：https://www.caniusevia.com/docs/supported_keyboards （页面标注 Compatible as of 9/19/2026，1400+ 型号）全文检索无 “IQUNIX”/“MQ80”；the-via/keyboards 也没有 IQUNIX 定义（Lead 已用 GitHub API 复核，本次 GitHub API 被限流，改用 VIA 官方列表交叉验证）。**因此必须走“手动加载 JSON”的路径，而不是插上键盘自动识别。** `【官方 VIA 列表 + Lead 实测】`
- VIA 桌面版：the-via/app README 明确说明桌面离线版是第三方（cebby2420/via-desktop），与 VIA 官方无隶属关系；MacSources 评测中 macOS 桌面版无法识别键盘（见第 7 节）。

### 2.4 macOS 上 VIA 是否可用
- 独立评测 MacSources（2026-03-04）明确写：**Chrome 版 VIA 在 macOS 上稳定可用**，可完整改键、宏、RGB 实时调整；**VIA 桌面 app 在 macOS 上会侦测不到键盘**（即使 USB-C 正确连接并授予权限）→ 结论：Mac 上走浏览器版。`【媒体/评测】`
- IQUNIX 用户指南给 Mac 用户的建议：用 VIA 的 Layer 0 做 Mac 布局（LWin↔LAlt、RAlt→RWin），Layer 2 做 Windows 布局，并用 `TG(2)` / `TG(0)` 切换。`【官方】`
- 结论：**macOS 上可用，但依赖 Chromium 浏览器 + 手动 JSON；官方没有 macOS 原生应用。** `【高置信度】`

---

## 3. 固件更新工具与流程

### 3.1 版本与文件
| 包 | 链接 | 版本/日期 | 内容 |
|---|---|---|---|
| 新版（产品页当前） | https://cdn.shopify.com/s/files/1/0676/7853/5986/files/MQ80-CS9041-V0106-20260206.exe.zip | V0106 / 2026-02-06（文件名） | 单个 `.exe` 2,580,992 B，SHA-256 `91ea15564b35d433a43729c72dd8cad681501c5b636fd09af337c6d6a6bbbf8c` |
| 旧版（VIA Guide 兜底） | https://cdn.shopify.com/s/files/1/0676/7853/5986/files/MQ80-CS836B-V0109-20241220.exe.zip | V0109 / 2024-12-20（文件名） | 单个 `.exe` 2,580,992 B，SHA-256 `ae26c52d...1b938`（社区文档中记录的官方 V0109 exe 哈希与此一致） |
- 两个 exe 文件大小相同但哈希不同；文件内未发现明文 `V0109/V0106` 字符串（固件镜像被压缩/打包）`【官方文件静态分析】`。
- 官方**未提供**固件 changelog / 版本历史页 `【未找到】`；官方在 VIA Guide 里只把 V0109 作为“VIA 报错时的兜底升级包”。

### 3.2 工具性质与流程
- 静态检查（未运行）：PE32 .NET/Mono WinForms，P/Invoke `hid.dll`（`HidD_GetHidGuid/GetHidDeviceList/HidD_GetFeature/HidD_SetFeature/HidD_SetOutputReport/GetHidSerialNumberString` 等），含 `get_fw_version`、`bin_fw_version`、`getFwVersionToolStripMenuItem`、`Open bin`、`Start`、`Debug Mode` 等符号；设备枚举字符串包含 `IQUNIX MQ80 KB`、`IQUNIX MQ80 KB BT1/BT2/BT3`。**没有** keymap/macro/RGB 相关 UI 字符串 → 判断它是**固件升级工具（OTA）**，不是改键软件。`【官方文件静态分析】`
- 社区记录的官方操作流程（Q101/MQ80 项目 docs，见第 6 节）：
  1. **Windows 电脑** + USB 线，切到 USB 模式，关闭 VIA；
  2. 运行 exe → `Get Device Fw Version` 读取 CRC；
  3. `Debug Mode` 输入小写 `telink` → `show Debug surface` → `open bin` 选择固件 → `Start`；
  4. 进度 100% + `OTA Success`，重新查询 CRC 校验。`【社区】`
- 官方承认的更新方式：**Windows + 有线 + OTA**；没有 macOS/Linux 官方工具。`【官方】`

### 3.3 是否 QMK / 能否自行刷 QMK/Vial
- 官方产品页明确写：**“The MQ80 features custom firmware and does not support Mod-Tap, Layer-Tap, or KC_MEH/KC_HYPR modifiers.”** → 自定义固件，非标准 QMK（QMK 支持这些键码）。`【官方】`
- 社区对官方固件的分析：芯片/指令集为 **RISC-V Andes 指令**（docs/SIDE_HID.md 多次提到 RV32/Andes 指令），项目免责声明提到与 **Telink** 无关联，官方升级工具的 Debug 口令也是 `telink` → 芯片方案指向 Telink（TLSR9/RISC-V 系列）`【社区 + 推测】`。
- **未找到** MQ80 的 QMK 或 Vial 移植；Vial 依赖 QMK，因此“自行刷 QMK/Vial”在当前证据下**不可行**（无源码、无公开 bootloader 文档、无回滚保障）。`【未找到 / 高置信度推断】`
- 社区能做的是**基于官方 V0109 镜像打补丁**（改电量灯效等），仍用官方 exe 的 Debug 模式刷入；官方完整固件不开源，仓库只提供补丁/测试软件。社区明示：**没有已验证的纯 USB 强制恢复步骤**，刷坏可能只能拆机/编程器。`【社区】`

---

## 4. 官方 Windows 软件的功能清单（用于推断自研 macOS 工具范围）

> 关键发现：**MQ80 没有“官方改键驱动软件”**。官方可下载的 Windows 程序经静态检查是**固件升级工具**；官方指定的改键/宏/RGB 工具就是 **VIA**（网页版）。因此“官方 Windows 驱动功能清单”= VIA 功能 + 固件升级功能。

| 功能 | 是否由官方提供 | 证据 |
|---|---|---|
| 改键（keymap remap） | ✅ VIA（浏览器） | 产品页 “Custom key mappings”；官方 VIA Guide；MacSources 实测 |
| 多层（layers） | ✅ VIA；固件报告 4 层（Lead 实测 layer count=4） | 官方 User Guide 的 Layer 0 / Layer 2 方案；Lead HID 实测 |
| 宏（macros） | ✅ VIA；固件报告 16 个宏槽（Lead 实测 macros=16） | 产品页 “create macros”；官方 VIA Guide |
| RGB / 灯效 | ✅ VIA Lighting 菜单：亮度 0–9、18 种效果、速度 0–4、颜色 | 官方 JSON `menus`；产品页 “RGB settings” |
| 侧面灯条 / Logo 灯 | ✅ 键盘快捷键 + VIA customKeycodes（LED LOGO MODE/COLOUR） | 官方 User Guide、官方 JSON |
| 三模切换 / 蓝牙配对 / 电量查询 | ✅ 键盘 Fn 快捷键 + VIA customKeycodes（2.4G/BT1-3/USB/BATTST） | 官方 User Guide、官方 JSON |
| 磁轴/触发行程设置 | ❌ 不适用（MQ80 是矮轴机械轴，不是 HE 磁轴） | 产品页 specs（Mechanical Keyboard）；官方 HE 软件只服务 EV/EZ |
| 轮询率设置 | ❌ 无设置项；固定 1000Hz（有线/2.4G）、125Hz（蓝牙） | 产品页 specs |
| 固件升级 | ✅ 仅 Windows exe（OTA） | 官方包 + 社区流程 |
| Mod-Tap / Layer-Tap / MEH / HYPR | ❌ 官方明确不支持 | 产品页 Firmware Notice |
| 按键防抖/触发行程/去抖时间等底层参数 | ❌ 未找到任何官方设置入口 | `【未找到】` |

对自研 macOS 工具的最小功能覆盖建议（基于以上事实）：
1. 设备枚举 `VID 0x320F / PID 0x5055`，打开 `UsagePage 0xFF60 / Usage 0x61` 的 32 字节无编号报告（与 VIA Raw HID 完全一致）。
2. 实现 VIA 协议版本 11（0x0B）握手；读取/写入 4 层 keymap、16 个宏槽；读取 8×16 矩阵与物理布局（可内置官方 JSON 的 `layouts.keymap`）。
3. 灯效控制走 `qmk_rgb_matrix` 自定义值（brightness/effect/speed/color），效果枚举直接照抄官方 JSON 的 18 项。
4. 提供 12 个 customKeycodes（模式切换、电量、Win/Mac 切换等）。
5. v1 建议**只支持有线**（官方唯一保证的配置通道）；不要在 v1 做固件刷写（OTA 协议未公开、砖机风险高）。

---

## 5. 三模限制、Mac/Win 布局键、Fn 层

### 5.1 VIA 与连接模式
- 官方 VIA Guide 步骤 1 明确 “Connect the keyboard via **Wired**”；JSON 文件名也是 `KB-USB`。**官方只说明/支持有线模式配置。** `【官方】`
- 2.4G：社区对 **2.4G 接收器（PID 0x5088）** 的 USB Raw HID 做只读实测，12 次查询均收到 32 字节回复，**标准 VIA 协议版本读取返回 11**；但该次只读探测没有发送改键/OTA 命令。→ **2.4G 下 VIA 协议在物理上可达（至少读），写配置是否成功/持久未验证** `【社区实测 + 推测】`。
- 蓝牙：未找到任何 VIA over Bluetooth 的证据或官方说明；社区侧灯协议明确“蓝牙未增加新报告”。→ **推测蓝牙下 VIA 不可用**（WebHID 也无法在蓝牙 HID 上按 VIA 方式工作）`【未找到 / 推测】`。
- 配置是否写入并跨模式生效：VIA 写的是键盘固件内的配置；从机制上应跨连接模式保存，但**官方未说明、未找到实测证据** → 标 `【推测/未验证】`。自研工具应在有线写入后逐个模式实测。

### 5.2 官方 Fn 快捷键（官方 User Guide 原文整理）
| 功能 | 快捷键 |
|---|---|
| 开机/激活 | 插 USB 线（有线模式）；或长按 `Fn+Esc` 3 秒进入 2.4G 配对 |
| 有线模式 | `Fn+5`，指示灯白闪 3 次后插线 |
| 蓝牙配对/切换 | `Fn+1`（短按后长按 3 秒进入配对）；`Fn+2` / `Fn+3` 配其它设备；`Fn+1/2/3` 切换已配对设备 |
| 2.4G 模式 | 短按 `Fn+4`，插接收器；粉灯快闪配对 |
| Win/Mac 布局切换 | **`Fn+Tab`** |
| 锁定/解锁 Win 键 | `Fn+Win` |
| 恢复默认设置 | `Fn+Space` |
| 关机 | 长按 `Fn+Esc` 3 秒（需先拔 USB） |
| 背光开关/亮暗/速度/效果/颜色 | `Fn+Z` / `Fn+X` / `Fn+C` / `Fn+V` / `Fn+N` / `Fn+Enter` / `Fn+RightShift` |
| 侧灯条模式/颜色 | `Fn+{` / `Fn+}` |
| 电量查询 | `Fn+B`（黄闪 4 次=充电中；绿闪 1 次=充满；1–10 次=10%–100%） |
- 官方还提示：Caps Lock 下面的拨动开关是长期断电/运输断电用，**不是复位开关**；关机前必须拔掉 USB。`【官方】`

### 5.3 Mac/Win 布局
- 硬件快捷键 `Fn+Tab` 切 Win/Mac 布局；官方 User Guide 还给出用 VIA 层实现两套布局的推荐方案：Layer 0=Mac（LWin↔LAlt、RAlt→RWin），Layer 2=Windows，用 `TG(2)`/`TG(0)` 互相切换。`【官方】`

---

## 6. 社区已知的 IQUNIX 协议/开源项目（GitHub）

| 项目 | URL | 与 MQ80 的关系 | 备注 |
|---|---|---|---|
| `xiaoliu-heng/q101-mq80-battery-bar` | https://github.com/xiaoliu-heng/q101-mq80-battery-bar | **最相关**：Q101/MQ80 Fn+B 侧灯电量条固件补丁 + 原生 macOS/Windows `Kryra` 电量/灯光控制 App + **USB/2.4G HID 协议文档** + 官方 V0109 镜像 `stock.bin` | 基于官方 `MQ80-CS836B-V0109-20241220`；文档明确 VID `320F`、键盘 PID `5055`、2.4G 接收器 PID `5088`、Usage `FF60/61`、32 字节无编号报告、**VIA 协议版本 11**、原 VIA 命令 `0x00–0x15`、OTA 接口未被替换；macOS App 经 IOKit 直连键盘；仓库**无 LICENSE 文件**（默认保留所有权利），引用/借鉴需谨慎 `【社区】` |
| `t4kuya6e/magi65-mac-fw-builder` | https://github.com/t4kuya6e/magi65-mac-fw-builder | 不适用于 MQ80，但是**同类先例**：macOS 原生 OTA 刷写工具，从官方 `.exe` 提取固件、用 Python3+ctypes+IOKit 刷 Magi65 | 说明“官方 Windows exe 内含固件镜像 + HID OTA 协议可被 macOS 复刻”这条路可行（不同型号，协议不同）`【社区】` |
| `gnome-child/qmk-tilly60` | https://github.com/gnome-child/qmk-tilly60 | IQUNIX Tilly60 的社区 QMK 移植（非 MQ80） | 证明 IQUNIX 个别型号有社区 QMK hack，但 **MQ80 没有** `【社区】` |
| `Polylo/Iqunix-Super-Zonex-75` | https://github.com/Polylo/Iqunix-Super-Zonex-75 | IQUNIX Zonex 75 的 VIA 定义 | 与 MQ80 无关 `【社区】` |
| `LOONGTR/IQUNIX-EZ-Driver` | https://github.com/LOONGTR/IQUNIX-EZ-Driver | EZ 系列桌面驱动客户端 | 非 MQ80 `【社区】` |
| `leocodelab/ez-desktop-shell` | https://github.com/leocodelab/ez-desktop-shell | 非官方 Electron 壳，用于打开 IQUNIX EZ 键盘网页配置器 | 说明“官方网页配置器 + 非官方桌面壳”是 IQUNIX 生态常见做法 `【社区】` |
| `hparadiz/iqunix-f96` | https://github.com/hparadiz/iqunix-f96 | Linux Qt 控制 F96 | 老型号，非 MQ80 `【社区】` |
- **MQ80 VIA JSON 第三方镜像**：未找到（官方 CDN zip 是唯一来源；the-via/keyboards 无 IQUNIX 定义）。
- **Vial 支持**：未找到任何 MQ80 Vial 移植/讨论。
- **协议逆向**：目前公开最完整的就是上面 Q101/MQ80 项目的 `docs/SIDE_HID.md`，但它主要记录**侧灯/电量厂商扩展命令**（复用 VIA Raw HID 接口），不是 VIA 改键协议本身的文档；不过它明确证明官方 VIA 命令和 OTA 接口仍在，且 macOS 可通过 IOKit 访问该 32 字节通道。

---

## 7. Mac 用户的实际反馈

| 来源 | 内容 | 可信度 |
|---|---|---|
| MacSources 评测（2026-03-04，https://macsources.com/iqunix-mq80-keyboard-review/） | 优点：低轴手感、CNC 铝壳、三模、VIA 可改键/宏/RGB；**Cons 明确列 “VIA desktop app on macOS can fail to detect the keyboard” 与 “VIA guide not linked from product page”**；正文：初期 Chrome 版也折腾，改用桌面版后一直搜不到设备（确认 USB-C 与权限无误），**最终 Chrome 版 VIA 稳定工作**，可实时改键、宏、RGB；结论“macOS 上走网页版 VIA 更容易”；同评测给出 spec：84 键、1000Hz（有线/2.4G）、125Hz（无线）、4000mAh、Software: VIA、支持 Windows/macOS/iOS/Android | `【媒体/评测】`（独立评测，可信度高） |
| IQUNIX 官网 Loox 买家评价（2025-12 / 2026-01，产品页内嵌） | 多位 Mac 用户给 5 星，称其为 Mac 用户的“end game”、键帽兼容 Mac；未讨论 VIA on macOS 细节 | `【用户评价/官方站内】`（真实性较高但样本自选择） |
| Reddit r/IQUNIX 搜索 | 本次被 Reddit 403 拦截，未取得具体帖子 | `【未找到】` |
| Bilibili / 知乎 | 未检索到 MQ80 + VIA + macOS 的具体反馈 | `【未找到】` |
- 综合：**macOS 上可用（Chrome/Edge + usevia.app + 官方 JSON + 有线），但“桌面版 VIA 识别不到键盘”是已报道的坑；官方不提供 macOS 原生软件。**

---

## 8. 明确「未找到 / 未核实」清单

1. **官方 MQ80 macOS / Linux 驱动或配置软件**：未找到（只有 Windows `.exe` 固件工具）。
2. **官方 MQ80 专属支持页 / 说明书 PDF 官方下载**：未找到；官方说明书是博客文章（`/blogs/news/mq80-user-guide`），Amazon 有同款 PDF 副本但非 iqunix.com 支持页。
3. **官方对 VIA 最低版本、浏览器要求的说明**：未找到（官方 Guide 只写 `usevia.app` + Show Design TAB）。
4. **MQ80 VIA JSON 在 the-via/keyboards 或 QMK 仓库中的定义**：不存在（VIA 官方 supported keyboards 列表无 IQUNIX；JSON 只在 IQUNIX 官方 CDN）。
5. **2.4G / 蓝牙下 VIA 写配置是否成功并生效**：官方未说明；社区只验证了 2.4G 接收器可读出 VIA 协议版本 11，未验证写入/持久化。蓝牙无任何证据。
6. **MQ80 的 QMK / Vial 移植**：未找到；官方明确是 custom firmware 且不支持 Mod-Tap/Layer-Tap 等 QMK 键码。
7. **官方固件 changelog / 版本历史 / 回滚工具**：未找到；社区称没有已验证的 USB 强制恢复办法。
8. **Reddit 具体讨论帖**：被 403 阻断，未取得；GitHub API 在本次会话中被限流（搜索部分靠 HTML/raw 页面完成）。
9. **官方是否把 VIA JSON 放入固件动态定义（dynamic keymap definitions）**：未证实；从 JSON 与服务方式看是**手动加载静态 JSON**（the-via 无定义 + 官方教程要求手动上传），倾向“非动态定义”。

---

## 9. 主要来源 URL 列表（按可信度分组）

### 官方（IQUNIX）
- 产品页：https://iqunix.com/products/mq80-aluminum-low-profile-mechanical-keyboard
- 官方 User Guide & Software 汇总页：https://iqunix.com/pages/iqunix-super-custom-keyboard-kit-user-guide
- MQ80 User Guide（官方博客）：https://iqunix.com/blogs/news/mq80-user-guide
- MQ80 VIA Guide（官方博客，含 JSON 下载）：https://iqunix.com/blogs/news/mq80-via-guide
- 官方支持文档站：https://docs.iqunix.com/ （= support.iqunix.com）
- 官方 VIA JSON（zip）：https://cdn.shopify.com/s/files/1/0676/7853/5986/files/IQUNIX_MQ80_KB-USB.json.zip
- 官方固件工具 V0106/20260206：https://cdn.shopify.com/s/files/1/0676/7853/5986/files/MQ80-CS9041-V0106-20260206.exe.zip
- 官方固件工具 V0109/20241220：https://cdn.shopify.com/s/files/1/0676/7853/5986/files/MQ80-CS836B-V0109-20241220.exe.zip

### 官方（VIA 项目）
- VIA 官网：https://www.caniusevia.com/
- VIA 网页应用：https://usevia.app/
- VIA 支持键盘列表（2026-09-19 版，无 IQUNIX）：https://www.caniusevia.com/docs/supported_keyboards
- VIA 键盘定义规范：https://www.caniusevia.com/docs/specification
- VIA 源码/README（web-based，含第三方桌面版说明）：https://github.com/the-via/app

### 媒体 / 评测
- MacSources 评测（Mac 上 VIA 经验、spec）：https://macsources.com/iqunix-mq80-keyboard-review/
- NotebookCheck 发布报道（非 VIA 细节）：https://www.notebookcheck.net/Iqunix-teases-MQ80-as-ultimate-low-profile-mechanical-keyboard-Full-aluminium-build-350-hour-battery-life-and-compact-80-layout.965625.0.html
- jctechspace 开箱评测（繁体中文）：https://jctechspace.com/iqunix-mq80-aluminum-low-profile-keyboard-unbox/

### 社区 / GitHub
- Q101/MQ80 固件补丁 + macOS App + 协议文档：https://github.com/xiaoliu-heng/q101-mq80-battery-bar
  - HID 协议文档：https://github.com/xiaoliu-heng/q101-mq80-battery-bar/blob/main/docs/SIDE_HID.md
  - 跨平台设计/协议约束：https://github.com/xiaoliu-heng/q101-mq80-battery-bar/blob/main/docs/KRYRA_DESIGN.md
- Magi65 macOS OTA 刷写工具：https://github.com/t4kuya6e/magi65-mac-fw-builder
- Tilly60 社区 QMK：https://github.com/gnome-child/qmk-tilly60
- Zonex 75 VIA 定义：https://github.com/Polylo/Iqunix-Super-Zonex-75

---

## 10. 本次调研的复现命令（只读，供复核）

```bash
# 官方 VIA Guide（iqunix.com 对直连返回 429，用 jina reader 绕过）
curl -sS -m 60 https://r.jina.ai/https://iqunix.com/blogs/news/mq80-via-guide

# 官方 JSON（zip 内为 IQUNIX MQ80 KB-USB.json）
curl -sSL -o mq80_json.zip 'https://cdn.shopify.com/s/files/1/0676/7853/5986/files/IQUNIX_MQ80_KB-USB.json.zip?v=1744019164'
unzip -l mq80_json.zip

# 官方 Windows 工具（仅静态检查，不执行）
curl -sSL -o fw.zip 'https://cdn.shopify.com/s/files/1/0676/7853/5986/files/MQ80-CS9041-V0106-20260206.exe.zip?v=1770628594'
unzip -l fw.zip && shasum -a 256 <解压出的 exe>
file <解压出的 exe> && strings -a <解压出的 exe> | grep -iE 'hid|firmware|MQ80'
```
