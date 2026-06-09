# -*- coding: utf-8 -*-
"""יצירת קובץ Word של הצעת מחיר לאפליקציית הקטלוג B2B."""
from docx import Document
from docx.shared import Pt, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
from datetime import date

NAVY = RGBColor(0x1F, 0x3A, 0x5F)
GREY = RGBColor(0x55, 0x55, 0x55)
ACCENT = RGBColor(0x2E, 0x86, 0xC1)

doc = Document()

# מסמך RTL כברירת מחדל + פונט בסיס
style = doc.styles["Normal"]
style.font.name = "Arial"
style.font.size = Pt(11)
style.element.rPr.rFonts.set(qn("w:cs"), "Arial")


def set_rtl(paragraph):
    p = paragraph._p
    pPr = p.get_or_add_pPr()
    bidi = OxmlElement("w:bidi")
    pPr.append(bidi)


def run_rtl(run):
    rPr = run._element.get_or_add_rPr()
    rtl = OxmlElement("w:rtl")
    rtl.set(qn("w:val"), "1")
    rPr.append(rtl)


def add_par(text="", size=11, bold=False, color=None, align=WD_ALIGN_PARAGRAPH.RIGHT,
            space_after=6, space_before=0):
    p = doc.add_paragraph()
    set_rtl(p)
    p.alignment = align
    p.paragraph_format.space_after = Pt(space_after)
    p.paragraph_format.space_before = Pt(space_before)
    if text:
        r = p.add_run(text)
        run_rtl(r)
        r.font.size = Pt(size)
        r.font.bold = bold
        if color is not None:
            r.font.color.rgb = color
    return p


def shade_cell(cell, hex_color):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:fill"), hex_color)
    tcPr.append(shd)


def cell_text(cell, text, bold=False, color=None, size=11, align=WD_ALIGN_PARAGRAPH.RIGHT):
    cell.text = ""
    p = cell.paragraphs[0]
    set_rtl(p)
    p.alignment = align
    r = p.add_run(text)
    run_rtl(r)
    r.font.size = Pt(size)
    r.font.bold = bold
    r.font.name = "Arial"
    if color is not None:
        r.font.color.rgb = color


# ===== כותרת =====
add_par("הצעת מחיר", size=26, bold=True, color=NAVY,
        align=WD_ALIGN_PARAGRAPH.CENTER, space_after=2)
add_par("אפליקציית קטלוג והזמנות B2B", size=14, bold=False, color=ACCENT,
        align=WD_ALIGN_PARAGRAPH.CENTER, space_after=14)

# קו מפריד
sep = add_par("", space_after=10)
pPr = sep._p.get_or_add_pPr()
pbdr = OxmlElement("w:pBdr")
bottom = OxmlElement("w:bottom")
bottom.set(qn("w:val"), "single")
bottom.set(qn("w:sz"), "12")
bottom.set(qn("w:space"), "1")
bottom.set(qn("w:color"), "1F3A5F")
pbdr.append(bottom)
pPr.append(pbdr)

# ===== פרטי ההצעה =====
add_par(f"תאריך: {date.today().strftime('%d/%m/%Y')}", size=11, color=GREY)
add_par("לכבוד: ___________________", size=11, color=GREY, space_after=14)

# ===== תיאור =====
add_par("תיאור הפרויקט", size=14, bold=True, color=NAVY, space_before=4, space_after=6)
add_par(
    "פיתוח והפעלה של אפליקציית קטלוג הזמנות עסקית (B2B), בה כל לקוח עסקי "
    "מתחבר עם משתמש אישי וצופה במחירים המותאמים לו (לפי אחוז הנחה), מבצע "
    "הזמנות הנשמרות במערכת, ובעל העסק מנהל מוצרים, לקוחות והזמנות מלוח בקרה ייעודי.",
    size=11, space_after=10)

add_par("המערכת כוללת:", size=12, bold=True, color=NAVY, space_after=4)
for item in [
    "אפליקציית ווב מותקנת (PWA) הנפתחת מהדפדפן ומהנייד.",
    "מערכת התחברות ומשתמשים עם הרשאות (בעל עסק / לקוח).",
    "ניהול מוצרים, לקוחות והגדרת אחוז הנחה אישי לכל לקוח.",
    "מחירים אישיים לכל לקוח וקבלת הזמנות ישירות לעסק.",
    "אבטחת מידע ותמחור בצד השרת (כל לקוח רואה רק את הנתונים שלו).",
    "אחסון וענן מנוהל (Supabase + GitHub Pages).",
]:
    p = add_par(f"•  {item}", size=11, space_after=3)
    p.paragraph_format.right_indent = Cm(0.5)

# ===== טבלת מחירים =====
add_par("פירוט מחיר", size=14, bold=True, color=NAVY, space_before=12, space_after=6)

table = doc.add_table(rows=1, cols=3)
table.alignment = WD_TABLE_ALIGNMENT.CENTER
table.style = "Table Grid"
table.autofit = True

# כותרות (סדר RTL: שירות | תיאור | מחיר)
hdr = table.rows[0].cells
headers = ["שירות", "תיאור", "מחיר (כולל מע\"מ)"]
for c, txt in zip(hdr, headers):
    cell_text(c, txt, bold=True, color=RGBColor(0xFF, 0xFF, 0xFF),
              align=WD_ALIGN_PARAGRAPH.CENTER)
    shade_cell(c, "1F3A5F")

rows = [
    ("בנייה והרצת האפליקציה", "פיתוח, הקמה והעלאה לאוויר של אפליקציית הקטלוג", "3,000 ש\"ח"),
    ("ניהול חודשי", "תחזוקה, אחסון, גיבוי ותמיכה שוטפת", "250 ש\"ח לחודש"),
]
for service, desc, price in rows:
    cells = table.add_row().cells
    cell_text(cells[0], service, bold=True, align=WD_ALIGN_PARAGRAPH.RIGHT)
    cell_text(cells[1], desc, align=WD_ALIGN_PARAGRAPH.RIGHT)
    cell_text(cells[2], price, bold=True, color=ACCENT, align=WD_ALIGN_PARAGRAPH.CENTER)

# שורת סיכום
sum_cells = table.add_row().cells
sum_cells[0].merge(sum_cells[1])
cell_text(sum_cells[0], "תשלום חד-פעמי להקמה", bold=True, align=WD_ALIGN_PARAGRAPH.RIGHT)
cell_text(sum_cells[2], "3,000 ש\"ח", bold=True, color=NAVY, align=WD_ALIGN_PARAGRAPH.CENTER)
for c in sum_cells:
    shade_cell(c, "EAF2F8")

# ===== הערות =====
add_par("הערות", size=14, bold=True, color=NAVY, space_before=14, space_after=6)
for note in [
    "המחירים נקובים בשקלים חדשים (ש\"ח).",
    "דמי הניהול החודשיים נגבים החל מהחודש שלאחר עליית האפליקציה לאוויר.",
    "ההצעה כוללת ליווי והדרכה ראשונית לשימוש במערכת.",
    "תוקף ההצעה: 30 יום מתאריך הוצאתה.",
]:
    p = add_par(f"•  {note}", size=10.5, color=GREY, space_after=3)
    p.paragraph_format.right_indent = Cm(0.5)

# ===== חתימה =====
add_par("בברכה,", size=11, space_before=18, space_after=2)
add_par("___________________", size=11, color=GREY, space_after=2)
add_par("חתימה ותאריך", size=10, color=GREY)

doc.save("/home/user/Online-shop/הצעת_מחיר.docx")
print("saved")
