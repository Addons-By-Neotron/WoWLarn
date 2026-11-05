"""Build + render one frame of a flying spell effect.  Usage:
blender -b -P build_spell.py -- out.png '{"kind":"fireball", "t":0.25, ...}'
kind: fireball (a roiling ball of flame round a white-hot heart), missile (the magic missile: a small oblong bolt of
      blue energy flying towards +x, screen right, crackling, with sparks circling it).
t: 0..1, where in the animation's loop this frame is.  Every moving part goes round a circle in t (the noise is
   read at an offset going round a circle, the sparks orbit), so t = 1 is t = 0 again: a seamless loop.
The fireball shows no direction of flight; the missile points right (turn the texture to its heading in the game).
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, rig, render

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "spell.png"
P = dict(kind="fireball", t=0.0, elev=20, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
C = Vector((0, 0, 1.4))                             # rig's target: everything is centred on it
T = math.tau*P["t"]

def sphere(name, r, material, loc=C, segs=48, bolt=None):
    """bolt=(length, taper): drawn out along x to length times as long, its back (-x) narrowing by taper (a teardrop
    flying towards +x)."""
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs//2, radius=r)
    if bolt:
        for v in bm.verts:
            u = v.co.x/r; w = 1 - bolt[1]*max(0.0, -u)
            v.co = Vector((v.co.x*bolt[0], v.co.y*w, v.co.z*w))
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = True
    o = link(sc, name, me); o.location = loc; o.data.materials.append(material)
    return o

def see_through(name, build):
    """A material mixing Transparent with an Emission: build(N, Lk) returns (emission colour, strength, alpha)."""
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    N = nt.nodes.new; Lk = nt.links.new
    out = N("ShaderNodeOutputMaterial"); mix = N("ShaderNodeMixShader"); tr = N("ShaderNodeBsdfTransparent")
    em = N("ShaderNodeEmission"); col, strength, alpha = build(N, Lk)
    Lk(col, em.inputs["Color"]); em.inputs["Strength"].default_value = strength
    Lk(alpha, mix.inputs[0]); Lk(tr.outputs[0], mix.inputs[1]); Lk(em.outputs[0], mix.inputs[2]); Lk(mix.outputs[0], out.inputs[0])
    return m

def glow(name, col, strength):
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Color"].default_value = (*col, 1); em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs[0])
    return m

def looped_coords(N, Lk, scale, amp, phase=0.0):
    """Object coordinates * scale, shifted round a circle of radius amp as t goes round (loops seamlessly)."""
    tc = N("ShaderNodeTexCoord"); mp = N("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (scale, scale, scale)
    mp.inputs["Location"].default_value = (amp*math.cos(T + phase), amp*math.sin(T + phase), amp*0.5*math.sin(T + phase))
    Lk(tc.outputs["Object"], mp.inputs["Vector"])
    return mp.outputs["Vector"]

def ramp(N, Lk, fac, stops):
    cr = N("ShaderNodeValToRGB"); Lk(fac, cr.inputs[0]); el = cr.color_ramp.elements
    el[0].position, el[0].color = stops[0][0], (*stops[0][1], 1)
    el[1].position, el[1].color = stops[-1][0], (*stops[-1][1], 1)
    for p, c in stops[1:-1]:
        e = el.new(p); e.color = (*c, 1)
    return cr.outputs["Color"]

def flame_shell(name, k, stops, strength, scale, thresh, gain, facing_w):
    """Ragged flame: noise, thicker where the shell faces the camera (so the middle is dense and the edge licks
    out in tongues), alpha = (noise + facing*facing_w - thresh)*gain."""
    def build(N, Lk):
        nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 1.0; nz.inputs["Detail"].default_value = 6
        nz.inputs["Roughness"].default_value = 0.6; nz.inputs["Distortion"].default_value = 1.5
        Lk(looped_coords(N, Lk, scale, 0.8, phase=2.1*k), nz.inputs["Vector"])
        lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.5
        fc = N("ShaderNodeMath"); fc.operation = 'SUBTRACT'; fc.inputs[0].default_value = 1.0; Lk(lw.outputs["Facing"], fc.inputs[1])
        a = N("ShaderNodeMath"); a.operation = 'MULTIPLY_ADD'; Lk(fc.outputs[0], a.inputs[0]); a.inputs[1].default_value = facing_w
        Lk(nz.outputs["Fac"], a.inputs[2])
        b = N("ShaderNodeMapRange"); b.inputs["From Min"].default_value = thresh; b.inputs["From Max"].default_value = thresh + 1/gain
        Lk(a.outputs[0], b.inputs["Value"])
        return ramp(N, Lk, b.outputs["Result"], stops), strength, b.outputs["Result"]
    return see_through(name, build)

def fireball():
    sphere("Heart", 0.3, glow("Heart", (1.0, 0.7, 0.3), 3.0))
    fire = [(0.0, (0.25, 0.01, 0.0)), (0.45, (0.8, 0.1, 0.0)), (0.8, (1.0, 0.38, 0.02)), (1.0, (1.0, 0.7, 0.2))]
    for k, (r, s, th) in enumerate(((0.38, 3.0, 0.75), (0.48, 2.6, 0.85), (0.6, 2.2, 0.95))):
        sphere(f"Flame{k}", r, flame_shell(f"Flame{k}", k, fire, 2.2 - 0.5*k, s, th, 3.0, 0.7))
    for k in range(7):                             # embers thrown off round it, orbiting slowly
        a = math.tau*k/7 + T*(1 if k % 2 else -1); rr = 0.66 + 0.06*(k % 3)
        sphere("Ember", 0.018 + 0.008*(k % 2), glow("Ember", (1.0, 0.4, 0.05), 4.0),
               loc=C + Vector((rr*math.cos(a), 0.1*math.sin(2*a), rr*0.8*math.sin(a))), segs=12)

def missile():
    BOLT = (2.2, 0.6)                              # oblong: a bolt flying towards +x (screen right), its tail thinning
    sphere("Core", 0.11, glow("Core", (0.35, 0.6, 1.0), 2.0), bolt=BOLT)
    blue = [(0.0, (0.01, 0.04, 0.5)), (0.6, (0.05, 0.25, 1.0)), (1.0, (0.3, 0.6, 1.0))]
    sphere("Aura", 0.17, bolt=BOLT, material=flame_shell("Aura", 0, blue, 1.3, 4.0, 0.6, 2.5, 0.9))
    def crackle(N, Lk):                            # thin bright lines of lightning in a shell round the core
        vo = N("ShaderNodeTexVoronoi"); vo.feature = 'DISTANCE_TO_EDGE'; vo.inputs["Scale"].default_value = 1.0
        Lk(looped_coords(N, Lk, 6.0, 0.9), vo.inputs["Vector"])
        b = N("ShaderNodeMapRange"); b.inputs["From Min"].default_value = 0.06; b.inputs["From Max"].default_value = 0.0
        Lk(vo.outputs["Distance"], b.inputs["Value"])
        return ramp(N, Lk, b.outputs["Result"], blue), 2.0, b.outputs["Result"]
    sphere("Crackle", 0.23, see_through("Crackle", crackle), bolt=BOLT)
    for k in range(3):                             # sparks circling the bolt's long axis, one turn per loop
        a = T + math.tau*k/3; x = (-0.22, 0.0, 0.22)[k]; rr = 0.2 - 0.05*abs(x)/0.22
        sphere("Spark", 0.022, glow("Spark", (0.3, 0.6, 1.0), 3.0), loc=C + Vector((x, rr*math.cos(a), rr*math.sin(a))), segs=12)
    for o in sc.objects:                           # all of it smaller (the textures are in object space: unchanged)
        o.location = C + (o.location - C)*0.75; o.scale *= 0.75

globals()[P["kind"]]()
rig(sc, elev=P["elev"])
for o in [o for o in sc.objects if o.type == 'LIGHT']:   # emission only: no lamps
    bpy.data.objects.remove(o)
sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.0
render(sc, OUT, P["save_blend"], samples=96)
