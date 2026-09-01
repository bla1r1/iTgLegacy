import sys
from fontTools.ttLib import TTFont
font = TTFont(sys.argv[1])
for record in font['name'].names:
    if record.nameID == 4 and not record.isUnicode():
        print(record.toStr())
        break
