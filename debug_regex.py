import subprocess, re
for cmd, mode in [("arecord -l", "capture"), ("aplay -l", "playback")]:
    out = subprocess.check_output(cmd, shell=True, text=True, timeout=5)
    print(f"=== {mode} ({len(out.splitlines())} lines) ===")
    for line in out.splitlines():
        m = re.match(r"card (\d+): (\S+)\s+\[.*\], device (\d+):.*\[(.*)\]", line)
        if m:
            print(f"  MATCH: card={m.group(1)} id={m.group(2)} dev={m.group(3)} desc='{m.group(4)}'")
        elif "card" in line and "device" in line:
            print(f"  NO MATCH: {line}")