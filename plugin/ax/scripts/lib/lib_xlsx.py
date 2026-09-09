"""stdlib 전용 xlsx writer (openpyxl 불필요) — 단일/다중 시트.

inline string / number 셀. Excel·LibreOffice 호환. xlsx 는 곧 zip(OOXML) 이므로
표준 라이브러리 zipfile+xml 로 충분하다 — ax 의 무의존·크로스플랫폼 원칙 준수.

API:
    write_xlsx(path, rows, sheet_name="Sheet1")      # 단일 시트
    write_workbook(path, sheets)                       # 다중 시트: [(name, rows), ...]
rows 는 list[list[cell]] (첫 행 = 헤더). cell 은 str/int/float/None.
"""
import zipfile
from xml.sax.saxutils import escape


def _col_ref(idx0):
    """0-based 열 인덱스 → 엑셀 열 문자(A, B, ... Z, AA)."""
    s, n = "", idx0 + 1
    while n:
        n, r = divmod(n - 1, 26)
        s = chr(65 + r) + s
    return s


def _cell(row1, col0, val):
    ref = f"{_col_ref(col0)}{row1}"
    if isinstance(val, bool):  # bool 은 int 하위형 → 먼저 문자열 처리
        val = str(val)
    elif isinstance(val, (int, float)):
        return f'<c r="{ref}"><v>{val}</v></c>'
    text = escape("" if val is None else str(val))
    return f'<c r="{ref}" t="inlineStr"><is><t xml:space="preserve">{text}</t></is></c>'


def _safe_sheet_name(name, used):
    for ch in r':\/?*[]':
        name = name.replace(ch, "_")
    name = (name or "Sheet")[:31]
    base, i = name, 2
    while name in used:  # 시트명 중복 방지
        suffix = f"_{i}"
        name = base[:31 - len(suffix)] + suffix
        i += 1
    used.add(name)
    return name


def _sheet_xml(rows):
    body = []
    for i, row in enumerate(rows, start=1):
        cells = "".join(_cell(i, j, v) for j, v in enumerate(row))
        body.append(f'<row r="{i}">{cells}</row>')
    return (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        f'<sheetData>{"".join(body)}</sheetData></worksheet>'
    )


def write_workbook(path, sheets):
    """sheets: list[(name, rows)]. 다중 시트 xlsx 저장."""
    if not sheets:
        raise ValueError("sheets 비어있음")
    used = set()
    names = [_safe_sheet_name(n, used) for n, _ in sheets]

    overrides = "".join(
        f'<Override PartName="/xl/worksheets/sheet{i}.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        for i in range(1, len(sheets) + 1)
    )
    content_types = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        f'{overrides}</Types>'
    )
    root_rels = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>'
    )
    sheet_tags = "".join(
        f'<sheet name="{escape(nm)}" sheetId="{i}" r:id="rId{i}"/>'
        for i, nm in enumerate(names, start=1)
    )
    workbook = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        f'<sheets>{sheet_tags}</sheets></workbook>'
    )
    wb_rel_tags = "".join(
        f'<Relationship Id="rId{i}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        f'Target="worksheets/sheet{i}.xml"/>'
        for i in range(1, len(sheets) + 1)
    )
    wb_rels = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        f'{wb_rel_tags}</Relationships>'
    )
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", root_rels)
        z.writestr("xl/workbook.xml", workbook)
        z.writestr("xl/_rels/workbook.xml.rels", wb_rels)
        for i, (_, rows) in enumerate(sheets, start=1):
            z.writestr(f"xl/worksheets/sheet{i}.xml", _sheet_xml(rows))


def write_xlsx(path, rows, sheet_name="Sheet1"):
    """단일 시트 편의 함수."""
    write_workbook(path, [(sheet_name, rows)])
