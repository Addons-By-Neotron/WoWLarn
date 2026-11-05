"""Build + render one of the town's buildings (or the dungeon's bank branch) on the ground, with a shadow.  Usage:
blender -b -P build_building.py -- out.png '{"kind":"home", "elev":20, ...}'
kind: entrance (the way down into the dungeon), home, bank (the town's), bank2 (its branch in the dungeon: a vault
      door in the rock), dndstore (the Thrift Shoppe), school, tradepost, lrs (the Larn Revenue Service).
All face -y (the camera) and are turned by yaw so the front and the right-hand side show.
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, rock_material, studio_world, spot, wood_material

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "building.png"
P = dict(kind="home", yaw=-28, elev=20, seed=3, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
rnd = random.Random(P["seed"])

root = bpy.data.objects.new("Building", None); sc.collection.objects.link(root)

# ---- geometry helpers (bmesh; each returns a new bmesh unless given one to add to)
def obj(name, bm, material, smooth=False, bevel=0.0, subsurf=0):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = smooth
    o = link(sc, name, me); o.parent = root; o.data.materials.append(material)
    if bevel:
        m = o.modifiers.new("Bevel", 'BEVEL'); m.width = bevel; m.segments = 2; m.limit_method = 'ANGLE'
    if subsurf:
        m = o.modifiers.new("Sub", 'SUBSURF'); m.levels = m.render_levels = subsurf
    return o

def merge(bm, t):
    me = bpy.data.meshes.new("_"); t.to_mesh(me); t.free(); bm.from_mesh(me); bpy.data.meshes.remove(me)
    return bm

def box(x0, x1, y0, y1, z0, z1, bm=None, m=Matrix()):
    t = bmesh.new(); bmesh.ops.create_cube(t, size=1)
    t.transform(m @ Matrix.Translation(((x0 + x1)/2, (y0 + y1)/2, (z0 + z1)/2)) @ Matrix.Diagonal((x1 - x0, y1 - y0, z1 - z0, 1)))
    return merge(bm or bmesh.new(), t)

def quad_slab(p0, p1, p2, p3, t, bm=None):
    """A slab of thickness t under the quad p0..p3 (counter-clockwise seen from its top)."""
    bm = bm or bmesh.new(); q = [Vector(p) for p in (p0, p1, p2, p3)]
    n = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
    top = [bm.verts.new(p) for p in q]; bot = [bm.verts.new(p - n*t) for p in q]
    bm.faces.new(top); bm.faces.new(bot[::-1])
    for k in range(4):
        bm.faces.new((top[k], bot[k], bot[(k+1) % 4], top[(k+1) % 4]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

def prism(pts, y0, y1, bm=None):
    """A prism along y from y0 to y1 over the (x, z) polygon pts (a gable end, a pediment)."""
    bm = bm or bmesh.new()
    a = [bm.verts.new((x, y0, z)) for x, z in pts]; b = [bm.verts.new((x, y1, z)) for x, z in pts]
    bm.faces.new(a); bm.faces.new(b[::-1])
    for k in range(len(pts)):
        bm.faces.new((a[k], a[(k+1) % len(pts)], b[(k+1) % len(pts)], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

def lathe(prof, segs=24, m=Matrix(), bm=None):
    """Surface of revolution about z through (r, z) points; r = 0 closes an end; then transformed by m."""
    t = bmesh.new(); rings = []
    for r, z in prof:
        rings.append([t.verts.new((0, 0, z))] if r < 1e-4 else
                     [t.verts.new((r*math.cos(a), r*math.sin(a), z)) for a in (math.tau*k/segs for k in range(segs))])
    for A, B in zip(rings, rings[1:]):
        if len(A) == 1 and len(B) == 1: continue
        for k in range(segs):
            if len(A) == 1: t.faces.new((A[0], B[(k+1) % segs], B[k]))
            elif len(B) == 1: t.faces.new((A[k], A[(k+1) % segs], B[0]))
            else: t.faces.new((A[k], A[(k+1) % segs], B[(k+1) % segs], B[k]))
    bmesh.ops.recalc_face_normals(t, faces=t.faces); t.transform(m)
    return merge(bm or bmesh.new(), t)

def rock_lump(loc, size, squash=(1, 1, 0.7), bm=None, subdiv=2, jit=0.18):
    t = bmesh.new(); bmesh.ops.create_icosphere(t, subdivisions=subdiv, radius=1)
    ph = [rnd.uniform(0, math.tau) for _ in range(3)]
    for v in t.verts:
        d = v.co.normalized(); w = 1 + jit*(math.sin(3*d.x + ph[0]) + math.sin(4*d.y + ph[1]) + math.sin(5*d.z + ph[2]))/3
        v.co = Vector((v.co.x*size*squash[0], v.co.y*size*squash[1], v.co.z*size*squash[2]))*w*rnd.uniform(0.95, 1.05)
    t.transform(Matrix.Translation(loc))
    return merge(bm or bmesh.new(), t)

FRONT = Matrix()                                    # details on the front (-y) face
def side(W):                                       # ... and on the right-hand (+x) face: x -> -y turned to +x
    return Matrix.Translation((W/2, 0, 0)) @ Matrix.Rotation(math.pi/2, 4, 'Z') @ Matrix.Translation((0, 0, 0))

# ---- materials
def masonry(name, tint, scale=3.0, mortar=(0.12, 0.11, 0.1)):
    """Stone blocks in mortar on walls in the x-z and y-z planes (brick texture on (x + y, z)), each block a
    little lighter or darker, with a rock-like mottle and the mortar lines sunk in."""
    m, b = mat(name, tint, Roughness=0.85)
    nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord"); sp = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sp.inputs[0])
    ad = N("ShaderNodeMath"); Lk(sp.outputs["X"], ad.inputs[0]); Lk(sp.outputs["Y"], ad.inputs[1])
    cb = N("ShaderNodeCombineXYZ"); Lk(ad.outputs[0], cb.inputs["X"]); Lk(sp.outputs["Z"], cb.inputs["Y"])
    br = N("ShaderNodeTexBrick"); br.inputs["Scale"].default_value = scale; br.inputs["Mortar Size"].default_value = 0.025
    br.inputs["Brick Width"].default_value = 0.6; br.inputs["Row Height"].default_value = 0.3; br.offset = 0.5
    br.inputs["Color1"].default_value = (*[c*0.8 for c in tint], 1); br.inputs["Color2"].default_value = (*[c*1.15 for c in tint], 1)
    br.inputs["Mortar"].default_value = (*mortar, 1); Lk(cb.outputs[0], br.inputs["Vector"])
    nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 12; nz.inputs["Detail"].default_value = 6
    Lk(tc.outputs["Object"], nz.inputs["Vector"])
    mo = N("ShaderNodeMapRange"); mo.inputs["To Min"].default_value = 0.75; mo.inputs["To Max"].default_value = 1.15
    Lk(nz.outputs["Fac"], mo.inputs["Value"])
    mu = N("ShaderNodeMix"); mu.data_type = 'RGBA'; mu.blend_type = 'MULTIPLY'; mu.inputs["Factor"].default_value = 1.0
    Lk(br.outputs["Color"], mu.inputs["A"]); Lk(mo.outputs["Result"], mu.inputs["B"]); Lk(mu.outputs["Result"], b.inputs["Base Color"])
    bp = N("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.6; bp.inputs["Distance"].default_value = 0.02
    Lk(br.outputs["Fac"], bp.inputs["Height"]); Lk(bp.outputs["Normal"], b.inputs["Normal"])
    bp.invert = True
    return m

def mottle(name, base, amount=0.3, scale=6.0, rough=0.8, bump=0.2):
    """A plain surface with a soft noise in its colour and a fine bump (plaster, cloth, thatch, slate)."""
    m, b = mat(name, base, Roughness=rough)
    nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord"); nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = 8; Lk(tc.outputs["Object"], nz.inputs["Vector"])
    cr = N("ShaderNodeValToRGB"); Lk(nz.outputs["Fac"], cr.inputs[0]); el = cr.color_ramp.elements
    el[0].color = (*[c*(1 - amount) for c in base], 1); el[1].color = (*[min(1, c*(1 + amount)) for c in base], 1)
    Lk(cr.outputs["Color"], b.inputs["Base Color"])
    bp = N("ShaderNodeBump"); bp.inputs["Strength"].default_value = bump; Lk(nz.outputs["Fac"], bp.inputs["Height"])
    Lk(bp.outputs["Normal"], b.inputs["Normal"])
    return m

def straw(name):
    """Thatch: long streaks of straw running down the slope (noise squashed along x and y)."""
    m, b = mat(name, (0.55, 0.42, 0.2), Roughness=0.9)
    nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord"); mp = N("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (40, 4, 40)
    Lk(tc.outputs["Object"], mp.inputs["Vector"])
    nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 3; nz.inputs["Detail"].default_value = 6
    Lk(mp.outputs["Vector"], nz.inputs["Vector"])
    cr = N("ShaderNodeValToRGB"); Lk(nz.outputs["Fac"], cr.inputs[0]); el = cr.color_ramp.elements
    el[0].color = (0.1, 0.07, 0.03, 1); el[1].color = (0.4, 0.31, 0.15, 1)
    Lk(cr.outputs["Color"], b.inputs["Base Color"])
    bp = N("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.6; Lk(nz.outputs["Fac"], bp.inputs["Height"])
    Lk(bp.outputs["Normal"], b.inputs["Normal"])
    return m

STONE = masonry("Stone", (0.26, 0.25, 0.22))
DARKSTONE = masonry("DarkStone", (0.12, 0.12, 0.13), mortar=(0.05, 0.05, 0.05))
PALESTONE = masonry("PaleStone", (0.4, 0.37, 0.32), scale=2.2)
TRIM = mottle("Trim", (0.38, 0.35, 0.3), amount=0.15, scale=4)            # plain dressed stone: columns, sills
PLASTER = mottle("Plaster", (0.45, 0.39, 0.3), amount=0.12, scale=3, bump=0.1)
TIMBER = wood_material("Timber", (0.07, 0.04, 0.02), axis="Z")
TIMBERX = wood_material("TimberX", (0.07, 0.04, 0.02), axis="X")
PLANK = wood_material("Plank", (0.12, 0.07, 0.035), axis="Z")
SLATE = mottle("Slate", (0.05, 0.06, 0.075), amount=0.25, scale=8, rough=0.75)
TILE = mottle("Tile", (0.22, 0.06, 0.03), amount=0.25, scale=8, rough=0.8)
SHINGLE = mottle("Shingle", (0.16, 0.1, 0.06), amount=0.3, scale=8)
THATCH = straw("Thatch")
IRON = mat("Iron", (0.05, 0.05, 0.055), Metallic=0.8, Roughness=0.45)[0]
GOLD = mat("Gold", (1.0, 0.7, 0.28), Metallic=1.0, Roughness=0.25)[0]
BLACK = mat("Black", (0.0, 0.0, 0.0), Roughness=1.0)[0]
GLOW = mat("Window", (0.2, 0.1, 0.03), Roughness=0.2, **{"Emission Color": (1.0, 0.62, 0.25, 1), "Emission Strength": 2.5})[0]
FLAME = mat("Flame", (1.0, 0.5, 0.1), **{"Emission Color": (1.0, 0.45, 0.08, 1), "Emission Strength": 12.0})[0]

# ---- parts
def walls(W, D, H, material, bm=None):
    return obj("Walls", box(-W/2, W/2, -D/2, D/2, 0, H), material, bevel=0.01)

def gable_roof(W, D, H, R, material, ov=0.18, rows=7, thick=0.05, ends=None):
    """A pitched roof, ridge along x, from the eaves at height H up R; overhanging by ov; laid as rows of shingles
    (each row's lower edge kicked out a little so the courses show), or one thick slab if rows = 0.  ends: material
    of the gable triangles."""
    x0, x1 = -W/2 - ov, W/2 + ov
    for sgn in (-1, 1):
        ye, yr = sgn*(D/2 + ov), 0.0; ze, zr = H - ov*R/(D/2), H + R
        bm = bmesh.new()
        if rows:
            for i in range(rows):
                t0, t1 = i/rows, min(1.0, (i + 1)/rows + 0.04)
                p = lambda t, x: Vector((x, ye + (yr - ye)*t, ze + (zr - ze)*t))
                kick = Vector((0, sgn*0.025, -0.012))
                quad = [p(t0, x0) + kick, p(t0, x1) + kick, p(t1, x1), p(t1, x0)]
                quad_slab(*(quad if sgn < 0 else quad[::-1]), thick, bm=bm)
        else:
            quad = [Vector((x0, ye, ze)), Vector((x1, ye, ze)), Vector((x1, yr, zr)), Vector((x0, yr, zr))]
            quad_slab(*(quad if sgn < 0 else quad[::-1]), thick, bm=bm)
        obj("Roof", bm, material, bevel=0.01 if rows else 0.04, smooth=not rows)
    if ends:
        g = bmesh.new()
        for x in (-W/2, W/2 - 0.001):
            g = merge(g, prism([(-D/2, H), (D/2, H), (0, H + R)], 0, 0.001)) if False else g
        tri = bmesh.new()
        for xa, xb in ((-W/2, -W/2 + 0.02), (W/2 - 0.02, W/2)):
            a = [tri.verts.new((xx, y, z)) for xx in (xa, xb) for y, z in ((-D/2, H), (D/2, H), (0, H + R))]
            tri.faces.new((a[0], a[1], a[2])); tri.faces.new((a[5], a[4], a[3]))
            for k in range(3):
                tri.faces.new((a[k], a[3 + k], a[3 + (k+1) % 3], a[(k+1) % 3]))
        bmesh.ops.recalc_face_normals(tri, faces=tri.faces)
        obj("Gables", tri, ends)

def window(m, cx, cz, w=0.3, h=0.4, frame=TIMBER, arched=False, bars=False, shutters=None):
    """A glowing window on a face (m places the front-face coordinates): a frame proud of the wall, a cross of
    mullions (or iron bars), a sill; shutters: material of a pair of open shutters."""
    y = -0.0
    f = bmesh.new()
    for x0, x1, z0, z1 in ((cx - w/2 - 0.04, cx - w/2, cz - h/2, cz + h/2), (cx + w/2, cx + w/2 + 0.04, cz - h/2, cz + h/2),
                           (cx - w/2 - 0.04, cx + w/2 + 0.04, cz + h/2, cz + h/2 + 0.04)):
        box(x0, x1, y - 0.04, y + 0.01, z0, z1, bm=f, m=m)
    obj("WinFrame", f, frame, bevel=0.005)
    obj("Sill", box(cx - w/2 - 0.07, cx + w/2 + 0.07, y - 0.07, y + 0.01, cz - h/2 - 0.05, cz - h/2, m=m), TRIM, bevel=0.005)
    obj("Glass", box(cx - w/2, cx + w/2, y - 0.012, y + 0.01, cz - h/2, cz + h/2, m=m), GLOW)
    g = bmesh.new()
    if bars:
        for k in range(1, 4):
            box(cx - w/2 + w*k/4 - 0.01, cx - w/2 + w*k/4 + 0.01, y - 0.035, y - 0.015, cz - h/2, cz + h/2, bm=g, m=m)
        obj("Bars", g, IRON)
    else:
        box(cx - 0.012, cx + 0.012, y - 0.03, y - 0.01, cz - h/2, cz + h/2, bm=g, m=m)
        box(cx - w/2, cx + w/2, y - 0.03, y - 0.01, cz - 0.012, cz + 0.012, bm=g, m=m)
        obj("Mullions", g, frame)
    if shutters:
        s = bmesh.new()
        for sg in (-1, 1):
            box(cx + sg*(w/2 + 0.05), cx + sg*(w/2 + 0.05 + w/2), y - 0.03, y - 0.01, cz - h/2, cz + h/2, bm=s, m=m)
        obj("Shutters", s, shutters, bevel=0.005)

def door(m, cx, w=0.42, h=0.75, frame=TIMBER, arched=True, wood=PLANK):
    """A plank door with iron straps and a ring, in a frame; arched: a round top."""
    y = 0.0
    obj("DoorFrame", box(cx - w/2 - 0.06, cx + w/2 + 0.06, y - 0.05, y + 0.01, 0, h + 0.06, m=m), frame, bevel=0.01)
    obj("Door", box(cx - w/2, cx + w/2, y - 0.07, y - 0.04, 0, h, m=m), wood, bevel=0.004)
    st = bmesh.new()
    for z in (0.18, h - 0.2):
        box(cx - w/2, cx + w/2 - 0.04, y - 0.085, y - 0.065, z, z + 0.035, bm=st, m=m)
    lathe([(0, 0), (0.03, 0), (0.03, 0.012), (0, 0.012)], 12, m @ Matrix.Translation((cx + w/2 - 0.08, y - 0.08, 0.38)) @ Matrix.Rotation(math.pi/2, 4, 'X'), bm=st)
    obj("Straps", st, IRON)
    obj("Step", box(cx - w/2 - 0.1, cx + w/2 + 0.1, y - 0.22, y, 0, 0.06, m=m), TRIM, bevel=0.01)

def sign(m, cx, cz, emblem, board=PLANK, w=0.4, h=0.26):
    """A board hung from an iron bracket sticking out of the wall, with an emblem on its face (a function
    drawing it at (x, z) on the board's front)."""
    obj("Bracket", box(cx - 0.015, cx + 0.015, -0.5, 0.0, cz + h/2 + 0.07, cz + h/2 + 0.1, m=m), IRON)
    ch = bmesh.new()
    for yy in (-0.42, -0.12):
        box(cx - 0.006, cx + 0.006, yy - 0.006, yy + 0.006, cz + h/2, cz + h/2 + 0.07, bm=ch, m=m)
    obj("Chains", ch, IRON)
    mb = m @ Matrix.Translation((cx, -0.27, cz)) @ Matrix.Rotation(-math.pi/2, 4, 'Z')   # board side-on to the wall: its face looks along -x... turned to face the camera
    obj("Board", box(-w/2, w/2, -0.02, 0.02, -h/2, h/2, m=mb), board, bevel=0.01)
    emblem(mb @ Matrix.Translation((0, -0.025, 0)))

def chimney(x, y, z0, z1, material=STONE):
    obj("Chimney", box(x - 0.13, x + 0.13, y - 0.13, y + 0.13, z0, z1), material, bevel=0.01)
    obj("ChimneyCap", box(x - 0.16, x + 0.16, y - 0.16, y + 0.16, z1, z1 + 0.05), TRIM, bevel=0.01)

# ---- emblems (m: on the board's front, x across, z up, looking along -y)
def coin(m, r=0.09):
    lathe([(0, 0), (r, 0), (r, 0.02), (r*0.8, 0.028), (0, 0.028)], 32, m @ Matrix.Rotation(math.pi/2, 4, 'X'), bm=None)
    obj("Coin", lathe([(0, 0), (r, 0), (r, 0.02), (r*0.8, 0.028), (0, 0.028)], 32, m @ Matrix.Rotation(math.pi/2, 4, 'X')), GOLD, smooth=True)

def scales(m):
    g = bmesh.new()
    box(-0.008, 0.008, -0.02, 0.0, -0.1, 0.08, bm=g, m=m)                    # post
    box(-0.13, 0.13, -0.02, 0.0, 0.065, 0.08, bm=g, m=m)                     # beam
    for sx in (-1, 1):
        for k in (-1, 1):
            box(sx*0.12 + k*0.035 - 0.004, sx*0.12 + k*0.035 + 0.004, -0.02, 0.0, -0.02, 0.07, bm=g, m=m)
        lathe([(0, 0), (0.06, 0), (0.06, 0.012), (0, 0.012)], 16, m @ Matrix.Translation((sx*0.12, -0.02, -0.035)), bm=g)
    box(-0.05, 0.05, -0.02, 0.0, -0.11, -0.095, bm=g, m=m)                   # foot
    obj("Scales", g, GOLD)

def sack(m):
    g = bmesh.new(); t = bmesh.new(); bmesh.ops.create_uvsphere(t, u_segments=16, v_segments=10, radius=0.08)
    t.transform(m @ Matrix.Translation((0, -0.05, -0.02)) @ Matrix.Diagonal((1, 0.6, 1.05, 1))); merge(g, t)
    lathe([(0, 0.0), (0.035, 0.0), (0.02, 0.04), (0.04, 0.07), (0, 0.075)], 16, m @ Matrix.Translation((0, -0.05, 0.05)), bm=g)
    obj("Sack", g, GOLD, smooth=True)

def book(m):
    g = bmesh.new()
    for sx in (-1, 1):
        box(0, sx*0.13, -0.02, 0.0, -0.07, 0.07, bm=g, m=m @ Matrix.Rotation(sx*math.radians(18), 4, 'Z'))
    obj("Book", g, mat("Pages", (0.85, 0.8, 0.65), Roughness=0.7)[0])
    obj("Spine", box(-0.012, 0.012, -0.03, 0.0, -0.075, 0.075, m=m), mat("Cover", (0.35, 0.05, 0.04), Roughness=0.5)[0])

def crates_and_barrels(spots):
    for x, y, kind, s in spots:
        if kind == "crate":
            obj("Crate", box(x - s, x + s, y - s, y + s, 0, 2*s, m=Matrix.Rotation(rnd.uniform(-0.3, 0.3), 4, 'Z')), PLANK, bevel=0.01)
        else:
            obj("Barrel", lathe([(0, 0), (s*0.85, 0), (s, s*1.2), (s*0.85, s*2.4), (0, s*2.4)], 20, Matrix.Translation((x, y, 0))), TIMBER, smooth=True)
            hoops = bmesh.new()
            for z in (s*0.35, s*2.05):
                lathe([(s*0.92, z - 0.012), (s*0.93, z + 0.012)], 20, Matrix.Translation((x, y, 0)), bm=hoops)
            obj("Hoops", hoops, IRON, smooth=True)

def torch(x, y, z):
    obj("TorchPole", box(x - 0.02, x + 0.02, y - 0.02, y + 0.02, z - 0.25, z), IRON)
    obj("TorchCup", lathe([(0, 0), (0.04, 0), (0.06, 0.08), (0, 0.08)], 12, Matrix.Translation((x, y, z))), IRON)
    f = bmesh.new(); bmesh.ops.create_uvsphere(f, u_segments=12, v_segments=8, radius=0.05)
    f.transform(Matrix.Translation((x, y, z + 0.12)) @ Matrix.Diagonal((1, 1, 1.8, 1))); obj("Flame", f, FLAME, smooth=True)

# ---- the buildings: each returns its look-at height
def home():
    # a cottage: white plaster between dark timbers, a thick thatched roof, a stone chimney, glowing windows
    W, D, H = 1.7, 1.2, 0.95
    walls(W, D, H, PLASTER)
    tb = bmesh.new()                               # the timber frame on the front and the side
    for x in (-W/2, -0.25, 0.25, W/2 - 0.06):
        box(x, x + 0.06, -D/2 - 0.02, -D/2 + 0.02, 0, H, bm=tb)
    box(-W/2, W/2, -D/2 - 0.025, -D/2 + 0.02, H - 0.06, H, bm=tb); box(-W/2, W/2, -D/2 - 0.025, -D/2 + 0.02, 0, 0.06, bm=tb)
    for y in (-D/2, 0.0, D/2 - 0.06):
        box(W/2 - 0.02, W/2 + 0.02, y, y + 0.06, 0, H, bm=tb)
    box(W/2 - 0.025, W/2 + 0.025, -D/2, D/2, H - 0.06, H, bm=tb)
    obj("Timbers", tb, TIMBER, bevel=0.005)
    gable_roof(W, D, H, 0.75, THATCH, ov=0.2, rows=0, thick=0.16, ends=PLASTER)
    chimney(-0.5, 0.25, 1.1, 1.95)
    door(FRONT @ Matrix.Translation((0, -D/2, 0)), 0.0, w=0.36, h=0.68)
    for cx in (-0.58, 0.58):
        window(FRONT @ Matrix.Translation((0, -D/2 - 0.02, 0)), cx, 0.55, w=0.3, h=0.3, shutters=mottle("Shutter", (0.12, 0.25, 0.15), 0.2))
    window(side(W) @ Matrix.Translation((0, -0.02, 0)), 0.3, 0.55, w=0.3, h=0.3)
    fl = mottle("Flowers", (0.7, 0.15, 0.2), 0.4, 20)
    for cx in (-0.58, 0.58):
        obj("Flowers", box(cx - 0.17, cx + 0.17, -D/2 - 0.12, -D/2 - 0.04, 0.32, 0.36), fl, bevel=0.02, subsurf=1)
    return 0.8

def bank():
    # the First National Bank of Larn: pale stone, a portico of four columns under a pediment with a gold coin,
    # broad steps, a slate roof
    W, D, H = 2.0, 1.4, 1.25
    walls(W, D, H, PALESTONE)
    gable_roof(W, D, H + 0.08, 0.45, SLATE, ov=0.08, rows=6, ends=PALESTONE)
    obj("Cornice", box(-W/2 - 0.08, W/2 + 0.08, -D/2 - 0.08, D/2 + 0.08, H, H + 0.08), TRIM, bevel=0.01)
    for i, z in enumerate((0.0, 0.07, 0.14)):      # steps up to the portico
        e = 0.12*(3 - i)
        obj("Steps", box(-W/2 - 0.05 + e*0.3, W/2 + 0.05 - e*0.3, -D/2 - 0.55 - e*0.0 + 0.12*i, -D/2, z, z + 0.07), TRIM, bevel=0.008)
    zc = 0.21; yc = -D/2 - 0.32
    for x in (-0.75, -0.25, 0.25, 0.75):
        obj("Column", lathe([(0, zc), (0.11, zc), (0.11, zc + 0.05), (0.08, zc + 0.08), (0.07, H - 0.12), (0.1, H - 0.06), (0.1, H), (0, H)], 20,
                            Matrix.Translation((x, yc, 0))), TRIM, smooth=True)
    obj("Architrave", box(-W/2 + 0.05, W/2 - 0.05, yc - 0.13, -D/2, H, H + 0.1), TRIM, bevel=0.01)
    obj("Pediment", prism([(-W/2 + 0.05, H + 0.1), (W/2 - 0.05, H + 0.1), (0, H + 0.48)], yc - 0.13, -D/2 + 0.01), TRIM, bevel=0.01)
    coin(Matrix.Translation((0, yc - 0.14, H + 0.24)), r=0.1)
    door(FRONT @ Matrix.Translation((0, -D/2, 0.21)), 0.0, w=0.4, h=0.7, frame=TRIM, wood=wood_material("BankDoor", (0.09, 0.04, 0.02), axis="Z"))
    for cx in (-0.62, 0.62):
        window(FRONT @ Matrix.Translation((0, -D/2 - 0.02, 0)), cx, 0.78, w=0.26, h=0.45, frame=TRIM, bars=True)
    for cy in (-0.3, 0.3):
        window(side(W) @ Matrix.Translation((0, -0.02, 0)), cy, 0.7, w=0.26, h=0.45, frame=TRIM, bars=True)
    return 0.8

def bank2():
    # the bank's branch down in the dungeon: a round iron vault door with a gold coin, set in a dressed stone
    # face cut into a mound of rock
    rk = rock_material("Rock", (0.3, 0.28, 0.26), 0.8)[0]
    bm = bmesh.new()
    rock_lump(Vector((0, 0.35, 0.35)), 1.1, (1.1, 0.7, 0.85), bm=bm)
    for k in range(5):
        a = rnd.uniform(-math.pi, math.pi); rock_lump(Vector((0.95*math.cos(a), 0.35 + 0.6*math.sin(a), 0.1)), rnd.uniform(0.25, 0.45), bm=bm, subdiv=1)
    obj("Mound", bm, rk, smooth=True)
    obj("Face", box(-0.62, 0.62, -0.5, -0.1, 0, 1.15), DARKSTONE, bevel=0.02)
    obj("Lintel", box(-0.7, 0.7, -0.56, -0.1, 1.08, 1.24), TRIM, bevel=0.02)
    for x in (-0.66, 0.5):
        obj("Pillar", box(x, x + 0.16, -0.56, -0.1, 0, 1.08), TRIM, bevel=0.02)
    m = Matrix.Translation((0, -0.5, 0.55)) @ Matrix.Rotation(math.pi/2, 4, 'X')
    obj("VaultRim", lathe([(0.36, 0.0), (0.44, 0.0), (0.44, 0.07), (0.36, 0.07)], 40, m), IRON, smooth=True)
    obj("Vault", lathe([(0, 0.0), (0.36, 0.0), (0.36, 0.05), (0, 0.05)], 40, m), mat("Steel", (0.3, 0.3, 0.32), Metallic=0.9, Roughness=0.35)[0], smooth=True)
    sp = bmesh.new()
    for k in range(6):                             # the wheel's spokes
        a = math.tau*k/6
        box(-0.012, 0.012, -0.08, -0.05, 0.0, 0.2, bm=sp, m=Matrix.Translation((0, -0.5, 0.55)) @ Matrix.Rotation(a, 4, 'Y'))
    lathe([(0.19, 0.05), (0.22, 0.05), (0.22, 0.08), (0.19, 0.08)], 32, m, bm=sp)
    for k in range(12):                            # bolts round the rim
        a = math.tau*k/12
        box(-0.015, 0.015, -0.07, -0.05, -0.015, 0.015, bm=sp, m=Matrix.Translation((0.4*math.cos(a), -0.5, 0.55 + 0.4*math.sin(a))))
    obj("Wheel", sp, IRON)
    coin(Matrix.Translation((0, -0.585, 0.55)), r=0.08)
    torch(-0.85, -0.45, 0.85); torch(0.85, -0.45, 0.85)
    return 0.6

def dndstore():
    # the Thrift Shoppe: a two-storey timber-framed shop, a broad shop window under a striped awning, the upper
    # floor jutting out, a hanging sign with a gold sack, a tiled roof
    W, D, H1, H2 = 1.6, 1.2, 0.8, 0.75
    walls(W, D, H1, STONE)
    obj("Upper", box(-W/2 - 0.06, W/2 + 0.06, -D/2 - 0.1, D/2, H1, H1 + H2), PLASTER, bevel=0.01)
    tb = bmesh.new()
    for x in (-W/2 - 0.06, -0.3, 0.3, W/2):
        box(x, x + 0.06, -D/2 - 0.12, -D/2 - 0.08, H1, H1 + H2, bm=tb)
    box(-W/2 - 0.06, W/2 + 0.06, -D/2 - 0.13, -D/2 - 0.08, H1, H1 + 0.06, bm=tb)
    for x0, x1 in ((-W/2 - 0.06, -0.3), (0.3, W/2 + 0.06)):          # diagonal braces
        bmesh.ops.create_cube(t := bmesh.new(), size=1)
        L = math.hypot(x1 - x0, H2); a = math.atan2(H2, x1 - x0)
        t.transform(Matrix.Translation(((x0 + x1)/2, -D/2 - 0.1, H1 + H2/2)) @ Matrix.Rotation(-a if x0 < 0 else a, 4, 'Y') @ Matrix.Diagonal((L, 0.04, 0.05, 1)))
        merge(tb, t)
    obj("Timbers", tb, TIMBER, bevel=0.005)
    gable_roof(W + 0.12, D + 0.1, H1 + H2, 0.55, TILE, ov=0.12, rows=7, ends=PLASTER)
    chimney(0.45, 0.2, 1.7, 2.15)
    door(FRONT @ Matrix.Translation((0, -D/2, 0)), -0.5, w=0.34, h=0.66)
    window(FRONT @ Matrix.Translation((0, -D/2 - 0.02, 0)), 0.28, 0.42, w=0.7, h=0.4)        # the shop window
    stripes = bpy.data.materials.new("Awning"); stripes.use_nodes = True; nt = stripes.node_tree; b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord"); wv = nt.nodes.new("ShaderNodeTexWave"); wv.wave_type = 'BANDS'; wv.bands_direction = 'X'
    wv.inputs["Scale"].default_value = 6; nt.links.new(tc.outputs["Object"], wv.inputs["Vector"])
    cr = nt.nodes.new("ShaderNodeValToRGB"); cr.color_ramp.interpolation = 'CONSTANT'; cr.color_ramp.elements[1].position = 0.5
    cr.color_ramp.elements[0].color = (0.55, 0.05, 0.04, 1); cr.color_ramp.elements[1].color = (0.8, 0.72, 0.55, 1)
    nt.links.new(wv.outputs["Fac"], cr.inputs[0]); nt.links.new(cr.outputs["Color"], b.inputs["Base Color"]); b.inputs["Roughness"].default_value = 0.9
    obj("Awning", quad_slab((-0.18, -D/2 - 0.02, 0.78), (0.74, -D/2 - 0.02, 0.78), (0.74, -D/2 - 0.38, 0.6), (-0.18, -D/2 - 0.38, 0.6), 0.02), stripes)
    for cx in (-0.4, 0.4):
        window(FRONT @ Matrix.Translation((0, -D/2 - 0.12, 0)), cx, H1 + 0.4, w=0.26, h=0.3)
    window(side(W) @ Matrix.Translation((0, -0.02, 0)), 0.0, 0.42, w=0.3, h=0.32)
    sign(FRONT @ Matrix.Translation((0, -D/2 - 0.1, 0)), -W/2 - 0.02, 1.05, sack)
    return 0.9

def school():
    # the school: a long stone hall with a red tiled roof, tall arched windows, an open book over the door and a
    # bell turret on the ridge
    W, D, H = 2.1, 1.1, 1.0
    walls(W, D, H, STONE)
    gable_roof(W, D, H, 0.6, TILE, ov=0.12, rows=7, ends=STONE)
    door(FRONT @ Matrix.Translation((0, -D/2, 0)), 0.0, w=0.4, h=0.72)
    book(Matrix.Translation((0, -D/2 - 0.03, 0.86)))
    for cx in (-0.7, -0.38, 0.38, 0.7):
        window(FRONT @ Matrix.Translation((0, -D/2 - 0.02, 0)), cx, 0.55, w=0.18, h=0.5)
    window(side(W) @ Matrix.Translation((0, -0.02, 0)), 0.0, 0.55, w=0.26, h=0.5)
    zt = H + 0.6 - 0.05                            # the bell turret on the ridge
    obj("Turret", box(-0.2, 0.2, -0.2, 0.2, H + 0.3, zt + 0.12), PLASTER, bevel=0.01)
    po = bmesh.new()
    for x in (-0.2, 0.14):
        for y in (-0.2, 0.14):
            box(x, x + 0.06, y, y + 0.06, zt + 0.12, zt + 0.5, bm=po)
    obj("Posts", po, TIMBER)
    obj("Bell", lathe([(0, zt + 0.42), (0.04, zt + 0.42), (0.07, zt + 0.32), (0.11, zt + 0.2), (0, zt + 0.2)], 20), GOLD, smooth=True)
    obj("Spire", lathe([(0.0, zt + 0.5), (0.3, zt + 0.5), (0.0, zt + 0.95)], 4, Matrix.Rotation(math.pi/4, 4, 'Z')), SLATE)
    return 1.0

def tradepost():
    # the Trading Post: a plank-walled store with a porch roof on posts across its front, crates and barrels
    # stacked outside, a sign; a shingled roof
    W, D, H = 1.9, 1.2, 0.95
    walls(W, D, H, wood_material("Boards", (0.16, 0.09, 0.045), axis="X"))
    cl = bmesh.new()                               # the boards' seams
    for z in [0.12*k for k in range(1, 8)]:
        box(-W/2 - 0.005, W/2 + 0.005, -D/2 - 0.005, D/2 + 0.005, z, z + 0.012, bm=cl)
    obj("Seams", cl, TIMBER)
    gable_roof(W, D, H, 0.55, SHINGLE, ov=0.14, rows=7, ends=wood_material("Boards2", (0.16, 0.09, 0.045), axis="X"))
    obj("Porch", quad_slab((-W/2 - 0.05, -D/2, 0.88), (W/2 + 0.05, -D/2, 0.88), (W/2 + 0.05, -D/2 - 0.5, 0.75), (-W/2 - 0.05, -D/2 - 0.5, 0.75), 0.04), SHINGLE, bevel=0.01)
    po = bmesh.new()
    for x in (-W/2, -0.2, 0.2, W/2 - 0.06):
        box(x, x + 0.06, -D/2 - 0.47, -D/2 - 0.41, 0, 0.76, bm=po)
    obj("PorchPosts", po, TIMBER)
    obj("Deck", box(-W/2 - 0.05, W/2 + 0.05, -D/2 - 0.52, -D/2, 0, 0.05), PLANK)
    door(FRONT @ Matrix.Translation((0, -D/2, 0.05)), 0.0, w=0.4, h=0.66)
    for cx in (-0.6, 0.6):
        window(FRONT @ Matrix.Translation((0, -D/2 - 0.02, 0)), cx, 0.52, w=0.32, h=0.28)
    window(side(W) @ Matrix.Translation((0, -0.02, 0)), 0.1, 0.52, w=0.32, h=0.28)
    obj("SignBoard", box(-0.45, 0.45, -D/2 - 0.53, -D/2 - 0.49, 0.9, 1.05), PLANK, bevel=0.01)
    coin(Matrix.Translation((-0.32, -D/2 - 0.54, 0.975)), r=0.05); coin(Matrix.Translation((0.32, -D/2 - 0.54, 0.975)), r=0.05)
    crates_and_barrels([(-0.6, -D/2 - 0.3, "crate", 0.11), (-0.42, -D/2 - 0.28, "crate", 0.09), (-0.58, -D/2 - 0.3 + 0.0, "crate", 0.0),
                        (0.55, -D/2 - 0.32, "barrel", 0.1), (0.78, -D/2 - 0.75, "barrel", 0.11), (-1.0, -0.2, "crate", 0.12)])
    obj("TopCrate", box(-0.68, -0.5, -D/2 - 0.39, -D/2 - 0.21, 0.22, 0.4, m=Matrix.Rotation(0.15, 4, 'Z')), PLANK, bevel=0.01)
    return 0.8

def lrs():
    # the Larn Revenue Service: a grim, tall grey stone office, iron-barred windows, a heavy door between two
    # buttresses, gold scales over it, a steep slate roof
    W, D, H = 1.5, 1.2, 1.55
    walls(W, D, H, DARKSTONE)
    obj("Plinth", box(-W/2 - 0.05, W/2 + 0.05, -D/2 - 0.05, D/2 + 0.05, 0, 0.15), TRIM, bevel=0.01)
    obj("Cornice", box(-W/2 - 0.06, W/2 + 0.06, -D/2 - 0.06, D/2 + 0.06, H - 0.08, H), TRIM, bevel=0.01)
    gable_roof(W, D, H, 0.7, SLATE, ov=0.1, rows=8, ends=DARKSTONE)
    for x in (-0.36, 0.26):
        obj("Buttress", box(x, x + 0.1, -D/2 - 0.16, -D/2, 0, 1.0), TRIM, bevel=0.01)
    door(FRONT @ Matrix.Translation((0, -D/2, 0.0)), -0.05, w=0.4, h=0.78, frame=TRIM, wood=wood_material("TaxDoor", (0.05, 0.03, 0.02), axis="Z"))
    scales(Matrix.Translation((-0.05, -D/2 - 0.03, 1.07)))
    for cx in (-0.55, 0.45):
        window(FRONT @ Matrix.Translation((0, -D/2 - 0.02, 0)), cx, 0.55, w=0.18, h=0.36, frame=TRIM, bars=True)
    for cx in (-0.45, 0.35):
        window(FRONT @ Matrix.Translation((0, -D/2 - 0.02, 0)), cx, 1.25, w=0.2, h=0.3, frame=TRIM, bars=True)
    for cy in (-0.25, 0.25):
        window(side(W) @ Matrix.Translation((0, -0.02, 0)), cy, 0.6, w=0.2, h=0.36, frame=TRIM, bars=True)
        window(side(W) @ Matrix.Translation((0, -0.02, 0)), cy, 1.25, w=0.2, h=0.3, frame=TRIM, bars=True)
    return 1.0

def entrance():
    # the way down: a stone stair sinking into a dark pit, ringed by a paved kerb, under a stone arch with a torch
    # on each pillar
    rk = rock_material("Steps", (0.3, 0.28, 0.25), 0.8, fade=(-0.1, -0.7))[0]
    PW, PL = 0.7, 1.3                              # the pit's half width and its length (from the arch back)
    kb = bmesh.new()                               # the paved kerb round the pit
    for x0, x1, y0, y1 in ((-PW - 0.3, -PW, -0.1, PL + 0.3), (PW, PW + 0.3, -0.1, PL + 0.3), (-PW - 0.3, PW + 0.3, PL, PL + 0.3)):
        box(x0, x1, y0, y1, 0, 0.12, bm=kb)
    obj("Kerb", kb, STONE, bevel=0.015)
    st = bmesh.new()
    n = 9
    for k in range(n):                             # steps going down away from the arch
        y = 0.0 + k*PL/n; z = -0.12*(k + 1)
        box(-PW, PW, y, y + PL/n, -1.3, z, bm=st)
    for sx in (-1, 1):                             # the pit's side walls
        box(sx*PW - 0.02 if sx > 0 else -PW - 0.0, sx*PW + 0.0 if sx > 0 else -PW + 0.02, 0, PL, -1.3, 0.0, bm=st)
    box(-PW, PW, PL - 0.02, PL, -1.3, 0.0, bm=st)
    obj("Stair", st, rk, bevel=0.01)
    obj("Pit", box(-PW, PW, -0.0, PL, -1.4, -1.3), BLACK)
    for x in (-PW - 0.25, PW):                     # the arch: two pillars and a round top
        obj("Pillar", box(x, x + 0.25, -0.2, 0.05, 0, 1.25), STONE, bevel=0.015)
        obj("Cap", box(x - 0.03, x + 0.28, -0.23, 0.08, 1.25, 1.33), TRIM, bevel=0.01)
    R0, R1 = PW, PW + 0.25
    arc = bmesh.new()
    for k in range(10):                            # voussoirs
        a0, a1 = math.pi*k/10, math.pi*(k + 1)/10 - 0.02
        pts = [(R0*math.cos(a0), 1.33 + R0*math.sin(a0)), (R1*math.cos(a0), 1.33 + R1*math.sin(a0)),
               (R1*math.cos(a1), 1.33 + R1*math.sin(a1)), (R0*math.cos(a1), 1.33 + R0*math.sin(a1))]
        prism(pts, -0.2, 0.05, bm=arc)
    obj("Arch", arc, TRIM, bevel=0.008)
    obj("Keystone", prism([(-0.1, 1.33 + R0 - 0.02), (0.1, 1.33 + R0 - 0.02), (0.13, 1.33 + R1 + 0.08), (-0.13, 1.33 + R1 + 0.08)], -0.23, 0.08), STONE, bevel=0.01)
    torch(-PW - 0.125, -0.28, 0.95); torch(PW + 0.125, -0.28, 0.95)
    return 0.6

look = globals()[P["kind"]]()

ground = bmesh.new()
if P["kind"] == "entrance":                         # the ground has a hole where the pit is
    bmesh.ops.create_grid(ground, x_segments=1, y_segments=1, size=10)
    gm = bpy.data.meshes.new("Ground"); ground.to_mesh(gm); ground.free()
    g = link(sc, "Ground", gm); g.is_shadow_catcher = True
    bo = g.modifiers.new("Hole", 'BOOLEAN'); bo.operation = 'DIFFERENCE'
    cut = link(sc, "Cut", bpy.data.meshes.new("Cut")); bc = box(-0.7, 0.7, 0.0, 1.3, -0.5, 0.5); bc.to_mesh(cut.data); bc.free()
    cut.parent = root; cut.hide_render = True; bo.object = cut
else:
    bmesh.ops.create_grid(ground, x_segments=1, y_segments=1, size=10)
    gm = bpy.data.meshes.new("Ground"); ground.to_mesh(gm); ground.free()
    link(sc, "Ground", gm).is_shadow_catcher = True

root.rotation_euler = (0, 0, math.radians(P["yaw"]))
tgt = Vector((0, 0, look))
rig(sc, tgt=tgt, elev=P["elev"])
sc.camera.data.lens = 55
studio_world(sc, 0.3)
spot(sc, (-3, -4, 4), 120, (1, 0.95, 0.85), tgt=tgt); spot(sc, (3, -3, 3), 60, (1, 1, 1), tgt=tgt)
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 3.2; sun.angle = math.radians(6)
so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(32), 0, math.radians(-40))
for l in bpy.data.lights:                          # only the sun darkens the ground (see build_throne.py)
    if l.type != 'SUN': l.use_shadow = False
vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
vis.diffuse = False
render(sc, OUT, P["save_blend"], samples=128)
