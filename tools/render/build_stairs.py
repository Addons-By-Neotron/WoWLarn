"""Build + render a stone spiral stair standing on the ground (with a shadow).  Usage:
blender -b -P build_stairs.py -- out.png '{"down":false, "elev":45, ...}'
up:   wedge steps winding round a central column for about one turn, rising from a ring of stone blocks.
down: the same stair winding down into a round shaft in the floor, edged by a ring of stone blocks;
      the ground is a shadow catcher with a hole in it, so only the shaft shows below the floor.
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, rock_material, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "stairs.png"
P = dict(down=False, steps=17, turns=1.05, rise=0.15, radius=1.0, stone=(0.2, 0.2, 0.21), rock_scale=0.6,
         yaw=0, elev=90, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

root = bpy.data.objects.new("Stairs", None); sc.collection.objects.link(root)

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

def sector(r0, r1, a0, a1, n=5):
    """Ring sector outline between radii r0 < r1 and angles a0 < a1."""
    outer = [(r1*math.cos(a0 + (a1-a0)*k/n), r1*math.sin(a0 + (a1-a0)*k/n)) for k in range(n + 1)]
    inner = [(r0*math.cos(a1 - (a1-a0)*k/n), r0*math.sin(a1 - (a1-a0)*k/n)) for k in range(n + 1)]
    return outer + inner

def tube(path, r, segs=8):
    """Round tube along a polyline of Vectors."""
    bm = bmesh.new(); rings = []
    for i, p in enumerate(path):
        t = (path[min(i+1, len(path)-1)] - path[max(i-1, 0)]).normalized()
        u = t.orthogonal().normalized(); v = t.cross(u)
        rings.append([bm.verts.new(p + r*(math.cos(a)*u + math.sin(a)*v)) for a in (math.tau*k/segs for k in range(segs))])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k+1) % segs], r1[(k+1) % segs], r1[k]))
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1])
    return bm

def cylinder(r, z0, z1, segs=32, caps=True, inward=False):
    bm = bmesh.new()
    lo = [bm.verts.new((r*math.cos(a), r*math.sin(a), z0)) for a in (math.tau*k/segs for k in range(segs))]
    hi = [bm.verts.new((v.co.x, v.co.y, z1)) for v in lo]
    for k in range(segs):
        f = bm.faces.new((lo[k], lo[(k+1) % segs], hi[(k+1) % segs], hi[k]))
        if inward: f.normal_flip()
    if caps:
        bm.faces.new(lo[::-1]); bm.faces.new(hi)
    return bm

# ---- materials: weathered stone (render_common.rock_material); it fades to black away from the floor: down the
# shaft so it reads as a dark hole, and up the stair so it climbs into the dark of the room above
stone, tint = rock_material("Stone", P["stone"], P["rock_scale"], fade=(0.0, -1.4) if P["down"] else (0.4, 2.4))
black, _ = mat("Black", (0, 0, 0), Roughness=1.0)

# ---- the spiral: wedge steps round a central column
R, RC, n, rise = P["radius"], 0.17, P["steps"], P["rise"]
span = math.tau*P["turns"]/n                       # angle per step
sgn = -1 if P["down"] else 1                       # down: each step lower than the last
TH = 0.12                                          # step slab thickness
tops = []
START = math.pi/2 + 0.6 if P["down"] else -math.pi/2 - span/2   # up: the first step faces the camera
for i in range(n):
    a0 = START + i*span
    top = (i + 1)*rise if not P["down"] else -i*rise - 0.02
    tops.append((a0, top))
    obj("Step", prism(sector(RC*0.9, R, a0, a0 + span*1.12), top - TH, top), stone, bevel=0.015)
z_lo = min(t for _, t in tops) - TH; z_hi = max(t for _, t in tops)
obj("Column", cylinder(RC, z_lo - 0.4 if P["down"] else 0.0, z_hi + (0.25 if not P["down"] else 0.0), segs=24), stone, bevel=0.01, smooth=True)

HR = R + 0.04                                      # inner radius of the tower wall / shaft
def ring_blocks(name, z0, z1, n, offset=0.0, skip=lambda a: False, wall=0.28):
    """A course of n stone blocks round the stair, from radius HR out by wall; skip(a) leaves a block out."""
    for k in range(n):
        a0 = math.tau*(k + offset)/n + 0.01; a1 = math.tau*(k + 1 + offset)/n - 0.01
        if skip((a0 + a1)/2): continue
        obj(name, prism(sector(HR, HR + wall, a0, a1, 3), z0, z1), stone, bevel=0.025)

if not P["down"]:
    # open spiral rising from a ring of the same stone blocks that edge the down shaft, so the pair match
    obj("Cap", cylinder(RC + 0.05, z_hi + 0.25, z_hi + 0.33, segs=24), stone, bevel=0.015, smooth=True)
    ring_blocks("Rim", 0.0, 0.11, 14)
    floor = stone.copy()                           # paved floor inside the ring, darker so the first steps stand out
    floor.node_tree.nodes[tint.name].inputs["B"].default_value = (*[c*0.55 for c in P["stone"]], 1)
    obj("Floor", cylinder(HR, 0.0, 0.03, segs=48), floor, bevel=0.01)
else:
    # the shaft: stone wall below the floor, black far below, a ring of blocks round the opening
    HR, depth = R + 0.04, n*rise + 0.6
    obj("Shaft", cylinder(HR, -depth, 0.0, segs=48, caps=False, inward=True), stone)
    obj("Pit", cylinder(HR, -depth - 0.01, -depth, segs=48), black)
    for k in range(14):
        a0 = math.tau*k/14 + 0.01; a1 = math.tau*(k + 1)/14 - 0.01
        obj("Rim", prism(sector(HR, HR + 0.28, a0, a1, 3), -0.02, 0.11), stone, bevel=0.025)

# ---- ground: shadow catcher (with a hole over the shaft)
gb = bmesh.new()
if P["down"]:
    segs = 48; HR = R + 0.04
    inner = [gb.verts.new((HR*math.cos(a), HR*math.sin(a), 0)) for a in (math.tau*k/segs for k in range(segs))]
    outer = [gb.verts.new((10*math.cos(a), 10*math.sin(a), 0)) for a in (math.tau*k/segs for k in range(segs))]
    for k in range(segs):
        gb.faces.new((inner[k], outer[k], outer[(k+1) % segs], inner[(k+1) % segs]))
else:
    bmesh.ops.create_grid(gb, x_segments=1, y_segments=1, size=10)
gm_ = bpy.data.meshes.new("Ground"); gb.to_mesh(gm_); gb.free()
ground = link(sc, "Ground", gm_); ground.is_shadow_catcher = True

root.rotation_euler = (0, 0, math.radians(P["yaw"]))
rig(sc, tgt=Vector((0, 0, -0.2 if P["down"] else 1.1)), elev=P["elev"])
sc.camera.data.lens = 68                          # a little wider than the other items: the tower and its shadow fit
studio_world(sc, 0.4)
spot(sc, (-3, -4, 4), 150, (1, 0.95, 0.85), tgt=Vector((0, 0, 0))); spot(sc, (3, -3, 3), 80, (1, 1, 1), tgt=Vector((0, 0, 0)))
sun = bpy.data.lights.new("Sun", 'SUN'); sun.energy = 5; sun.angle = math.radians(6)
so = link(sc, "Sun", sun); so.rotation_euler = (math.radians(32), 0, math.radians(-40))   # high-ish sun: the tall stair's shadow stays in frame
for l in bpy.data.lights:                          # only the sun darkens the ground (see build_throne.py)
    if l.type != 'SUN': l.use_shadow = False
vis = getattr(sc.world, "visibility", None) or getattr(sc.world, "cycles_visibility", None)
vis.diffuse = False                                # also keeps the shaft dark: no ambient light down there
render(sc, OUT, P["save_blend"], samples=128)
