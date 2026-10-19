# IQUNIX MQ80 · VIA Raw HID 协议实测笔记

- 设备：`IQUNIX MQ80 KB`，`VID 0x320F` / `PID 0x5055`，USB 有线
- 接口：Usage Page `0xFF60` / Usage `0x61`，32 字节 Input + 32 字节 Output，无 Report ID（按 0 处理）
- 固件协议版本：`0x000B`（十进制 11）
- 测试环境：macOS 26.6.2，IOHIDManager / IOHIDDevice（见 `tools/probe/`）
- 说明：`R` = 请求（host → device）32 字节，`A` = 应答（device → host）32 字节，未写满部分补 0。

---

## 1. 传输层

```c
IOHIDManagerCreate / SetDeviceMatching(VID, PID) / Open
IOHIDDeviceOpen(dev, 0)
IOHIDDeviceRegisterInputReportCallback(dev, buf, 64, cb, NULL)
IOHIDDeviceScheduleWithRunLoop(dev, runloop, kCFRunLoopDefaultMode)
IOHIDDeviceSetReport(dev, kIOHIDReportTypeOutput, 0, report32, 32)   // 发送
// 应答从 input report callback 得到（report id = 0，长度 32）
```

要点：

- 第 0 字节是命令码，不是 Report ID。
- 每个请求都必须等到匹配的 32 字节应答再发下一条（固件是按序处理的）。
- 实测应答延迟约 2–5 ms；建议超时 200 ms + 重试 3 次。
- 首次运行需要「输入监控（Input Monitoring）」TCC 授权；未授权时 `IOHIDManagerOpen` 返回 `0xE00002E2`（`kIOReturnNotPermitted`）。
- 打开设备不会抢占用键盘输入（不 seize），可与打字同时存在。

---

## 2. 命令总表（实测）

| 命令 | 名称 | 请求 | 应答 | 实测 |
|---|---|---|---|---|
| `0x01` | get_protocol_version | `[01]` | `[01, 00, 0B]` | ✅ 版本 11 |
| `0x02` | get_keyboard_value | `[02, id]` | 非标准：`[02, 03, 00...]` | ⚠️ 不可用 |
| `0x03` | set_keyboard_value | `[03, id, ...]` | 非标准 | ⚠️ 不用 |
| `0x04` | get_keycode（单键） | `[04, layer, row, col]` | 非标准：`[01, layer, 09, col...]` | ⚠️ 用 `0x12` 代替 |
| `0x05` | set_keycode（单键） | `[05, layer, row, col, hi, lo]` | 未测 | 用 `0x13` 代替 |
| `0x06` | keymap reset | — | — | 危险，未测 |
| `0x07` | custom set value | `[07, channel, value_id, ...value]` | 原样回显 | ✅ RGB |
| `0x08` | custom get value | `[08, channel, value_id, 0]` | `[08, channel, value_id, ...value]` | ✅ RGB |
| `0x09` | custom save | `[09, channel, value_id]` | 回显 | ✅ |
| `0x0A` | eeprom reset | — | — | 危险，不用 |
| `0x0B` | bootloader jump | — | — | 危险，不用 |
| `0x0C` | macro get count | `[0C]` | `[0C, 10]` → 16 个 | ✅ |
| `0x0D` | macro get buffer size | `[0D]` | `[0D, 02, 00]` → 512B | ✅ |
| `0x0E` | macro get buffer | `[0E, off_hi, off_lo, size]` | `[0E, off_hi, off_lo, size, ...data]` | ✅ |
| `0x0F` | macro set buffer | `[0F, off_hi, off_lo, size, ...data]` | 回显 | ⚠️ 写后回读未持久化 |
| `0x10` | macro reset | `[10]` | 回显 | ⚠️ 未验证语义 |
| `0x11` | get layer count | `[11]` | `[11, 04]` → 4 层 | ✅ |
| `0x12` | keymap get buffer | `[12, off_hi, off_lo, size]` | `[12, off_hi, off_lo, size, ...data]` | ✅ size ≤ 28 |
| `0x13` | keymap set buffer | `[13, off_hi, off_lo, size, ...data]` | 回显 | ✅ |
| `0x14` | encoder get | `[14, layer, id, cw]` | `[14, layer, id, cw, hi, lo]` | ✅ 有响应 |
| `0x15` | encoder set | `[15, layer, id, cw, hi, lo]` | 未测 | JSON 未用 |
| `0x16` | UI sync request（VIA 3） | `[16, ...]` | 非标准：`[01, ...09...]` | ❌ 不支持 |

---

## 3. 键位（动态 Keymap）

- 矩阵：`rows = 8`，`cols = 16`，共 128 个位置；1 个键码 = 2 字节，**大端**。
- 每层字节数：`8 × 16 × 2 = 256` 字节。
- 总层数：4（命令 `0x11`），总缓冲区 `4 × 256 = 1024` 字节。
- 键码字节偏移（全局）：`offset = layer × 256 + row × 32 + col × 2`。

读取示例（一次最多 28 字节，通常一次读 14 个键码）：

```
R: 12 00 00 1C ...   // offset=0x0000, size=28
A: 12 00 00 1C 00 00 00 3A 00 3B 00 3C ...  // 后面 28 字节是键码数据
```

写入示例（一次最多 28 字节，必须整字节对齐；写完回读校验）：

```
R: 13 00 C0 02 00 04 ...   // offset=0x00C0（第 96 个位置 ×2），size=2，键码 0x0004
A: 13 00 C0 02 ...         // 回显
```

实测：将空位 `(r6,c0)` 写为 `0x0004` 后回读一致，再还原为 `0x0000` 回读一致 → 写入可用。

层内容（当前固件默认值）：

- Layer 0：基础 84 键布局；`(r7,c14) = 0x5221` 即 `MO(1)`（Fn 键）。
- Layer 1：Fn 层，30 个键与 Layer 0 不同：媒体控制、RGB 灯效键（`0x7820`–`0x782A` 等）、自定义键等。
- Layer 2 / Layer 3：当前与 Layer 0 相同（可编辑，但键盘默认没有切层键指向它们）。

### 3.1 写入陷阱（重要，2026-10-19 实测）

这块固件的 `0x13`（keymap set buffer）和 `0x12`（keymap get buffer）在**层边界**上有非标准行为：

1. **`0x13` 不能从层边界开始写**：如果一次写入的起始偏移正好是 `0x100` / `0x200` / `0x300`（即偏移低字节为 `0x00` 且非 0），数据会被错误地写到**上一层**。
   - 实测：`13 01 00 02 00 68`（offset=0x100）写入后，值出现在 `0x000`（Layer 0 #0）。
   - 实测：`13 02 00 02 00 6A`（offset=0x200）写入后，值出现在 `0x100`（Layer 1 #0）。
   - 偏移低字节非 0 时正常：`13 01 1C 02 00 6D` 正确落在 `0x11C`（Layer 1 #14）。
2. **`0x12` 不能跨层读取**：一次读取跨过层边界时，边界之后的部分返回 `0xFF`。
   - 实测：`12 00 FC 1C`（offset=0xFC, size=28）只返回前 4 字节有效数据，其余 24 字节为 `FF`。
3. **`0x05`（单键写入）完全可靠**：`[05, layer, row, col, kc_hi, kc_lo]`，四层都验证通过（写入后立即用 `0x12` 回读校验）。

**结论（App 的实现策略）**：

- 读取：按层分块，块大小为 28 且**不跨层**（每层从 `base+0` 开始，最多 28 字节）。
- 写入：使用 `0x05` 逐键写入（512 个键码约 2 秒），写完整体回读校验；不使用 `0x13`。
- 这也解释了为什么 VIA 官方前端的连续 28 字节分块写恰好避开了 0x100/0x200/0x300（28 步长不会命中这些偏移），但它的分块会跨层读取，故不能照搬其实现。

---

## 4. RGB 灯效（channel 3）

官方 JSON 的灯效菜单使用 `qmk_rgb_matrix` 通道 `3`：

| value_id | 含义 | 范围 |
|---|---|---|
| `1` | 亮度（Brightness） | 0–9 |
| `2` | 灯效（Effect） | 0–17（18 种） |
| `3` | 速度（Effect Speed） | 0–4 |
| `4` | 颜色（Color） | hue, sat 两个字节 |

读：`R: 08 03 01 00` → `A: 08 03 01 05 ...`（第 3 字节 = 亮度值 5）

写：`R: 07 03 01 05`（channel=3, value_id=1, value=5）→ 原样回显；随后读回 `05`

颜色写：`R: 07 03 04 00 FF`（hue=0, sat=255）→ 读回 `08 03 04 00 FF`

保存：`R: 09 03 01`（channel 3）；实测保存后读回值不变。

灯效 ID（官方 JSON 顺序，0–17）：

```
0 OFF_MODE, 1 WAVE_MODE, 2 COLOUR_CLOUD_MODE, 3 VORTEX_MODE, 4 MIX_COLOUR_MODE,
5 BREATHE_MODE, 6 LIGHT_MODE, 7 SLOWLY_OFF_MODE, 8 STONE_MODE, 9 LASER_MODE,
10 STARRY_MODE, 11 FLOWERS_OPEN_MODE, 12 TRAVERSE_MODE, 13 WAVE_BAR_MODE,
14 METEOR_MODE, 15 RAIN_MODE, 16 SCAN_MODE, 17 TRIGGER_COLOUR_MODE,
18 CENTER_SPREAD_MODE
```

> 注意：JSON 里 effect 下拉框实际列了 19 项（0–18）。写值时按设备实际范围先读后写、回读校验即可。

---

## 5. 宏（读取可用，写入待验证）

- 宏槽：16（`0x0C` → `0x10`）
- 宏缓冲区：512 字节（`0x0D` → `0x02 00`）
- 读取：`R: 0E off_hi off_lo size`，每次 ≤28 字节；当前缓冲区全 `0xFF`（空）。
- 写入：`R: 0F off_hi off_lo size data...` 有回显，但实测写入 `TEST\0` 后回读仍是 `FF`，**未能持久化**。
- 参考 VIA 官方时序：写宏前先 `0x10` 重置，把缓冲区最后 1 字节设为非零表示「写入中」，分块写入后把最后 1 字节清零表示完成。该时序尚未在 MQ80 上复现成功，v1 建议宏功能只读展示，写入标为实验。

---

## 6. 已知非标准行为（重要）

1. `0x02 get_keyboard_value`：无论 value_id 是 uptime / layout options / firmware version，都返回 `02 03 00 00...` → 无法读取固件版本、布局选项、矩阵状态。
2. `0x04 get_keycode`：请求 `[04, layer, row, col]` 返回 `[01, layer, 09, col, ...]`，不是标准 `[04, layer, row, col, kc_hi, kc_lo]` → 单键读取不可用，必须走 `0x12` 批量读。
3. `0x16 UI_SYNC_REQUEST`：不支持，返回与 `0x04` 同类的非标准应答 → VIA 3 的部分动态菜单功能在这块固件上会失败。
4. 未知命令（如 `0x7E`）返回 `[01, 00, 09, ...]`，不是标准 `0xFF` 未处理标记。

因此：**自研 App 不能直接照搬 VIA 前端代码的假设**，只使用已验证命令并做回读校验；遇到非标准命令只记录日志、不抛致命错误。

---

## 7. 安全边界

- **可以安全做**：读协议版本/层数/键位/灯效/宏；写键位 `0x13`（可回滚）；写灯效 `0x07` + `0x09`（可回滚）。
- **必须二次确认**：`0x06` keymap reset、整层重置、恢复默认。
- **v1 绝对不发送**：`0x0A` eeprom reset、`0x0B` bootloader jump（只在后续做固件升级功能时单独评估）。
- 所有写入都按「写前备份 → 写入 → 回读校验 → 失败回滚」执行。
- 灯效写入会落 EEPROM：拖动滑块时只做本地预览，松手/点「应用」才写入，避免频繁擦写。

---

## 8. 2.4G / 蓝牙（待验证）

- 社区文档记录：2.4G 接收器 `PID 0x5088` 也暴露 `0xFF60/0x61`，且可读回 VIA 协议版本 11。
- 本机测试时未插接收器，未实测。
- 蓝牙：无证据表明可配置；官方 VIA Guide 只写 Wired。
- 结论：v1 只支持 USB 有线；2.4G 作为后续验证项（同一套协议，理论上可复用）。

---

## 9. 验证工具

`tools/probe/` 下的 C 探针（IOKit，无第三方依赖）：

| 文件 | 用途 |
|---|---|
| `via_probe.c` | 枚举接口 / 打印 report descriptor / 基础命令 |
| `via_probe2.c` | 逐命令读取（只读） |
| `via_probe3.c` | 帧格式与 keyboard value / keycode / buffer / custom 实验 |
| `via_probe4.c` | 全量键位读取 + 写入回读校验 |
| `via_probe5.c` | 修正层偏移后的层读取 / 换位写入测试 / 灯效布局测试 |
| `via_probe6.c` | 灯效完整读写保存 / 宏读写 / channel 探测 |

编译运行（在本机已验证）：

```sh
mkdir -p .probe/tmp .probe/mc
clang -O2 -framework IOKit -framework CoreFoundation tools/probe/via_probe5.c -o .probe/via_probe5
TMPDIR=$PWD/.probe/tmp ./.probe/via_probe5
```

> 首次运行若没有权限，会在「系统设置 → 隐私与安全性 → 输入监控」中提示授权。
