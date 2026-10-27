# SPDX-License-Identifier: MPL-2.0
"""Flattens a 12 Step Editor preset folder into the harness's tab-separated input."""
import json, sys, os

folder = sys.argv[1]
def kind(v):
    if isinstance(v, bool): return "i", str(int(v))
    if isinstance(v, int): return "i", str(v)
    if isinstance(v, float): return "d", repr(v)
    return "s", str(v)

out = []
for key, preset in json.load(open(os.path.join(folder, "12Step.json"))).items():
    for field, value in preset.items():
        t, v = kind(value)
        out.append(f"P\t{key}\t{field}\t{t}\t{v}")
for slot, name in json.load(open(os.path.join(folder, "setlist.json"))).items():
    out.append(f"S\t{slot}\t{name}")
for field, value in json.load(open(os.path.join(folder, "settings.json"))).get("Global", {}).items():
    t, v = kind(value)
    out.append(f"G\t{field}\t{t}\t{v}")
sys.stdout.write("\n".join(out) + "\n")
