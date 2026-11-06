"""Build + render the shield (a carried item, floating like the trinkets).  Usage:
blender -b -P build_shield.py -- out.png '{"yaw":25, ...}'
The model is "Medieval Shield" by Artem Mykhailov (CC-BY 4.0, models/medieval_shield, see CREDITS.md), with its
own textures: a round wooden shield, iron rim and boss.
"""
import bpy, math, os, sys, json
from mathutils import Matrix, Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from render_common import rig, render, studio_world, spot

args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
OUT = args[0] if args else "shield.png"
P = dict(size=2.0, yaw=25, tilt=10, flip=False, elev=20, save_blend=False)
if len(args) > 1:
    P.update(json.loads(args[1]))
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
MODEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "models", "medieval_shield")

bpy.ops.import_scene.gltf(filepath=os.path.join(MODEL, "scene.gltf"))
shield = next(o for o in sc.objects if o.type == 'MESH')
bpy.context.view_layer.update()
me = shield.data; me.transform(shield.matrix_world)               # bake the importer's transforms into the mesh
shield.parent = None; shield.matrix_world = Matrix.Identity(4)
for o in [o for o in sc.objects if o.type == 'EMPTY']: bpy.data.objects.remove(o)
lo = Vector([min(v.co[i] for v in me.vertices) for i in range(3)]); hi = Vector([max(v.co[i] for v in me.vertices) for i in range(3)])
k = P["size"]/max(hi.x - lo.x, hi.z - lo.z)        # P["size"] across, centred
me.transform(Matrix.Scale(k, 4) @ Matrix.Translation(-(lo + hi)/2))
root = bpy.data.objects.new("Item", None); sc.collection.objects.link(root); shield.parent = root
root.location = (0, 0, 1.4)                        # where the camera looks (as for build_item.py)
root.rotation_euler = (math.radians(P["tilt"]), 0, math.radians(P["yaw"] + (180 if P["flip"] else 0)))

rig(sc, elev=P["elev"])
studio_world(sc, 0.7)                               # something for the metal to reflect
spot(sc, (-3, -3, 4), 140, (1, 0.95, 0.85)); spot(sc, (3, -2.5, 3), 70, (1, 1, 1))
render(sc, OUT, P["save_blend"], samples=128)
