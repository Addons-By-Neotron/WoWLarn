"""Shared bits for the item renders (run inside Blender): materials, camera/light rig, studio world, render."""
import bpy, math
from mathutils import Vector

def link(sc, name, data):
    ob = bpy.data.objects.new(name, data); sc.collection.objects.link(ob); return ob

def mat(name, base, **kw):
    m = bpy.data.materials.new(name)
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*base[:3], 1)
    for k, v in kw.items():
        if k in b.inputs: b.inputs[k].default_value = v
    return m, b

def paper_material(pc, edge_axes="X", ink=None, ink_color=(0.12, 0.05, 0.02), ink_strength=0.85):
    """Aged parchment: large stains, fine fibres (colour + bump), darkened edges.
    edge_axes: UV axes whose 0/1 edges get darkened ("X" for the rolled scroll's ends, "XY" for a sheet).
    ink: optional image path drawn onto UV map "Ink" (clipped outside 0..1)."""
    m, b = mat("Paper", pc, Roughness=0.8)
    nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    st = N("ShaderNodeTexNoise"); st.inputs["Scale"].default_value = 3.5; st.inputs["Detail"].default_value = 6
    sr = N("ShaderNodeValToRGB"); Lk(st.outputs["Fac"], sr.inputs[0])
    sr.color_ramp.elements[0].position = 0.4; sr.color_ramp.elements[1].position = 0.65
    sr.color_ramp.elements[0].color = (*[c*0.62 for c in pc], 1); sr.color_ramp.elements[1].color = (*[min(1, c*1.1) for c in pc], 1)
    fb = N("ShaderNodeTexNoise"); fb.inputs["Scale"].default_value = 60; fb.inputs["Detail"].default_value = 10
    fb.inputs["Roughness"].default_value = 0.7
    fm = N("ShaderNodeMix"); fm.data_type = 'RGBA'; fm.blend_type = 'MULTIPLY'; fm.inputs["Factor"].default_value = 0.35
    Lk(sr.outputs["Color"], fm.inputs["A"]); Lk(fb.outputs["Color"], fm.inputs["B"])
    col = fm.outputs["Result"]
    if ink:
        iu = N("ShaderNodeUVMap"); iu.uv_map = "Ink"
        im = N("ShaderNodeTexImage"); im.image = bpy.data.images.load(ink); im.extension = 'CLIP'
        Lk(iu.outputs["UV"], im.inputs["Vector"])
        ia = N("ShaderNodeMath"); ia.operation = 'MULTIPLY'; ia.inputs[1].default_value = ink_strength
        Lk(im.outputs["Alpha"], ia.inputs[0])
        mi = N("ShaderNodeMix"); mi.data_type = 'RGBA'; mi.inputs["B"].default_value = (*ink_color, 1)
        Lk(ia.outputs[0], mi.inputs["Factor"]); Lk(col, mi.inputs["A"]); col = mi.outputs["Result"]
    # aged edges: darken towards the 0/1 edges of the chosen UV axes
    uvn = N("ShaderNodeUVMap"); uvn.uv_map = "UVMap"; sp = N("ShaderNodeSeparateXYZ"); Lk(uvn.outputs["UV"], sp.inputs[0])
    edge = None
    for axis in edge_axes:
        pp = N("ShaderNodeMath"); pp.operation = 'PINGPONG'; pp.inputs[1].default_value = 0.5
        Lk(sp.outputs[axis], pp.inputs[0])
        if edge is None: edge = pp.outputs[0]
        else:
            mn = N("ShaderNodeMath"); mn.operation = 'MINIMUM'
            Lk(edge, mn.inputs[0]); Lk(pp.outputs[0], mn.inputs[1]); edge = mn.outputs[0]
    er = N("ShaderNodeMapRange"); er.inputs["From Min"].default_value = 0.0; er.inputs["From Max"].default_value = 0.08
    Lk(edge, er.inputs["Value"])
    em = N("ShaderNodeMix"); em.data_type = 'RGBA'
    em.inputs["A"].default_value = (*[c*0.35 for c in pc], 1)
    Lk(er.outputs["Result"], em.inputs["Factor"]); Lk(col, em.inputs["B"])
    Lk(em.outputs["Result"], b.inputs["Base Color"])
    bp = N("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.25; bp.inputs["Distance"].default_value = 0.02
    Lk(fb.outputs["Fac"], bp.inputs["Height"]); Lk(bp.outputs["Normal"], b.inputs["Normal"])
    return m

def rig(sc, tgt=Vector((0, 0, 1.4)), elev=20):
    """Same camera (elev deg from above, default 20) and warm three-light setup as the other item renders."""
    cam = bpy.data.cameras.new("Cam"); cam.type = 'PERSP'; cam.lens = 85
    co = link(sc, "Cam", cam)
    ang = math.radians(elev); dist = 12
    co.location = tgt + Vector((0, -dist*math.cos(ang), dist*math.sin(ang)))
    co.rotation_euler = (math.pi/2 - ang, 0, 0); sc.camera = co
    def area(loc, energy, size, col):
        l = bpy.data.lights.new("L", 'AREA'); l.energy = energy; l.size = size; l.color = col
        o = link(sc, "L", l); o.location = loc
        o.rotation_euler = (tgt - o.location).to_track_quat('-Z', 'Y').to_euler()
    area((-4, -4, 4), 320, 3, (1, 0.95, 0.88))
    area((4, -3, 2), 160, 3, (0.85, 0.85, 1))
    area((0, 3, 3), 250, 4, (1, 0.9, 0.8))
    w = bpy.data.worlds.new("W"); sc.world = w
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.08, 0.07, 0.12, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 0.6

def studio_world(sc, strength=1.2, scale=1.6, distortion=2.0):
    """Bright/dark horizontal bands in the environment, so facets and polished metal reflect something."""
    nt = sc.world.node_tree
    bg = nt.nodes["Background"]; bg.inputs["Strength"].default_value = strength
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexWave"); wave.wave_type = 'BANDS'; wave.bands_direction = 'Z'
    wave.inputs["Scale"].default_value = scale; wave.inputs["Distortion"].default_value = distortion
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.45; ramp.color_ramp.elements[0].color = (0.02, 0.02, 0.03, 1)
    ramp.color_ramp.elements[1].position = 0.6; ramp.color_ramp.elements[1].color = (0.9, 0.9, 0.95, 1)
    nt.links.new(tc.outputs["Generated"], wave.inputs["Vector"]); nt.links.new(wave.outputs["Fac"], ramp.inputs[0])
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])

def spot(sc, loc, energy, col, size=0.25, tgt=Vector((0, 0, 1.4))):
    """Small hard area light aimed at the item: sharp sparkles/highlights."""
    l = bpy.data.lights.new("S", 'AREA'); l.energy = energy; l.size = size; l.color = col
    o = link(sc, "S", l); o.location = loc
    o.rotation_euler = (tgt - o.location).to_track_quat('-Z', 'Y').to_euler()

def use_device(sc):
    """GPU (OptiX/CUDA/HIP) if available, else Cycles' CPU default."""
    cp = bpy.context.preferences.addons['cycles'].preferences
    for t in ('OPTIX', 'CUDA', 'HIP'):
        try:
            cp.compute_device_type = t; cp.get_devices()
        except TypeError:
            continue
        if any(d.type == t for d in cp.devices):
            for d in cp.devices: d.use = d.type == t
            sc.cycles.device = 'GPU'; break

def render(sc, out, save_blend=None, samples=128):
    sc.render.engine = 'CYCLES'; sc.cycles.samples = samples; sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'Standard'
    use_device(sc)
    sc.render.resolution_x = sc.render.resolution_y = 512
    sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGBA'
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    if save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=save_blend)
