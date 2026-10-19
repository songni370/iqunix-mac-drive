# IQUNIX MQ80 · macOS 原生配置工具可行性报告

- 报告时间：2026-10-19（Asia/Shanghai）
- 测试设备：IQUNIX MQ80（USB 有线模式，`Product=IQUNIX MQ80 KB`，`Manufacturer=RDR`，`VID=0x320F`，`PID=0x5055`）
- 测试主机：macOS 26.6.2 (25G83)，Apple Silicon (arm64)，Command Line Tools 26.x / Swift 6.4
- 结论：**可行。核心配置协议已在真机上验证打通，可以做一个完全离线、原生 SwiftUI 的 macOS 配置 App。**
- 实现状态（2026-10-19）：**已实现并交付 v0.1.0**，App/CLI/Homebrew cask 均可运行，真机读写/备份/恢复已通过端到端验证。

---

## 1. 一句话结论

官方没有 macOS 驱动；官方 Windows 软件是**固件升级工具**而非改键工具。但键盘固件内置了 **VIA Raw HID 协议**（`0xFF60/0x61`，协议版本 `0x000B = 11`），官方另提供 **VIA JSON 键盘定义**。因此：

- **立刻可用**：Chrome/Edge + `usevia.app` + 官方 JSON（手动导入 Design 定义），即可在 macOS 上改键、调灯效。
- **推荐自研**：原生 SwiftUI App 直连 IOKit HID，实现改键、4 层编辑、RGB 灯效、配置备份/恢复，离线、无需浏览器、体验和可靠性都更好。
- **明确边界**：配置仅建议 USB 有线模式（2.4G 接收器 `PID 0x5088` 有 VIA Raw HID，社区验证可读协议版本，写入待验证；蓝牙无证据）；固件升级在 v1 不做；原版固件没有电脑可读电量/侧灯接口。

---

## 2. 真机实测证据（最重要）

以下全部由仓库内 `tools/probe/` 的原始 C 探针在本机真机执行，非推测。

### 2.1 设备识别

| 属性 | 值 |
|---|---|
| USB Product | `IQUNIX MQ80 KB` |
| Manufacturer | `RDR` |
| Vendor ID / Product ID | `0x320F` / `0x5055` |
| VIA Raw HID 接口 | Usage Page `0xFF60`，Usage `0x61` |
| 报文格式 | 32 字节 Input / 32 字节 Output，无 Report ID（Report ID 0） |
| 另一厂商接口 | Usage Page `0xFF1C` / Usage `0x92`，输入 8B、输出 63B（Report ID 4）——官方/社区私有通道，本次未逆向，不影响 VIA 功能 |
| 权限 | 首次 `IOHIDManagerOpen` 返回 `0xE00002E2`（`kIOReturnNotPermitted`），在「系统设置 → 隐私与安全性 → 输入监控」授权宿主 App 后返回 `0x00000000`；无需 root |

### 2.2 已验证的 VIA 协议能力

| 能力 | 命令 | 实测结果 |
|---|---|---|
| 协议版本 | `0x01` | 返回 `01 00 0B` → **协议版本 11** |
| 动态层数 | `0x11` | 返回 `11 04` → **4 层** |
| 键位整体读取 | `0x12`（offset hi/lo + size ≤ 28B） | 成功读出 **4 层 × 256 字节 = 1024 字节**动态键位 |
| 键位写入 | `0x13` | 将空矩阵位 `0x0000` 改写为 `0x0004`，回读一致；随后还原为 `0x0000`，回读一致 → **写入链路可用** |
| 键位矩阵 | 官方 JSON + 实测 | `rows=8, cols=16`，行优先，1 键码 = 2 字节大端 |
| 层内容 | — | Layer 0 为基础层；**Layer 1 是 Fn 层**（媒体键 / RGB 控制 / 自定义功能键，与 Layer 0 有 30 处差异）；Layer 2、3 当前与 Layer 0 相同 |
| RGB 灯效读取 | `0x08` channel `3` | 亮度 `1`、效果 `2`、速度 `3`、颜色 `4` 均可读：亮度 5、效果 1（WAVE）、速度 2、颜色 hue=0/sat=255 |
| RGB 灯效写入 | `0x07` channel `3` | `[07 03 01 05]` 写亮度成功并回读为 5；效果/速度/颜色同格式写回成功 |
| 灯效保存 | `0x09` | `[09 03 01]` 保存成功，回读保持 |
| 宏槽数量 | `0x0C` | **16** 个宏槽 |
| 宏缓冲区 | `0x0D` | **512 字节**（`02 00`） |
| 宏内容读取 | `0x0E` | 正常（当前全 `0xFF`，表示空） |
| 宏内容写入 | `0x0F` / 重置 `0x10` | 命令有正常回显，但写入测试未能在回读中持久化 → **待进一步验证（见风险）** |
| 键盘状态值 | `0x02` | 固件返回非标准固定响应 `02 03 00...`（uptime/布局选项/固件版本都不可用）→ **不要依赖** |
| 单键码读取 | `0x04` | 返回非标准响应（`01 layer 09 col...`）→ 用批量 buffer 接口代替 |
| VIA 3 菜单同步 | `0x16` | 不支持（非标准响应）→ 这也是自研 App 相对网页版的优势：灯效直接走 `0x07/0x08/0x09` |
| 编码器 | `0x14` | 有响应（`0x00A9`），但官方 JSON 未声明编码器，暂不处理 |

> 结论：**改键 + 4 层 + RGB 灯效 + 配置备份所需的核心协议全部可用，且读写均经过真机回读校验。**

### 2.3 官方键盘定义（JSON）

官方 VIA 指南给出的 JSON 已下载并解析（存于 `definition/IQUNIX MQ80 KB-USB.json`）：

- `name = "IQUNIX MQ80 KB"`，`vendorId = "0x320F"`，`productId = "0x5055"`（与实机一致）
- `matrix = { rows: 8, cols: 16 }`
- 84 键 80% ANSI 物理布局（KLE 格式，含每个键的矩阵坐标）
- `keycodes: ["qmk_lighting"]`
- 灯效菜单：亮度 0–9、18 种灯效、速度 0–4、颜色（RGB Matrix 通道 `3`，值 `1/2/3/4`）
- 12 个自定义功能键：2.4G MODE、Bluetooth 1/2/3、USB MODE、LOCK WIN KEY、MAC WIN CHANGE、KEY SCAN DELAY、BATTERY STATUS、KEYBOARD SLEEP、LED LOGO MODE、LED LOGO COLOUR
- **没有** layers/macros 字段 → 层和宏由固件提供（层数实测 4）

---

## 3. 官方生态事实（决定方案选择）

| 问题 | 事实 |
|---|---|
| 官方 macOS 软件 | **不存在**。官网只有 Windows `.exe`（.NET WinForms），静态分析显示它是**固件升级工具**（`get_fw_version` / `Open bin` / `Start` / `Debug Mode`），没有改键 UI |
| 官方配置方式 | 官方 VIA Guide：有线连接 → `usevia.app` → 下载 JSON → VIA 设置开 `Show Design TAB` → Design 上传 JSON → 连接键盘 |
| MQ80 是否在 VIA 官方键盘库 | **不在**（caniusevia.com 支持列表无 IQUNIX；the-via/keyboards 仓库无定义）→ 必须手动导入 JSON |
| 网页版在 macOS 的可用性 | 独立评测 MacSources 确认 **Chrome 版 VIA 在 macOS 稳定可用**；VIA 桌面版在 macOS 识别不到键盘 |
| 固件性质 | 官方称 custom firmware，**不是 QMK**；不支持 Mod-Tap / Layer-Tap / MEH / HYPR；社区分析为 Telink/Andes RISC-V。无 QMK/Vial 移植 → **刷 QMK/Vial 不可行** |
| 固件升级 | 仅 Windows 官方工具（OTA）；Mac 上暂无法升级。官方 VIA Guide 提到：若 JSON 加载报错，需先在 Windows 上升级固件再试 |
| 三模 | 官方 VIA 流程只写 Wired；社区只读实测 2.4G 接收器（PID `0x5088`）可读 VIA 协议版本 11；蓝牙无证据 |
| 官方 JSON 再分发 | 官方 CDN 提供，无明确许可声明。本地自用没问题；对外分发需谨慎/征得同意 |

---

## 4. 方案对比与推荐

| 方案 | 开发量 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| **A. usevia.app + 官方 JSON** | 0 | 立即可用；官方支持路径；功能覆盖改键/灯效 | 需要 Chrome/Edge；每次涉及 WebHID 授权；Design 手动导入；无备份/恢复管理；协议 11 + VIA 3 菜单路径可能报错；无离线 | 作为**临时应急** |
| **B. 原生 SwiftUI + IOKit（推荐）** | 约 2–3 天 MVP | 完全离线；原生体验；可备份/恢复/多套配置；写前自动备份、写后校验；可扩展 2.4G；可直接操作灯效通道；无浏览器依赖 | 需要做 UI 与键码库；TCC 授权引导；仅本机自用需 ad-hoc 签名 | **推荐主线** |
| C. Electron/CEF 内嵌 VIA | 中 | 复用 VIA 前端 | 包体大、Chromium 权限模型、签名复杂、无原生感、仍有 WebHID 限制 | 不推荐 |
| D. 刷 QMK/Vial/社区固件 | 高 | 可获得完整 QMK 能力 | 固件非 QMK、无移植；刷机有变砖风险；社区固件无 LICENSE、仅实验验证 | **不做**（如想要电量条可另立项） |

**推荐：方案 B 为主，方案 A 作为今天就能用的应急路径。**

---

## 5. 推荐产品方案（v1 MVP）

**产品名（暂定）**：MQ80 Studio —— 离线、原生、只做 MQ80 的配置管理 App。

### 5.1 功能范围

1. **设备连接与识别**
   - 自动发现 `VID 0x320F / PID 0x5055`、Usage `0xFF60:0x61` 的键盘；热插拔。
   - 显示协议版本、层数、当前模式（USB/2.4G/蓝牙可用性提示）、矩阵信息。
   - 非 USB / 非目标设备时给明确提示（「请用数据线连接并切到 USB 模式（Fn+5）」）。
2. **键位编辑器（核心）**
   - 84 键可视化布局（来自官方 JSON 的 KLE 坐标），支持 Layer 0–3 切换。
   - 点击按键 → 键码选择器：基础 HID 键、媒体键、鼠标键、RGB 灯效键、12 个 MQ80 自定义功能键。
   - 支持单键修改、单层重置、恢复默认（写入前自动备份 + 二次确认）。
   - 写入后自动回读校验，失败可一键回滚。
3. **灯效面板**
   - 亮度 0–9、18 种灯效、速度 0–4、颜色（色轮/色板）。
   - 拖动实时预览，松手/点「应用」才写 EEPROM（减少无谓写入），应用后自动保存并回读。
   - 恢复默认灯效。
4. **配置备份 / 恢复**
   - 连接后首次写操作前自动全量备份（4 层键位 + 灯效 + 宏原始数据）。
   - 导出/导入 `.mq80profile`（JSON），支持多套配置、恢复出厂状态。
5. **权限与安全**
   - 首次启动引导授权「输入监控」，说明原因；权限缺失时只读模式。
   - 危险操作（整层重置/恢复默认/写入）二次确认。
   - v1 **不写固件、不跳 Bootloader**，只写键位/灯效 EEPROM → 风险低、可恢复。
6. **设置 / 诊断**
   - 原生调试日志（命令/响应 32B hex 开关）、协议探针页（方便以后兼容新固件）。
   - 语言（中/英）、启动行为、版本信息。

### 5.2 明确不做（v1）

- 固件升级 / 回滚（需要 OTA 协议逆向，风险高；Mac 无官方工具）。
- 蓝牙模式配置（无证据）。
- 电池电量读取、侧灯控制（原版固件没有电脑接口；社区实现依赖自定义固件，不能作为 v1 功能）。
- 逐键 RGB（官方 JSON 未声明 per-key）。
- Mod-Tap / Layer-Tap（固件不支持，UI 不应提供）。

---

## 6. 技术架构

```
MQ80Studio.app
├─ HIDTransport        IOHIDManager/IOHIDDevice 枚举、热插拔、打开/关闭、32B 收发
├─ VIAProtocol         串行命令队列（每命令等匹配回包 + 超时重试）
│   ├─ Keymap          0x12/0x13 分块读写、层数 0x11、校验
│   ├─ Lighting        0x07/0x08/0x09（channel 3，1–4）
│   ├─ Macros          0x0C–0x10（读取可用；写入待验证，先只读展示）
│   └─ Info            0x01 协议版本、设备信息
├─ Definition         官方 JSON 解析（matrix/KLE/菜单/customKeycodes）+ 键码目录
├─ Core               状态、备份/恢复、写前自动备份、回读校验、回滚
└─ UI                 SwiftUI（键位编辑 / 灯效 / 配置 / 设置）+ 权限引导
```

- **平台**：macOS 13+；Apple Silicon 优先（Universal 可后补）。
- **依赖**：只用系统框架（SwiftUI / AppKit / IOKit），无第三方运行时依赖。
- **构建**：本机只有 Command Line Tools（无完整 Xcode / `xcodebuild`），采用 `swiftc -parse-as-library` + 手工组装 `.app`（Info.plist + ad-hoc `codesign --force -s -`）；已验证 SwiftUI 可执行文件可在本机编译链接。后续如需 Xcode 工程可再转换。
- **权限**：Input Monitoring TCC；无沙盒（本地自用最简单，沙盒下 HID 访问受限）；分享给别人时再做 Developer ID + notarization。
- **安全设计**：连接即全量备份；所有写操作 `写入 → 回读比对 → 失败自动回滚`；灯效保存去抖动；危险命令默认隐藏并二次确认。

---

## 7. 实施计划（里程碑）

| 里程碑 | 内容 | 预估 |
|---|---|---|
| M0 ✅ | 可行性 + 协议真机验证（本报告） | 已完成 |
| M1 | Swift 工程骨架 + HIDTransport + VIAProtocol + CLI（读键位/灯效、导出备份、写回并校验） | 0.5–1 天 |
| M2 | SwiftUI 键位编辑器（84 键布局、4 层、键码选择器、写入校验） | 1–2 天 |
| M3 | 灯效面板 + 备份/恢复 + 权限引导 + 危险操作确认 | 0.5–1 天 |
| M4 | 打包 `.app`（ad-hoc）、自测/回归、README 与使用说明 | 0.5 天 |
| 可选 | 2.4G 接收器支持、宏写入验证、固件 OTA 逆向、电池/侧灯（需自定义固件） | 另议 |

> 实际由本 Agent 开发时速度会明显快于上述人日估算；M1 完成即可交付可用的命令行验证版。

---

## 8. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| TCC 输入监控未授权 | App 无法打开设备 | 首次启动引导授权；提供检测与「打开系统设置」按钮；权限缺失时只读/提示模式 |
| 固件批次/版本差异 | 命令行为可能不同 | 启动读取协议版本；协议不符时降级只读；内置官方 JSON 并支持导入自定义定义；调试探针页 |
| `0x02`/`0x04`/`0x16` 等非标准响应 | 若照搬 VIA 代码会报错 | 只使用已验证命令（`0x01/0x07-0x09/0x0C-0x13`）；每命令独立解析 + 回读校验 |
| 宏写入未持久化 | 宏编辑功能可能不可用 | v1 先只读展示宏、写入标为实验；进一步按 VIA 的「写前 reset + 末字节标记」时序复测 |
| 2.4G 配置未验证 | 无线下无法配置 | v1 明确只支持 USB 有线；后续用接收器 PID `0x5088` 验证读写 |
| 固件升级只能在 Windows | 若官方 JSON 报错需升级固件时 Mac 无法处理 | 文档说明可用 Windows 虚拟机/USB 直通或借用 Windows；v1 不含 OTA |
| 灯效频繁写 EEPROM | 影响寿命 | 松手/点应用才写；拖动只做本地预览；保存去抖 |
| 官方 JSON / 社区资料许可 | 分发/引用风险 | 本地自用；若对外分发需确认许可；社区项目无 LICENSE → 只参考协议事实，不复制代码 |
| 无 Developer ID | 无法直接分发给别人 | 本地 ad-hoc 签名；分享时再申请 Developer ID + notarization |

---

## 9. 现在就能用的应急方案（0 开发）

1. 用 Chrome 或 Edge 打开 <https://usevia.app/>。
2. 右上角 Settings（齿轮）→ 打开 **Show Design TAB**。
3. Design 页 → **Load Draft Definition** → 选择 `definition/IQUNIX MQ80 KB-USB.json`（官方原始 JSON 已放入本仓库）。
4. 用数据线连接键盘，切到 USB 模式（Fn+5）；在 VIA 里授权并选择 `IQUNIX MQ80 KB`。
5. 回到 Configure 页改键/调灯效。
6. 如果 JSON 上传报错：官方要求先在 Windows 上运行固件升级工具再重试（这是官方已知兜底流程）；我们的原生 App 可以直接绕过网页版的这类限制。

> 注意：VIA 网页版不会帮你做配置备份。建议在大量改动前先用我们的 CLI/App 导出一份备份；或先只做小改动。

---

## 10. 证据索引

| 文件 | 内容 |
|---|---|
| `docs/protocol-notes.md` | 实测协议字节级笔记（含请求/响应格式、怪癖、安全边界） |
| `definition/IQUNIX MQ80 KB-USB.json` | 官方 VIA 键盘定义（从官方 CDN 下载，7,529 B） |
| `tools/probe/` | 本机真机协议探针 C 源码与验证结果 |
| `docs/research-official.md` | 官方软件/VIA 支持调研（含全部 URL 与可信度标注） |
| `docs/research-macos.md` | macOS HID/权限/分发/方案调研 |
| 官方 VIA Guide | <https://iqunix.com/blogs/news/mq80-via-guide> |
| 官方 VIA JSON（zip） | <https://cdn.shopify.com/s/files/1/0676/7853/5986/files/IQUNIX_MQ80_KB-USB.json.zip> |
| 社区同类项目（仅参考事实） | <https://github.com/xiaoliu-heng/q101-mq80-battery-bar>（无 LICENSE，不复制代码） |
