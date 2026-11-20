# "By Gavin Horricks" in mixed case for the main menu: a 1 bit/pixel strip, 8 rows x 17 bytes (one byte per 8x8 character cell, bit 7 = left column).
# Capitals come from the game font (font8.py); the few lower case letters are drawn here (the game font is capitals only).
import os,sys
B=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','build')
ns={}
exec(open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'font8.py')).read(),ns)
G=ns['G']
L={
 'a':["......","......",".####.",".....#",".#####","#....#",".#####","......"],
 'y':["......","......","#....#","#....#","#....#",".#####",".....#",".####."],
 'v':["......","......","#....#","#....#",".#..#.",".#..#.","..##..","......"],
 'i':["..#...","......",".##...","..#...","..#...","..#...",".###..","......"],
 'n':["......","......","#.###.","##...#","#....#","#....#","#....#","......"],
 'o':["......","......",".####.","#....#","#....#","#....#",".####.","......"],
 'r':["......","......","#.###.","##...#","#.....","#.....","#.....","......"],
 'c':["......","......",".####.","#....#","#.....","#....#",".####.","......"],
 'k':["#.....","#.....","#...#.","#..#..","###...","#..#..","#...#.","......"],
 's':["......","......",".#####","#.....",".####.",".....#","#####.","......"],
}
def cell(ch):
    if ch==' ': return ["."*8]*8
    if ch in L: return [r+"."*(8-len(r)) for r in L[ch]]
    rows=[r+"." for r in G[ch]]; return rows+["."*8]
text="By Gavin Horricks"
cells=[cell(c) for c in text]
out=bytearray()
for r in range(8):
    for c in cells: out.append(int(c[r].replace('#','1').replace('.','0'),2))
open(os.path.join(B,'byline.bin'),'wb').write(out); print(len(out))
