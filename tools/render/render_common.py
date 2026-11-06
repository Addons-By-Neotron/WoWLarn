"""Shared bits for the item renders (run inside Blender): materials, camera/light rig, studio world, render."""
import bpy, math, os
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

TEXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "textures")

def rock_material(name, tint, scale=0.6, fade=None):
    """Weathered stone: Poly Haven rock_face_03 (CC0) colour/roughness/normal maps, box-projected in object space
    (no UVs needed); each object gets a random offset into the texture so neighbouring blocks don't match up.
    The brown photo is greyed down, then multiplied by tint.  fade=(z0, z1): object Z from z0 to z1 fades to black
    (a shaft going down into the dark).  Returns the material and its tint node (copy the material and change the
    node's "B" input for a darker/lighter variant)."""
    m, b = mat(name, (1, 1, 1))
    nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord"); oi = N("ShaderNodeObjectInfo")
    jit = N("ShaderNodeVectorMath"); jit.operation = 'MULTIPLY_ADD'; jit.inputs[1].default_value = (7.3, 5.1, 3.7)
    Lk(oi.outputs["Random"], jit.inputs[0]); Lk(tc.outputs["Object"], jit.inputs[2])
    mp = N("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (scale,)*3; Lk(jit.outputs["Vector"], mp.inputs["Vector"])
    def tex(kind, colour=True):
        t = N("ShaderNodeTexImage"); t.image = bpy.data.images.load(os.path.join(TEXTURES, f"rock_face_03_{kind}_2k.jpg"))
        if not colour: t.image.colorspace_settings.name = "Non-Color"
        t.projection = 'BOX'; t.projection_blend = 0.25; Lk(mp.outputs["Vector"], t.inputs["Vector"])
        return t
    hs = N("ShaderNodeHueSaturation"); hs.inputs["Saturation"].default_value = 0.3
    Lk(tex("diff").outputs["Color"], hs.inputs["Color"])
    tn = N("ShaderNodeMix"); tn.data_type = 'RGBA'; tn.blend_type = 'MULTIPLY'; tn.inputs["Factor"].default_value = 1.0
    tn.inputs["B"].default_value = (*tint, 1); Lk(hs.outputs["Color"], tn.inputs["A"]); Lk(tn.outputs["Result"], b.inputs["Base Color"])
    rr = N("ShaderNodeMapRange"); rr.inputs["To Min"].default_value = 0.7; rr.inputs["To Max"].default_value = 1.0
    Lk(tex("rough", False).outputs["Color"], rr.inputs["Value"]); Lk(rr.outputs["Result"], b.inputs["Roughness"])
    nm = N("ShaderNodeNormalMap"); nm.inputs["Strength"].default_value = 1.0
    Lk(tex("nor_gl", False).outputs["Color"], nm.inputs["Color"]); Lk(nm.outputs["Normal"], b.inputs["Normal"])
    if fade:
        sz = N("ShaderNodeSeparateXYZ"); Lk(tc.outputs["Object"], sz.inputs[0])
        dk = N("ShaderNodeMapRange"); dk.inputs["From Min"].default_value, dk.inputs["From Max"].default_value = fade
        Lk(sz.outputs["Z"], dk.inputs["Value"])
        ms = N("ShaderNodeMixShader"); em = N("ShaderNodeEmission"); em.inputs["Color"].default_value = (0, 0, 0, 1)
        Lk(dk.outputs["Result"], ms.inputs[0]); Lk(b.outputs[0], ms.inputs[1]); Lk(em.outputs[0], ms.inputs[2])
        Lk(ms.outputs[0], nt.nodes["Material Output"].inputs["Surface"])
    return m, tn

def wood_material(name, base, axis="X", roughness=0.8):
    """Wood: long noise streaks of grain along axis ("X", "Y" or "Z") in object space, darker and lighter than base,
    with a matching bump; each object gets a random offset so neighbouring planks differ."""
    m, b = mat(name, base, Roughness=roughness)
    nt = m.node_tree; N = nt.nodes.new; Lk = nt.links.new
    tc = N("ShaderNodeTexCoord"); oi = N("ShaderNodeObjectInfo")
    jit = N("ShaderNodeVectorMath"); jit.operation = 'MULTIPLY_ADD'; jit.inputs[1].default_value = (3.1, 7.7, 5.3)
    Lk(oi.outputs["Random"], jit.inputs[0]); Lk(tc.outputs["Object"], jit.inputs[2])
    sq = N("ShaderNodeMapping"); sq.inputs["Scale"].default_value = {"X": (1, 14, 14), "Y": (14, 1, 14), "Z": (14, 14, 1)}[axis]
    Lk(jit.outputs["Vector"], sq.inputs["Vector"])
    grain = N("ShaderNodeTexNoise"); grain.inputs["Scale"].default_value = 3; grain.inputs["Detail"].default_value = 8
    grain.inputs["Distortion"].default_value = 0.6; Lk(sq.outputs["Vector"], grain.inputs["Vector"])
    wr = N("ShaderNodeValToRGB"); Lk(grain.outputs["Fac"], wr.inputs[0])
    wr.color_ramp.elements[0].position = 0.3; wr.color_ramp.elements[1].position = 0.75
    wr.color_ramp.elements[0].color = (*[c*0.45 for c in base], 1); wr.color_ramp.elements[1].color = (*[c*1.4 for c in base], 1)
    Lk(wr.outputs["Color"], b.inputs["Base Color"])
    bp = N("ShaderNodeBump"); bp.inputs["Strength"].default_value = 0.4; bp.inputs["Distance"].default_value = 0.01
    Lk(grain.outputs["Fac"], bp.inputs["Height"]); Lk(bp.outputs["Normal"], b.inputs["Normal"])
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

def render(sc, out, save_blend=None, samples=128, res=512):
    sc.render.engine = 'CYCLES'; sc.cycles.samples = samples; sc.cycles.use_denoising = True
    sc.render.film_transparent = True
    sc.view_settings.view_transform = 'Standard'
    use_device(sc)
    sc.render.resolution_x = sc.render.resolution_y = res
    sc.render.image_settings.file_format = 'PNG'; sc.render.image_settings.color_mode = 'RGBA'
    sc.render.filepath = out
    bpy.ops.render.render(write_still=True)
    if save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=save_blend)
