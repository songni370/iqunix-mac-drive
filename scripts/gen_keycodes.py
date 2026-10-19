#!/usr/bin/env python3
"""Generate the Swift keycode catalogues from the QMK/VIA key-to-byte dictionaries.

* ``third_party/keycodes_v11.json`` (already extracted from VIA ``v11.ts``) ->
  ``Sources/MQ80Core/KeycodeData.swift`` (``KeycodeCatalog.base``).
* ``.probe/src/app-main/src/utils/key-to-byte/v12.ts`` ->
  ``Sources/MQ80Core/KeycodeDataV12.swift`` (``KeycodeCatalog.baseV12``).
* ``.probe/src/app-main/src/utils/key-to-byte/v13.ts`` (v12 minus the legacy
  ``RGB_*`` keycodes, plus the ``UG_*`` / ``RM_*`` overrides) ->
  ``Sources/MQ80Core/KeycodeDataV13.swift`` (``KeycodeCatalog.baseV13``).

The keycode VALUES are QMK facts (GPL-adjacent data extracted from the-via/app,
also mirrored in QMK). Only names/values/categories used.  Every generator is
deterministic: re-running the script over the same input produces byte-identical
output.
"""
import json
import pathlib
import re

repo = pathlib.Path(__file__).resolve().parent.parent
v11_src = repo / "third_party" / "keycodes_v11.json"
key_to_byte_dir = repo / ".probe" / "src" / "app-main" / "src" / "utils" / "key-to-byte"
out_dir = repo / "Sources" / "MQ80Core"
out_v11 = out_dir / "KeycodeData.swift"
out_v12 = out_dir / "KeycodeDataV12.swift"
out_v13 = out_dir / "KeycodeDataV13.swift"

PUNCT = {
    "KC_MINS": ("-", "basic"), "KC_EQL": ("=", "basic"), "KC_LBRC": ("[", "basic"),
    "KC_RBRC": ("]", "basic"), "KC_BSLS": ("\\", "basic"), "KC_NUHS": ("#", "basic"),
    "KC_SCLN": (";", "basic"), "KC_QUOT": ("'", "basic"), "KC_GRV": ("`", "basic"),
    "KC_COMM": (",", "basic"), "KC_DOT": (".", "basic"), "KC_SLSH": ("/", "basic"),
    "KC_SPC": ("Space", "basic"), "KC_ENT": ("Enter", "basic"), "KC_ESC": ("Esc", "basic"),
    "KC_BSPC": ("Backspace", "basic"), "KC_TAB": ("Tab", "basic"), "KC_CAPS": ("Caps", "basic"),
    "KC_NUBS": ("\\", "basic"), "KC_APP": ("Menu", "basic"),
    "KC_EQL": ("=", "basic"),
}
MODS = {
    "KC_LCTL": ("L Ctrl", "modifiers"), "KC_LSFT": ("L Shift", "modifiers"),
    "KC_LALT": ("L Option", "modifiers"), "KC_LGUI": ("L Command", "modifiers"),
    "KC_RCTL": ("R Ctrl", "modifiers"), "KC_RSFT": ("R Shift", "modifiers"),
    "KC_RALT": ("R Option", "modifiers"), "KC_RGUI": ("R Command", "modifiers"),
}
NAV = {
    "KC_PSCR": ("PrtSc", "navigation"), "KC_SLCK": ("Scroll Lock", "navigation"),
    "KC_PAUS": ("Pause", "navigation"), "KC_INS": ("Insert", "navigation"),
    "KC_HOME": ("Home", "navigation"), "KC_PGUP": ("PgUp", "navigation"),
    "KC_DEL": ("Delete", "navigation"), "KC_END": ("End", "navigation"),
    "KC_PGDN": ("PgDn", "navigation"), "KC_RGHT": ("→", "navigation"),
    "KC_LEFT": ("←", "navigation"), "KC_DOWN": ("↓", "navigation"), "KC_UP": ("↑", "navigation"),
}
KEYPAD = {
    "KC_NLCK": ("Num", "keypad"), "KC_PSLS": ("/", "keypad"), "KC_PAST": ("*", "keypad"),
    "KC_PMNS": ("-", "keypad"), "KC_PPLS": ("+", "keypad"), "KC_PENT": ("Enter", "keypad"),
    "KC_P1": ("1", "keypad"), "KC_P2": ("2", "keypad"), "KC_P3": ("3", "keypad"),
    "KC_P4": ("4", "keypad"), "KC_P5": ("5", "keypad"), "KC_P6": ("6", "keypad"),
    "KC_P7": ("7", "keypad"), "KC_P8": ("8", "keypad"), "KC_P9": ("9", "keypad"),
    "KC_P0": ("0", "keypad"), "KC_PDOT": (".", "keypad"), "KC_PEQL": ("=", "keypad"),
}
MEDIA = {
    "KC_MUTE": ("Mute", "media"), "KC_VOLU": ("Vol +", "media"), "KC_VOLD": ("Vol -", "media"),
    "KC_MPLY": ("Play", "media"), "KC_MSTP": ("Stop", "media"), "KC_MNXT": ("Next", "media"),
    "KC_MPRV": ("Prev", "media"), "KC_MFFD": ("FF", "media"), "KC_MRWD": ("Rew", "media"),
    "KC_MSEL": ("Media", "media"), "KC_EJCT": ("Eject", "media"),
    "KC_BRID": ("Bright -", "media"), "KC_BRIU": ("Bright +", "media"),
    "KC_MAIL": ("Mail", "media"), "KC_CALC": ("Calc", "media"), "KC_MYCM": ("My PC", "media"),
    "KC_WSCH": ("Search", "media"), "KC_WHOM": ("Home", "media"), "KC_WBAK": ("Back", "media"),
    "KC_WFWD": ("Forward", "media"), "KC_WSTP": ("Stop", "media"), "KC_WREF": ("Refresh", "media"),
    "KC_WFAV": ("Fav", "media"),
    "KC_PWR": ("Power", "media"), "KC_SLEP": ("Sleep", "media"), "KC_WAKE": ("Wake", "media"),
}
MOUSE = {
    "KC_MS_U": ("Mouse ↑", "mouse"), "KC_MS_D": ("Mouse ↓", "mouse"),
    "KC_MS_L": ("Mouse ←", "mouse"), "KC_MS_R": ("Mouse →", "mouse"),
    "KC_BTN1": ("L Click", "mouse"), "KC_BTN2": ("R Click", "mouse"),
    "KC_BTN3": ("M Click", "mouse"), "KC_BTN4": ("B4", "mouse"), "KC_BTN5": ("B5", "mouse"),
    "KC_WH_U": ("Wheel ↑", "mouse"), "KC_WH_D": ("Wheel ↓", "mouse"),
    "KC_ACCEL": ("Accel", "mouse"),
}
LIGHT = {
    "RGB_TOG": ("RGB Toggle", "lighting"), "RGB_MOD": ("Mode +", "lighting"),
    "RGB_RMOD": ("Mode -", "lighting"), "RGB_HUI": ("Hue +", "lighting"),
    "RGB_HUD": ("Hue -", "lighting"), "RGB_SAI": ("Sat +", "lighting"),
    "RGB_SAD": ("Sat -", "lighting"), "RGB_VAI": ("Bright +", "lighting"),
    "RGB_VAD": ("Bright -", "lighting"), "RGB_SPI": ("Speed +", "lighting"),
    "RGB_SPD": ("Speed -", "lighting"), "RGB_M_P": ("Plain", "lighting"),
    "RGB_M_B": ("Breathe", "lighting"), "RGB_M_R": ("Rainbow", "lighting"),
    "RGB_M_SW": ("Swirl", "lighting"), "RGB_M_SN": ("Snake", "lighting"),
    "RGB_M_K": ("Knight", "lighting"), "RGB_M_X": ("Xmas", "lighting"),
    "RGB_M_G": ("Gradient", "lighting"),
    "BL_TOGG": ("Backlight Toggle", "lighting"), "BL_ON": ("BL On", "lighting"),
    "BL_OFF": ("BL Off", "lighting"), "BL_DEC": ("BL -", "lighting"),
    "BL_INC": ("BL +", "lighting"), "BL_STEP": ("BL Cycle", "lighting"),
    "BL_BRTG": ("BL Breathe", "lighting"),
}
# v12/v13 replace the legacy RGB_* keycodes with UG_* (underglow) and RM_*
# (RGB matrix) keycodes.  They share the same 0x78xx value range, so they are
# explicitly labelled here instead of relying on the code-name fallback.
UG_RM = {
    "UG_TOGG": ("UG Toggle", "lighting"), "UG_NEXT": ("UG Mode +", "lighting"),
    "UG_PREV": ("UG Mode -", "lighting"), "UG_HUEU": ("UG Hue +", "lighting"),
    "UG_HUED": ("UG Hue -", "lighting"), "UG_SATU": ("UG Sat +", "lighting"),
    "UG_SATD": ("UG Sat -", "lighting"), "UG_VALU": ("UG Bright +", "lighting"),
    "UG_VALD": ("UG Bright -", "lighting"), "UG_SPDU": ("UG Speed +", "lighting"),
    "UG_SPDD": ("UG Speed -", "lighting"),
    "RM_ON": ("RM On", "lighting"), "RM_OFF": ("RM Off", "lighting"),
    "RM_TOGG": ("RM Toggle", "lighting"), "RM_NEXT": ("RM Mode +", "lighting"),
    "RM_PREV": ("RM Mode -", "lighting"), "RM_HUEU": ("RM Hue +", "lighting"),
    "RM_HUED": ("RM Hue -", "lighting"), "RM_SATU": ("RM Sat +", "lighting"),
    "RM_SATD": ("RM Sat -", "lighting"), "RM_VALU": ("RM Bright +", "lighting"),
    "RM_VALD": ("RM Bright -", "lighting"), "RM_SPDU": ("RM Speed +", "lighting"),
    "RM_SPDD": ("RM Speed -", "lighting"),
}
OTHER_EXTRA = {
    "KC_GESC": ("Grave/Esc", "basic"), "KC_POWER": ("Power", "media"),
}
CATEGORY_ORDER = [
    "basic", "modifiers", "function", "navigation", "keypad", "media",
    "mouse", "lighting", "layer", "custom", "other",
]

# v13.ts destructures these legacy keycodes out of the v12 dictionary before
# re-exporting it with the UG_*/RM_* overrides.
V13_REMOVED = [
    "RGB_TOG", "RGB_MOD", "RGB_RMOD", "RGB_HUI", "RGB_HUD", "RGB_SAI", "RGB_SAD",
    "RGB_VAI", "RGB_VAD", "RGB_SPI", "RGB_SPD", "RGB_M_P", "RGB_M_B", "RGB_M_R",
    "RGB_M_SW", "RGB_M_SN", "RGB_M_K", "RGB_M_X", "RGB_M_G", "RGB_MODE_RGBTEST",
]


def classify(code, value):
    if code in PUNCT:
        return PUNCT[code]
    if code in MODS:
        return MODS[code]
    if code in NAV:
        return NAV[code]
    if code in KEYPAD:
        return KEYPAD[code]
    if code in MEDIA:
        return MEDIA[code]
    if code in MOUSE:
        return MOUSE[code]
    if code in LIGHT:
        return LIGHT[code]
    if code in UG_RM:
        return UG_RM[code]
    if code in OTHER_EXTRA:
        return OTHER_EXTRA[code]
    m = re.fullmatch(r"KC_([A-Z])", code)
    if m:
        return (m.group(1), "basic")
    m = re.fullmatch(r"KC_(\d)", code)
    if m:
        return (m.group(1), "basic")
    m = re.fullmatch(r"KC_F(\d+)", code)
    if m:
        return ("F" + m.group(1), "function")
    if value == 0x0000:
        return ("—", "basic")
    if value == 0x0001:
        return ("▽", "layer")
    # reasonable fallback label from the code name
    label = code.replace("KC_", "").replace("RGB_", "").replace("BL_", "")
    label = label.replace("_", " ").strip().title()
    cat = "other"
    if value >= 0x7800 and value < 0x7900:
        cat = "lighting"
    if 0x00A0 <= value <= 0x00D4:
        cat = "media"
    return (label, cat)


def collect_entries(data):
    """Normalise one key-to-byte dictionary into sorted, de-duplicated entries."""
    entries = []
    seen = set()
    for code, value in sorted(data.items(), key=lambda kv: kv[1]):
        if code.startswith("_") or value < 0 or value > 0xFFFF or value in seen:
            continue
        label, cat = classify(code, value)
        seen.add(value)
        entries.append((value, code, label, cat))

    # explicit KC_NO / KC_TRNS (dict already has them, but ensure sane labels)
    extra = [
        (0x0000, "KC_NO", "—", "basic"),
        (0x0001, "KC_TRNS", "▽", "layer"),
    ]
    by_value = {e[0]: e for e in entries}
    for e in extra:
        by_value[e[0]] = e
    return sorted(
        by_value.values(),
        key=lambda e: (CATEGORY_ORDER.index(e[3]), e[2].lower(), e[0]),
    )


def render(entries, version, variable):
    lines = [
        f"// Generated by scripts/gen_keycodes.py from QMK/VIA keycodes version {version} data. Do not edit.",
        "// Keycode values are QMK facts; labels are for display only.",
        "extension KeycodeCatalog {",
        f"    static let {variable}: [KeycodeInfo] = [",
    ]
    for value, code, label, cat in entries:
        esc_label = label.replace("\\", "\\\\").replace('"', '\\"')
        esc_code = code.replace('"', '\\"')
        lines.append(
            f'        KeycodeInfo(value: 0x{value:04X}, code: "{esc_code}", label: "{esc_label}", category: .{cat}),'
        )
    lines += ["    ]", "}", ""]
    return "\n".join(lines)


def write(entries, version, variable, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(render(entries, version, variable), encoding="utf-8")
    print(f"wrote {destination} with {len(entries)} keycodes ({variable})")


def parse_ts_export(path):
    """Parse the numeric ``name: 0xNNNN,`` entries of a key-to-byte TS module.

    Only the ``export default { ... }`` object is considered, so helper
    destructuring in ``v13.ts`` (``RGB_TOG: _RGB_TOG``) and spread operators
    are ignored.  Values are TS numeric literals, i.e. hex or decimal.
    """
    if not path.is_file():
        raise SystemExit(f"error: missing keycode source: {path}")
    text = path.read_text(encoding="utf-8")
    start = text.find("export default")
    if start < 0:
        raise SystemExit(f"error: no 'export default' object in {path}")
    entries = {}
    pattern = re.compile(
        r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(0[xX][0-9a-fA-F]+|\d+)\s*,?\s*$",
        re.MULTILINE,
    )
    for match in pattern.finditer(text[start:]):
        entries[match.group(1)] = int(match.group(2), 0)
    if not entries:
        raise SystemExit(f"error: no keycode entries found in {path}")
    return entries


def build_v13(v12_entries):
    """Apply v13.ts semantics: v12 minus legacy RGB_* plus v13's overrides."""
    v13 = {code: value for code, value in v12_entries.items() if code not in V13_REMOVED}
    overrides = parse_ts_export(key_to_byte_dir / "v13.ts")
    missing = [code for code in V13_REMOVED if code not in v12_entries]
    if missing:
        raise SystemExit(f"error: v13.ts removes keycodes absent from v12.ts: {missing}")
    overlap_removed = [code for code in overrides if code in V13_REMOVED]
    if overlap_removed:
        raise SystemExit(f"error: v13 overrides collide with removed keycodes: {overlap_removed}")
    v13.update(overrides)
    return v13, overrides


def main():
    # --- v11 -------------------------------------------------------------
    v11 = json.loads(v11_src.read_text(encoding="utf-8"))
    write(collect_entries(v11), 11, "base", out_v11)

    # --- v12 -------------------------------------------------------------
    v12 = parse_ts_export(key_to_byte_dir / "v12.ts")
    write(collect_entries(v12), 12, "baseV12", out_v12)

    # --- v13 -------------------------------------------------------------
    v13, overrides = build_v13(v12)
    entries_v13 = collect_entries(v13)
    write(entries_v13, 13, "baseV13", out_v13)
    removed = len(V13_REMOVED)
    print(
        f"v13 = v12 - {removed} legacy RGB_* keycodes + {len(overrides)} v13 overrides "
        f"({len(v12)} raw v12 entries -> {len(v13)} raw v13 entries)"
    )


if __name__ == "__main__":
    main()
