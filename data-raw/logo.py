"""Final coreval hex logo: monospace wordmark with a terminal block cursor.

Kept as a script so the logo is reproducible rather than a binary nobody can
regenerate. Type is fitted to the hexagon's usable width: a point-up hexagon
of circumradius r has vertical edges at x = cx +/- 0.866r, so the widest band
across the vertical centre is 1.732r.
"""
import math, sys
from PIL import Image, ImageDraw, ImageFont

SLATE  = (43, 63, 86, 255)     # #2b3f56
CREAM  = (242, 237, 227, 255)  # #f2ede3
AMBER  = (232, 163, 61, 255)   # #e8a33d
FONT   = "C:/Windows/Fonts/CascadiaMono.ttf"
FILL   = 0.80                  # share of the usable width the type claims
SS     = 4                     # supersample factor

def hexagon(cx, cy, r):
    return [(cx + r*math.cos(math.radians(a)), cy - r*math.sin(math.radians(a)))
            for a in (90, 150, 210, 270, 330, 30)]

def fit_font(draw, text, target_w, lo=10, hi=2000):
    best = lo
    while lo <= hi:
        mid = (lo+hi)//2
        if draw.textlength(text, font=ImageFont.truetype(FONT, mid)) <= target_w:
            best, lo = mid, mid+1
        else:
            hi = mid-1
    return ImageFont.truetype(FONT, best), best

def build(size):
    S = size*SS
    cx = cy = S/2
    r  = S*0.47
    content = Image.new("RGBA", (S,S), (0,0,0,0))
    d = ImageDraw.Draw(content)
    d.polygon(hexagon(cx, cy, r), fill=SLATE)

    word = "coreval"
    f, fs = fit_font(d, word + "m", 1.732*r*FILL)   # trailing 'm' reserves the cursor cell
    ww = d.textlength(word, font=f)
    cw = d.textlength("m", font=f)
    x  = cx - (ww+cw)/2
    base = cy + fs*0.32
    d.text((x, base), word, font=f, fill=CREAM, anchor="ls")
    d.rectangle([x+ww+cw*0.10, base-fs*0.76, x+ww+cw*0.90, base+fs*0.08], fill=AMBER)

    mask = Image.new("L", (S,S), 0)
    ImageDraw.Draw(mask).polygon(hexagon(cx, cy, r), fill=255)
    content.putalpha(Image.composite(content.getchannel("A"), Image.new("L",(S,S),0), mask))
    out = Image.new("RGBA", (S,S), (0,0,0,0))
    out.paste(content, (0,0), content)
    pts = hexagon(cx, cy, r*0.955)
    ImageDraw.Draw(out).line(pts+[pts[0]], fill=CREAM, width=int(S*0.010), joint="curve")
    return out.resize((size,size), Image.LANCZOS)

if __name__ == "__main__":
    dest = sys.argv[1]
    for px, name in ((240, "logo.png"), (1200, "logo-large.png")):
        p = f"{dest}/{name}"
        build(px).save(p)
        print(f"{name}: {px}x{px}")
