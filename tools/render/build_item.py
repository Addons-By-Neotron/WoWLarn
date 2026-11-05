"""Build + render one of the carried trinkets / containers.  Usage:
blender -b -P build_item.py -- out.png '{"kind":"chest", ...}'
kind: chest, amulet, dragon_orb, enlightenment, scarab, cube, cookie, lock, lamp, hand, talisman, wand, annihilation
yaw / tilt: turn the item (degrees) on top of its own pose.
ground: stand it on a shadow catcher with a sun (the world objects: chest, lamp), seen from elev degrees.
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, studio_world, spot, wood_material

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "item.png"
P = dict(kind="chest", yaw=0, tilt=0, ground=False, elev=20, seed=1, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
rnd = random.Random(P["seed"])

root = bpy.data.objects.new("Item", None); sc.collection.objects.link(root)

# ---- geometry helpers (bmesh; each returns a new bmesh unless given one to add to)
def obj(name, bm, material, smooth=True, bevel=0.0, subsurf=0, parent=None):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = smooth
    o = link(sc, name, me); o.parent = parent or root; o.data.materials.append(material)
    if bevel:
        m = o.modifiers.new("Bevel", 'BEVEL'); m.width = bevel; m.segments = 2; m.limit_method = 'ANGLE'
    if subsurf:
        m = o.modifiers.new("Sub", 'SUBSURF'); m.levels = m.render_levels = subsurf
    return o

def box(x0, x1, y0, y1, z0, z1, bm=None):
    bm = bm or bmesh.new(); t = bmesh.new(); bmesh.ops.create_cube(t, size=1)
    t.transform(Matrix.Translation(((x0 + x1)/2, (y0 + y1)/2, (z0 + z1)/2)) @ Matrix.Diagonal((x1 - x0, y1 - y0, z1 - z0, 1)))
    return merge(bm, t)

def merge(bm, t):
    """Add bmesh t into bm (t is freed)."""
    me = bpy.data.meshes.new("_"); t.to_mesh(me); t.free(); bm.from_mesh(me); bpy.data.meshes.remove(me)
    return bm

def sphere(r, loc=(0, 0, 0), scale=(1, 1, 1), bm=None, segs=32):
    t = bmesh.new(); bmesh.ops.create_uvsphere(t, u_segments=segs, v_segments=segs//2, radius=r)
    t.transform(Matrix.Translation(loc) @ Matrix.Diagonal((*scale, 1)))
    return merge(bm or bmesh.new(), t)

def ico(r, loc, subdiv=1, bm=None):
    t = bmesh.new(); bmesh.ops.create_icosphere(t, subdivisions=subdiv, radius=r)
    t.transform(Matrix.Translation(loc))
    return merge(bm or bmesh.new(), t)

def torus(R, r, M=Matrix(), bm=None, segs=40, tseg=10):
    """Ring of radius R round the local z axis, tube radius r, placed by matrix M."""
    bm = bm or bmesh.new()
    vs = [[bm.verts.new(M @ Vector(((R + r*math.cos(v))*math.cos(u), (R + r*math.cos(v))*math.sin(u), r*math.sin(v))))
           for v in (math.tau*j/tseg for j in range(tseg))] for u in (math.tau*i/segs for i in range(segs))]
    for i in range(segs):
        for j in range(tseg):
            bm.faces.new((vs[i][j], vs[(i+1) % segs][j], vs[(i+1) % segs][(j+1) % tseg], vs[i][(j+1) % tseg]))
    return bm

def lathe(prof, segs=48, bm=None):
    """Surface of revolution round z through (r, z) points, bottom to top; r = 0 closes an end."""
    bm = bm or bmesh.new(); rings = []
    for r, z in prof:
        rings.append([bm.verts.new((0, 0, z))] if r < 1e-4 else
                     [bm.verts.new((r*math.cos(a), r*math.sin(a), z)) for a in (math.tau*k/segs for k in range(segs))])
    for A, B in zip(rings, rings[1:]):
        if len(A) == 1 and len(B) == 1: continue
        for k in range(segs):
            if len(A) == 1: bm.faces.new((A[0], B[(k+1) % segs], B[k]))
            elif len(B) == 1: bm.faces.new((A[k], A[(k+1) % segs], B[0]))
            else: bm.faces.new((A[k], A[(k+1) % segs], B[(k+1) % segs], B[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

def spline(pts, n=8):
    """Catmull-Rom through the control points, n steps per span."""
    pts = [Vector(p) for p in pts]; ext = [2*pts[0] - pts[1]] + pts + [2*pts[-1] - pts[-2]]; out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i-1:i+3]
        for k in range(n):
            t = k/n
            out.append(0.5*((2*p1) + (-p0 + p2)*t + (2*p0 - 5*p1 + 4*p2 - p3)*t*t + (-p0 + 3*p1 - 3*p2 + p3)*t**3))
    out.append(pts[-1]); return out

def tube(path, r, segs=14, bm=None):
    """Round tube along a list of points; r is one radius or one per point (tapers)."""
    path = [Vector(p) for p in path]; rs = list(r) if isinstance(r, (list, tuple)) else [r]*len(path)
    if len(rs) != len(path):                       # radii given per control point: spread along the path
        rs = [rs[0] + (rs[-1] - rs[0])*i/(len(path) - 1) for i in range(len(path))] if len(rs) == 2 else \
             [rs[min(len(rs) - 1, int(i*(len(rs) - 1)/(len(path) - 1) + 0.5))] for i in range(len(path))]
    bm = bm or bmesh.new(); rings = []; u = None
    for i, p in enumerate(path):
        t = (path[min(i+1, len(path)-1)] - path[max(i-1, 0)]).normalized()
        u = t.orthogonal().normalized() if u is None else (u - t*u.dot(t)).normalized()   # parallel transport
        v = t.cross(u)
        rings.append([bm.verts.new(p + rs[i]*(math.cos(a)*u + math.sin(a)*v)) for a in (math.tau*k/segs for k in range(segs))])
    for A, B in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((A[k], A[(k+1) % segs], B[(k+1) % segs], B[k]))
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

def cone(r, length, base, direction, bm=None):
    """A pointed cone (claw, talon) from base along direction."""
    d = Vector(direction).normalized(); t = bmesh.new()
    bmesh.ops.create_cone(t, cap_ends=True, segments=12, radius1=r, radius2=0.0, depth=length)
    t.transform(Matrix.Translation(Vector(base) + d*length/2) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4())
    return merge(bm or bmesh.new(), t)

# ---- materials
def glow_mat(name, stops, strength, base=(0.02, 0.02, 0.02), scale=2.5, distortion=4.0, rough=0.08):
    """Glossy surface with a swirling glow inside: noise (distorted) through a colour ramp into emission."""
    m, b = mat(name, base, Roughness=rough, **{"Coat Weight": 1.0})
    nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord"); nz = N("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = scale; nz.inputs["Distortion"].default_value = distortion; nz.inputs["Detail"].default_value = 4
    Lk(tc.outputs["Object"], nz.inputs["Vector"])
    cr = N("ShaderNodeValToRGB"); Lk(nz.outputs["Fac"], cr.inputs[0]); el = cr.color_ramp.elements
    while len(el) < len(stops): el.new(0.5)
    for e, (pos, col) in zip(el, stops): e.position, e.color = pos, (*col, 1)
    Lk(cr.outputs["Color"], b.inputs["Emission Color"]); b.inputs["Emission Strength"].default_value = strength
    return m

def mottled(name, dark, light, rough=0.6, scale=6.0, bump=0.3, bump_scale=30.0):
    """Two-tone noise colour with a fine bump: baked dough, withered skin, worn stone."""
    m, b = mat(name, light, Roughness=rough)
    nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord"); nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = scale
    nz.inputs["Detail"].default_value = 8; Lk(tc.outputs["Object"], nz.inputs["Vector"])
    cr = N("ShaderNodeValToRGB"); Lk(nz.outputs["Fac"], cr.inputs[0]); el = cr.color_ramp.elements
    el[0].position, el[0].color = 0.35, (*dark, 1); el[1].position, el[1].color = 0.7, (*light, 1)
    Lk(cr.outputs["Color"], b.inputs["Base Color"])
    fb = N("ShaderNodeTexNoise"); fb.inputs["Scale"].default_value = bump_scale; fb.inputs["Detail"].default_value = 10
    Lk(tc.outputs["Object"], fb.inputs["Vector"])
    bp = N("ShaderNodeBump"); bp.inputs["Strength"].default_value = bump; bp.inputs["Distance"].default_value = 0.02
    Lk(fb.outputs["Fac"], bp.inputs["Height"]); Lk(bp.outputs["Normal"], b.inputs["Normal"])
    return m

GOLD = mat("Gold", (1.0, 0.7, 0.28), Metallic=1.0, Roughness=0.22)[0]
IRON = mat("Iron", (0.05, 0.05, 0.055), Metallic=0.8, Roughness=0.45)[0]
BLACK = mat("Black", (0.0, 0.0, 0.0), Roughness=1.0)[0]

# ---- the items: each builds round the origin (about 2 units across) and returns its look-at height offset
def chest():
    wood = wood_material("Wood", (0.06, 0.032, 0.016), axis="X", roughness=0.85)
    wood.node_tree.nodes["Principled BSDF"].inputs["Specular IOR Level"].default_value = 0.2
    W, D, Hb, R, SZ = 1.1, 0.65, 0.85, 0.65, 0.6
    def half_cyl(x0, x1, r, sz, n=20):
        bm = bmesh.new()
        ends = [[bm.verts.new((x, r*math.cos(math.pi*k/n), Hb + sz*r*math.sin(math.pi*k/n))) for k in range(n + 1)] for x in (x0, x1)]
        for k in range(n):
            bm.faces.new((ends[0][k], ends[1][k], ends[1][k+1], ends[0][k+1]))
        bm.faces.new((ends[0][0], ends[0][-1], ends[1][-1], ends[1][0]))      # the flat underside
        bm.faces.new(ends[0][::-1]); bm.faces.new(ends[1])
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        return bm
    obj("Body", box(-W, W, -D, D, 0, Hb), wood, smooth=False, bevel=0.02)
    obj("Lid", half_cyl(-W, W, R, SZ), wood, smooth=True)
    trim = bmesh.new()
    for x in (-0.72, 0.72):                        # iron bands round the body and over the lid
        box(x - 0.07, x + 0.07, -D - 0.025, D + 0.025, -0.01, Hb, bm=trim)
        merge(trim, half_cyl(x - 0.07, x + 0.07, R + 0.025, (SZ*R + 0.025)/(R + 0.025)))
    for x in (-W - 0.02, W - 0.05):                # and round its ends
        box(x, x + 0.07, -D - 0.025, D + 0.025, -0.01, Hb, bm=trim)
    box(-W - 0.025, W + 0.025, -D - 0.025, D + 0.025, -0.01, 0.07, bm=trim)   # foot rim
    box(-W - 0.025, W + 0.025, -D - 0.025, D + 0.025, Hb - 0.07, Hb, bm=trim)  # top rim
    obj("Bands", trim, IRON, smooth=False, bevel=0.01)
    studs = bmesh.new()
    for x in (-0.72, 0.72):
        for z in (0.17, 0.42, 0.67):
            sphere(0.028, (x, -D - 0.035, z), (1, 0.6, 1), bm=studs, segs=12)
    obj("Studs", studs, IRON)
    lock = box(-0.18, 0.18, -D - 0.05, -D - 0.01, Hb - 0.4, Hb - 0.02)
    box(-0.07, 0.07, -D - 0.07, -D - 0.03, Hb - 0.12, Hb + 0.25, bm=lock)   # the hasp down from the lid
    obj("Lock", lock, mat("Brass", (0.75, 0.5, 0.2), Metallic=1.0, Roughness=0.3)[0], smooth=False, bevel=0.01)
    obj("Keyhole", box(-0.025, 0.025, -D - 0.055, -D - 0.045, Hb - 0.32, Hb - 0.2), BLACK, smooth=False)
    root.rotation_euler = (0, 0, math.radians(-14))
    return Vector((0, 0, -0.65))

def amulet():
    gem = mat("Gem", (0.02, 0.1, 0.75), Roughness=0.04, **{"Coat Weight": 1.0, "Emission Color": (0.05, 0.2, 1.0, 1),
                                                           "Emission Strength": 0.5})[0]
    F = Matrix.Rotation(math.pi/2, 4, 'X')        # the pendant faces the camera (-y)
    pend = bmesh.new()
    t = bmesh.new(); bmesh.ops.create_cone(t, cap_ends=True, segments=48, radius1=0.5, radius2=0.5, depth=0.1); t.transform(F); merge(pend, t)
    torus(0.5, 0.05, F, bm=pend, segs=48); torus(0.35, 0.028, Matrix.Translation((0, -0.05, 0)) @ F, bm=pend, segs=40)
    for k in range(12):
        a = math.tau*k/12; sphere(0.035, (0.43*math.cos(a), -0.055, 0.43*math.sin(a)), bm=pend, segs=10)
    torus(0.09, 0.03, Matrix.Translation((0, 0, 0.6)) @ Matrix.Rotation(math.pi/2, 4, 'Y'), bm=pend, segs=20, tseg=8)
    obj("Pendant", pend, GOLD)
    obj("Stone", sphere(0.27, (0, -0.06, 0), (1, 0.45, 1)), gem)
    chain = bmesh.new(); N_, rx, rz = 46, 0.72, 0.68; zc = 0.69 + rz
    pts = [Vector((rx*math.sin(t), 0.32*(1 - math.cos(t)), zc - rz*math.cos(t))) for t in (math.tau*i/N_ for i in range(N_))]
    for i, p in enumerate(pts):
        tg = (pts[(i+1) % N_] - pts[i-1]).normalized()
        q = tg.to_track_quat('X', 'Z').to_matrix().to_4x4() @ Matrix.Rotation(math.pi/2*(i % 2), 4, 'X')
        torus(0.045, 0.013, Matrix.Translation(p) @ q @ Matrix.Diagonal((1.7, 1, 1, 1)), bm=chain, segs=16, tseg=6)
    obj("Chain", chain, GOLD)
    root.rotation_euler = (0, 0, math.radians(-12))
    return Vector((0, 0, -0.55))

def dragon_orb():
    orb = glow_mat("Orb", [(0.3, (0.12, 0.0, 0.0)), (0.55, (1.0, 0.22, 0.02)), (0.75, (1.0, 0.75, 0.25))], 4.0,
                   base=(0.25, 0.02, 0.0))
    obj("Orb", sphere(0.65, (0, 0, 0.3), segs=48), orb)
    dark_gold = mat("OldGold", (0.75, 0.48, 0.16), Metallic=1.0, Roughness=0.3)[0]
    obj("Stand", lathe([(0, -0.78), (0.45, -0.78), (0.46, -0.72), (0.34, -0.64), (0.2, -0.5), (0.24, -0.4), (0, -0.4)]), dark_gold)
    claws = bmesh.new()
    for k in range(4):                             # four dragon claws grip the orb from below
        a = math.tau*k/4 + math.pi/4; c, s = math.cos(a), math.sin(a)
        ctrl = [(0.18, -0.42), (0.45, -0.3), (0.7, 0.12), (0.62, 0.55)]
        path = spline([(r*c, r*s, z) for r, z in ctrl], 8)
        tube(path, [0.075 - 0.05*i/(len(path) - 1) for i in range(len(path))], bm=claws)
        cone(0.026, 0.14, path[-1], path[-1] - path[-3], bm=claws)
    obj("Claws", claws, dark_gold)
    root.rotation_euler = (0, 0, math.radians(20))
    return Vector((0, 0, 0))

def enlightenment():
    # the Orb of Enlightenment: a clear crystal ball with a soft golden light at its heart, held in a silver lotus
    # frosted, with little reflection: a clear glossy ball mirrors studio_world's bands as hard stripes
    glass = mat("Crystal", (0.95, 0.9, 0.8), Roughness=0.3, IOR=1.15, **{"Transmission Weight": 1.0,
                 "Specular IOR Level": 0.15, "Emission Color": (1.0, 0.82, 0.5, 1), "Emission Strength": 0.15})[0]   # lit from within
    obj("Orb", sphere(0.62, (0, 0, 0.32), segs=48), glass)
    light = glow_mat("Light", [(0.35, (0.9, 0.45, 0.08)), (0.6, (1.0, 0.75, 0.3)), (0.8, (1.0, 0.92, 0.65))], 2.2,
                     base=(0.3, 0.15, 0.02), scale=4.0, distortion=2.0)
    obj("Heart", sphere(0.24, (0, 0, 0.32), segs=32), light)
    silver = mat("Silver", (0.9, 0.92, 0.95), Metallic=1.0, Roughness=0.25)[0]
    obj("Base", lathe([(0, -0.62), (0.4, -0.62), (0.42, -0.56), (0.3, -0.5), (0.16, -0.42), (0.18, -0.3), (0, -0.3)]), silver)
    petals = bmesh.new()
    for k in range(8):                             # lotus petals: flattened, pointed leaves leaning out round the ball
        a = math.tau*k/8 + math.pi/8; t = bmesh.new()
        rd, tg = Vector((math.cos(a), math.sin(a), 0)), Vector((-math.sin(a), math.cos(a), 0))
        ax = (rd*math.sin(math.radians(42)) + Vector((0, 0, math.cos(math.radians(42))))).normalized()   # leaning out
        bmesh.ops.create_uvsphere(t, u_segments=16, v_segments=10, radius=1.0)
        for v in t.verts:                          # a leaf: thin, widest low down, pointed at the top, cupped
            u = (v.co.z + 1)/2; w = math.sin(math.pi*min(1.0, u*1.15))*0.17
            v.co = Vector((0.22*rd.x, 0.22*rd.y, -0.36)) + ax*(u*0.62) + tg*(v.co.x*w) + rd*(v.co.y*0.03 - 0.05*abs(v.co.x)*u)
        merge(petals, t)
    obj("Petals", petals, silver)
    root.rotation_euler = (0, 0, math.radians(15))
    return Vector((0, 0, 0))

def scarab():
    shell = mat("Shell", (0.02, 0.32, 0.38), Roughness=0.12, **{"Coat Weight": 1.0, "Emission Color": (0.1, 0.9, 1.0, 1),
                                                                "Emission Strength": 0.15})[0]
    piv = bpy.data.objects.new("Pivot", None); sc.collection.objects.link(piv); piv.parent = root
    obj("Elytra", sphere(0.55, (0, -0.1, 0), (1, 1.4, 0.55), segs=40), shell, parent=piv)
    obj("Thorax", sphere(0.46, (0, 0.68, 0.0), (1, 0.68, 0.5)), shell, parent=piv)
    obj("Head", sphere(0.28, (0, 1.0, -0.02), (1, 0.7, 0.45)), shell, parent=piv)
    trim = box(-0.014, 0.014, -0.86, 0.5, 0.16, 0.315)           # the seam between the wing cases
    torus(0.46, 0.018, Matrix.Translation((0, 0.68, 0.0)) @ Matrix.Diagonal((1, 0.68, 1, 1)), bm=trim, segs=40, tseg=6)
    for s in (-1, 1):
        for y0, dy in ((0.62, 0.3), (0.2, 0.0), (-0.25, -0.3)):   # six legs
            tube(spline([(s*0.36, y0, -0.12), (s*0.78, y0 + dy*0.6, -0.08), (s*1.02, y0 + dy*1.5, -0.32)], 6), [0.045, 0.022], bm=trim)
        tube(spline([(s*0.12, 1.15, 0.0), (s*0.3, 1.35, 0.05), (s*0.42, 1.42, 0.0)], 5), [0.03, 0.012], bm=trim)   # feelers
    obj("Trim", trim, GOLD, parent=piv)
    piv.rotation_euler = (math.radians(62), 0, 0)  # head up, the back towards the camera
    root.rotation_euler = (0, 0, math.radians(-18))
    return Vector((0, 0, 0))

def cube():
    stone = mat("Obsidian", (0.025, 0.03, 0.035), Roughness=0.22, **{"Coat Weight": 0.6})[0]
    rune, _ = mat("Rune", (0.1, 1.0, 0.3), **{"Emission Color": (0.15, 1.0, 0.35, 1), "Emission Strength": 4.0})
    piv = bpy.data.objects.new("Pivot", None); sc.collection.objects.link(piv); piv.parent = root
    obj("Cube", box(-0.6, 0.6, -0.6, 0.6, -0.6, 0.6), stone, smooth=False, bevel=0.06, parent=piv)
    runes = bmesh.new(); bone = bmesh.new()
    faces = [Matrix(), Matrix.Rotation(math.pi, 4, 'X'), Matrix.Rotation(math.pi/2, 4, 'X'), Matrix.Rotation(-math.pi/2, 4, 'X'),
             Matrix.Rotation(math.pi/2, 4, 'Y'), Matrix.Rotation(-math.pi/2, 4, 'Y')]
    for M in faces:                                # on each face: a glowing frame, a ring and a cross of lines
        t = bmesh.new(); w, z0, z1 = 0.022, 0.595, 0.61
        for a, b in ((-0.42, -0.42 + 2*w), (0.42 - 2*w, 0.42)):
            box(a, b, -0.42, 0.42, z0, z1, bm=t); box(-0.42, 0.42, a, b, z0, z1, bm=t)
        torus(0.17, 0.02, Matrix.Translation((0, 0, 0.6)), bm=t, segs=32, tseg=6)
        for k in range(4):
            r = Matrix.Rotation(math.pi/2*k, 4, 'Z')
            tt = box(-w, w, 0.19, 0.4, z0, z1); tt.transform(r); merge(t, tt)
        t.transform(M); merge(runes, t)
        sk = bmesh.new()                           # bone studs at the corners of the frame
        for x, y in ((-0.42, -0.42), (-0.42, 0.42), (0.42, -0.42), (0.42, 0.42)):
            sphere(0.05, (x, y, 0.6), (1, 1, 0.6), bm=sk, segs=12)
        sk.transform(M); merge(bone, sk)
    obj("Runes", runes, rune, smooth=False, parent=piv)
    obj("Bone", bone, mat("Bone", (0.7, 0.65, 0.52), Roughness=0.5)[0], parent=piv)
    piv.rotation_euler = (math.radians(30), 0, math.radians(40))
    return Vector((0, 0, 0))

def cookie():
    # smooth baked wafer: a faint broad tone change, a few small darker blemishes, fine pores in the bump
    dough = mottled("Cookie", (0.68, 0.42, 0.15), (0.83, 0.57, 0.25), rough=0.5, scale=2.5, bump=0.12, bump_scale=70)
    nt = dough.node_tree; N = nt.nodes.new; Lk = nt.links.new
    bsdf = nt.nodes["Principled BSDF"]; ramp = bsdf.inputs["Base Color"].links[0].from_node
    tc = N("ShaderNodeTexCoord"); spots = N("ShaderNodeTexNoise"); spots.inputs["Scale"].default_value = 18
    spots.inputs["Detail"].default_value = 2; Lk(tc.outputs["Object"], spots.inputs["Vector"])
    sr = N("ShaderNodeValToRGB"); Lk(spots.outputs["Fac"], sr.inputs[0]); el = sr.color_ramp.elements
    el[0].position, el[0].color = 0.62, (0, 0, 0, 1); el[1].position, el[1].color = 0.72, (0.6, 0.6, 0.6, 1)
    bl = N("ShaderNodeMix"); bl.data_type = 'RGBA'; bl.inputs["B"].default_value = (0.55, 0.3, 0.09, 1)
    Lk(sr.outputs["Color"], bl.inputs["Factor"]); Lk(ramp.outputs["Color"], bl.inputs["A"])
    at = N("ShaderNodeAttribute"); at.attribute_name = "Edge"   # the baked rims and fold go browner
    mix = N("ShaderNodeMix"); mix.data_type = 'RGBA'; mix.inputs["B"].default_value = (0.34, 0.15, 0.035, 1)
    Lk(at.outputs["Fac"], mix.inputs["Factor"]); Lk(bl.outputs["Result"], mix.inputs["A"])
    Lk(mix.outputs["Result"], bsdf.inputs["Base Color"])
    # a thin wafer disk folded in half over the x axis (the fold at the bottom, the rims on top), seen face on:
    # the fold is creased sharply at its middle (A, W) so each half swings down rigidly, its fold edge a straight
    # line from the notch to the tip, flaring out a little (A2) past its midpoint; D rounds the notch, the halves
    # part round it (BN), the pinched middle bulges toward the camera (PO), the back rim stands proud (RIM)
    C = dict(B=0.2, BN=0.2, D=0.0, A=82, W=0.08, A2=-15, W2=0.3, PO=0.35, RIM=0.06, TT=0.3, TP=12); C.update(P.get("cookie", {}))
    R = 1.0; B, BN, D, RIM = C["B"], C["BN"], C["D"], C["RIM"]
    def fold(x, y):
        t = abs(y)/R; s = -1 if y < 0 else 1       # s = -1: the front half
        g = max(0.0, 1 - abs(x)/R)*(1 - t)         # the middle of the fold pushed in: straight from the notch to the tips
        yy = s*(B*math.sin(math.pi*t) + BN*math.exp(-(x/0.3)**2)*(1 - t)**1.5*min(1, 8*t)) \
             - C["PO"]*math.exp(-(x/0.35)**2)*(1 - t)**0.7
        z = t*(1 + RIM*t**3*(s > 0)) + D*g
        return x, yy, z
    A, A2, W = math.radians(C["A"]), math.radians(C["A2"]), C["W"]; n = 400; ds = R/n
    th = lambda s: A*math.tanh(s/W)/math.tanh(R/W) + A2*0.5*(1 + math.tanh((s - 0.5*R)/C["W2"]))
    cs = [Vector((0, 0))]
    for i in range(n):
        s = (i + 0.5)*ds; cs.append(cs[-1] + ds*Vector((math.cos(th(s)), -math.sin(th(s)))))
    def bend(x, y, z):                             # crease the fold line at its middle: the ends droop
        c = cs[min(n, int(abs(x)/ds + 0.5))]; t = th(abs(x)); p = c + z*Vector((math.sin(t), math.cos(t)))
        return Vector((math.copysign(p.x, x), y, p.y))
    bm = bmesh.new(); S, RN = 256, 32; edge = []; lay = bm.verts.layers.float.new("Edge")
    rings = [[bm.verts.new(bend(*fold(0, 0)))]]; edge.append([0.0])
    for k in range(1, RN + 1):
        r = R*k/RN                                 # the disk narrowed toward the ends of the fold: thinner tips
        pts = [(r*math.cos(a), r*math.sin(a)*(1 - C["TT"]*abs(math.cos(a))**C["TP"])) for a in (math.tau*j/S for j in range(S))]
        rings.append([bm.verts.new(bend(*fold(x, y))) for x, y in pts])
        edge.append([max((k/RN)**3.5*0.9, math.exp(-(y/0.12)**2)*0.75) for x, y in pts])
    for j in range(S):
        bm.faces.new((rings[0][0], rings[1][j], rings[1][(j+1) % S]))
    for A_, B_ in zip(rings[1:], rings[2:]):
        for j in range(S):
            bm.faces.new((A_[j], B_[j], B_[(j+1) % S], A_[(j+1) % S]))
    for rg, ev in zip(rings, edge):
        for v, e in zip(rg, ev): v[lay] = e
    o = obj("Cookie", bm, dough)
    m = o.modifiers.new("Thick", 'SOLIDIFY'); m.thickness = 0.045; m.offset = 0   # the rims show the wafer's edge
    m = o.modifiers.new("Sub", 'SUBSURF'); m.levels = m.render_levels = 1
    root.rotation_euler = (math.radians(-30), math.radians(20), math.radians(-27))   # top tipped back, left end up
    return Vector((0, 0, -0.45))

def lock():
    # the Device of Theft-Prevention: a heavy brass padlock, a steel shackle, a dark keyhole ringed by glowing
    # blue wards, small studs round the face
    brass = mat("Brass", (0.8, 0.53, 0.2), Metallic=1.0, Roughness=0.3)[0]
    steel = mat("Steel", (0.6, 0.62, 0.66), Metallic=1.0, Roughness=0.25)[0]
    ward = mat("Ward", (0.1, 0.4, 1.0), **{"Emission Color": (0.1, 0.45, 1.0, 1), "Emission Strength": 2.2})[0]
    W, H, T = 0.75, 0.68, 0.28                      # half width, half height, half depth of the body
    body = box(-W, W, -T, T, -H, H)
    obj("Body", body, brass, bevel=0.12, subsurf=0)
    arc = [Vector((0.48*math.cos(a), 0, H - 0.05 + 0.48*math.sin(a)*1.15)) for a in (math.pi*i/24 for i in range(25))]
    legs = [Vector((0.48, 0, H - 0.05 - 0.25))] + arc + [Vector((-0.48, 0, H - 0.05 - 0.25))]
    obj("Shackle", tube(spline(legs, 3), 0.1, segs=16), steel, smooth=True)
    hole = bmesh.new()                              # keyhole: a round top and a tapering slot below, just proud of the face
    sphere(0.1, (0, -T - 0.005, 0.08), (1, 0.25, 1), bm=hole, segs=20)
    vs = [hole.verts.new((x, -T - 0.012, z)) for x, z in ((-0.05, 0.06), (0.05, 0.06), (0.08, -0.25), (-0.08, -0.25))]
    hole.faces.new(vs)
    obj("Keyhole", hole, BLACK, smooth=False)
    obj("Ward", torus(0.24, 0.022, Matrix.Translation((0, -T - 0.01, -0.03)) @ Matrix.Rotation(math.pi/2, 4, 'X'), segs=48, tseg=8), ward)
    for k in range(6):                              # the ward's runes: small glowing ticks round the ring
        a = math.tau*k/6 + math.pi/6
        obj("Rune", ico(0.035, (0.34*math.cos(a), -T - 0.01, -0.03 + 0.34*math.sin(a)), subdiv=0), ward, smooth=False)
    for x in (-W + 0.14, W - 0.14):                 # rivets in the corners
        for z in (-H + 0.14, H - 0.14):
            obj("Rivet", sphere(0.05, (x, -T - 0.01, z), (1, 0.6, 1), segs=12), steel, smooth=True)
    root.rotation_euler = (math.radians(8), 0, math.radians(-22))
    return Vector((0, 0, -0.2))

def lamp():
    brass = mat("Brass", (0.8, 0.53, 0.2), Metallic=1.0, Roughness=0.26)[0]
    obj("Body", sphere(1.0, (0, 0, 0), (0.85, 0.55, 0.42), segs=48), brass)
    obj("Foot", lathe([(0, -0.56), (0.32, -0.56), (0.33, -0.51), (0.2, -0.43), (0.16, -0.33), (0, -0.33)]), brass)
    obj("Lid", lathe([(0, 0.3), (0.33, 0.3), (0.35, 0.36), (0.27, 0.42), (0.2, 0.52), (0.08, 0.6), (0.05, 0.66), (0.09, 0.71), (0, 0.76)]), brass)
    sp = spline([(0.55, 0, 0.0), (1.0, 0, 0.1), (1.35, 0, 0.3), (1.62, 0, 0.5)], 8)
    obj("Spout", tube(sp, [0.2 - 0.145*i/(len(sp) - 1) for i in range(len(sp))], segs=20), brass)
    obj("Handle", tube(spline([(-0.7, 0, 0.22), (-1.1, 0, 0.32), (-1.27, 0, 0.06), (-1.06, 0, -0.18), (-0.74, 0, -0.12)], 8), 0.05), brass)
    obj("Band", torus(1.0, 0.025, Matrix.Diagonal((0.86, 0.56, 1, 1)), segs=64, tseg=6), GOLD)
    root.rotation_euler = (0, 0, math.radians(-22))
    return Vector((-0.15, 0, 0.05))

def hand():
    skin = mottled("Skin", (0.06, 0.06, 0.045), (0.2, 0.2, 0.14), rough=0.75, scale=7, bump=0.5, bump_scale=40)
    nail = mat("Nail", (0.04, 0.03, 0.025), Roughness=0.25)[0]
    linen = mottled("Linen", (0.35, 0.3, 0.2), (0.62, 0.56, 0.42), rough=0.9, scale=12, bump=0.3, bump_scale=80)
    flesh = bmesh.new(); claws = bmesh.new()
    sphere(1.0, (0, 0, 0), (0.48, 0.17, 0.56), bm=flesh, segs=32)
    tube(spline([(0, 0.02, -0.4), (0, 0.04, -0.8), (0, 0.06, -1.25)], 6), [0.24, 0.22], bm=flesh)
    def finger(base, dirx, curls, lengths, r0, r1):
        d = Vector((dirx, 0, 1)).normalized(); p = Vector(base); pts = [p.copy()]
        for c, L in zip(curls, lengths):               # each joint bends the finger towards the camera (-y)
            d = Matrix.Rotation(-math.radians(c), 3, 'X') @ d; p = p + d*L; pts.append(p.copy())
        path = spline(pts, 6)
        rs = [r0 + (r1 - r0)*i/(len(path) - 1) + 0.012*math.cos(i*math.tau/6) for i in range(len(path))]   # knobbly knuckles
        tube(path, rs, bm=flesh); cone(r1*0.9, 0.17, path[-1], d, bm=claws)
    for x, L in ((-0.33, 0.42), (-0.11, 0.5), (0.11, 0.48), (0.33, 0.38)):
        finger((x, 0, 0.42), x*0.5, (15, 35, 40), (L*0.65, L*0.5, L*0.4), 0.075, 0.042)
    d = Vector((0.75, -0.55, 0.9)).normalized(); b = Vector((0.34, -0.04, -0.15))   # the thumb
    pts = [b, b + d*0.2, b + d*0.34 + Vector((-0.02, -0.08, 0.05)), b + d*0.4 + Vector((-0.08, -0.17, 0.1))]
    path = spline(pts, 6); tube(path, [0.11, 0.05], bm=flesh); cone(0.05, 0.15, path[-1], path[-1] - path[-3], bm=claws)
    obj("Hand", flesh, skin); obj("Claws", claws, nail)
    wraps = bmesh.new()                               # mummy wrappings round the wrist
    for k, z in enumerate((-0.55, -0.72, -0.9, -1.07)):
        torus(0.235, 0.035, Matrix.Translation((0, 0.03 + 0.04*(z + 0.5), z)) @ Matrix.Rotation(math.radians(12*(-1)**k), 4, 'X')
              @ Matrix.Diagonal((1, 1, 1.6, 1)), bm=wraps, segs=32, tseg=6)
    obj("Wraps", wraps, linen)
    root.rotation_euler = (0, math.radians(-12), math.radians(8))
    return Vector((0, 0, -0.2))

def talisman():
    void = glow_mat("Void", [(0.35, (0.0, 0.0, 0.0)), (0.6, (0.25, 0.0, 0.55)), (0.8, (0.6, 0.25, 1.0))], 2.5, base=(0.0, 0.0, 0.0), scale=3)
    obj("Sphere", sphere(0.45, segs=48), void)
    rings = bmesh.new()
    for M in (Matrix.Rotation(math.pi/2, 4, 'X'), Matrix.Rotation(math.pi/2, 4, 'Y'), Matrix()):   # an armillary of gold bands
        torus(0.56, 0.035, M, bm=rings, segs=64, tseg=8)
    for p in ((0, 0, 0.56), (0, 0, -0.56), (0.56, 0, 0), (-0.56, 0, 0), (0, 0.56, 0), (0, -0.56, 0)):
        sphere(0.06, p, bm=rings, segs=14)
    torus(0.1, 0.03, Matrix.Translation((0, 0, 0.7)), bm=rings, segs=24, tseg=8)
    obj("Rings", rings, GOLD)
    root.rotation_euler = (math.radians(15), 0, math.radians(35))
    return Vector((0, 0, 0.05))

def wand():
    wood = wood_material("Shaft", (0.1, 0.05, 0.025), axis="Z", roughness=0.5)
    obj("Shaft", tube([(0, 0, -1.3), (0, 0, 0.95)], [0.065, 0.085], segs=20), wood)
    bands = bmesh.new()
    for z in (-1.1, -0.15, 0.7, 0.86):
        torus(0.08 + 0.01*(z + 1.3)/2.25, 0.022, Matrix.Translation((0, 0, z)), bm=bands, segs=24, tseg=6)
    sphere(0.11, (0, 0, -1.36), bm=bands, segs=16)
    obj("Bands", bands, GOLD)
    star = glow_mat("Star", [(0.2, (1.0, 0.1, 0.3)), (0.4, (1.0, 0.8, 0.1)), (0.6, (0.1, 1.0, 0.4)), (0.8, (0.2, 0.4, 1.0))],
                    1.4, base=(0.05, 0.05, 0.08), scale=4, distortion=2)
    obj("Crystal", ico(0.24, (0, 0, 1.15), subdiv=0), star, smooth=False)
    sparks = [(1.0, 0.2, 0.4), (1.0, 0.85, 0.2), (0.2, 1.0, 0.5), (0.3, 0.5, 1.0), (0.8, 0.3, 1.0), (1.0, 0.5, 0.1), (0.3, 1.0, 1.0)]
    for k, c in enumerate(sparks):
        a = math.tau*k/len(sparks) + rnd.uniform(-0.3, 0.3); r = rnd.uniform(0.35, 0.6)
        m = mat(f"Spark{k}", c, **{"Emission Color": (*c, 1), "Emission Strength": 6.0})[0]
        obj("Spark", ico(rnd.uniform(0.025, 0.045), (r*math.cos(a), r*math.sin(a)*0.6, 1.15 + r*math.sin(a)*0.8), subdiv=1), m)
    root.rotation_euler = (math.radians(10), math.radians(-32), math.radians(15))
    return Vector((0, 0, -0.05))

def annihilation():
    # the Sphere of Annihilation (the spell's moving orb): a ball of perfect black, its edge lit by a violet rim,
    # swallowing a swirling, tilted disc of glowing matter that gets hotter as it spirals in
    void = mat("Void", (0.0, 0.0, 0.0), Roughness=1.0, **{"Specular IOR Level": 0.0})[0]
    obj("Void", sphere(0.42, segs=64), void)
    def see_through(name, build):
        """A material mixing Transparent with an Emission: build(N, Lk) returns (emission colour, strength, alpha)."""
        m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
        N = nt.nodes.new; Lk = nt.links.new
        out = N("ShaderNodeOutputMaterial"); mix = N("ShaderNodeMixShader"); tr = N("ShaderNodeBsdfTransparent")
        em = N("ShaderNodeEmission"); col, strength, alpha = build(N, Lk)
        Lk(col, em.inputs["Color"]); em.inputs["Strength"].default_value = strength
        Lk(alpha, mix.inputs[0]); Lk(tr.outputs[0], mix.inputs[1]); Lk(em.outputs[0], mix.inputs[2]); Lk(mix.outputs[0], out.inputs[0])
        return m
    def rim(N, Lk):                                # bright only where the shell is seen edge-on
        lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.35
        pw = N("ShaderNodeMath"); pw.operation = 'POWER'; pw.inputs[1].default_value = 2.5; Lk(lw.outputs["Facing"], pw.inputs[0])
        rgb = N("ShaderNodeValToRGB"); Lk(pw.outputs[0], rgb.inputs[0]); el = rgb.color_ramp.elements
        el[0].color = (0.35, 0.0, 0.9, 1); el[1].color = (1.0, 0.55, 1.0, 1)
        return rgb.outputs["Color"], 5.0, pw.outputs[0]
    obj("Rim", sphere(0.46, segs=64), see_through("Rim", rim))
    def swirl(N, Lk):                              # spiral arms wound round the centre, ragged with noise; white-hot near the void
        tc = N("ShaderNodeTexCoord"); ln = N("ShaderNodeVectorMath"); ln.operation = 'LENGTH'; Lk(tc.outputs["Object"], ln.inputs[0])
        sp = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sp.inputs[0])
        at = N("ShaderNodeMath"); at.operation = 'ARCTAN2'; Lk(sp.outputs["Y"], at.inputs[0]); Lk(sp.outputs["X"], at.inputs[1])
        nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 4.0; nz.inputs["Detail"].default_value = 6
        Lk(tc.outputs["Object"], nz.inputs["Vector"])
        def lin(x, k, add=None):                   # k*x (+ add)
            m = N("ShaderNodeMath"); m.operation = 'MULTIPLY_ADD' if add is not None else 'MULTIPLY'; Lk(x, m.inputs[0])
            m.inputs[1].default_value = k
            if add is not None: Lk(add, m.inputs[2])
            return m.outputs[0]
        ph = lin(at.outputs[0], 3/math.tau, lin(ln.outputs["Value"], 5.0, lin(nz.outputs["Fac"], 1.2)))   # 3 arms, wound 5 turns per unit
        sn = N("ShaderNodeMath"); sn.operation = 'SINE'; Lk(lin(ph, math.tau), sn.inputs[0])
        band = N("ShaderNodeMapRange"); band.inputs["From Min"].default_value = 0.1; band.inputs["From Max"].default_value = 0.9
        Lk(sn.outputs[0], band.inputs["Value"])
        fall = N("ShaderNodeMapRange"); fall.inputs["From Min"].default_value = 0.45; fall.inputs["From Max"].default_value = 1.15
        fall.inputs["To Min"].default_value = 1.0; fall.inputs["To Max"].default_value = 0.0; Lk(ln.outputs["Value"], fall.inputs["Value"])
        a = N("ShaderNodeMath"); a.operation = 'MULTIPLY'; Lk(band.outputs["Result"], a.inputs[0]); Lk(fall.outputs["Result"], a.inputs[1])
        heat = N("ShaderNodeValToRGB"); Lk(fall.outputs["Result"], heat.inputs[0]); el = heat.color_ramp.elements
        el[0].color = (0.2, 0.0, 0.5, 1); el[1].position = 0.95; el[1].color = (1.0, 0.7, 1.0, 1)
        e = heat.color_ramp.elements.new(0.55); e.color = (0.9, 0.15, 0.85, 1)
        return heat.outputs["Color"], 2.2, a.outputs[0]
    disc = lathe([(0.44, -0.012), (1.15, -0.004), (1.15, 0.004), (0.44, 0.012)], segs=96)
    tilt = bpy.data.objects.new("Tilt", None); sc.collection.objects.link(tilt); tilt.parent = root
    tilt.rotation_euler = (math.radians(30), math.radians(-10), 0)   # nearly flat, tipped a little towards the camera
    d = obj("Disc", disc, see_through("Swirl", swirl), parent=tilt)
    d.rotation_euler = (0, 0, math.radians(-P.get("spin", 0)))      # spin (animation): turning this way the arms wind inwards
    motes = mat("Mote", (1.0, 0.6, 1.0), **{"Emission Color": (1.0, 0.6, 1.0, 1), "Emission Strength": 8.0})[0]
    for k in range(9):                             # specks of matter being pulled in along the disc
        a = math.tau*k/9 + rnd.uniform(-0.3, 0.3); r = rnd.uniform(0.6, 1.05)
        obj("Mote", ico(rnd.uniform(0.012, 0.025), (r*math.cos(a), r*math.sin(a), rnd.uniform(-0.03, 0.03)), subdiv=1), motes, parent=d)
    return Vector((0, 0, 0))

off = globals()[P["kind"]]()
root.location = Vector((0, 0, 1.4)) + off
r = root.rotation_euler; root.rotation_euler = (r.x + math.radians(P["tilt"]), r.y, r.z + math.radians(P["yaw"]))

rig(sc, elev=P["elev"])
studio_world(sc, 0.7)                               # something for the metal and glaze to reflect
spot(sc, (-3, -3, 4), 140, (1, 0.95, 0.85)); spot(sc, (3, -2.5, 3), 70, (1, 1, 1))
if P["ground"]:                                     # stands on the floor: a shadow catcher under its lowest point
    bpy.context.view_layer.update(); dg = bpy.context.evaluated_depsgraph_get()
    z0 = min((o.matrix_world @ v.co).z for o in sc.objects if o.type == 'MESH'
             for v in o.evaluated_get(dg).to_mesh().vertices)
    gp = bmesh.new(); bmesh.ops.create_grid(gp, x_segments=1, y_segments=1, size=10)
    ground = obj("Ground", gp, BLACK); ground.parent = None
    ground.location = (0, 0, z0); ground.is_shadow_catcher = True
    sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 4; sun.angle = math.radians(6)
    so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(30), 0, math.radians(-40))
    for l in bpy.data.lights:                       # only the sun darkens the ground (see build_throne.py)
        if l.type != 'SUN': l.use_shadow = False
    vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
    vis.diffuse = False
    sc.cycles.diffuse_bounces = 0
render(sc, OUT, P["save_blend"], samples=128)
