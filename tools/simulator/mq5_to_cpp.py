import re, sys

def strip_comments(text):
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == '\\' else 1
            out.append(text[i:j+1]); i = j + 1
        elif c == "'":
            j = i + 1
            while j < n and text[j] != "'":
                j += 2 if text[j] == '\\' else 1
            out.append(text[i:j+1]); i = j + 1
        elif text.startswith('//', i):
            j = text.find('\n', i)
            if j < 0: j = n
            i = j
        elif text.startswith('/*', i):
            j = text.find('*/', i + 2)
            i = n if j < 0 else j + 2
        else:
            out.append(c); i += 1
    return ''.join(out)

def wrap_literals(text):
    # merge adjacent literals ("a" "b" -> "ab"), then wrap each literal as string("...")
    lit = r'"(?:[^"\\\n]|\\.)*"'
    prev = None
    while prev != text:
        prev = text
        text = re.sub(r'(' + lit + r')\s+(' + lit + r')', lambda m: m.group(1)[:-1] + m.group(2)[1:], text)
    return re.sub(lit, lambda m: 'string(' + m.group(0) + ')', text)

args = sys.argv[1:]
header = 'mql5_mock.h'
overrides = {}
path = None
i = 0
while i < len(args):
    if args[i] == '--header':
        header = args[i+1]; i += 2
    elif args[i] == '--set':
        k, v = args[i+1].split('=', 1); overrides[k] = v; i += 2
    else:
        path = args[i]; i += 1
src = strip_comments(open(path, encoding='utf-8').read())
out = []
for line in src.split('\n'):
    s = line.strip()
    if s.startswith('#property') or s.startswith('#include') or re.match(r'^input\s+group\b', s):
        continue
    m = re.match(r'^(\s*)(input|sinput)\s+(\w+)\s+(\w+)\s*=\s*(.*);\s*$', line)
    if m and m.group(4) in overrides:
        line = f'{m.group(1)}input {m.group(3)} {m.group(4)} = {overrides.pop(m.group(4))};'
    line = re.sub(r'^(\s*)(input|sinput)\s+', r'\1const ', line)
    def dlit(m):
        import calendar, datetime as dtm
        txt = m.group(1).strip()
        for fmt in ('%Y.%m.%d %H:%M:%S', '%Y.%m.%d %H:%M', '%Y.%m.%d'):
            try:
                return str(calendar.timegm(dtm.datetime.strptime(txt, fmt).timetuple())) + 'L'
            except ValueError:
                pass
        raise SystemExit('bad date literal ' + txt)
    line = re.sub(r"D'([^']*)'", dlit, line)
    line = re.sub(r'(const\s+)?(\w+)\s*&\s*(\w+)\s*\[\s*\]', lambda m: f"{m.group(1) or ''}MqlArray<{m.group(2)}> &{m.group(3)}", line)
    line = re.sub(r'^(\s*)(static\s+)?(\w+)\s+(\w+)\s*\[\s*\]\s*;', lambda m: f"{m.group(1)}{m.group(2) or ''}MqlArray<{m.group(3)}> {m.group(4)};", line)
    line = re.sub(r'^(\s*)(\w+)\s+(\w+)\s*\[\s*(\d+)\s*\]\s*;', lambda m: f"{m.group(1)}MqlArray<{m.group(2)}> {m.group(3)}({m.group(4)});", line)
    out.append(line)
body = wrap_literals('\n'.join(out))
if overrides:
    sys.exit('unknown inputs: ' + ', '.join(overrides))
print('#include "' + header + '"')
if header == 'mql5_mock.h':
    print('string _Symbol; ENUM_TIMEFRAMES _Period; double _Point; int _Digits;')
print(body)
