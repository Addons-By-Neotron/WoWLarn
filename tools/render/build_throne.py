"""Build + render a carved marble throne standing on the ground (with a shadow).  Usage:
blender -b -P build_throne.py -- out.png '{"jewels":true, "tint":[r,g,b], ...}'
Massive marble blocks on a stepped plinth: seat, slab armrests, tall back with a pointed crest and a raised
carved panel; jewels set in gold bezels.  jewels=false gives the pried-off version: dark empty holes.
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "throne.png"
P = dict(jewels=True, tint=(0.78, 0.78, 0.8), marble_scale=0.45, gold=(0.95, 0.68, 0.25),
         gems=[(0.75, 0.0, 0.03), (0.03, 0.12, 0.85), (0.02, 0.6, 0.15)], yaw=0, elev=20, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

root = bpy.data.objects.new("Throne", None); sc.collection.objects.link(root)

def obj(name, bm, material, bevel=0.0, segs=3, smooth=True):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = smooth
    o = link(sc, name, me); o.parent = root; o.data.materials.append(material)
    if bevel:
        m = o.modifiers.new("Bevel", 'BEVEL'); m.width = bevel; m.segments = segs; m.limit_method = 'ANGLE'
    return o

def box(sx, sy, sz, loc):
    """Box of size (sx, sy, sz); loc is the centre of its bottom face."""
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co = Vector((v.co.x*sx + loc[0], v.co.y*sy + loc[1], (v.co.z + 0.5)*sz + loc[2]))
    return bm

def lathe(profile, loc, segs=20):
    """Turned part: profile [(radius, z), ...] bottom to top, revolved about Z at loc (x, y, z)."""
    bm = bmesh.new(); rings = []
    for r, z in profile:
        rings.append([bm.verts.new((loc[0] + r*math.cos(a), loc[1] + r*math.sin(a), loc[2] + z))
                      for a in (math.tau*k/segs for k in range(segs))])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k+1) % segs], r1[(k+1) % segs], r1[k]))
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1])
    return bm

def slab(outline, y0, y1):
    """Extrude a closed XZ outline [(x, z), ...] between y0 (front) and y1 (back)."""
    bm = bmesh.new()
    f = [bm.verts.new((x, y0, z)) for x, z in outline]; b = [bm.verts.new((x, y1, z)) for x, z in outline]
    n = len(outline)
    bm.faces.new(f); bm.faces.new(b[::-1])
    for k in range(n):
        bm.faces.new((f[k], b[k], b[(k+1) % n], f[(k+1) % n]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

def arch(hw, zb, zs, zp, n=24):
    """Outline with straight sides up to zs, then a pointed arch to the peak zp."""
    top = [(hw*x, zs + (zp - zs)*(1 - abs(x))**0.55) for x in (1 - 2*k/n for k in range(n + 1))]
    return [(-hw, zb), (hw, zb)] + top

def arch_z(hw, zs, zp, x):
    return zs + (zp - zs)*max(0.0, 1 - abs(x)/hw)**0.55

# ---- materials
# marble: ambientCG Marble012 (CC0) colour/roughness/normal maps, box-projected in object space (no UVs needed)
TEX = os.path.join(os.path.dirname(os.path.abspath(__file__)), "textures", "Marble012_2K-JPG_")
stone, sb = mat("Marble", (1, 1, 1))
nt = stone.node_tree; N = nt.nodes.new; Lk = nt.links.new
tc = N("ShaderNodeTexCoord"); mp = N("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (P["marble_scale"],)*3
Lk(tc.outputs["Object"], mp.inputs["Vector"])
def tex(kind, colour=True):
    t = N("ShaderNodeTexImage"); t.image = bpy.data.images.load(TEX + kind + ".jpg")
    if not colour: t.image.colorspace_settings.name = "Non-Color"
    t.projection = 'BOX'; t.projection_blend = 0.25; Lk(mp.outputs["Vector"], t.inputs["Vector"])
    return t
col = tex("Color")
tint = N("ShaderNodeMix"); tint.data_type = 'RGBA'; tint.blend_type = 'MULTIPLY'; tint.inputs["Factor"].default_value = 1.0
tint.inputs["B"].default_value = (*P["tint"], 1); Lk(col.outputs["Color"], tint.inputs["A"]); Lk(tint.outputs["Result"], sb.inputs["Base Color"])
rgh = tex("Roughness", False)
rr = N("ShaderNodeMapRange"); rr.inputs["To Min"].default_value = 0.12; rr.inputs["To Max"].default_value = 0.45   # polished
Lk(rgh.outputs["Color"], rr.inputs["Value"]); Lk(rr.outputs["Result"], sb.inputs["Roughness"])
nrm = tex("NormalGL", False)
nm = N("ShaderNodeNormalMap"); nm.inputs["Strength"].default_value = 0.6
Lk(nrm.outputs["Color"], nm.inputs["Color"]); Lk(nm.outputs["Normal"], sb.inputs["Normal"])

gold, _ = mat("Gold", P["gold"], Metallic=1.0, Roughness=0.3)
gem_mats = [mat(f"Gem{i}", c, Roughness=0.02, IOR=1.75, **{"Transmission Weight": 0.5, "Coat Weight": 0.6})[0]
            for i, c in enumerate(P["gems"])]
hole, _ = mat("Socket", (0.012, 0.01, 0.009), Roughness=0.8)

# ---- stepped plinth, seat block, slab armrests
obj("Plinth", box(2.5, 2.1, 0.22, (0, 0.05, 0)), stone, bevel=0.04)
obj("Step", box(2.2, 1.85, 0.18, (0, 0.08, 0.22)), stone, bevel=0.04)
Z0 = 0.4                                           # top of the plinth
SW, SD, SH = 1.3, 1.25, 0.55                       # seat width, depth, height
obj("Seat", box(SW, SD, SH, (0, 0, Z0)), stone, bevel=0.05)
obj("SeatPanel", box(SW - 0.3, 0.04, SH - 0.22, (0, -SD/2 - 0.01, Z0 + 0.11)), stone, bevel=0.015)   # carved front panel
AW, AH = 0.32, 1.1                                 # armrest slab width, height above the plinth
for s in (-1, 1):
    x = s*(SW/2 + AW/2)
    obj("Arm", box(AW, SD + 0.1, AH, (x, -0.02, Z0)), stone, bevel=0.07, segs=4)
    obj("ArmCap", box(AW + 0.08, SD + 0.18, 0.1, (x, -0.04, Z0 + AH)), stone, bevel=0.04)

# ---- tall back slab with a pointed crest; raised carved panel on its front
BW, BT = SW + 2*AW + 0.04, 0.32                    # back spans the arms
BY = SD/2 - 0.02                                   # front face of the back
ZS, ZP = 2.45, 3.05                                # where the crest starts, its peak
obj("Back", slab(arch(BW/2, Z0, ZS, ZP), BY, BY + BT), stone, bevel=0.05, segs=4)
PW, PZS, PZP = SW/2 - 0.08, 2.2, 2.65             # panel half width, arch start, peak
obj("Panel", slab(arch(PW, Z0 + SH, PZS, PZP), BY - 0.05, BY + 0.01), stone, bevel=0.025)
obj("PanelIn", slab(arch(PW - 0.1, Z0 + SH + 0.1, PZS - 0.05, PZP - 0.16), BY - 0.08, BY - 0.04), stone, bevel=0.02)
for s in (-1, 1):                                  # stone balls on the back's shoulders
    sp = bmesh.new(); bmesh.ops.create_uvsphere(sp, u_segments=20, v_segments=12, radius=0.16)
    for v in sp.verts: v.co += Vector((s*(BW/2 - 0.16), BY + BT/2, ZS + 0.12))
    obj("Ball", sp, stone)

# ---- jewels in gold bezels (or empty sockets): all face the front (-Y)
def setting(x, y, z, r, k):
    bz = lathe([(r*1.35, -0.03), (r*1.35, 0.0), (r*1.1, 0.025), (r*0.95, 0.02)], (0, 0, 0), segs=16)
    bmesh.ops.rotate(bz, verts=bz.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.pi/2, 3, 'X'))
    bmesh.ops.translate(bz, verts=bz.verts, vec=(x, y, z))
    if P["jewels"]:
        obj("Bezel", bz, gold)
        g = bmesh.new(); bmesh.ops.create_uvsphere(g, u_segments=8, v_segments=4, radius=r)
        for v in g.verts: v.co = Vector((v.co.x + x, v.co.y*0.55 + y - 0.01, v.co.z + z))
        obj("Gem", g, gem_mats[k % len(gem_mats)], smooth=False)
    else:
        bz.free()                                                          # pried out: setting gone too, dark hole left
        h = bmesh.new(); bmesh.ops.create_circle(h, cap_ends=True, segments=16, radius=r*1.15)
        for v in h.verts: v.co = Vector((v.co.x + x, y - 0.012, v.co.y + z))
        obj("Hole", h, hole)

setting(0, BY - 0.005, (PZP + ZP)/2 + 0.05, 0.14, 0)                   # crest jewel above the panel
for i, t in enumerate((-0.8, -0.45, 0.45, 0.8)):   # round the panel's arch, on its raised rim
    x = t*(PW - 0.05)
    setting(x, BY - 0.055, arch_z(PW - 0.05, PZS - 0.02, PZP - 0.07, x), 0.065, i + 1)
setting(0, BY - 0.085, 1.75, 0.1, 0)               # centre of the inner panel
for s, k in ((-1, 1), (1, 2)):
    setting(s*(SW/2 + AW/2), -(SD + 0.1)/2 - 0.025, Z0 + AH - 0.22, 0.08, k)   # arm fronts
for i, x in enumerate((-0.32, 0, 0.32)):                                    # seat front panel
    setting(x, -SD/2 - 0.035, Z0 + SH/2, 0.075 if x else 0.09, i)

# ---- ground: shadow catcher
gp = bmesh.new(); bmesh.ops.create_grid(gp, x_segments=1, y_segments=1, size=10)
ground = obj("Ground", gp, stone); ground.is_shadow_catcher = True

root.rotation_euler = (0, 0, math.radians(P["yaw"]))
rig(sc, elev=P["elev"])                             # camera angle above the horizon
studio_world(sc, 0.6)
spot(sc, (-3, -4, 4), 150, (1, 0.95, 0.85)); spot(sc, (3, -3, 3), 80, (1, 1, 1))
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 4; sun.angle = math.radians(6)   # crisp ground shadow
so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(30), 0, math.radians(-40))   # high sun: short shadow that stays in frame from above
# only the sun darkens the ground: the soft fill lights and the world would add a faint, wide shadow over the
# whole catcher, which the square icon crop then cuts off into a visible edge
for l in bpy.data.lights:
    if l.type != 'SUN': l.use_shadow = False
vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
vis.diffuse = False
sc.cycles.diffuse_bounces = 0                     # bounce light off the throne onto the ground also reads as faint noisy shadow
sc.cycles.transmission_bounces = 12; sc.cycles.glossy_bounces = 8
render(sc, OUT, P["save_blend"], samples=128)
