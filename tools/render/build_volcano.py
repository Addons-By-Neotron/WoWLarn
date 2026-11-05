"""Build + render a volcanic shaft: the volcano level's stairs (with a shadow).  Usage:
blender -b -P build_volcano.py -- out.png '{"down":false, "elev":45, ...}'
Natural black basalt (glowing lava cracks optional); a rough rock walkway instead of steps: a ledge along the wall of
the shaft or cave.
down: the volcano as seen in the open world (the way in): a ragged basalt cone with a lava pool in its crater and
      lava running down its sides.
up:   the way out, inside: a lumpy rock floor; the walkway climbs straight from the near left to the far right
      against a rough rock wall, both fading into the dark above.
"""
import bpy, bmesh, math, os, random, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, rig, render, rock_material, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "volcano.png"
P = dict(down=False, basalt=(0.012, 0.010, 0.010), rock_scale=0.7, lava=(0.9, 0.08, 0.01), cracks=0, elev=90, seed=5,
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
basalt, btint = rock_material("Basalt", P["basalt"], P["rock_scale"], fade=None if P["down"] else (0.9, 2.6))
nt = basalt.node_tree; N = nt.nodes.new; Lk = nt.links.new; bs = nt.nodes["Principled BSDF"]
bs.inputs["Specular IOR Level"].default_value = 0.2   # little grey sheen: lava rock is dark
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
            bm.faces.new((s0[k], s1[k], s1[k+1], s0[k+1])).material_index = 1 if k >= 5 else 0   # 1: the rock face
        bm.faces.new((s0[8], s1[8], s1[0], s0[0]))   # underside
    for s in (secs[0], secs[-1]):
        bm.faces.new(s)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

def spline_pts(pts, n=4):
    """Catmull-Rom through the points, n steps per span."""
    ext = [2*pts[0] - pts[1]] + pts + [2*pts[-1] - pts[-2]]; out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i-1:i+3]
        for k in range(n):
            t = k/n
            out.append(0.5*((2*p1) + (-p0 + p2)*t + (2*p0 - 5*p1 + 4*p2 - p3)*t*t + (-p0 + 3*p1 - 3*p2 + p3)*t**3))
    out.append(pts[-1]); return out

def ribbon(path, widths):
    """A flat strip along path (lying on a slope), widths per point; a slight crown so it catches the light."""
    bm = bmesh.new(); rows = []
    for i, p in enumerate(path):
        t = path[min(i+1, len(path)-1)] - path[max(i-1, 0)]; up = Vector((p.x, p.y, 0)).normalized()
        side = t.cross(up).normalized(); w = widths[i]/2
        rows.append([bm.verts.new(p + side*w*s_ + up*(0.01*(1 - abs(s_)))) for s_ in (-1, -0.5, 0, 0.5, 1)])
    for r0, r1 in zip(rows, rows[1:]):
        for k in range(4):
            bm.faces.new((r0[k], r0[k+1], r1[k+1], r1[k]))
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
    # ---- the volcano as seen in the open world: a ragged basalt cone (gullies down its sides, its foot spreading
    # out), a crater at the top holding a pool of lava, a few lava runs spilling down the slopes
    H, R0, RC = 1.35, 1.45, 0.32
    gul = [(k, rnd.uniform(0.02, 0.05), rnd.uniform(0, math.tau)) for k in (7, 11, 17)]
    def cone_r(a, t):                              # t: 0 at the foot, 1 at the rim
        r = RC + (R0 - RC)*(1 - t)**1.8
        return ragged(a, r)*(1 + sum(amp*math.sin(k*a + ph + 2*t) for k, amp, ph in gul))
    bm = bmesh.new(); M = 20; rows = []
    for i in range(M + 1):
        t = i/M
        rows.append([bm.verts.new((cone_r(a, t)*math.cos(a), cone_r(a, t)*math.sin(a),
                                   H*t + (rnd.uniform(-0.02, 0.02) if 0 < i < M else 0) - (0.01 if i == 0 else 0))) for a in ang])
    rimz = [H + rnd.uniform(-0.05, 0.04) for _ in ang]
    for k, v in enumerate(rows[-1]): v.co.z = rimz[k]
    for t, dz in ((0.8, -0.1), (0.62, -0.2)):      # the crater: down the inside of the rim to the pool
        rows.append([bm.verts.new((RC*t*math.cos(a)*(1 + rnd.uniform(-0.05, 0.05)), RC*t*math.sin(a)*(1 + rnd.uniform(-0.05, 0.05)),
                                   H + dz + rnd.uniform(-0.02, 0.02))) for a in ang])
    for lo, hi in zip(rows, rows[1:]):
        for k in range(NS):
            bm.faces.new((lo[k], lo[(k+1) % NS], hi[(k+1) % NS], hi[k]))
    bm.faces.new(rows[-1])
    obj("Cone", bm, basalt, smooth=True)
    # molten lava: distorted noise through black crust, deep red, orange and yellow-hot; dark veins of crust
    # (voronoi edges) over it, and a bump so the crust has relief.  Kept fairly dim so the reds stay red.
    lava = bpy.data.materials.new("Lava"); lava.use_nodes = True; ln = lava.node_tree; L = ln.nodes.new; LK = ln.links.new
    lb = ln.nodes["Principled BSDF"]; lb.inputs["Roughness"].default_value = 0.45
    ltc = L("ShaderNodeTexCoord"); lnz = L("ShaderNodeTexNoise"); lnz.inputs["Scale"].default_value = 6
    lnz.inputs["Distortion"].default_value = 4.0; lnz.inputs["Detail"].default_value = 8; LK(ltc.outputs["Object"], lnz.inputs["Vector"])
    lr = L("ShaderNodeValToRGB"); LK(lnz.outputs["Fac"], lr.inputs[0]); el = lr.color_ramp.elements
    while len(el) < 5: el.new(0.5)
    for e, (pos, col) in zip(el, ((0.3, (0.0, 0.0, 0.0)), (0.42, (0.35, 0.01, 0.0)), (0.55, (0.9, 0.06, 0.005)),
                                  (0.68, (1.0, 0.25, 0.02)), (0.8, (1.0, 0.6, 0.1)))):
        e.position, e.color = pos, (*col, 1)
    lv = L("ShaderNodeTexVoronoi"); lv.feature = 'DISTANCE_TO_EDGE'; lv.inputs["Scale"].default_value = 14
    LK(ltc.outputs["Object"], lv.inputs["Vector"])
    lvr = L("ShaderNodeMapRange"); lvr.inputs["From Max"].default_value = 0.06; lvr.inputs["To Min"].default_value = 0.15
    LK(lv.outputs["Distance"], lvr.inputs["Value"])
    lm = L("ShaderNodeMix"); lm.data_type = 'RGBA'; lm.blend_type = 'MULTIPLY'; lm.inputs["Factor"].default_value = 1.0
    LK(lr.outputs["Color"], lm.inputs["A"]); LK(lvr.outputs["Result"], lm.inputs["B"])
    LK(lm.outputs["Result"], lb.inputs["Emission Color"]); lb.inputs["Emission Strength"].default_value = 3.0
    lb.inputs["Base Color"].default_value = (0.03, 0.005, 0.0, 1)
    lbp = L("ShaderNodeBump"); lbp.inputs["Strength"].default_value = 0.5; LK(lnz.outputs["Fac"], lbp.inputs["Height"])
    LK(lbp.outputs["Normal"], lb.inputs["Normal"])
    pool = bmesh.new(); pc = pool.verts.new((0, 0, H - 0.17))
    pr = [pool.verts.new((RC*0.66*math.cos(a), RC*0.66*math.sin(a), H - 0.17)) for a in ang]
    for k in range(NS):
        pool.faces.new((pc, pr[k], pr[(k+1) % NS]))
    obj("Pool", pool, lava)
    for a0 in (-1.9, -1.2, 0.4):                    # lava runs from the rim down the slopes, thinning out
        a0 += rnd.uniform(-0.15, 0.15); pts = []
        for i in range(14):
            t = 1 - 0.8*i/13; a = a0 + 0.1*math.sin(9*t + a0) + rnd.uniform(-0.02, 0.02)
            pts.append(Vector((cone_r(a, t)*math.cos(a), cone_r(a, t)*math.sin(a), H*t + 0.012)))
        pts[0].z = H - 0.03
        sp = spline_pts(pts)
        obj("Run", ribbon(sp, [0.13*(1 - 0.7*j/(len(sp) - 1))*(0.8 + 0.4*rnd.random()) for j in range(len(sp))]), lava, smooth=True)
    for k in range(12):
        a = rnd.uniform(0, math.tau); d = R0*rnd.uniform(1.0, 1.35)
        rock("Rubble", Vector((d*math.cos(a), d*math.sin(a), 0.03)), rnd.uniform(0.04, 0.11), basalt)
    bmesh.ops.create_grid(ground, x_segments=1, y_segments=1, size=10)
    tgt = Vector((0, 0, 0.45))
else:
    # ---- a lumpy patch of rock floor with a ragged edge
    bm = bmesh.new()
    edge = smooth([ragged(a, 1.35) + rnd.uniform(-0.08, 0.08) for a in ang])
    rows = [[bm.verts.new((r*t*math.cos(a), r*t*math.sin(a), -0.01 if t == 1 else rnd.uniform(0.0, 0.06)*(1.2 - t)))
             for a, r in zip(ang, edge)] for t in (1.0, 0.8, 0.55, 0.3)]
    c = bm.verts.new((0, 0, 0.03))
    for out, inn in zip(rows, rows[1:]):
        for k in range(NS):
            bm.faces.new((inn[k], out[k], out[(k+1) % NS], inn[(k+1) % NS]))
    for k in range(NS):
        bm.faces.new((rows[-1][k], rows[-1][(k+1) % NS], c))
    obj("Floor", bm, basalt, smooth=True)
    # the way out: a solid rock ramp climbing straight from the near left up to the far right, built against a
    # rough rock wall along its far side that rises with it and fades into the dark above
    A, B = Vector((-1.0, -0.8, 0)), Vector((0.85, 0.75, 0)); RWID = 0.7
    d = (B - A).normalized(); nw = Vector((-d.y, d.x, 0))
    M, WH, TW = 36, 1.7, 0.3
    bm = bmesh.new(); cols = []
    hs = [WH*min(1.0, (i/M)/0.3)**0.8*(0.45 + 0.55*i/M)*rnd.uniform(0.9, 1.05) for i in range(M + 1)]
    hs = [hs[0]] + [(hs[i-1] + 2*hs[i] + hs[i+1])/4 for i in range(1, M)] + [hs[-1]]
    for i in range(M + 1):
        s_ = -0.1 + 1.2*i/M; base = A + (B - A)*s_ + nw*(RWID/2 - 0.05); h = max(0.15, hs[i])
        rin = [0.08*math.sin(5*s_ + 1.3*j) + rnd.uniform(-0.05, 0.05) for j in range(9)]
        inner = [bm.verts.new(base + nw*r + Vector((0, 0, h*j/8))) for j, r in enumerate(rin)]
        outer = [bm.verts.new(base + nw*(r + TW) + Vector((0, 0, h*j/8))) for j, r in enumerate(rin)]
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
    # walked from the top down, so the wall is on the right and the open rock face looks toward the camera
    pts = []
    for i in range(29):
        s_ = i/28; p = B + (A - B)*s_ + nw*0.04*math.sin(5*s_)
        pts.append(Vector((p.x, p.y, 0.04 + 1.35*(1 - s_)**1.15)))
    ww = obj("Walkway", walkway(pts, RWID, floor=0.0), path_mat, smooth=True)
    cliff = basalt.copy(); cliff.node_tree.nodes[btint.name].inputs["B"].default_value = (*[c*0.55 for c in P["basalt"]], 1)
    ww.data.materials.append(cliff)                # the ramp's rock face darker, so the worn path on top stands out
    for k in range(8):
        a = rnd.uniform(-math.pi, 0); dd = rnd.uniform(0.5, 1.3)
        rock("Rubble", Vector((dd*math.cos(a) + 0.3, dd*math.sin(a), 0.04)), rnd.uniform(0.04, 0.1), basalt)
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
