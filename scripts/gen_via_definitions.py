#!/usr/bin/env python3
"""Generate the embedded VIA keyboard-definition library.

Reads every VIA keyboard definition JSON under
``third_party/via-keyboards/src`` (snapshot of https://github.com/the-via/keyboards,
GPL-3.0), validates it, normalises the USB IDs and writes:

  * ``Resources/VIAKeyboardDefinitions/index.json`` - metadata index.
  * ``Resources/VIAKeyboardDefinitions/src/<same relative path>`` - verbatim
    copies of every valid definition (directory structure is preserved so
    same-named files from different vendors cannot collide).
  * ``docs/definitions-report.md`` - human-readable generation report.

The script is deterministic given the input tree; only the ``generatedAt``
field of the index depends on the wall clock.  Set ``SOURCE_DATE_EPOCH`` to
pin that timestamp for byte-identical reproducible output::

    SOURCE_DATE_EPOCH=0 python3 scripts/gen_via_definitions.py

Run from anywhere: paths are resolved relative to the repository root.
"""
from __future__ import annotations

import datetime
import json
import os
import pathlib
import re
import shutil
import sys
from collections import Counter, defaultdict

REPO = pathlib.Path(__file__).resolve().parent.parent
SRC = REPO / "third_party" / "via-keyboards" / "src"
OUT = REPO / "Resources" / "VIAKeyboardDefinitions"
REPORT = REPO / "docs" / "definitions-report.md"

INDEX_VERSION = 1
# A canonical USB ID always fits in 16 bits.  Define-style strings may omit
# the "0x" prefix (and some even carry trailing whitespace), but they are
# always hexadecimal - e.g. "414B" is 0x414B, not decimal 414.
HEX_ID_RE = re.compile(r"^(?:0[xX])?([0-9a-fA-F]{1,4})$")
MATRIX_POS_RE = re.compile(r"^\s*(\d+)\s*,\s*(\d+)\s*$")


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def normalize_usb_id(value):
    """Return ``0x%04X`` for a VIA vendorId/productId, or None if invalid.

    VIA definitions store these either as hexadecimal strings (usually
    ``"0x320F"``, sometimes bare hex like ``"414B"`` / ``"0X4155 "``) or, less
    commonly, as plain integers.  Booleans are rejected: ``True`` is not an ID.
    """
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return "0x%04X" % value if 0 <= value <= 0xFFFF else None
    if isinstance(value, str):
        match = HEX_ID_RE.match(value.strip())
        if match:
            return "0x%04X" % int(match.group(1), 16)
    return None


def iter_kle_keys(keymap):
    """Yield ``(label, dekaled)`` for every key string in a KLE keymap.

    KLE rows are arrays; a JSON object provides layout properties for the
    string that follows it.  Objects that are not followed by a key (e.g. the
    ``{"name": "..."}`` row) are ignored.
    """
    for row in keymap:
        if not isinstance(row, list):
            continue
        pending = {}
        for item in row:
            if isinstance(item, dict):
                pending = {**pending, **item}
            elif isinstance(item, str):
                yield item, pending
                pending = {}


def matrix_stats(keymap):
    """Return stats about matrix positions encoded in KLE key labels.

    VIA stores the matrix position in the first line of a key legend, e.g.
    ``"3,12\\n\\n\\n0,1"`` means matrix (3, 12) and layout-option variant 0,1.
    ``"d": true`` keys are KLE decals (decorations, not real keys) and are
    skipped.  A keyboard normally repeats a coordinate once per layout-option
    variant, so duplicates are expected - they are reported, not "fixed".
    """
    stats = {
        "decal_keys": 0,
        "keys": 0,
        "coords": 0,
        "no_position": 0,
        "dup_groups": 0,
        "dup_keys": 0,
        "max_dup": 0,
        "examples": [],
    }
    seen = Counter()
    for label, props in iter_kle_keys(keymap):
        if props.get("d") is True:
            stats["decal_keys"] += 1
            continue
        stats["keys"] += 1
        first_line = label.split("\n", 1)[0]
        match = MATRIX_POS_RE.match(first_line)
        if not match:
            stats["no_position"] += 1
            if len(stats["examples"]) < 5 and label.strip():
                stats["examples"].append(label.strip()[:40])
            continue
        stats["coords"] += 1
        seen[(int(match.group(1)), int(match.group(2)))] += 1
    duplicate = {coord: count for coord, count in seen.items() if count > 1}
    stats["dup_groups"] = len(duplicate)
    stats["dup_keys"] = sum(duplicate.values())
    stats["max_dup"] = max(duplicate.values(), default=0)
    stats["total_keys"] = stats["keys"]
    if stats["examples"]:
        stats["examples"].sort()
    return stats


def parse_definition(path):
    """Validate one definition.  Returns ``(entry, stats)`` or raises ValueError."""
    try:
        raw = path.read_text(encoding="utf-8")
    except OSError as error:
        raise ValueError(f"cannot read file: {error}") from error
    try:
        definition = json.loads(raw)
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON: {error}") from error

    if not isinstance(definition, dict):
        raise ValueError(f"top-level value is {type(definition).__name__}, expected object")

    name = definition.get("name")
    if not isinstance(name, str) or not name.strip():
        raise ValueError("missing or empty string 'name'")

    matrix = definition.get("matrix")
    if not isinstance(matrix, dict):
        raise ValueError("missing object 'matrix'")
    rows, cols = matrix.get("rows"), matrix.get("cols")
    for key, value in (("rows", rows), ("cols", cols)):
        if isinstance(value, bool) or not isinstance(value, int):
            raise ValueError(f"matrix.{key} is {type(value).__name__}, expected integer")
        if value <= 0:
            raise ValueError(f"matrix.{key} is not positive: {value!r}")

    layouts = definition.get("layouts")
    if not isinstance(layouts, dict):
        raise ValueError("missing object 'layouts'")
    keymap = layouts.get("keymap")
    if not isinstance(keymap, list):
        raise ValueError("missing array 'layouts.keymap'")
    if not keymap:
        raise ValueError("empty 'layouts.keymap'")

    vendor_id = normalize_usb_id(definition.get("vendorId"))
    if vendor_id is None:
        raise ValueError(f"invalid vendorId: {definition.get('vendorId')!r}")
    product_id = normalize_usb_id(definition.get("productId"))
    if product_id is None:
        raise ValueError(f"invalid productId: {definition.get('productId')!r}")

    return definition, {
        "name": name,
        "vendorId": vendor_id,
        "productId": product_id,
        "rows": rows,
        "cols": cols,
        "matrix": matrix_stats(keymap),
    }


def generated_at(previous_index, new_index):
    """UTC timestamp for the index.

    ``SOURCE_DATE_EPOCH`` always wins (reproducible builds).  Otherwise the
    timestamp is only refreshed when the generated content actually changes:
    re-running the generator over an unchanged source tree keeps the previous
    ``generatedAt`` so the output stays byte-identical (idempotent re-runs).
    """
    epoch = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch and epoch.isdigit():
        moment = datetime.datetime.fromtimestamp(int(epoch), datetime.timezone.utc)
        return moment.strftime("%Y-%m-%dT%H:%M:%SZ")
    if isinstance(previous_index, dict):
        same_content = (
            previous_index.get("version") == new_index["version"]
            and previous_index.get("count") == new_index["count"]
            and previous_index.get("entries") == new_index["entries"]
        )
        previous_stamp = previous_index.get("generatedAt")
        if same_content and isinstance(previous_stamp, str) and previous_stamp:
            return previous_stamp
    moment = datetime.datetime.now(datetime.timezone.utc)
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def rel_posix(path):
    return path.relative_to(SRC).as_posix()


# ---------------------------------------------------------------------------
# generation
# ---------------------------------------------------------------------------
def main():
    if not SRC.is_dir():
        sys.exit(f"error: definition source tree not found: {SRC}")
    if not (SRC.parent / "LICENSE").is_file() or not (SRC.parent / "README.md").is_file():
        sys.exit(f"error: LICENSE / README.md missing next to {SRC}")

    files = sorted(SRC.rglob("*.json"))
    if not files:
        sys.exit(f"error: no .json files under {SRC}")

    entries = []
    failures = []
    all_stats = {}
    emitted = {}  # relative path -> bytes, written at the end

    for path in files:
        rel = rel_posix(path)
        try:
            definition, stats = parse_definition(path)
        except ValueError as error:
            failures.append((rel, str(error)))
            continue
        entry = {
            "id": rel[: -len(".json")],
            "name": stats["name"],
            "vendorId": stats["vendorId"],
            "productId": stats["productId"],
            "rows": stats["rows"],
            "cols": stats["cols"],
            "file": "src/" + rel,
        }
        entries.append(entry)
        all_stats[rel] = stats
        emitted["src/" + rel] = path.read_bytes()

    entries.sort(key=lambda entry: entry["file"])

    # A non-canonical spelling of the USB IDs is not an error (they are
    # normalised), but it is worth reporting so the source data can be fixed.
    non_canonical = []
    for path in files:
        rel = rel_posix(path)
        if rel not in all_stats:
            continue
        definition = json.loads(path.read_text(encoding="utf-8"))
        for key in ("vendorId", "productId"):
            raw = definition.get(key)
            canonical = normalize_usb_id(raw)
            if not isinstance(raw, str):
                non_canonical.append((rel, key, raw, canonical, "integer"))
            elif raw == canonical:
                continue
            elif raw[:2] == "0X":
                non_canonical.append((rel, key, raw, canonical, "uppercase-0X-prefix"))
            elif raw != raw.strip():
                non_canonical.append((rel, key, raw, canonical, "surrounding-whitespace"))
            elif not re.match(r"^0[xX]", raw):
                non_canonical.append((rel, key, raw, canonical, "missing-0x-prefix"))
            elif raw == canonical.lower():
                non_canonical.append((rel, key, raw, canonical, "lowercase-hex-letters"))
            else:
                non_canonical.append((rel, key, raw, canonical, "other"))

    # --- write definition copies (only when content changed) --------------
    dest_files = set()
    for rel_file, payload in emitted.items():
        destination = OUT / rel_file
        destination.parent.mkdir(parents=True, exist_ok=True)
        dest_files.add(destination.resolve())
        if not destination.exists() or destination.read_bytes() != payload:
            destination.write_bytes(payload)

    # Remove stale generated files so the output directory mirrors the index.
    removed_stale = 0
    if (OUT / "src").is_dir():
        for stale in sorted((OUT / "src").rglob("*")):
            if stale.is_file() and stale.resolve() not in dest_files:
                stale.unlink()
                removed_stale += 1
        for stale_dir in sorted((OUT / "src").rglob("*"), reverse=True):
            if stale_dir.is_dir() and not any(stale_dir.iterdir()):
                stale_dir.rmdir()

    # --- index.json -------------------------------------------------------
    index = {
        "version": INDEX_VERSION,
        "generatedAt": "",
        "count": len(entries),
        "entries": entries,
    }
    index_path = OUT / "index.json"
    previous_index = None
    if index_path.is_file():
        try:
            previous_index = json.loads(index_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            previous_index = None
    index["generatedAt"] = generated_at(previous_index, index)
    index_bytes = (json.dumps(index, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    if not index_path.exists() or index_path.read_bytes() != index_bytes:
        index_path.write_bytes(index_bytes)

    # --- statistics for the report ---------------------------------------
    total_source_bytes = sum(path.stat().st_size for path in files)
    output_files = sorted(OUT.rglob("*"))
    total_output_files = sum(1 for path in output_files if path.is_file())
    total_output_bytes = sum(path.stat().st_size for path in output_files if path.is_file())

    vid_pid_groups = defaultdict(list)
    for entry in entries:
        vid_pid_groups[(entry["vendorId"], entry["productId"])].append(entry["file"])
    duplicate_ids = {key: value for key, value in vid_pid_groups.items() if len(value) > 1}

    with_duplicates = []
    total_dup_groups = 0
    total_decals = 0
    total_no_position = 0
    for rel, stats in sorted(all_stats.items()):
        matrix = stats["matrix"]
        total_decals += matrix["decal_keys"]
        total_no_position += matrix["no_position"]
        if matrix["dup_groups"]:
            total_dup_groups += matrix["dup_groups"]
            with_duplicates.append((rel, matrix["dup_groups"], matrix["max_dup"]))
    with_duplicates.sort(key=lambda item: (-item[1], item[0]))

    report = render_report(
        files=files,
        entries=entries,
        failures=failures,
        non_canonical=non_canonical,
        total_source_bytes=total_source_bytes,
        total_output_files=total_output_files,
        total_output_bytes=total_output_bytes,
        removed_stale=removed_stale,
        vid_pid_groups=vid_pid_groups,
        duplicate_ids=duplicate_ids,
        with_duplicates=with_duplicates,
        total_dup_groups=total_dup_groups,
        total_decals=total_decals,
        total_no_position=total_no_position,
        index_bytes=len(index_bytes),
    )
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(report, encoding="utf-8")

    print(f"source definitions : {len(files)}")
    print(f"valid definitions  : {len(entries)}")
    print(f"failed definitions : {len(failures)}")
    print(f"duplicate VID/PID  : {len(duplicate_ids)} groups")
    print(f"matrix dup boards  : {len(with_duplicates)} "
          f"({total_dup_groups} duplicate coordinate groups)")
    print(f"index              : {index_path} ({len(entries)} entries, {len(index_bytes)} bytes)")
    print(f"report             : {REPORT}")
    if removed_stale:
        print(f"removed stale files: {removed_stale}")
    for rel, reason in failures[:20]:
        print(f"FAILED {rel}: {reason}")
    if failures:
        sys.exit(1)


def render_report(**kw):
    """Build docs/definitions-report.md.  Pure function of the inputs."""
    entries = kw["entries"]

    lines = [
        "# VIA 键盘定义库生成报告",
        "",
        "本报告由 `scripts/gen_via_definitions.py` 自动生成，请勿手工编辑。",
        "",
        "## 数据来源",
        "",
        "- 上游：<https://github.com/the-via/keyboards>（`src/` 快照，VIA 官方键盘定义仓库）",
        "- 本地副本：`third_party/via-keyboards/`（含上游 `LICENSE` 与 `README.md`）",
        "- 许可证：GPL-3.0（见 `third_party/via-keyboards/LICENSE`）",
        "- 生成命令：`python3 scripts/gen_via_definitions.py`",
        "- 产物：`Resources/VIAKeyboardDefinitions/index.json` + `src/**` 原样副本",
        "",
        "## 结果摘要",
        "",
        "| 项目 | 数值 |",
        "| --- | --- |",
        f"| 扫描 JSON 定义文件 | {len(kw['files'])} |",
        f"| 通过校验、写入索引 | {len(entries)} |",
        f"| 校验失败/跳过 | {len(kw['failures'])} |",
        f"| 索引条目数（`count`） | {len(entries)} |",
        f"| 索引大小 | {kw['index_bytes']} 字节 |",
        f"| 源 JSON 总大小 | {kw['total_source_bytes']} 字节（{kw['total_source_bytes'] / (1024 * 1024):.2f} MiB） |",
        f"| 产物总大小 | {kw['total_output_bytes']} 字节（{kw['total_output_bytes'] / (1024 * 1024):.2f} MiB，{kw['total_output_files']} 个文件，含索引） |",
        f"| 重复 VID/PID 组数 | {len(kw['duplicate_ids'])} |",
        f"| 存在重复 matrix 坐标的键盘数 | {len(kw['with_duplicates'])} / {len(entries)} |",
        f"| 重复 matrix 坐标组数（合计） | {kw['total_dup_groups']} |",
        f"| 清理的陈旧产物文件数 | {kw['removed_stale']} |",
        "",
        "> 说明：任务简报提到约 1482 个定义；本地快照实际包含 "
        f"{len(kw['files'])} 个 `.json` 文件，"
        f"其中 {len(entries)} 个通过校验并进入索引，其余 "
        f"{len(kw['failures'])} 个被跳过（详见下文）。",
        "",
        "## 校验规则",
        "",
        "每个定义必须满足以下条件才会进入索引并被复制：",
        "",
        "1. 顶层为 JSON 对象；",
        "2. `name` 为非空字符串；",
        "3. `matrix.rows` / `matrix.cols` 均为正整数；",
        "4. `layouts.keymap` 为非空数组（V2/V3 均为 KLE keymap 格式）；",
        "5. `vendorId` / `productId` 合法。支持十六进制字符串（`\"0x320F\"`、"
        "不带前缀的 `\"414B\"`、带空格的 `\"0x4155 \"`，统一按十六进制解析）"
        "或整数；统一规范化为大写十六进制、固定 4 位的 `\"0x%04X\"` 字符串。",
        "",
        "不合法/缺失的定义会被跳过，原始文件不会被复制进 `Resources/`。",
        "",
        "## 失败 / 跳过样例",
        "",
    ]
    if kw["failures"]:
        lines += ["最多列出 20 条：", "", "| 文件 | 原因 |", "| --- | --- |"]
        for rel, reason in kw["failures"][:20]:
            lines.append(f"| `src/{rel}` | {reason} |")
        lines.append("")
    else:
        lines += [f"无：{len(kw['files'])} 个定义全部通过校验，失败/跳过 0 个。", ""]

    lines += [
        "## VID / PID 规范化",
        "",
        "所有 USB ID 均成功解析，并统一规范化为大写十六进制、固定 4 位的"
        "`\"0x%04X\"` 字符串。原始写法统计：",
        "",
    ]
    kinds = Counter(item[4] for item in kw["non_canonical"])
    kind_labels = {
        "lowercase-hex-letters": "十六进制字母小写（如 `0xa455`），仅字母大小写差异",
        "missing-0x-prefix": "缺少 `0x` 前缀（如 `\"414B\"`），按十六进制解析",
        "uppercase-0X-prefix": "前缀写作大写 `0X`（如 `\"0X1012\"`）",
        "surrounding-whitespace": "首尾含空白（如 `\"0x4155 \"`），已 strip",
        "integer": "以整数形式给出",
        "other": "其他非标准写法",
    }
    lines += ["| 写法 | 出现次数 |", "| --- | --- |"]
    if kinds:
        for kind, count in kinds.most_common():
            lines.append(f"| {kind_labels.get(kind, kind)} | {count} |")
    else:
        lines.append("| 全部为标准 `0x%04X` 写法 | 0 |")
    lines.append("")
    notable = [item for item in kw["non_canonical"] if item[4] != "lowercase-hex-letters"]
    if notable:
        lines += [
            "除大小写差异外，以下定义需要特别说明（已正确规范化，不影响索引）：",
            "",
            "| 文件 | 字段 | 原始值 | 规范化结果 | 情况 |",
            "| --- | --- | --- | --- | --- |",
        ]
        for rel, key, raw, canonical, kind in notable:
            lines.append(
                f"| `src/{rel}` | `{key}` | `{raw!r}` | `{canonical}` | "
                f"{kind_labels.get(kind, kind)} |"
            )
        lines.append("")
    else:
        lines += ["无缺失前缀或其他异常写法。", ""]

    lines += [
        "## 重复 VID/PID",
        "",
        "VIA 允许同一 VID/PID 存在多个定义（例如不同版本的变体），索引中全部保留，"
        "由使用方自行挑选。",
        "",
    ]
    if kw["duplicate_ids"]:
        lines += [f"共 {len(kw['duplicate_ids'])} 组：", "", "| VID | PID | 定义数 | 文件 |", "| --- | --- | --- | --- |"]
        for (vendor_id, product_id), files in sorted(kw["duplicate_ids"].items()):
            lines.append(
                f"| `{vendor_id}` | `{product_id}` | {len(files)} | "
                + "<br>".join(f"`{path}`" for path in files)
                + " |"
            )
        lines.append("")
    else:
        lines += [
            "本快照中 0 组：全部 "
            f"{len(entries)} 个定义的 VID/PID 组合互不相同（按规范化后的字符串比较）。",
            "",
        ]

    lines += [
        "## matrix 坐标重复（布局选项变体）",
        "",
        "统计方法：遍历 `layouts.keymap` 中的 KLE 键，取键标签首行的 `row,col`"
        "（如 `\"3,12\\n\\n\\n0,1\"` → `(3,12)`）；`\"d\": true` 的 KLE 装饰键"
        "（decal，非真实按键）不参与统计。布局选项变体通常会在同一 matrix 坐标上"
        "重复出现多次，因此重复是正常现象，本报告只统计、不修正。",
        "",
        f"- 存在重复坐标的键盘：**{len(kw['with_duplicates'])}** / {len(entries)}",
        f"- 重复坐标组总数：**{kw['total_dup_groups']}**",
        f"- 被跳过的 decal 键：{kw['total_decals']} 个",
        f"- 无法从键标签首行解析出 matrix 坐标的非 decal 键：{kw['total_no_position']} 个"
        "（这些键不参与重复统计）",
        "",
    ]
    if kw["with_duplicates"]:
        lines += [
            "重复坐标最多的 15 个键盘：",
            "",
            "| 文件 | 重复坐标组数 | 单坐标最大重复次数 |",
            "| --- | --- | --- |",
        ]
        for rel, groups, max_dup in kw["with_duplicates"][:15]:
            lines.append(f"| `src/{rel}` | {groups} | {max_dup} |")
        lines.append("")

    lines += [
        "## 产物清单",
        "",
        f"- `Resources/VIAKeyboardDefinitions/index.json`：版本 1，`count` = {len(entries)}；"
        "`entries[]` 按 `file` 排序，每项含 `id`（相对 `src/` 去掉 `.json` 的路径）、"
        "`name`、规范化后的 `vendorId`/`productId`、`rows`、`cols`、`file`"
        "（相对 `Resources/VIAKeyboardDefinitions/` 的路径）。",
        f"- `Resources/VIAKeyboardDefinitions/src/**`：{len(entries)} 个定义文件的"
        "原样副本，目录结构与 `third_party/via-keyboards/src` 一致。",
        "",
        f"矩阵规模范围：rows {min((e['rows'] for e in entries), default=0)}–"
        f"{max((e['rows'] for e in entries), default=0)}，cols "
        f"{min((e['cols'] for e in entries), default=0)}–"
        f"{max((e['cols'] for e in entries), default=0)}。",
        "",
        "## 幂等性",
        "",
        "- 定义副本仅在内容变化时重写，陈旧产物会被清理，重复执行不会产生重复数据"
        "（例如定义被上游删除后，对应的副本也会从 `Resources/` 移除）。",
        "- 条目的顺序、字段与内容完全由输入树决定。当输入内容不变时，"
        "`generatedAt` 会沿用上一次的值，因此重复执行产生逐字节相同的产物。",
        "- 如需在内容变化时也强制固定时间戳（可复现构建），设置 `SOURCE_DATE_EPOCH`：",
        "",
        "```sh",
        "SOURCE_DATE_EPOCH=0 python3 scripts/gen_via_definitions.py",
        "```",
        "",
    ]
    return "\n".join(lines)


if __name__ == "__main__":
    main()
