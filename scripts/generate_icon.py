"""Generate 1Claw.net app icon — a stylized '1' + Claw on a gradient background."""

from PIL import Image, ImageDraw, ImageFont
import os, math

SIZE = 1024
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'icon', 'app_icon.png')

# Colors
BG_TOP = (18, 20, 48)      # deep navy
BG_BOT = (40, 18, 64)      # deep purple
CLAW = (255, 255, 255)     # white
ACCENT = (120, 200, 255)   # cyan accent

img = Image.new('RGBA', (SIZE, SIZE))
draw = ImageDraw.Draw(img)

# --- 1. Gradient background (rounded rect) ---
for y in range(SIZE):
    t = y / SIZE
    r = int(BG_TOP[0] + (BG_BOT[0] - BG_TOP[0]) * t)
    g = int(BG_TOP[1] + (BG_BOT[1] - BG_TOP[1]) * t)
    b = int(BG_TOP[2] + (BG_BOT[2] - BG_TOP[2]) * t)
    draw.rectangle([(0, y), (SIZE, y)], fill=(r, g, b))

# Rounded rect clipping mask
mask = Image.new('L', (SIZE, SIZE), 0)
mask_draw = ImageDraw.Draw(mask)
radius = 180
mask_draw.rounded_rectangle([(0, 0), (SIZE, SIZE)], radius=radius, fill=255)

# Apply mask
img.putalpha(mask)

# --- 2. Claw shape (bottom curve + top hook) ---
# A crab claw / hook shape wrapping around the "1"
cx, cy = SIZE // 2, SIZE // 2

# Main claw arc (a sweeping hook shape)
claw_width = 40
claw_color = CLAW

# Draw the claw as a thick curved line
# Outer arc (top-right to bottom-left sweep)
arc_bbox = (SIZE * 0.15, SIZE * 0.25, SIZE * 0.85, SIZE * 0.85)
arc_start = 160   # degrees (left side bottom)
arc_end = 20      # degrees (right side top)
steps = 120
claw_points = []
for i in range(steps + 1):
    angle = math.radians(arc_start + (arc_end - arc_start) * i / steps)
    x = arc_bbox[0] + (arc_bbox[2] - arc_bbox[0]) * (0.5 + 0.5 * math.cos(angle))
    y = arc_bbox[1] + (arc_bbox[3] - arc_bbox[1]) * (0.5 + 0.5 * math.sin(angle))
    claw_points.append((x, y))

# Draw the curved claw body
for thickness in range(-claw_width // 2, claw_width // 2):
    offset_pts = []
    for i, (px, py) in enumerate(claw_points):
        angle = math.radians(arc_start + (arc_end - arc_start) * i / steps)
        # perpendicular offset
        ox = -math.sin(angle) * thickness * 0.4
        oy = math.cos(angle) * thickness * 0.4
        offset_pts.append((px + ox, py + oy))
    if len(offset_pts) > 1:
        draw.line(offset_pts, fill=(*claw_color, min(255, 255 - abs(thickness) * 1)), width=4)

# --- 3. The number "1" with serif styling ---
# Use a thick vertical bar
bar_x = cx
bar_top = SIZE * 0.22
bar_bot = SIZE * 0.72
bar_w = 48

# Vertical bar with gradient
for y in range(int(bar_top), int(bar_bot)):
    t2 = (y - bar_top) / (bar_bot - bar_top)
    # slight width taper
    w = bar_w * (1 - t2 * 0.15)
    x1 = bar_x - w / 2
    x2 = bar_x + w / 2
    alpha = int(255 * (0.85 + 0.15 * (1 - t2)))
    # cyan glow on edges
    draw.line([(x1, y), (x2, y)], fill=(*CLAW, alpha), width=3)

# Top serif (angled cap)
serif_pts = [
    (bar_x - bar_w * 0.6, bar_top - 10),
    (bar_x + bar_w * 1.2, bar_top - 40),
    (bar_x + bar_w * 1.2, bar_top + 15),
    (bar_x - bar_w * 0.3, bar_top + 5),
]
draw.polygon(serif_pts, fill=(*CLAW, 240))

# Bottom base serif
base_pts = [
    (bar_x - bar_w * 0.5, bar_bot),
    (bar_x + bar_w * 0.5, bar_bot),
    (bar_x + bar_w * 0.7, bar_bot + 25),
    (bar_x - bar_w * 0.7, bar_bot + 25),
]
draw.polygon(base_pts, fill=(*CLAW, 200))

# --- 4. Pincer (sharp hook tip at the end of the claw) ---
pincer_x = SIZE * 0.82
pincer_y = SIZE * 0.28
pincer_size = 35
draw.polygon([
    (pincer_x, pincer_y),
    (pincer_x + pincer_size, pincer_y - pincer_size // 3),
    (pincer_x + pincer_size // 2, pincer_y + pincer_size // 4),
], fill=(*CLAW, 220))

# Second smaller pincer
draw.polygon([
    (pincer_x - 15, pincer_y + 20),
    (pincer_x + 5, pincer_y - 5),
    (pincer_x + 5, pincer_y + 30),
], fill=(*CLAW, 180))

# --- 5. Glow / shadow effects ---
# Soft outer glow
glow = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
gdraw = ImageDraw.Draw(glow)
for r in range(40, 60):
    alpha = max(0, 20 - r)
    gdraw.rounded_rectangle(
        [(r, r), (SIZE - r, SIZE - r)],
        radius=180, outline=(*ACCENT, 0), width=2
    )

# Highlight dot (small sparkle near pincer)
sparkle_x, sparkle_y = SIZE * 0.78, SIZE * 0.32
for s in range(3, 0, -1):
    draw.ellipse(
        [(sparkle_x - s*3, sparkle_y - s*3), (sparkle_x + s*3, sparkle_y + s*3)],
        fill=(*ACCENT, 255 - s * 60)
    )

os.makedirs(os.path.dirname(OUT), exist_ok=True)
img.save(OUT, 'PNG')
print(f"Icon saved: {OUT} ({os.path.getsize(OUT)} bytes)")
print(f"Dimensions: {img.size}")
