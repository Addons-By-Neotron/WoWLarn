"""Build + render a volcanic shaft: the volcano level's stairs (with a shadow).  Usage:
blender -b -P build_volcano.py -- out.png '{"down":false, "elev":45, ...}'
Natural black basalt (glowing lava cracks optional); a rough rock walkway instead of steps: a ledge along the wall of
the shaft or cave.
down: a ragged crater in the floor; the walkway winds down round a shaft that leans away from the viewer and
      fades to black (the ground is a shadow catcher with the same hole in it).
up:   a lumpy rock floor; the walkway climbs round the inside of a rough rock wall round the back half,
      both fading into the dark above.
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, rig, render, rock_material, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "volcano.png"
P = dict(down=False, basalt=(0.035, 0.032, 0.032), rock_scale=0.7, lava=(1.0, 0.3, 0.04), cracks=0, elev=90, seed=5,
         save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
rnd = random.Random(P["seed"])

root = bpy.data.objects.new("Volcano", None); sc.collection.objects.link(root)

def obj(name, bm, material, smooth=False):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = smooth
    o = link(sc, name, me); o.parent = root; o.data.materials.append(material)
    return o

def rock(name, loc, size, material):
    """A lump of rubble: a jittered, squashed icosphere."""
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1)
    for v in bm.verts:
        v.co = Vector((v.co.x*size, v.co.y*size*rnd.uniform(0.7, 1.1), v.co.z*size*0.7))*rnd.uniform(0.8, 1.15)
    bm.transform(Matrix.Translation(loc) @ Matrix.Rotation(rnd.uniform(0, math.tau), 4, 'Z'))
    return obj(name, bm, material)

# ---- basalt, with glowing cracks if cracks > 0 (the edges of a voronoi pattern glow where a noise mask lets them);
# it fades to black away from the floor (down the shaft / up into the dark)
basalt, btint = rock_material("Basalt", P["basalt"], P["rock_scale"], fade=(0.0, -1.2) if P["down"] else (0.5, 2.2))
nt = basalt.node_tree; N = nt.nodes.new; Lk = nt.links.new; bs = nt.nodes["Principled BSDF"]
tc = N("ShaderNodeTexCoord")
vo = N("ShaderNodeTexVoronoi"); vo.feature = 'DISTANCE_TO_EDGE'; vo.inputs["Scale"].default_value = 4
Lk(tc.outputs["Object"], vo.inputs["Vector"])
ck = N("ShaderNodeMapRange"); ck.inputs["From Max"].default_value = 0.025
ck.inputs["To Min"].default_value = 1.0; ck.inputs["To Max"].default_value = 0.0; Lk(vo.outputs["Distance"], ck.inputs["Value"])
nz = N("ShaderNodeTexNoise"); nz.inputs["Scale"].default_value = 2.5; Lk(tc.outputs["Object"], nz.inputs["Vector"])
nm = N("ShaderNodeMapRange"); nm.inputs["From Min"].default_value = 0.6; nm.inputs["From Max"].default_value = 0.68
Lk(nz.outputs["Fac"], nm.inputs["Value"])
cm = N("ShaderNodeMath"); cm.operation = 'MULTIPLY'; Lk(ck.outputs["Result"], cm.inputs[0]); Lk(nm.outputs["Result"], cm.inputs[1])
cs = N("ShaderNodeMath"); cs.operation = 'MULTIPLY'; cs.inputs[1].default_value = P["cracks"]; Lk(cm.outputs[0], cs.inputs[0])
bs.inputs["Emission Color"].default_value = (*P["lava"], 1); Lk(cs.outputs[0], bs.inputs["Emission Strength"])
path_mat = basalt.copy()                           # the walkway: lighter, worn rock, so it stands out from the walls
path_mat.node_tree.nodes[btint.name].inputs["B"].default_value = (*[c*3.2 for c in P["basalt"]], 1)
if P["down"]:                                      # and it fades slower, so it shows further down the shaft
    for n_ in path_mat.node_tree.nodes:
        if n_.type == 'MAP_RANGE' and n_.inputs["From Max"].default_value == -1.2:
            n_.inputs["From Max"].default_value = -2.2

def walkway(path, width, floor=None, thick=0.35):
    """A rough slab of rock along path (Vectors on its top centre line, winding counter-clockwise against a wall on its
    right): a crowned, uneven top with ragged edges, its sides running down to z=floor (solid to the ground) or thick
    below the top.  The open (left) side is a natural rock face: bulging, uneven, and spreading out at its foot."""
    bm = bmesh.new(); secs = []
    ph = [rnd.uniform(0, math.tau) for _ in range(3)]
    for i, p in enumerate(path):
        t = (path[min(i+1, len(path)-1)] - path[max(i-1, 0)]); t.z = 0; t.normalize()
        side = Vector((-t.y, t.x, 0)); w = width/2*rnd.uniform(0.85, 1.15)
        top = [p + side*s*w + Vector((0, 0, dz + rnd.uniform(-0.015, 0.015))) for s, dz in ((-1, -0.05), (-0.5, -0.01), (0, 0), (0.5, -0.01), (1, -0.05))]
        zb = floor if floor is not None else top[-1].z - thick
        h = top[-1].z - zb
        wob = [0.05*math.sin(0.8*i + ph[j]) + rnd.uniform(-0.03, 0.03) for j in range(3)]
        face = [top[-1] + side*(0.03 + wob[0]) + Vector((0, 0, -0.3*h)),                      # bulging out
                top[-1] + side*(0.06 + 0.12*h + wob[1]) + Vector((0, 0, -0.68*h)),
                top[-1] + side*(0.12 + 0.3*min(h, 1.5) + wob[2]) + Vector((0, 0, -h))]   # the foot spreads out
        outer = Vector((top[0].x, top[0].y, zb))
        secs.append([bm.verts.new(q) for q in [outer] + top + face])
    for s0, s1 in zip(secs, secs[1:]):
        for k in range(8):
            bm.faces.new((s0[k], s1[k], s1[k+1], s0[k+1]))
        bm.faces.new((s0[8], s1[8], s1[0], s0[0]))   # underside
    for s in (secs[0], secs[-1]):
        bm.faces.new(s)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

NS = 64
ang = [math.tau*k/NS for k in range(NS)]
harm = [(k, rnd.uniform(0.03, 0.08)/k**0.4, rnd.uniform(0, math.tau)) for k in (2, 3, 5, 7)]
def ragged(a, r):
    return r*(1 + sum(amp*math.sin(k*a + ph) for k, amp, ph in harm))
def smooth(vals):
    return [(vals[k-1] + 2*vals[k] + vals[(k+1) % NS])/4 for k in range(NS)]

ground = bmesh.new()
if P["down"]:
    # ---- crater: a raised, broken lip running down into rough walls that lean away as they go down
    bm = bmesh.new()
    def ring(rs, zs, off=Vector()):
        return [bm.verts.new((off.x + r*math.cos(a), off.y + r*math.sin(a), z)) for a, r, z in zip(ang, rs, zs)]
    rh = [ragged(a, 0.85) + rnd.uniform(-0.05, 0.05) for a in ang]
    width = smooth([rnd.uniform(0.25, 0.5) for _ in ang])
    lip = []
    for t, hi in ((1.0, 0.0), (0.7, 0.04), (0.4, 0.1), (0.15, 0.14), (0.0, 0.09)):   # outside in
        lip.append(ring([r + t*w + (rnd.uniform(-0.05, 0.05) if t else 0) for r, w in zip(rh, width)],
                        [rnd.uniform(-0.01, 0.005) if not hi else rnd.uniform(0.3, 1.0)*hi for _ in ang]))
    walls = [lip[-1]]
    for d in range(1, 14):
        walls.append(ring([r*(1 - 0.012*d) + rnd.uniform(-0.04, 0.04) for r in rh], [-0.16*d + rnd.uniform(-0.03, 0.03) for _ in ang],
                          Vector((0, 0.3*0.16*d, 0))))
    for out, inn in zip(lip, lip[1:]):             # facing up
        for k in range(NS):
            bm.faces.new((inn[k], out[k], out[(k+1) % NS], inn[(k+1) % NS]))
    for top, low in zip(walls, walls[1:]):         # facing in
        for k in range(NS):
            bm.faces.new((top[k], top[(k+1) % NS], low[(k+1) % NS], low[k]))
    bm.faces.new(walls[-1])
    obj("Crater", bm, basalt)
    # the walkway: a ledge along the shaft's wall (its outer edge sunk into it) from the near edge, round and down
    # into the dark, following the ragged, leaning wall: its centre drifts away 0.3 per unit of depth, its radius
    # narrows 1.2% per 0.16
    def ledge(t, w=0.6):
        a = -math.pi/2 + 3.6*t; z = 0.06 - 1.5*t**1.1
        r = ragged(a, 0.85)*(1 - 0.012*(-z/0.16)) - w/2 + 0.04
        return Vector((r*math.cos(a), 0.3*-z + r*math.sin(a), z))
    obj("Walkway", walkway([ledge(i/28) for i in range(29)], 0.6), path_mat, smooth=True)
    for k in range(10):
        j = rnd.randrange(NS); d = rh[j] + rnd.uniform(0.1, 0.7)
        rock("Rubble", Vector((d*math.cos(ang[j]), d*math.sin(ang[j]), 0.03)), rnd.uniform(0.04, 0.11), basalt)
    inner = [ground.verts.new((r*math.cos(a), r*math.sin(a), 0)) for a, r in zip(ang, rh)]
    outer = [ground.verts.new((10*math.cos(a), 10*math.sin(a), 0)) for a in ang]
    for k in range(NS):
        ground.faces.new((inner[k], outer[k], outer[(k+1) % NS], inner[(k+1) % NS]))
    tgt = Vector((0, 0, -0.3))
else:
    # ---- a lumpy patch of rock floor with a ragged edge
    bm = bmesh.new()
    edge = smooth([ragged(a, 1.35) + 0.35*max(0.0, math.sin(a) + 0.3)/1.3 + rnd.uniform(-0.08, 0.08) for a in ang])   # out under the wall
    rows = [[bm.verts.new((r*t*math.cos(a), r*t*math.sin(a), -0.01 if t == 1 else rnd.uniform(0.0, 0.06)*(1.2 - t)))
             for a, r in zip(ang, edge)] for t in (1.0, 0.8, 0.55, 0.3)]
    c = bm.verts.new((0, 0, 0.03))
    for out, inn in zip(rows, rows[1:]):
        for k in range(NS):
            bm.faces.new((inn[k], out[k], out[(k+1) % NS], inn[(k+1) % NS]))
    for k in range(NS):
        bm.faces.new((rows[-1][k], rows[-1][(k+1) % NS], c))
    obj("Floor", bm, basalt, smooth=True)
    # a rough rock wall round the back half, dying down at both ends
    A0, A1, M, WH, RW, TW = -0.2, math.pi + 0.2, 40, 2.1, 1.35, 0.3
    bm = bmesh.new(); cols = []
    hs = [max(0.15, WH*max(0.0, min(1.0, (a - A0)/0.7, (A1 - a)/0.7))**0.7*rnd.uniform(0.85, 1.05))
          for a in (A0 + (A1 - A0)*i/M for i in range(M + 1))]
    hs = [hs[0]] + [(hs[i-1] + 2*hs[i] + hs[i+1])/4 for i in range(1, M)] + [hs[-1]]   # a rolling top, not teeth
    for i in range(M + 1):
        a = A0 + (A1 - A0)*i/M; h = hs[i]
        rin = [RW + 0.08*math.sin(3*a + 1.3*j) + rnd.uniform(-0.06, 0.06) for j in range(9)]
        inner = [bm.verts.new((r*math.cos(a), r*math.sin(a), h*j/8)) for j, r in enumerate(rin)]
        outer = [bm.verts.new(((r + TW)*math.cos(a), (r + TW)*math.sin(a), h*j/8)) for j, r in enumerate(rin)]
        cols.append((inner, outer))
    for (i0, o0), (i1, o1) in zip(cols, cols[1:]):
        for j in range(8):
            bm.faces.new((i0[j], i1[j], i1[j+1], i0[j+1])); bm.faces.new((o0[j], o0[j+1], o1[j+1], o1[j]))
        bm.faces.new((i0[8], i1[8], o1[8], o0[8]))
    for inner, outer in (cols[0], cols[-1]):
        for j in range(8):
            bm.faces.new((inner[j], inner[j+1], outer[j+1], outer[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    obj("Cave", bm, basalt).visible_shadow = False   # its shadow would only spill out of the icon
    # the walkway: a solid ledge built up against the inside of the wall (its outer edge sunk into it), from the
    # wall's near right end round the back
    def ledge(t, w=0.7):
        a = -0.15 + 2.9*t; r = RW - w/2 + 0.1
        return Vector((r*math.cos(a), r*math.sin(a), 0.04 + 1.6*t**1.2))
    obj("Walkway", walkway([ledge(i/28) for i in range(29)], 0.7, floor=0.0), path_mat, smooth=True)
    for k in range(8):
        a = rnd.uniform(-math.pi, 0); d = rnd.uniform(0.6, 1.3)   # rubble on the near half
        rock("Rubble", Vector((d*math.cos(a), d*math.sin(a), 0.04)), rnd.uniform(0.04, 0.1), basalt)
    bmesh.ops.create_grid(ground, x_segments=1, y_segments=1, size=10)
    tgt = Vector((0, 0, 0.6))

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
vis.diffuse = False
render(sc, OUT, P["save_blend"], samples=128)
