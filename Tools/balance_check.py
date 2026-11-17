import io, re

files = [
    r"Views/ReaderView.swift",
    r"Views/RootView.swift",
    r"Core/BookReaderCore.swift",
    r"Views/PagedReaderView.swift",
]
str_re = re.compile(r'"(?:[^"\\]|\\.)*"')
line_comment = re.compile(r"//[^\n]*")
block_comment = re.compile(r"/\*.*?\*/", re.S)

for f in files:
    s = io.open(f, encoding="utf-8").read()
    s = str_re.sub('""', s)
    s = line_comment.sub("", s)
    s = block_comment.sub("", s)
    print(f, "braces", s.count("{") - s.count("}"),
          "parens", s.count("(") - s.count(")"),
          "brackets", s.count("[") - s.count("]"))
