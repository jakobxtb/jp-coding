import zlib, struct, math, sys
N=1024
BG=(0x06,0x0b,0x0d); PANEL=(0x0c,0x14,0x18); G=(0x3d,0xff,0xa8); DIM=(0x1c,0x6b,0x4c)
R=N*0.225
def rr(x,y,m,rad):
    dx=max(m+rad-x,0,x-(N-m-rad)); dy=max(m+rad-y,0,y-(N-m-rad))
    return math.hypot(dx,dy)-rad
def segd(px,py,ax,ay,bx,by):
    vx,vy=bx-ax,by-ay; wx,wy=px-ax,py-ay
    t=max(0,min(1,(wx*vx+wy*vy)/(vx*vx+vy*vy+1e-9)))
    return math.hypot(px-(ax+t*vx),py-(ay+t*vy))
def S_(*p): return [(a*N,b*N,c*N,d*N) for a,b,c,d in p]
J=S_((.435,.315,.435,.600),(.435,.600,.398,.664),(.398,.664,.330,.660))
P=S_((.585,.315,.585,.690),(.585,.315,.712,.315),(.712,.315,.712,.437),(.712,.437,.585,.437))
STROKE=N*0.036
UND=(N*0.30,N*0.775,N*0.70,N*0.775)
def letters(x,y):
    d=min(min(segd(x,y,*s) for s in J), min(segd(x,y,*s) for s in P))
    return max(0.0,min(1.0,STROKE-d+0.5))
def under(x,y):
    d=segd(x,y,*UND); return max(0.0,min(1.0,N*0.016-d+0.5))
buf=bytearray()
for y in range(N):
    buf.append(0); row=bytearray()
    for x in range(N):
        px,py=x+.5,y+.5
        a=max(0.0,min(1.0,0.5-rr(px,py,N*0.055,R)))
        if a<=0: row+=b'\x00\x00\x00\x00'; continue
        inner=max(0.0,min(1.0,0.5-rr(px,py,N*0.105,R*0.82)))
        r,g,b=[int(BG[i]+(PANEL[i]-BG[i])*inner) for i in range(3)]
        ring=max(0.0,min(1.0,1.0-abs(rr(px,py,N*0.075,R*0.93))/2.2))
        if ring>0: r,g,b=[int(v+(DIM[i]-v)*ring*0.9) for i,v in enumerate((r,g,b))]
        L=letters(px,py)
        if L>0: r,g,b=[int(v+(G[i]-v)*L) for i,v in enumerate((r,g,b))]
        U=under(px,py)
        if U>0: r,g,b=[int(v+(G[i]-v)*U*0.8) for i,v in enumerate((r,g,b))]
        row+=bytes((r,g,b,int(a*255)))
    buf+=row
def ch(t,d):
    c=t+d; return struct.pack('>I',len(d))+c+struct.pack('>I',zlib.crc32(c)&0xffffffff)
open(sys.argv[1],'wb').write(b'\x89PNG\r\n\x1a\n'
 +ch(b'IHDR',struct.pack('>IIBBBBB',N,N,8,6,0,0,0))
 +ch(b'IDAT',zlib.compress(bytes(buf),6))+ch(b'IEND',b''))
print("ok")
