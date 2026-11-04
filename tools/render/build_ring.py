"""Build + render one ring.  Usage:
blender -b -P build_ring.py -- out.png '{"style":"plain", "metal":[r,g,b], ...}'
Styles: plain, twisted, vine, shield, zigzag, stacked, studded, waves, spiked.
"""
import bpy, bmesh, math, os, sys, json
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import mat, rig, render, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "ring.png"
P = dict(style="plain", metal=(1.0, 0.72, 0.3), metal_rough=0.18, accent=(0.1, 0.6, 0.2),
         accent_glow=0.0, tilt=25, roll=-28, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
TAU = math.tau
RC = 1.0                                           # radius of the band's centre line

def sweep(name, N, M, f):
    """Closed tube: f(theta, phi) -> (dr, dz) around the ring centre line; theta around the ring, phi around the section."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    grid = []
    for a in range(N):
        th = TAU*a/N; c, s = math.cos(th), math.sin(th)
        row = []
        for b in range(M):
            dr, dz = f(th, TAU*b/M)
            row.append(bm.verts.new(((RC+dr)*c, (RC+dr)*s, dz)))
        grid.append(row)
    for a in range(N):
        for b in range(M):
            bm.faces.new((grid[a][b], grid[a][(b+1) % M], grid[(a+1) % N][(b+1) % M], grid[(a+1) % N][b]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = True
    ob = bpy.data.objects.new(name, me); sc.collection.objects.link(ob)
    return ob

def band(name, w, h, e=2.6, N=192, M=48, outer=None):
    """Band with a superellipse section (half-width w radially, half-height h); outer(theta, z) bulges the outside."""
    def f(th, ph):
        c, s = math.cos(ph), math.sin(ph)
        dr = w*math.copysign(abs(c)**(2/e), c); dz = h*math.copysign(abs(s)**(2/e), s)
        if outer and dr > 0: dr += outer(th, dz)*(dr/w)
        return dr, dz
    return sweep(name, N, M, f)

def tube(name, path, r, N=256, M=16):
    """Round wire following path(theta) -> (dr, dz)."""
    def f(th, ph):
        dr, dz = path(th); return dr + r*math.cos(ph), dz + r*math.sin(ph)
    return sweep(name, N, M, f)

def blob(name, th, dr, dz, size, squash=(1, 1, 1)):
    """Small sphere (stud, leaf, bead) on the band at angle th."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=size, segments=24, ring_count=12,
                                         location=((RC+dr)*math.cos(th), (RC+dr)*math.sin(th), dz))
    o = bpy.context.object; o.name = name; o.scale = squash; o.rotation_euler.z = th
    bpy.ops.object.shade_smooth()
    return o

def spike(name, th, dr, dz, h, r):
    """Cone pointing up out of the top edge, leaning outward a little."""
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=r, depth=h,
                                    location=((RC+dr)*math.cos(th), (RC+dr)*math.sin(th), dz + h/2))
    o = bpy.context.object; o.name = name; o.rotation_euler = (0, math.radians(-12), th)
    return o

tri = lambda x: 2*abs(2*((x/TAU) % 1) - 1) - 1    # triangle wave in [-1, 1], period TAU

# ---- styles: lists of metal parts and accent parts (enamel / glowing inlay)
metal, accent = [], []
st = P["style"]
if st == "plain":
    metal.append(band("Band", 0.1, 0.16, e=2.4))
elif st == "twisted":                              # two twisted strands round a thin enamel core
    for k in range(2):
        metal.append(tube(f"Strand{k}", lambda th, k=k: (0.07*math.cos(8*th + k*math.pi), 0.07*math.sin(8*th + k*math.pi)), 0.068))
    accent.append(tube("Core", lambda th: (0, 0), 0.05))
elif st == "vine":                                 # engraved vine with enamel leaves
    metal.append(band("Band", 0.09, 0.2, e=3))
    accent.append(tube("Vine", lambda th: (0.095, 0.09*math.sin(5*th)), 0.022))
    for k in range(10):
        th = TAU*(k + 0.25)/10; z = 0.09*math.sin(5*th)
        accent.append(blob(f"Leaf{k}", th + 0.08, 0.1, z + (0.07 if k % 2 else -0.07), 0.05, (0.45, 1.0, 0.55)))
elif st == "shield":                               # wide flat band, raised rims, enamel centre line
    metal.append(band("Band", 0.08, 0.26, e=5))
    for z in (-0.26, 0.26):
        metal.append(tube(f"Rim{z}", lambda th, z=z: (0.06, z), 0.045))
    accent.append(tube("Line", lambda th: (0.08, 0), 0.03))
elif st == "zigzag":                               # lightning inlay
    metal.append(band("Band", 0.1, 0.2, e=4))
    accent.append(tube("Bolt", lambda th: (0.1, 0.12*tri(7*th)), 0.026, N=512))
elif st == "stacked":                              # three slim bands
    for k, z in enumerate((-0.17, 0.0, 0.17)):
        metal.append(tube(f"Hoop{k}", lambda th, z=z: (0, z), 0.075))
elif st == "studded":                              # heavy band with studs and edge ridges
    metal.append(band("Band", 0.13, 0.24, e=4))
    for z in (-0.2, 0.2):
        metal.append(tube(f"Ridge{z}", lambda th, z=z: (0.12, z), 0.03))
    for k in range(10):
        metal.append(blob(f"Stud{k}", TAU*k/10, 0.13, 0.0, 0.095))
elif st == "waves":                                # two interleaved wave inlays
    metal.append(band("Band", 0.1, 0.2, e=3))
    for k in range(2):
        accent.append(tube(f"Wave{k}", lambda th, k=k: (0.1, 0.1*math.sin(3*th + k*math.pi)), 0.022))
elif st == "spiked":                               # crown of spikes on the top edge, inlay groove
    metal.append(band("Band", 0.1, 0.16, e=3))
    for k in range(12):
        metal.append(spike(f"Spike{k}", TAU*k/12, 0.04, 0.1, 0.34, 0.075))
    accent.append(tube("Groove", lambda th: (0.1, -0.02), 0.025))

m, b = mat("Metal", P["metal"], Metallic=1.0, Roughness=P["metal_rough"])
for o in metal: o.data.materials.append(m)
m, b = mat("Accent", P["accent"], Roughness=0.15, **{"Coat Weight": 0.8})
if P["accent_glow"]:
    b.inputs["Emission Color"].default_value = (*P["accent"], 1); b.inputs["Emission Strength"].default_value = P["accent_glow"]
for o in accent: o.data.materials.append(m)

# ---- pose: ring tilted toward the camera and turned diagonally, like the rolled scroll
pivot = bpy.data.objects.new("Pivot", None); sc.collection.objects.link(pivot)
for o in metal + accent: o.parent = pivot
pivot.rotation_euler = (math.radians(P["tilt"]), math.radians(P["roll"]), 0)
pivot.location = (0, 0, 1.4)

rig(sc)
studio_world(sc, 0.9)                              # polished metal needs something to reflect
spot(sc, (-2.5, -3, 4), 200, (1, 1, 1), size=0.6); spot(sc, (3, -2, 3.5), 140, (1, 0.97, 0.92), size=0.6)
render(sc, OUT, P["save_blend"], samples=192)
