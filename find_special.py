import re

filepath = r"C:\Users\lenovo\Downloads\fir python\camilladsp-auto-install-with-back-and-frontend-1\web_index.html"
with open(filepath, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    for j, c in enumerate(line):
        if ord(c) > 127:
            print(f"Line {i+1}, col {j+1}: char='{c}' (U+{ord(c):04X}) context: ...{line[max(0,j-10):j+10].strip()}...")