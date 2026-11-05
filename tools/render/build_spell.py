"""Build + render one frame of a flying spell effect.  Usage:
blender -b -P build_spell.py -- out.png '{"kind":"fireball", "t":0.25, ...}'
kind: fireball (a roiling ball of flame round a white-hot heart, its flames and embers streaming back in a comet's
      tail), missile (the magic missile: a small oblong bolt of blue energy, crackling, with sparks circling it).
t: 0..1, where in the animation's loop this frame is.  Every moving part goes round a circle in t (the noise is
   read at an offset going round a circle, the sparks orbit), so t = 1 is t = 0 again: a seamless loop.
Both fly towards -x, screen left, as if cast from the right (turn the texture to its heading in the game).
kind firewall (wall of fire) and flood fill a tile instead, drawn on a flat sheet facing the camera (a billboard,
like the potions; render them at elev 0), or with solid=true as a block on the tile in 3D (render at elev 15).  frost (the cone of cold, on each tile it reaches) is the same but in 3D
(render at elev 15).  spear (the sonic spear) flies like the missile.  They play once, not looping: t = 0..1 is the whole of it, the flames or
the water rising from the bottom up to fill the tile, burning or churning a while, then dying down and fading out.
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
    """bolt=(head, tail, taper): drawn out along x, its front (-x) head times as long and its back (+x) tail times,
    the back narrowing by taper (a teardrop flying towards -x)."""
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=segs//2, radius=r)
    if bolt:
        for v in bm.verts:
            u = v.co.x/r; w = 1 - bolt[2]*max(0.0, u)
            v.co = Vector((v.co.x*(bolt[1] if u > 0 else bolt[0]), v.co.y*w, v.co.z*w))
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
    sphere("Heart", 0.3, glow("Heart", (1.0, 0.7, 0.3), 3.0), bolt=(1.0, 1.3, 0.3))
    fire = [(0.0, (0.25, 0.01, 0.0)), (0.45, (0.8, 0.1, 0.0)), (0.8, (1.0, 0.38, 0.02)), (1.0, (1.0, 0.7, 0.2))]
    for k, (r, s, th) in enumerate(((0.38, 3.0, 0.75), (0.48, 2.6, 0.85), (0.6, 2.2, 0.95))):
        sphere(f"Flame{k}", r, flame_shell(f"Flame{k}", k, fire, 1.9 - 0.5*k, s, th, 3.0, 0.7),
               bolt=(1.0, 1.7 + 0.5*k, 0.8))     # the outer flames trail furthest behind
    for k in range(9):                             # embers shed behind it, drifting back and dying out; each comes
        f = (P["t"] + k/9) % 1.0                   # round again once per loop, born small inside the flames
        a = math.tau*k*0.38 + 2.0*f; rr = 0.12 + 0.3*f
        sphere("Ember", (0.03 - 0.002*(k % 3))*math.sin(math.pi*f), glow("Ember", (1.0, 0.4, 0.05), 4.0),
               loc=C + Vector((0.35 + 1.0*f, rr*math.cos(a), rr*0.8*math.sin(a))), segs=12)
    for o in sc.objects:                           # smaller, to fit the frame with its tail; centred on ball and tail
        o.location = C + (o.location - C + Vector((-0.5, 0, 0)))*0.65; o.scale *= 0.65

def missile():
    BOLT = (2.2, 2.2, 0.6)                         # oblong: a bolt flying towards -x (screen left), its tail thinning
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

def smooth(a, b, x):
    x = min(1.0, max(0.0, (x - a)/(b - a))); return x*x*(3 - 2*x)

def op(N, Lk, o, *ins):
    """A Math node: o on ins, each a number or a socket."""
    m = N("ShaderNodeMath"); m.operation = o
    for k, v in enumerate(ins):
        if isinstance(v, (int, float)): m.inputs[k].default_value = v
        else: Lk(v, m.inputs[k])
    return m.outputs[0]

def span(N, Lk, v, a, b, smoothstep=False):
    """v mapped from a..b to 0..1, clamped."""
    m = N("ShaderNodeMapRange"); m.inputs["From Min"].default_value = a; m.inputs["From Max"].default_value = b
    if smoothstep: m.interpolation_type = 'SMOOTHSTEP'
    Lk(v, m.inputs["Value"]); return m.outputs["Result"]

def lerp(N, Lk, a, b, f):
    """Colour a towards colour b (either a socket or an rgb) by f."""
    def vec(c):
        if isinstance(c, tuple):
            n = N("ShaderNodeCombineXYZ")
            for k in range(3): n.inputs[k].default_value = c[k]
            return n.outputs[0]
        return c
    d = N("ShaderNodeVectorMath"); d.operation = 'SUBTRACT'; Lk(vec(b), d.inputs[0]); Lk(vec(a), d.inputs[1])
    sc_ = N("ShaderNodeVectorMath"); sc_.operation = 'SCALE'; Lk(d.outputs[0], sc_.inputs[0]); Lk(f, sc_.inputs["Scale"])
    ad = N("ShaderNodeVectorMath"); ad.operation = 'ADD'; Lk(vec(a), ad.inputs[0]); Lk(sc_.outputs[0], ad.inputs[1])
    return ad.outputs[0]

def noise4(N, Lk, vec, w, scale=1.0, detail=5, rough=0.55, dist=0.0, voronoi=None):
    if voronoi:
        n = N("ShaderNodeTexVoronoi"); n.voronoi_dimensions = '4D'; n.feature = voronoi
        out = n.outputs["Distance"]
    else:
        n = N("ShaderNodeTexNoise"); n.noise_dimensions = '4D'; n.inputs["Detail"].default_value = detail
        n.inputs["Roughness"].default_value = rough; n.inputs["Distortion"].default_value = dist; out = n.outputs["Fac"]
    n.inputs["Scale"].default_value = scale; n.inputs["W"].default_value = w; Lk(vec, n.inputs["Vector"])
    return out

W, H = 0.8, 0.8                                    # the tile: the sheet's half width and half height

def sheet(name, build, loc=None, h=H):
    """A flat sheet in the xz plane facing the camera (half height h, at loc, default the middle), its material from
    see_through(build), build getting (N, Lk, x, z, hb, ax) with hb the height from the bottom 0..1 and ax = |x|/W."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([(-W, 0, -h), (W, 0, -h), (W, 0, h), (-W, 0, h)], [], [(0, 1, 2, 3)])
    o = link(sc, name, me); o.location = loc or C
    def b(N, Lk):
        tc = N("ShaderNodeTexCoord"); sp = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sp.inputs[0])
        x, z = sp.outputs["X"], sp.outputs["Z"]
        hb = op(N, Lk, 'MULTIPLY_ADD', z, 1/(2*h), 0.5)
        ax = op(N, Lk, 'MULTIPLY', op(N, Lk, 'ABSOLUTE', x), 1/W)
        return build(N, Lk, x, z, hb, ax)
    o.data.materials.append(see_through(name, b))
    return o

# in 3D (P["solid"]): the effect fills the tile as a block, BH half high, standing on the floor at BASE, D half deep
BH, D = 0.62, 0.8
BASE = C.z - 0.6

def floor_glow(name, col, alpha):
    """Light thrown on the floor under it, brightest in the middle."""
    me = bpy.data.meshes.new(name)
    me.from_pydata([(-W, -D, 0), (W, -D, 0), (W, D, 0), (-W, D, 0)], [], [(0, 1, 2, 3)])
    o = link(sc, name, me); o.location = (0, 0, BASE + 0.005)
    def b(N, Lk):
        tc = N("ShaderNodeTexCoord"); vl = N("ShaderNodeVectorMath"); vl.operation = 'LENGTH'
        Lk(tc.outputs["Object"], vl.inputs[0])
        c = N("ShaderNodeRGB"); c.outputs[0].default_value = (*col, 1)
        return c.outputs[0], 1.2, op(N, Lk, 'MULTIPLY', span(N, Lk, vl.outputs["Value"], 1.0, 0.1, True), alpha)
    o.data.materials.append(see_through(name, b))

def coords(N, Lk, x, sx, z, sz, dz=0.0):
    c = N("ShaderNodeCombineXYZ"); Lk(op(N, Lk, 'MULTIPLY', x, sx), c.inputs[0])
    Lk(op(N, Lk, 'MULTIPLY_ADD', z, sz, dz), c.inputs[2]); return c.outputs[0]

def firewall():
    t = P["t"]
    rise, die = smooth(0.0, 0.35, t), smooth(0.6, 1.0, t)
    top = 0.78*rise*(1 - 0.75*die)                 # how high the flames reach, as a share of the tile
    fade = 1 - smooth(0.75, 1.0, t)
    def build(N, Lk, x, z, hb, ax, ph=0.0, dens_k=1.0):
        n = noise4(N, Lk, coords(N, Lk, x, 3.0, z, 0.9, -5.0*t), 2.0*t + ph, detail=6)  # flames licking upwards
        n2 = noise4(N, Lk, coords(N, Lk, x, 7.0, z, 2.5, -9.0*t), 3.0*t + ph, detail=3) # finer streaks in them
        d = op(N, Lk, 'MULTIPLY_ADD', op(N, Lk, 'SUBTRACT', n, 0.5), 1.7,
               op(N, Lk, 'MULTIPLY_ADD', op(N, Lk, 'SUBTRACT', top, hb), 3.0, 0.1))
        dens = op(N, Lk, 'MULTIPLY', span(N, Lk, d, 0.0, 0.55), span(N, Lk, n2, 0.25, 0.6))
        side = op(N, Lk, 'SUBTRACT', 1.0, span(N, Lk, op(N, Lk, 'MULTIPLY_ADD', n, 0.25, ax), 0.75, 1.1, True))
        dens = op(N, Lk, 'MULTIPLY', op(N, Lk, 'MULTIPLY', dens, side), span(N, Lk, hb, 0.0, 0.1, True))  # soft foot
        heat = op(N, Lk, 'MULTIPLY_ADD', op(N, Lk, 'SUBTRACT', n2, 0.45), 1.6,        # streaky, hottest low down
                  op(N, Lk, 'MULTIPLY_ADD', span(N, Lk, d, 0.0, 1.5), 0.55, op(N, Lk, 'MULTIPLY', hb, -0.3)))
        fire = [(0.0, (0.2, 0.01, 0.0)), (0.35, (0.75, 0.08, 0.0)), (0.65, (1.0, 0.35, 0.02)), (0.88, (1.0, 0.7, 0.2)), (1.0, (1.0, 0.92, 0.6))]
        return ramp(N, Lk, span(N, Lk, heat, 0.0, 1.0), fire), 1.5, op(N, Lk, 'MULTIPLY', dens, fade*dens_k)
    if not P.get("solid"):
        sheet("Fire", build); return
    # in 3D: sheets of flame one behind the other across the tile, each burning its own way, over a glowing floor
    for k, y in enumerate((-0.6, -0.2, 0.2, 0.6)):
        sheet(f"Fire{k}", lambda N, Lk, *a, k=k: build(N, Lk, *a, ph=3.7*k, dens_k=0.8),
              loc=Vector((0, y, BASE + BH)), h=BH)
    floor_glow("Glow", (1.0, 0.35, 0.05), 0.55*rise*fade)

def flood():
    t = P["t"]
    rise = smooth(0.0, 0.4, t)
    level = 0.92*rise + 0.04*math.sin(t*30)*math.exp(-6*t)*rise - 0.25*smooth(0.65, 1.0, t)   # sloshes, settles, ebbs
    fade = 1 - smooth(0.65, 1.0, t)
    def build(N, Lk, x, z, hb, ax):
        wave = op(N, Lk, 'ADD', op(N, Lk, 'MULTIPLY', op(N, Lk, 'SINE', op(N, Lk, 'MULTIPLY_ADD', x, 7.0, 25*t)), 0.025),
                  op(N, Lk, 'MULTIPLY', op(N, Lk, 'SINE', op(N, Lk, 'MULTIPLY_ADD', x, 13.0, -18*t)), 0.015))
        below = op(N, Lk, 'SUBTRACT', op(N, Lk, 'ADD', wave, level), hb)          # depth under the surface
        inside = span(N, Lk, below, 0.0, 0.015)
        foam = op(N, Lk, 'MULTIPLY', inside, op(N, Lk, 'SUBTRACT', 1.0, span(N, Lk, below, 0.0, 0.07, True)))
        rn = noise4(N, Lk, coords(N, Lk, x, 2.5, z, 2.5, -1.0*t), 2.5*t, detail=2, dist=0.8)   # ridged: rippling light
        caus = span(N, Lk, op(N, Lk, 'ABSOLUTE', op(N, Lk, 'SUBTRACT', rn, 0.5)), 0.05, 0.0, True)
        bub = span(N, Lk, noise4(N, Lk, coords(N, Lk, x, 10.0, z, 8.0, -16.0*t), 1.5*t, voronoi='F1'), 0.06, 0.035)
        bub = op(N, Lk, 'MULTIPLY', bub, span(N, Lk, below, 0.03, 0.08))          # bubbles stay under the surface
        col = lerp(N, Lk, (0.0, 0.04, 0.22), (0.03, 0.3, 0.65), hb)
        col = lerp(N, Lk, col, (0.25, 0.7, 1.0), op(N, Lk, 'MULTIPLY', caus, 0.4))
        col = lerp(N, Lk, col, (0.7, 0.92, 1.0), op(N, Lk, 'MAXIMUM', foam, bub))
        side = op(N, Lk, 'SUBTRACT', 1.0, span(N, Lk, ax, 0.9, 1.0, True))
        a = op(N, Lk, 'MULTIPLY_ADD', op(N, Lk, 'MAXIMUM', foam, op(N, Lk, 'MULTIPLY', caus, 0.5)), 0.35, 0.65)
        return col, 1.3, op(N, Lk, 'MULTIPLY', op(N, Lk, 'MULTIPLY', op(N, Lk, 'MULTIPLY', a, inside), side), fade)
    if not P.get("solid"):
        sheet("Water", build); return
    # in 3D: a block of water on the tile, its front and back the sheet's look, and the top a rippling surface
    # standing at the same wave height as the front's edge
    for y in (-D, D):
        sheet("Water", build, loc=Vector((0, y, BASE + BH)), h=BH)
    if level <= 0.01: return
    n = 32
    def wz(x, y):
        w = 0.025*math.sin(7*x + 25*t) + 0.015*math.sin(13*x - 18*t)
        return 2*BH*(level + w + 0.006*math.sin(math.pi*y/D)*math.sin(9*y + 20*t))
    vs = [(-W + 2*W*i/n, -D + 2*D*j/n) for j in range(n + 1) for i in range(n + 1)]
    me = bpy.data.meshes.new("Surface")
    me.from_pydata([(x, y, wz(x, y)) for x, y in vs], [],
                   [(j*(n + 1) + i, j*(n + 1) + i + 1, (j + 1)*(n + 1) + i + 1, (j + 1)*(n + 1) + i) for j in range(n) for i in range(n)])
    for f in me.polygons: f.use_smooth = True
    o = link(sc, "Surface", me); o.location = (0, 0, BASE)
    def top(N, Lk):
        tc = N("ShaderNodeTexCoord"); sp = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sp.inputs[0])
        rn = noise4(N, Lk, coords(N, Lk, sp.outputs["X"], 2.5, sp.outputs["Y"], 2.5, -1.0*t), 2.5*t + 5.0, detail=2, dist=0.8)
        caus = span(N, Lk, op(N, Lk, 'ABSOLUTE', op(N, Lk, 'SUBTRACT', rn, 0.5)), 0.06, 0.0, True)
        lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.3
        col = lerp(N, Lk, (0.05, 0.35, 0.72), (0.7, 0.92, 1.0), op(N, Lk, 'MAXIMUM', caus, lw.outputs["Fresnel"]))
        return col, 1.3, op(N, Lk, 'MULTIPLY', op(N, Lk, 'MULTIPLY_ADD', caus, 0.35, 0.55), fade)
    o.data.materials.append(see_through("Surface", top))

def along_x(bm, x0=0.0):
    """Turn a mesh built along +z to lie along -x (its +z end to the front, -x), shifted to start at x0."""
    for v in bm.verts:
        v.co = Vector((x0 - v.co.z, v.co.y, v.co.x))

def cone(name, r0, r1, length, material, x0, segs=24):
    """A cone along -x from x0 (radius r0) to x0 - length (radius r1)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r0, radius2=r1, depth=length)
    for v in bm.verts: v.co.z += length/2
    along_x(bm, x0)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = True
    o = link(sc, name, me); o.location = C; o.data.materials.append(material)
    return o

def torus_x(name, R, r, material, x, segs=48, rsegs=10):
    """A ring round the x axis at x, radius R, tube radius r."""
    vs = [(x + r*math.sin(math.tau*j/rsegs), (R + r*math.cos(math.tau*j/rsegs))*math.cos(math.tau*i/segs),
           (R + r*math.cos(math.tau*j/rsegs))*math.sin(math.tau*i/segs)) for i in range(segs) for j in range(rsegs)]
    fs = [(i*rsegs + j, ((i+1) % segs)*rsegs + j, ((i+1) % segs)*rsegs + (j+1) % rsegs, i*rsegs + (j+1) % rsegs)
          for i in range(segs) for j in range(rsegs)]
    me = bpy.data.meshes.new(name); me.from_pydata(vs, [], fs)
    for f in me.polygons: f.use_smooth = True
    o = link(sc, name, me); o.location = C; o.data.materials.append(material)
    return o

def arc(name, R, r, material, x, spread=70, n=24):
    """A wave front of sound facing the camera: a "(" round the x axis at x, R high, a tube r thick, bowed towards
    the front (-x)."""
    cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = r; cu.bevel_resolution = 3
    sp = cu.splines.new('POLY'); sp.points.add(n - 1)
    for i in range(n):
        th = math.radians(-spread + 2*spread*i/(n - 1))
        sp.points[i].co = (x + 0.45*R*(1 - math.cos(th)), 0, R*math.sin(th), 1)
        sp.points[i].radius = 0.35 + 0.65*math.cos(th)   # thinning to its tips
    o = link(sc, name, cu); o.location = C; o.data.materials.append(material)
    return o

def faded(name, col, strength, alpha, rim=0.0):
    """See-through glow of col at alpha (a number); rim > 0 makes the edges (facing away) brighter and more solid."""
    def build(N, Lk):
        c = N("ShaderNodeRGB"); c.outputs[0].default_value = (*col, 1)
        if not rim:
            v = N("ShaderNodeValue"); v.outputs[0].default_value = alpha
            return c.outputs[0], strength, v.outputs[0]
        lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.4
        a = op(N, Lk, 'MULTIPLY', op(N, Lk, 'MULTIPLY_ADD', lw.outputs["Facing"], rim, 1 - rim), alpha)
        return lerp(N, Lk, c.outputs[0], (0.85, 0.97, 1.0), op(N, Lk, 'MULTIPLY', lw.outputs["Facing"], rim)), strength, a
    return see_through(name, build)

def spear():
    """A spear of sound: a bright head and a shaft of energy fading back from it, with rings of sound running back
    along it, widening and dying (each comes round again once per loop)."""
    gold = (1.0, 0.82, 0.45)
    cone("Head", 0.085, 0.0, 0.32, glow("Head", (1.0, 0.72, 0.32), 1.6), -0.25)
    cone("Neck", 0.045, 0.085, 0.06, glow("Neck", (1.0, 0.65, 0.25), 1.4), -0.19)
    def shaft(N, Lk):                              # brightest at the head, gone by the tail
        tc = N("ShaderNodeTexCoord"); sp = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sp.inputs[0])
        f = span(N, Lk, sp.outputs["X"], 0.75, -0.2)
        return lerp(N, Lk, (0.8, 0.4, 0.08), gold, f), 1.4, op(N, Lk, 'MULTIPLY', f, 0.9)
    cone("Shaft", 0.0, 0.05, 0.95, see_through("Shaft", shaft), 0.75)
    for k in range(5):
        f = (P["t"] + k/5) % 1.0
        arc("Wave", 0.07 + 0.24*f, 0.011 + 0.007*f, faded("Wave", gold, 1.3, 0.95*math.sin(math.pi*f)**0.7*(1 - f)**0.5),
            -0.3 + 1.0*f)
    for o in sc.objects:                           # centred on the whole of it
        o.location.x -= 0.15

def frost():
    """The cone of cold on one tile: shards of ice burst up from the floor one after another out of a cold mist,
    then melt down and fade.  It plays once: t = 0..1 is the whole of it."""
    import random; random.seed(7)
    t = P["t"]; die = smooth(0.6, 1.0, t); fade = 1 - smooth(0.7, 1.0, t)
    base = C + Vector((0, 0, -0.62))
    shards = [(0.0, 0.0, 1.05, 0.13)] + [(0.45*math.cos(a), 0.4*math.sin(a), 0.45 + 0.35*random.random(), 0.07 + 0.04*random.random())
              for a in [math.tau*k/8 + 0.4*random.random() for k in range(8)]] + \
             [(0.2*math.cos(a), 0.18*math.sin(a), 0.7 + 0.2*random.random(), 0.09) for a in (0.9, 2.9, 4.8)]
    for k, (ox, oy, h, r) in enumerate(shards):
        g = smooth(0.02*k, 0.02*k + 0.22, t)*(1 - 0.45*die)
        if g <= 0.001: continue
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=5, radius1=r, radius2=0.0, depth=h)
        for v in bm.verts: v.co.z += h/2
        me = bpy.data.meshes.new("Shard"); bm.to_mesh(me); bm.free()
        o = link(sc, "Shard", me); o.location = base + Vector((ox, oy, 0))
        tilt = Vector((ox*1.1, oy*1.1, 1.0)).normalized()
        o.rotation_mode = 'QUATERNION'; o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(tilt)
        o.rotation_quaternion = o.rotation_quaternion @ Matrix.Rotation(random.random()*math.tau, 4, 'Z').to_quaternion()
        o.scale = (0.5 + 0.5*g, 0.5 + 0.5*g, g)
        o.data.materials.append(faded("Ice", (0.12, 0.45, 0.9), 1.5, 0.85*fade, rim=0.7))
    mg = smooth(0.0, 0.3, t)
    def mist(N, Lk):
        nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 3.0; nz.inputs["Detail"].default_value = 4
        nz.noise_dimensions = '4D'; nz.inputs["W"].default_value = 1.5*t
        lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.5
        a = op(N, Lk, 'MULTIPLY', span(N, Lk, op(N, Lk, 'MULTIPLY', nz.outputs["Fac"], op(N, Lk, 'SUBTRACT', 1.0, lw.outputs["Facing"])), 0.15, 0.55), 0.6*fade)
        c = N("ShaderNodeRGB"); c.outputs[0].default_value = (0.55, 0.8, 1.0, 1)
        return c.outputs[0], 0.9, a
    if mg > 0.001:
        m = sphere("Mist", 0.75, see_through("Mist", mist), loc=base + Vector((0, 0, 0.05)))
        m.scale = (0.4 + 0.6*mg, 0.4 + 0.6*mg, 0.3*mg)
    for k in range(12):                            # frost glittering up out of it
        f = (t*1.6 + k/12) % 1.0; a = math.tau*k*0.37
        sz = 0.016*math.sin(math.pi*f)*fade*smooth(0.05, 0.25, t)
        if sz > 0.001:
            sphere("Glint", sz, glow("Glint", (0.8, 0.95, 1.0), 4.0), segs=8,
                   loc=base + Vector((0.5*math.cos(a)*(0.4 + 0.6*f), 0.4*math.sin(a), 0.1 + 0.9*f)))

globals()[P["kind"]]()
rig(sc, elev=P["elev"])
for o in [o for o in sc.objects if o.type == 'LIGHT']:   # emission only: no lamps
    bpy.data.objects.remove(o)
sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.0
render(sc, OUT, P["save_blend"], samples=96)
