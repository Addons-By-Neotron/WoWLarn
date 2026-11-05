"""Build + render one faceted gem.  Usage:
blender -b -P build_gem.py -- out.png '{"cut":"brilliant", "color":[r,g,b], ...}'
Cuts: brilliant (round), heart, emerald (step cut), trillion (triangle), globe (a smooth ball), ball1 / ball2 (faceted balls).
inner: {"cut", "scale", "color", "strength", "yaw", "loc", "rot", "coat", "swirl" (noise scale: smoky filaments), "spin" (degrees: animation phase)} (or a list of them): glowing gems set inside (the Eye of Larn).
smoke: {"color", "inside", "around", "glow"}: wisps of glowing smoke swirling inside the stone (density inside) and
       round it (density around).
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import mat, rig, render, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "gem.png"
P = dict(cut="brilliant", color=(0.95, 0.97, 1.0), ior=2.42, glow=None, glow_strength=0.0,
         fire=False, inner=None, smoke=None, tilt=52, yaw=18, roll=0, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# ---- outlines: closed 2D curves on t in [0, 1), unit size, centred
def circle(t):
    a = t*math.tau; return (math.cos(a), math.sin(a))

def heart(t):
    a = t*math.tau
    x = 16*math.sin(a)**3
    y = 13*math.cos(a) - 5*math.cos(2*a) - 2*math.cos(3*a) - math.cos(4*a)
    return (x/17, (y+2.5)/17)

def polyline(pts):
    """Piecewise-linear closed outline through pts, parameterised by perimeter length."""
    segs = list(zip(pts, pts[1:] + pts[:1])); lens = [math.dist(a, b) for a, b in segs]; tot = sum(lens)
    def f(t):
        d = (t % 1.0)*tot
        for (a, b), l in zip(segs, lens):
            if d <= l:
                u = d/l; return (a[0] + (b[0]-a[0])*u, a[1] + (b[1]-a[1])*u)
            d -= l
        return pts[0]
    return f

W, Hh, C = 1.0, 0.7, 0.22                          # emerald cut: rectangle with chamfered corners
octagon = polyline([(W, Hh-C), (W-C, Hh), (-W+C, Hh), (-W, Hh-C), (-W, -Hh+C), (-W+C, -Hh), (W-C, -Hh), (W, -Hh+C)])

def trillion(t):                                   # triangle with slightly convex sides, rounded tips
    a = t*math.tau + math.pi/2
    r = 0.62/math.cos(((a - math.pi/2) % (math.tau/3)) - math.pi/3)**0.85
    return (r*math.cos(a), r*math.sin(a))

# ---- cuts: (outline, segments, rings).  A ring is (scale, z, half-step twist).  Twisted rings
#      between plain ones make the triangular star/kite facets of brilliant cuts; step cuts don't twist.
# Kept deliberately simple (few, large facets): the icons are shown at ~40px in game.
CUTS = {
    "brilliant": (circle, 8, [(0.0, -0.62, 0), (1.0, 0.0, 0), (1.0, 0.05, 0),
                              (0.6, 0.3, 1), (0.0, 0.3, 0)]),
    "heart":     (heart, 14, [(0.0, -0.55, 0), (1.0, 0.0, 0), (1.0, 0.05, 0),
                              (0.6, 0.27, 0), (0.0, 0.27, 0)]),
    "emerald":   (octagon, 8, [(0.1, -0.45, 0), (0.6, -0.25, 0), (1.0, 0.0, 0), (1.0, 0.05, 0),
                               (0.84, 0.17, 0), (0.7, 0.26, 0), (0.0, 0.26, 0)]),
    "trillion":  (trillion, 6, [(0.0, -0.5, 0), (1.0, 0.0, 0), (1.0, 0.05, 0),
                                (0.55, 0.25, 1), (0.0, 0.25, 0)]),
}
def gem_mesh(name, cut):
    outline, N, rings = CUTS[cut]
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    loops = []
    for s, z, tw in rings:
        if s == 0.0:
            loops.append([bm.verts.new((0, 0, z))])
        else:
            loops.append([bm.verts.new((*(c*s for c in outline((k + 0.5*tw)/N)), z)) for k in range(N)])
    for a, b in zip(loops, loops[1:]):
        if len(a) == 1 or len(b) == 1:             # fan to the culet / table centre
            ring, pt = (b, a[0]) if len(a) == 1 else (a, b[0])
            for k in range(N):
                bm.faces.new((ring[k], ring[(k+1) % N], pt))
        else:
            for k in range(N):                     # quads split into triangles so twisted rings stay planar-ish
                bm.faces.new((a[k], a[(k+1) % N], b[(k+1) % N])); bm.faces.new((a[k], b[(k+1) % N], b[k]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-6)
    bmesh.ops.dissolve_limit(bm, angle_limit=math.radians(1), verts=bm.verts, edges=bm.edges)   # merge coplanar tris (table)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    return me

def make_mesh(name, cut):
    """A cut from CUTS, or globe (a smooth ball) / ball1, ball2 (faceted balls: icospheres, flat facets)."""
    if cut == "globe" or cut.startswith("ball"):
        gb = bmesh.new()
        if cut == "globe": bmesh.ops.create_uvsphere(gb, u_segments=48, v_segments=24, radius=0.85)
        else: bmesh.ops.create_icosphere(gb, subdivisions=int(cut[4:]), radius=0.85)
        me = bpy.data.meshes.new(name); gb.to_mesh(me); gb.free()
        for f in me.polygons: f.use_smooth = cut == "globe"
        return me
    return gem_mesh(name, cut)

gem = bpy.data.objects.new("Gem", make_mesh("Gem", P["cut"])); sc.collection.objects.link(gem)
gem.scale = (0.85, 0.85, 0.85)
gem.rotation_mode = 'ZXY'
gem.rotation_euler = (math.radians(P["tilt"]), math.radians(P["roll"]), math.radians(P["yaw"]))   # tilt table toward camera
gem.location = (0, 0, 1.4)

m, b = mat("Gem", P["color"], Roughness=0.0, IOR=P["ior"], **{"Transmission Weight": 1.0})
if P["glow"]:
    b.inputs["Emission Color"].default_value = (*P["glow"], 1); b.inputs["Emission Strength"].default_value = P["glow_strength"]
gem.data.materials.append(m)
for n_, inner in enumerate([P["inner"]] if isinstance(P["inner"], dict) else P["inner"] or []):
    # smaller gems glowing inside the outer one (loc, rot: placed in its frame; rot = (x, y, z) degrees)
    I = dict(cut="trillion", scale=0.45, color=(1.0, 0.3, 0.05), strength=6.0, yaw=0, loc=(0, 0, -0.12), rot=None, coat=1.0, spin=0); I.update(inner)
    core = bpy.data.objects.new(f"Core{n_}", make_mesh(f"Core{n_}", I["cut"])); sc.collection.objects.link(core)
    core.parent = gem; core.location = I["loc"]; core.scale = (I["scale"],)*3
    core.rotation_euler = [math.radians(a) for a in I["rot"]] if I["rot"] else (0, 0, math.radians(I["yaw"]))
    core.rotation_euler.z += math.radians(I["spin"])
    cm, cb = mat(f"Core{n_}", I["color"], Roughness=0.05 if I["coat"] else 0.3, IOR=1.6, **{"Transmission Weight": 0.2, "Coat Weight": I["coat"]})
    cb.inputs["Emission Color"].default_value = (*I["color"], 1); cb.inputs["Emission Strength"].default_value = I["strength"]
    if I.get("swirl"):                             # smoky swirls: thin glowing filaments over black (warped noise)
        nt = cm.node_tree; N = nt.nodes.new; Lk = nt.links.new
        # the coarse warp is read in its own frame, turning the other way round a different axis as the core spins:
        # whole turns of both over an animation loop, so the swirls churn and the loop is seamless
        wf = bpy.data.objects.new(f"Warp{n_}", None); sc.collection.objects.link(wf); wf.parent = core
        wf.rotation_euler = (math.radians(-2*I["spin"]), 0, math.radians(-I["spin"]))
        tc = N("ShaderNodeTexCoord"); wt = N("ShaderNodeTexCoord"); wt.object = wf
        wn = N("ShaderNodeTexNoise"); wn.inputs["Scale"].default_value = 1.5
        wn.inputs["Distortion"].default_value = 2.0; Lk(wt.outputs["Object"], wn.inputs["Vector"])
        wv = N("ShaderNodeVectorMath"); wv.operation = 'MULTIPLY_ADD'; wv.inputs[1].default_value = (1.5, 1.5, 1.5)
        Lk(wn.outputs["Color"], wv.inputs[0]); Lk(tc.outputs["Object"], wv.inputs[2])
        nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = I["swirl"]; nz.inputs["Distortion"].default_value = I.get("swirl_dist", 3.0)
        nz.inputs["Detail"].default_value = 1; Lk(wv.outputs["Vector"], nz.inputs["Vector"])
        cr = N("ShaderNodeValToRGB"); Lk(nz.outputs["Fac"], cr.inputs[0]); el = cr.color_ramp.elements
        c = I["color"]; bright = tuple(min(1.0, v*1.6 + 0.25) for v in c)
        stops = ((0.46, (0, 0, 0)), (0.52, tuple(v*0.25 for v in c)), (0.56, c), (0.58, bright), (0.61, c), (0.66, tuple(v*0.2 for v in c)), (0.72, (0, 0, 0)))
        while len(el) < len(stops): el.new(0.5)
        for e, (pos, col) in zip(el, stops): e.position, e.color = pos, (*col, 1)
        Lk(cr.outputs["Color"], cb.inputs["Emission Color"]); cb.inputs["Base Color"].default_value = (0.005, 0.0, 0.01, 1)
        cb.inputs["Transmission Weight"].default_value = 0.0   # solid black between the wisps
    core.data.materials.append(cm)

def smoke(nt, color, density, glow, scale, stretch=1.0, distortion=2.0, lo=0.55, radius=None):
    """Glowing smoke into the Volume output of node tree nt: wisps (distorted noise above lo; stretch < 1 draws them
    out upward); radius: fading out to nothing at that distance from the object's centre."""
    N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord"); st = N("ShaderNodeMapping"); st.inputs["Scale"].default_value = (1.0, 1.0, stretch)
    Lk(tc.outputs["Object"], st.inputs["Vector"])
    nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = scale; nz.inputs["Distortion"].default_value = distortion
    nz.inputs["Detail"].default_value = 2; Lk(st.outputs["Vector"], nz.inputs["Vector"])
    wisp = N("ShaderNodeMapRange"); wisp.inputs["From Min"].default_value = lo; wisp.inputs["From Max"].default_value = lo + 0.25
    Lk(nz.outputs["Fac"], wisp.inputs["Value"]); d = wisp.outputs["Result"]
    if radius:
        ln = N("ShaderNodeVectorMath"); ln.operation = 'LENGTH'; Lk(tc.outputs["Object"], ln.inputs[0])
        fo = N("ShaderNodeMapRange"); fo.inputs["From Min"].default_value = 0.55; fo.inputs["From Max"].default_value = radius
        fo.inputs["To Min"].default_value = 1.0; fo.inputs["To Max"].default_value = 0.0; Lk(ln.outputs["Value"], fo.inputs["Value"])
        sq = N("ShaderNodeMath"); sq.operation = 'POWER'; sq.inputs[1].default_value = 2.0; Lk(fo.outputs["Result"], sq.inputs[0])
        mu = N("ShaderNodeMath"); mu.operation = 'MULTIPLY'; Lk(d, mu.inputs[0]); Lk(sq.outputs[0], mu.inputs[1]); d = mu.outputs[0]
    vol = N("ShaderNodeVolumePrincipled"); vol.inputs["Color"].default_value = (*(c*0.25 for c in color), 1)   # it glows, barely scatters
    vol.inputs["Emission Color"].default_value = (*color, 1)
    dm = N("ShaderNodeMath"); dm.operation = 'MULTIPLY'; dm.inputs[1].default_value = density; Lk(d, dm.inputs[0])
    em = N("ShaderNodeMath"); em.operation = 'MULTIPLY'; em.inputs[1].default_value = glow; Lk(d, em.inputs[0])
    Lk(dm.outputs[0], vol.inputs["Density"]); Lk(em.outputs[0], vol.inputs["Emission Strength"])
    Lk(vol.outputs[0], nt.nodes["Material Output"].inputs["Volume"])

if P["smoke"] is not None:
    # dense enough to have real alpha: thin glowing smoke clips to white once the PNG is un-premultiplied
    SM = dict(color=(0.4, 0.05, 1.0), inside=5.0, around=20.0, glow=3.0, scale=1.8); SM.update(P["smoke"])
    smoke(m.node_tree, SM["color"], SM["inside"], SM["glow"], 2.5, distortion=5.0, lo=0.45)   # swirling in the stone
    if SM["around"]:                               # round it: rising wisps, fading out with distance
        am = bpy.data.materials.new("Aura"); am.use_nodes = True; am.node_tree.nodes.remove(am.node_tree.nodes["Principled BSDF"])
        smoke(am.node_tree, SM["color"], SM["around"], SM["glow"], SM["scale"], stretch=0.4, radius=1.5)
        ab = bmesh.new(); bmesh.ops.create_icosphere(ab, subdivisions=3, radius=1.5)
        ame = bpy.data.meshes.new("Aura"); ab.to_mesh(ame); ab.free()
        aura = bpy.data.objects.new("Aura", ame); sc.collection.objects.link(aura); aura.location = gem.location
        aura.data.materials.append(am)

rig(sc)
studio_world(sc, 1.2, scale=0.7, distortion=0.4)  # few broad bands: each facet reads as one clean tone
spot(sc, (-2.5, -3, 4), 250, (1, 1, 1)); spot(sc, (3, -2, 3.5), 180, (1, 1, 1))
if P["fire"]:                                      # fake dispersion: coloured sparkle lights
    spot(sc, (-3.5, -1.5, 2.5), 120, (0.2, 0.6, 1)); spot(sc, (3.5, -3, 1.5), 120, (1, 0.5, 0.1)); spot(sc, (0, -4, 5), 80, (0.9, 0.3, 1))

sc.cycles.max_bounces = 24; sc.cycles.transmission_bounces = 24; sc.cycles.glossy_bounces = 16
render(sc, OUT, P["save_blend"], samples=256)
