"""Build + render the throne standing on the ground (with a shadow).  Usage:
blender -b -P build_throne.py -- out.png '{"jewels":true, ...}'
The model is "Demon King Throne - Dark Fantasy Gothic Chair" by UNREAL JOELAB (CC-BY 4.0,
models/demon_king_throne, see CREDITS.md): horned, skull-carved dark stone, kept with its own textures.
Jewels in gold bezels are added on it (the back's medallion, the crest, the arm and seat skulls);
jewels=false gives the pried-off version: dark empty sockets.
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "throne.png"
P = dict(jewels=True, height=3.0, glow=None, veins=3.0, bright=None, rough=None, metal=None,
         gem_glow=2.5, glints=True, rim=(0.7, 0.4, 1.0), gold=(0.95, 0.68, 0.25),
         gems=[(0.75, 0.0, 0.03), (0.03, 0.12, 0.85), (0.02, 0.6, 0.15)], yaw=0, elev=20, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
if P["rough"] is None: P["rough"] = (0.12, 0.45) if P["jewels"] else (0.2, 0.55)   # jewelled: polished; pried: dulled
if P["metal"] is None: P["metal"] = 0.25 if P["jewels"] else 0.15
if P["bright"] is None: P["bright"] = 2.0 if P["jewels"] else 1.6
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
MODEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models", "demon_king_throne")

# ---- the model (a glTF: only meshes, materials and images)
bpy.ops.import_scene.gltf(filepath=os.path.join(MODEL, "scene.gltf"))
throne = next(o for o in sc.objects if o.type == 'MESH')
bpy.context.view_layer.update()
mw = throne.matrix_world.copy()
throne.parent = None; throne.matrix_world = mw                  # off the importer's empties, which then go
for o in [o for o in sc.objects if o.type == 'EMPTY']: bpy.data.objects.remove(o)
bb = [throne.matrix_world @ Vector(c) for c in throne.bound_box]
lo = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
hi = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
k = P["height"]/(hi.z - lo.z)                      # its base on the ground at the middle, P["height"] tall
mid = Vector(((lo.x + hi.x)/2, (lo.y + hi.y)/2, lo.z))
throne.matrix_world = Matrix.Scale(k, 4) @ Matrix.Translation(-mid) @ throne.matrix_world
for m in throne.data.materials:                    # lighter, polished stone; the veins glow while the jewels are on
    nt = m.node_tree; b = nt.nodes["Principled BSDF"]
    b.inputs["Emission Strength"].default_value = P["glow"] if P["glow"] is not None else (P["veins"] if P["jewels"] else 0.0)
    def between(socket, node, out="Result"):       # put node between whatever feeds socket and socket
        src = socket.links[0].from_socket
        nt.links.new(src, node.inputs[0 if node.bl_idname != 'ShaderNodeHueSaturation' else "Color"])
        nt.links.new(node.outputs[out], socket)
    hs = nt.nodes.new("ShaderNodeHueSaturation"); hs.inputs["Value"].default_value = P["bright"]
    hs.inputs["Saturation"].default_value = 1.1; between(b.inputs["Base Color"], hs, "Color")
    rr = nt.nodes.new("ShaderNodeMapRange"); rr.inputs["To Min"].default_value, rr.inputs["To Max"].default_value = P["rough"]
    between(b.inputs["Roughness"], rr)
    mm = nt.nodes.new("ShaderNodeMapRange"); mm.inputs["To Min"].default_value = P["metal"]
    between(b.inputs["Metallic"], mm)
    m.cycles.emission_sampling = 'NONE'           # (the veins are not lights: they would haze the shadow catcher)
root = bpy.data.objects.new("Throne", None); sc.collection.objects.link(root)
throne.parent = root
bpy.context.view_layer.update()

# ---- jewels in gold bezels (or empty sockets), set on the carving where a ray from the front meets it
gold, _ = mat("Gold", P["gold"], Metallic=1.0, Roughness=0.3)
gem_mats = [mat(f"Gem{i}", c, Roughness=0.02, IOR=1.75, **{"Transmission Weight": 0.5, "Coat Weight": 0.6,
                "Emission Color": (*c, 1), "Emission Strength": P["gem_glow"]})[0]   # (a glow: they read on the dark stone)
            for i, c in enumerate(P["gems"])]
for m in gem_mats: m.cycles.emission_sampling = 'NONE'   # (not lights: they would brighten the shadow catcher into a haze)
hole, _ = mat("Socket", (0.012, 0.01, 0.009), Roughness=0.8)

def part(name, bm, material, smooth=True):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = smooth
    o = link(sc, name, me); o.parent = root; o.data.materials.append(material)
    return o

def ring(bm, r, z, n):
    return [bm.verts.new((r*math.cos(math.tau*(i + 0.5)/n), r*math.sin(math.tau*(i + 0.5)/n), z)) for i in range(n)]

def band(bm, a, b):
    for i in range(len(a)):
        bm.faces.new((a[i], a[(i+1) % len(a)], b[(i+1) % len(a)], b[i]))

def gem(r):
    """Cut stone facing +Z: pavilion point sunk below, girdle at 0, table on top."""
    bm = bmesh.new(); n = 10
    tip = bm.verts.new((0, 0, -0.5*r)); g = ring(bm, r, 0.0, n); t = ring(bm, 0.6*r, 0.38*r, n)
    for i in range(n): bm.faces.new((tip, g[(i+1) % n], g[i]))
    band(bm, g, t); bm.faces.new(t)
    return bm

def bezel(r):
    """Gold collar round the stone, facing +Z."""
    bm = bmesh.new(); n = 20
    rs = [ring(bm, rr, z, n) for rr, z in ((r*1.0, -0.3*r), (r*1.38, -0.3*r), (r*1.38, 0.08*r), (r*1.12, 0.2*r), (r*0.96, 0.12*r))]
    for a, b in zip(rs, rs[1:]): band(bm, a, b)
    return bm

def socket(r):
    bm = bmesh.new(); bmesh.ops.create_circle(bm, cap_ends=True, segments=16, radius=r*1.15)
    return bm

dg = bpy.context.evaluated_depsgraph_get()
GLINTS = []                                        # (where, radius, colour) of each jewel, for its sparkle
def setting(px, py, r, c):
    """At the front view's pixel (px, py) of the 512 ortho render of the raw model (2 units across, centred):
    find the surface, set a jewel of radius r (raw units) along its normal."""
    x, z = (px - 256)/256, (256 - py)/256
    x, z = (x - mid.x)*k, (z - mid.z)*k
    r *= k
    hit, loc, nrm, *_ = sc.ray_cast(dg, Vector((x, -20, z)), Vector((0, 1, 0)))
    if hit:
        nrm = (nrm + Vector((0, -1.5, 0))).normalized()             # lean toward the front, so it reads from the camera
    else:                                                            # an open hole: sit in it, level with its rim
        rim = [sc.ray_cast(dg, Vector((x + 1.6*r*math.cos(a), -20, z + 1.6*r*math.sin(a))), Vector((0, 1, 0)))
               for a in (math.tau*i/8 for i in range(8))]
        rim = [h[1].y for h in rim if h[0]]
        if not rim: print("no surface at", px, py); return
        loc, nrm = Vector((x, sum(rim)/len(rim), z)), Vector((0, -1, 0))
    m = Matrix.Translation(loc + nrm*0.01) @ nrm.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    if P["jewels"]:
        GLINTS.append((loc + nrm*0.4*r, r, P["gems"][c % len(P["gems"])]))
        for name, bm, mt, sm in (("Bezel", bezel(r), gold, True), ("Gem", gem(r), gem_mats[c % len(gem_mats)], False)):
            bmesh.ops.transform(bm, matrix=m, verts=bm.verts); part(name, bm, mt, sm)
    else:                                                            # pried out: setting gone too, dark hole left
        bm = socket(r); bmesh.ops.transform(bm, matrix=m, verts=bm.verts); part("Hole", bm, hole)

setting(256, 203, 0.045, 0)                        # in the back's medallion (an open hole)
setting(256, 104, 0.04, 2)                         # crest skull's brow
for s in (-1, 1):
    setting(256 + s*51, 146, 0.026, 2)             # the red marks either side of the back's arch
    setting(256 + s*126, 292, 0.034, 0)            # the arm skulls' brows
setting(256, 404, 0.036, 1)                        # the seat front's skull

# ---- ground: shadow catcher
gp = bmesh.new(); bmesh.ops.create_grid(gp, x_segments=1, y_segments=1, size=10)
ground = part("Ground", gp, hole); ground.is_shadow_catcher = True

root.rotation_euler = (0, 0, math.radians(P["yaw"]))
rig(sc, elev=P["elev"])                             # camera angle above the horizon

# ---- magic: a four-point star sparkle on each jewel, facing the camera, and a violet rim light from behind
def glint_mat(c):
    m = bpy.data.materials.new("Glint"); nt = m.node_tree; nt.nodes.clear(); N = nt.nodes.new; Lk = nt.links.new
    uv = N("ShaderNodeTexCoord"); sep = N("ShaderNodeSeparateXYZ"); Lk(uv.outputs["UV"], sep.inputs[0])
    def f(op, a, b=None):
        n = N("ShaderNodeMath"); n.operation = op
        for i, v in enumerate((a, b)):
            if v is None: continue
            if isinstance(v, (int, float)): n.inputs[i].default_value = v
            else: Lk(v, n.inputs[i])
        return n.outputs[0]
    dx = f('ABSOLUTE', f('SUBTRACT', sep.outputs["X"], 0.5)); dy = f('ABSOLUTE', f('SUBTRACT', sep.outputs["Y"], 0.5))
    # star: bright where one of |dx|, |dy| is small, falling off along the arm; plus a round core
    arm = lambda a, b: f('MULTIPLY', f('POWER', f('MAXIMUM', f('SUBTRACT', 1.0, f('MULTIPLY', a, 2.0)), 0.0), 3.0),
                         f('POWER', f('MAXIMUM', f('SUBTRACT', 1.0, f('MULTIPLY', b, 60.0)), 0.0), 2.0))
    core = f('POWER', f('MAXIMUM', f('SUBTRACT', 1.0, f('MULTIPLY', f('ADD', f('MULTIPLY', dx, dx), f('MULTIPLY', dy, dy)), 150.0)), 0.0), 2.0)
    a = f('MINIMUM', f('ADD', f('ADD', arm(dx, dy), arm(dy, dx)), core), 1.0)
    em = N("ShaderNodeEmission"); em.inputs["Color"].default_value = (*[0.25 + 0.75*v for v in c], 1); em.inputs["Strength"].default_value = 3
    tr = N("ShaderNodeBsdfTransparent"); mx = N("ShaderNodeMixShader"); Lk(a, mx.inputs[0])
    Lk(tr.outputs[0], mx.inputs[1]); Lk(em.outputs[0], mx.inputs[2])
    out = N("ShaderNodeOutputMaterial"); Lk(mx.outputs[0], out.inputs["Surface"])
    m.cycles.emission_sampling = 'NONE'
    return m

if P["jewels"] and P["glints"]:
    cam = sc.camera.location; dg = bpy.context.evaluated_depsgraph_get()
    for i, (at, r, c) in enumerate(GLINTS):
        w = Matrix.Rotation(math.radians(P["yaw"]), 4, 'Z') @ at
        d = w - cam
        hit, loc, *_ = sc.ray_cast(dg, cam, d.normalized(), distance=d.length)
        if hit and (loc - w).length > 3*r: continue    # the jewel is hidden from here: no sparkle
        s = r*(7 if i == 0 else 5)                  # the medallion's the brightest
        bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=s)
        uvl = bm.loops.layers.uv.new()
        for fc in bm.faces:
            for lp in fc.loops: lp[uvl].uv = (lp.vert.co.x/(2*s) + 0.5, lp.vert.co.y/(2*s) + 0.5)
        tilt = Matrix.Rotation(math.radians(12 + 17*i), 4, 'Z')    # each star turned a little differently
        face = (cam - w).normalized().to_track_quat('Z', 'Y').to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=Matrix.Translation(w + (cam - w).normalized()*0.05) @ face @ tilt, verts=bm.verts)
        me = bpy.data.meshes.new("Glint"); bm.to_mesh(me); bm.free()
        o = link(sc, "Glint", me); o.data.materials.append(glint_mat(c))
        o.visible_shadow = False; o.visible_diffuse = False; o.visible_glossy = False
if P["jewels"] and P["rim"]:
    for x in (-2.5, 2.5):                          # behind, either side: lights the horns' and skulls' edges
        l = bpy.data.lights.new("Rim", 'AREA'); l.energy = 200; l.size = 1.5; l.color = P["rim"]; l.use_shadow = False
        o = link(sc, "Rim", l); o.location = (1.2*x, 2.5, 1.8); o.visible_camera = False   # (low: not on the crest's top, seen from above)
        o.rotation_euler = (Vector((0, 0, 1.4)) - o.location).to_track_quat('-Z', 'Y').to_euler()
studio_world(sc, P["world"] if P.get("world") else (1.6 if P["jewels"] else 0.6))   # (jewelled: more for the polish to reflect)
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
