import re

filepath = r"C:\Users\lenovo\Downloads\fir python\camilladsp-auto-install-with-back-and-frontend-1\web_index.html"
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

replacements = {
    'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u',
    'ñ': 'n', 'Á': 'A', 'É': 'E', 'Í': 'I', 'Ó': 'O',
    'Ú': 'U', 'Ñ': 'N', '¿': '?', '¡': '!', 'ü': 'u', 'Ü': 'U',
}

for old, new in replacements.items():
    content = content.replace(old, new)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

print("Done")