# VIA 键盘定义库生成报告

本报告由 `scripts/gen_via_definitions.py` 自动生成，请勿手工编辑。

## 数据来源

- 上游：<https://github.com/the-via/keyboards>（`src/` 快照，VIA 官方键盘定义仓库）
- 本地副本：`third_party/via-keyboards/`（含上游 `LICENSE` 与 `README.md`）
- 许可证：GPL-3.0（见 `third_party/via-keyboards/LICENSE`）
- 生成命令：`python3 scripts/gen_via_definitions.py`
- 产物：`Resources/VIAKeyboardDefinitions/index.json` + `src/**` 原样副本

## 结果摘要

| 项目 | 数值 |
| --- | --- |
| 扫描 JSON 定义文件 | 1484 |
| 通过校验、写入索引 | 1484 |
| 校验失败/跳过 | 0 |
| 索引条目数（`count`） | 1484 |
| 索引大小 | 330193 字节 |
| 源 JSON 总大小 | 5470460 字节（5.22 MiB） |
| 产物总大小 | 5800653 字节（5.53 MiB，1485 个文件，含索引） |
| 重复 VID/PID 组数 | 0 |
| 存在重复 matrix 坐标的键盘数 | 823 / 1484 |
| 重复 matrix 坐标组数（合计） | 6940 |
| 清理的陈旧产物文件数 | 0 |

> 说明：任务简报提到约 1482 个定义；本地快照实际包含 1484 个 `.json` 文件，其中 1484 个通过校验并进入索引，其余 0 个被跳过（详见下文）。

## 校验规则

每个定义必须满足以下条件才会进入索引并被复制：

1. 顶层为 JSON 对象；
2. `name` 为非空字符串；
3. `matrix.rows` / `matrix.cols` 均为正整数；
4. `layouts.keymap` 为非空数组（V2/V3 均为 KLE keymap 格式）；
5. `vendorId` / `productId` 合法。支持十六进制字符串（`"0x320F"`、不带前缀的 `"414B"`、带空格的 `"0x4155 "`，统一按十六进制解析）或整数；统一规范化为大写十六进制、固定 4 位的 `"0x%04X"` 字符串。

不合法/缺失的定义会被跳过，原始文件不会被复制进 `Resources/`。

## 失败 / 跳过样例

无：1484 个定义全部通过校验，失败/跳过 0 个。

## VID / PID 规范化

所有 USB ID 均成功解析，并统一规范化为大写十六进制、固定 4 位的`"0x%04X"` 字符串。原始写法统计：

| 写法 | 出现次数 |
| --- | --- |
| 十六进制字母小写（如 `0xa455`），仅字母大小写差异 | 151 |
| 缺少 `0x` 前缀（如 `"414B"`），按十六进制解析 | 10 |
| 前缀写作大写 `0X`（如 `"0X1012"`） | 2 |
| 首尾含空白（如 `"0x4155 "`），已 strip | 1 |

除大小写差异外，以下定义需要特别说明（已正确规范化，不影响索引）：

| 文件 | 字段 | 原始值 | 规范化结果 | 情况 |
| --- | --- | --- | --- | --- |
| `src/akb/ogr.json` | `vendorId` | `'414B'` | `0x414B` | 缺少 `0x` 前缀（如 `"414B"`），按十六进制解析 |
| `src/akb/ogr.json` | `productId` | `'4F47'` | `0x4F47` | 缺少 `0x` 前缀（如 `"414B"`），按十六进制解析 |
| `src/akb/ogrn.json` | `vendorId` | `'414B'` | `0x414B` | 缺少 `0x` 前缀（如 `"414B"`），按十六进制解析 |
| `src/akb/ogrn.json` | `productId` | `'4F4E'` | `0x4F4E` | 缺少 `0x` 前缀（如 `"414B"`），按十六进制解析 |
| `src/cybergear/macro25/mkmacro01.json` | `vendorId` | `'1209'` | `0x1209` | 缺少 `0x` 前缀（如 `"414B"`），按十六进制解析 |
| `src/cybergear/macro25/mkmacro01.json` | `productId` | `'69A1'` | `0x69A1` | 缺少 `0x` 前缀（如 `"414B"`），按十六进制解析 |
| `src/daji/seis_cinco/seis_cinco.json` | `vendorId` | `'BF00'` | `0xBF00` | 缺少 `0x` 前缀（如 `"414B"`），按十六进制解析 |
| `src/daji/seis_cinco/seis_cinco.json` | `productId` | `'BF22'` | `0xBF22` | 缺少 `0x` 前缀（如 `"414B"`），按十六进制解析 |
| `src/dztech/duo_s/duo_s.json` | `productId` | `'0X1012'` | `0x1012` | 前缀写作大写 `0X`（如 `"0X1012"`） |
| `src/dztech/endless80/endless80.json` | `productId` | `'0X1015'` | `0x1015` | 前缀写作大写 `0X`（如 `"0X1012"`） |
| `src/oddforge/oddforge_vea.json` | `productId` | `'0x4155 '` | `0x4155` | 首尾含空白（如 `"0x4155 "`），已 strip |
| `src/sheubox/fallacy/fallacy.json` | `vendorId` | `'BF00'` | `0xBF00` | 缺少 `0x` 前缀（如 `"414B"`），按十六进制解析 |
| `src/sheubox/fallacy/fallacy.json` | `productId` | `'BFFA'` | `0xBFFA` | 缺少 `0x` 前缀（如 `"414B"`），按十六进制解析 |

## 重复 VID/PID

VIA 允许同一 VID/PID 存在多个定义（例如不同版本的变体），索引中全部保留，由使用方自行挑选。

本快照中 0 组：全部 1484 个定义的 VID/PID 组合互不相同（按规范化后的字符串比较）。

## matrix 坐标重复（布局选项变体）

统计方法：遍历 `layouts.keymap` 中的 KLE 键，取键标签首行的 `row,col`（如 `"3,12\n\n\n0,1"` → `(3,12)`）；`"d": true` 的 KLE 装饰键（decal，非真实按键）不参与统计。布局选项变体通常会在同一 matrix 坐标上重复出现多次，因此重复是正常现象，本报告只统计、不修正。

- 存在重复坐标的键盘：**823** / 1484
- 重复坐标组总数：**6940**
- 被跳过的 decal 键：821 个
- 无法从键标签首行解析出 matrix 坐标的非 decal 键：1 个（这些键不参与重复统计）

重复坐标最多的 15 个键盘：

| 文件 | 重复坐标组数 | 单坐标最大重复次数 |
| --- | --- | --- |
| `src/rart/rartlite/rartlite.json` | 54 | 4 |
| `src/lazydesigners/dimple.json` | 44 | 6 |
| `src/xd/xd96.json` | 40 | 8 |
| `src/other/mechmini_v2/mechmini_v2.json` | 36 | 4 |
| `src/lazydesigners/the40.json` | 34 | 4 |
| `src/rmi_kb/wete/wete.json` | 31 | 4 |
| `src/4pplet/waffling80_rev_a.json` | 30 | 6 |
| `src/4pplet/waffling80_rev_b.json` | 30 | 6 |
| `src/keebio/dsp40/dsp40-rev1.json` | 30 | 3 |
| `src/YMDK/yd60mq/yd60mq.json` | 29 | 8 |
| `src/other/dz60/dz60.json` | 29 | 10 |
| `src/wolf/ts60/ts60.json` | 29 | 10 |
| `src/zx60/zx60_via.json` | 29 | 10 |
| `src/keebio/quefrency/quefrency-rev3a.json` | 28 | 3 |
| `src/quad_h/lb75/lb75.json` | 28 | 3 |

## 产物清单

- `Resources/VIAKeyboardDefinitions/index.json`：版本 1，`count` = 1484；`entries[]` 按 `file` 排序，每项含 `id`（相对 `src/` 去掉 `.json` 的路径）、`name`、规范化后的 `vendorId`/`productId`、`rows`、`cols`、`file`（相对 `Resources/VIAKeyboardDefinitions/` 的路径）。
- `Resources/VIAKeyboardDefinitions/src/**`：1484 个定义文件的原样副本，目录结构与 `third_party/via-keyboards/src` 一致。

矩阵规模范围：rows 1–20，cols 1–26。

## 幂等性

- 定义副本仅在内容变化时重写，陈旧产物会被清理，重复执行不会产生重复数据（例如定义被上游删除后，对应的副本也会从 `Resources/` 移除）。
- 条目的顺序、字段与内容完全由输入树决定。当输入内容不变时，`generatedAt` 会沿用上一次的值，因此重复执行产生逐字节相同的产物。
- 如需在内容变化时也强制固定时间戳（可复现构建），设置 `SOURCE_DATE_EPOCH`：

```sh
SOURCE_DATE_EPOCH=0 python3 scripts/gen_via_definitions.py
```
