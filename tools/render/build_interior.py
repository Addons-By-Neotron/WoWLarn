"""Build + render the inside of one of the places you go into (a backdrop for its window, not an icon).  Usage:
blender -b -P build_interior.py -- out.png '{"kind":"home", "res":[1600, 1000], ...}'
kind: home, bank, branch (the bank's 8th-level office in the dungeon), shop (the Thrift Shoppe), trade (the Trading Post), college, lrs (the Revenue Service), den (Grizzik's), entrance (the dungeon's), volcano (its shaft; view: down from the rim or up from the bottom); home (the cottage at night: the hearth, your sick daughter in bed, the doctor's things, a moonlit window).
The room: floor z = 0, back wall at +y, the camera at eye height in front looking in.
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, use_device, wood_material, rock_material

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "interior.png"
P = dict(kind="home", res=[1600, 1000], samples=256, seed=5, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
rnd = random.Random(P["seed"])

# ---- geometry helpers (bmesh; each returns a new bmesh unless given one to add to)
def obj(name, bm, material, smooth=False, bevel=0.0, subsurf=0):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = smooth
    o = link(sc, name, me); o.data.materials.append(material)
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

def ball(loc, r, scale=(1, 1, 1), bm=None, segs=24):
    t = bmesh.new(); bmesh.ops.create_uvsphere(t, u_segments=segs, v_segments=segs//2, radius=r)
    t.transform(Matrix.Translation(loc) @ Matrix.Diagonal((*scale, 1)))
    return merge(bm or bmesh.new(), t)

def lump(loc, size, squash=(1, 1, 0.7), bm=None, jit=0.2):
    t = bmesh.new(); bmesh.ops.create_icosphere(t, subdivisions=2, radius=1)
    ph = [rnd.uniform(0, math.tau) for _ in range(3)]
    for v in t.verts:
        d = v.co.normalized(); w = 1 + jit*(math.sin(3*d.x + ph[0]) + math.sin(4*d.y + ph[1]) + math.sin(5*d.z + ph[2]))/3
        v.co = Vector((v.co.x*size*squash[0], v.co.y*size*squash[1], v.co.z*size*squash[2]))*w
    t.transform(Matrix.Translation(loc))
    return merge(bm or bmesh.new(), t)

# ---- materials
def mottle(name, base, amount=0.3, scale=6.0, rough=0.8, bump=0.2):
    """A plain surface with a soft noise in its colour and a fine bump (plaster, cloth)."""
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

def quilt(name, a, b_, scale=7.0):
    """A patchwork quilt: squares of two cloths (a checker in object space), soft."""
    m, b = mat(name, a, Roughness=0.95)
    nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord"); ck = N("ShaderNodeTexChecker"); ck.inputs["Scale"].default_value = scale
    ck.inputs["Color1"].default_value = (*a, 1); ck.inputs["Color2"].default_value = (*b_, 1)
    Lk(tc.outputs["Object"], ck.inputs["Vector"]); Lk(ck.outputs["Color"], b.inputs["Base Color"])
    b.inputs["Sheen Weight"].default_value = 0.5
    return m

def emit(name, col, strength, base=(0, 0, 0)):
    return mat(name, base, **{"Emission Color": (*col, 1), "Emission Strength": strength})[0]

def op(N, Lk, o, *ins):
    """A Math node: o on ins, each a number or a socket."""
    m = N("ShaderNodeMath"); m.operation = o
    for k, v in enumerate(ins):
        if isinstance(v, (int, float)): m.inputs[k].default_value = v
        else: Lk(v, m.inputs[k])
    return m.outputs[0]

def span(N, Lk, v, a, b):
    """v mapped from a..b to 0..1, clamped, smoothly."""
    m = N("ShaderNodeMapRange"); m.inputs["From Min"].default_value = a; m.inputs["From Max"].default_value = b
    m.interpolation_type = 'SMOOTHSTEP'; Lk(v, m.inputs["Value"]); return m.outputs["Result"]

def flame_material(name, phase):
    """Flames on a sheet (object x -0.5..0.5 across, z 0..1 up): noise stretched upwards eats a tongue shape away at
    its edges, so it licks up in ragged tongues, hottest (yellow-white) low in the middle, dark red at the tips."""
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    N = nt.nodes.new; Lk = nt.links.new
    out = N("ShaderNodeOutputMaterial"); mix = N("ShaderNodeMixShader"); tr = N("ShaderNodeBsdfTransparent")
    em = N("ShaderNodeEmission"); em.inputs["Strength"].default_value = 3.0
    tc = N("ShaderNodeTexCoord"); sp = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sp.inputs[0])
    x, z = sp.outputs["X"], sp.outputs["Z"]
    def noise(sx, sz, detail, w):
        cb = N("ShaderNodeCombineXYZ"); Lk(op(N, Lk, 'MULTIPLY', x, sx), cb.inputs["X"]); Lk(op(N, Lk, 'MULTIPLY', z, sz), cb.inputs["Y"])
        n = N("ShaderNodeTexNoise"); n.noise_dimensions = '3D'; n.inputs["Scale"].default_value = 1.0
        n.inputs["Detail"].default_value = detail; n.inputs["Roughness"].default_value = 0.55; n.inputs["Distortion"].default_value = 0.8
        cb.inputs["Z"].default_value = w; Lk(cb.outputs[0], n.inputs["Vector"]); return n.outputs["Fac"]
    n1 = noise(4.0, 1.6, 6, phase)                  # big tongues
    n2 = noise(10.0, 3.5, 3, phase + 5.0)           # finer flicker in them
    ax = op(N, Lk, 'ABSOLUTE', x)
    # the tongue: wide at the foot, narrowing to nothing at the top
    shape = op(N, Lk, 'SUBTRACT', op(N, Lk, 'SUBTRACT', 1.0, op(N, Lk, 'MULTIPLY', z, 1.05)),
               op(N, Lk, 'MULTIPLY', ax, op(N, Lk, 'MULTIPLY_ADD', z, 2.2, 1.3)))
    d = op(N, Lk, 'ADD', shape, op(N, Lk, 'MULTIPLY', op(N, Lk, 'SUBTRACT', n1, 0.5), 1.5))
    d = op(N, Lk, 'ADD', d, op(N, Lk, 'MULTIPLY', op(N, Lk, 'SUBTRACT', n2, 0.5), 0.5))
    dens = op(N, Lk, 'MULTIPLY', span(N, Lk, d, 0.0, 0.3), span(N, Lk, z, 0.0, 0.08))   # (a soft foot in the logs)
    heat = span(N, Lk, op(N, Lk, 'SUBTRACT', d, op(N, Lk, 'MULTIPLY', z, 0.25)), 0.0, 0.8)
    cr = N("ShaderNodeValToRGB"); Lk(heat, cr.inputs[0]); el = cr.color_ramp.elements
    stops = [(0.0, (0.25, 0.02, 0.0)), (0.3, (0.8, 0.12, 0.0)), (0.6, (1.0, 0.38, 0.03)), (0.85, (1.0, 0.7, 0.2)), (1.0, (1.0, 0.9, 0.6))]
    el[0].position, el[0].color = stops[0][0], (*stops[0][1], 1); el[1].position, el[1].color = stops[-1][0], (*stops[-1][1], 1)
    for p_, c_ in stops[1:-1]:
        e = el.new(p_); e.color = (*c_, 1)
    Lk(cr.outputs["Color"], em.inputs["Color"])
    Lk(dens, mix.inputs[0]); Lk(tr.outputs[0], mix.inputs[1]); Lk(em.outputs[0], mix.inputs[2]); Lk(mix.outputs[0], out.inputs[0])
    m.cycles.emission_sampling = 'NONE'             # (the point lights do the lighting; the sheets only show)
    return m

def flame_sheet(name, foot, w, h, phase, toward):
    """A sheet of flames w wide and h high standing on foot, turned (about z) to face toward."""
    bm = bmesh.new()
    vs = [bm.verts.new(v) for v in ((-0.5, 0, 0), (0.5, 0, 0), (0.5, 0, 1), (-0.5, 0, 1))]; bm.faces.new(vs)
    o = obj(name, bm, flame_material(name, phase))
    o.location = foot; o.scale = (w, 1, h)
    d = Vector(toward) - Vector(foot); o.rotation_euler = (0, 0, math.atan2(d.y, d.x) - math.pi/2)
    o.visible_shadow = False
    return o

CAM = (0.0, -2.5, 1.5)                              # where the camera stands (see home)

PLASTER = mottle("Plaster", (0.36, 0.3, 0.23), amount=0.15, scale=3, bump=0.15)
TIMBER = wood_material("Timber", (0.06, 0.035, 0.018), axis="Z")
BEAM = wood_material("Beam", (0.06, 0.035, 0.018), axis="X")
FLOOR = wood_material("Floor", (0.11, 0.065, 0.03), axis="Y", roughness=0.7)
FURN = wood_material("Furniture", (0.13, 0.075, 0.035), axis="X", roughness=0.6)
STONE = rock_material("Hearth", (0.75, 0.72, 0.68), scale=1.2)[0]
SOOT = mottle("Soot", (0.03, 0.025, 0.02), amount=0.4, scale=8)
IRON = mat("Iron", (0.05, 0.05, 0.055), Metallic=0.8, Roughness=0.45)[0]
BRASS = mat("Brass", (0.7, 0.48, 0.2), Metallic=1.0, Roughness=0.3)[0]
LINEN = mottle("Linen", (0.75, 0.72, 0.65), amount=0.08, scale=10, rough=0.95, bump=0.1)
QUILT = quilt("Quilt", (0.35, 0.08, 0.06), (0.55, 0.42, 0.22))
RUG = quilt("Rug", (0.16, 0.05, 0.03), (0.11, 0.08, 0.06), scale=9)
SKIN = mat("Skin", (0.62, 0.42, 0.33), Roughness=0.6, **{"Subsurface Weight": 0.3})[0]
HAIR = mottle("Hair", (0.25, 0.14, 0.06), amount=0.3, scale=30, rough=0.7)
LEATHER = mottle("Leather", (0.08, 0.04, 0.025), amount=0.25, scale=12, rough=0.55)
GLASS_GREEN = mat("GlassG", (0.15, 0.4, 0.15), Roughness=0.05, **{"Transmission Weight": 0.9})[0]
GLASS_BLUE = mat("GlassB", (0.15, 0.25, 0.5), Roughness=0.05, **{"Transmission Weight": 0.9})[0]
GLASS_AMBER = mat("GlassA", (0.5, 0.25, 0.05), Roughness=0.05, **{"Transmission Weight": 0.9})[0]
WAX = mat("Wax", (0.85, 0.8, 0.65), Roughness=0.5, **{"Subsurface Weight": 0.5})[0]
FIRE = emit("Fire", (1.0, 0.22, 0.02), 1.6)
EMBER = emit("Ember", (1.0, 0.25, 0.04), 6.0, (0.2, 0.05, 0.01))
CANDLE = emit("CandleFlame", (1.0, 0.7, 0.3), 25.0)
NIGHT = emit("Night", (0.03, 0.05, 0.12), 0.6)
MOON = emit("Moon", (0.85, 0.9, 1.0), 6.0)
CERAMIC = mottle("Ceramic", (0.55, 0.5, 0.42), amount=0.1, scale=5, rough=0.35)
BREAD = mottle("Bread", (0.45, 0.26, 0.1), amount=0.3, scale=14, rough=0.8, bump=0.4)
PAPER = mottle("Paper", (0.8, 0.74, 0.6), amount=0.1, scale=6, rough=0.9)

def light(kind, loc, energy, col, size=0.2, aim=None, spot=None):
    l = bpy.data.lights.new("L", kind); l.energy = energy; l.color = col
    if kind in ('POINT', 'SPOT'): l.shadow_soft_size = size
    elif kind == 'AREA': l.size = size
    if spot: l.spot_size = math.radians(spot); l.spot_blend = 0.6
    o = link(sc, "L", l); o.location = loc; o.visible_camera = False
    if aim is not None: o.rotation_euler = (Vector(aim) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return o

def camera(loc, aim, lens):
    cam = bpy.data.cameras.new("Cam"); cam.lens = lens; cam.sensor_width = 36
    co = link(sc, "Cam", cam); co.location = loc
    co.rotation_euler = (Vector(aim) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler(); sc.camera = co

# ---- the rooms
def home():
    """The cottage at night.  Back wall y = 4, side walls x = -3.2 and 3.2, the ceiling beams at 2.6."""
    X0, X1, Y1, H = -3.2, 3.2, 3.4, 2.7
    obj("Floor", box(X0, X1, -2, Y1, -0.1, 0), FLOOR)
    fl = bmesh.new()                                # the floor boards' seams
    for x in [X0 + 0.32*k for k in range(1, 20)]:
        box(x - 0.005, x + 0.005, -2, Y1, 0, 0.002, bm=fl)
    obj("Seams", fl, SOOT)
    # walls: plaster between dark timbers
    back = bmesh.new()
    box(X0, -0.15, Y1, Y1 + 0.2, 0, H, bm=back); box(1.45, X1, Y1, Y1 + 0.2, 0, H, bm=back)   # (the window in between)
    box(-0.15, 1.45, Y1, Y1 + 0.2, 0, 0.95, bm=back); box(-0.15, 1.45, Y1, Y1 + 0.2, 2.05, H, bm=back)
    obj("BackWall", back, PLASTER)
    obj("LeftWall", box(X0 - 0.2, X0, -2, Y1, 0, H), PLASTER)
    obj("RightWall", box(X1, X1 + 0.2, -2, Y1, 0, H), PLASTER)
    obj("Ceiling", box(X0, X1, -2, Y1, H, H + 0.1), PLASTER)
    tb = bmesh.new()
    for x in (-2.0, -0.15 - 0.08, 1.45, 2.4):       # posts on the back wall
        box(x, x + 0.14, Y1 - 0.04, Y1 + 0.02, 0, H, bm=tb)
    box(X0, X1, Y1 - 0.05, Y1 + 0.02, 0, 0.14, bm=tb)        # sill beam
    box(X0, X1, Y1 - 0.06, Y1 + 0.02, H - 0.2, H, bm=tb)     # wall plate
    for y in (-1.0, 0.6, 2.2):                      # posts on the side walls
        box(X0, X0 + 0.06, y, y + 0.14, 0, H, bm=tb); box(X1 - 0.06, X1, y, y + 0.14, 0, H, bm=tb)
    box(-2.0, -0.23, Y1 - 0.05, Y1 + 0.02, 1.45, 1.55, bm=tb)  # a rail across the panels
    obj("Timbers", tb, TIMBER, bevel=0.01)
    bm_ = bmesh.new()
    for y in (-1.2, 0.2, 1.6, 3.0):                 # ceiling beams across
        box(X0, X1, y, y + 0.2, H - 0.24, H, bm=bm_)
    obj("Beams", bm_, BEAM, bevel=0.015)

    # the window: night outside, the moon, mullions; moonlight falling in
    obj("NightSky", box(-0.4, 1.7, Y1 + 0.6, Y1 + 0.62, 0.5, 2.6), NIGHT)
    obj("Moon", ball((1.05, Y1 + 0.55, 1.78), 0.09, segs=24), MOON)
    wf = bmesh.new()
    box(-0.15, 1.45, Y1 - 0.06, Y1 + 0.24, 0.9, 0.98, bm=wf); box(-0.15, 1.45, Y1 - 0.02, Y1 + 0.2, 2.02, 2.1, bm=wf)
    for x in (-0.15, 0.61, 1.37):
        box(x, x + 0.08, Y1 + 0.02, Y1 + 0.12, 0.95, 2.05, bm=wf)
    box(-0.15, 1.45, Y1 + 0.03, Y1 + 0.1, 1.48, 1.54, bm=wf)
    obj("WindowFrame", wf, TIMBER, bevel=0.005)
    light('AREA', (0.65, Y1 + 1.2, 2.4), 60, (0.55, 0.65, 1.0), size=1.4, aim=(0.4, 1.5, 0))

    # the hearth on the left wall: stone surround, a sooty firebox, a fire, a pot on a hook, a mantel
    hx = X0
    hs = bmesh.new()
    box(hx, hx + 0.55, 0.6, 1.0, 0, 1.25, bm=hs); box(hx, hx + 0.55, 2.2, 2.6, 0, 1.25, bm=hs)   # cheeks
    box(hx, hx + 0.55, 0.6, 2.6, 1.0, 1.25, bm=hs)                                             # lintel
    box(hx, hx + 0.45, 0.75, 2.45, 1.25, H, bm=hs)                                             # chimney breast
    box(hx + 0.55, hx + 0.95, 0.5, 2.7, 0, 0.08, bm=hs)                                        # hearthstone
    obj("Hearth", hs, STONE, bevel=0.02)
    obj("Firebox", box(hx - 0.01, hx + 0.3, 1.0, 2.2, 0, 1.0), SOOT)
    obj("Mantel", box(hx, hx + 0.68, 0.5, 2.7, 1.25, 1.33), FURN, bevel=0.01)
    logs = bmesh.new()
    for k, (y, a) in enumerate(((1.35, 0.2), (1.75, -0.25), (1.55, 0.05))):
        t = lathe([(0, -0.3), (0.07, -0.3), (0.07, 0.3), (0, 0.3)], 12)
        t.transform(Matrix.Translation((hx + 0.35, y, 0.12 + 0.08*k)) @ Matrix.Rotation(math.pi/2, 4, 'X') @ Matrix.Rotation(a, 4, 'Y'))
        merge(logs, t)
    obj("Logs", logs, FURN)
    obj("Embers", box(hx + 0.2, hx + 0.5, 1.2, 1.95, 0.05, 0.08), EMBER, subsurf=1)
    for k, (dy, w, h, ph) in enumerate(((-0.25, 0.5, 0.42, 0.0), (0.2, 0.55, 0.5, 3.1), (0.0, 0.75, 0.6, 7.4))):
        flame_sheet(f"Fire{k}", (hx + 0.36 - 0.03*k, 1.6 + dy, 0.12), w, h, ph, toward=CAM)
    light('POINT', (hx + 0.95, 1.6, 0.45), 70, (1.0, 0.42, 0.1), size=0.3)   # (out of the firebox: inside, it lights the soot up)
    obj("Crane", box(hx + 0.05, hx + 0.6, 1.58, 1.62, 0.92, 0.95), IRON)
    obj("Pot", lathe([(0, 0), (0.12, 0.02), (0.17, 0.12), (0.15, 0.26), (0.16, 0.28), (0, 0.28)], 20,
                     Matrix.Translation((hx + 0.45, 1.6, 0.48))), IRON, smooth=True)
    mt = bmesh.new()                                # things on the mantel
    for k, y in enumerate((0.75, 1.05, 2.35)):
        lathe([(0, 0), (0.06, 0), (0.07, 0.12), (0.04, 0.2), (0.05, 0.22), (0, 0.22)], 14,
              Matrix.Translation((hx + 0.35, y, 1.33)), bm=mt)
    obj("Jugs", mt, CERAMIC, smooth=True)
    obj("PlateBack", lathe([(0, 0), (0.17, 0.01), (0.19, 0.03), (0, 0.03)], 24,
                           Matrix.Translation((hx + 0.1, 1.7, 1.55)) @ Matrix.Rotation(math.radians(80), 4, 'Y')), CERAMIC, smooth=True)

    # the table and chairs, middle left, a candle, a bowl and bread, a letter from the doctor
    tx, ty = -1.0, 0.9
    t = bmesh.new()
    box(tx - 0.65, tx + 0.65, ty - 0.4, ty + 0.4, 0.72, 0.78, bm=t)
    for dx in (-0.57, 0.5):
        for dy in (-0.32, 0.25):
            box(tx + dx, tx + dx + 0.07, ty + dy, ty + dy + 0.07, 0, 0.72, bm=t)
    obj("Table", t, FURN, bevel=0.01)
    for cx, cy, turn in ((tx - 0.25, ty - 0.75, 0.15), (tx + 0.9, ty + 0.1, 1.4)):
        c = bmesh.new(); m = Matrix.Translation((cx, cy, 0)) @ Matrix.Rotation(turn, 4, 'Z')
        box(-0.22, 0.22, -0.22, 0.22, 0.43, 0.47, bm=c, m=m)
        for dx in (-0.2, 0.16):
            for dy in (-0.2, 0.16):
                box(dx, dx + 0.04, dy, dy + 0.04, 0, 0.43, bm=c, m=m)
        box(-0.22, 0.22, -0.22, -0.18, 0.47, 0.95, bm=c, m=m)
        obj("Chair", c, FURN, bevel=0.008)
    obj("Candle", lathe([(0, 0), (0.025, 0), (0.025, 0.16), (0, 0.16)], 12, Matrix.Translation((tx + 0.3, ty + 0.1, 0.8))), WAX)
    obj("CandleDish", lathe([(0, 0), (0.07, 0), (0.08, 0.02), (0, 0.02)], 16, Matrix.Translation((tx + 0.3, ty + 0.1, 0.78))), BRASS)
    obj("CandleFlame", lathe([(0, 0), (0.012, 0.015), (0.008, 0.035), (0, 0.055)], 10, Matrix.Translation((tx + 0.3, ty + 0.1, 0.965))), CANDLE)
    light('POINT', (tx + 0.3, ty + 0.1, 1.02), 12, (1.0, 0.7, 0.35), size=0.05)
    obj("Bowl", lathe([(0, 0), (0.08, 0), (0.15, 0.07), (0.13, 0.08), (0.06, 0.02), (0, 0.02)], 20,
                      Matrix.Translation((tx - 0.3, ty, 0.78))), CERAMIC, smooth=True)
    obj("Bread", lump((tx - 0.3, ty, 0.86), 0.08, (1.3, 0.9, 0.6)), BREAD, smooth=True)
    obj("Letter", box(tx + 0.0, tx + 0.22, ty - 0.25, ty - 0.08, 0.78, 0.782, m=Matrix.Rotation(0.2, 4, 'Z')), PAPER)

    # the bed on the right, against the back wall: your daughter, sick, under the quilt
    before = set(bpy.data.objects)
    bx, by = 0.0, 0.0                               # the middle of the bed, its head at +y
    bd = bmesh.new()
    box(bx - 0.6, bx + 0.6, by - 1.05, by + 1.05, 0.25, 0.4, bm=bd)                 # frame
    for dx in (-0.6, 0.52):
        box(bx + dx, bx + dx + 0.08, by + 0.97, by + 1.05, 0, 1.1, bm=bd)          # head posts
        box(bx + dx, bx + dx + 0.08, by - 1.05, by - 0.97, 0, 0.7, bm=bd)          # foot posts
    box(bx - 0.6, bx + 0.6, by + 0.98, by + 1.04, 0.4, 0.95, bm=bd)                 # headboard
    box(bx - 0.6, bx + 0.6, by - 1.04, by - 0.98, 0.4, 0.6, bm=bd)                  # footboard
    obj("Bed", bd, FURN, bevel=0.01)
    obj("Mattress", box(bx - 0.55, bx + 0.55, by - 0.98, by + 0.97, 0.4, 0.55), LINEN, bevel=0.05)
    obj("Pillow", lump((bx, by + 0.72, 0.62), 0.32, (1.0, 0.45, 0.22), jit=0.08), LINEN, smooth=True, subsurf=1)
    hz = 0.76                                        # her head on the pillow, face up (her face is +z, the top of her head +y)
    obj("Head", ball((bx, by + 0.66, hz), 0.1, (0.85, 1.0, 0.95)), SKIN, smooth=True)
    obj("Nose", ball((bx, by + 0.62, hz + 0.095), 0.02, (1, 1, 1.1)), SKIN, smooth=True)
    hr = bmesh.new()                                # her hair: round the top and back of her head, spread on the pillow
    ball((bx, by + 0.71, hz + 0.01), 0.105, (0.95, 0.85, 0.9), bm=hr)
    ball((bx, by + 0.8, hz - 0.06), 0.14, (1.3, 0.65, 0.22), bm=hr)
    obj("Hair", hr, HAIR, smooth=True)
    q = bmesh.new()                                  # the quilt over her, the shape of a child under it
    box(bx - 0.6, bx + 0.6, by - 1.0, by + 0.5, 0.52, 0.62, bm=q)
    obj("QuiltFlat", q, QUILT, bevel=0.04)
    obj("Body", lump((bx - 0.02, by - 0.05, 0.62), 0.55, (0.42, 1.0, 0.32), jit=0.08), QUILT, smooth=True, subsurf=1)
    obj("Cloth", box(bx - 0.08, bx + 0.08, by + 0.62, by + 0.72, 0.85, 0.875), LINEN, bevel=0.01)  # a cool cloth on her brow

    bed = bpy.data.objects.new("BedRoot", None); sc.collection.objects.link(bed)
    bed.location = (2.1, 1.35, 0); bed.rotation_euler = (0, 0, -math.pi/2)   # side on to us, its head against the right wall
    for o in set(bpy.data.objects) - before - {bed}: o.parent = bed

    # the bedside stool: the doctor's bottles, a spoon, a candle; his bag on the floor
    sx, sy = 2.75, 0.35
    s = bmesh.new()
    box(sx - 0.22, sx + 0.22, sy - 0.22, sy + 0.22, 0.5, 0.55, bm=s)
    for dx in (-0.18, 0.14):
        for dy in (-0.18, 0.14):
            box(sx + dx, sx + dx + 0.04, sy + dy, sy + dy + 0.04, 0, 0.5, bm=s)
    obj("Stool", s, FURN, bevel=0.008)
    for (dx, dy), g, h in (((-0.1, 0.05), GLASS_GREEN, 0.2), ((0.05, 0.08), GLASS_AMBER, 0.15), ((0.1, -0.08), GLASS_BLUE, 0.12)):
        obj("Bottle", lathe([(0, 0), (0.04, 0), (0.045, h*0.6), (0.015, h*0.8), (0.015, h), (0, h)], 16,
                            Matrix.Translation((sx + dx, sy + dy, 0.55))), g, smooth=True)
    obj("Spoon", box(sx - 0.12, sx + 0.04, sy - 0.12, sy - 0.1, 0.55, 0.56, m=Matrix.Rotation(0.4, 4, 'Z')), BRASS)
    obj("Candle2", lathe([(0, 0), (0.02, 0), (0.02, 0.1), (0, 0.1)], 12, Matrix.Translation((sx - 0.05, sy - 0.08, 0.55))), WAX)
    obj("Flame2", lathe([(0, 0), (0.01, 0.012), (0.007, 0.03), (0, 0.045)], 10, Matrix.Translation((sx - 0.05, sy - 0.08, 0.655))), CANDLE)
    light('POINT', (sx - 0.05, sy - 0.08, 0.72), 14, (1.0, 0.7, 0.35), size=0.04)
    bag = bmesh.new()
    lathe([(0, 0), (0.22, 0), (0.24, 0.12), (0.2, 0.26), (0.05, 0.3), (0, 0.3)], 20,
          Matrix.Translation((0.75, 0.1, 0)) @ Matrix.Diagonal((1.0, 0.6, 1.0, 1)), bm=bag)
    obj("DoctorsBag", bag, LEATHER, smooth=True)
    obj("BagClasp", box(0.67, 0.83, -0.06, -0.03, 0.24, 0.28), BRASS)

    # a rug, a chest at the foot of the bed, a shelf with crocks on the right wall, a broom by the hearth
    obj("Rug", box(-1.9, 0.6, -0.4, 2.0, 0, 0.012), RUG, bevel=0.005)
    ch = bmesh.new(); box(1.9, 2.8, Y1 - 0.45, Y1, 0, 0.42, bm=ch)
    obj("Chest", ch, FURN, bevel=0.015)
    obj("ChestBands", box(1.88, 2.82, Y1 - 0.47, Y1, 0.3, 0.33), IRON)
    obj("Shelf", box(X1 - 0.3, X1, 0.2, 1.5, 1.6, 1.65), FURN)
    cr = bmesh.new()
    for y in (0.35, 0.65, 0.95, 1.3):
        lathe([(0, 0), (0.08, 0), (0.1, 0.12), (0.07, 0.2), (0, 0.2)], 14, Matrix.Translation((X1 - 0.15, y, 1.65)), bm=cr)
    obj("Crocks", cr, CERAMIC, smooth=True)
    br = bmesh.new()
    box(hx + 0.62, hx + 0.65, 0.3, 0.33, 0.1, 1.2, bm=br, m=Matrix.Rotation(0.12, 4, 'X'))
    obj("BroomHandle", br, FURN)
    obj("BroomHead", lump((hx + 0.635, 0.3, 0.12), 0.12, (0.6, 0.6, 1.0)), mottle("Straw", (0.5, 0.38, 0.15), 0.4, 30), smooth=True)

    # fill: a little warm bounce so the dark corners are not black
    light('AREA', (0, -1.5, 2.4), 6, (1.0, 0.75, 0.5), size=3, aim=(0, 2, 0.8))
    camera(CAM, (0.15, 3.0, 0.85), 19)
    return 0.0

def checker(name, a, b_, scale, rough):
    """Polished stone squares of two kinds (a floor), each with a soft mottle."""
    m, b = mat(name, a, Roughness=rough)
    nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord"); ck = N("ShaderNodeTexChecker"); ck.inputs["Scale"].default_value = scale
    ck.inputs["Color1"].default_value = (*a, 1); ck.inputs["Color2"].default_value = (*b_, 1)
    Lk(tc.outputs["Object"], ck.inputs["Vector"])
    nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 3; nz.inputs["Detail"].default_value = 8
    nz.inputs["Distortion"].default_value = 2.0; Lk(tc.outputs["Object"], nz.inputs["Vector"])
    mo = N("ShaderNodeMapRange"); mo.inputs["To Min"].default_value = 0.8; mo.inputs["To Max"].default_value = 1.15
    Lk(nz.outputs["Fac"], mo.inputs["Value"])
    mu = N("ShaderNodeMix"); mu.data_type = 'RGBA'; mu.blend_type = 'MULTIPLY'; mu.inputs["Factor"].default_value = 1.0
    Lk(ck.outputs["Color"], mu.inputs["A"]); Lk(mo.outputs["Result"], mu.inputs["B"]); Lk(mu.outputs["Result"], b.inputs["Base Color"])
    return m

def text(name, body, loc, size, material, rot=(math.pi/2, 0, 0), extrude=0.01):
    cu = bpy.data.curves.new(name, 'FONT'); cu.body = body; cu.size = size; cu.extrude = extrude
    cu.align_x = 'CENTER'; cu.align_y = 'CENTER'
    o = link(sc, name, cu); o.location = loc; o.rotation_euler = rot; o.data.materials.append(material)
    return o

def coin_heap(name, cx, cy, z0, R, H, material, dark, lumps=4, density=1.3, cr=0.035, spill=True):
    """A heap of gold coins like the ones in the dungeon (build_gold.py): overlapping mounds with coins lying on the
    surface, a few propped up, some spilled round the foot, and a dark core under them so no gaps show."""
    ct = cr*0.2
    proto = bmesh.new(); bmesh.ops.create_cone(proto, cap_ends=True, segments=16, radius1=cr, radius2=cr, depth=ct)
    caps = [f for f in proto.faces if abs(f.normal.z) > 0.9]
    bmesh.ops.inset_individual(proto, faces=caps, thickness=cr*0.14, depth=-ct*0.18)
    mounds = []
    for k in range(lumps):
        a = rnd.uniform(0, math.tau); off = R*0.45*(rnd.random()**0.5 if k else 0)
        mounds.append((off*math.cos(a), off*math.sin(a), R*rnd.uniform(0.3, 0.45), H*(1.0 if k == 0 else rnd.uniform(0.45, 0.85))))
    def h(x, y): return max(hm*math.exp(-((x - mx)**2 + (y - my)**2)/(s_*s_)) for mx, my, s_, hm in mounds)
    def nrm(x, y, e=0.01): return Vector((h(x - e, y) - h(x + e, y), h(x, y - e) - h(x, y + e), 2*e)).normalized()
    bm = bmesh.new(); floor = ct*0.6
    def place(loc, n_, spin):
        t = proto.copy(); t.transform(Matrix.Translation(loc) @ n_.to_track_quat('Z', 'Y').to_matrix().to_4x4() @ Matrix.Rotation(spin, 4, 'Z'))
        merge(bm, t)
    area = sum(1 for i in range(40) for j in range(40) if h(2*R*(i/19.5 - 1), 2*R*(j/19.5 - 1)) > floor)*(4*R/40)**2
    n = int(density*area/(math.pi*cr*cr)); placed = spilled = 0
    while placed < n:
        x, y = rnd.uniform(-2*R, 2*R), rnd.uniform(-2*R, 2*R); z = h(x, y)
        if z < floor: continue
        tilt = 0.6 if rnd.random() < 0.12 else 0.25
        n_ = (nrm(x, y) + Vector((rnd.gauss(0, tilt), rnd.gauss(0, tilt), 0))).normalized()
        place(Vector((cx + x, cy + y, z0 + z + ct/2 + rnd.uniform(0, 0.01))), n_, rnd.uniform(0, math.tau)); placed += 1
    while spill and spilled < n//12:
        x, y = rnd.uniform(-2.2*R, 2.2*R), rnd.uniform(-2.2*R, 2.2*R)
        if not (0.0003 < h(x, y) < floor): continue
        place(Vector((cx + x, cy + y, z0 + ct/2 + 0.002)), Vector((rnd.gauss(0, 0.12), rnd.gauss(0, 0.12), 1)).normalized(),
              rnd.uniform(0, math.tau)); spilled += 1
    proto.free()
    obj(name, bm, material, smooth=True)
    core = bmesh.new(); bmesh.ops.create_grid(core, x_segments=48, y_segments=48, size=2.2*R)
    for v in core.verts: v.co.z = max(0.0, h(v.co.x, v.co.y)*0.92 - 0.005)
    bmesh.ops.delete(core, geom=[f for f in core.faces if all(v.co.z <= 0.0 for v in f.verts)], context='FACES')
    core.transform(Matrix.Translation((cx, cy, z0)))
    obj(name + "Core", core, dark, smooth=True)
    return lambda x, y: z0 + h(x - cx, y - cy)      # (the heap's height, to lay things on it)

def gem(name, loc, size, color, ior, cut="brilliant", tilt=(0, 0, 0)):
    """A cut gem like the dungeon's (build_gem.py): brilliant (round), step (emerald: a chamfered oblong) or trillion."""
    if cut == "brilliant":
        n, outline, rings = 8, lambda t: (math.cos(t*math.tau), math.sin(t*math.tau)), [(0.0, -0.62), (1.0, 0.0), (1.0, 0.05), (0.6, 0.3), (0.0, 0.3)]
    elif cut == "step":
        pts = [(1, 0.48), (0.78, 0.7), (-0.78, 0.7), (-1, 0.48), (-1, -0.48), (-0.78, -0.7), (0.78, -0.7), (1, -0.48)]
        n, outline, rings = 8, lambda t: pts[int(round(t*8)) % 8], [(0.1, -0.45), (0.6, -0.25), (1.0, 0.0), (1.0, 0.05), (0.75, 0.22), (0.0, 0.22)]
    else:
        n, outline, rings = 3, lambda t: (math.cos(t*math.tau + math.pi/2), math.sin(t*math.tau + math.pi/2)), [(0.0, -0.5), (1.0, 0.0), (1.0, 0.05), (0.55, 0.25), (0.0, 0.25)]
    bm = bmesh.new(); loops = []
    for sc_, z in rings:
        loops.append([bm.verts.new((0, 0, z))] if sc_ == 0 else [bm.verts.new((outline(k/n)[0]*sc_, outline(k/n)[1]*sc_, z)) for k in range(n)])
    for a, b in zip(loops, loops[1:]):
        if len(a) == 1 or len(b) == 1:
            ring, pt = (b, a[0]) if len(a) == 1 else (a, b[0])
            for k in range(n): bm.faces.new((ring[k], ring[(k + 1) % n], pt))
        else:
            for k in range(n): bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.transform(Matrix.Translation(loc) @ Matrix.Rotation(tilt[2], 4, 'Z') @ Matrix.Rotation(tilt[0], 4, 'X')
                 @ Matrix.Rotation(tilt[1], 4, 'Y') @ Matrix.Diagonal((size, size, size, 1)))
    m = mat(name, color, Roughness=0.0, IOR=ior, **{"Transmission Weight": 1.0})[0]
    return obj(name, bm, m)

GEMS = [((0.75, 0.0, 0.03), 1.77, "brilliant"), ((0.02, 0.6, 0.15), 1.58, "step"),
        ((0.03, 0.12, 0.85), 1.77, "trillion"), ((0.85, 0.93, 1.0), 1.9, "brilliant")]   # ruby, emerald, sapphire, diamond

def bank():
    """The First National Bank of Ularn by day: a pale stone hall, a chequered marble floor, columns down both sides,
    the tellers' counter across the back behind brass grilles, the great round vault door standing ajar with the gold
    shining inside, daylight from tall windows on the left, a chandelier.  Back wall y = 5."""
    X0, X1, Y1, H = -4.2, 4.2, 5.0, 4.4
    MARBLE = checker("Marble", (0.38, 0.35, 0.3), (0.12, 0.1, 0.09), 2.6, 0.15)
    WALL = mottle("BankWall", (0.36, 0.31, 0.25), amount=0.12, scale=2, bump=0.1)
    PALE = mottle("PaleStone", (0.45, 0.42, 0.36), amount=0.15, scale=5, rough=0.5, bump=0.15)
    DARKWOOD = wood_material("DarkWood", (0.07, 0.03, 0.015), axis="X", roughness=0.35)
    GILT = mat("Gilt", (1.0, 0.72, 0.3), Metallic=1.0, Roughness=0.2)[0]
    STEEL = mat("Steel", (0.45, 0.45, 0.47), Metallic=1.0, Roughness=0.3)[0]
    VELVET = mottle("Velvet", (0.35, 0.03, 0.04), amount=0.2, scale=20, rough=0.9)
    SKY = bpy.data.materials.new("Sky"); SKY.use_nodes = True; _n = SKY.node_tree.nodes; _n.clear()
    _e = _n.new("ShaderNodeEmission"); _e.inputs["Color"].default_value = (0.75, 0.85, 1.0, 1); _e.inputs["Strength"].default_value = 3.0
    SKY.node_tree.links.new(_e.outputs[0], _n.new("ShaderNodeOutputMaterial").inputs[0])
    LAMP = emit("LampGlass", (0.3, 0.9, 0.4), 3.0)
    GOLDGLOW = emit("GoldGlow", (1.0, 0.65, 0.2), 6.0)
    INK = mat("Ink", (0.02, 0.02, 0.03), Roughness=0.3)[0]

    obj("Floor", box(X0, X1, -3, Y1, -0.1, 0), MARBLE)
    obj("Ceiling", box(X0, X1, -3, Y1, H, H + 0.2), WALL)
    # the back wall, with the round opening of the vault on the right
    vx, vz, vr = 2.6, 1.5, 1.3
    bw = bmesh.new()
    box(X0, vx - vr - 0.1, Y1, Y1 + 0.3, 0, H, bm=bw); box(vx + vr + 0.1, X1, Y1, Y1 + 0.3, 0, H, bm=bw)
    box(vx - vr - 0.1, vx + vr + 0.1, Y1, Y1 + 0.3, vz + vr + 0.1, H, bm=bw)
    obj("BackWall", bw, WALL)
    around = obj("VaultWall", box(vx - vr - 0.1, vx + vr + 0.1, Y1, Y1 + 0.3, 0, vz + vr + 0.1), WALL)   # round the opening
    hole = obj("VaultHole", lathe([(0, -1), (vr + 0.01, -1), (vr + 0.01, 1), (0, 1)], 64,
                                  Matrix.Translation((vx, Y1 + 0.15, vz)) @ Matrix.Rotation(math.pi/2, 4, 'X')), WALL)
    hole.hide_render = True
    cut = around.modifiers.new("Hole", 'BOOLEAN'); cut.operation = 'DIFFERENCE'; cut.object = hole
    obj("RightWall", box(X1, X1 + 0.3, -3, Y1, 0, H), WALL)
    lw = bmesh.new()                                # the left wall, with two tall windows
    edges = [(-3, -1.6), (-0.6, 1.6), (2.6, Y1)]
    for y0, y1 in edges:
        box(X0 - 0.3, X0, y0, y1, 0, H, bm=lw)
    for y0, y1 in ((-1.6, -0.6), (1.6, 2.6)):
        box(X0 - 0.3, X0, y0, y1, 0, 0.9, bm=lw); box(X0 - 0.3, X0, y0, y1, 3.4, H, bm=lw)
        obj("SkyPane", box(X0 - 0.62, X0 - 0.6, y0 - 1.2, y1 + 1.2, 0.0, H + 0.5), SKY)
        wf = bmesh.new()
        box(X0 - 0.2, X0 - 0.12, (y0 + y1)/2 - 0.03, (y0 + y1)/2 + 0.03, 0.9, 3.4, bm=wf)
        for z in (1.7, 2.55):
            box(X0 - 0.2, X0 - 0.12, y0, y1, z - 0.03, z + 0.03, bm=wf)
        obj("WindowBars", wf, IRON)
        light('AREA', (X0 - 0.45, (y0 + y1)/2, 3.0), 350, (1.0, 0.95, 0.85), size=1.0, aim=(X0 + 2.5, (y0 + y1)/2 + 0.8, 0))
    obj("LeftWall", lw, WALL)
    # wainscot and cornice round the walls
    tr = bmesh.new()
    box(X0, vx - vr - 0.2, Y1 - 0.06, Y1, 0, 0.9, bm=tr); box(vx + vr + 0.2, X1, Y1 - 0.06, Y1, 0, 0.9, bm=tr)
    box(X1 - 0.06, X1, -3, Y1, 0, 0.9, bm=tr)
    box(X0, X1, Y1 - 0.15, Y1, H - 0.3, H, bm=tr); box(X1 - 0.15, X1, -3, Y1, H - 0.3, H, bm=tr); box(X0, X0 + 0.15, -3, Y1, H - 0.3, H, bm=tr)
    obj("Wainscot", tr, DARKWOOD, bevel=0.01)

    # pilasters set into the side walls (half in the wall): between the windows on the left, the same on the right
    for x, y in ((X0, 0.5), (X0, 3.7), (X1, 0.5), (X1, -2.2), (X0, -2.2)):
        obj("Pilaster", lathe([(0, 0), (0.36, 0), (0.36, 0.12), (0.3, 0.2), (0.27, 0.3), (0.24, 3.85), (0.3, 3.95),
                               (0.36, 4.1), (0.36, H), (0, H)], 32, Matrix.Translation((x, y, 0))), PALE, smooth=True)

    # the counter across the back left, the grilles and teller windows over it, the clerks' things behind
    cx0, cx1, cy = -3.4, 1.0, 3.6
    ct = bmesh.new()
    box(cx0, cx1, cy - 0.35, cy + 0.35, 0, 1.05, bm=ct)
    for x in [cx0 + 0.55*k for k in range(1, 8)]:   # its panels
        box(x - 0.03, x + 0.03, cy - 0.37, cy - 0.35, 0.1, 0.95, bm=ct)
    obj("Counter", ct, DARKWOOD, bevel=0.01)
    obj("CounterTop", box(cx0 - 0.05, cx1 + 0.05, cy - 0.42, cy + 0.4, 1.05, 1.12), PALE, bevel=0.01)
    gr = bmesh.new()
    windows = (-2.55, -0.95, 0.4)                   # the gaps the tellers serve through
    x = cx0
    while x < cx1:
        if not any(abs(x - w) < 0.32 for w in windows):
            box(x - 0.012, x + 0.012, cy - 0.01, cy + 0.01, 1.12, 2.3, bm=gr)
        x += 0.09
    box(cx0, cx1, cy - 0.03, cy + 0.03, 2.3, 2.4, bm=gr); box(cx0, cx1, cy - 0.03, cy + 0.03, 1.12, 1.17, bm=gr)
    for w in windows:                               # an arch over each window
        box(w - 0.34, w + 0.34, cy - 0.03, cy + 0.03, 1.75, 1.8, bm=gr)
    obj("Grille", gr, GILT)
    obj("CounterBack", box(cx0, cx1, cy + 0.35, cy + 0.45, 2.4, 2.55), DARKWOOD)
    for k, w in enumerate(windows):                 # a brass sign over each window
        text(f"Teller{k}", ("DEPOSITS", "GEMS", "WITHDRAWALS")[k], (w, cy - 0.05, 2.0), 0.07, GILT)
    # on the counter: scales, coins, a ledger and ink
    sxs = -0.95
    sc_ = bmesh.new()
    lathe([(0, 0), (0.1, 0), (0.08, 0.03), (0.015, 0.05), (0.012, 0.42), (0, 0.42)], 16, Matrix.Translation((sxs, cy - 0.2, 1.12)), bm=sc_)
    box(sxs - 0.28, sxs + 0.28, cy - 0.21, cy - 0.19, 1.52, 1.54, bm=sc_)
    for dx in (-0.26, 0.26):
        box(sxs + dx - 0.003, sxs + dx + 0.003, cy - 0.203, cy - 0.197, 1.3, 1.53, bm=sc_)
        lathe([(0, 0), (0.09, 0.0), (0.1, 0.03), (0, 0.03)], 16, Matrix.Translation((sxs + dx, cy - 0.2, 1.28)), bm=sc_)
    obj("Scales", sc_, BRASS, smooth=True)
    coins = bmesh.new()
    for k, (x, n) in enumerate(((-2.75, 6), (-2.6, 9), (-2.4, 4), (0.15, 7), (0.32, 5), (-1.25, 3))):
        for j in range(n):
            lathe([(0, 0), (0.045, 0), (0.045, 0.012), (0, 0.012)], 16,
                  Matrix.Translation((x + rnd.uniform(-0.004, 0.004), cy - 0.25 + 0.02*(k % 2), 1.12 + 0.013*j)), bm=coins)
    obj("Coins", coins, GILT)
    obj("Ledger", box(0.45, 0.85, cy - 0.33, cy - 0.05, 1.12, 1.16, m=Matrix.Rotation(-0.1, 4, 'Z')), VELVET, bevel=0.005)
    obj("LedgerPages", box(0.47, 0.83, cy - 0.31, cy - 0.07, 1.16, 1.17, m=Matrix.Rotation(-0.1, 4, 'Z')), PAPER)
    obj("InkPot", lathe([(0, 0), (0.04, 0), (0.04, 0.05), (0.015, 0.07), (0, 0.07)], 14, Matrix.Translation((0.95, cy - 0.15, 1.12))), INK, smooth=True)
    obj("Quill", box(0.94, 0.96, cy - 0.155, cy - 0.145, 1.15, 1.4, m=Matrix.Rotation(0.25, 4, 'Y')), PAPER)
    # banker's lamps behind the counter
    for x in (-2.0, -0.2):
        obj("LampStem", lathe([(0, 0), (0.07, 0), (0.06, 0.02), (0.012, 0.03), (0.012, 0.3), (0, 0.3)], 16,
                              Matrix.Translation((x, cy + 0.2, 1.12))), BRASS, smooth=True)
        obj("LampShade", box(x - 0.16, x + 0.16, cy + 0.12, cy + 0.28, 1.4, 1.48), LAMP, bevel=0.03)
        light('POINT', (x, cy + 0.2, 1.36), 25, (1.0, 0.85, 0.55), size=0.08)
    # shelves of ledgers behind the counter
    sh = bmesh.new(); bk = bmesh.new()
    for z in (0.3, 0.9, 1.5, 2.1):
        box(cx0, cx1, Y1 - 0.45, Y1 - 0.05, z, z + 0.04, bm=sh)
        x = cx0 + 0.05
        while x < cx1 - 0.1:
            w = rnd.uniform(0.05, 0.1); h = rnd.uniform(0.34, 0.5)
            box(x, x + w, Y1 - 0.4, Y1 - 0.1, z + 0.04, z + 0.04 + h, bm=bk); x += w + 0.008
    obj("Shelves", sh, DARKWOOD)
    obj("Ledgers", bk, mottle("Bindings", (0.25, 0.08, 0.05), amount=0.6, scale=40, rough=0.6))

    # the vault: a thick round steel door swung open on its hinge, the gold inside lit up
    vd = bmesh.new()
    lathe([(0, -0.25), (vr - 0.05, -0.25), (vr, -0.2), (vr, 0.2), (vr - 0.05, 0.25), (0, 0.25)], 64, bm=vd)
    vdo = obj("VaultDoor", vd, STEEL, bevel=0.02)
    sp = bmesh.new()                                # its wheel and bolts on the face
    for k in range(6):
        a = math.tau*k/6
        box(-0.02, 0.02, -0.02, 0.02, 0.0, 0.55, bm=sp, m=Matrix.Translation((0, 0, 0.3)) @ Matrix.Rotation(a, 4, 'X') @ Matrix.Rotation(math.pi/2, 4, 'X'))
    lathe([(0.5, 0.29), (0.56, 0.29), (0.56, 0.35), (0.5, 0.35)], 48, bm=sp)
    lathe([(0, 0.25), (0.1, 0.25), (0.1, 0.38), (0, 0.38)], 24, bm=sp)
    for k in range(16):
        a = math.tau*k/16
        lathe([(0, 0), (0.04, 0), (0.04, 0.05), (0, 0.05)], 12, Matrix.Translation((1.05*math.cos(a), 1.05*math.sin(a), 0.25)), bm=sp)
    spo = obj("VaultWheel", sp, BRASS, smooth=True)
    for o in (vdo, spo):                            # stand it up, the wheel on its outer face (-y, the room)
        o.rotation_euler = (math.pi/2, 0, 0)   # (local +z, the wheel, to -y)
    hinge = bpy.data.objects.new("Hinge", None); sc.collection.objects.link(hinge)
    hinge.location = (vx + vr, Y1 - 0.3, vz); hinge.rotation_euler = (0, 0, math.radians(40))   # (half open, swung out into the room)
    for o in (vdo, spo):
        o.parent = hinge; o.location = (-vr, 0, 0)
    obj("VaultRim", lathe([(vr + 0.02, -0.05), (vr + 0.18, -0.05), (vr + 0.18, 0.35), (vr + 0.02, 0.35)], 64,
                          Matrix.Translation((vx, Y1, vz)) @ Matrix.Rotation(math.pi/2, 4, 'X')), STEEL, smooth=True)
    # inside: a short tunnel, shelves and heaps of gold, glowing
    obj("VaultInside", lathe([(vr, 0), (vr, 1.6), (0, 1.6)], 48, Matrix.Translation((vx, Y1 + 0.2, vz)) @ Matrix.Rotation(-math.pi/2, 4, 'X')),
        mottle("VaultStone", (0.2, 0.18, 0.15), 0.2, 6), smooth=True)
    GOLDDARK = mat("GoldDark", (0.3, 0.2, 0.08), Metallic=1.0, Roughness=0.6)[0]
    heaps = [coin_heap(f"Heap{k}", vx + dx, Y1 + dy, vz - vr + 0.05, r_, h_, GILT, GOLDDARK)
             for k, (dx, dy, r_, h_) in enumerate(((-0.6, 0.7, 0.4, 0.42), (-0.1, 0.95, 0.38, 0.5), (-0.35, 1.45, 0.45, 0.62)))]
    for k in range(14):                             # gems lying on the heaps
        col, ior, cut = GEMS[k % 4]
        x, y = vx + rnd.uniform(-0.9, 0.2), Y1 + rnd.uniform(0.5, 1.4)
        z = max(hp(x, y) for hp in heaps)
        gem(f"Gem{k}", (x, y, z + 0.03), 0.05, col, ior, cut, (rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), rnd.uniform(0, math.tau)))
    bars = bmesh.new()
    for k in range(10):
        x = vx - 0.6 + 0.13*k
        box(x, x + 0.11, Y1 + 1.2, Y1 + 1.45, vz - 0.05 + 0.06*(k % 3), vz + 0.01 + 0.06*(k % 3), bm=bars)
    obj("GoldBars", bars, GILT, bevel=0.01)
    obj("BarShelf", box(vx - 0.75, vx + 0.75, Y1 + 1.15, Y1 + 1.5, vz - 0.1, vz - 0.05), DARKWOOD, bevel=0.005)
    light('POINT', (vx, Y1 + 0.7, vz + 0.5), 120, (1.0, 0.75, 0.4), size=0.4)
    obj("VaultGlow", ball((vx, Y1 + 1.7, vz), 0.05), GOLDGLOW)

    # the bank's name in gilt letters over the counter
    obj("NameBoard", box(cx0 + 0.2, cx1 - 0.2, Y1 - 0.06, Y1, 3.2, 3.75), DARKWOOD, bevel=0.01)
    text("Name", "FIRST NATIONAL BANK OF ULARN", (cx0/2 + cx1/2, Y1 - 0.08, 3.47), 0.2, GILT, extrude=0.015)
    # a chandelier, ropes on brass posts before the counter, a bench and a potted palm on the right
    # the chandelier: a ceiling rose, a chain down to a turned brass body, eight arms curving out and up to candle cups
    kx, ky, kz = -0.4, 1.8, 3.45                    # the middle of the body (high enough to clear the name board behind)
    def tube(pts, r, bm):
        for a_, b_ in zip(pts, pts[1:]):
            d = b_ - a_; m = Matrix.Translation(a_) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
            lathe([(r, 0), (r, d.length)], 10, m, bm=bm)
    ch = bmesh.new()
    lathe([(0.11, 0.001), (0.09, -0.04), (0.04, -0.1), (0.016, -0.12), (0, -0.12)], 24, Matrix.Translation((kx, ky, H)), bm=ch)   # canopy
    obj("Medallion", lathe([(0, 0.001), (0.45, 0.001), (0.45, -0.02), (0.39, -0.03), (0.35, -0.05), (0.24, -0.05), (0.2, -0.035),
                            (0.14, -0.035), (0.12, -0.05), (0, -0.05)], 48, Matrix.Translation((kx, ky, H))), PALE, smooth=True)
    lathe([(0.016, kz + 0.38), (0.016, H - 0.08)], 12, Matrix.Translation((kx, ky, 0)), bm=ch)   # the rod down from the rose
    for z in (H - 0.3, (H + kz)/2 + 0.2, kz + 0.5):                                               # knops on it
        ball((kx, ky, z), 0.035, (1, 1, 1.3), bm=ch, segs=16)
    lathe([(0, 0.4), (0.03, 0.4), (0.05, 0.3), (0.1, 0.18), (0.16, 0.06), (0.17, 0.0), (0.12, -0.08), (0.05, -0.14), (0.07, -0.2),
           (0.03, -0.3), (0, -0.32)], 24, Matrix.Translation((kx, ky, kz)), bm=ch)                                   # the body
    cups = []
    for k in range(8):
        a = math.tau*(k + 0.5)/8; ca, sa = math.cos(a), math.sin(a)   # (symmetric about the way we look)
        pts = [Vector((kx + r*ca, ky + r*sa, kz + z)) for r, z in
               ((0.14, -0.04), (0.3, -0.12), (0.45, -0.12), (0.57, -0.06), (0.63, 0.04), (0.64, 0.12))]
        tube(pts, 0.016, ch)
        cup = pts[-1]; cups.append(cup)
        lathe([(0, 0), (0.05, 0.0), (0.06, 0.03), (0.035, 0.035), (0, 0.035)], 14, Matrix.Translation(cup), bm=ch)   # drip pan
    obj("Chandelier", ch, GILT, smooth=True)
    cn, fl = bmesh.new(), bmesh.new()
    for cup in cups:
        lathe([(0, 0), (0.016, 0), (0.016, 0.13), (0, 0.13)], 10, Matrix.Translation(cup + Vector((0, 0, 0.035))), bm=cn)
        lathe([(0, 0), (0.012, 0.012), (0.008, 0.03), (0, 0.05)], 10, Matrix.Translation(cup + Vector((0, 0, 0.17))), bm=fl)
    obj("ChandelierCandles", cn, WAX)
    obj("ChandelierFlames", fl, CANDLE)
    light('POINT', (kx, ky, kz + 0.2), 140, (1.0, 0.75, 0.45), size=0.7)
    posts = bmesh.new()
    for x in (-3.0, -1.8, -0.6, 0.6):
        lathe([(0, 0), (0.12, 0), (0.1, 0.04), (0.03, 0.06), (0.025, 0.95), (0.05, 1.0), (0, 1.05)], 16, Matrix.Translation((x, 2.4, 0)), bm=posts)
    obj("RopePosts", posts, BRASS, smooth=True)
    rope = bmesh.new()
    for x0 in (-3.0, -1.8, -0.6):
        pts = [Vector((x0 + 1.2*k/12, 2.4, 0.92 - 0.18*math.sin(math.pi*k/12))) for k in range(13)]
        for a_, b_ in zip(pts, pts[1:]):
            d = b_ - a_; m = Matrix.Translation(a_) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
            lathe([(0.025, 0), (0.025, d.length)], 10, m, bm=rope)
    obj("Rope", rope, VELVET, smooth=True)
    bn = bmesh.new()
    box(1.9, 3.7, 0.2, 0.7, 0.45, 0.52, bm=bn)
    for x in (2.0, 3.55):
        box(x, x + 0.1, 0.25, 0.65, 0, 0.45, bm=bn)
    box(1.9, 3.7, 0.62, 0.7, 0.52, 1.0, bm=bn)
    obj("Bench", bn, DARKWOOD, bevel=0.01)
    obj("Pot", lathe([(0, 0), (0.25, 0), (0.32, 0.5), (0.35, 0.55), (0, 0.55)], 24, Matrix.Translation((-3.6, 4.2, 0))), CERAMIC, smooth=True)
    leaves = bmesh.new()
    for k in range(9):
        a = math.tau*k/9; t = bmesh.new(); bmesh.ops.create_uvsphere(t, u_segments=8, v_segments=6, radius=1)
        t.transform(Matrix.Translation((-3.6 + 0.45*math.cos(a), 4.2 + 0.45*math.sin(a), 1.3)) @ Matrix.Rotation(a, 4, 'Z')
                    @ Matrix.Rotation(0.7, 4, 'Y') @ Matrix.Diagonal((0.55, 0.12, 0.03, 1)))
        merge(leaves, t)
    obj("Palm", leaves, mottle("Leaf", (0.06, 0.16, 0.04), 0.3, 8), smooth=True)
    obj("PalmStem", lathe([(0.05, 0), (0.04, 1.3), (0, 1.3)], 10, Matrix.Translation((-3.6, 4.2, 0.5))), FURN)

    light('AREA', (0, -2.5, 3.8), 15, (1.0, 0.92, 0.8), size=5, aim=(0, 3, 1))   # fill
    camera((0.0, -5.6, 1.75), (0.0, 5.0, 1.75), 24)   # (level, and long enough not to stretch the chandelier at the top)

def rough(bm, axis, amp, freq=1.2, seed=0):
    """Pushes a grid's verts along axis (0 x, 1 y, 2 z) by a few sines: rough-hewn rock."""
    r = random.Random(seed); waves = [(r.uniform(0.5, 1.5)*freq, r.uniform(0.5, 1.5)*freq, r.uniform(0, math.tau), r.uniform(0.4, 1)) for _ in range(6)]
    o = [k for k in range(3) if k != axis]
    for v in bm.verts:
        a, b = v.co[o[0]], v.co[o[1]]
        v.co[axis] += amp*sum(w*math.sin(fa*a*(1 + k*0.7) + fb*b*(1 + k*0.5) + ph) for k, (fa, fb, ph, w) in enumerate(waves))/3
    return bm

def grid(a0, a1, b0, b1, axis, at, n=40):
    """A flat grid across a0..a1, b0..b1 (the other two axes, in order) at axis = at."""
    bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=n, y_segments=n, size=0.5)
    for v in bm.verts:
        a, b = a0 + (v.co.x + 0.5)*(a1 - a0), b0 + (v.co.y + 0.5)*(b1 - b0)
        v.co = Vector({0: (at, a, b), 1: (a, at, b), 2: (a, b, at)}[axis])
    return bm

def branch():
    """The 8th-level branch office of the bank, down in the dungeon: a rough-hewn rock chamber shored up with timbers,
    a counter knocked together from planks behind a few crooked iron bars, a hand-painted sign, an iron-bound chest
    with what gold there is, torches in sconces, a lantern, barrels and crates.  Back wall y = 3.4."""
    X0, X1, Y1, H = -3.0, 3.0, 3.4, 2.8
    ROCK = rock_material("CaveRock", (0.42, 0.37, 0.31), scale=0.7)[0]
    FLOORROCK = rock_material("CaveFloor", (0.3, 0.27, 0.23), scale=0.9)[0]
    OLDWOOD = wood_material("OldWood", (0.09, 0.06, 0.035), axis="X", roughness=0.9)
    POSTWOOD = wood_material("PostWood", (0.08, 0.05, 0.03), axis="Z", roughness=0.9)
    RUST = mottle("Rust", (0.12, 0.07, 0.04), amount=0.5, scale=25, rough=0.75, bump=0.3)
    PAINT = mottle("Paint", (0.75, 0.68, 0.5), amount=0.25, scale=30, rough=0.9)
    GILT = mat("DullGold", (0.9, 0.62, 0.25), Metallic=1.0, Roughness=0.35)[0]
    GOLDDARK = mat("GoldDark", (0.3, 0.2, 0.08), Metallic=1.0, Roughness=0.6)[0]
    BONE = mottle("Bone", (0.6, 0.55, 0.45), amount=0.2, scale=12, rough=0.8)

    obj("Floor", rough(grid(X0 - 0.5, X1 + 0.5, -5, Y1 + 0.5, 2, 0.0, 60), 2, 0.025, 2.5, 1), FLOORROCK, smooth=True)
    obj("BackWall", rough(grid(X0 - 0.5, X1 + 0.5, -0.2, H + 0.4, 1, Y1, 50), 1, 0.12, 1.3, 2), ROCK, smooth=True)
    obj("LeftWall", rough(grid(-5, Y1 + 0.3, -0.2, H + 0.4, 0, X0, 60), 0, 0.15, 1.1, 3), ROCK, smooth=True)
    obj("RightWall", rough(grid(-5, Y1 + 0.3, -0.2, H + 0.4, 0, X1, 60), 0, 0.15, 1.1, 4), ROCK, smooth=True)
    obj("Ceiling", rough(grid(X0 - 0.5, X1 + 0.5, -5, Y1 + 0.5, 2, H, 60), 2, 0.12, 1.0, 5), ROCK, smooth=True)
    # the timbers shoring it up: posts against the side walls and a cap beam across, twice
    tb = bmesh.new()
    for y in (0.2, 2.6):
        for x in (X0 + 0.25, X1 - 0.25):
            box(x - 0.11, x + 0.11, y - 0.11, y + 0.11, 0, H - 0.25, bm=tb, m=Matrix.Rotation(rnd.uniform(-0.02, 0.02), 4, 'Y'))
        box(X0 - 0.1, X1 + 0.1, y - 0.13, y + 0.13, H - 0.27, H - 0.03, bm=tb)
    obj("Timbers", tb, POSTWOOD, bevel=0.02)

    # the counter: planks nailed upright to a frame, a plank top, across the back left
    cx0, cx1, cy = -2.3, 0.7, 2.25
    ct = bmesh.new()
    x = cx0
    while x < cx1 - 0.01:
        w = min(rnd.uniform(0.17, 0.24), cx1 - x)
        box(x + 0.006, x + w - 0.006, cy - 0.3, cy - 0.26, 0, rnd.uniform(0.94, 0.98), bm=ct,
            m=Matrix.Rotation(rnd.uniform(-0.01, 0.01), 4, 'Y')); x += w
    box(cx0, cx1, cy + 0.2, cy + 0.26, 0, 0.98, bm=ct)
    for x in (cx0, cx1 - 0.06):
        box(x, x + 0.06, cy - 0.3, cy + 0.26, 0, 0.98, bm=ct)
    obj("CounterPlanks", ct, OLDWOOD, bevel=0.005)
    tp = bmesh.new()
    for k in range(3):
        box(cx0 - 0.05, cx1 + 0.05, cy - 0.36 + 0.21*k, cy - 0.16 + 0.21*k, 0.98, 1.03, bm=tp,
            m=Matrix.Rotation(rnd.uniform(-0.008, 0.008), 4, 'X'))
    obj("CounterTop", tp, OLDWOOD, bevel=0.006)
    # a few iron bars over it, not quite straight, with a gap to be served through
    br = bmesh.new()
    x = cx0 + 0.05
    while x < cx1:
        if abs(x - (-0.8)) > 0.28:
            box(x - 0.012, x + 0.012, cy - 0.012, cy + 0.012, 1.03, 2.05, bm=br,
                m=Matrix.Translation((x, cy, 1.5)) @ Matrix.Rotation(rnd.uniform(-0.03, 0.03), 4, 'Y') @ Matrix.Translation((-x, -cy, -1.5)))
        x += 0.2
    for z in (1.4, 2.0):
        box(cx0, cx1, cy - 0.015, cy + 0.015, z, z + 0.04, bm=br)
    obj("Bars", br, RUST)
    # on the counter: a battered ledger, a little stack of coins, a lantern
    obj("Ledger", box(-0.55, -0.15, cy - 0.3, cy - 0.05, 1.03, 1.07, m=Matrix.Rotation(0.15, 4, 'Z')),
        mottle("OldLeather", (0.12, 0.07, 0.04), 0.3, 15, 0.8), bevel=0.004)
    obj("LedgerPages", box(-0.53, -0.17, cy - 0.28, cy - 0.07, 1.07, 1.075, m=Matrix.Rotation(0.15, 4, 'Z')), PAPER)
    coins = bmesh.new()
    for k, (x, n) in enumerate(((-1.7, 4), (-1.58, 2))):
        for j in range(n):
            lathe([(0, 0), (0.04, 0), (0.04, 0.011), (0, 0.011)], 14,
                  Matrix.Translation((x + rnd.uniform(-0.006, 0.006), cy - 0.25, 1.03 + 0.012*j)), bm=coins)
    obj("Coins", coins, GILT)
    lx, ly = 0.35, cy - 0.15                        # the lantern: a tin box with horn windows, a candle in it
    ln = bmesh.new()
    box(lx - 0.09, lx + 0.09, ly - 0.09, ly + 0.09, 1.03, 1.06, bm=ln); box(lx - 0.1, lx + 0.1, ly - 0.1, ly + 0.1, 1.3, 1.33, bm=ln)
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        box(lx + 0.085*dx - 0.01, lx + 0.085*dx + 0.01, ly + 0.085*dy - 0.01, ly + 0.085*dy + 0.01, 1.06, 1.3, bm=ln)
    lathe([(0.06, 1.33), (0, 1.42)], 4, Matrix.Translation((lx, ly, 0)) @ Matrix.Rotation(math.pi/4, 4, 'Z'), bm=ln)
    lathe([(0.03, 0), (0.035, 0.03), (0.03, 0.06), (0.026, 0.03)], 12, Matrix.Translation((lx, ly, 1.42)) @ Matrix.Rotation(math.pi/2, 4, 'X'), bm=ln)
    obj("Lantern", ln, RUST)
    obj("LanternHorn", box(lx - 0.08, lx + 0.08, ly - 0.08, ly + 0.08, 1.06, 1.3),
        mat("Horn", (0.9, 0.7, 0.4), Roughness=0.6, **{"Transmission Weight": 0.6})[0])
    obj("LanternCandle", lathe([(0, 0), (0.018, 0), (0.018, 0.1), (0, 0.1)], 10, Matrix.Translation((lx, ly, 1.06))), WAX)
    obj("LanternFlame", lathe([(0, 0), (0.012, 0.012), (0.008, 0.03), (0, 0.05)], 10, Matrix.Translation((lx, ly, 1.17))), CANDLE)
    light('POINT', (lx, ly - 0.02, 1.2), 15, (1.0, 0.65, 0.3), size=0.06)
    # behind the counter: a rickety shelf of ledgers on the rock, a stool
    sh = bmesh.new(); bk = bmesh.new()
    for z in (1.15, 1.7):
        box(cx0 + 0.3, cx1 - 0.4, Y1 - 0.35, Y1 - 0.05, z, z + 0.04, bm=sh)
        x = cx0 + 0.35
        while x < cx1 - 0.6:
            w = rnd.uniform(0.06, 0.11); h = rnd.uniform(0.25, 0.36); lean = rnd.uniform(-0.1, 0.1) if rnd.random() < 0.3 else 0
            box(x, x + w, Y1 - 0.3, Y1 - 0.1, z + 0.04, z + 0.04 + h, bm=bk,
                m=Matrix.Translation((x, 0, z + 0.04)) @ Matrix.Rotation(lean, 4, 'Y') @ Matrix.Translation((-x, 0, -z - 0.04))); x += w + 0.02
        for x in (cx0 + 0.4, cx1 - 0.5):
            box(x - 0.02, x + 0.02, Y1 - 0.2, Y1 - 0.05, z - 0.25, z, bm=sh)
    obj("Shelf", sh, OLDWOOD)
    obj("Ledgers", bk, mottle("Bindings", (0.16, 0.08, 0.05), amount=0.6, scale=40, rough=0.8))
    st = bmesh.new()
    lathe([(0, 0.62), (0.2, 0.62), (0.2, 0.67), (0, 0.67)], 16, Matrix.Translation((-1.4, 2.9, 0)), bm=st)
    for k in range(3):
        a = math.tau*k/3 + 0.3
        box(-0.025, 0.025, -0.025, 0.025, 0, 0.64, bm=st,
            m=Matrix.Translation((-1.4 + 0.15*math.cos(a), 2.9 + 0.15*math.sin(a), 0)) @ Matrix.Rotation(0.12, 4, Vector((-math.sin(a), math.cos(a), 0))))
    obj("Stool", st, OLDWOOD)

    # the sign: a plank nailed up over the counter, the name painted on by hand, and the branch's on a board hung under it
    sg = obj("Sign", box(-1.55, 1.55, -0.02, 0.02, -0.22, 0.22), OLDWOOD, bevel=0.01)
    sg.location = (cx0/2 + cx1/2, Y1 - 0.2, 2.45); sg.rotation_euler = (0, math.radians(1.5), 0)
    t = text("SignName", "FIRST NATIONAL BANK OF ULARN", (0, -0.025, 0.03), 0.17, PAINT, extrude=0.002); t.parent = sg
    t = text("SignBranch", "8th level branch", (0, -0.025, -0.13), 0.1, PAINT, extrude=0.002); t.parent = sg

    # the chest on the right: iron-bound planks, the lid thrown back, what gold there is inside, a few gems
    kx, ky, kw, kd, kh = 1.75, 2.55, 1.0, 0.6, 0.55
    ch = bmesh.new()
    box(kx - kw/2, kx + kw/2, ky - kd/2, ky - kd/2 + 0.05, 0, kh, bm=ch); box(kx - kw/2, kx + kw/2, ky + kd/2 - 0.05, ky + kd/2, 0, kh, bm=ch)
    box(kx - kw/2, kx - kw/2 + 0.05, ky - kd/2, ky + kd/2, 0, kh, bm=ch); box(kx + kw/2 - 0.05, kx + kw/2, ky - kd/2, ky + kd/2, 0, kh, bm=ch)
    box(kx - kw/2, kx + kw/2, ky - kd/2, ky + kd/2, 0, 0.08, bm=ch)
    obj("Chest", ch, OLDWOOD, bevel=0.008)
    bd = bmesh.new()
    for x in (kx - kw/2 + 0.12, kx + kw/2 - 0.12):
        box(x - 0.035, x + 0.035, ky - kd/2 - 0.01, ky + kd/2 + 0.01, 0, kh + 0.005, bm=bd)
    box(kx - kw/2 - 0.01, kx + kw/2 + 0.01, ky - kd/2 - 0.01, ky + kd/2 + 0.01, kh - 0.06, kh - 0.01, bm=bd)
    box(kx - 0.06, kx + 0.06, ky - kd/2 - 0.02, ky - kd/2, kh - 0.18, kh - 0.02, bm=bd)   # the hasp
    obj("ChestBands", bd, RUST, bevel=0.004)
    lid = bmesh.new()
    box(-kw/2, kw/2, -kd, 0, 0, 0.06, bm=lid)
    for x in (-kw/2 + 0.12, kw/2 - 0.12):
        box(x - 0.035, x + 0.035, -kd - 0.01, 0, 0.06, 0.07, bm=lid)
    lo = obj("ChestLid", lid, OLDWOOD, bevel=0.008)
    lo.location = (kx, ky + kd/2, kh); lo.rotation_euler = (math.radians(-105), 0, 0)
    obj("ChestFill", box(kx - kw/2 + 0.05, kx + kw/2 - 0.05, ky - kd/2 + 0.05, ky + kd/2 - 0.05, 0.08, kh - 0.03), mat("CoinBed", (0.6, 0.42, 0.15), Metallic=1.0, Roughness=0.5)[0])
    def mound(x, y): return kh - 0.03 + 0.09*math.exp(-((x - kx + 0.1)/0.3)**2 - ((y - ky)/0.25)**2)   # (heaped up a little)
    cc = bmesh.new()
    for _ in range(420):                            # coins strewn over it, every which way
        x, y = kx + rnd.uniform(-kw/2 + 0.08, kw/2 - 0.08), ky + rnd.uniform(-kd/2 + 0.08, kd/2 - 0.08)
        n_ = Vector((rnd.gauss(0, 0.3), rnd.gauss(0, 0.3), 1)).normalized()
        lathe([(0, -0.004), (0.035, -0.004), (0.035, 0.004), (0, 0.004)], 14,
              Matrix.Translation((x, y, mound(x, y) + rnd.uniform(0, 0.012))) @ n_.to_track_quat('Z', 'Y').to_matrix().to_4x4(), bm=cc)
    obj("ChestCoins", cc, GILT)
    heaps = [lambda x, y: mound(x, y) + 0.01]
    for k in range(3):
        col, ior, cut = GEMS[k]
        x, y = kx + rnd.uniform(-0.3, 0.3), ky + rnd.uniform(-0.1, 0.1)
        gem(f"Gem{k}", (x, y, max(hp(x, y) for hp in heaps) + 0.03), 0.045, col, ior, cut,
            (rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), rnd.uniform(0, math.tau)))
    # a padlock dropped in front of it
    pl = bmesh.new()
    box(-0.05, 0.05, -0.02, 0.02, 0, 0.08, bm=pl)
    lathe([(0.035, 0), (0.045, 0)], 16, Matrix.Translation((0, 0, 0.08)) @ Matrix.Rotation(math.pi/2, 4, 'X') @ Matrix.Diagonal((1, 1, 0.02/0.0001*0.0001, 1)), bm=pl)
    po = obj("Padlock", pl, RUST); po.location = (kx - 0.3, ky - kd/2 - 0.25, 0.02); po.rotation_euler = (math.pi/2, 0, 0.6)

    # barrels and crates heaped on the left, a skull by the wall
    def barrel(name, x, y, z=0, h=0.9, r=0.32, lying=False):
        m = Matrix.Translation((x, y, z)) @ (Matrix.Rotation(math.pi/2, 4, 'Y') @ Matrix.Translation((-r, 0, -h/2)) if lying else Matrix())
        prof = [(0, 0)] + [(r*(0.86 + 0.14*math.sin(math.pi*k/8)), h*k/8) for k in range(9)] + [(0, h)]
        obj(name, lathe(prof, 24, m), POSTWOOD, smooth=True)
        hp = bmesh.new()
        for zz in (0.08, 0.3, 0.7, 0.92):
            rr = r*(0.86 + 0.14*math.sin(math.pi*zz)) + 0.006
            lathe([(rr, h*zz - 0.025), (rr, h*zz + 0.025)], 24, m, bm=hp)
        obj(name + "Hoops", hp, RUST, smooth=True)
    barrel("Barrel1", -2.45, 1.4)
    barrel("Barrel2", -2.0, 1.75, h=0.8, r=0.28)
    barrel("Barrel3", -2.3, 0.85, z=0.0, h=0.85, r=0.3, lying=True)
    cr_ = bmesh.new()
    for x, y, z, s, a in ((2.45, 1.2, 0, 0.55, 0.2), (2.4, 1.25, 0.55, 0.42, -0.15), (2.0, 0.6, 0, 0.45, 0.5)):
        box(-s/2, s/2, -s/2, s/2, 0, s, bm=cr_, m=Matrix.Translation((x, y, z)) @ Matrix.Rotation(a, 4, 'Z'))
    obj("Crates", cr_, OLDWOOD, bevel=0.015)
    sk = bmesh.new()
    ball((0, 0.02, 0.1), 0.1, (0.82, 1.05, 0.9), bm=sk); ball((0, -0.07, 0.045), 0.06, (0.85, 0.75, 0.6), bm=sk)
    so = obj("Skull", sk, BONE, smooth=True); so.location = (-2.35, -0.2, 0); so.rotation_euler = (0, 0, -0.35)
    ey = bmesh.new()                                # eye sockets and the nose hole, dark
    for dx, dz, r in ((-0.035, 0.1, 0.028), (0.035, 0.1, 0.028), (0, 0.06, 0.014)):
        ball((dx, -0.075, dz), r, (1, 0.6, 1.1 if r < 0.02 else 1), bm=ey)
    eo = obj("SkullHoles", ey, mat("Hole", (0.01, 0.008, 0.006), Roughness=1)[0], smooth=True); eo.parent = so
    sh_ = bmesh.new()
    for k in range(4):
        a = rnd.uniform(0, math.pi)
        lathe([(0.015, 0), (0.015, 0.3)], 8, Matrix.Translation((-2.5 + 0.12*k, -0.6 + rnd.uniform(-0.1, 0.1), 0.02)) @ Matrix.Rotation(math.pi/2, 4, Vector((math.cos(a), math.sin(a), 0))), bm=sh_)
    obj("Bones", sh_, BONE, smooth=True)

    # torches in iron brackets: on the side walls and on the back by the chest
    for k, (x, y, z, face) in enumerate(((X0 + 0.12, 1.4, 1.85, 1), (X1 - 0.12, 1.4, 1.85, -1))):
        tq = bmesh.new()
        box(x - 0.06*face, x + 0.0, y - 0.06, y + 0.06, z - 0.25, z + 0.05, bm=tq)
        tq_ = obj(f"Bracket{k}", tq, RUST)
        stick = obj(f"Torch{k}", lathe([(0.025, 0), (0.03, 0.4), (0.04, 0.45), (0, 0.47)], 10,
                                     Matrix.Translation((x + 0.1*face, y, z - 0.25)) @ Matrix.Rotation(0.3*face, 4, 'Y')), POSTWOOD)
        tip = Vector((x + 0.1*face + 0.45*math.sin(0.3*face), y, z - 0.25 + 0.45*math.cos(0.3)))
        flame_sheet(f"TorchFire{k}", tip - Vector((0, 0, 0.03)), 0.22, 0.42, 1.7*k, toward=(0, -4.0, 1.5))
        light('POINT', tip + Vector((0.1*face, 0, 0.15)), 110, (1.0, 0.5, 0.15), size=0.12)
    bx, by, bz = 1.0, Y1 - 0.1, 1.75                 # one on the back wall between the counter and the chest
    obj("BracketB", box(bx - 0.05, bx + 0.05, by - 0.08, by + 0.02, bz - 0.25, bz + 0.05), RUST)
    obj("TorchB", lathe([(0.025, 0), (0.03, 0.4), (0.04, 0.45), (0, 0.47)], 10,
                        Matrix.Translation((bx, by - 0.1, bz - 0.25)) @ Matrix.Rotation(-0.3, 4, 'X')), POSTWOOD)
    tip = Vector((bx, by - 0.1 - 0.45*math.sin(0.3), bz - 0.25 + 0.45*math.cos(0.3)))
    flame_sheet("TorchFireB", tip - Vector((0, 0, 0.03)), 0.22, 0.42, 3.3, toward=(0, -4.0, 1.5))
    light('POINT', tip + Vector((0, -0.15, 0.15)), 90, (1.0, 0.5, 0.15), size=0.12)
    light('POINT', (kx, ky - 0.25, kh + 0.6), 25, (1.0, 0.7, 0.35), size=0.3)        # (a glint off the gold)
    light('AREA', (0, -2.5, 2.6), 14, (1.0, 0.7, 0.45), size=3, aim=(0, 2, 0.8))   # (a little fill, warm)
    camera((0.0, -4.0, 1.45), (0.0, 3.4, 1.45), 22)

def shop():
    """The Ularn Thrift Shoppe by day: a timbered shop crammed with stock.  Shelves of potions, scrolls and books
    behind the counter, swords, an axe and shields on the left wall, spears in a barrel, a suit of armour on a stand
    by the window, oil lamps hanging from the beams, the shop's name painted over the shelves.  Back wall y = 4."""
    X0, X1, Y1, H = -3.6, 3.6, 4.0, 3.0
    STEEL = mat("Steel", (0.5, 0.5, 0.52), Metallic=1.0, Roughness=0.28)[0]
    CHAIN = mottle("Chain", (0.32, 0.32, 0.34), amount=0.5, scale=220, rough=0.45, bump=0.8)
    next(n for n in CHAIN.node_tree.nodes if n.type == 'BSDF_PRINCIPLED').inputs["Metallic"].default_value = 0.9
    CORK = mottle("Cork", (0.35, 0.22, 0.12), amount=0.3, scale=40, rough=0.9)
    PAINT = mottle("SignPaint", (0.85, 0.7, 0.35), amount=0.15, scale=30, rough=0.6)
    RED = mottle("ShieldRed", (0.4, 0.05, 0.03), amount=0.2, scale=8, rough=0.6)
    BLUE = mottle("ShieldBlue", (0.05, 0.1, 0.3), amount=0.2, scale=8, rough=0.6)
    SKY = bpy.data.materials.new("Sky"); SKY.use_nodes = True; _n = SKY.node_tree.nodes; _n.clear()
    _e = _n.new("ShaderNodeEmission"); _e.inputs["Color"].default_value = (0.75, 0.85, 1.0, 1); _e.inputs["Strength"].default_value = 3.0
    SKY.node_tree.links.new(_e.outputs[0], _n.new("ShaderNodeOutputMaterial").inputs[0])
    POTIONS = [mat(f"Potion{k}", c, Roughness=0.05, IOR=1.45, **{"Transmission Weight": 1.0})[0] for k, c in enumerate(
        ((0.8, 0.05, 0.05), (0.1, 0.25, 0.9), (0.1, 0.7, 0.15), (0.9, 0.5, 0.05), (0.5, 0.1, 0.7), (0.85, 0.85, 0.8)))]

    obj("Floor", box(X0, X1, -5, Y1, -0.1, 0), FLOOR)
    obj("Ceiling", box(X0, X1, -5, Y1, H, H + 0.1), BEAM)
    bw = bmesh.new()                                # the back wall, a window in it on the right
    wx0, wx1, wz0, wz1 = 2.0, 3.1, 1.0, 2.4
    box(X0, wx0, Y1, Y1 + 0.25, 0, H, bm=bw); box(wx1, X1, Y1, Y1 + 0.25, 0, H, bm=bw)
    box(wx0, wx1, Y1, Y1 + 0.25, 0, wz0, bm=bw); box(wx0, wx1, Y1, Y1 + 0.25, wz1, H, bm=bw)
    obj("BackWall", bw, PLASTER)
    obj("SkyPane", box(wx0 - 1.0, wx1 + 1.0, Y1 + 0.6, Y1 + 0.62, wz0 - 1, wz1 + 1), SKY)
    wf = bmesh.new()
    box(wx0 - 0.06, wx1 + 0.06, Y1 - 0.04, Y1 + 0.04, wz0 - 0.08, wz0, bm=wf); box(wx0 - 0.06, wx1 + 0.06, Y1 - 0.04, Y1 + 0.04, wz1, wz1 + 0.06, bm=wf)
    for x in (wx0 - 0.06, (wx0 + wx1)/2 - 0.025, wx1):
        box(x, x + 0.06 if x != (wx0 + wx1)/2 - 0.025 else x + 0.05, Y1 + 0.08, Y1 + 0.13, wz0, wz1, bm=wf)
    box(wx0, wx1, Y1 + 0.08, Y1 + 0.13, (wz0 + wz1)/2 - 0.025, (wz0 + wz1)/2 + 0.025, bm=wf)
    obj("WindowFrame", wf, TIMBER, bevel=0.005)
    light('AREA', ((wx0 + wx1)/2, Y1 + 0.45, (wz0 + wz1)/2 + 0.2), 400, (1.0, 0.95, 0.85), size=1.2, aim=(1.0, 1.0, 0))
    obj("LeftWall", box(X0 - 0.25, X0, -5, Y1, 0, H), PLASTER)
    obj("RightWall", box(X1, X1 + 0.25, -5, Y1, 0, H), PLASTER)
    tb = bmesh.new()                                # beams and posts
    for y in (-0.6, 1.2):
        box(X0, X1, y - 0.12, y + 0.12, H - 0.25, H, bm=tb)
    for x, y in ((X0 + 0.1, 1.2), (X1 - 0.1, 1.2), (X0 + 0.1, Y1 - 0.1), (X1 - 0.1, Y1 - 0.1)):
        box(x - 0.1, x + 0.1, y - 0.1, y + 0.1, 0, H, bm=tb)
    obj("Timbers", tb, TIMBER, bevel=0.015)

    # the shelves behind the counter: jars at the bottom, two of potions, scrolls in cubbies, books on top
    sx0, sx1, sy = -3.3, 1.6, Y1 - 0.45
    sh = bmesh.new()
    levels = (0.3, 0.85, 1.35, 1.85, 2.35)
    for z in levels:
        box(sx0, sx1, sy, Y1, z, z + 0.04, bm=sh)
    for x in [sx0 + (sx1 - sx0)*k/5 for k in range(6)]:
        box(x - 0.03, x + 0.03, sy, Y1, 0, 2.8, bm=sh)
    obj("Shelves", sh, FURN, bevel=0.005)
    pots = [bmesh.new() for _ in POTIONS]; corks = bmesh.new()
    for z in (0.85, 1.35):
        x = sx0 + 0.1
        while x < sx1 - 0.1:
            if abs(x - round((x - sx0)/((sx1 - sx0)/5))*((sx1 - sx0)/5) - sx0) < 0.08: x += 0.06; continue
            r = rnd.uniform(0.04, 0.07); h = rnd.uniform(0.2, 0.36); k = rnd.randrange(len(POTIONS))
            prof = rnd.choice(([(0, 0), (r, 0), (r, 0.6*h), (0.35*r, 0.78*h), (0.3*r, h), (0, h)],
                               [(0, 0), (0.6*r, 0), (r, 0.25*h), (r*0.95, 0.5*h), (0.32*r, 0.72*h), (0.3*r, h), (0, h)],
                               [(0, 0), (r, 0), (r*0.8, 0.5*h), (0.3*r, 0.8*h), (0.3*r, h), (0, h)]))
            m_ = Matrix.Translation((x + r, sy + rnd.uniform(0.12, 0.3), z + 0.04))
            lathe(prof, 16, m_, bm=pots[k])
            lathe([(0, h), (0.3*r + 0.004, h), (0.3*r + 0.004, h + 0.04), (0, h + 0.04)], 10, m_, bm=corks)
            x += 2*r + rnd.uniform(0.01, 0.04)
    for k, b_ in enumerate(pots):
        obj(f"Potions{k}", b_, POTIONS[k], smooth=True)
    obj("Corks", corks, CORK)
    sc_, ties = bmesh.new(), bmesh.new()            # scrolls, rolled, their ends to us, piled in each cubby
    for c in range(5):
        cx = sx0 + (sx1 - sx0)*(c + 0.5)/5
        for row, n in ((0, 3), (1, 3), (2, 2)):     # (lying across, a little askew, so they read as scrolls)
            for j in range(n):
                for dy in (0.1, 0.28):
                    x = cx + (j - (n - 1)/2)*0.3 + rnd.uniform(-0.03, 0.03)
                    m_ = (Matrix.Translation((x, sy + dy, 1.85 + 0.04 + 0.046 + 0.085*row)) @ Matrix.Rotation(rnd.uniform(-0.15, 0.15), 4, 'Z')
                          @ Matrix.Rotation(math.pi/2, 4, 'Y'))
                    lathe([(0, -0.14), (0.045, -0.14), (0.045, 0.14), (0, 0.14)], 14, m_, bm=sc_)
                    lathe([(0.047, -0.015), (0.047, 0.015)], 14, m_, bm=ties)
    obj("Scrolls", sc_, mottle("Parchment", (0.62, 0.5, 0.32), amount=0.25, scale=12, rough=0.85), smooth=True)
    obj("ScrollTies", ties, mottle("Ribbon", (0.45, 0.04, 0.03), amount=0.2, scale=30, rough=0.7), smooth=True)
    bk = bmesh.new(); jars = bmesh.new()
    x = sx0 + 0.06
    while x < sx1 - 0.1:
        w = rnd.uniform(0.05, 0.1); h = rnd.uniform(0.3, 0.44)
        box(x, x + w, sy + 0.05, Y1 - 0.05, 2.39, 2.39 + h, bm=bk); x += w + 0.008
    for k in range(9):
        x = sx0 + 0.3 + k*0.53
        lathe([(0, 0), (0.12, 0), (0.15, 0.12), (0.13, 0.3), (0.09, 0.34), (0.1, 0.38), (0, 0.38)], 20, Matrix.Translation((x, sy + 0.22, 0.34)), bm=jars)
    obj("Books", bk, mottle("Bindings", (0.22, 0.1, 0.06), amount=0.7, scale=40, rough=0.6))
    obj("Jars", jars, CERAMIC, smooth=True)
    # the name painted on a board over the shelves
    obj("NameBoard", box(sx0 + 0.1, sx1 - 0.1, Y1 - 0.06, Y1 - 0.02, 2.8, 3.0), TIMBER)
    text("Name", "ULARN THRIFT SHOPPE", ((sx0 + sx1)/2, Y1 - 0.08, 2.9), 0.17, PAINT, extrude=0.004)

    # the counter, its things: a bell, a ledger, the warning, potions waiting to go back
    cx0, cx1, cy = -2.4, 0.9, 2.3
    obj("Counter", box(cx0, cx1, cy - 0.3, cy + 0.3, 0, 0.98), FURN, bevel=0.01)
    pn = bmesh.new()
    for x in [cx0 + (cx1 - cx0)*k/6 for k in range(1, 6)]:
        box(x - 0.025, x + 0.025, cy - 0.32, cy - 0.3, 0.08, 0.9, bm=pn)
    box(cx0, cx1, cy - 0.32, cy - 0.3, 0.08, 0.13, bm=pn); box(cx0, cx1, cy - 0.32, cy - 0.3, 0.85, 0.9, bm=pn)
    obj("CounterPanels", pn, TIMBER)
    obj("CounterTop", box(cx0 - 0.05, cx1 + 0.05, cy - 0.36, cy + 0.34, 0.98, 1.04), TIMBER, bevel=0.008)
    obj("Bell", lathe([(0, 0), (0.07, 0), (0.06, 0.02), (0.035, 0.08), (0.02, 0.1), (0.008, 0.1), (0.008, 0.13), (0.02, 0.14), (0, 0.15)],
                      20, Matrix.Translation((0.55, cy - 0.15, 1.04))), BRASS, smooth=True)
    obj("Ledger", box(-0.5, 0.0, cy - 0.28, cy + 0.05, 1.04, 1.07, m=Matrix.Rotation(-0.12, 4, 'Z')), LEATHER, bevel=0.004)
    obj("LedgerPages", box(-0.48, -0.02, cy - 0.26, cy + 0.03, 1.07, 1.08, m=Matrix.Rotation(-0.12, 4, 'Z')), PAPER)
    wb = obj("Warning", box(-0.45, 0.45, -0.015, 0.015, 0, 0.3), TIMBER, bevel=0.005)
    wb.location = (-1.55, cy - 0.1, 1.04); wb.rotation_euler = (math.radians(-12), 0, math.radians(8))
    for k, line in enumerate(("IF YOU BREAK 'EM", "YOU PAY FOR 'EM")):
        t = text(f"Warn{k}", line, (0, -0.02, 0.2 - 0.1*k), 0.075, PAINT, extrude=0.002); t.parent = wb
    for k, x in enumerate((0.2, 0.32)):
        obj(f"CounterPotion{k}", lathe([(0, 0), (0.05, 0), (0.05, 0.14), (0.018, 0.2), (0.018, 0.24), (0, 0.24)], 16,
                                       Matrix.Translation((x, cy - 0.05, 1.04))), POTIONS[k + 1], smooth=True)

    # the left wall: swords hung point down on pegs, an axe, two round shields above, spears in a barrel
    bs, bg, bh = bmesh.new(), bmesh.new(), bmesh.new()
    for k, y in enumerate((1.6, 2.0, 2.4, 2.8)):
        m = Matrix.Translation((X0 + 0.06, y, 0.75)) @ Matrix.Rotation(math.pi/2, 4, 'Z')
        bl = lathe([(0, 0), (0.035, 0.1), (0.03, 0.78), (0, 0.8)], 4); bl.transform(m @ Matrix.Diagonal((1, 0.18, 1, 1))); merge(bs, bl)
        box(-0.12, 0.12, -0.02, 0.02, 0.78, 0.82, bm=bs, m=m)
        lathe([(0.018, 0.82), (0.02, 0.98), (0, 0.98)], 10, m, bm=bh)
        ball(m @ Vector((0, 0, 1.0)), 0.03, bm=bg)
    obj("SwordSteel", bs, STEEL); obj("SwordGrips", bh, LEATHER, smooth=True); obj("SwordPommels", bg, BRASS, smooth=True)
    obj("WeaponBoard", box(X0, X0 + 0.04, 1.35, 3.05, 0.6, 1.95), FURN)
    ax = bmesh.new()
    am = Matrix.Translation((X0 + 0.07, 1.0, 0.8)) @ Matrix.Rotation(math.pi/2, 4, 'Z')
    lathe([(0.02, 0), (0.022, 0.95), (0, 0.97)], 10, am, bm=ax)
    obj("AxeHaft", ax, FURN)
    ah = bmesh.new()
    box(-0.02, 0.2, -0.012, 0.012, 0.78, 0.92, bm=ah, m=am); box(0.15, 0.24, -0.008, 0.008, 0.68, 1.02, bm=ah, m=am)
    obj("AxeHead", ah, STEEL, bevel=0.004)
    for k, (y, m_) in enumerate(((1.0, RED), (2.2, BLUE))):
        sm = Matrix.Translation((X0 + 0.05, y, 2.25)) @ Matrix.Rotation(math.pi/2, 4, 'Y')
        obj(f"Shield{k}", lathe([(0, -0.06), (0.36, -0.03), (0.36, 0.0), (0, 0.0)], 32, sm), m_, smooth=True)
        rim = lathe([(0.355, -0.035), (0.375, -0.035), (0.375, 0.005), (0.355, 0.005)], 32, sm)
        ball(sm @ Vector((0, 0, -0.06)), 0.08, (1, 1, 0.6), bm=rim)
        obj(f"ShieldRim{k}", rim, IRON, smooth=True)
    def barrel(name, x, y, h=0.8, r=0.3):
        m = Matrix.Translation((x, y, 0))
        prof = [(0, 0)] + [(r*(0.86 + 0.14*math.sin(math.pi*k/8)), h*k/8) for k in range(9)] + [(r*0.88, h), (r*0.88, h - 0.03), (0, h - 0.03)]
        obj(name, lathe(prof, 24, m), FURN, smooth=True)
        hp = bmesh.new()
        for zz in (0.08, 0.3, 0.7, 0.92):
            rr = r*(0.86 + 0.14*math.sin(math.pi*zz)) + 0.006
            lathe([(rr, h*zz - 0.025), (rr, h*zz + 0.025)], 24, m, bm=hp)
        obj(name + "Hoops", hp, IRON, smooth=True)
    barrel("SpearBarrel", -2.95, 0.3)
    sp_, tp_ = bmesh.new(), bmesh.new()
    for k in range(5):
        a = math.tau*k/5 + 0.4; d = Vector((0.12*math.cos(a), 0.12*math.sin(a), 0))
        lean = Matrix.Rotation(0.1, 4, Vector((-math.sin(a), math.cos(a), 0)))
        m = Matrix.Translation(Vector((-2.95, 0.3, 0.1)) + d) @ lean
        lathe([(0.016, 0), (0.016, 2.0 + 0.1*(k % 2)), (0, 2.0 + 0.1*(k % 2))], 8, m, bm=sp_)
        lathe([(0.02, 0), (0.035, 0.06), (0, 0.28)], 4, m @ Matrix.Translation((0, 0, 2.0 + 0.1*(k % 2))), bm=tp_)
    obj("SpearShafts", sp_, FURN); obj("SpearHeads", tp_, STEEL)

    # the right: a suit of armour on a stand by the window, a barrel of arrows, a pair of boots
    ax_, ay_ = 2.3, 1.9
    obj("ArmourPost", lathe([(0, 0), (0.25, 0), (0.25, 0.05), (0.03, 0.07), (0.03, 1.1), (0, 1.1)], 16, Matrix.Translation((ax_, ay_, 0))), FURN)
    tm = Matrix.Translation((ax_, ay_, 0.95)) @ Matrix.Rotation(-0.35, 4, 'Z')
    pl = lathe([(0, 0.08), (0.17, 0.08), (0.2, 0.15), (0.19, 0.35), (0.23, 0.5), (0.24, 0.6), (0.15, 0.7), (0.07, 0.72), (0, 0.72)], 28,
               tm @ Matrix.Diagonal((1.25, 0.75, 1, 1)))                                         # a breastplate
    lathe([(0.09, 0.7), (0.1, 0.78), (0, 0.78)], 20, tm, bm=pl)                                  # gorget
    obj("Skirt", lathe([(0.18, 0.1), (0.26, -0.32), (0.0, -0.32)], 28, tm @ Matrix.Diagonal((1.25, 0.8, 1, 1))),
        mat("Mail", (0.12, 0.12, 0.13), Metallic=0.9, Roughness=0.55)[0], smooth=True)          # mail under it
    obj("Belt", lathe([(0.225, 0.04), (0.225, 0.11)], 28, tm @ Matrix.Diagonal((1.25, 0.78, 1, 1))), LEATHER, smooth=True)
    obj("Buckle", box(-0.03, 0.03, -0.2, -0.17, 0.045, 0.105, m=tm), BRASS)
    for s_ in (-1, 1):
        ball(Matrix.Translation((ax_, ay_, 1.6)) @ Matrix.Rotation(-0.35, 4, 'Z') @ Vector((0.3*s_, 0, 0)), 0.13, (1.1, 1.0, 0.7), bm=pl)
    hm = Matrix.Translation((ax_, ay_, 1.66)) @ Matrix.Rotation(-0.35, 4, 'Z')
    lathe([(0.12, 0.06), (0.13, 0.12), (0.11, 0.22), (0.06, 0.29), (0, 0.31)], 24, hm, bm=pl)
    lathe([(0.12, 0.06), (0.16, 0.05), (0.16, 0.07), (0.12, 0.08)], 24, hm, bm=pl)           # its brim
    box(-0.012, 0.012, -0.145, -0.125, 0.0, 0.17, bm=pl, m=hm)                              # nasal
    obj("Plate", pl, STEEL, smooth=True)
    obj("EyeSlit", box(-0.09, 0.09, -0.14, -0.1, 0.11, 0.14, m=hm), mat("Slit", (0.01, 0.01, 0.01), Roughness=1)[0])
    barrel("ArrowBarrel", 3.05, 2.9, h=0.7, r=0.26)
    ar, fl_ = bmesh.new(), bmesh.new()
    for k in range(14):
        a = rnd.uniform(0, math.tau); d = rnd.uniform(0, 0.16)
        m = Matrix.Translation((3.05 + d*math.cos(a), 2.9 + d*math.sin(a), 0.2)) @ Matrix.Rotation(rnd.uniform(-0.15, 0.15), 4, Vector((math.cos(a), math.sin(a), 0)))
        lathe([(0.006, 0), (0.006, 0.85), (0, 0.85)], 6, m, bm=ar)
        box(-0.02, 0.02, -0.002, 0.002, 0.7, 0.82, bm=fl_, m=m @ Matrix.Rotation(rnd.uniform(0, math.pi), 4, 'Z'))
    obj("Arrows", ar, FURN); obj("Fletching", fl_, mottle("Feather", (0.6, 0.55, 0.45), 0.3, 20))

    # oil lamps hanging from the middle beam
    for k, x in enumerate((-2.55, 0.95)):
        lm = bmesh.new()
        lathe([(0.004, 2.5), (0.004, H - 0.25)], 6, Matrix.Translation((x, 1.2, 0)), bm=lm)
        lathe([(0, 2.15), (0.08, 2.2), (0.11, 2.27), (0.08, 2.33), (0.02, 2.35), (0.02, 2.5), (0, 2.5)], 20, Matrix.Translation((x, 1.2, 0)), bm=lm)
        obj(f"Lamp{k}", lm, BRASS, smooth=True)
        obj(f"LampFlame{k}", lathe([(0, 0), (0.02, 0.02), (0.012, 0.06), (0, 0.1)], 10, Matrix.Translation((x + 0.07, 1.2, 2.33))), CANDLE)
        light('POINT', (x + 0.07, 1.2, 2.4), 70, (1.0, 0.72, 0.4), size=0.08)
    light('POINT', (X0 + 0.8, 1.8, 2.4), 60, (1.0, 0.72, 0.4), size=0.3)          # (on the weapons)
    light('AREA', (0, -2.0, 2.6), 60, (1.0, 0.9, 0.75), size=4, aim=(0, 2, 0.9))   # fill
    light('AREA', (0, 0.5, 0.3), 12, (1.0, 0.85, 0.65), size=4, aim=(0, 0.5, 3))  # (the beams and ceiling, from below)
    camera((0.0, -2.8, 1.55), (0.0, 4.0, 1.55), 22)

def trade():
    """The Ularn Trading Post: a log-walled room where the gear explorers sell is weighed up and patched for resale.
    The appraiser's desk with big balance scales, a loupe and price tags; a chalkboard of what they pay; pelts, rope
    and old lanterns on pegs; a bench for the reconditioning (a grindstone, an anvil on a stump); a crate of used
    swords, a dented shield; daylight from a window on the left.  Back wall y = 4."""
    X0, X1, Y1, H = -3.6, 3.6, 4.0, 3.0
    LOG = wood_material("Log", (0.12, 0.075, 0.04), axis="X", roughness=0.85)
    LOGY = wood_material("LogY", (0.12, 0.075, 0.04), axis="Y", roughness=0.85)
    STEEL = mat("Steel", (0.45, 0.45, 0.47), Metallic=1.0, Roughness=0.35)[0]
    WORN = mottle("WornSteel", (0.3, 0.29, 0.28), amount=0.4, scale=18, rough=0.55, bump=0.4)
    next(n for n in WORN.node_tree.nodes if n.type == 'BSDF_PRINCIPLED').inputs["Metallic"].default_value = 0.85
    SLATE = mottle("Slate", (0.04, 0.045, 0.045), amount=0.3, scale=6, rough=0.9)
    CHALK = mottle("Chalk", (0.8, 0.8, 0.75), amount=0.2, scale=60, rough=1.0)
    FUR = mottle("Fur", (0.22, 0.13, 0.07), amount=0.45, scale=25, rough=1.0, bump=0.6)
    FUR2 = mottle("Fur2", (0.4, 0.35, 0.28), amount=0.35, scale=25, rough=1.0, bump=0.6)
    ROPE = mottle("Rope", (0.45, 0.36, 0.22), amount=0.3, scale=80, rough=1.0, bump=0.5)
    GRIT = rock_material("Grindstone", (0.7, 0.66, 0.6), scale=2.0)[0]
    SACK = mottle("Sack", (0.2, 0.15, 0.09), amount=0.3, scale=40, rough=1.0, bump=0.5)
    SKY = bpy.data.materials.new("Sky"); SKY.use_nodes = True; _n = SKY.node_tree.nodes; _n.clear()
    _e = _n.new("ShaderNodeEmission"); _e.inputs["Color"].default_value = (0.75, 0.85, 1.0, 1); _e.inputs["Strength"].default_value = 3.0
    SKY.node_tree.links.new(_e.outputs[0], _n.new("ShaderNodeOutputMaterial").inputs[0])

    obj("Floor", box(X0, X1, -5, Y1, -0.1, 0), FLOOR)
    obj("Ceiling", box(X0, X1, -5, Y1, H, H + 0.1), BEAM)
    # log walls: the back logs run across, the side logs along; a window cut in the left
    R_, step = 0.15, 0.27
    lg, ly = bmesh.new(), bmesh.new()
    wy0, wy1, wz0, wz1 = 1.0, 2.4, 0.95, 2.3
    for k in range(int(H/step) + 1):
        z = R_ + k*step
        lathe([(0, X0 - 0.3), (R_, X0 - 0.3), (R_, X1 + 0.3), (0, X1 + 0.3)], 16,
              Matrix.Translation((0, Y1 + R_, z)) @ Matrix.Rotation(math.pi/2, 4, 'Y') @ Matrix.Rotation(rnd.uniform(0, 6), 4, 'Z'), bm=lg)
        for x, sgn in ((X0 - R_, 1), (X1 + R_, -1)):
            spans = [(-5, Y1 + 0.3)]
            if sgn == 1 and wz0 - R_ < z < wz1 + R_: spans = [(-5, wy0), (wy1, Y1 + 0.3)]
            for a, b in spans:
                lathe([(0, a), (R_, a), (R_, b), (0, b)], 16, Matrix.Translation((x, 0, z)) @ Matrix.Rotation(-math.pi/2, 4, 'X'), bm=ly)
    obj("BackLogs", lg, LOG, smooth=True); obj("SideLogs", ly, LOGY, smooth=True)
    obj("Chinking", box(X0 - 0.4, X1 + 0.4, Y1 + 0.2, Y1 + 0.25, 0, H), mottle("Daub", (0.3, 0.25, 0.18), 0.3, 8))
    obj("ChinkingL", box(X0 - 0.25, X0 - 0.2, -5, Y1, 0, wz0 - 0.05), mottle("DaubL", (0.3, 0.25, 0.18), 0.3, 8))
    wf = bmesh.new()
    box(X0 - 0.3, X0 + 0.02, wy0 - 0.08, wy0, wz0 - 0.1, wz1 + 0.1, bm=wf); box(X0 - 0.3, X0 + 0.02, wy1, wy1 + 0.08, wz0 - 0.1, wz1 + 0.1, bm=wf)
    box(X0 - 0.3, X0 + 0.04, wy0 - 0.08, wy1 + 0.08, wz0 - 0.1, wz0, bm=wf); box(X0 - 0.3, X0 + 0.02, wy0 - 0.08, wy1 + 0.08, wz1, wz1 + 0.08, bm=wf)
    box(X0 - 0.32, X0 + 0.03, wy0, wy0 + 0.06, wz0 - 0.1, wz1 + 0.1, bm=wf); box(X0 - 0.32, X0 + 0.03, wy1 - 0.06, wy1, wz0 - 0.1, wz1 + 0.1, bm=wf)
    box(X0 - 0.2, X0 - 0.16, (wy0 + wy1)/2 - 0.025, (wy0 + wy1)/2 + 0.025, wz0, wz1, bm=wf)
    box(X0 - 0.2, X0 - 0.16, wy0, wy1, (wz0 + wz1)/2 - 0.025, (wz0 + wz1)/2 + 0.025, bm=wf)
    obj("WindowFrame", wf, TIMBER, bevel=0.005)
    obj("SkyPane", box(X0 - 1.2, X0 - 1.18, wy0 - 1.5, wy1 + 1.5, wz0 - 1.5, wz1 + 1.5), SKY)
    light('AREA', (X0 - 0.6, (wy0 + wy1)/2, (wz0 + wz1)/2 + 0.2), 450, (1.0, 0.95, 0.85), size=1.3, aim=(0.5, 2.2, 0.2))
    tb = bmesh.new()
    for y in (-0.6, 1.4):
        lathe([(0, X0), (0.14, X0), (0.14, X1), (0, X1)], 16, Matrix.Translation((0, y, H - 0.14)) @ Matrix.Rotation(math.pi/2, 4, 'Y'), bm=tb)
    obj("Rafters", tb, LOG, smooth=True)

    # the sign over it all, the chalkboard of what they pay
    obj("NameBoard", box(-2.0, 2.0, Y1 - 0.06, Y1 - 0.0, 2.52, 2.88), wood_material("Board", (0.4, 0.28, 0.15), axis="X"), bevel=0.01)
    text("Name", "ULARN TRADING POST", (0, Y1 - 0.08, 2.7), 0.21, mottle("Burnt", (0.02, 0.012, 0.006), 0.2, 30), extrude=0.005)
    cb = obj("Chalkboard", box(-0.7, 0.7, -0.02, 0.02, -0.5, 0.5), SLATE)
    cb.location = (-2.2, Y1 - 0.05, 1.75)
    obj("ChalkFrame", box(-0.75, 0.75, -0.03, 0.03, -0.55, 0.55, m=Matrix.Translation((-2.2, Y1 - 0.02, 1.75))), TIMBER)
    for k, (line, size) in enumerate((("WE BUY", 0.13), ("1/5 OF NEW", 0.09), ("1/10 IF DAMAGED", 0.09), ("NO HAGGLING", 0.07))):
        t = text(f"Chalk{k}", line, (0, -0.025, 0.32 - 0.21*k), size, CHALK, extrude=0.001); t.parent = cb

    # the appraiser's desk: balance scales, a loupe, price tags, a ledger, a helmet being looked over
    cx0, cx1, cy = -1.3, 1.5, 2.4
    obj("Desk", box(cx0, cx1, cy - 0.32, cy + 0.32, 0, 0.98), FURN, bevel=0.01)
    pn = bmesh.new()
    for x in [cx0 + (cx1 - cx0)*k/4 for k in range(1, 4)]:
        box(x - 0.025, x + 0.025, cy - 0.34, cy - 0.32, 0.06, 0.92, bm=pn)
    obj("DeskPanels", pn, TIMBER)
    obj("DeskTop", box(cx0 - 0.05, cx1 + 0.05, cy - 0.38, cy + 0.36, 0.98, 1.04), TIMBER, bevel=0.008)
    sxs, top = 0.85, 1.04
    sc_ = bmesh.new()
    lathe([(0, 0), (0.15, 0), (0.12, 0.04), (0.02, 0.07), (0.016, 0.62), (0, 0.62)], 18, Matrix.Translation((sxs, cy, top)), bm=sc_)
    box(sxs - 0.4, sxs + 0.4, cy - 0.012, cy + 0.012, top + 0.6, top + 0.625, bm=sc_, m=Matrix.Translation((sxs, cy, top + 0.61)) @ Matrix.Rotation(0.06, 4, 'Y') @ Matrix.Translation((-sxs, -cy, -top - 0.61)))
    for dx, dz in ((-0.38, 0.025), (0.38, -0.025)):
        for sy_ in (-1, 1):
            box(sxs + dx - 0.003, sxs + dx + 0.003, cy - 0.003 + 0.05*sy_, cy + 0.003 + 0.05*sy_, top + 0.28 + dz, top + 0.6 + dz, bm=sc_)
        lathe([(0, 0), (0.13, 0.0), (0.14, 0.04), (0, 0.04)], 20, Matrix.Translation((sxs + dx, cy, top + 0.26 + dz)), bm=sc_)
    obj("Scales", sc_, BRASS, smooth=True)
    wt = bmesh.new()
    for k, r in enumerate((0.04, 0.03, 0.025)):
        lathe([(0, 0), (r, 0), (r, r*1.1), (r*0.4, r*1.3), (r*0.4, r*1.6), (0, r*1.6)], 12, Matrix.Translation((sxs - 0.38 + (k - 1)*0.07, cy, top + 0.3 + 0.025)), bm=wt)
    obj("Weights", wt, IRON, smooth=True)
    obj("Ring", lathe([(0.03, 0.0), (0.035, 0.0), (0.035, 0.01), (0.03, 0.01)], 16, Matrix.Translation((sxs + 0.38, cy, top + 0.26 - 0.025 + 0.04))), mat("Gold", (1.0, 0.72, 0.3), Metallic=1.0, Roughness=0.2)[0])
    lp = bmesh.new()                                # the loupe on the desk
    lathe([(0.05, 0), (0.06, 0), (0.06, 0.02), (0.05, 0.02)], 20, Matrix.Translation((-0.1, cy - 0.15, top)), bm=lp)
    obj("Loupe", lp, BRASS, smooth=True)
    obj("LoupeGlass", lathe([(0, 0.004), (0.05, 0.004), (0.05, 0.016), (0, 0.016)], 20, Matrix.Translation((-0.1, cy - 0.15, top))),
        mat("Lens", (0.9, 0.95, 1.0), Roughness=0.0, **{"Transmission Weight": 1.0})[0])
    obj("LoupeHandle", box(-0.02, 0.02, -0.12, 0.0, 0.005, 0.015, m=Matrix.Translation((-0.1, cy - 0.15 - 0.06, top)) @ Matrix.Rotation(0.7, 4, 'Z')), FURN)
    tg = bmesh.new()
    for k in range(6):
        box(-0.035, 0.035, -0.02, 0.02, 0, 0.003, bm=tg, m=Matrix.Translation((-0.45 + rnd.uniform(-0.05, 0.05), cy - 0.2 + rnd.uniform(-0.05, 0.05), top + 0.003*k)) @ Matrix.Rotation(rnd.uniform(-0.6, 0.6), 4, 'Z'))
    obj("Tags", tg, PAPER)
    obj("Ledger", box(-0.95, -0.5, cy - 0.25, cy + 0.08, top, top + 0.03, m=Matrix.Rotation(0.1, 4, 'Z')), LEATHER, bevel=0.004)
    obj("LedgerPages", box(-0.93, -0.52, cy - 0.23, cy + 0.06, top + 0.03, top + 0.04, m=Matrix.Rotation(0.1, 4, 'Z')), PAPER)
    hm = Matrix.Translation((0.25, cy + 0.05, top)) @ Matrix.Rotation(0.5, 4, 'Z') @ Matrix.Rotation(0.25, 4, 'X')
    obj("DentedHelm", lathe([(0.13, 0), (0.14, 0.08), (0.12, 0.17), (0.06, 0.24), (0, 0.26)], 20, hm), WORN, smooth=True)

    # pegs on the back wall right: pelts, a coil of rope, old lanterns
    for k, (x, z, m_, sz) in enumerate(((1.95, 1.75, FUR, 1.0), (2.65, 1.65, FUR2, 0.85), (3.25, 1.8, FUR, 0.9))):
        pe = bmesh.new(); pts = []                  # a hide: an oval with the legs and the neck stretched out
        for j in range(72):
            a = math.tau*j/72
            r = 1 + sum(0.55*math.exp(-((math.atan2(math.sin(a - c), math.cos(a - c)))/0.16)**2) for c in (0.75, 2.39, 3.9, 5.52))
            r += 0.35*math.exp(-((math.atan2(math.sin(a - math.pi/2), math.cos(a - math.pi/2)))/0.2)**2) + rnd.uniform(-0.04, 0.04)
            pts.append(pe.verts.new((0.28*sz*r*math.cos(a), 0, 0.42*sz*r*math.sin(a))))
        f = pe.faces.new(pts)
        ex = bmesh.ops.extrude_face_region(pe, geom=[f]); bmesh.ops.translate(pe, vec=(0, -0.025, 0), verts=[v for v in ex["geom"] if isinstance(v, bmesh.types.BMVert)])
        bmesh.ops.recalc_face_normals(pe, faces=pe.faces)
        bmesh.ops.triangulate(pe, faces=pe.faces)
        o = obj(f"Pelt{k}", pe, m_); o.location = (x, Y1 - 0.02, z); o.rotation_euler = (0, rnd.uniform(-0.1, 0.1), 0)
    pg = bmesh.new()
    for x in (1.95, 2.65, 3.25):
        lathe([(0.02, 0), (0.02, 0.12), (0, 0.12)], 8, Matrix.Translation((x, Y1, 2.25)) @ Matrix.Rotation(math.pi/2, 4, 'X'), bm=pg)
    obj("Pegs", pg, TIMBER)
    # the reconditioning bench on the right: a grindstone in its frame, an anvil on a stump, a hammer
    obj("Bench", box(2.0, 3.4, 1.3, 1.9, 0.75, 0.82), FURN, bevel=0.008)
    bl = bmesh.new()
    for x in (2.1, 3.3):
        for y in (1.35, 1.85):
            box(x - 0.04, x + 0.04, y - 0.04, y + 0.04, 0, 0.75, bm=bl)
    obj("BenchLegs", bl, FURN)
    gx, gy = 2.45, 1.55
    gm = Matrix.Translation((gx, gy, 1.12)) @ Matrix.Rotation(0.5, 4, 'Z') @ Matrix.Rotation(math.pi/2, 4, 'Y')
    obj("Grindstone", lathe([(0, -0.05), (0.27, -0.05), (0.28, -0.03), (0.28, 0.03), (0.27, 0.05), (0, 0.05)], 32, gm), GRIT, smooth=True)
    gf = bmesh.new()
    lathe([(0.02, -0.18), (0.02, 0.24), (0, 0.24)], 8, gm, bm=gf)
    for s_ in (-1, 1):
        box(-0.035, 0.035, -0.035, 0.035, 0.82, 1.15, bm=gf, m=Matrix.Translation((gx, gy, 0)) @ Matrix.Rotation(0.5, 4, 'Z') @ Matrix.Translation((0.13*s_, 0, 0)))
    obj("GrindFrame", gf, IRON)
    obj("Crank", box(-0.015, 0.015, -0.015, 0.015, 0, 0.14, m=gm @ Matrix.Translation((0, 0, 0.24)) @ Matrix.Rotation(math.pi/2, 4, 'X')), IRON)
    obj("Stump", lathe([(0, 0), (0.24, 0), (0.22, 0.55), (0, 0.55)], 20, Matrix.Translation((1.95, 0.55, 0))), wood_material("Stump", (0.1, 0.06, 0.035), axis="Z"), smooth=True)
    an = bmesh.new()
    am = Matrix.Translation((1.95, 0.55, 0.55)) @ Matrix.Rotation(0.3, 4, 'Z')
    box(-0.1, 0.1, -0.07, 0.07, 0, 0.12, bm=an, m=am); box(-0.2, 0.18, -0.09, 0.09, 0.12, 0.24, bm=an, m=am)
    lathe([(0.075, 0), (0, 0.22)], 10, am @ Matrix.Translation((-0.2, 0, 0.18)) @ Matrix.Rotation(-math.pi/2, 4, 'Y'), bm=an)
    obj("Anvil", an, IRON, bevel=0.01)
    hm_ = Matrix.Translation((2.85, 1.65, 0.82)) @ Matrix.Rotation(0.3, 4, 'Z')
    obj("HammerHaft", lathe([(0.015, 0), (0.015, 0.4), (0, 0.4)], 8, hm_ @ Matrix.Rotation(math.pi/2, 4, 'Y') @ Matrix.Translation((-0.02, 0, 0))), FURN)
    obj("HammerHead", box(0.36, 0.44, -0.035, 0.035, 0.0, 0.07, m=hm_ @ Matrix.Translation((0, 0, 0.005))), IRON)
    # used gear on the floor: a crate of swords, a dented shield leant on it, sacks, a barrel
    kx, ky = -2.55, 2.1
    obj("Crate", box(kx - 0.35, kx + 0.35, ky - 0.3, ky + 0.3, 0, 0.6), FURN, bevel=0.012)
    ss, sg, sh_ = bmesh.new(), bmesh.new(), bmesh.new()
    for k in range(5):
        m = (Matrix.Translation((kx + rnd.uniform(-0.2, 0.2), ky + rnd.uniform(-0.15, 0.15), 0.1)) @ Matrix.Rotation(rnd.uniform(0, math.tau), 4, 'Z')
             @ Matrix.Rotation(rnd.uniform(0.1, 0.3), 4, 'X'))
        b_ = lathe([(0, 0), (0.035, 0.1), (0.03, 0.78), (0, 0.8)], 4); b_.transform(m @ Matrix.Diagonal((1, 0.18, 1, 1))); merge(ss, b_)
        box(-0.12, 0.12, -0.02, 0.02, 0.78, 0.82, bm=ss, m=m)
        lathe([(0.018, 0.82), (0.02, 0.97), (0, 0.97)], 10, m, bm=sh_)
        ball(m @ Vector((0, 0, 0.99)), 0.028, bm=sg)
    obj("UsedSwords", ss, WORN); obj("UsedGrips", sh_, LEATHER, smooth=True); obj("UsedPommels", sg, IRON, smooth=True)
    shm = Matrix.Translation((kx + 0.15, ky - 0.42, 0.36)) @ Matrix.Rotation(0.3, 4, 'Z') @ Matrix.Rotation(math.pi/2 - 0.25, 4, 'X')
    sd = lathe([(0, -0.05), (0.36, -0.02), (0.36, 0.0), (0, 0.0)], 32, shm)
    for v in sd.verts:                              # a dent or two
        if (v.co - (shm @ Vector((0.12, 0.1, -0.03)))).length < 0.12: v.co -= (shm.to_3x3() @ Vector((0, 0, -1))) * 0.03
    obj("UsedShield", sd, mottle("FadedGreen", (0.12, 0.2, 0.1), 0.35, 8, 0.7), smooth=True)
    obj("UsedShieldRim", lathe([(0.355, -0.025), (0.375, -0.025), (0.375, 0.005), (0.355, 0.005)], 32, shm), WORN, smooth=True)
    bx_, by_, bh_, br_ = -1.85, 1.2, 0.75, 0.28      # a barrel of used staves and a bow
    bm_ = Matrix.Translation((bx_, by_, 0))
    obj("Barrel", lathe([(0, 0)] + [(br_*(0.86 + 0.14*math.sin(math.pi*k/8)), bh_*k/8) for k in range(9)] + [(br_*0.88, bh_ - 0.03), (0, bh_ - 0.03)], 24, bm_),
        wood_material("Staves", (0.1, 0.06, 0.035), axis="Z"), smooth=True)
    hp = bmesh.new()
    for zz in (0.08, 0.3, 0.7, 0.92):
        rr = br_*(0.86 + 0.14*math.sin(math.pi*zz)) + 0.006
        lathe([(rr, bh_*zz - 0.025), (rr, bh_*zz + 0.025)], 24, bm_, bm=hp)
    obj("BarrelHoops", hp, IRON, smooth=True)
    st_ = bmesh.new()
    for k in range(4):
        a_ = math.tau*k/4 + 0.5
        m = Matrix.Translation((bx_ + 0.1*math.cos(a_), by_ + 0.1*math.sin(a_), 0.1)) @ Matrix.Rotation(0.12, 4, Vector((-math.sin(a_), math.cos(a_), 0)))
        lathe([(0.02, 0), (0.022, 1.5 + 0.12*k), (0.035, 1.55 + 0.12*k), (0, 1.6 + 0.12*k)], 8, m, bm=st_)
    obj("Staves", st_, FURN, smooth=True)
    bw_ = bmesh.new()                               # the bow, its string
    pts = [Vector((bx_ - 0.12 + 0.12*math.sin(math.pi*t/12), by_ + 0.05, 0.25 + 1.3*t/12)) for t in range(13)]
    for p0, p1 in zip(pts, pts[1:]):
        d = p1 - p0; lathe([(0.015, 0), (0.015, d.length)], 8, Matrix.Translation(p0) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4(), bm=bw_)
    obj("Bow", bw_, LEATHER, smooth=True)
    d = pts[-1] - pts[0]
    obj("BowString", lathe([(0.003, 0), (0.003, d.length)], 6, Matrix.Translation(pts[0]) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()), PAPER)
    rp = bmesh.new()
    for k in range(3):
        prof = [(0.17 + 0.012*k + 0.022*math.cos(t*math.tau/10), 0.022*math.sin(t*math.tau/10)) for t in range(11)]
        lathe(prof, 32, Matrix.Translation((-3.05, 2.0, 0.025 + 0.04*k)), bm=rp)
    obj("RopeCoil", rp, ROPE, smooth=True)
    # a lantern hung from the rafter over the desk
    lx = 0.2
    lm = bmesh.new()
    lathe([(0.004, 2.25), (0.004, H - 0.28)], 6, Matrix.Translation((lx, 1.4, 0)), bm=lm)
    box(lx - 0.09, lx + 0.09, 1.31, 1.49, 1.85, 1.88, bm=lm); box(lx - 0.1, lx + 0.1, 1.3, 1.5, 2.1, 2.13, bm=lm)
    for dx, dy in ((-1, -1), (1, -1), (-1, 1), (1, 1)):
        box(lx + 0.085*dx - 0.01, lx + 0.085*dx + 0.01, 1.4 + 0.085*dy - 0.01, 1.4 + 0.085*dy + 0.01, 1.88, 2.1, bm=lm)
    lathe([(0.07, 2.13), (0, 2.25)], 4, Matrix.Translation((lx, 1.4, 0)) @ Matrix.Rotation(math.pi/4, 4, 'Z'), bm=lm)
    obj("Lantern", lm, IRON)
    obj("LanternFlame", lathe([(0, 0), (0.014, 0.014), (0.009, 0.035), (0, 0.06)], 10, Matrix.Translation((lx, 1.4, 1.92))), CANDLE)
    light('POINT', (lx, 1.4, 1.98), 50, (1.0, 0.68, 0.35), size=0.06)
    light('AREA', (0, -2.0, 2.6), 90, (1.0, 0.9, 0.75), size=4, aim=(0, 2, 0.9))   # fill
    light('AREA', (1.5, 0.5, 2.4), 40, (1.0, 0.85, 0.65), size=2, aim=(2.6, 1.0, 0.8))   # (the bench)
    camera((0.0, -2.8, 1.55), (0.0, 4.0, 1.55), 22)

def arch_prism(ya, yb, z0, zs, x0, x1):
    """A pointed (gothic) arch opening in the y-z plane, from z0 up, the sides to zs then two arcs meeting at a point;
    as a prism from x0 to x1 (to cut a window with)."""
    w = yb - ya; pts = [(ya, z0), (yb, z0), (yb, zs)]
    pts += [(ya + w*math.cos(a), zs + w*math.sin(a)) for a in (math.pi/3*k/8 for k in range(1, 9))]          # right arc, about ya
    pts += [(yb + w*math.cos(a), zs + w*math.sin(a)) for a in (2*math.pi/3 + math.pi/3*k/8 for k in range(1, 9))]   # left arc, about yb
    bm = bmesh.new(); f = bm.faces.new([bm.verts.new((x0, y, z)) for y, z in pts])
    ex = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, vec=(x1 - x0, 0, 0), verts=[v for v in ex["geom"] if isinstance(v, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

def college():
    """The College of Ularn: a lecture hall seen from behind the benches.  A great blackboard of chalked diagrams on
    the back wall under the college's name, the master's desk with an orrery, a lectern, three rows of slanted
    desks with books and ink, tall pointed leaded windows down the left, bookcases on the right, banners.  Back wall y = 5."""
    X0, X1, Y1, H = -4.0, 4.0, 5.0, 3.8
    WALL = mottle("CollegeWall", (0.42, 0.38, 0.31), amount=0.12, scale=3, bump=0.1)
    PANEL = wood_material("Panel", (0.08, 0.045, 0.02), axis="Z", roughness=0.45)
    DESK = wood_material("DeskWood", (0.12, 0.07, 0.035), axis="X", roughness=0.5)
    SLATE = mottle("Slate", (0.035, 0.045, 0.04), amount=0.25, scale=5, rough=0.9)
    CHALK = mottle("Chalk", (0.85, 0.85, 0.8), amount=0.2, scale=60, rough=1.0)
    GILT = mat("Gilt", (1.0, 0.72, 0.3), Metallic=1.0, Roughness=0.25)[0]
    BANNER = mottle("Banner", (0.06, 0.08, 0.3), amount=0.2, scale=20, rough=0.9, bump=0.2)
    SKY = bpy.data.materials.new("Sky"); SKY.use_nodes = True; _n = SKY.node_tree.nodes; _n.clear()
    _e = _n.new("ShaderNodeEmission"); _e.inputs["Color"].default_value = (0.75, 0.85, 1.0, 1); _e.inputs["Strength"].default_value = 3.0
    SKY.node_tree.links.new(_e.outputs[0], _n.new("ShaderNodeOutputMaterial").inputs[0])
    BOOKS = mottle("Bindings", (0.2, 0.08, 0.05), amount=0.7, scale=40, rough=0.6)

    obj("Floor", box(X0, X1, -5, Y1, -0.1, 0), FLOOR)
    obj("Ceiling", box(X0, X1, -5, Y1, H, H + 0.1), WALL)
    obj("BackWall", box(X0, X1, Y1, Y1 + 0.3, 0, H), WALL)
    obj("RightWall", box(X1, X1 + 0.3, -5, Y1, 0, H), WALL)
    lw = obj("LeftWall", box(X0 - 0.4, X0, -5, Y1, 0, H), WALL)
    wins = ((-1.4, -0.2), (1.2, 2.4), (3.6, 4.6))[:2] + ((3.4, 4.4),)
    for k, (ya, yb) in enumerate(wins):             # tall pointed windows with leaded panes
        cut_ = obj(f"WinCut{k}", arch_prism(ya, yb, 1.0, 2.6, X0 - 0.5, X0 + 0.1), WALL); cut_.hide_render = True
        c = lw.modifiers.new(f"Win{k}", 'BOOLEAN'); c.operation = 'DIFFERENCE'; c.object = cut_
        ld = bmesh.new()
        y = ya
        while y <= yb + 1e-3:
            box(X0 - 0.22, X0 - 0.2, y - 0.008, y + 0.008, 1.0, 3.7, bm=ld); y += (yb - ya)/4
        z = 1.0
        while z < 3.7:
            box(X0 - 0.22, X0 - 0.2, ya, yb, z - 0.008, z + 0.008, bm=ld); z += 0.3
        obj(f"Leading{k}", ld, IRON)
        obj(f"Sill{k}", box(X0 - 0.4, X0 + 0.08, ya - 0.05, yb + 0.05, 0.92, 1.0), PANEL)
        light('AREA', (X0 - 0.8, (ya + yb)/2, 2.3), 300, (1.0, 0.96, 0.88), size=1.0, aim=(X0 + 3, (ya + yb)/2 + 1.0, 0))
    obj("SkyPane", box(X0 - 1.5, X0 - 1.48, -6, Y1 + 2, -1, H + 2), SKY)
    # dark panelling round the bottom of the walls, a moulding along the top
    pn = bmesh.new()
    box(X0, X1, Y1 - 0.05, Y1, 0, 1.0, bm=pn); box(X1 - 0.05, X1, -5, Y1, 0, 1.0, bm=pn); box(X0, X0 + 0.05, -5, Y1, 0, 0.92, bm=pn)
    box(X0, X1, Y1 - 0.1, Y1, 0.95, 1.02, bm=pn); box(X1 - 0.1, X1, -5, Y1, 0.95, 1.02, bm=pn)
    box(X0, X1, Y1 - 0.12, Y1, H - 0.2, H, bm=pn); box(X1 - 0.12, X1, -5, Y1, H - 0.2, H, bm=pn); box(X0, X0 + 0.12, -5, Y1, H - 0.2, H, bm=pn)
    obj("Panelling", pn, PANEL, bevel=0.005)
    bm_ = bmesh.new()
    for y in (-1.0, 2.0):
        box(X0, X1, y - 0.15, y + 0.15, H - 0.3, H, bm=bm_)
    obj("CeilingBeams", bm_, PANEL, bevel=0.01)

    # the blackboard and what is chalked on it
    obj("BoardFrame", box(-2.1, 2.1, Y1 - 0.08, Y1, 1.05, 2.75), PANEL, bevel=0.01)
    obj("Blackboard", box(-2.0, 2.0, Y1 - 0.1, Y1 - 0.05, 1.12, 2.68), SLATE)
    obj("ChalkLedge", box(-2.1, 2.1, Y1 - 0.2, Y1, 1.0, 1.05), PANEL)
    cy_ = Y1 - 0.105
    text("Lesson", "ARCANE THEORY I", (-1.0, cy_, 2.45), 0.14, CHALK, extrude=0.001)
    for k, line in enumerate(("1. the four elements", "2. the circle of binding", "3. on the conservation", "    of mana")):
        t = text(f"Note{k}", line, (-1.0, cy_, 2.2 - 0.15*k), 0.085, CHALK, extrude=0.001); t.data.align_x = 'LEFT'; t.location.x = -1.85
    ch = bmesh.new()                                # a circle of binding: two rings, a pentagram in them
    cm = Matrix.Translation((1.1, cy_, 1.85)) @ Matrix.Rotation(math.pi/2, 4, 'X')
    for r in (0.6, 0.52):
        lathe([(r - 0.008, 0), (r + 0.008, 0), (r + 0.008, 0.002), (r - 0.008, 0.002)], 64, cm, bm=ch)
    star = [cm @ Vector((0.52*math.cos(math.pi/2 + math.tau*k*2/5), 0.52*math.sin(math.pi/2 + math.tau*k*2/5), 0)) for k in range(6)]
    for a_, b_ in zip(star, star[1:]):
        d = b_ - a_; m = Matrix.Translation((a_ + b_)/2) @ d.to_track_quat('X', 'Y').to_matrix().to_4x4()
        box(-d.length/2, d.length/2, -0.0015, 0.0015, -0.008, 0.008, bm=ch, m=m)
    for k in range(5):                              # little signs round it
        a = math.pi/2 + math.tau*(k + 0.5)/5
        lathe([(0.025, 0), (0.035, 0), (0.035, 0.002), (0.025, 0.002)], 16, Matrix.Translation(cm @ Vector((0.56*math.cos(a), 0.56*math.sin(a), 0))) @ Matrix.Rotation(math.pi/2, 4, 'X'), bm=ch)
    obj("ChalkCircle", ch, CHALK)
    sticks = bmesh.new()
    for x in (-1.4, -1.32, 0.6):
        box(x, x + 0.06, Y1 - 0.18, Y1 - 0.15, 1.05, 1.07, bm=sticks)
    obj("ChalkSticks", sticks, CHALK)
    obj("Eraser", box(1.4, 1.62, Y1 - 0.19, Y1 - 0.1, 1.05, 1.1), FURN)
    # the college's name over the board, banners either side
    obj("NameBoard", box(-2.3, 2.3, Y1 - 0.06, Y1, 2.95, 3.35), PANEL, bevel=0.01)
    text("Name", "THE COLLEGE OF ULARN", (0, Y1 - 0.08, 3.15), 0.2, GILT, extrude=0.008)
    for k, x in enumerate((-3.0, 3.0)):
        bn = bmesh.new()
        vs = [bn.verts.new(v) for v in ((-0.4, 0, 0.0), (0.4, 0, 0.0), (0.4, 0, 1.5), (0, 0, 1.25), (-0.4, 0, 1.5))]
        bn.faces.new(vs)
        b_ = obj(f"Banner{k}", bn, BANNER); b_.location = (x, Y1 - 0.05, 3.5); b_.rotation_euler = (0, math.pi, 0)
        sol = b_.modifiers.new("Solid", 'SOLIDIFY'); sol.thickness = 0.01
        obj(f"BannerRod{k}", lathe([(0.02, -0.5), (0.02, 0.5), (0, 0.5)], 10, Matrix.Translation((x, Y1 - 0.06, 3.5)) @ Matrix.Rotation(math.pi/2, 4, 'Y')), GILT)
        cr = bmesh.new()                            # its crest: a ring and a star
        cm_ = Matrix.Translation((x, Y1 - 0.07, 2.75)) @ Matrix.Rotation(math.pi/2, 4, 'X')
        lathe([(0.2, 0), (0.24, 0), (0.24, 0.005), (0.2, 0.005)], 40, cm_, bm=cr)
        pts = [cm_ @ Vector(((0.16 if j % 2 == 0 else 0.07)*math.cos(math.pi/2 + math.tau*j/10), (0.16 if j % 2 == 0 else 0.07)*math.sin(math.pi/2 + math.tau*j/10), 0)) for j in range(10)]
        f = cr.faces.new([cr.verts.new(p_) for p_ in pts])
        obj(f"Crest{k}", cr, GILT)

    # the master's desk on the left of the board (books, a candle, an orrery), the lectern on the right
    dx0, dx1, dy = -2.9, -1.5, 3.9
    obj("MasterDesk", box(dx0, dx1, dy - 0.4, dy + 0.4, 0, 0.82), DESK, bevel=0.01)
    obj("MasterDeskTop", box(dx0 - 0.04, dx1 + 0.04, dy - 0.44, dy + 0.44, 0.82, 0.87), PANEL, bevel=0.006)
    bk = bmesh.new()
    for k in range(4):
        box(-0.17, 0.17, -0.12, 0.12, 0.87 + 0.055*k, 0.87 + 0.055*(k + 1) - 0.004, bm=bk,
            m=Matrix.Translation((dx0 + 0.3, dy - 0.05, 0)) @ Matrix.Rotation(rnd.uniform(-0.25, 0.25), 4, 'Z'))
    obj("DeskBooks", bk, BOOKS, bevel=0.003)
    om = Matrix.Translation((dx1 - 0.4, dy, 0.87))
    ob = bmesh.new()
    lathe([(0, 0), (0.1, 0), (0.08, 0.03), (0.015, 0.05), (0.015, 0.32), (0, 0.32)], 16, om, bm=ob)
    for k, (r, tilt) in enumerate(((0.2, 0.3), (0.26, -0.5), (0.32, 0.9))):
        lathe([(r - 0.006, -0.004), (r + 0.006, -0.004), (r + 0.006, 0.004), (r - 0.006, 0.004)], 48,
              om @ Matrix.Translation((0, 0, 0.42)) @ Matrix.Rotation(tilt, 4, 'X') @ Matrix.Rotation(k*0.8, 4, 'Y'), bm=ob)
    obj("Orrery", ob, BRASS, smooth=True)
    obj("OrrerySun", ball(om @ Vector((0, 0, 0.42)), 0.06), GILT)
    for k, (r, tilt, c) in enumerate(((0.2, 0.3, (0.2, 0.3, 0.7)), (0.26, -0.5, (0.7, 0.3, 0.15)), (0.32, 0.9, (0.6, 0.6, 0.55)))):
        p_ = om @ Matrix.Translation((0, 0, 0.42)) @ Matrix.Rotation(tilt, 4, 'X') @ Matrix.Rotation(k*0.8, 4, 'Y') @ Vector((r*math.cos(1 + k), r*math.sin(1 + k), 0))
        obj(f"Planet{k}", ball(p_, 0.025), mat(f"Planet{k}", c, Roughness=0.4)[0])
    obj("MasterCandle", lathe([(0, 0), (0.03, 0), (0.03, 0.2), (0, 0.2)], 12, Matrix.Translation((dx0 + 0.75, dy - 0.25, 0.87))), WAX)
    obj("MasterFlame", lathe([(0, 0), (0.014, 0.014), (0.009, 0.035), (0, 0.06)], 10, Matrix.Translation((dx0 + 0.75, dy - 0.25, 1.08))), CANDLE)
    light('POINT', (dx0 + 0.75, dy - 0.3, 1.15), 15, (1.0, 0.7, 0.35), size=0.04)
    obj("MasterChair", box(dx0 + 0.4, dx0 + 0.9, dy + 0.45, dy + 0.85, 0.45, 0.5), DESK)
    obj("MasterChairBack", box(dx0 + 0.4, dx0 + 0.9, dy + 0.8, dy + 0.85, 0.5, 1.4), DESK, bevel=0.01)
    lx, ly = 2.4, 3.8
    lc = bmesh.new()
    lathe([(0, 0), (0.25, 0), (0.22, 0.05), (0.06, 0.1), (0.05, 1.05), (0, 1.05)], 20, Matrix.Translation((lx, ly, 0)), bm=lc)
    box(-0.3, 0.3, -0.22, 0.22, 0, 0.06, bm=lc, m=Matrix.Translation((lx, ly, 1.1)) @ Matrix.Rotation(-0.35, 4, 'X'))
    obj("Lectern", lc, PANEL, smooth=False, bevel=0.005)
    ob_ = obj("LecternBook", box(-0.24, 0.24, -0.16, 0.16, 0.06, 0.09), PAPER); ob_.location = (lx, ly, 1.1); ob_.rotation_euler = (-0.35, 0, 0)

    # three rows of slanted desks either side of the aisle, a bench behind each, books, ink, quills
    stuff_b, stuff_i, stuff_q, scr = bmesh.new(), bmesh.new(), bmesh.new(), bmesh.new()
    dk, bnch = bmesh.new(), bmesh.new()
    for row, y in enumerate((0.95, 1.95, 2.95)):
        for xa, xb in ((-3.2, -0.6), (0.6, 3.2)):
            box(xa, xb, y - 0.25, y + 0.25, 0.72, 0.77, bm=dk, m=Matrix.Translation((0, y, 0.75)) @ Matrix.Rotation(0.15, 4, 'X') @ Matrix.Translation((0, -y, -0.75)))
            box(xa, xb, y + 0.22, y + 0.25, 0.0, 0.72, bm=dk)        # its front (to the board)
            for x in (xa + 0.05, xb - 0.05):
                box(x - 0.03, x + 0.03, y - 0.2, y + 0.22, 0, 0.72, bm=dk)
            box(xa, xb, y - 0.62, y - 0.36, 0.42, 0.47, bm=bnch)       # the bench the students sit on, facing it
            for x in (xa + 0.1, xb - 0.1):
                box(x - 0.03, x + 0.03, y - 0.58, y - 0.4, 0, 0.42, bm=bnch)
            for k in range(3):                      # each student's place
                x = xa + (xb - xa)*(k + 0.5)/3 + rnd.uniform(-0.1, 0.1)
                m = Matrix.Translation((x, y, 0.79)) @ Matrix.Rotation(0.15, 4, 'X')
                if rnd.random() < 0.7:
                    box(-0.17, 0.17, -0.12, 0.12, 0, 0.03, bm=stuff_b, m=m @ Matrix.Rotation(rnd.uniform(-0.3, 0.3), 4, 'Z'))
                else:
                    lathe([(0, -0.15), (0.03, -0.15), (0.03, 0.15), (0, 0.15)], 12, m @ Matrix.Translation((0, 0, 0.03)) @ Matrix.Rotation(math.pi/2, 4, 'Y') @ Matrix.Rotation(rnd.uniform(-0.3, 0.3), 4, 'X'), bm=scr)
                ip = Matrix.Translation((x + 0.25, y + 0.15, 0.81))
                lathe([(0, 0), (0.03, 0), (0.03, 0.04), (0.012, 0.055), (0, 0.055)], 12, ip, bm=stuff_i)
                qm = ip @ Matrix.Translation((0, 0, 0.03)) @ Matrix.Rotation(0.35, 4, 'Y')
                box(-0.003, 0.003, -0.002, 0.002, 0, 0.27, bm=stuff_q, m=qm)
                box(-0.022, 0.012, -0.0015, 0.0015, 0.1, 0.28, bm=stuff_q, m=qm)   # (its vane)
    obj("Desks", dk, DESK, bevel=0.004); obj("Benches", bnch, DESK, bevel=0.004)
    obj("StudentBooks", stuff_b, BOOKS, bevel=0.002); obj("InkPots", stuff_i, mat("Ink", (0.02, 0.02, 0.03), Roughness=0.25)[0], smooth=True)
    obj("Quills", stuff_q, PAPER); obj("StudentScrolls", scr, mottle("Parchment", (0.62, 0.5, 0.32), amount=0.25, scale=12, rough=0.85), smooth=True)

    # bookcases down the right wall, a globe by them
    bc, bb = bmesh.new(), bmesh.new()
    for ya, yb in ((0.0, 1.6), (1.8, 3.4)):
        box(X1 - 0.45, X1, ya, yb, 0, 0.05, bm=bc); box(X1 - 0.45, X1, ya, yb, 2.6, 2.7, bm=bc)
        for y in (ya, yb - 0.05):
            box(X1 - 0.45, X1, y, y + 0.05, 0, 2.7, bm=bc)
        for z in (0.05, 0.7, 1.3, 1.9):
            if z > 0.05: box(X1 - 0.45, X1, ya, yb, z, z + 0.04, bm=bc)
            y = ya + 0.06
            while y < yb - 0.1:
                w = rnd.uniform(0.05, 0.1); h = rnd.uniform(0.38, 0.52)
                if rnd.random() < 0.05: y += 0.15; continue
                box(X1 - 0.4, X1 - 0.08, y, y + w, z + 0.04, z + 0.04 + h, bm=bb); y += w + 0.006
    obj("Bookcases", bc, PANEL, bevel=0.005); obj("Books", bb, BOOKS)
    gm = Matrix.Translation((3.2, -0.4, 0))
    obj("GlobeStand", lathe([(0, 0), (0.22, 0), (0.2, 0.04), (0.04, 0.08), (0.03, 0.7), (0, 0.7)], 16, gm), DESK, smooth=True)
    obj("GlobeRing", lathe([(0.3, -0.01), (0.32, -0.01), (0.32, 0.01), (0.3, 0.01)], 40, gm @ Matrix.Translation((0, 0, 1.0)) @ Matrix.Rotation(math.pi/2, 4, 'X') @ Matrix.Rotation(0.4, 4, 'Y')), BRASS, smooth=True)
    obj("Globe", ball(gm @ Vector((0, 0, 1.0)), 0.28), quilt("Map", (0.55, 0.45, 0.28), (0.15, 0.3, 0.4), scale=4))

    light('AREA', (0, -2.0, 3.2), 70, (1.0, 0.92, 0.8), size=5, aim=(0, 3, 1.0))   # fill
    light('POINT', (0, 3.0, 3.0), 60, (1.0, 0.85, 0.6), size=0.6)                    # (on the board)
    camera((0.0, -3.0, 1.7), (0.0, 5.0, 1.7), 22)

def lrs():
    """The Ularn Revenue Service district office: a drab grey hall.  Behind a barred counter with its PAY HERE window,
    a wall of pigeonholes stuffed with forms; stacks of paper everywhere, a great seal stamp and ink pad, an
    hourglass; a notice board of demands; a queue rope on iron posts, a bench to wait on; small barred windows
    high in the left wall, a cold light.  Back wall y = 4.2."""
    X0, X1, Y1, H = -3.6, 3.6, 4.2, 3.2
    FLAGS = checker("Flags", (0.2, 0.2, 0.19), (0.15, 0.15, 0.145), 1.4, 0.75)
    WALL = mottle("DrabWall", (0.27, 0.29, 0.25), amount=0.15, scale=2.5, bump=0.12)
    DARK = wood_material("DrabWood", (0.06, 0.05, 0.04), axis="X", roughness=0.6)
    DARKZ = wood_material("DrabWoodZ", (0.06, 0.05, 0.04), axis="Z", roughness=0.6)
    FORMS = mottle("Forms", (0.62, 0.6, 0.52), amount=0.12, scale=25, rough=0.95)
    CORK = mottle("Cork", (0.32, 0.22, 0.13), amount=0.35, scale=40, rough=0.95, bump=0.4)
    INK = mat("Ink", (0.02, 0.02, 0.03), Roughness=0.3)[0]
    RED = mottle("RedInk", (0.45, 0.03, 0.02), amount=0.2, scale=30, rough=0.7)
    LETTER = mottle("Lettering", (0.05, 0.05, 0.05), amount=0.1, scale=30, rough=0.9)
    SKY = bpy.data.materials.new("Sky"); SKY.use_nodes = True; _n = SKY.node_tree.nodes; _n.clear()
    _e = _n.new("ShaderNodeEmission"); _e.inputs["Color"].default_value = (0.7, 0.8, 0.95, 1); _e.inputs["Strength"].default_value = 2.0
    SKY.node_tree.links.new(_e.outputs[0], _n.new("ShaderNodeOutputMaterial").inputs[0])

    obj("Floor", box(X0, X1, -5, Y1, -0.1, 0), FLAGS)
    obj("Ceiling", box(X0, X1, -5, Y1, H, H + 0.1), WALL)
    obj("BackWall", box(X0, X1, Y1, Y1 + 0.3, 0, H), WALL)
    obj("RightWall", box(X1, X1 + 0.3, -5, Y1, 0, H), WALL)
    lw = bmesh.new()                                # the left wall: small barred windows high up
    wins = ((-0.8, 0.0), (1.6, 2.4))
    edges = [-5] + [v for w in wins for v in w] + [Y1]
    for a, b in zip(edges[::2], edges[1::2]):
        box(X0 - 0.3, X0, a, b, 0, H, bm=lw)
    for ya, yb in wins:
        box(X0 - 0.3, X0, ya, yb, 0, 2.2, bm=lw); box(X0 - 0.3, X0, ya, yb, 2.8, H, bm=lw)
        bars = bmesh.new()
        for k in range(1, 5):
            y = ya + (yb - ya)*k/5
            box(X0 - 0.17, X0 - 0.13, y - 0.012, y + 0.012, 2.2, 2.8, bm=bars)
        obj("WindowBars", bars, IRON)
        light('AREA', (X0 - 0.5, (ya + yb)/2, 2.5), 180, (0.8, 0.88, 1.0), size=0.7, aim=(X0 + 2.5, (ya + yb)/2 + 1.0, 0))
    obj("LeftWall", lw, WALL)
    obj("SkyPane", box(X0 - 1.0, X0 - 0.98, -3, Y1, 1.5, H + 1), SKY)
    tr = bmesh.new()                                # a dark dado rail and skirting
    for z0, z1 in ((0, 0.15), (1.0, 1.06)):
        box(X0, X1, Y1 - 0.04, Y1, z0, z1, bm=tr); box(X1 - 0.04, X1, -5, Y1, z0, z1, bm=tr); box(X0, X0 + 0.04, -5, Y1, z0, z1, bm=tr)
    obj("Rails", tr, DARK)

    # the pigeonholes behind the counter, every one stuffed
    px0, px1, pz0, pz1, nx, nz = -3.2, 0.8, 0.9, 2.9, 10, 6
    ph, pp = bmesh.new(), bmesh.new()
    for i in range(nx + 1):
        x = px0 + (px1 - px0)*i/nx
        box(x - 0.015, x + 0.015, Y1 - 0.4, Y1, pz0, pz1, bm=ph)
    for j in range(nz + 1):
        z = pz0 + (pz1 - pz0)*j/nz
        box(px0 - 0.015, px1 + 0.015, Y1 - 0.4, Y1, z - 0.015, z + 0.015, bm=ph)
    cw, chh = (px1 - px0)/nx, (pz1 - pz0)/nz
    for i in range(nx):
        for j in range(nz):
            x, z = px0 + cw*i, pz0 + chh*j
            kind = rnd.random()
            if kind < 0.55:                         # a bundle of folded forms
                h = chh*rnd.uniform(0.35, 0.8)
                box(x + 0.03, x + cw - 0.03, Y1 - 0.36 + rnd.uniform(0, 0.08), Y1 - 0.05, z + 0.015, z + 0.015 + h, bm=pp,
                    m=Matrix.Translation((x + cw/2, 0, z)) @ Matrix.Rotation(rnd.uniform(-0.05, 0.05), 4, 'Y') @ Matrix.Translation((-x - cw/2, 0, -z)))
                if rnd.random() < 0.5:              # a sheet hanging out
                    box(x + 0.05, x + cw - 0.08, Y1 - 0.44, Y1 - 0.3, z + 0.015 + h - 0.004, z + 0.015 + h, bm=pp,
                        m=Matrix.Translation((x + cw/2, Y1 - 0.37, z + h)) @ Matrix.Rotation(rnd.uniform(-0.4, -0.1), 4, 'X') @ Matrix.Translation((-x - cw/2, -Y1 + 0.37, -z - h)))
            elif kind < 0.9:                        # rolled ones
                for r_ in range(rnd.randint(2, 4)):
                    lathe([(0, -0.17), (0.028, -0.17), (0.028, 0.17), (0, 0.17)], 10,
                          Matrix.Translation((x + 0.06 + 0.06*r_, Y1 - 0.2, z + 0.045 + 0.05*(r_ % 2))) @ Matrix.Rotation(math.pi/2, 4, 'X'), bm=pp)
    obj("Pigeonholes", ph, DARK); obj("PigeonPapers", pp, FORMS)

    # the counter, its grille and the window to pay at
    cx0, cx1, cy = -2.9, 0.9, 2.9
    obj("Counter", box(cx0, cx1, cy - 0.3, cy + 0.3, 0, 1.05), DARK, bevel=0.01)
    pn = bmesh.new()
    for x in [cx0 + (cx1 - cx0)*k/5 for k in range(1, 5)]:
        box(x - 0.025, x + 0.025, cy - 0.32, cy - 0.3, 0.08, 0.97, bm=pn)
    obj("CounterPanels", pn, DARKZ)
    obj("CounterTop", box(cx0 - 0.05, cx1 + 0.05, cy - 0.36, cy + 0.34, 1.05, 1.1), DARK, bevel=0.006)
    gr = bmesh.new()
    wx = -1.0                                       # the window
    x = cx0
    while x <= cx1 + 1e-3:
        if abs(x - wx) > 0.3:
            box(x - 0.01, x + 0.01, cy - 0.01, cy + 0.01, 1.1, 2.35, bm=gr)
        x += 0.08
    for z in (1.1, 1.75, 2.35):
        box(cx0, cx1, cy - 0.02, cy + 0.02, z, z + 0.035, bm=gr)
    obj("Grille", gr, IRON)
    obj("PayBoard", box(wx - 0.36, wx + 0.36, cy - 0.04, cy - 0.02, 1.85, 2.08), PAPER)
    text("PayHere", "PAY HERE", (wx, cy - 0.045, 1.965), 0.11, LETTER, extrude=0.002)
    # on the counter: the seal stamp and ink pad, forms in stacks, an hourglass, a ledger, a quill and ink
    st = bmesh.new()
    sm = Matrix.Translation((wx - 0.05, cy - 0.15, 1.1))
    lathe([(0, 0), (0.07, 0), (0.07, 0.03), (0.03, 0.05), (0.025, 0.14), (0.045, 0.17), (0.045, 0.21), (0.03, 0.23), (0, 0.23)], 16, sm, bm=st)
    obj("SealStamp", st, BRASS, smooth=True)
    obj("StampFace", lathe([(0, -0.002), (0.069, -0.002), (0.069, 0.004), (0, 0.004)], 16, sm), RED)
    obj("InkPad", box(wx + 0.12, wx + 0.36, cy - 0.25, cy - 0.08, 1.1, 1.13), IRON, bevel=0.004)
    obj("InkPadFelt", box(wx + 0.14, wx + 0.34, cy - 0.23, cy - 0.1, 1.13, 1.132), RED)
    fs = bmesh.new()
    for x, y, n in ((-2.5, cy - 0.05, 9), (-2.15, cy + 0.05, 14), (-1.75, cy - 0.1, 6), (0.2, cy, 11), (0.55, cy + 0.08, 17), (-0.45, cy + 0.1, 5)):
        z = 1.1
        for k in range(n):
            t_ = rnd.uniform(0.012, 0.03)
            box(-0.15, 0.15, -0.2, 0.2, z, z + t_, bm=fs, m=Matrix.Translation((x + rnd.uniform(-0.015, 0.015), y, 0)) @ Matrix.Rotation(rnd.uniform(-0.08, 0.08), 4, 'Z'))
            z += t_
    obj("FormStacks", fs, FORMS)
    hg = bmesh.new(); hx, hy = 0.6, cy - 0.2
    for z in (1.1, 1.38):
        lathe([(0, 0), (0.07, 0), (0.07, 0.02), (0, 0.02)], 16, Matrix.Translation((hx, hy, z)), bm=hg)
    for k in range(3):
        a = math.tau*k/3
        box(-0.008, 0.008, -0.008, 0.008, 1.12, 1.38, bm=hg, m=Matrix.Translation((hx + 0.058*math.cos(a), hy + 0.058*math.sin(a), 0)))
    obj("HourglassFrame", hg, DARK)
    obj("HourglassGlass", lathe([(0, 0), (0.05, 0.0), (0.05, 0.03), (0.012, 0.13), (0.05, 0.23), (0.05, 0.26), (0, 0.26)], 20, Matrix.Translation((hx, hy, 1.12))),
        mat("HGlass", (0.95, 0.95, 0.95), Roughness=0.0, **{"Transmission Weight": 1.0})[0], smooth=True)
    obj("Sand", lathe([(0, 0), (0.045, 0), (0.045, 0.02), (0.02, 0.08), (0, 0.09)], 16, Matrix.Translation((hx, hy, 1.15))), mottle("SandM", (0.7, 0.55, 0.3), 0.2, 50), smooth=True)
    obj("Ledger", box(-1.55, -1.15, cy - 0.3, cy - 0.04, 1.1, 1.14, m=Matrix.Rotation(0.06, 4, 'Z')), mottle("Binding", (0.12, 0.12, 0.1), 0.2, 15, 0.7), bevel=0.004)
    obj("LedgerPages", box(-1.53, -1.17, cy - 0.28, cy - 0.06, 1.14, 1.15, m=Matrix.Rotation(0.06, 4, 'Z')), PAPER)
    obj("InkPot", lathe([(0, 0), (0.035, 0), (0.035, 0.05), (0.014, 0.065), (0, 0.065)], 14, Matrix.Translation((-1.05, cy - 0.12, 1.1))), INK, smooth=True)
    obj("Quill", box(-0.003, 0.003, -0.002, 0.002, 0, 0.27, m=Matrix.Translation((-1.05, cy - 0.12, 1.13)) @ Matrix.Rotation(0.4, 4, 'Y')), PAPER)
    # a lamp behind the counter, its shade green, and one hung in the hall
    for x in (-2.3, 0.1):
        obj("LampStem", lathe([(0, 0), (0.07, 0), (0.06, 0.02), (0.012, 0.03), (0.012, 0.3), (0, 0.3)], 16, Matrix.Translation((x, cy + 0.2, 1.1))), IRON, smooth=True)
        obj("LampShade", box(x - 0.16, x + 0.16, cy + 0.12, cy + 0.28, 1.38, 1.46), emit("Shade", (0.3, 0.7, 0.35), 2.0), bevel=0.03)
        light('POINT', (x, cy + 0.2, 1.34), 20, (1.0, 0.9, 0.7), size=0.08)

    # the name over the pigeonholes
    obj("NameBoard", box(-3.2, 0.8, Y1 - 0.06, Y1, 2.98, 3.14), DARK)
    text("Name", "ULARN REVENUE SERVICE  -  DISTRICT OFFICE", (-1.2, Y1 - 0.08, 3.06), 0.1, mottle("Brass", (0.6, 0.45, 0.2), 0.1, 20, 0.4), extrude=0.003)
    # the notice board on the right of the back wall, its demands
    nb = obj("NoticeBoard", box(1.5, 3.3, Y1 - 0.05, Y1, 1.1, 2.5), CORK)
    obj("NoticeFrame", box(1.45, 3.35, Y1 - 0.03, Y1, 1.05, 2.55), DARK)
    notes = (("TAXES", "ARE DUE", 1.85, 2.05, 0.5, 0.45, 0.0), ("PAY", "OR ELSE", 2.6, 2.2, 0.38, 0.35, 0.05), ("NOW SERVING", "No. 7", 3.0, 1.5, 0.45, 0.3, -0.04),
             ("WANTED", "TAX EVADER", 2.1, 1.45, 0.42, 0.42, 0.03))
    for k, (l1, l2, x, z, w, h, rot) in enumerate(notes):
        nm = Matrix.Translation((x, Y1 - 0.06, z)) @ Matrix.Rotation(rot, 4, 'Y')
        obj(f"Notice{k}", box(-w/2, w/2, -0.003, 0.003, -h/2, h/2, m=nm), PAPER)
        for j, line in enumerate((l1, l2)):
            t = text(f"NoticeText{k}{j}", line, nm @ Vector((0, -0.006, h*0.18 - h*0.32*j)), w*0.16 if j else w*0.2, RED if j == 0 else LETTER, extrude=0.001)
            t.rotation_euler = (math.pi/2, rot, 0)
        obj(f"Pin{k}", ball(nm @ Vector((0, -0.01, h/2 - 0.03)), 0.012), RED)
    pt = bmesh.new()                                # a face drawn on the wanted notice
    fm_ = Matrix.Translation((2.1, Y1 - 0.066, 1.43)) @ Matrix.Rotation(0.03, 4, 'Y') @ Matrix.Rotation(math.pi/2, 4, 'X')
    lathe([(0.065, 0), (0.075, 0), (0.075, 0.001), (0.065, 0.001)], 24, fm_, bm=pt)
    obj("WantedFace", pt, LETTER)

    # the queue: iron posts and a rope, a bench to wait on along the left, a strongbox, paper on the floor
    posts = bmesh.new()
    for x, y in ((-1.4, 0.4), (-1.4, 1.6), (-0.6, 1.6), (-0.6, 0.4)):
        lathe([(0, 0), (0.12, 0), (0.1, 0.04), (0.025, 0.06), (0.022, 0.92), (0.04, 0.96), (0, 1.0)], 16, Matrix.Translation((x, y, 0)), bm=posts)
    obj("QueuePosts", posts, IRON, smooth=True)
    rope = bmesh.new()
    for (xa, ya), (xb, yb) in (((-1.4, 0.4), (-1.4, 1.6)), ((-0.6, 0.4), (-0.6, 1.6))):
        pts = [Vector((xa + (xb - xa)*k/12, ya + (yb - ya)*k/12, 0.9 - 0.16*math.sin(math.pi*k/12))) for k in range(13)]
        for a_, b_ in zip(pts, pts[1:]):
            d = b_ - a_; lathe([(0.018, 0), (0.018, d.length)], 8, Matrix.Translation(a_) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4(), bm=rope)
    obj("QueueRope", rope, mottle("RopeM", (0.35, 0.3, 0.2), 0.3, 60, 1.0), smooth=True)
    bn = bmesh.new()
    box(X0 + 0.05, X0 + 0.5, -1.4, 1.2, 0.42, 0.48, bm=bn); box(X0 + 0.05, X0 + 0.1, -1.4, 1.2, 0.48, 0.95, bm=bn)
    for y in (-1.3, 1.1):
        box(X0 + 0.1, X0 + 0.45, y - 0.04, y + 0.04, 0, 0.42, bm=bn)
    obj("WaitBench", bn, DARK, bevel=0.008)
    sbm = Matrix.Translation((2.6, 2.7, 0))
    obj("Strongbox", box(-0.45, 0.45, -0.3, 0.3, 0, 0.6, m=sbm), IRON, bevel=0.02)
    rv = bmesh.new()
    for k in range(9):
        for z in (0.06, 0.54):
            ball(sbm @ Vector((-0.4 + 0.1*k, -0.305, z)), 0.012, bm=rv, segs=8)
    box(-0.07, 0.07, -0.33, -0.3, 0.3, 0.48, bm=rv, m=sbm)
    obj("StrongboxRivets", rv, BRASS, smooth=True)
    text("StrongboxTax", "TAX", sbm @ Vector((0, -0.31, 0.2)), 0.12, mottle("WhitePaint", (0.75, 0.73, 0.68), 0.2, 30), extrude=0.001)
    fl = bmesh.new()
    for k in range(9):                              # forms dropped on the floor
        box(-0.1, 0.1, -0.14, 0.14, 0.002, 0.004, bm=fl, m=Matrix.Translation((rnd.uniform(-2.5, 1.5), rnd.uniform(0.2, 2.3), 0)) @ Matrix.Rotation(rnd.uniform(0, math.tau), 4, 'Z'))
    obj("FloorForms", fl, FORMS)
    bx = bmesh.new()                                # boxes of files by the strongbox
    for x, y, z, w in ((1.5, 2.9, 0, 0.5), (1.55, 2.95, 0.4, 0.45), (3.2, 1.9, 0, 0.5)):
        box(-w/2, w/2, -0.2, 0.2, z, z + 0.4, bm=bx, m=Matrix.Translation((x, y, 0)) @ Matrix.Rotation(rnd.uniform(-0.15, 0.15), 4, 'Z'))
    obj("FileBoxes", bx, DARK, bevel=0.01)

    lm = bmesh.new()                                # a plain iron lamp hung in the hall
    lathe([(0.005, 2.4), (0.005, H)], 6, Matrix.Translation((1.3, 0.9, 0)), bm=lm)
    lathe([(0, 2.15), (0.2, 2.15), (0.18, 2.2), (0.04, 2.38), (0.03, 2.4), (0, 2.4)], 24, Matrix.Translation((1.3, 0.9, 0)), bm=lm)
    obj("HallLamp", lm, IRON, smooth=True)
    obj("HallLampGlow", lathe([(0, 2.1), (0.06, 2.1), (0.06, 2.16), (0, 2.16)], 16, Matrix.Translation((1.3, 0.9, 0))), emit("Bulb", (1.0, 0.85, 0.6), 8.0))
    light('POINT', (1.3, 0.9, 2.0), 70, (1.0, 0.88, 0.7), size=0.15)
    light('AREA', (0, -2.0, 2.8), 60, (0.85, 0.9, 1.0), size=4, aim=(0, 2, 0.9))   # fill, cold
    camera((0.0, -2.8, 1.6), (0.0, 4.2, 1.6), 22)

def den():
    """Grizzik's Questionable Elixirs: a goblin's cramped den in the rock.  A counter knocked up from crates and a
    plank under a sign painted by hand, crooked shelves of mismatched bottles (some of them glowing), a cauldron
    bubbling green over a fire, an alembic and copper coils on a bench, pipes along the rock with a valve and a
    gauge, crates marked DO NOT SHAKE, jars of glow hung on a string.  Back wall y = 3.2."""
    X0, X1, Y1, H = -3.0, 3.0, 3.2, 2.7
    ROCK = rock_material("DenRock", (0.36, 0.33, 0.3), scale=0.7)[0]
    FLOORROCK = rock_material("DenFloor", (0.26, 0.24, 0.21), scale=0.9)[0]
    OLDWOOD = wood_material("OldWood", (0.1, 0.065, 0.035), axis="X", roughness=0.9)
    OLDWOODZ = wood_material("OldWoodZ", (0.1, 0.065, 0.035), axis="Z", roughness=0.9)
    COPPER = mat("Copper", (0.85, 0.45, 0.25), Metallic=1.0, Roughness=0.35)[0]
    VERDI = mottle("Verdigris", (0.25, 0.42, 0.33), amount=0.4, scale=15, rough=0.6)
    next(n for n in VERDI.node_tree.nodes if n.type == 'BSDF_PRINCIPLED').inputs["Metallic"].default_value = 0.4
    PAINT = mottle("GreenPaint", (0.55, 0.85, 0.2), amount=0.2, scale=30, rough=0.8)
    REDPAINT = mottle("RedPaint", (0.7, 0.08, 0.04), amount=0.2, scale=30, rough=0.8)
    BREW = emit("Brew", (0.35, 1.0, 0.15), 3.0, (0.1, 0.3, 0.05))
    GLASS = mat("Glass", (0.85, 0.95, 0.9), Roughness=0.02, **{"Transmission Weight": 1.0})[0]
    GLOWS = [emit(f"Glow{k}", c, 0.6, tuple(x*0.15 for x in c)) for k, c in enumerate(((0.3, 1.0, 0.2), (0.7, 0.2, 1.0), (1.0, 0.5, 0.1), (0.2, 0.6, 1.0)))]
    DULL = [mat(f"Dull{k}", c, Roughness=0.08, IOR=1.45, **{"Transmission Weight": 1.0})[0] for k, c in enumerate(
        ((0.5, 0.25, 0.05), (0.15, 0.4, 0.1), (0.5, 0.05, 0.1), (0.25, 0.2, 0.15), (0.8, 0.8, 0.7)))]

    obj("Floor", rough(grid(X0 - 0.5, X1 + 0.5, -5, Y1 + 0.5, 2, 0.0, 60), 2, 0.025, 2.5, 11), FLOORROCK, smooth=True)
    obj("BackWall", rough(grid(X0 - 0.5, X1 + 0.5, -0.2, H + 0.4, 1, Y1, 50), 1, 0.12, 1.3, 12), ROCK, smooth=True)
    obj("LeftWall", rough(grid(-5, Y1 + 0.3, -0.2, H + 0.4, 0, X0, 60), 0, 0.15, 1.1, 13), ROCK, smooth=True)
    obj("RightWall", rough(grid(-5, Y1 + 0.3, -0.2, H + 0.4, 0, X1, 60), 0, 0.15, 1.1, 14), ROCK, smooth=True)
    obj("Ceiling", rough(grid(X0 - 0.5, X1 + 0.5, -5, Y1 + 0.5, 2, H, 60), 2, 0.12, 1.0, 15), ROCK, smooth=True)

    # the counter: crates in a row and a plank on them, the sign over it, the notices on it
    cx0, cx1, cy = -1.5, 0.9, 2.15
    cr = bmesh.new()
    x = cx0
    for k in range(3):
        w = (cx1 - cx0)/3
        box(x + 0.02, x + w - 0.02, cy - 0.28, cy + 0.28, 0, 0.9 - 0.03*(k % 2), bm=cr, m=Matrix.Translation((x + w/2, cy, 0)) @ Matrix.Rotation(rnd.uniform(-0.04, 0.04), 4, 'Z') @ Matrix.Translation((-x - w/2, -cy, 0)))
        x += w
    obj("CounterCrates", cr, OLDWOOD, bevel=0.012)
    sl = bmesh.new()                                # the slats on the crates' fronts
    for k in range(3):
        xa = cx0 + (cx1 - cx0)*k/3
        for z in (0.15, 0.45, 0.75):
            box(xa + 0.03, xa + (cx1 - cx0)/3 - 0.03, cy - 0.3, cy - 0.28, z - 0.05, z + 0.05, bm=sl)
    obj("CrateSlats", sl, OLDWOODZ)
    obj("CounterPlank", box(cx0 - 0.15, cx1 + 0.2, cy - 0.36, cy + 0.32, 0.9, 0.95, m=Matrix.Translation((0, cy, 0.92)) @ Matrix.Rotation(0.015, 4, 'Y') @ Matrix.Translation((0, -cy, -0.92))), OLDWOOD, bevel=0.006)
    text("ShakeA", "DO NOT SHAKE", (cx0 + (cx1 - cx0)/6, cy - 0.31, 0.45), 0.06, REDPAINT, extrude=0.001)
    sg = obj("Sign", box(-1.25, 1.25, -0.02, 0.02, -0.22, 0.22), OLDWOOD, bevel=0.01)
    sg.location = ((cx0 + cx1)/2, Y1 - 0.25, 2.2); sg.rotation_euler = (0, math.radians(-3), 0)
    for k, (line, size, z) in enumerate((("GRIZZIK'S", 0.13, 0.08), ("QUESTIONABLE ELIXIRS", 0.11, -0.1))):
        t = text(f"SignText{k}", line, (0, -0.025, z), size, PAINT, extrude=0.002); t.parent = sg
    for k, (line, x, y, z, rot) in enumerate((("NO REFUNDS", 1.6, Y1 - 0.15, 1.55, 0.08), ("ONE EACH!", -0.3, cy - 0.32, 0.62, -0.06))):
        nm = Matrix.Translation((x, y, z)) @ Matrix.Rotation(rot, 4, 'Y')
        obj(f"Notice{k}", box(-0.3, 0.3, -0.004, 0.004, -0.09, 0.09, m=nm), PAPER)
        t = text(f"NoticeText{k}", line, nm @ Vector((0, -0.006, 0)), 0.07, REDPAINT, extrude=0.001); t.rotation_euler = (math.pi/2, rot, 0)

    def bottles(x0, x1, y, z, glow_chance=0.25):
        x = x0
        while x < x1:
            r = rnd.uniform(0.035, 0.07); h = rnd.uniform(0.14, 0.32)
            prof = rnd.choice(([(0, 0), (r, 0), (r, 0.6*h), (0.35*r, 0.78*h), (0.3*r, h), (0, h)],
                               [(0, 0), (0.6*r, 0), (r, 0.3*h), (0.9*r, 0.55*h), (0.3*r, 0.75*h), (0.3*r, h), (0, h)],
                               [(0, 0), (r, 0), (r*0.7, 0.5*h), (r*1.05, 0.7*h), (0.3*r, 0.85*h), (0.3*r, h), (0, h)],
                               [(0, 0), (0.5*r, 0), (r, 0.5*h), (0.2*r, 0.8*h), (0.25*r, h), (0, h)]))
            m_ = Matrix.Translation((x + r, y + rnd.uniform(-0.05, 0.05), z)) @ Matrix.Rotation(rnd.uniform(-0.08, 0.08), 4, 'Y')
            pick = rnd.choice(GLOWS) if rnd.random() < glow_chance else rnd.choice(DULL)
            bpy_ = lathe(prof, 14, m_); merge(by_mat.setdefault(pick.name, (pick, bmesh.new()))[1], bpy_)
            lathe([(0, h), (0.3*r + 0.004, h), (0.3*r + 0.004, h + 0.035), (0, h + 0.035)], 8, m_, bm=corks)
            x += 2*r + rnd.uniform(0.01, 0.05)
    by_mat = {}; corks = bmesh.new()
    # crooked shelves on the rock behind the counter
    sh = bmesh.new()
    for k, (z, tilt) in enumerate(((1.15, 0.03), (1.6, -0.025))):
        m = Matrix.Translation((-0.3, Y1 - 0.3, z)) @ Matrix.Rotation(tilt, 4, 'Y')
        box(-1.5, 1.5, -0.15, 0.15, -0.03, 0.0, bm=sh, m=m)
        for x in (-1.2, 1.2):
            box(x - 0.02, x + 0.02, 0.1, 0.16, -0.25, 0.0, bm=sh, m=m @ Matrix.Rotation(0.6, 4, 'X'))
        bottles(-1.7, 1.1, Y1 - 0.3, z + 0.02 - 0.02*k)
    obj("Shelves", sh, OLDWOOD)
    bottles(cx0 + 0.05, cx1 - 0.35, cy - 0.05, 0.95, glow_chance=0.4)   # the five on offer and a few more on the counter
    for k, (m_, b_) in enumerate(by_mat.values()):
        obj(f"Bottles{k}", b_, m_, smooth=True)
    obj("Corks", corks, mottle("Cork", (0.35, 0.22, 0.12), 0.3, 40, 0.9))
    obj("Bell", lathe([(0, 0), (0.06, 0), (0.05, 0.02), (0.03, 0.07), (0.015, 0.085), (0.007, 0.085), (0.007, 0.11), (0, 0.12)], 16,
                      Matrix.Translation((cx1 - 0.15, cy - 0.15, 0.95))), BRASS, smooth=True)

    # the cauldron on the left, bubbling green over a fire; a pipe from its hood up into the rock
    kx, ky = -2.05, 1.2
    obj("Cauldron", lathe([(0.0, 0.25), (0.3, 0.27), (0.45, 0.45), (0.48, 0.65), (0.42, 0.85), (0.44, 0.88), (0.4, 0.9), (0.38, 0.85), (0.4, 0.7),
                           (0.0, 0.7)], 32, Matrix.Translation((kx, ky, 0))), IRON, smooth=True)
    obj("BrewTop", lathe([(0, 0.8), (0.39, 0.8), (0.39, 0.81), (0, 0.81)], 32, Matrix.Translation((kx, ky, 0))), BREW)
    bb = bmesh.new()
    for k in range(9):
        a = rnd.uniform(0, math.tau); d = rnd.uniform(0, 0.3)
        ball((kx + d*math.cos(a), ky + d*math.sin(a), 0.82), rnd.uniform(0.025, 0.06), (1, 1, 0.7), bm=bb, segs=12)
    obj("Bubbles", bb, emit("BubbleM", (0.5, 1.0, 0.3), 4.0, (0.2, 0.4, 0.1)), smooth=True)
    lg = bmesh.new()
    for k in range(3):
        a = math.tau*k/3 + 0.4
        lathe([(0, 0), (0.04, 0), (0.04, 0.26), (0, 0.26)], 10, Matrix.Translation((kx + 0.3*math.cos(a), ky + 0.3*math.sin(a), 0)), bm=lg)
    obj("CauldronLegs", lg, IRON)
    logs = bmesh.new()
    for k in range(4):
        a = math.tau*k/4 + 0.3
        lathe([(0.04, -0.28), (0.04, 0.28), (0, 0.28)], 10, Matrix.Translation((kx, ky, 0.05)) @ Matrix.Rotation(a, 4, 'Z') @ Matrix.Rotation(math.pi/2, 4, 'Y'), bm=logs)
    obj("FireLogs", logs, mottle("Charred", (0.05, 0.03, 0.02), 0.5, 10))
    for k in range(3):
        flame_sheet(f"Fire{k}", (kx + (k - 1)*0.12, ky - 0.25 + 0.02*k, 0.05), 0.3, 0.32, 1.3*k, toward=(0, -3.5, 1.4))
    light('POINT', (kx + 0.2, ky - 0.45, 0.25), 40, (1.0, 0.45, 0.1), size=0.15)
    light('POINT', (kx, ky, 1.2), 60, (0.45, 1.0, 0.25), size=0.3)
    obj("Hood", lathe([(0.5, 0), (0.15, 0.35), (0.12, 0.4), (0.0, 0.4)], 24, Matrix.Translation((kx, ky, 1.55))), COPPER, smooth=True)
    pp = bmesh.new()
    lathe([(0.07, 0), (0.07, H - 1.95 + 0.2)], 14, Matrix.Translation((kx, ky, 1.9)), bm=pp)
    obj("HoodPipe", pp, VERDI, smooth=True)

    # copper pipes along the back wall right, a valve and a gauge; the alchemy bench under them
    pp = bmesh.new()
    for z in (2.0, 2.15):
        lathe([(0.04, 0), (0.04, X1 - 0.9)], 14, Matrix.Translation((1.0, Y1 - 0.2, z)) @ Matrix.Rotation(math.pi/2, 4, 'Y'), bm=pp)
    lathe([(0.04, 0), (0.04, 1.2)], 14, Matrix.Translation((2.4, Y1 - 0.2, 0.9)), bm=pp)
    for x in (1.4, 2.4):
        lathe([(0.055, -0.05), (0.055, 0.05)], 14, Matrix.Translation((x, Y1 - 0.2, 2.0)) @ Matrix.Rotation(math.pi/2, 4, 'Y'), bm=pp)
    obj("Pipes", pp, COPPER, smooth=True)
    vm = Matrix.Translation((1.85, Y1 - 0.31, 2.0)) @ Matrix.Rotation(math.pi/2, 4, 'X')
    vw = lathe([(0.12, -0.012), (0.14, -0.012), (0.14, 0.012), (0.12, 0.012)], 24, vm)
    for k in range(4):
        box(-0.12, 0.12, -0.01, 0.01, -0.008, 0.008, bm=vw, m=vm @ Matrix.Rotation(math.pi*k/4, 4, 'Z'))
    lathe([(0.012, 0), (0.012, 0.12)], 8, Matrix.Translation((1.85, Y1 - 0.2, 2.0)) @ Matrix.Rotation(math.pi/2, 4, 'X'), bm=vw)
    obj("Valve", vw, REDPAINT, smooth=True)
    gm = Matrix.Translation((2.4, Y1 - 0.3, 1.75)) @ Matrix.Rotation(math.pi/2, 4, 'X')
    obj("Gauge", lathe([(0, 0), (0.11, 0), (0.11, 0.06), (0.095, 0.06), (0.095, 0.05), (0, 0.05)], 24, gm), BRASS, smooth=True)
    obj("GaugeFace", lathe([(0, 0.045), (0.095, 0.045), (0.095, 0.05), (0, 0.05)], 24, gm), PAPER)
    obj("GaugeNeedle", box(-0.005, 0.005, 0, 0.08, 0.052, 0.056, m=gm @ Matrix.Rotation(-1.1, 4, 'Z')), REDPAINT)
    bx0, bx1, by = 1.3, 2.8, 2.5
    obj("BenchTop", box(bx0, bx1, by - 0.35, by + 0.35, 0.82, 0.88), OLDWOOD, bevel=0.006)
    bl = bmesh.new()
    for x in (bx0 + 0.06, bx1 - 0.06):
        for y in (by - 0.3, by + 0.3):
            box(x - 0.04, x + 0.04, y - 0.04, y + 0.04, 0, 0.82, bm=bl)
    obj("BenchLegs", bl, OLDWOODZ)
    am = Matrix.Translation((1.65, by, 0.88))       # the alembic: a round flask on a little burner, its neck curving off to a coil
    obj("Burner", lathe([(0, 0), (0.08, 0), (0.08, 0.06), (0.03, 0.08), (0.03, 0.12), (0, 0.12)], 14, am), BRASS, smooth=True)
    obj("BurnerFlame", lathe([(0, 0), (0.02, 0.02), (0.012, 0.05), (0, 0.08)], 10, am @ Matrix.Translation((0, 0, 0.12))), emit("BlueFlame", (0.3, 0.5, 1.0), 12.0))
    fl = bmesh.new()
    lathe([(0, 0.2), (0.08, 0.21), (0.13, 0.28), (0.13, 0.36), (0.08, 0.43), (0.03, 0.47), (0.025, 0.55), (0, 0.55)], 20, am, bm=fl)
    obj("Flask", fl, GLASS, smooth=True)
    obj("FlaskBrew", lathe([(0, 0.215), (0.08, 0.22), (0.12, 0.28), (0.122, 0.31), (0, 0.31)], 20, am), GLOWS[1], smooth=True)
    tube = bmesh.new()
    pts = [am @ Vector((0.0, 0, 0.55))] + [am @ Vector((0.4*t, 0, 0.55 + 0.12*math.sin(math.pi*t) - 0.25*t*t)) for t in (0.2, 0.4, 0.6, 0.8, 1.0)]
    for a_, b_ in zip(pts, pts[1:]):
        d = b_ - a_; lathe([(0.012, 0), (0.012, d.length)], 8, Matrix.Translation(a_) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4(), bm=tube)
    obj("Tube", tube, GLASS, smooth=True)
    coil = bmesh.new()                              # the copper coil, dripping into a jar
    cxc = 2.1
    cp = [Vector((cxc + 0.1*math.cos(t*0.5), by + 0.1*math.sin(t*0.5), 1.15 - 0.012*t)) for t in range(0, 26)]
    for a_, b_ in zip(cp, cp[1:]):
        d = b_ - a_; lathe([(0.012, 0), (0.012, d.length)], 8, Matrix.Translation(a_) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4(), bm=coil)
    obj("Coil", coil, COPPER, smooth=True)
    obj("Jar", lathe([(0, 0), (0.08, 0), (0.08, 0.18), (0.06, 0.2), (0, 0.2)], 16, Matrix.Translation((cxc, by, 0.88))), GLASS, smooth=True)
    obj("JarBrew", lathe([(0, 0.005), (0.077, 0.005), (0.077, 0.09), (0, 0.09)], 16, Matrix.Translation((cxc, by, 0.88))), GLOWS[0], smooth=True)
    for k, (x, c) in enumerate(((2.45, 2), (2.6, 3), (2.7, 0))):
        m_ = Matrix.Translation((x, by - 0.15 + 0.1*k, 0.88))
        obj(f"BenchFlask{k}", lathe([(0, 0), (0.06, 0), (0.06, 0.02), (0.02, 0.12), (0.02, 0.18), (0, 0.18)], 14, m_), GLASS, smooth=True)
        obj(f"BenchBrew{k}", lathe([(0, 0.003), (0.057, 0.003), (0.057, 0.02), (0.035, 0.07), (0, 0.07)], 14, m_), GLOWS[c], smooth=True)
    light('POINT', (2.1, by - 0.2, 1.2), 25, (0.8, 0.6, 1.0), size=0.2)

    # crates in the right corner, DO NOT SHAKE; a strongbox by the counter
    cb = bmesh.new()
    for x, y, z, sz, a in ((2.35, 1.05, 0, 0.6, 0.15), (2.4, 1.1, 0.6, 0.45, -0.2), (1.75, 0.6, 0, 0.45, 0.4)):
        box(-sz/2, sz/2, -sz/2, sz/2, z, z + sz, bm=cb, m=Matrix.Translation((x, y, 0)) @ Matrix.Rotation(a, 4, 'Z'))
    obj("Crates", cb, OLDWOOD, bevel=0.015)
    t = text("ShakeB", "DO NOT SHAKE", (0, 0, 0), 0.07, REDPAINT, extrude=0.001)
    t.location = Matrix.Translation((2.35, 1.05, 0)) @ Matrix.Rotation(0.15, 4, 'Z') @ Vector((0, -0.305, 0.32)); t.rotation_euler = (math.pi/2, 0, 0.15)
    t = text("ShakeC", "EXPLOSIVE", (0, 0, 0), 0.06, REDPAINT, extrude=0.001)
    t.location = Matrix.Translation((2.4, 1.1, 0)) @ Matrix.Rotation(-0.2, 4, 'Z') @ Vector((0, -0.23, 0.85)); t.rotation_euler = (math.pi/2, 0, -0.2)
    obj("Strongbox", box(-0.3, 0.3, -0.2, 0.2, 0, 0.35, m=Matrix.Translation((-1.0, 1.55, 0)) @ Matrix.Rotation(-0.3, 4, 'Z')), IRON, bevel=0.015)

    # jars of glow hung on a string across the front of the counter
    pts = [Vector((-2.4 + 4.6*t/16, 1.3, 2.3 - 0.35*math.sin(math.pi*t/16))) for t in range(17)]
    st = bmesh.new()
    for a_, b_ in zip(pts, pts[1:]):
        d = b_ - a_; lathe([(0.004, 0), (0.004, d.length)], 6, Matrix.Translation(a_) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4(), bm=st)
    obj("String", st, mottle("Twine", (0.4, 0.33, 0.2), 0.2, 50))
    for k, i in enumerate((3, 6, 10, 13)):
        p_ = pts[i] - Vector((0, 0, 0.18))
        obj(f"GlowJar{k}", lathe([(0, 0), (0.06, 0), (0.06, 0.14), (0.04, 0.16), (0, 0.16)], 14, Matrix.Translation(p_)), GLASS, smooth=True)
        obj(f"GlowJarFill{k}", lathe([(0, 0.01), (0.055, 0.01), (0.055, 0.11), (0, 0.11)], 14, Matrix.Translation(p_)), GLOWS[k % 4], smooth=True)
        light('POINT', p_ + Vector((0, 0, 0.06)), 6, GLOWS[k % 4].node_tree.nodes["Principled BSDF"].inputs["Emission Color"].default_value[:3], size=0.05)
    light('AREA', (0, -2.0, 2.3), 22, (1.0, 0.8, 0.6), size=3, aim=(0, 2, 0.8))   # (a little fill)
    light('POINT', (-0.3, 1.8, 1.9), 25, (1.0, 0.75, 0.45), size=0.3)              # (the shelves)
    light('POINT', (1.5, 0.2, 1.6), 20, (1.0, 0.75, 0.45), size=0.3)               # (the crates)
    camera((0.0, -3.4, 1.45), (0.0, 3.2, 1.45), 22)

WORLD = {"color": (0.01, 0.012, 0.02), "strength": 1.0}   # (an outdoor scene changes it: the sky)

def entrance():
    """The way into the dungeon, in the town at dusk: a stone portal cut into a cliff, steps going down into the dark
    behind it, a torch either side, a warning sign on a post, boulders and old bones about.  The cliff face y = 3."""
    WORLD.update(color=(0.32, 0.38, 0.55), strength=0.8)
    CLIFF = rock_material("Cliff", (0.45, 0.4, 0.34), scale=0.45)[0]
    HEWN = rock_material("Hewn", (0.55, 0.5, 0.44), scale=0.9)[0]
    STEP = rock_material("Steps", (0.4, 0.36, 0.31), scale=1.2, fade=(-0.6, -2.8))[0]
    DARKROCK = rock_material("Tunnel", (0.3, 0.27, 0.24), scale=0.8, fade=(-0.8, -3.0))[0]
    GROUND = mottle("Ground", (0.07, 0.07, 0.035), amount=0.45, scale=1.5, rough=0.95, bump=0.4)
    GRASS = mottle("Grass", (0.1, 0.16, 0.05), amount=0.4, scale=25, rough=0.95, bump=0.3)
    OLDWOOD = wood_material("SignWood", (0.12, 0.08, 0.045), axis="X", roughness=0.9)
    POST = wood_material("Post", (0.1, 0.065, 0.035), axis="Z", roughness=0.9)
    PAINT = mottle("WarnPaint", (0.75, 0.1, 0.05), amount=0.25, scale=30, rough=0.8)
    BONE = mottle("Bone", (0.6, 0.55, 0.45), amount=0.2, scale=12, rough=0.8)
    Y, PW, PH = 3.0, 1.1, 2.5                        # the cliff face, the portal's half width and height

    obj("Ground", rough(grid(-10, 10, -8, Y + 0.3, 2, 0.0, 70), 2, 0.05, 0.8, 21), GROUND, smooth=True)
    tufts = bmesh.new()
    for _ in range(600):                            # tufts of grass
        x, y = rnd.uniform(-8, 8), rnd.uniform(-5, Y - 0.4)
        if abs(x) < PW + 0.4 and y > -1.5: continue
        for k in range(5):
            a = rnd.uniform(0, math.tau)
            box(-0.008, 0.008, -0.002, 0.002, 0, rnd.uniform(0.08, 0.2), bm=tufts,
                m=Matrix.Translation((x + 0.03*math.cos(a), y + 0.03*math.sin(a), 0.0)) @ Matrix.Rotation(a, 4, 'Z') @ Matrix.Rotation(rnd.uniform(0.1, 0.5), 4, 'X'))
    obj("Grass", tufts, GRASS)
    # the cliff in three pieces round the portal (the portal's frame hides the joins)
    def crest(bm, top):                            # a ragged skyline: the top row of the cliff pushed up and down
        for v in bm.verts:
            if v.co.z > top - 1.2:
                f = (v.co.z - (top - 1.2))/1.2
                v.co.z += f*(0.9*math.sin(0.55*v.co.x + 1.0) + 0.5*math.sin(1.7*v.co.x + 2.0) + 0.25*math.sin(4.3*v.co.x))
                v.co.y += f*f*0.8                   # (leaning back over the top)
        return bm
    obj("CliffLeft", crest(rough(grid(-12, -PW - 0.2, -0.5, 4.6, 1, Y, 50), 1, 0.35, 0.7, 22), 4.6), CLIFF, smooth=True)
    obj("CliffRight", crest(rough(grid(PW + 0.2, 12, -0.5, 4.6, 1, Y, 50), 1, 0.35, 0.7, 23), 4.6), CLIFF, smooth=True)
    obj("CliffTop", crest(rough(grid(-PW - 0.6, PW + 0.6, PH + 0.3, 4.6, 1, Y, 20), 1, 0.2, 0.7, 24), 4.6), CLIFF, smooth=True)
    obj("Hills", rough(grid(-25, 25, -1, 6.5, 1, Y + 9, 40), 1, 0.6, 0.25, 25), mottle("FarHills", (0.08, 0.09, 0.07), 0.3, 1, 0.95), smooth=True)
    pt = bmesh.new()                                # the portal: two jambs, a lintel, a step at its foot
    for s_ in (-1, 1):
        box(s_*PW, s_*(PW + 0.45), Y - 0.35, Y + 0.6, 0, PH, bm=pt)
        box(s_*(PW - 0.05), s_*(PW + 0.5), Y - 0.4, Y + 0.65, PH - 0.1, PH, bm=pt)      # capitals
    box(-PW - 0.55, PW + 0.55, Y - 0.4, Y + 0.6, PH, PH + 0.55, bm=pt)
    obj("Portal", pt, HEWN, bevel=0.03)
    text("Carving", "ULARN", (0, Y - 0.415, PH + 0.27), 0.24, mottle("Carved", (0.12, 0.1, 0.08), 0.2, 20), extrude=0.004)
    # the steps going down inside, the tunnel's walls and roof (fading into the dark)
    st = bmesh.new()
    for k in range(16):
        y0 = Y - 0.35 + 0.32*k; z = -0.17*k
        box(-PW, PW, y0, y0 + 0.34, z - 0.3, z, bm=st)
    obj("Stairs", st, STEP, bevel=0.01)
    tn = bmesh.new()
    for s_ in (-1, 1):
        box(s_*PW, s_*(PW + 0.4), Y, Y + 6, -3.5, PH, bm=tn)
    box(-PW - 0.4, PW + 0.4, Y + 0.6, Y + 6, PH - 0.2, PH + 0.3, bm=tn,
        m=Matrix.Translation((0, Y + 0.6, PH)) @ Matrix.Rotation(-0.35, 4, 'X') @ Matrix.Translation((0, -Y - 0.6, -PH)))
    box(-PW - 0.4, PW + 0.4, Y + 5.5, Y + 6, -3.5, PH, bm=tn)
    obj("Tunnel", tn, DARKROCK)
    # torches in iron brackets on the jambs
    for k, s_ in enumerate((-1, 1)):
        x = s_*(PW + 0.22)
        obj(f"Bracket{k}", box(x - 0.05, x + 0.05, Y - 0.5, Y - 0.35, 1.45, 1.75), IRON)
        obj(f"Torch{k}", lathe([(0.025, 0), (0.03, 0.4), (0.042, 0.45), (0, 0.47)], 10, Matrix.Translation((x, Y - 0.55, 1.4)) @ Matrix.Rotation(0.3, 4, 'X')), POST)
        tip = Vector((x, Y - 0.55 - 0.45*math.sin(0.3), 1.4 + 0.45*math.cos(0.3)))
        flame_sheet(f"TorchFire{k}", tip - Vector((0, 0, 0.03)), 0.24, 0.45, 2.1*k, toward=(0, -5.5, 1.6))
        light('POINT', tip + Vector((0, -0.2, 0.15)), 140, (1.0, 0.5, 0.15), size=0.12)
    light('POINT', (0, Y + 0.4, 1.4), 60, (1.0, 0.45, 0.12), size=0.3)            # (a little way in, on the steps)
    # the sign by the way
    sg = obj("Sign", box(-0.6, 0.6, -0.03, 0.03, -0.25, 0.25), OLDWOOD, bevel=0.01)
    sg.location = (2.6, 0.6, 1.35); sg.rotation_euler = (0, math.radians(-7), math.radians(-12))
    for k, (line, size, z) in enumerate((("DANGER!", 0.13, 0.09), ("DUNGEON BELOW", 0.09, -0.1))):
        t = text(f"SignText{k}", line, (0, -0.035, z), size, PAINT, extrude=0.002); t.parent = sg
    obj("SignPost", lathe([(0.05, 0), (0.05, 1.5), (0, 1.5)], 10, Matrix.Translation((2.6, 0.65, 0)) @ Matrix.Rotation(0.05, 4, 'Y')), POST)
    # boulders, a skull and bones
    bl = bmesh.new()
    for x, y, r in ((-3.2, 1.6, 0.6), (-2.4, 2.4, 0.4), (3.6, 2.2, 0.7), (4.5, 1.0, 0.35), (-4.8, 0.2, 0.5), (1.8, 2.5, 0.3)):
        lump((x, y, r*0.35), r, (1.0, 0.85, 0.7), bm=bl, jit=0.3)
    obj("Boulders", bl, CLIFF, smooth=True)
    sk = bmesh.new()
    ball((0, 0.02, 0.1), 0.1, (0.82, 1.05, 0.9), bm=sk); ball((0, -0.07, 0.045), 0.06, (0.85, 0.75, 0.6), bm=sk)
    so = obj("Skull", sk, BONE, smooth=True); so.location = (-1.6, 1.3, 0.02); so.rotation_euler = (0, 0, 0.4)
    ey = bmesh.new()
    for dx, dz, r in ((-0.035, 0.1, 0.028), (0.035, 0.1, 0.028), (0, 0.06, 0.014)):
        ball((dx, -0.075, dz), r, (1, 0.6, 1.1 if r < 0.02 else 1), bm=ey)
    eo = obj("SkullHoles", ey, mat("Hole", (0.01, 0.008, 0.006), Roughness=1)[0], smooth=True); eo.parent = so
    bn = bmesh.new()
    for k in range(4):
        a = rnd.uniform(0, math.pi)
        lathe([(0.015, 0), (0.015, 0.3)], 8, Matrix.Translation((-1.9 + 0.13*k, 1.1 + rnd.uniform(-0.1, 0.1), 0.03)) @ Matrix.Rotation(math.pi/2, 4, Vector((math.cos(a), math.sin(a), 0))), bm=bn)
    obj("Bones", bn, BONE, smooth=True)

    sun = light('SUN', (0, 0, 10), 2.2, (1.0, 0.62, 0.38), aim=(-2.5, 6, 0))       # a low evening sun from behind on the right
    sun.data.angle = math.radians(3)
    light('AREA', (0, -4, 4), 60, (0.6, 0.7, 1.0), size=6, aim=(0, 3, 1))           # (the sky's light on the face)
    camera((0.0, -5.6, 1.6), (0.0, 3.0, 1.6), 24)

def volcano():
    """The volcano's shaft: P["view"] "down" looks over the rim into it, the lava glowing far below and a rope ladder
    going down; "up" looks up it from the bottom, the ladder climbing to the sky.  The shaft is round about (0, SY)."""
    view = P.get("view", "down")
    WORLD.update(color=(0.45, 0.3, 0.25) if view == "down" else (0.55, 0.65, 0.85), strength=0.7 if view == "down" else 1.2)
    SY, R0, DEPTH = 2.0, 2.2, 9.0
    ASH = rock_material("Ash", (0.25, 0.22, 0.2), scale=0.6)[0]
    BASALT = rock_material("Basalt", (0.2, 0.17, 0.15), scale=0.8)[0]
    LAVA = bpy.data.materials.new("Lava"); LAVA.use_nodes = True; nt = LAVA.node_tree; nt.nodes.clear()
    N = nt.nodes.new; Lk = nt.links.new
    em = N("ShaderNodeEmission"); out = N("ShaderNodeOutputMaterial"); Lk(em.outputs[0], out.inputs[0])
    tc = N("ShaderNodeTexCoord")
    nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 1.2; nz.inputs["Detail"].default_value = 8
    nz.inputs["Distortion"].default_value = 1.5; Lk(tc.outputs["Object"], nz.inputs["Vector"])
    vein = span(N, Lk, op(N, Lk, 'ABSOLUTE', op(N, Lk, 'SUBTRACT', nz.outputs["Fac"], 0.5)), 0.09, 0.0)   # (bright veins between crusted plates)
    n2 = N("ShaderNodeTexNoise"); n2.inputs["Scale"].default_value = 0.6; n2.inputs["Detail"].default_value = 3; Lk(tc.outputs["Object"], n2.inputs["Vector"])
    hot = op(N, Lk, 'ADD', op(N, Lk, 'MULTIPLY', vein, 0.85), op(N, Lk, 'MULTIPLY', span(N, Lk, n2.outputs["Fac"], 0.45, 0.75), 0.45))
    cr = N("ShaderNodeValToRGB"); Lk(hot, cr.inputs[0]); el = cr.color_ramp.elements
    el[0].position, el[0].color = 0.25, (0.08, 0.01, 0.0, 1); el[1].position, el[1].color = 1.0, (1.0, 0.75, 0.25, 1)
    e = el.new(0.55); e.color = (1.0, 0.25, 0.02, 1)
    Lk(cr.outputs["Color"], em.inputs["Color"]); em.inputs["Strength"].default_value = 6.0

    # the shaft and the ground round it, one mesh: rings going down the rough wall, then out over the plain
    def rad(a, z): return R0 + 0.25*math.sin(3*a + 0.6*z) + 0.15*math.sin(7*a - 1.3*z) + 0.12*math.sin(0.9*z) - 0.012*(-z)
    sh = bmesh.new(); segs = 72
    rows = []
    for i in range(14, 0, -1):                      # the plain, from far out in to the rim
        t = i/14; out = 13*t**1.6
        z = 0.15*math.exp(-((out - 0.35)/0.3)**2)   # (a little lip at the edge)
        rows.append([(rad(a_, 0) + out, z, a_) for a_ in (math.tau*j/segs for j in range(segs))])
    rings = 36
    for i in range(rings + 1):                      # the wall down to the lava
        z = -DEPTH*i/rings
        rows.append([(rad(a_, z) + rnd.uniform(-0.04, 0.04), z + 0.08*math.sin(2*a_), a_) for a_ in (math.tau*j/segs for j in range(segs))])
    vs = []
    for k, row in enumerate(rows):
        ring = []
        for r, z, a_ in row:
            zz = z + (0.12*math.sin(0.7*r*math.cos(a_)) + 0.1*math.sin(0.9*r*math.sin(a_) + 1) if k < 14 else 0)
            ring.append(sh.verts.new((r*math.cos(a_), SY + r*math.sin(a_), zz)))
        vs.append(ring)
    for k in range(len(vs) - 1):
        for j in range(segs):
            f = sh.faces.new((vs[k][j], vs[k][(j + 1) % segs], vs[k + 1][(j + 1) % segs], vs[k + 1][j]))
            f.material_index = 0 if k < 14 else 1
    bmesh.ops.recalc_face_normals(sh, faces=sh.faces)
    so = obj("Ground", sh, ASH, smooth=True); so.data.materials.append(BASALT)
    obj("Lava", rough(grid(-4, 4, SY - 4, SY + 4, 2, -DEPTH + 0.4, 40), 2, 0.08, 2.0, 32), LAVA)
    for k in range(5):
        a = math.tau*k/5
        light('POINT', (1.0*math.cos(a), SY + 1.0*math.sin(a), -DEPTH + 1.5), 800 if view == "down" else 450, (1.0, 0.35, 0.08), size=1.0)
    light('POINT', (0, SY, -DEPTH*0.6), 120, (1.0, 0.4, 0.1), size=1.5)
    # the rope ladder down the far side: two ropes, rungs, pegged to stakes at the rim
    ROPE = mottle("Rope", (0.42, 0.33, 0.2), amount=0.3, scale=80, rough=1.0, bump=0.5)
    A = math.pi/2                                   # (the far side)
    def on_wall(dx, z, inset=0.1):
        r = rad(A, z) - inset
        return Vector((dx, SY + r, z))
    rp, rg = bmesh.new(), bmesh.new()
    for s_ in (-0.22, 0.22):
        pts = [Vector((s_, SY + rad(A, 0) + 0.55, 0.2)), on_wall(s_, 0.12, -0.05)] + [on_wall(s_, -0.35*k) for k in range(1, int(DEPTH/0.35) - 2)]
        for a_, b_ in zip(pts, pts[1:]):
            d = b_ - a_; lathe([(0.018, 0), (0.018, d.length)], 8, Matrix.Translation(a_) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4(), bm=rp)
        lathe([(0.05, -0.1), (0.04, 0.45), (0, 0.5)], 10, Matrix.Translation((s_, SY + rad(A, 0) + 0.6, -0.1)), bm=rg)
    for k in range(1, int(DEPTH/0.35) - 2):
        p_ = on_wall(0, -0.35*k + 0.17)
        box(-0.24, 0.24, -0.025, 0.025, -0.02, 0.02, bm=rg, m=Matrix.Translation(p_))
    obj("LadderRopes", rp, ROPE, smooth=True); obj("LadderRungs", rg, wood_material("Rungs", (0.1, 0.065, 0.035), axis="X"))
    ly = SY + rad(A, 0)
    # rocks about the rim, a cairn by the ladder
    bl = bmesh.new()
    for _ in range(26):
        a = rnd.uniform(0, math.tau); d = rnd.uniform(R0 + 0.7, R0 + 6)
        r = rnd.uniform(0.1, 0.45)
        lump((d*math.cos(a), SY + d*math.sin(a), r*0.3), r, (1, 0.9, 0.6), bm=bl, jit=0.3)
    for k in range(5):
        lump((0.8, ly + 0.6, 0.12 + 0.17*k), 0.2 - 0.03*k, (1, 1, 0.6), bm=bl, jit=0.25)
    obj("Rocks", bl, BASALT, smooth=True)
    if view == "down":
        sun = light('SUN', (0, 0, 10), 0.6, (1.0, 0.7, 0.55), aim=(-3, 1.0, 0)); sun.data.angle = math.radians(4)
        camera((0.0, SY - 2.9, 2.3), (0.0, SY + 0.5, -DEPTH*0.8), 22)
    else:
        sky = obj("SkyDisc", lathe([(0, 0), (6, 0), (0, 0.0001)], 48, Matrix.Translation((0, SY, 2.0))), emit("SkyGlow", (0.55, 0.68, 0.95), 1.6))
        light('SPOT', (0, SY, 3.0), 3000, (1.0, 0.92, 0.82), size=1.5, aim=(0, SY, -10), spot=40)
        camera((0.1, SY - 0.9, -DEPTH + 1.8), (0.0, SY + 0.35, 0.0), 18)

{"home": home, "bank": bank, "branch": branch, "shop": shop, "trade": trade, "college": college, "lrs": lrs, "den": den,
 "entrance": entrance, "volcano": volcano}[P["kind"]]()

w = bpy.data.worlds.new("W"); sc.world = w
w.node_tree.nodes["Background"].inputs[0].default_value = (*WORLD["color"], 1)
w.node_tree.nodes["Background"].inputs[1].default_value = WORLD["strength"]
sc.render.engine = 'CYCLES'; sc.cycles.samples = P["samples"]; sc.cycles.use_denoising = True
sc.cycles.transparent_max_bounces = 32
use_device(sc)
sc.view_settings.view_transform = 'AgX'; sc.view_settings.look = 'AgX - Medium High Contrast'
sc.render.resolution_x, sc.render.resolution_y = P["res"]
sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGB'
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
if P["save_blend"]:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.splitext(OUT)[0] + ".blend")

