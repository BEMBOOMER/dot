"""Generate DOT launcher sources; native icon generation is a release step."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
BASE = (61, 90, 254)

def sphere():
    image = Image.new('RGBA', (SIZE, SIZE))
    shadow = Image.new('RGBA', image.size)
    ImageDraw.Draw(shadow).ellipse((260, 740, 764, 836), fill=(0, 0, 0, 24))
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(32)))
    pixels = image.load()
    cx, cy, radius = 512, 482, 310
    for y in range(cy-radius, cy+radius+1):
        for x in range(cx-radius, cx+radius+1):
            dx, dy = (x-cx)/radius, (y-cy)/radius
            distance = math.hypot(dx, dy)
            if distance > 1: continue
            light_distance = math.hypot(dx+.4, dy+.5)
            tint = max(0, 1-light_distance/1.55)*.35
            shade = max(0, (light_distance-.7)/1.5)*.32
            highlight = math.exp(-((dx+.32)**2+(dy+.36)**2)/.045)*.55
            rgb = [int((v+(255-v)*tint)*(1-shade)) for v in BASE]
            rgb = [int(v+(255-v)*highlight) for v in rgb]
            pixels[x,y] = (*rgb, int(min(1, (1-distance)*radius)*255))
    return image

if __name__ == '__main__':
    folder = Path(__file__).parent
    foreground = sphere()
    foreground.save(folder/'dot_foreground.png')
    background = Image.new('RGBA', foreground.size, 'white')
    background.alpha_composite(foreground)
    background.convert('RGB').save(folder/'dot_icon.png')

    mac = Image.new('RGBA', foreground.size)
    ImageDraw.Draw(mac).rounded_rectangle((32, 32, 992, 992), radius=216, fill='white')
    mac.alpha_composite(foreground)
    mac.save(folder/'dot_icon_macos.png')
