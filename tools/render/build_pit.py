"""Build + render a floor trap (with a shadow).  Usage:
blender -b -P build_pit.py -- out.png '{"kind":"pit", "elev":45, ...}'
pit:      a ragged hole broken through the floor, edged by cracked paving and a little rubble; its rock walls fade
          to black with depth (the ground is a shadow catcher with the same hole in it).
trapdoor: a closed plank door set flush in a stone frame, with iron straps, hinges at the back and a ring pull.
arrow:    a stone pressure plate in that frame, arrows stuck in the floor round it, the slits they came from.
dart:     the plate pierced with a grid of dart holes, spattered with green poison, darts in it.
teleport: a round stone dais with glowing blue rings, runes and a star in it, a faint shaft of light over it.
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, rock_material, studio_world, spot, wood_material

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "pit.png"
P = dict(kind="pit", stone=(0.2, 0.2, 0.21), rock_scale=0.6, wood=(0.085, 0.05, 0.028), glow=(0.15, 0.45, 1.0), shine=1.6, column=0.5, elev=90, seed=3, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
rnd = random.Random(P["seed"])

root = bpy.data.objects.new("Trap", None); sc.collection.objects.link(root)

def obj(name, bm, material, bevel=0.0, segs=2, smooth=False):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = smooth
    o = link(sc, name, me); o.parent = root; o.data.materials.append(material)
    if bevel:
        m = o.modifiers.new("Bevel", 'BEVEL'); m.width = bevel; m.segments = segs; m.limit_method = 'ANGLE'
    return o

def prism(outline, z0, z1):
    """Extrude a closed XY outline (counter-clockwise) from z0 up to z1."""
    bm = bmesh.new()
    lo = [bm.verts.new((x, y, z0)) for x, y in outline]; hi = [bm.verts.new((x, y, z1)) for x, y in outline]
    n = len(outline)
    bm.faces.new(lo[::-1]); bm.faces.new(hi)
    for k in range(n):
        bm.faces.new((lo[k], lo[(k+1) % n], hi[(k+1) % n], hi[k]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

def rect(x0, x1, y0, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]

def rock(name, loc, size, material):
    """A lump of rubble: a jittered, squashed icosphere."""
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1)
    for v in bm.verts:
        v.co = Vector((v.co.x*size, v.co.y*size*rnd.uniform(0.7, 1.1), v.co.z*size*0.6))*rnd.uniform(0.8, 1.15)
    bm.transform(Matrix.Translation(loc) @ Matrix.Rotation(rnd.uniform(0, math.tau), 4, 'Z'))
    return obj(name, bm, material, smooth=False)

def stone_frame(frame, D, F):
    """The square stone frame round a trap: an opening of half-size D in a frame of half-size F."""
    for outline in (rect(-F, F, -F, -D), rect(-F, F, D, F), rect(-F, -D, -D, D), rect(D, F, -D, D)):
        obj("Frame", prism(outline, -0.08, 0.05), frame, bevel=0.02)

def lathe(profile, segs=48):
    """Turned shape about Z: profile [(radius, z), ...] from the outside in (radius 0 closes it)."""
    bm = bmesh.new(); rings = []
    for r, z in profile:
        rings.append([bm.verts.new((r*math.cos(math.tau*i/segs), r*math.sin(math.tau*i/segs), z)) for i in range(segs)])
    bm.faces.new(rings[0][::-1])
    for r0, r1 in zip(rings, rings[1:]):
        for i in range(segs): bm.faces.new((r0[i], r0[(i+1) % segs], r1[(i+1) % segs], r1[i]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    return bm

def arrow(base, yaw, tilt, length, shaft_mat, head_mat, fletch_mat, thick=0.012):
    """An arrow (or dart) stuck in the floor at base: its shaft sticks out towards yaw (degrees round Z),
    tilt degrees above the floor; the head is in the floor, only its back shows."""
    d = Vector((math.cos(math.radians(tilt))*math.cos(math.radians(yaw)), math.cos(math.radians(tilt))*math.sin(math.radians(yaw)),
                math.sin(math.radians(tilt))))
    m = Matrix.Translation(base) @ d.to_track_quat('Z', 'Y').to_matrix().to_4x4()
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=thick, radius2=thick, depth=length)
    bm.transform(m @ Matrix.Translation((0, 0, length/2 - 0.02))); obj("Shaft", bm, shaft_mat, smooth=True)
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=8, radius1=thick*2.6, radius2=thick*1.2, depth=0.04)
    bm.transform(m @ Matrix.Translation((0, 0, -0.01))); obj("Head", bm, head_mat, smooth=True)
    for k in range(3):                                 # three fins at the back
        bm = bmesh.new()
        vs = [bm.verts.new(v) for v in ((thick, 0, length - 0.2*length), (thick + 0.07*length/0.5, 0, length - 0.17*length),
                                         (thick + 0.07*length/0.5, 0, length - 0.03), (thick, 0, length - 0.02))]
        bm.faces.new(vs); bm.transform(m @ Matrix.Rotation(math.tau*k/3 + 0.3, 4, 'Z'))
        obj("Fin", bm, fletch_mat)

def shaft(colour, r0, z0, z1, strength):
    """A faint shaft of light going up from the floor, see-through at its middle, fading out at the top."""
    bm = bmesh.new(); segs = 40
    lo = [bm.verts.new((r0*math.cos(math.tau*i/segs), r0*math.sin(math.tau*i/segs), z0)) for i in range(segs)]
    hi = [bm.verts.new((0.85*r0*math.cos(math.tau*i/segs), 0.85*r0*math.sin(math.tau*i/segs), z1)) for i in range(segs)]
    for i in range(segs): bm.faces.new((lo[i], lo[(i+1) % segs], hi[(i+1) % segs], hi[i]))
    m = bpy.data.materials.new("Shaft"); nt = m.node_tree; nt.nodes.clear(); N = nt.nodes.new; Lk = nt.links.new
    def f(op, a, b):
        n = N("ShaderNodeMath"); n.operation = op
        for i, v in enumerate((a, b)):
            if isinstance(v, (int, float)): n.inputs[i].default_value = v
            else: Lk(v, n.inputs[i])
        return n.outputs[0]
    lw = N("ShaderNodeLayerWeight"); lw.inputs["Blend"].default_value = 0.5
    edge = f('POWER', f('SUBTRACT', 1.0, lw.outputs["Facing"]), 2.0)
    tc = N("ShaderNodeTexCoord"); sp = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sp.inputs[0])
    h = f('DIVIDE', f('SUBTRACT', sp.outputs["Z"], z0), z1 - z0)
    a = f('MULTIPLY', f('MULTIPLY', edge, f('POWER', f('SUBTRACT', 1.0, f('MINIMUM', h, 1.0)), 2.5)), strength)
    e = N("ShaderNodeEmission"); e.inputs["Color"].default_value = (*colour, 1); e.inputs["Strength"].default_value = 2.0
    tr = N("ShaderNodeBsdfTransparent"); mx = N("ShaderNodeMixShader"); Lk(a, mx.inputs[0])
    Lk(tr.outputs[0], mx.inputs[1]); Lk(e.outputs[0], mx.inputs[2])
    Lk(mx.outputs[0], N("ShaderNodeOutputMaterial").inputs["Surface"])
    m.cycles.emission_sampling = 'NONE'
    o = obj("Shaft", bm, m, smooth=True); o.visible_shadow = False; o.visible_diffuse = False; o.visible_glossy = False

ground = bmesh.new()
if P["kind"] == "pit":
    # ---- the hole: a ragged outline (a few random harmonics on a circle)
    NS = 72
    harm = [(k, rnd.uniform(0.03, 0.09)/k**0.4, rnd.uniform(0, math.tau)) for k in (2, 3, 5, 7, 11)]
    def r_hole(a):
        return 0.78*(1 + sum(amp*math.sin(k*a + ph) for k, amp, ph in harm))
    ang = [math.tau*k/NS for k in range(NS)]
    rh = [r_hole(a) + rnd.uniform(-0.06, 0.06) for a in ang]   # jagged, not smooth
    rock_mat, _ = rock_material("Rock", P["stone"], P["rock_scale"], fade=(0.0, -1.1))
    # one rock surface: a lumpy broken lip round the hole (heaved up at the edge, settling into the floor further
    # out, ragged outer outline) running straight down into the walls, every vertex jittered so it looks broken
    bm = bmesh.new()
    def ring(rs, zs):
        return [bm.verts.new((r*math.cos(a), r*math.sin(a), z)) for a, r, z in zip(ang, rs, zs)]
    width = [rnd.uniform(0.25, 0.5) for _ in ang]
    width = [(width[k-1] + 2*width[k] + width[(k+1) % NS])/4 for k in range(NS)]   # lumps, not spikes
    lip = []
    for t, hi in ((1.0, 0.0), (0.7, 0.03), (0.4, 0.07), (0.15, 0.1), (0.0, 0.07)):   # outside in
        lip.append(ring([r + t*w + (rnd.uniform(-0.05, 0.05) if t else 0) for r, w in zip(rh, width)],
                        [rnd.uniform(-0.01, 0.005) if not hi else rnd.uniform(0.3, 1.0)*hi for _ in ang]))
    walls = [lip[-1]]
    for d in range(1, 14):
        shrink = 1 - 0.012*d
        walls.append(ring([r*shrink + rnd.uniform(-0.04, 0.04) for r in rh], [-0.16*d + rnd.uniform(-0.03, 0.03) for _ in ang]))
    for out, inn in zip(lip, lip[1:]):                  # facing up
        for k in range(NS):
            bm.faces.new((inn[k], out[k], out[(k+1) % NS], inn[(k+1) % NS]))
    for top, low in zip(walls, walls[1:]):              # facing in
        for k in range(NS):
            bm.faces.new((top[k], top[(k+1) % NS], low[(k+1) % NS], low[k]))
    bm.faces.new(walls[-1])                             # floor far below: black anyway
    obj("Rock", bm, rock_mat)
    for k in range(14):                                 # broken chunks on the lip and spilled beyond it
        j = rnd.randrange(NS); d = rh[j] + rnd.uniform(0.05, 0.75)
        rock("Rubble", Vector((d*math.cos(ang[j]), d*math.sin(ang[j]), 0.03)), rnd.uniform(0.04, 0.12), rock_mat)
    # ground: shadow catcher with the same hole
    inner = [ground.verts.new((r*math.cos(a), r*math.sin(a), 0)) for a, r in zip(ang, rh)]
    outer = [ground.verts.new((10*math.cos(a), 10*math.sin(a), 0)) for a in ang]
    for k in range(NS):
        ground.faces.new((inner[k], outer[k], outer[(k+1) % NS], inner[(k+1) % NS]))
    tgt = Vector((0, 0, -0.2))
elif P["kind"] in ("arrow", "dart"):
    # ---- a pressure plate in the trapdoor's stone frame; arrow: arrows shot into the floor round it, and the
    # slits they came from in the frame; dart: the plate pierced with dart holes, green poison spattered, darts on it
    frame, _ = rock_material("Frame", P["stone"], P["rock_scale"])
    D, F = 0.8, 1.05
    stone_frame(frame, D, F)
    plate, _ = rock_material("Plate", [c*1.6 for c in P["stone"]], P["rock_scale"])
    obj("Recess", prism(rect(-D, D, -D, D), -0.08, -0.01), frame)
    obj("Plate", prism(rect(-D + 0.08, D - 0.08, -D + 0.08, D - 0.08), -0.02, 0.035), plate, bevel=0.025)
    dark, _ = mat("Dark", (0.008, 0.007, 0.006), Roughness=0.9)
    wood = wood_material("Shaft", (0.3, 0.2, 0.1), axis="Z", roughness=0.7)
    iron, _ = mat("Iron", (0.06, 0.06, 0.065), Metallic=0.85, Roughness=0.45)
    if P["kind"] == "arrow":
        feather, _ = mat("Feather", (0.55, 0.06, 0.03), Roughness=0.8)
        for x in (-0.5, 0.0, 0.5):                     # arrow slits in the frame's back edge, facing the plate
            obj("Slit", prism(rect(x - 0.09, x + 0.09, D + 0.005, D + 0.03), -0.02, 0.035), dark)
        for at, yaw, tilt, length in (((-0.3, -0.25), 95, 32, 0.62), ((0.35, 0.1), 80, 26, 0.55),
                                       ((0.05, -0.5), 100, 38, 0.48), ((-0.62, 0.42), 110, 30, 0.4)):
            arrow(Vector((*at, 0.035)), yaw, tilt, length, wood, iron, feather, thick=0.02)
    else:
        poison, pb = mat("Poison", (0.06, 0.2, 0.02), Roughness=0.25, **{"Emission Color": (0.25, 0.8, 0.1, 1), "Emission Strength": 0.15})
        poison.cycles.emission_sampling = 'NONE'
        for i in range(4):                             # a grid of dart holes, each a dark pit with a brass rim
            for j in range(4):
                x, y = -0.48 + 0.32*i, -0.48 + 0.32*j
                bm = bmesh.new(); bmesh.ops.create_circle(bm, cap_ends=True, segments=12, radius=0.035)
                bm.transform(Matrix.Translation((x, y, 0.037))); obj("Hole", bm, dark)
                bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=False, segments=12, radius1=0.052, radius2=0.042, depth=0.012)
                bm.transform(Matrix.Translation((x, y, 0.04))); obj("Rim", bm, iron, smooth=True)
        for k in range(9):                             # poison spatter: flat drops, a few round the holes
            bm = bmesh.new(); r = rnd.uniform(0.03, 0.09)
            bmesh.ops.create_circle(bm, cap_ends=True, segments=14, radius=r)
            sx, at = rnd.uniform(0.7, 1.4), Vector((rnd.uniform(-0.6, 0.6), rnd.uniform(-0.6, 0.6), 0.037 + 0.001*k))
            for v in bm.verts: v.co.x *= sx*rnd.uniform(0.9, 1.1); v.co += at
            obj("Poison", bm, poison, smooth=True)
        fl, _ = mat("Flight", (0.3, 0.6, 0.1), Roughness=0.8)
        for at, yaw, tilt in (((0.25, -0.15), 70, 84), ((-0.3, 0.3), 150, 86), ((0.05, 0.42), 210, 40)):
            arrow(Vector((*at, 0.05 if tilt > 60 else 0.035)), yaw, tilt, 0.42, iron, poison, fl, thick=0.014)
    bmesh.ops.create_grid(ground, x_segments=1, y_segments=1, size=10)
    tgt = Vector((0, 0, 0))
elif P["kind"] == "teleport":
    # ---- teleport trap: a round stone dais with a groove of glowing blue round it, runes inside and a star in the
    # middle (the teleport spell's blue); a faint shaft of light over it
    frame, _ = rock_material("Dais", P["stone"], P["rock_scale"])
    obj("Dais", lathe([(1.0, -0.05), (1.0, 0.03), (0.96, 0.06), (0.0, 0.06)]), frame, smooth=False)
    glow, gb = mat("Glow", (0.05, 0.2, 0.8), Roughness=0.3, **{"Emission Color": (*P["glow"], 1), "Emission Strength": P["shine"]})
    glow.cycles.emission_sampling = 'NONE'
    for r, w in ((0.86, 0.035), (0.6, 0.02)):          # two glowing rings set in the stone
        bm = bmesh.new(); n = 64
        a = [bm.verts.new(((r - w)*math.cos(math.tau*i/n), (r - w)*math.sin(math.tau*i/n), 0.062)) for i in range(n)]
        b = [bm.verts.new(((r + w)*math.cos(math.tau*i/n), (r + w)*math.sin(math.tau*i/n), 0.062)) for i in range(n)]
        for i in range(n): bm.faces.new((a[i], b[i], b[(i+1) % n], a[(i+1) % n]))
        obj("Ring", bm, glow)
    for i in range(12):                                # runes between the rings: little strokes, each different
        c = 0.73; a0 = math.tau*i/12
        rot = Matrix.Rotation(a0 - math.pi/2, 4, 'Z'); at = Vector((c*math.cos(a0), c*math.sin(a0), 0.063))
        for s in range(rnd.randint(2, 3)):
            x0, y0 = rnd.uniform(-0.04, 0.04), rnd.uniform(-0.05, 0.05); ang_ = rnd.choice((0, 45, 90, 135))
            bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1)
            bm.transform(Matrix.Translation(at) @ rot @ Matrix.Translation((x0, y0, 0)) @ Matrix.Rotation(math.radians(ang_), 4, 'Z') @ Matrix.Diagonal((0.035, 0.007, 1, 1)))
            obj("Rune", bm, glow)
    for k in range(8):                                 # an eight-point star: lines from point to point, three on
        a0, a1 = math.tau*k/8, math.tau*(k + 3)/8
        p0 = Vector((0.5*math.cos(a0), 0.5*math.sin(a0), 0.063)); p1 = Vector((0.5*math.cos(a1), 0.5*math.sin(a1), 0.063))
        mid = (p0 + p1)/2; d = p1 - p0
        bm = bmesh.new(); bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=1)
        bm.transform(Matrix.Translation(mid) @ Matrix.Rotation(math.atan2(d.y, d.x), 4, 'Z') @ Matrix.Diagonal((d.length/2, 0.012, 1, 1)))
        obj("Star", bm, glow)
    l = bpy.data.lights.new("Glow", 'POINT'); l.energy = 30; l.color = P["glow"]; l.shadow_soft_size = 0.5
    link(sc, "Glow", l).location = (0, 0, 0.35)
    shaft(P["glow"], 0.8, 0.06, 1.4, P["column"])
    bmesh.ops.create_grid(ground, x_segments=1, y_segments=1, size=10)
    tgt = Vector((0, 0, 0))
else:
    # ---- trapdoor: stone frame, planks across, two iron straps running back to hinge knuckles, a ring pull
    frame, _ = rock_material("Frame", P["stone"], P["rock_scale"])
    D, F = 0.8, 1.05                                   # half-size of the door opening / of the frame
    stone_frame(frame, D, F)
    wood = wood_material("Wood", P["wood"])
    NP, gap = 7, 0.014
    pw = (2*D - 0.02)/NP
    for k in range(NP):                                # planks run left-right, stacked front to back
        y0 = -D + 0.01 + k*pw
        obj("Plank", prism(rect(-D + 0.01, D - 0.01, y0 + gap/2, y0 + pw - gap/2), -0.04, 0.03 + rnd.uniform(-0.006, 0.004)), wood, bevel=0.01)
    iron, ib = mat("Iron", (0.05, 0.05, 0.055), Metallic=0.85, Roughness=0.55)
    for x in (-0.45, 0.45):
        obj("Strap", prism(rect(x - 0.045, x + 0.045, -D + 0.05, D + 0.04), 0.0, 0.045), iron, bevel=0.006)
        for k in range(NP):                            # a nail head per plank
            y = -D + 0.01 + (k + 0.5)*pw
            bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=10, radius1=0.016, radius2=0.011, depth=0.012)
            bm.transform(Matrix.Translation((x, y, 0.051)))
            obj("Nail", bm, iron, smooth=True)
        bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.035, radius2=0.035, depth=0.16)
        bm.transform(Matrix.Translation((x, D + 0.04, 0.035)) @ Matrix.Rotation(math.pi/2, 4, 'Y'))
        obj("Knuckle", bm, iron, smooth=True)          # hinge knuckle on the frame's back edge
    bm = bmesh.new(); bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.04, radius2=0.035, depth=0.012)
    bm.transform(Matrix.Translation((0, -D + 0.14, 0.036)))
    obj("Plate", bm, iron, smooth=True)
    bm = bmesh.new()                                   # ring pull lying flat, towards the front
    RM, RN = 0.075, 0.012
    vs = [[bm.verts.new(((RM + RN*math.cos(v))*math.cos(u), -D + 0.14 - RM + (RM + RN*math.cos(v))*math.sin(u), 0.044 + RN*math.sin(v)))
           for v in (math.tau*j/8 for j in range(8))] for u in (math.tau*i/32 for i in range(32))]
    for i in range(32):
        for j in range(8):
            bm.faces.new((vs[i][j], vs[(i+1) % 32][j], vs[(i+1) % 32][(j+1) % 8], vs[i][(j+1) % 8]))
    obj("Ring", bm, iron, smooth=True)
    bmesh.ops.create_grid(ground, x_segments=1, y_segments=1, size=10)
    tgt = Vector((0, 0, 0))

gm = bpy.data.meshes.new("Ground"); ground.to_mesh(gm); ground.free()
link(sc, "Ground", gm).is_shadow_catcher = True

rig(sc, tgt=tgt, elev=P["elev"])
sc.camera.data.lens = 68                          # same scale as the stairs
studio_world(sc, 0.4)
spot(sc, (-3, -4, 4), 150, (1, 0.95, 0.85), tgt=Vector((0, 0, 0))); spot(sc, (3, -3, 3), 80, (1, 1, 1), tgt=Vector((0, 0, 0)))
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 5; sun.angle = math.radians(6)
so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(32), 0, math.radians(-40))
for l in bpy.data.lights:                          # only the sun darkens the ground (see build_throne.py)
    if l.type != 'SUN': l.use_shadow = False
vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
vis.diffuse = False                                # also keeps the pit dark: no ambient light down there
render(sc, OUT, P["save_blend"], samples=128)
