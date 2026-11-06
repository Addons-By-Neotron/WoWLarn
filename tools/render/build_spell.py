"""Build + render one frame of a flying spell effect.  Usage:
blender -b -P build_spell.py -- out.png '{"kind":"fireball", "t":0.25, ...}'
kind: fireball (a roiling ball of flame round a white-hot heart, its flames and embers streaming back in a comet's
      tail), missile (the magic missile: a small oblong bolt of blue energy, crackling, with sparks circling it).
t: 0..1, where in the animation's loop this frame is.  Every moving part goes round a circle in t (the noise is
   read at an offset going round a circle, the sparks orbit), so t = 1 is t = 0 again: a seamless loop.
Both fly towards -x, screen left, as if cast from the right (turn the texture to its heading in the game).
kind firewall (wall of fire) and flood fill a tile instead, drawn on a flat sheet facing the camera (a billboard,
like the potions; render them at elev 0), or with solid=true as a block on the tile in 3D (render at elev 15).  frost (the cone of cold, on each tile it reaches) is the same but in 3D
(render at elev 15), as is gas (the cloud kill, on each tile round the caster).  claw (the summoned demon's strike), phantasm (phantasmal forces), dehydrate, drain (drain life) and death (finger
of death) the same, each on the monster it hits.  spear (the sonic spear) flies like the missile.  They play once, not looping: t = 0..1 is the whole of it, the flames or
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

def smoke(name, k, stops, strength, alpha, thin=0.0, rise=0.6):
    """A puff of smoke, gas or steam: noise, dense in the middle and wispy at the edge, no hard outline; k sets it apart
    from the other puffs, thin eats it away, rise rolls it upwards over the effect, alpha its strength."""
    t = P["t"]
    def build(N, Lk):
        tc = N("ShaderNodeTexCoord"); mp = N("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (2.6, 2.6, 2.6)
        mp.inputs["Location"].default_value = (1.7*k, 0.9*k, -rise*t)
        Lk(tc.outputs["Object"], mp.inputs["Vector"])
        n = noise4(N, Lk, mp.outputs["Vector"], 1.2*t + 0.7*k, detail=5, rough=0.6, dist=0.6)
        lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.5
        core = op(N, Lk, 'SUBTRACT', 1.0, lw.outputs["Facing"])
        d = span(N, Lk, op(N, Lk, 'MULTIPLY_ADD', core, 0.55, n), 0.78 + thin, 1.3 + thin)
        edge = span(N, Lk, core, 0.0, 0.55, True)
        return ramp(N, Lk, d, stops), strength, op(N, Lk, 'MULTIPLY', op(N, Lk, 'MULTIPLY', d, edge), alpha)
    return see_through(name, build)

BASE_C = C + Vector((0, 0, -0.62))                 # the floor under the tile's effects

def motes(name, n, col, size, spread, height, t, rate=1.3, gate=1.0, swirl=0.0, bright=3.0):
    """Specks of light drifting up from the floor and dying, each coming round again (rate times over the effect)."""
    for k in range(n):
        f = (t*rate + k/n) % 1.0; a = math.tau*k*0.41 + swirl*f
        sz = size*math.sin(math.pi*f)*gate
        if sz > 0.001:
            sphere(name, sz, glow(name, col, bright), segs=8,
                   loc=BASE_C + Vector((spread*math.cos(a)*(0.5 + 0.5*f), 0.75*spread*math.sin(a), 0.15 + height*f)))

def gas():
    """The cloud kill on one tile: puffs of poison gas billow up from the floor one after another, roll and swell,
    then thin out and fade.  It plays once: t = 0..1 is the whole of it."""
    t = P["t"]; fade = 1 - smooth(0.6, 1.0, t); thin = 0.25*smooth(0.5, 1.0, t)
    sc.cycles.transparent_max_bounces = 64         # (the puffs overlap many deep: past the default it shows black)
    puffs = [((0.0, 0.0, 0.38), 0.42), ((-0.36, 0.12, 0.26), 0.33), ((0.36, -0.1, 0.26), 0.33),
             ((0.12, 0.3, 0.6), 0.3), ((-0.16, -0.22, 0.66), 0.28), ((0.3, 0.2, 0.18), 0.26), ((-0.3, -0.25, 0.16), 0.26)]
    green = [(0.0, (0.04, 0.1, 0.01)), (0.5, (0.16, 0.42, 0.04)), (0.85, (0.38, 0.75, 0.1)), (1.0, (0.65, 0.9, 0.3))]
    for k, ((ox, oy, oz), r) in enumerate(puffs):
        g = smooth(0.035*k, 0.035*k + 0.3, t)
        if g <= 0.001: continue
        o = sphere(f"Puff{k}", r*1.3, smoke(f"Puff{k}", k, green, 0.75, 0.8*fade, thin),
                   loc=BASE_C + Vector((ox, oy, oz + 0.12*t)), segs=32)
        o.scale = (g*(0.85 + 0.2*t), g*(0.85 + 0.2*t), g*(0.75 + 0.2*t))
    motes("Fume", 10, (0.55, 1.0, 0.2), 0.014, 0.55, 0.85, t, gate=fade*smooth(0.1, 0.3, t))   # poison drifting up

def phantasm():
    """Phantasmal forces on one tile: ghosts of nothing rise round the monster and wheel about it, pale violet with
    staring eyes, then come apart into wisps.  It plays once."""
    t = P["t"]; fade = 1 - smooth(0.6, 1.0, t); come = smooth(0.0, 0.3, t)
    sc.cycles.transparent_max_bounces = 64
    for k in range(4):
        a = math.tau*k/4 + 2.6*t + 0.3; rr = 0.38 + 0.08*math.sin(3*t + k)
        z = 0.15 + 0.5*come + 0.12*math.sin(5*t + 2*k); g = smooth(0.06*k, 0.06*k + 0.25, t)
        if g <= 0.001: continue
        at = BASE_C + Vector((rr*math.cos(a), rr*math.sin(a), z))
        def body(N, Lk, k=k):                      # a pale shape, its edge brighter, its tail wisping off at the bottom
            tc = N("ShaderNodeTexCoord"); sp = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sp.inputs[0])
            n = noise4(N, Lk, coords(N, Lk, sp.outputs["X"], 4.0, sp.outputs["Z"], 3.0, 2.0*t), 1.5*t + k, detail=4)
            lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.35
            tail = span(N, Lk, op(N, Lk, 'MULTIPLY_ADD', n, 0.15, sp.outputs["X"]), 0.32, 0.0)  # (+x is its tail, down)
            a_ = op(N, Lk, 'MULTIPLY', op(N, Lk, 'MULTIPLY_ADD', lw.outputs["Facing"], 0.75, 0.12), tail)
            col = lerp(N, Lk, (0.45, 0.2, 0.9), (0.9, 0.75, 1.0), lw.outputs["Facing"])
            return col, 1.4, op(N, Lk, 'MULTIPLY', a_, 0.85*fade*g)
        o = sphere("Ghost", 0.15, see_through("Ghost", body), loc=at, segs=32, bolt=(1.0, 2.6, 0.9))   # a head and a tail
        o.rotation_euler = (0, math.radians(90) + 0.25*math.sin(4*t + k), 0); o.scale = (g, g, g)       # tail down, swaying
        for e in (-1, 1):                          # its eyes
            sphere("Eye", 0.022*g, glow("Eye", (0.7, 1.0, 1.0), 4.0*fade), segs=8,
                   loc=at + Vector((0.05*e*g, -0.13*g, 0.02*g)))
    motes("Wisp", 12, (0.75, 0.55, 1.0), 0.014, 0.5, 0.9, t, rate=1.0, gate=come*fade, swirl=4.0)

def dehydrate():
    """Dehydration on one tile: the water is pulled up out of the monster, drops spiralling up and boiling off to
    steam, while dust swirls up round its feet as it dries.  It plays once."""
    t = P["t"]; fade = 1 - smooth(0.65, 1.0, t)
    sc.cycles.transparent_max_bounces = 64
    sand = [(0.0, (0.12, 0.08, 0.03)), (0.6, (0.42, 0.3, 0.14)), (1.0, (0.7, 0.58, 0.36))]
    steam = [(0.0, (0.25, 0.3, 0.35)), (0.7, (0.65, 0.75, 0.82)), (1.0, (0.9, 0.95, 1.0))]
    for k in range(5):                             # dust round its feet
        a = math.tau*k/5 + 1.5*t; g = smooth(0.15 + 0.04*k, 0.45 + 0.04*k, t)
        if g > 0.001:
            o = sphere("Dust", 0.3, smoke("Dust", k, sand, 0.7, 0.75*fade, 0.15*smooth(0.6, 1, t), rise=0.3), segs=32,
                       loc=BASE_C + Vector((0.42*math.cos(a), 0.32*math.sin(a), 0.1)))
            o.scale = (g, g, 0.55*g)
    for k in range(3):                             # steam boiling off at the top
        g = smooth(0.25 + 0.08*k, 0.6 + 0.08*k, t)
        if g > 0.001:
            o = sphere("Steam", 0.36, smoke("Steam", 10 + k, steam, 0.8, 0.75*fade, 0.2*smooth(0.55, 1, t), rise=1.2), segs=32,
                       loc=BASE_C + Vector(((-0.2, 0.18, 0.0)[k], 0.05*k, 0.85 + 0.25*g)))
            o.scale = (g, g, 0.8*g)
    for k in range(28):                            # drops spiralling up, shrinking as they go
        t0 = 0.02*k; f = (t - t0)/0.45
        if not 0 < f < 1: continue
        a = math.tau*k*0.37 + 7.0*f; rr = 0.32*(1 - 0.6*f)
        sphere("Drop", 0.05*(1 - 0.6*f), faded("Drop", (0.25, 0.55, 1.0), 1.6, 0.9*(1 - f**3), rim=0.6), segs=12,
               loc=BASE_C + Vector((rr*math.cos(a), rr*math.sin(a), 0.2 + 0.85*f)))

def drain():
    """Drain life on one tile: dark red threads of life are torn up out of the monster, winding round it as they
    rise, with motes of blood light; then they thin and fade.  It plays once."""
    t = P["t"]; fade = 1 - smooth(0.6, 1.0, t)
    for k in range(5):
        reveal = smooth(0.04*k, 0.3 + 0.04*k, t); tail = smooth(0.45 + 0.03*k, 0.9 + 0.02*k, t)
        if reveal <= 0.001 or tail >= 0.999: continue
        ph = math.tau*k/5
        for name, w, col, strength, alpha in (("Thread", 0.04, (0.6, 0.0, 0.05), 1.0, 0.35*fade),
                                              ("Vein", 0.012, (1.0, 0.25, 0.25), 2.4, fade)):
            cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = w; cu.bevel_resolution = 3
            cu.bevel_factor_mapping_start = cu.bevel_factor_mapping_end = 'SPLINE'
            cu.bevel_factor_start, cu.bevel_factor_end = tail, reveal   # (drawn up from the floor, then let go of it)
            sp = cu.splines.new('POLY'); n = 40; sp.points.add(n - 1)
            for i in range(n):
                u = i/(n - 1); a = ph + 5.5*u + 2.0*t; rr = 0.42*(1 - 0.75*u)
                sp.points[i].co = (rr*math.cos(a), rr*math.sin(a), 0.05 + 1.15*u, 1)
                sp.points[i].radius = 0.4 + 0.6*math.sin(math.pi*u)
            o = link(sc, name, cu); o.location = BASE_C
            o.data.materials.append(faded(name, col, strength, alpha))
    glow_k = smooth(0.0, 0.25, t)*fade
    sphere("Heart", 0.07, faded("Heart", (1.0, 0.15, 0.15), 2.5, glow_k), segs=16, loc=BASE_C + Vector((0, 0, 1.25)))
    motes("Blood", 12, (1.0, 0.15, 0.1), 0.016, 0.5, 1.0, t, rate=1.2, gate=fade*smooth(0.05, 0.25, t), swirl=3.0)

def death():
    """Finger of death on one tile: a ring of sickly green light opens on the floor, a pale skull rises out of it,
    its eyes black, and fades away above.  It plays once."""
    t = P["t"]; fade = 1 - smooth(0.6, 1.0, t)
    sc.cycles.transparent_max_bounces = 64
    sick = (0.45, 1.0, 0.2)
    for k in range(2):                             # rings spreading out over the floor
        f = smooth(0.0 + 0.15*k, 0.5 + 0.15*k, t)
        if 0.001 < f:
            cu = bpy.data.curves.new("Ring", 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = 0.02*(1 - 0.5*f)
            sp = cu.splines.new('POLY'); n = 64; sp.points.add(n - 1); sp.use_cyclic_u = True
            for i in range(n):
                a = math.tau*i/n; sp.points[i].co = (0.7*f*math.cos(a), 0.6*f*math.sin(a), 0.01, 1)
            o = link(sc, "Ring", cu); o.location = BASE_C
            o.data.materials.append(faded("Ring", sick, 2.0, (1 - f)*fade))
    g = smooth(0.08, 0.35, t); z = 0.35 + 0.45*smooth(0.1, 1.0, t)
    if g > 0.001:
        skull = BASE_C + Vector((0, -0.1, z))
        bone = faded("Bone", (0.55, 0.85, 0.4), 1.2, 0.85*fade, rim=0.5)
        o = sphere("Skull", 0.2, bone, loc=skull, segs=32); o.scale = (g, 0.95*g, 0.95*g)
        o = sphere("Jaw", 0.13, bone, loc=skull + Vector((0, -0.04*g, -0.17*g)), segs=24); o.scale = (g, 0.9*g, 0.6*g)
        black = bpy.data.materials.new("Hollow")    # (no light from it: dark against the glow)
        for e in (-1, 1):
            o = sphere("Socket", 0.055, black, loc=skull + Vector((0.075*e*g, -0.16*g, 0.0)), segs=16); o.scale = (g, 0.6*g, 1.1*g)
        o = sphere("Nose", 0.025, black, loc=skull + Vector((0, -0.18*g, -0.07*g)), segs=12); o.scale = (g, 0.6*g, 1.3*g)
        # the dark parts are opaque: they must fade too, so they go to see-through as the rest does
        black.use_nodes = True; nt = black.node_tree; nt.nodes.clear()
        tr = nt.nodes.new("ShaderNodeBsdfTransparent"); em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = (0, 0, 0, 1); mx = nt.nodes.new("ShaderNodeMixShader")
        mx.inputs[0].default_value = 0.9*fade
        nt.links.new(tr.outputs[0], mx.inputs[1]); nt.links.new(em.outputs[0], mx.inputs[2])
        nt.links.new(mx.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs[0])
        def aura(N, Lk):                           # the sick green flare round it
            lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.5
            n = noise4(N, Lk, coords(N, Lk, op(N, Lk, 'MULTIPLY', lw.outputs["Facing"], 1.0), 1.0, lw.outputs["Facing"], 1.0, -3*t), 2*t, detail=3)
            c_ = N("ShaderNodeRGB"); c_.outputs[0].default_value = (*sick, 1)
            return c_.outputs[0], 1.2, op(N, Lk, 'MULTIPLY', op(N, Lk, 'SUBTRACT', 1.0, lw.outputs["Facing"]), 0.35*fade*g)
        o = sphere("Flare", 0.36, see_through("Flare", aura), loc=skull + Vector((0, 0.05, -0.05)), segs=32); o.scale = (g, g, 1.15*g)
    motes("Soul", 10, sick, 0.015, 0.45, 1.0, t, rate=1.1, gate=fade*smooth(0.1, 0.3, t))

# ---- the spells that act on one monster without hurting it, and the ones the caster casts on themself: each plays
# once on its tile (the monster's, or the caster's)

def lines(name, polys, w, col, strength, alpha, loc=None, reveal=1.0, tail=0.0, cyclic=False, rot=(0, 0, 0)):
    """Glowing lines: polys a list of point lists (x, y, z), drawn on from the start to reveal (0..1 of each) and let go
    of up to tail; a tube w thick, thinning at the ends of an open one."""
    if reveal <= tail + 0.001 or alpha <= 0.001: return None
    cu = bpy.data.curves.new(name, 'CURVE'); cu.dimensions = '3D'; cu.bevel_depth = w; cu.bevel_resolution = 2
    cu.bevel_factor_mapping_start = cu.bevel_factor_mapping_end = 'SPLINE'
    cu.bevel_factor_start, cu.bevel_factor_end = tail, reveal
    for pts in polys:
        sp = cu.splines.new('POLY'); sp.points.add(len(pts) - 1); sp.use_cyclic_u = cyclic
        for i, q in enumerate(pts):
            sp.points[i].co = (*q, 1)
            if not cyclic: sp.points[i].radius = 0.35 + 0.65*math.sin(math.pi*min(1.0, 0.05 + 0.95*i/(len(pts) - 1)))
    o = link(sc, name, cu); o.location = loc or BASE_C; o.rotation_euler = rot
    o.data.materials.append(faded(name, col, 0.6*strength, alpha))   # (dimmer than the bolts: keeps its colour)
    return o

def circle(r, z=0.0, n=64, ry=None):
    return [(r*math.cos(math.tau*i/n), (ry or r)*math.sin(math.tau*i/n), z) for i in range(n)]

def helix(ph, turns, r0, r1, h, z0=0.05, n=48):
    return [((r0 + (r1 - r0)*u)*math.cos(ph + math.tau*turns*u), (r0 + (r1 - r0)*u)*math.sin(ph + math.tau*turns*u), z0 + h*u)
            for u in (i/(n - 1) for i in range(n))]

def flat(pts2, at, size):
    """A shape drawn flat facing the camera (x across, z up), at the point at (from the lines' loc), size across."""
    return [(at.x + size*x, at.y, at.z + size*z) for x, z in pts2]

HEART = [(16*math.sin(a)**3/17, (13*math.cos(a) - 5*math.cos(2*a) - 2*math.cos(3*a) - math.cos(4*a))/17)
         for a in (math.tau*i/48 for i in range(48))]
ZED = [(-0.5, 0.5), (0.5, 0.5), (-0.5, -0.5), (0.5, -0.5)]

def dome(name, r, col, strength, alpha, g=1.0, z=0.5, rim=0.92, squash=1.0):
    """A bubble of light round the tile's middle, its edge bright and its face clear."""
    if alpha <= 0.001 or g <= 0.001: return
    def b(N, Lk):                                  # (its own colour, all but clear where it faces the camera)
        lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.5
        edge = op(N, Lk, 'POWER', lw.outputs["Facing"], 2.0)
        c_ = N("ShaderNodeRGB"); c_.outputs[0].default_value = (*col, 1)
        return c_.outputs[0], strength*0.7, op(N, Lk, 'MULTIPLY', op(N, Lk, 'MULTIPLY_ADD', edge, rim, 1 - rim), alpha)
    o = sphere(name, r, see_through(name, b), loc=BASE_C + Vector((0, 0, z)), segs=48)
    o.scale = (g, g, g*squash)

def column(name, r, h, col, strength, alpha, g=1.0):
    """A shaft of light up from the floor, fading out at its top, clear in its face."""
    if alpha <= 0.001: return
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=False, segments=48, radius1=r, radius2=r*0.9, depth=h)
    for v in bm.verts: v.co.z += h/2
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = True
    o = link(sc, name, me); o.location = BASE_C; o.scale = (g, g, 1)
    def b(N, Lk):
        tc = N("ShaderNodeTexCoord"); sp = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sp.inputs[0])
        lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.4
        up = span(N, Lk, sp.outputs["Z"], h, 0.0)
        a_ = op(N, Lk, 'MULTIPLY', op(N, Lk, 'MULTIPLY', op(N, Lk, 'MULTIPLY_ADD', lw.outputs["Facing"], 0.8, 0.15), up), alpha)
        c_ = N("ShaderNodeRGB"); c_.outputs[0].default_value = (*col, 1)
        return c_.outputs[0], strength, a_
    o.data.materials.append(see_through(name, b))

def once(t, a=0.6):
    return 1 - smooth(a, 1.0, t)

def sleep():
    """Sleep: lavender dust sifts down over the monster and Zs drift up off it."""
    t = P["t"]; fade = once(t); col = (0.72, 0.62, 1.0)
    for k in range(16):                            # dust falling
        f = (t*1.2 + k/16) % 1.0; a = math.tau*k*0.37
        sz = 0.015*math.sin(math.pi*f)*fade*smooth(0.0, 0.2, t)
        if sz > 0.001:
            sphere("Dust", sz, glow("Dust", col, 1.6), segs=8, loc=BASE_C + Vector((0.45*math.cos(a), 0.3*math.sin(a), 1.05 - 0.95*f)))
    for k in range(3):                             # Zs, one after another
        f = smooth(0.15 + 0.2*k, 0.75 + 0.15*k, t)
        if 0 < f < 1:
            at = Vector((0.05 + 0.3*f, -0.4, 0.5 + 0.4*f + 0.05*k))
            lines("Zed", [flat(ZED, at, 0.16 + 0.12*f)], 0.016, (0.7, 0.6, 1.0), 2.2, math.sin(math.pi*f)*fade)

def web():
    """Web: silver threads spun out across the monster, spokes first, then the spiral, which then fade."""
    t = P["t"]; fade = once(t, 0.65); at = BASE_C + Vector((0, -0.4, 0.55)); col = (0.85, 0.9, 1.0)
    spokes = [flat([(0, 0), (0.62*math.cos(math.tau*k/9 + 0.2), 0.62*math.sin(math.tau*k/9 + 0.2))], at, 1.0) for k in range(9)]
    lines("Spoke", spokes, 0.008, col, 1.4, 0.9*fade, loc=Vector((0, 0, 0)), reveal=smooth(0.0, 0.25, t))
    spiral = [(0.6*u*math.cos(math.tau*5*u), 0.6*u*math.sin(math.tau*5*u)) for u in (0.08 + 0.92*i/239 for i in range(240))]
    lines("Spiral", [flat(spiral, at, 1.0)], 0.006, col, 1.3, 0.85*fade, loc=Vector((0, 0, 0)), reveal=smooth(0.15, 0.5, t))

def polymorph():
    """Polymorph: sparks of every colour whirl round the monster and it goes up in a puff of pink smoke."""
    t = P["t"]; fade = once(t)
    sc.cycles.transparent_max_bounces = 64
    for k in range(4):
        hue = [(1.0, 0.3, 0.6), (0.4, 0.8, 1.0), (1.0, 0.85, 0.3), (0.6, 1.0, 0.4)][k]
        lines("Whirl", [helix(math.tau*k/4 + 4*t, 1.5, 0.45, 0.2, 1.1)], 0.014, hue, 2.0, fade,
              reveal=smooth(0.0 + 0.05*k, 0.35 + 0.05*k, t), tail=smooth(0.4, 0.9, t))
    pink = [(0.0, (0.2, 0.05, 0.15)), (0.6, (0.75, 0.35, 0.65)), (1.0, (1.0, 0.75, 0.9))]
    for k in range(4):
        g = smooth(0.3 + 0.03*k, 0.55 + 0.03*k, t)
        if g > 0.001:
            o = sphere("Puff", 0.3, smoke("Puff", k, pink, 0.9, 0.85*once(t, 0.55), 0.3*smooth(0.55, 1, t)), segs=32,
                       loc=BASE_C + Vector(((-0.2, 0.2, 0.0, 0.05)[k], 0.05*k, (0.35, 0.4, 0.65, 0.2)[k])))
            o.scale = (g, g, g)
    motes("Spark", 12, (1.0, 0.8, 1.0), 0.016, 0.5, 1.0, t, rate=1.5, gate=fade, swirl=4.0, bright=1.6)
def teleport():
    """Teleport away: a shaft of blue light comes down on the monster, rings climbing it, and it pinches out."""
    t = P["t"]; col = (0.45, 0.55, 1.0); pinch = 1 - smooth(0.55, 0.85, t)
    column("Shaft", 0.42, 1.5, col, 1.1, smooth(0.0, 0.2, t)*once(t, 0.7), g=max(0.02, pinch))
    for k in range(4):
        f = (t*2.0 + k/4) % 1.0
        lines("Ring", [circle(0.42*max(0.05, pinch), 1.3*f, ry=0.42*max(0.05, pinch))], 0.012, (0.8, 0.85, 1.0), 2.2,
              math.sin(math.pi*f)*smooth(0.05, 0.2, t)*once(t, 0.7), cyclic=True)
    motes("Glint", 12, (0.8, 0.85, 1.0), 0.016, 0.4*pinch + 0.05, 1.3, t, rate=2.0, gate=once(t, 0.7), bright=1.6)
def charm():
    """Charm monster: pink hearts float up off the caster, sparkling."""
    t = P["t"]; fade = once(t)
    for k in range(5):
        f = smooth(0.05 + 0.1*k, 0.6 + 0.08*k, t)
        if 0 < f < 1:
            at = Vector(((-0.3, 0.3, -0.05, 0.2, -0.25)[k] + 0.08*math.sin(6*f + k), -0.35, 0.25 + 0.75*f))
            lines("Heart", [flat(HEART, at, 0.14 + 0.05*(k % 2))], 0.018, (1.0, 0.35, 0.6), 2.2, math.sin(math.pi*f)*fade, cyclic=True)
    motes("Glint", 12, (1.0, 0.7, 0.85), 0.014, 0.5, 1.1, t, gate=fade, bright=1.6)
def scare():
    """Scare monster: waves of dread roll out from the caster over the floor, teal and dark."""
    t = P["t"]; col = (0.25, 0.85, 0.75)
    for k in range(3):
        f = smooth(0.0 + 0.18*k, 0.55 + 0.18*k, t)
        if 0 < f < 1:
            lines("Wave", [circle(0.15 + 0.6*f, 0.02, ry=(0.15 + 0.6*f)*0.85)], 0.03*(1 - 0.6*f), col, 1.8, (1 - f)**1.2, cyclic=True)
            dome("Dread", 0.2 + 0.55*f, (0.15, 0.55, 0.6), 1.0, 0.45*(1 - f), z=0.0, squash=0.6)
    for k in range(3):                             # wisps of it curling up
        lines("Curl", [helix(math.tau*k/3 + 2*t, 1.2, 0.35, 0.1, 1.0)], 0.01, col, 1.8, once(t),
              reveal=smooth(0.1, 0.5, t), tail=smooth(0.45, 0.95, t))

def hold():
    """Hold monster: violet rings of force close in round the caster at all angles, turning, then fade."""
    t = P["t"]; fade = once(t); g = 1.25 - 0.45*smooth(0.0, 0.4, t)  # (closing in)
    for k in range(3):
        tilt = (math.radians((70, 70, 0)[k]), 0, math.radians(120*k) + 1.5*t)
        o = lines("Band", [circle(0.45*g, 0.0)], 0.014, (0.75, 0.45, 1.0), 2.2, fade*smooth(0.05*k, 0.2 + 0.05*k, t),
                  loc=BASE_C + Vector((0, 0, 0.55)), cyclic=True, rot=tilt)
    motes("Glint", 10, (0.85, 0.7, 1.0), 0.014, 0.45, 1.0, t, gate=fade, bright=1.6)
def timestop():
    """Time stop: a cyan spiral winds out over the floor round the caster and a still bubble of time rises over it."""
    t = P["t"]; fade = once(t, 0.65); col = (0.3, 0.9, 1.0)
    spiral = [(0.75*u*math.cos(math.tau*3*u + 1.2*t), 0.65*u*math.sin(math.tau*3*u + 1.2*t), 0.02) for u in (i/199 for i in range(200))]
    lines("Spiral", [spiral], 0.018, col, 2.0, fade, reveal=smooth(0.0, 0.4, t))
    dome("Still", 0.7, (0.4, 0.85, 1.0), 1.0, 0.3*smooth(0.25, 0.5, t)*fade, g=smooth(0.2, 0.5, t), z=0.0, squash=0.95)
    motes("Glint", 10, (0.7, 0.95, 1.0), 0.014, 0.5, 0.9, t, rate=0.3, gate=fade, bright=1.6)   # (barely moving)

def protection():
    """Protection: a silver-blue shield of light closes round the caster, flares, settles and fades."""
    t = P["t"]; g = smooth(0.0, 0.25, t); flare = 1 + 0.6*math.exp(-30*(t - 0.25)**2)
    dome("Shield", 0.62, (0.55, 0.7, 1.0), 1.4*flare, 0.75*once(t), g=g, z=0.35, squash=1.15)
    for k in range(3):
        lines("Band", [circle(0.62*g, 0.0)], 0.012, (0.8, 0.88, 1.0), 2.0, once(t)*g, loc=BASE_C + Vector((0, 0, 0.1 + 0.3*k)),
              cyclic=True)

def swirl(col, n, turns, rise, t, w=0.012, fast=1.0):
    for k in range(n):
        lines("Swirl", [helix(math.tau*k/n + 3*t*fast, turns, 0.42, 0.3, rise)], w, col, 2.2, once(t),
              reveal=smooth(0.02*k, 0.3 + 0.02*k, t), tail=smooth(0.35 + 0.02*k, 0.85, t))

def dexterity():
    """Dexterity: quick green streaks of wind whip up round the caster."""
    t = P["t"]; swirl((0.35, 1.0, 0.55), 5, 1.6, 1.15, t, fast=1.5)
    motes("Glint", 10, (0.6, 1.0, 0.7), 0.014, 0.45, 1.1, t, rate=1.8, gate=once(t), bright=1.6)
def strength():
    """Strength: a red-gold flare of might bursts up from the caster's feet, a ring of it on the floor."""
    t = P["t"]; col = (1.0, 0.35, 0.08); f = smooth(0.0, 0.45, t)
    lines("Burst", [circle(0.2 + 0.55*f, 0.02, ry=(0.2 + 0.55*f)*0.85)], 0.03*(1 - 0.5*f), col, 2.2, (1 - f)*once(t), cyclic=True)
    column("Might", 0.38, 1.2, (1.0, 0.45, 0.1), 1.5, 0.6*math.sin(math.pi*min(1.0, t/0.7)))
    swirl((1.0, 0.6, 0.2), 3, 1.0, 1.1, t)
    motes("Ember", 12, (1.0, 0.5, 0.1), 0.016, 0.45, 1.2, t, rate=1.6, gate=once(t), bright=1.6)
def invisible():
    """Invisibility: a shimmer runs over the caster and they fade from sight, specks of light winking out."""
    t = P["t"]; col = (0.8, 0.9, 1.0)
    dome("Shimmer", 0.5, col, 1.0, 0.55*math.sin(math.pi*min(1.0, t/0.8)), g=1.0, z=0.5, squash=1.3)
    for k in range(4):
        f = (t*1.5 + k/4) % 1.0
        lines("Ripple", [circle(0.5, 1.2*f - 0.1, ry=0.5)], 0.01, col, 1.8, math.sin(math.pi*f)*once(t, 0.5), cyclic=True)
    motes("Wink", 16, (0.9, 0.95, 1.0), 0.014, 0.5, 1.0, t, rate=1.0, gate=once(t, 0.5), bright=1.6)
def haste():
    """Haste self: golden streaks race up round the caster, fast and tight."""
    t = P["t"]; swirl((1.0, 0.82, 0.2), 6, 2.5, 1.2, t, w=0.01, fast=3.0)
    motes("Glint", 14, (1.0, 0.9, 0.5), 0.013, 0.45, 1.2, t, rate=3.0, gate=once(t), bright=1.6)
def globe():
    """Invulnerability: a golden globe forms round the caster, bands of light first, then the whole of it, then fades."""
    t = P["t"]; fade = once(t, 0.65); g = smooth(0.15, 0.45, t)
    for k in range(4):
        lines("Band", [circle(0.66, 0.0)], 0.012, (1.0, 0.85, 0.45), 2.2, fade*(1 - 0.5*g), loc=BASE_C + Vector((0, 0, 0.5)),
              cyclic=True, rot=(math.radians(90), 0, math.radians(45*k) + 2*t), reveal=smooth(0.03*k, 0.2 + 0.03*k, t))
    dome("Globe", 0.66, (1.0, 0.8, 0.4), 1.4, 0.8*fade, g=g, z=0.5)

def wtw():
    """Walk through walls: rings of pale light sweep up through the caster, who goes half to mist."""
    t = P["t"]; col = (0.7, 0.85, 1.0)
    for k in range(2):
        f = smooth(0.05 + 0.3*k, 0.55 + 0.3*k, t)
        if 0 < f < 1:
            lines("Sweep", [circle(0.48, 1.3*f - 0.05, ry=0.42)], 0.02, col, 2.2, math.sin(math.pi*f), cyclic=True)
            column("Veil", 0.48, 1.3*f, col, 1.0, 0.35*math.sin(math.pi*f))
    motes("Mist", 14, (0.85, 0.92, 1.0), 0.014, 0.45, 1.0, t, rate=1.0, gate=once(t), bright=1.6)
def heal():
    """Healing: a warm shaft of light comes down on the caster, crosses of green light rising in it."""
    t = P["t"]; fade = once(t)
    column("Light", 0.4, 1.4, (1.0, 0.85, 0.45), 1.6, 0.6*smooth(0.0, 0.2, t)*fade)
    for k in range(4):
        f = smooth(0.08 + 0.12*k, 0.6 + 0.1*k, t)
        if 0 < f < 1:
            at = Vector(((-0.22, 0.22, 0.0, -0.05)[k], -0.4, 0.25 + 0.9*f)); sz = 0.16
            lines("Cross", [flat([(-0.5, 0), (0.5, 0)], at, sz), flat([(0, -0.5), (0, 0.5)], at, sz)], 0.026, (0.5, 1.0, 0.4),
                  2.2, math.sin(math.pi*f)*fade)
    motes("Glint", 12, (0.9, 1.0, 0.6), 0.015, 0.4, 1.2, t, gate=fade, bright=1.6)
def sight():
    """Cure blindness: a flash of white light breaks from the caster's eyes, rays spreading, then fades."""
    t = P["t"]; at = BASE_C + Vector((0, -0.4, 0.8)); f = smooth(0.0, 0.4, t); fade = once(t, 0.4)
    rays = [flat([(0.08*math.cos(a), 0.08*math.sin(a)), ((0.25 + 0.45*f)*math.cos(a), (0.25 + 0.45*f)*math.sin(a))], at, 1.0)
            for a in (math.tau*k/12 + 0.1 for k in range(12))]
    lines("Ray", rays, 0.012, (1.0, 0.95, 0.75), 2.4, fade, loc=Vector((0, 0, 0)))
    o = sphere("Flash", 0.12, faded("Flash", (1.0, 0.95, 0.8), 3.0, math.exp(-12*t)), loc=at, segs=24); o.scale = (1.3, 1, 1)
    motes("Glint", 10, (1.0, 0.95, 0.8), 0.014, 0.4, 1.0, t, gate=fade, bright=1.6)
globals()[P["kind"]]()
rig(sc, elev=P["elev"])
for o in [o for o in sc.objects if o.type == 'LIGHT']:   # emission only: no lamps
    bpy.data.objects.remove(o)
sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.0
render(sc, OUT, P["save_blend"], samples=96)
