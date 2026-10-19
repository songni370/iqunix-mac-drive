# macOS 上写 VIA/QMK 键盘配置 App —— 技术可行性调研

> 调研对象：IQUNIX MQ80（VID `0x320F` / PID `0x5055`），USB 暴露 VIA Raw HID：UsagePage `0xFF60` / Usage `0x61`。
> 调研机器：macOS **26.6.2 (25G83)**，Apple Silicon arm64，Swift 6.4（Command Line Tools）。
> 调研方式：只读。通过 `curl`/公开源码与官方文档核对；本机实测由 lead/另一路 probe 完成（见下）。
> 置信度标记：**【确认】**=有官方/源码直接证据；**【高置信】**=多来源一致但未逐行核验；**【推测】**=合理推断；**【未找到】**=查不到。
> 调研时间：2026-10-19。（GitHub raw / caniuse 页面通过 curl 抓取；`web_fetch` 工具因 DNS 被解析到非公网 IP 不可用，已改用 curl。）

---

## 0. 结论先行（TL;DR）

- **可行，且不需要 root。** 原生 Swift/SwiftUI + IOKit HID（`IOHIDManager`/`IOHIDDevice`）即可完整讲 VIA 协议；本地自用 App 不必沙盒、不必 Developer ID，ad-hoc 签名即可跑。
- **最大的两个坑**：① 首次打开 HID 设备会触发 TCC（本机实测 `0xE00002E2` = `kIOReturnNotPermitted`，用户授权后变 0），App 打包后要处理"授权后需重启 App/重新插拔"的体验；② **设备端不自描述**：VIA 协议本身没有"读取键盘定义 JSON"的命令（那是 Vial 的扩展），所以 App 必须自带 MQ80 的布局/矩阵 JSON（或让用户手动导入）。
- **不要在 App 里用 WKWebView 跑 usevia.app**：WebKit/Safari 不支持 WebHID（caniuse：Safari 3.1–26.6/27 均 Not supported）。要么原生 IOKit，要么内嵌 Chromium（Electron/CEF）。
- 固件刷新不在 VIA 协议内（只有 `0x0B bootloader_jump` 跳 bootloader），实际烧录建议复用 QMK Toolbox / UF2 / dfu-util。

---

## 1. VIA 协议规范（Raw HID）

### 1.1 传输层【确认】

- HID 接口：UsagePage `0xFF60`，Usage `0x61`；**32 字节**定长报告；**Report ID = 0**（QMK `RAW_EPSIZE 32`；VIA App 源码注释 `COMMAND_START = 0x00 // This is really a HID Report ID`）。
- Host → 设备：Output Report（macOS：`IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, buf, 32)`）。
- 设备 → Host：**把请求缓冲区原地修改后原样回发**（QMK `raw_hid_receive()` 末尾 `raw_hid_send(data, length)`）；所以响应也是 32 字节，byte0 = 命令 ID（未知命令则被改成 `0xFF id_unhandled`）。
- 依据：QMK `quantum/via.c` / `via.h`（<https://github.com/qmk/qmk_firmware/blob/master/quantum/via.c>、<https://github.com/qmk/qmk_firmware/blob/master/quantum/via.h>）；VIA App `src/utils/keyboard-api.ts`（<https://github.com/the-via/app/blob/main/src/utils/keyboard-api.ts>）。
- 当前 QMK master 的 `VIA_PROTOCOL_VERSION = 0x000D`（13）【确认】。任务描述里的 `0x000C` 是较老的 VIA 3 早期固件版本；**以设备实际 `get_protocol_version` 返回为准**。
- 协议版本 >= 13 的差异（部分）：RGBLight/RGB Matrix 拆分出独立的 `UG_*`/`RM_*` keycode 集；`id_get_keyboard_value` 新增 `id_keycodes_version = 0x06`；VIA App 新增 `UI_SYNC_REQUEST = 0x16`（见 §1.3）。【高置信】

### 1.2 命令 ID 表【确认，均出自 QMK `via.h` + VIA App `keyboard-api.ts`】

| ID | 名称 | 请求（byte0 起，32B 内） | 响应/说明 |
|---|---|---|---|
| `0x01` | `id_get_protocol_version` | `[0x01]` | `[0x01, ver_hi, ver_lo]`（例：`0x000D` → `01 00 0D`） |
| `0x02` | `id_get_keyboard_value` | `[0x02, value_id, ...]` | `[0x02, value_id, data...]` |
| `0x03` | `id_set_keyboard_value` | `[0x03, value_id, data...]` | 原样回显；未知 value_id 置 `0xFF` |
| `0x04` | `dynamic_keymap_get_keycode` | `[0x04, layer, row, col]` | `[0x04, layer, row, col, kc_hi, kc_lo]` |
| `0x05` | `dynamic_keymap_set_keycode` | `[0x05, layer, row, col, kc_hi, kc_lo]` | 回显 |
| `0x06` | `dynamic_keymap_reset` | `[0x06]` | 清空全部动态 keymap（慎用） |
| `0x07/0x08/0x09` | `custom_set/get/save_value` | `[cmd, channel, value_id, data...]` | 灯光/自定义值，见 §1.4 |
| `0x0A` | `id_eeprom_reset` | `[0x0A]` | 需固件定义 `VIA_EEPROM_ALLOW_RESET`；恢复默认（慎用） |
| `0x0B` | `id_bootloader_jump` | `[0x0B]` | 跳 bootloader（设备会断开重枚举） |
| `0x0C` | macro get count | `[0x0C]` | `[0x0C, count]` |
| `0x0D` | macro get buffer size | `[0x0D]` | `[0x0D, size_hi, size_lo]` |
| `0x0E` | macro get buffer | `[0x0E, off_hi, off_lo, size(<=28)]` | 头部 3 字节 + 数据（`data[3..]`） |
| `0x0F` | macro set buffer | `[0x0F, off_hi, off_lo, size(<=28), data...]` | 回显 |
| `0x10` | `dynamic_keymap_macro_reset` | `[0x10]` | 清宏 |
| `0x11` | get layer count | `[0x11]` | `[0x11, layer_count]` |
| `0x12` | `dynamic_keymap_get_buffer` | `[0x12, off_hi, off_lo, size(<=28)]` | 头部 3B + 数据；offset 单位=字节，1 keycode=2B |
| `0x13` | `dynamic_keymap_set_buffer` | `[0x13, off_hi, off_lo, size(<=28), data...]` | 回显 |
| `0x14` | get encoder | `[0x14, layer, idx, direction]`（direction≠0 表示顺时针） | `[..., kc_hi, kc_lo]` |
| `0x15` | set encoder | `[0x15, layer, idx, direction, kc_hi, kc_lo]` | 回显 |
| `0x16` | `UI_SYNC_REQUEST`（VIA App v3 新增） | `[0x16, 0x01(ver), type, count, ...]` | 用于自定义菜单/命令同步；QMK master `via.c` 中**未找到**该命令实现【未找到】 |
| `0xFF` | `id_unhandled` | — | 固件对未知命令的回退值 |

keyboard_value_id（`0x02/0x03` 的 value_id）【确认】：
`0x01 id_uptime`（4B 大端毫秒）、`0x02 id_layout_options`（4B 大端）、`0x03 id_switch_matrix_state`（读矩阵：请求 `[0x02,0x03,offset]`，响应打包行数据，28 字节内按 `ceil(cols/8)` 字节/行）、`0x04 id_firmware_version`（4B 大端，= `VIA_FIRMWARE_VERSION`）、`0x05 id_device_indication`（仅 set）、`0x06 id_keycodes_version`（4B 大端 BCD，协议 13 起）。

### 1.3 关键推论【高置信】

- **层数**：协议不放在定义 JSON 里，而是 `0x11 get_layer_count` 现场读；每层默认 `rows*cols` 个 keycode。
- **单 keycode 布局**：`dynamic_keymap` 的 EEPROM 排布 = `(layer * rows + row) * cols + col`，每个 keycode 2 字节（大端序 `hi,lo`），所以 `get_buffer` 的字节 offset = `2 * (layer*rows*cols + row*cols + col)`。
- **读-改-写**：改键前先 `get_protocol_version` → `get_keyboard_value(id_layout_options)` / `get_layer_count` → 再批量 `get_buffer` 缓存整块 keymap；每次写后建议读回校验。VIA App 内部用**串行命令队列**（`KeyboardAPI`/`globalCommandQueue`）避免并发，32B 一次一命令，这也是我们该抄的架构【确认：keyboard-api.ts】。
- **超时/流控**：QMK 在 `raw_hid_receive` 里同步处理并立刻 `raw_hid_send`，正常延迟 <几 ms；建议 App 每命令 300–1000ms 超时并重试一次，收到 `0xFF` 视为不支持。

### 1.4 灯光/RGB 命令【确认字节布局，具体值 ID 见 `via.h`】

- 统一走 `0x07 set` / `0x08 get` / `0x09 save`：`[cmd, channel, value_id, value...]`。
- channel：`0` 自定义、`1` QMK Backlight、`2` QMK RGBLight、`3` QMK RGB Matrix、`4` Audio、`5` LED Matrix。
- 例（RGBLight/RGB Matrix）：`value_id 1` 亮度 0–255、`2` 效果编号、`3` 速度、`4` 颜色（通常 3 字节 H/S/V）；Backlight：`1` 亮度、`2` 效果。**MQ80 用哪套（RGBLight 还是 RGB Matrix）要看定义 JSON 的 `menus` 和设备实际响应**；VIA 定义里用 `"menus": ["qmk_rgblight"]` / `["qmk_rgb_matrix"]` 或自定义 UI 指定 channel/value_id（见 §2）。
- 保存到 EEPROM：`0x09`（channel 跟随上一条）；`0x07` 之后镜头效果是实时的，`0x09` 才持久化。

---

## 2. VIA 的键盘定义机制（App 怎么知道布局/矩阵/层数/RGB）

### 2.1 官方机制：静态 JSON（来自 the-via/keyboards 仓库）【确认】

- VIA 官网 Specification：<https://www.caniusevia.com/docs/specification>（"VIA requires a definition of the keyboard… a JSON file stored in the VIA Keyboards repository"）。
- VIA App v3 **不是**运行时从 caniusevia.com 拉定义，而是构建时把 `github:the-via/keyboards`（npm 包 `via-keyboards`）编译进 `public/definitions`：`package.json` 里有 `"via-keyboards": "github:the-via/keyboards"`、`build:kbs: node … build-all.ts public/definitions`【确认：<https://github.com/the-via/app/blob/main/package.json>】。
- 定义 JSON 关键字段（Specification + post-V3 示例 <https://www.caniusevia.com/docs/post_v3_examples>）：
  - `name`（v3 可用 custom value 动态取名）、`vendorId`、`productId`
  - `matrix: {rows, cols}`：**必须**等于固件矩阵
  - `layouts.keymap`：KLE JSON，键位图例 `"row,col"`；`layouts.labels`：布局选项（split backspace/ISO 等）
  - `menus`：`qmk_backlight` / `qmk_rgblight` / `qmk_rgb_matrix` / `qmk_audio` 或自定义 UI（`content: ["id_qmk_rgb_matrix_brightness", 3, 1]` 里最后两个数就是 custom channel + value id）
  - `keycodes`（v3：`qmk_rgblight_keycodes` / `qmk_rgb_matrix_keycodes` 等）、`customKeycodes`、`firmwareVersion`
- 层数、当前 layout options、firmware version、矩阵状态：不在 JSON 里，走协议实时读（§1.3）。RGB 类型由定义的 `menus`/`keycodes` 决定，实际命令靠 custom channel 值。

### 2.2 "设备端动态定义" = Vial 的扩展，不是 VIA 协议【确认】

- 在 VIA 官方 spec、QMK master 的 `via.h`/`via.c` 中**没有**"读取设备端定义 JSON"的命令【确认：抓取的 via.h 命令表无 definition 相关项；`via.c` 仅在第 205 行注释提到 definition】。
- 设备端自描述是 **Vial** 固件/协议的能力（Vial 是 VIA 的超集），证据：`vial-qmk/quantum/vial.h` 的命令表：
  - `vial_get_keyboard_id = 0x00`、`vial_get_size = 0x01`、`vial_get_def = 0x02`、`vial_get_encoder = 0x03`、…；`VIAL_RAW_EPSIZE 32`；`VIAL_PROTOCOL_VERSION 0x00000006`
  - 流程（第三方 DeepWiki 对 Vial 协议描述，未在 Vial 源码逐行核验）：`0x01` 返回 4 字节**小端**定义总大小 → `ceil(size/pageSize)` 页 → 逐页 `0x02`（带 page index）取**压缩后的**定义数据 → 拼接解压得 JSON。
  - 来源：<https://github.com/vial-kb/vial-qmk/blob/vial/quantum/vial.h>、<https://deepwiki.com/sekigon-gonnoc/via-custom-ui-for-vial/6-via-and-vial-protocols>
- **对我们 App 的含义**：MQ80 若只跑 VIA/QMK（非 Vial），设备**不会**吐出布局 JSON。必须：① 自带（或从 the-via/keyboards 拉）MQ80 的 VIA JSON；② 或要求用户手动导入 JSON；③ 或我们另存一份"矩阵+物理布局"元数据随 App 分发，再用协议读层数/键值。**若设备支持 Vial 协议，可先探测 `vial_get_keyboard_id`，成功则能完全自描述**——但这是额外假设，MQ80 未确认【推测/待实测】。
- 用户手动加载：VIA App 的 **Design 标签页**支持拖入/draft 定义 JSON（Specification 提到 Design tab；第三方文档也称 "sideloaded using Via's Design tab"【高置信】）。我们的 App 应提供"导入 VIA 定义 JSON"作为兜底。

### 2.3 MQ80 的 JSON 在哪

- 先查 `the-via/keyboards` 仓库（<https://github.com/the-via/keyboards>，实际定义文件在 `v3/` 或 `definitions/` 按 VID/PID 组织；未在本次抓取中逐项确认 MQ80 是否存在，**未找到直接条目**）。
- VIA 官方支持列表：<https://www.caniusevia.com/docs/supported_keyboards>（可搜 VID `0x320F`/PID `0x5055`；本次未逐条核对）。
- 若官方仓库没有：只能自己写 JSON（矩阵 rows/cols 可从固件 `info.json` 或 QMK 源码拿，或通过 `id_switch_matrix_state` 逐个按键实测推断），这也是本项目的**主要工作量之一**。

---

## 3. macOS HID 访问（IOKit）

### 3.1 基本可行性【确认（本机实测）】

- `IOHIDManagerCreate` + `kIOHIDVendorIDKey`/`kIOHIDProductIDKey` 匹配 → `IOHIDManagerOpen` → `IOHIDManagerCopyDevices` 遍历；按 `kIOHIDPrimaryUsagePageKey == 0xFF60 && kIOHIDPrimaryUsageKey == 0x61` 选接口 → `IOHIDDeviceOpen` → `IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, buf, 32)` 发 32B → `IOHIDDeviceRegisterInputReportCallback` + `IOHIDDeviceScheduleWithRunLoop` 收回 32B。**不需要 root。**
- 本机实测（lead 提供）：首次 `IOHIDManagerOpen` 返回 **`0xE00002E2`**，用户在系统提示中授权后变 `0x00000000`；随后成功收发 32 字节报告。
  - `0xE00002E2` = `kIOReturnNotPermitted`（本机 SDK `IOKit.framework/Headers/IOReturn.h:138` 直接核对：`#define kIOReturnNotPermitted iokit_common_err(0x2e2)`）【确认】。
- 注意 API 细节：`IOHIDDeviceSetReport` 的 `reportID` 参数传 0，**buffer 不包含 report ID 字节**（设备无编号报告时传 0）；buffer 长度应等于接口的 `kIOHIDMaxOutputReportSizeKey`（32）。输入回调里 `reportID` 为 0、`reportLength` 为 32。
- 替代异步 API：`IOHIDDeviceSetReportWithCallback`（macOS 10.15+，避免主线程阻塞）；也可以 `IOHIDDeviceGetReport` 读 Feature Report（VIA 不用 Feature，走 Output/Input）。
- 默认是**非独占打开**：不要传 `kIOHIDOptionsTypeSeizeDevice`（会抢走键盘，用户无法打字）；默认打开时键盘仍正常输入。macOS 允许多个进程同时打开同一 HID 接口（实测 via probe 与系统同时工作）【高置信】。

### 3.2 TCC / 输入监控（Input Monitoring）【高置信 + 实测】

- macOS 10.15+ 起，访问键盘类 HID 输入流需要在 系统设置 → 隐私与安全性 → **输入监控** 中授权；命令行程序授权对象是**终端 App**（Terminal/iTerm），.app 是**自身**。首次触发时系统弹窗，授权后**通常需重启 App**（对命令行则新起进程一般即可，但终端自身可能要重启）【高置信，Apple 官方文档页：<https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4b68873b/mac>；该页在 26/27 版路径有改版，本次抓取正文未完整取到】。
- **对 0xFF60 vendor collection 是否也强制 Input Monitoring**：本机实测"只打开 0xFF60/0x61 接口，首次 open 被拒（0xE00002E2）→ 授权后成功"，说明在 macOS 26.6.2 上**确实会触发**（至少对当前进程/终端）。具体 TCC 服务名与判定逻辑 Apple 未公开；**未找到** Apple 官方文档明确写"vendor HID 需要 Input Monitoring"【未找到】。工程上按"需要"处理，并在 App 内做引导。
- 不存在专用 Info.plist 使用说明 key（如 `NSInputMonitoringUsageDescription`）：Input Monitoring 的授权由系统 TCC 面板管理，无自定义文案 key【未找到/高置信】。
- 若只是发送 Output Report 而完全不注册输入回调，是否仍需要授权：**未实测**；但 VIA 要收响应，必须收 Input Report，所以授权不可避免【推测】。

### 3.3 App Sandbox 与 entitlement【高置信】

- Apple 文档中**存在** `com.apple.security.device.usb`（"A Boolean value indicating whether your app may interact with USB devices."）：<https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.usb>（本次通过 docs JSON API 取到 abstract，确认真实存在）。
- Apple 文档中**没有** `com.apple.security.device.hid`（对应 docs 页 404）【确认：2026-10 抓取】。也就是说没有"HID 专用 entitlement"。
- 社区/论坛已知问题：沙盒 App 里 `IOHIDDeviceOpen` 常被 TCC 拒绝，需要关沙盒/加临时例外；Apple 论坛 thread "App with sandbox TCC deny IOHIDDeviceOpen"：<https://developer.apple.com/forums/thread/724608>（论坛页有反爬，本次未取到正文，仅确认标题/存在）【未找到正文】。
- **工程建议**：本项目为本地自用，**不要开 App Sandbox**（Xcode：Signing & Capabilities 不勾 App Sandbox；或用命令行 `codesign` 构建无沙盒 .app）；`com.apple.security.device.usb` 对纯 IOHID 访问既非必要也未必有效。若未来上 Mac App Store，HID 访问会成为硬约束（很可能不可行），这是分发路线的重要限制【推测】。

### 3.4 kext / DriverKit / 新版本限制

- 用户态 IOHID 客户端（我们这种）**不需要** kext 或 DriverKit，macOS 14/15/26 没有改变这一点的公开政策【高置信】。
- kext 早已被弃用，若要**创建虚拟 HID 设备**（比如把键盘映射成另一个设备）才需要 `HIDDriverKit`（DriverKit 的 HID driver，用户态扩展，需要 entitlement 与用户批准）——本项目不需要【高置信】。
- 未发现 macOS 14/15/26 针对第三方 App 访问 0xFF60 vendor HID 的新限制；相反本机 26.6.2 实测可正常收发【确认：本机实测】。TCC 收紧（Input Monitoring）是 10.15 以来的既有机制【高置信】。

### 3.5 hidapi 在 macOS 上的实现【确认（源码）】

- macOS 后端**不是 libusb**，直接封装 IOHIDManager/IOHIDDevice：`mac/hid.c` 中 `IOHIDManagerCreate`（L446）、`IOHIDManagerSetDeviceMatching`（L448/L739）、`IOHIDDeviceOpen`（L1062）、`IOHIDDeviceSetReport`（L1133），出错时打印 `(0x%08X)` 错误码。
  - 源码：<https://github.com/libusb/hidapi/blob/master/mac/hid.c>
- 搜索 `mac/hid.c` 中没有 `kIOHIDOptionsTypeSeizeDevice` → **hidapi 默认不 seize 设备**（如需独占要显式传 `kIOHIDOptionsTypeSeizeDevice`；hidapi API 不暴露，正常用不上）【确认：本次抓取版本无该符号】。
- hidapi 的 `hid_write` 对无编号报告设备，数据首字节语义需注意（hidapi 约定 `data[0]` 是 report ID；VIA 用 report ID 0，通常传 32B 且首字节是命令 ID，实际发送时 hidapi 会按 report ID 0 处理）——建议原生 IOKit 直接用 `IOHIDDeviceSetReport`，少一层歧义【高置信】。
- 枚举/热插拔：hidapi 的 macOS 实现依赖 IOHIDManager 快照；热插拔需要调用 `hid_enumerate` 重新枚举（无系统级回调）。原生 IOKit 可注册 `IOHIDManagerRegisterDeviceMatchingCallback/RemovalCallback`，体验更好【高置信】。

---

## 4. 替代方案对比

| 方案 | 可行性 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| **原生 SwiftUI + IOKit HID** | 【确认】本机已验证 | 无依赖、启动快、UI 原生、可精细处理 TCC/热插拔、可做托盘/菜单栏 | 需自己写协议栈、定义 JSON、DFU 引导；TCC 首次体验要设计 | **推荐**（自用/长期维护） |
| Chrome/Edge + usevia.app（WebHID） | 【确认】可行 | 现成、零开发 | 需用户装 Chrome、依赖外部站点、不能深度定制、无固件刷新 | 作为**基线/应急**方案；可直接用 |
| 内嵌 Chromium（Electron/CEF）跑 VIA 前端 | 【高置信】可行（VIA 本身就是 WebHID 应用；Electron 内置 Chromium 支持 WebHID，需在主进程 `select-hid-device` 处理设备选择） | 复用 the-via/app 全量功能、跨平台 | 包体 100MB+、签名/公证复杂、Chromium 升级维护、macOS TCC 同样存在 | 想"快速出功能"时可选；长期不如原生 |
| **WKWebView + usevia.app** | 【不可行】 | — | WebKit/Safari 不支持 WebHID（caniuse：Safari 3.1–26.6、Safari 27、iOS Safari 全 Not supported）；WKWebView 无 WebHID 实现，也没有可用的私有桥 | **放弃**（任务假设正确：Safari/WKWebView 不支持 WebHID） |
| Qt + HIDAPI | 【高置信】可行 | 跨平台（Vial GUI 同款）、HIDAPI 成熟 | 包体大、macOS 原生观感差、Swift 生态割裂 | 不推荐（除非要 Windows/Linux 同步） |

- WebHID 支持矩阵：Chrome 89+ / Edge 89+ 支持，Firefox 不支持，Safari 全版本不支持（本次抓取 caniuse 2026-03 数据：<https://caniuse.com/webhid>）【确认】。
- WebHID 的限制（若走 Chromium 路线需注意）：必须 HTTPS/安全上下文 + 用户手势触发 `navigator.hid.requestDevice()`；浏览器对键盘/鼠标**顶层**集合有保护（blocklist），但我们的 0xFF60 vendor 接口是独立 collection，可被授权访问【高置信】。
- Electron 方案仍需处理 macOS Input Monitoring：Chromium 的 HID 服务同样走 TCC；实际是否提示取决于系统与设备分类【推测】。

---

## 5. 参考开源实现

| 项目 | 技术栈 | 定义/协议处理 | 固件刷新 | 对 ours 的参考 |
|---|---|---|---|---|
| **the-via/app**（usevia.app） | React/TS + **WebHID**；定义 JSON 构建期从 `via-keyboards` 打入 | 静态定义按 VID/PID 匹配 + Design tab 手动导入；命令层 `keyboard-api.ts` 串行队列 | 不做刷新（仅 `0x0B bootloader_jump` 跳转） | **协议实现的最佳参考**；直接抄命令队列/字节布局 |
| **Vial GUI** | Qt + **HIDAPI**（C++） | 支持**设备端动态定义**（`vial_get_size/get_def`，压缩 JSON）+ 本地定义 | 不含 DFU（跳 bootloader 后另用工具） | 动态定义/多页读取的参考；跨平台桌面架构参考 |
| **QMK Toolbox** | macOS 原生 App（Swift/ObjC，仓库 <https://github.com/qmk/qmk_toolbox>） | 不配置键位，只做**固件烧录/DFU**（hidapi/dfu-util/UF2 等） | **是**（本项目固件刷新可复用其方案或直接引导用户使用） | 分发/签名参考：官方 DMG 已 Developer ID 签名+公证【高置信，未逐版本核验】 |
| **Keychron Launcher** | Web（WebHID）在线配置器 | 键位/灯光/宏，定义内置 | 部分型号支持在线固件升级（WebHID/WebUSB） | 证明 WebHID 产品级可行 |
| **Wootility**（Wooting） | Web（WebHID）配置器 | 自带定义 | 支持固件更新 | 同类参考【高置信，产品形态公开，源码未核验】 |

- VIA App 的协议实现文件（建议直接读源码移植）：`src/utils/keyboard-api.ts`（命令 ID/队列/16bit 转换）、`src/utils/usb-hid.ts`（WebHID 连接）、`src/utils/keyboard-values.ts`（keyboard value 封装）【确认存在 keyboard-api.ts/usb-hid.ts；keyboard-values.ts 由 import 推断】。
- 固件刷新路线（自研 App 若要做）：`0x0B bootloader_jump` → 设备重枚举为 bootloader PID（STM32 DFU / RP2040 UF2 / AVR DFU 各不相同）→ 按芯片选择 `dfu-util`、`hidapitester`+DFU、或挂载 UF2 盘拷固件。VIA 协议**不包含**写 flash 命令【确认】。

---

## 6. 分发与签名

- **本地自用（推荐起步）**：
  - 不需要 Developer ID，也不需要公证；Xcode 直接 Run，或 `xcodebuild` 出 .app 后运行。
  - 若从网上下载/拷贝到别的机器：去掉隔离属性 `xattr -d com.apple.quarantine App.app`（或 `xattr -cr`）；否则 Gatekeeper 拦截。
  - 建议 ad-hoc 签名：`codesign --force --deep --sign - App.app`（未签名也能跑，但 ad-hoc 让 TCC 有稳定身份）。**注意**：TCC（Input Monitoring）授权与 code signature/路径绑定；每次重新签名/换构建路径可能导致**重新弹授权**，开发期把构建产物路径固定、用稳定的签名 identity 可减少反复授权【高置信】。
  - **不需要 root**（HID 用户态访问）；**不需要辅助功能（Accessibility）**——那是给模拟输入/控制其他 App 用的，我们只读写 HID，不需要【高置信】。
- **分享给他人**：
  - Apple Developer Program（$99/年）→ **Developer ID Application** 证书签名 + Hardened Runtime + **公证**（`xcrun notarytool submit App.zip --keychain-profile … --wait`，然后 `xcrun stapler staple App.app`）。用户首次打开仍可能看到"已公证"正常提示。
  - 公证文档：<https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>。
  - 千万不要为省事让用户 `sudo`/关 SIP；HID 配置不需要。
- **Mac App Store**：需 App Sandbox，而 HID 访问在沙盒下大概率不可行（无 HID entitlement，论坛有 IOHIDDeviceOpen 被 TCC 拒的案例），不建议走 MAS【高置信/推测】。

---

## 7. 测试与抓包方法

### 7.1 安全探测流程（推荐）
1. 枚举设备与接口：`IOHIDManager` 匹配 VID/PID，打印每个接口的 `kIOHIDPrimaryUsagePageKey/UsageKey`、`kIOHIDMaxInputReportSizeKey/MaxOutputReportSizeKey/ReportDescriptor`（工作区已有 `.probe/via_probe.swift` 可作参考；本次不改它）。
2. `IOHIDDeviceOpen` → 若 `0xE00002E2`：确认 系统设置→隐私与安全性→输入监控 中已勾选宿主 App/终端，重启 App 重试。
3. `get_protocol_version`（`01 00 …`）→ 确认版本（0x000C 或 0x000D）。
4. **只读命令**：get keyboard value（layout_options、firmware_version、keycodes_version）、layer count、批量 get_buffer 读全 keymap、macro count/size/buffer、custom get value（灯光）。
5. **危险命令先别发**：`0x0A eeprom_reset`、`0x06 dynamic_keymap_reset`、`0x0B bootloader_jump`、`0x09 save`（会写 EEPROM）；改键用 `0x05` 前先备份整块 keymap 到文件，并提供一键恢复。
6. 回归验证：读回校验 + 用键盘实测按键 + 对比 VIA 网页版行为（同一设备两边交叉验证）。

### 7.2 抓包【部分确认】
- **Wireshark on macOS**：官方 wiki 说 macOS 自 Wireshark 2.4.0 / libpcap 1.9.0 / High Sierra 起可通过 **XHC20** 接口抓 USB：`sudo ifconfig XHC20 up`；但 **macOS Catalina 及以后需要关闭 SIP** 才能抓：<https://wiki.wireshark.org/CaptureSetup/USB>【确认：wiki 原文】。Apple Silicon 上的 XHC20 是否可用**未确认**【未找到】——建议不要依赖；关 SIP 对开发机风险高，不推荐。
- **Windows 虚拟机 + USBPcap**：可行方案（VMware/Parallels/UTM 把键盘 USB 直通给 guest，USBPcap 抓 URB）；注意 USBPcap 历史上会卡键鼠（wiki 有 warning），且 HID 直通/重定向在 macOS 宿主上可能抢焦点【高置信】。
- **最实用替代**：在 App/probe 内部做**双向 HID 日志**（时间戳 + 32B hex + 命令名），配合 VIA 网页版操作对照；对协议开发足够，且无 SIP/VM 成本【推荐】。也可在 IOKit 层用 `IOHIDDeviceRegisterInputReportCallback` 记录所有 Input Report。
- CLI 工具：
  - `hidapitester`（<https://github.com/todbot/hidapitester>，macOS 可用，基于 hidapi；支持 `--vid/--pid/--open/--send-output/--read-input` 等，示例见 README）。
  - `qmk_hid`（FrameworkComputer 的 Python CLI，<https://github.com/FrameworkComputer/qmk_hid>）可做 VIA 命令级调试【高置信，未逐行核验】。
  - 自己写 Swift CLI 最可控（本工作区已有 probe 雏形）。

---

## 8. 给本项目的架构建议（SwiftUI）

1. **分层**：`HIDTransport`（IOHIDManager + 热插拔回调 + 32B report 收发 + 超时重试）→ `VIAProtocol`（命令/响应、命令队列、16bit 转换、错误映射）→ `KeyboardModel`（定义 JSON 解析、KLE 布局、矩阵→按键映射、层）→ SwiftUI 视图（Keymap 编辑、Lighting、Macros、Settings）→ 持久化（当前配置快照/备份）。
2. **TCC 引导**：启动即探测；被拒时展示引导页 + 一键打开 `x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent`（Input Monitoring 面板 URL）；提示用户授权后重启 App。
3. **定义管理**：内置 MQ80 JSON（或从 the-via/keyboards 抓取后打包）；同时支持导入任意 VIA JSON（Design 模式）；把 JSON 的 `matrix.rows/cols` 与设备 `layer_count` 交叉校验。
4. **安全**：所有写操作前自动全量备份（keymap buffer + macros + layout options）；危险操作二次确认；固件跳转/刷新列为独立高级功能并明确"设备会断开"。
5. **签名**：先 `codesign -s -` 本地 ad-hoc；分享再上 Developer ID + notarize；**别开沙盒**。
6. **备选**：先用 Chrome + usevia.app 验证 MQ80 的协议版本与功能是否齐全（灯光/宏），作为原生实现的"对照真值"。

---

## 9. 明确"未找到/待实测"清单

- 【未找到】VIA 协议中"设备端定义 JSON"命令（结论：属于 Vial 扩展；VIA 定义仍靠静态 JSON）。
- 【未找到】Apple 官方明确说明"0xFF60 vendor HID 需要 Input Monitoring"的文档；仅有本机 26.6.2 实测 `0xE00002E2 → 授权后成功`。
- 【未找到】Apple 论坛 thread 724608 正文（反爬）；仅确认存在该主题。
- 【未确认】MQ80 在 the-via/keyboards 中的定义条目与 `protocol version`（需实测 `0x01` 响应；可能是 0x000C 或 0x000D）。
- 【未确认】MQ80 是否支持 Vial 协议（若支持则可设备端自描述）。
- 【未确认】Apple Silicon 上 Wireshark XHC20 抓 USB 是否可用（wiki 的 XHC20 方案面向 Intel 时代 + 需关 SIP）。
- 【未确认】沙盒 App 加 `com.apple.security.device.usb` 后 IOHIDDeviceOpen 是否放行（无 HID 专用 entitlement，预计仍会被 TCC 拒）。

## 10. 主要链接汇总

- VIA Specification：<https://www.caniusevia.com/docs/specification>
- VIA Post-V3 examples：<https://www.caniusevia.com/docs/post_v3_examples>
- QMK via.h（命令/协议版本 0x000D）：<https://github.com/qmk/qmk_firmware/blob/master/quantum/via.h>
- QMK via.c（命令处理/字节布局）：<https://github.com/qmk/qmk_firmware/blob/master/quantum/via.c>
- the-via/app（WebHID 前端，协议层 keyboard-api.ts）：<https://github.com/the-via/app>
- the-via/keyboards（定义仓库）：<https://github.com/the-via/keyboards>
- the-via/app package.json（定义构建期打包证据）：<https://github.com/the-via/app/blob/main/package.json>
- Vial 协议头（动态定义命令）：<https://github.com/vial-kb/vial-qmk/blob/vial/quantum/vial.h>
- Vial 协议第三方说明：<https://deepwiki.com/sekigon-gonnoc/via-custom-ui-for-vial/6-via-and-vial-protocols>
- Apple：USB entitlement：<https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.usb>
- Apple：输入监控用户指南：<https://support.apple.com/guide/mac-help/control-access-to-input-monitoring-on-mac-mchl4b68873b/mac>
- Apple 论坛（沙盒 TCC IOHIDDeviceOpen）：<https://developer.apple.com/forums/thread/724608>
- Apple：macOS 软件公证：<https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution>
- WebHID 支持矩阵：<https://caniuse.com/webhid>
- MDN WebHID：<https://developer.mozilla.org/en-US/docs/Web/API/WebHID_API>
- hidapi macOS 实现：<https://github.com/libusb/hidapi/blob/master/mac/hid.c>
- Wireshark USB capture：<https://wiki.wireshark.org/CaptureSetup/USB>
- hidapitester：<https://github.com/todbot/hidapitester>
- QMK Toolbox：<https://github.com/qmk/qmk_toolbox>
- IOKit `IOReturn.h`（本地 SDK）：`/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/IOKit.framework/Headers/IOReturn.h:138`（`kIOReturnNotPermitted = 0x2e2`）
