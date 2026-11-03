"""Build + render one potion.  Usage:
blender -b -P build_potion.py -- out.png '{"color":[r,g,b], ...}'  (see variants.py for keys)
"""
import bpy, bmesh, math, random, sys, json
from mathutils import Vector

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "potion.png"
P = dict(color=(0.2, 0.0, 0.45), glow=(0.45, 0.05, 0.9), glow_strength=0.6, alpha=0.9,
         transmission=0.15, sparks=26, spark_color=(0.9, 0.6, 1), shape="round",
         cap="cork", cap_color=None, fill=135, fill_frac=0.72, rot=25, lean=None, save_blend=False, seed=7)
if len(args) > 1:
    P.update(json.loads(args[1]))
random.seed(P["seed"])
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

def lathe(name, pts, steps=64, smooth=True):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vs = [bm.verts.new((r, 0, z)) for r, z in pts]
    for a, b in zip(vs, vs[1:]):
        bm.edges.new((a, b))
    bmesh.ops.spin(bm, geom=bm.verts[:]+bm.edges[:], axis=(0,0,1), cent=(0,0,0),
                   angle=math.tau, steps=steps)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    if smooth:
        for p in me.polygons: p.use_smooth = True
    return ob

# ---- body + liquid.  round/wide: lathed ellipse.  square/pyramid: 4-step lathe (square
#      cross-section) with bevelled edges and a separate round neck.
SHAPE = P["shape"]
NECK = [(0.42, 1.95), (0.30, 2.15), (0.27, 2.45), (0.34, 2.52), (0.34, 2.64), (0.27, 2.66)]
if SHAPE in ("round", "wide"):
    RX, RZ = {"round": (1.0, 1.0), "wide": (1.12, 0.85)}[SHAPE]
    cz = RZ
    dz = (cz + RZ*math.sin(math.radians(60))) - 1.866   # shift neck to match body top
    pts = [(0.0, 0.0)]
    for i in range(1, 25):                      # bottom pole -> up the body
        a = -math.pi/2 + i*(math.radians(150))/24
        pts.append((RX*math.cos(a), cz + RZ*math.sin(a)))
    pts += [(r, z+dz) for r, z in NECK]
    glass = lathe("Glass", pts)
    glass.modifiers.new("Solidify", 'SOLIDIFY').thickness = -0.05
    glass.modifiers.new("Sub", 'SUBSURF').levels = 1
    liq_pts = [(0.0, 0.06)]
    for i in range(1, 25):
        a = -math.pi/2 + i*math.radians(P["fill"])/24
        liq_pts.append(((RX-0.07)*math.cos(a), cz + (RZ-0.07)*math.sin(a)))
    top = liq_pts[-1][1]
    liq_pts += [(liq_pts[-1][0]*0.9, top+0.015), (0.0, top+0.02)]
    liquid = lathe("Liquid", liq_pts)
    def spark_ok(r, z): return (r/RX)**2 + ((z-cz)/RZ)**2 < 0.7
else:
    if SHAPE == "square":
        W, H = 1.25, 1.7                        # W = corner radius of the square section
        body = [(0, 0), (W, 0), (W, H), (0.4, H+0.08)]
        dz = H + 0.08 - 1.95
        r_in = lambda z: W - 0.1
    else:                                       # pyramid
        W, H = 1.6, 1.95
        body = [(0, 0), (W, 0), (W-0.05, 0.12), (0.38, H)]
        dz = H - 1.95
        r_in = lambda z: W - 0.05 + (0.38 - (W-0.05))*(z-0.12)/(H-0.12) - 0.12
    glass = lathe("Glass", body, steps=4, smooth=False)
    bv = glass.modifiers.new("Bevel", 'BEVEL'); bv.width = 0.08; bv.segments = 4; bv.limit_method = 'ANGLE'
    glass.modifiers.new("Solidify", 'SOLIDIFY').thickness = -0.05
    neck = lathe("GlassNeck", [(r, z+dz) for r, z in NECK])
    neck.modifiers.new("Solidify", 'SOLIDIFY').thickness = -0.05
    top = 0.06 + (H - 0.3)*P["fill_frac"]
    liquid = lathe("Liquid", [(0, 0.06), (r_in(0.06), 0.06), (r_in(top), top), (0, top)], steps=4, smooth=False)
    bv = liquid.modifiers.new("Bevel", 'BEVEL'); bv.width = 0.05; bv.segments = 3; bv.limit_method = 'ANGLE'
    for o in (glass, liquid):
        o.rotation_euler.z = math.radians(P["rot"])
    def spark_ok(r, z): return r < r_in(z)*0.55

# ---- cap (cork / wax / metal share the stopper shape)
cork = lathe("Cork", [(0,2.28+dz),(0.22,2.28+dz),(0.27,2.5+dz),(0.31,2.9+dz),(0.28,2.96+dz),(0,2.97+dz)], steps=32)
cork.modifiers.new("Sub", 'SUBSURF').levels = 1
if P["cap"] == "cork":
    disp = bpy.data.textures.new("corkn", 'CLOUDS'); disp.noise_scale = 0.12
    dm = cork.modifiers.new("Disp", 'DISPLACE'); dm.texture = disp; dm.strength = 0.025
elif P["cap"] == "wax":                     # wax seal drips over the lip
    seal = lathe("Seal", [(0,2.98+dz),(0.33,2.95+dz),(0.38,2.7+dz),(0.37,2.5+dz),(0.33,2.48+dz)], steps=32)
    seal.modifiers.new("Sub", 'SUBSURF').levels = 2
    disp = bpy.data.textures.new("waxn", 'CLOUDS'); disp.noise_scale = 0.25
    dm = seal.modifiers.new("Disp", 'DISPLACE'); dm.texture = disp; dm.strength = 0.04

# ---- sparkles (emissive) inside liquid
sparks = []
for i in range(P["sparks"]):
    a = random.random()*math.tau; rr = random.random()**0.5*0.8
    z = random.uniform(0.25, top-0.1)
    if not spark_ok(rr, z): continue
    bpy.ops.mesh.primitive_uv_sphere_add(radius=random.uniform(0.012, 0.035), location=(rr*math.cos(a), rr*math.sin(a)*0.5, z))
    sparks.append(bpy.context.object)

# ---- materials
def mat(name, base, **kw):
    m = bpy.data.materials.new(name); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base[:3], 1)
    for k, v in kw.items():
        if k in b.inputs:
            b.inputs[k].default_value = v
    return m, b

def tint(c, k):                             # lerp colour toward white
    return tuple(x + (1-x)*k for x in c[:3])

glow = P["glow"]
m, b = mat("Glass", (0.92,0.92,0.96), **{"Roughness":0.03, "Transmission Weight":0.97, "IOR":1.15, "Specular IOR Level":0.3})
nt = m.node_tree
lw = nt.nodes.new("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.35
mr = nt.nodes.new("ShaderNodeMath"); mr.operation='MULTIPLY'; mr.inputs[1].default_value = 0.25
nt.links.new(lw.outputs["Facing"], mr.inputs[0]); nt.links.new(mr.outputs[0], b.inputs["Emission Strength"])
b.inputs["Emission Color"].default_value = (*tint(glow, 0.2), 1)
lw2 = nt.nodes.new("ShaderNodeLayerWeight"); lw2.inputs["Blend"].default_value = 0.5
ra = nt.nodes.new("ShaderNodeMapRange"); ra.inputs["From Min"].default_value = 0.0; ra.inputs["From Max"].default_value = 0.8
ra.inputs["To Min"].default_value = 0.18; ra.inputs["To Max"].default_value = 1.0
nt.links.new(lw2.outputs["Fresnel"], ra.inputs["Value"]); nt.links.new(ra.outputs["Result"], b.inputs["Alpha"])
glass.data.materials.append(m)
if SHAPE in ("square", "pyramid"): neck.data.materials.append(m)

m, b = mat("Liquid", P["color"], **{"Roughness":0.05, "Transmission Weight":P["transmission"], "IOR":1.33,
      "Emission Strength":P["glow_strength"], "Alpha":P["alpha"]})
b.inputs["Emission Color"].default_value = (*glow, 1)
liquid.data.materials.append(m)

if P["cap"] == "cork" or P["cap"] == "wax":
    m, b = mat("Cork", (0.45,0.26,0.12), Roughness=0.8)
    cn = m.node_tree.nodes.new("ShaderNodeTexNoise"); cn.inputs["Scale"].default_value = 25
    cr = m.node_tree.nodes.new("ShaderNodeValToRGB")
    m.node_tree.links.new(cn.outputs["Fac"], cr.inputs[0])
    cr.color_ramp.elements[0].color = (0.25,0.12,0.05,1); cr.color_ramp.elements[1].color = (0.6,0.38,0.2,1)
    m.node_tree.links.new(cr.outputs["Color"], b.inputs["Base Color"])
    cork.data.materials.append(m)
    if P["cap"] == "wax":
        m, b = mat("Wax", P["cap_color"] or (0.5,0.03,0.03), Roughness=0.3, **{"Coat Weight":0.5})
        seal.data.materials.append(m)
else:                                       # gold / silver metal stopper
    col = P["cap_color"] or {"gold": (1.0,0.7,0.25), "silver": (0.85,0.87,0.9)}[P["cap"]]
    m, b = mat("Metal", col, Metallic=1.0, Roughness=0.25)
    cork.data.materials.append(m)

m, b = mat("Spark", (1,1,1), **{"Emission Strength":8})
b.inputs["Emission Color"].default_value = (*P["spark_color"], 1)
for s in sparks: s.data.materials.append(m)

# ---- optional sideways lean of the whole potion (off by default)
lean = P["lean"] if P["lean"] is not None else 0
if lean:
    pivot = bpy.data.objects.new("Pivot", None); sc.collection.objects.link(pivot)
    for o in list(sc.collection.objects):
        if o.type in ('MESH', 'CURVE') and o.parent is None:
            o.parent = pivot
    pivot.rotation_euler.y = math.radians(lean)

# ---- camera / lights / render
cam = bpy.data.cameras.new("Cam"); cam.type='PERSP'; cam.lens = 85
co = bpy.data.objects.new("Cam", cam); sc.collection.objects.link(co)
tgt = Vector((0,0,1.4)); ang = math.radians(20); dist = 12
co.location = tgt + Vector((0, -dist*math.cos(ang), dist*math.sin(ang)))
co.rotation_euler = (math.pi/2 - ang, 0, 0); sc.camera = co

def area(loc, energy, size, col=(1,1,1)):
    l = bpy.data.lights.new("L", 'AREA'); l.energy = energy; l.size = size; l.color = col
    o = bpy.data.objects.new("L", l); sc.collection.objects.link(o); o.location = loc
    d = (Vector((0,0,1.4)) - o.location); o.rotation_euler = d.to_track_quat('-Z','Y').to_euler()
area((-4,-4,4), 280, 3, (1,0.95,0.9))
area((4,-3,2), 160, 3, (0.85,0.85,1))
area((0,3,2), 450, 4, tint(glow, 0.15))      # backlight in potion colour so glass/liquid glow
w = bpy.data.worlds.new("W"); sc.world = w
w.node_tree.nodes["Background"].inputs[0].default_value = (0.08,0.07,0.12,1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.6

sc.render.engine = 'CYCLES'; sc.cycles.samples = 192; sc.cycles.use_denoising = True
sc.cycles.transparent_max_bounces = 16; sc.cycles.max_bounces = 16
sc.render.film_transparent = True
sc.cycles.film_transparent_glass = True          # refractive glass/liquid keeps real alpha
sc.cycles.film_transparent_roughness = 0.1
sc.view_settings.view_transform = 'Standard'
# GPU (OptiX) if available
cp = bpy.context.preferences.addons['cycles'].preferences
for t in ('OPTIX', 'CUDA', 'HIP'):
    try:
        cp.compute_device_type = t; cp.get_devices()
    except TypeError:
        continue
    gpus = [d for d in cp.devices if d.type == t]
    if gpus:
        for d in cp.devices: d.use = d.type == t
        sc.cycles.device = 'GPU'; break
sc.render.resolution_x = sc.render.resolution_y = 512
sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGBA'
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
if P["save_blend"]:
    bpy.ops.wm.save_as_mainfile(filepath=P["save_blend"])
