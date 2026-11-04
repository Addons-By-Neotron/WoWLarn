"""Build + render a closed spell tome standing upright.  Usage:
blender -b -P build_tome.py -- out.png '{"sigil":"/path/sigil.png", "leather":[r,g,b], ...}'
Leather boards with a bulging, banded spine, metal strap hinges, cream page block, a gold sigil and a tooled ornamental border on the cover.
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import link, mat, rig, render, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "tome.png"
P = dict(leather=(0.3, 0.16, 0.06), pages=(0.8, 0.72, 0.52), metal=(0.4, 0.4, 0.42), gold=(1.0, 0.72, 0.3),
         brass=(0.72, 0.5, 0.2), sigil=None, border=None,
         yaw=28, lean=0, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

W, H, T = 1.5, 2.0, 0.5          # cover width (X), height (Z), thickness (Y); front cover faces -Y (camera)
BT, OH = 0.06, 0.05              # board thickness, board overhang past the pages

root = bpy.data.objects.new("Tome", None); sc.collection.objects.link(root)

def obj(name, bm, material, bevel=0.0, segs=3):
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for f in me.polygons: f.use_smooth = True
    o = link(sc, name, me); o.parent = root; o.data.materials.append(material)
    if bevel:
        m = o.modifiers.new("Bevel", 'BEVEL'); m.width = bevel; m.segments = segs; m.limit_method = 'ANGLE'
    return o

def box(sx, sy, sz, loc):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co = Vector((v.co.x*sx + loc[0], v.co.y*sy + loc[1], v.co.z*sz + loc[2]))
    return bm

# ---- materials
leather, lb = mat("Leather", P["leather"], Roughness=0.55)
nt = leather.node_tree; N = nt.nodes.new; Lk = nt.links.new
tc = N("ShaderNodeTexCoord")
blot = N("ShaderNodeTexNoise"); blot.inputs["Scale"].default_value = 4; blot.inputs["Detail"].default_value = 5
Lk(tc.outputs["Object"], blot.inputs["Vector"])
br = N("ShaderNodeValToRGB"); Lk(blot.outputs["Fac"], br.inputs[0])
br.color_ramp.elements[0].position = 0.35; br.color_ramp.elements[1].position = 0.7
br.color_ramp.elements[0].color = (*[c*0.55 for c in P["leather"]], 1); br.color_ramp.elements[1].color = (*[min(1, c*1.15) for c in P["leather"]], 1)
Lk(br.outputs["Color"], lb.inputs["Base Color"])
grain = N("ShaderNodeTexVoronoi"); grain.inputs["Scale"].default_value = 90; Lk(tc.outputs["Object"], grain.inputs["Vector"])
bump = N("ShaderNodeBump"); bump.inputs["Strength"].default_value = 0.35; bump.inputs["Distance"].default_value = 0.01
Lk(grain.outputs["Distance"], bump.inputs["Height"]); Lk(bump.outputs["Normal"], lb.inputs["Normal"])

pages, pb = mat("Pages", P["pages"], Roughness=0.85)
nt = pages.node_tree; N = nt.nodes.new; Lk = nt.links.new
tc = N("ShaderNodeTexCoord")
wv = N("ShaderNodeTexWave"); wv.wave_type = 'BANDS'; wv.bands_direction = 'Y'
wv.inputs["Scale"].default_value = 18; wv.inputs["Distortion"].default_value = 1.5; wv.inputs["Detail"].default_value = 3
Lk(tc.outputs["Object"], wv.inputs["Vector"])
pr = N("ShaderNodeValToRGB"); Lk(wv.outputs["Fac"], pr.inputs[0])
pr.color_ramp.elements[0].color = (*[c*0.7 for c in P["pages"]], 1); pr.color_ramp.elements[1].color = (*P["pages"], 1)
Lk(pr.outputs["Color"], pb.inputs["Base Color"])
pbump = N("ShaderNodeBump"); pbump.inputs["Strength"].default_value = 0.3; pbump.inputs["Distance"].default_value = 0.005
Lk(wv.outputs["Fac"], pbump.inputs["Height"]); Lk(pbump.outputs["Normal"], pb.inputs["Normal"])

metal, mb = mat("Metal", P["metal"], Metallic=1.0, Roughness=0.5)  # worn, hammered: dull with dark pits and dents
nt = metal.node_tree; N = nt.nodes.new; Lk = nt.links.new
tc = N("ShaderNodeTexCoord")
pit = N("ShaderNodeTexNoise"); pit.inputs["Scale"].default_value = 40; pit.inputs["Detail"].default_value = 8
pit.inputs["Roughness"].default_value = 0.65; Lk(tc.outputs["Object"], pit.inputs["Vector"])
mr = N("ShaderNodeValToRGB"); Lk(pit.outputs["Fac"], mr.inputs[0])
mr.color_ramp.elements[0].position = 0.35; mr.color_ramp.elements[1].position = 0.65
mr.color_ramp.elements[0].color = (*[c*0.45 for c in P["metal"]], 1); mr.color_ramp.elements[1].color = (*P["metal"], 1)
Lk(mr.outputs["Color"], mb.inputs["Base Color"])
rr = N("ShaderNodeMapRange"); rr.inputs["To Min"].default_value = 0.65; rr.inputs["To Max"].default_value = 0.4
Lk(pit.outputs["Fac"], rr.inputs["Value"]); Lk(rr.outputs["Result"], mb.inputs["Roughness"])
dent = N("ShaderNodeTexVoronoi"); dent.inputs["Scale"].default_value = 25; Lk(tc.outputs["Object"], dent.inputs["Vector"])
mbump = N("ShaderNodeBump"); mbump.inputs["Strength"].default_value = 0.5; mbump.inputs["Distance"].default_value = 0.01
Lk(dent.outputs["Distance"], mbump.inputs["Height"]); Lk(mbump.outputs["Normal"], mb.inputs["Normal"])
gold, _ = mat("Gold", P["gold"], Metallic=1.0, Roughness=0.25)

# ---- page block (slightly inset from the boards, fore-edge gently concave)
px0, px1 = -W/2 + 0.04, W/2 - OH
bm = box(px1 - px0, T - 2*BT, H - 2*OH, ((px0 + px1)/2, 0, 0))
bmesh.ops.subdivide_edges(bm, edges=[e for e in bm.edges if abs(e.verts[0].co.y - e.verts[1].co.y) > 0.1], cuts=6)
for v in bm.verts:
    if v.co.x > px1 - 1e-4:
        v.co.x -= 0.03*(1 - (2*v.co.y/(T - 2*BT))**2)
obj("Pages", bm, pages, bevel=0.01, segs=2)

# ---- boards + rounded spine with raised bands
for side in (-1, 1):
    obj("Board", box(W, BT, H, (0, side*(T/2 - BT/2), 0)), leather, bevel=0.022)
def spine_a(z):                                    # spine depth (x semi-axis): barrel-shaped bulge, fullest mid-height
    return T/2*(0.62 + 0.22*(1 - (2*z/H)**2))

def loft(zs, grow=0.0, segs=40):
    """Closed elliptic tube around the spine axis through the given heights (capped), offset outward by grow."""
    bm = bmesh.new(); rings = []
    for z in zs:
        a, b = spine_a(z) + grow, T/2 + grow
        rings.append([bm.verts.new((-W/2 + a*math.cos(t), b*math.sin(t), z))
                      for t in (math.tau*k/segs for k in range(segs))])
    for r0, r1 in zip(rings, rings[1:]):
        for k in range(segs):
            bm.faces.new((r0[k], r0[(k+1) % segs], r1[(k+1) % segs], r1[k]))
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    return bm

obj("Spine", loft([H/2*(2*k/24 - 1) for k in range(25)]), leather, bevel=0.02)
for z in (-0.38, 0.0, 0.38):
    obj("Band", loft([z - 0.035, z + 0.035], grow=0.025), leather, bevel=0.025, segs=4)

# ---- metal strap hinges: a thick knuckle over the spine, straps with a raised centre ridge that flare
#      onto both boards into a straight-sided arrowhead point, riveted on the front
HL, HW, HTH, E = 0.42, 0.18, 0.018, 0.006          # reach onto the boards, width at the spine, thickness, gap over the leather
WIDE, AT, RIDGE, KNUCKLE = 1.9, 0.6, 0.6, 1.4      # arrowhead width (x HW) and where it peaks (fraction of HL); ridge, knuckle height
US = [HL*k/10 for k in range(11)]                  # distances from the spine (straight segments: the shape is all corners)

def strap_profile(u):
    """Half width and thickness of a strap at u (0 at the spine, 1 at the tip): widen, then straight taper to a point."""
    w = HW/2*(1 + (WIDE - 1)*u/AT) if u <= AT else HW/2*WIDE*max(0.03, (1 - u)/(1 - AT))
    return w, HTH*(1 + 0.4*min(u, AT)/AT)

for zh in (-0.64, 0.64):
    a, b = spine_a(zh) + E, T/2 + E
    path = [(-W/2 + u, -b, *strap_profile(u/HL)) for u in US[:0:-1]]          # front strap, tip -> spine
    path += [(-W/2 + a*math.cos(t), b*math.sin(t), HW/2, HTH*(1 + KNUCKLE*math.sin(math.pi*k/16)))
             for k, t in ((k, -math.pi/2 - math.pi*k/16) for k in range(17))] # around the spine, thickest mid-spine
    path += [(-W/2 + u, b, *strap_profile(u/HL)) for u in US[1:]]             # back strap, spine -> tip
    bm = bmesh.new(); secs = []
    for i, (x, y, w, th) in enumerate(path):
        p0, p1 = Vector(path[max(0, i-1)][:2]), Vector(path[min(len(path)-1, i+1)][:2])
        t = (p1 - p0).normalized(); n = Vector((t.y, -t.x))
        if n.dot(Vector((x + W/2 - 0.2, y))) < 0: n = -n
        out = lambda h: (x + n.x*h, y + n.y*h)
        secs.append([bm.verts.new((x, y, zh - w)), bm.verts.new((*out(th), zh - w)),
                     bm.verts.new((*out(th*(1 + RIDGE)), zh)),              # raised centre ridge
                     bm.verts.new((*out(th), zh + w)), bm.verts.new((x, y, zh + w))])
    for s0, s1 in zip(secs, secs[1:]):
        for k in range(5):
            bm.faces.new((s0[k], s0[(k+1) % 5], s1[(k+1) % 5], s1[k]))
    bm.faces.new(secs[0]); bm.faces.new(secs[-1][::-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    hg = obj("Hinge", bm, metal, bevel=0.006, segs=2)
    for f in hg.data.polygons: f.use_smooth = False                          # keep the facets crisp
    for rx in (0.1, 0.25):                                                   # rivets on the front strap's ridge
        _, th = strap_profile(rx/HL)
        sb = bmesh.new(); bmesh.ops.create_uvsphere(sb, u_segments=12, v_segments=8, radius=0.03)
        for v in sb.verts: v.co += Vector((-W/2 + rx, -(b + th*(1 + RIDGE)), zh))
        obj("Rivet", sb, metal)

# ---- cover emblem: gold ring frame + gold sigil inlay
R = 0.42; cz0 = 0.05
bm = bmesh.new()
bmesh.ops.create_circle(bm, cap_ends=False, segments=48, radius=R)
ring = [v for v in bm.verts]
for v in ring: v.co = Vector((v.co.x, -(T/2 + 0.005), v.co.y + cz0))
fr = obj("Frame", bm, gold)
fr.modifiers.new("Skin", 'SKIN')                    # thicken the circle into a round wire
for v in fr.data.skin_vertices[0].data: v.radius = (0.03, 0.03)
fr.modifiers.new("Smooth", 'SUBSURF').levels = 2

def decal(name, image, color, x0, x1, z0, z1, rough=0.3, emboss=0.0):
    """Gold-leaf style plate on the front cover: metal where the image has ink, transparent elsewhere;
    emboss > 0 bumps the ink up so the edges catch light like a raised, tooled ornament."""
    m, sb = mat(name, color, Metallic=1.0, Roughness=rough)
    nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    out = nt.nodes["Material Output"]; mix = N("ShaderNodeMixShader"); tr = N("ShaderNodeBsdfTransparent")
    im = N("ShaderNodeTexImage"); im.image = bpy.data.images.load(image); im.extension = 'CLIP'
    Lk(im.outputs["Alpha"], mix.inputs[0]); Lk(tr.outputs[0], mix.inputs[1]); Lk(sb.outputs[0], mix.inputs[2])
    Lk(mix.outputs[0], out.inputs["Surface"])
    if emboss:
        bp = N("ShaderNodeBump"); bp.inputs["Strength"].default_value = emboss; bp.inputs["Distance"].default_value = 0.02
        Lk(im.outputs["Alpha"], bp.inputs["Height"]); Lk(bp.outputs["Normal"], sb.inputs["Normal"])
    bm = bmesh.new()
    vs = [bm.verts.new((x, -(T/2 + 0.004), z)) for x, z in ((x0, z0), (x1, z0), (x1, z1), (x0, z1))]
    f = bm.faces.new(vs); uv = bm.loops.layers.uv.new("UVMap")
    for l, c in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))): l[uv].uv = c
    obj(name, bm, m)

if P["sigil"]:
    s = R*0.98
    decal("Sigil", P["sigil"], P["gold"], -s, s, cz0 - s, cz0 + s, emboss=0.6)
if P["border"]:                                    # image spans the whole front board (W x H)
    decal("Border", P["border"], P["brass"], -W/2, W/2, -H/2, H/2, rough=0.45, emboss=0.8)

root.location = (0, 0, 1.4)
root.rotation_mode = 'ZXY'
root.rotation_euler = (0, math.radians(P["lean"]), math.radians(P["yaw"]))   # yaw turns the spine toward the camera

rig(sc)
studio_world(sc, 0.5)                               # something for the metal to reflect
spot(sc, (-3, -3, 4), 120, (1, 0.95, 0.85))
render(sc, OUT, P["save_blend"], samples=128)
