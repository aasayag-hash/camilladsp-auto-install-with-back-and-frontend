filepath = r"C:\Users\lenovo\Downloads\fir python\camilladsp-auto-install-with-back-and-frontend-1\web_index.html"
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Specific mappings for box-drawing and special chars
specific = {
    '\u2014': '-',  # em dash
    '\u2013': '-',  # en dash
    '\u2500': '-',  # box drawing horizontal
    '\u2502': '|',  # box drawing vertical
    '\u250c': '+',  # box drawing top-left
    '\u2510': '+',  # box drawing top-right
    '\u2514': '+',  # box drawing bottom-left
    '\u2518': '+',  # box drawing bottom-right
    '\u251c': '+',  # box drawing left tee
    '\u2524': '+',  # box drawing right tee
    '\u252c': '+',  # box drawing top tee
    '\u2534': '+',  # box drawing bottom tee
    '\u253c': '+',  # box drawing crossing
    '\u2588': '#',  # full block
    '\u2591': '.',  # light shade
    '\u2592': ':',  # medium shade
    '\u2593': ':',  # dark shade
    '\u00b7': '.',  # middle dot
    '\u2022': '*',  # bullet
    '\u2026': '...', # ellipsis
    '\u00ab': '<<',  # left double angle
    '\u00bb': '>>',  # right double angle
    '\u2018': "'",   # left single quote
    '\u2019': "'",   # right single quote
    '\u201c': '"',   # left double quote
    '\u201d': '"',   # right double quote
    '\u00d7': 'x',   # multiplication sign
    '\u00f7': '/',   # division sign
    '\u2264': '<=',   # less than or equal
    '\u2265': '>=',   # greater than or equal
    '\u2260': '!=',   # not equal
    '\u221e': 'inf',  # infinity
    '\u00b0': 'deg',  # degree
    '\u00b1': '+/-',  # plus-minus
}

for old, new in specific.items():
    content = content.replace(old, new)

# Then replace any remaining non-ASCII chars (except HTML entities like &#xxxx;)
result = []
i = 0
while i < len(content):
    c = content[i]
    if c == '&' and i+1 < len(content):
        # keep HTML entities
        j = content.find(';', i)
        if j > i and j - i < 10:
            result.append(content[i:j+1])
            i = j + 1
            continue
    if ord(c) > 127:
        result.append('?')
    else:
        result.append(c)
    i += 1

content = ''.join(result)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

# Count remaining non-ASCII
count = sum(1 for c in content if ord(c) > 127)
print(f"Remaining non-ASCII chars: {count}")