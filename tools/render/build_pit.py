"""Build + render a floor trap (with a shadow).  Usage:
blender -b -P build_pit.py -- out.png '{"kind":"pit", "elev":45, ...}'
pit:      a ragged hole broken through the floor, edged by cracked paving and a little rubble; its rock walls fade
          to black with depth (the ground is a shadow catcher with the same hole in it).
trapdoor: a closed plank door set flush in a stone frame, with iron straps, hinges at the back and a ring pull.
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, rock_material, studio_world, spot, wood_material

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "pit.png"
P = dict(kind="pit", stone=(0.2, 0.2, 0.21), rock_scale=0.6, wood=(0.085, 0.05, 0.028), elev=90, seed=3, save_blend=False)
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
else:
    # ---- trapdoor: stone frame, planks across, two iron straps running back to hinge knuckles, a ring pull
    frame, _ = rock_material("Frame", P["stone"], P["rock_scale"])
    D, F = 0.8, 1.05                                   # half-size of the door opening / of the frame
    for outline in (rect(-F, F, -F, -D), rect(-F, F, D, F), rect(-F, -D, -D, D), rect(D, F, -D, D)):
        obj("Frame", prism(outline, -0.08, 0.05), frame, bevel=0.02)
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
