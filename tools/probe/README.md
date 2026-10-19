# 真机协议探针（IQUNIX MQ80）

本目录是可行性验证阶段使用的 C 探针，直接调用 macOS `IOKit/hid`，无第三方依赖。

## 编译与运行

```sh
cd <repo 根目录>
mkdir -p .probe/tmp
clang -O2 -framework IOKit -framework CoreFoundation tools/probe/via_probe5.c -o .probe/via_probe5
TMPDIR=$PWD/.probe/tmp ./.probe/via_probe5
```

- 首次运行会被系统提示授权「输入监控」（系统设置 → 隐私与安全性 → 输入监控）。授权宿主 App/终端后重试。
- 只识别 `VID=0x320F`、`PID=0x5055` 的 `UsagePage 0xFF60 / Usage 0x61` 接口，不会影响键盘正常输入。

## 各探针用途

| 文件 | 说明 |
|---|---|
| `via_probe.c` | 枚举接口、打印 HID report descriptor、发基础命令 |
| `via_probe2.c` | 逐命令只读探测（协议版本、keyboard value、层数、键位、宏、custom） |
| `via_probe3.c` | 帧格式实验、键码读取、keymap buffer、custom channel、未知命令 |
| `via_probe4.c` | 全量 4 层键位读取（注意：当时层偏移写错，4 层读到的是同一层） |
| `via_probe5.c` | 修正层偏移；层差异对比；空位写入-回读-还原；灯效写入布局；宏写入 |
| `via_probe6.c` | 灯效完整读写保存、channel 扫描、宏缓冲读取、UI_SYNC 探测 |

## 会写键盘的探针（注意）

- `via_probe4.c`：只写回原值（字节级相同），不会改变键位；但会写灯效亮度（旧布局，可能改掉亮度，需手动恢复）。
- `via_probe5.c`：会临时改写一个空矩阵位再还原，并写回原灯效值；运行完会恢复原状（亮度 5 / WAVE / 速度 2 / 色相 0 饱和度 255）。
- `via_probe6.c`：灯效写入的是读到的原值；宏写入测试后会 `0x10` 重置宏缓冲（测试时缓冲为空）。
- 其余探针为只读。

> 写入命令没有固件风险（只写键位/灯效 EEPROM），但运行前仍建议先备份键位（`0x12` 全量导出）。

## 实测结果

见同目录 [`RESULTS.md`](RESULTS.md)。
