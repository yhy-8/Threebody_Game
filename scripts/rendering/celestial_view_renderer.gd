class_name CelestialViewRenderer
extends Node3D
## Shared 3D celestial-body renderer used by the orbital and local-horizon views.

const FRAME_WORLD := "world"
const FRAME_LOCAL_HORIZON := "local_horizon"
const PlanetZoneManagerScript = preload("res://scripts/simulation/planet_zones.gd")

const STAR_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 base_color : source_color = vec4(1.0);
varying vec3 object_position;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(cell), hash3(cell + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash3(cell + vec3(0.0, 1.0, 0.0)), hash3(cell + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(cell + vec3(0.0, 0.0, 1.0)), hash3(cell + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash3(cell + vec3(0.0, 1.0, 1.0)), hash3(cell + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += noise3(p) * amplitude;
		p = p * 2.03 + vec3(7.1, 3.4, 5.8);
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	object_position = VERTEX;
}

void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 surface_point = normalize(object_position);
	float convection = fbm(surface_point * 5.5 + vec3(TIME * 0.055, -TIME * 0.035, TIME * 0.025));
	float filaments = smoothstep(0.48, 0.82, convection);
	float limb = 0.32 + 0.68 * pow(facing, 0.38);
	vec3 hot_color = mix(base_color.rgb * 0.72, min(vec3(1.0), base_color.rgb * 1.32 + vec3(0.16)), filaments);
	ALBEDO = hot_color * limb;
	EMISSION = hot_color * limb * (2.2 + filaments * 2.8);
	ALPHA = base_color.a;
}
"""

const STAR_HALO_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_add;
uniform vec4 halo_color : source_color = vec4(1.0, 0.7, 0.3, 0.34);
void fragment() {
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float soft_disc = pow(facing, 2.8);
	float pulse = 0.94 + 0.06 * sin(TIME * 1.7);
	ALBEDO = halo_color.rgb;
	EMISSION = halo_color.rgb * 2.4;
	ALPHA = halo_color.a * soft_disc * pulse;
}
"""

const PLANET_SHADER_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 ocean_color : source_color = vec4(0.018, 0.10, 0.25, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.04, 0.28, 0.42, 1.0);
uniform vec4 land_color : source_color = vec4(0.18, 0.36, 0.24, 1.0);
uniform vec4 highland_color : source_color = vec4(0.48, 0.43, 0.28, 1.0);
uniform vec4 atmosphere_color : source_color = vec4(0.12, 0.48, 1.0, 1.0);
varying vec3 object_position;

float hash3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3(cell), hash3(cell + vec3(1.0, 0.0, 0.0)), f.x),
			mix(hash3(cell + vec3(0.0, 1.0, 0.0)), hash3(cell + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(hash3(cell + vec3(0.0, 0.0, 1.0)), hash3(cell + vec3(1.0, 0.0, 1.0)), f.x),
			mix(hash3(cell + vec3(0.0, 1.0, 1.0)), hash3(cell + vec3(1.0, 1.0, 1.0)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 5; i++) {
		value += noise3(p) * amplitude;
		p = p * 2.08 + vec3(5.2, 1.3, 7.7);
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	object_position = VERTEX;
}

void fragment() {
	vec3 sphere_point = normalize(object_position);
	float continents = fbm(sphere_point * 3.2 + vec3(2.4, 7.1, 1.3));
	float detail = fbm(sphere_point * 11.0 + vec3(8.2, 0.7, 4.5));
	float land_mask = smoothstep(0.51, 0.58, continents + (detail - 0.5) * 0.16);
	float highlands = smoothstep(0.61, 0.78, continents + detail * 0.12);
	vec3 water = mix(ocean_color.rgb, shallow_color.rgb, smoothstep(0.45, 0.54, continents));
	vec3 terrain = mix(land_color.rgb, highland_color.rgb, highlands);
	ALBEDO = mix(water, terrain, land_mask);
	ROUGHNESS = mix(0.2, 0.88, land_mask);
	SPECULAR = mix(0.78, 0.22, land_mask);
	float clouds = smoothstep(0.68, 0.79, fbm(sphere_point * 7.0 + vec3(TIME * 0.006, 3.0, 0.0)));
	ALBEDO = mix(ALBEDO, vec3(0.82, 0.88, 0.94), clouds * 0.36);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.2);
	EMISSION = atmosphere_color.rgb * rim * 0.72 + vec3(0.12) * clouds * 0.06;
}
"""

var _profile: Dictionary = {
	"position_scale": 1.0,
	"radius_scale": 1.0,
	"fixed_radius": 0.0,
	"include_planet": true,
	"planet_grid": false,
	"stellar_lights": true,
}
var _coordinate_frame: String = FRAME_WORLD
var _horizon_mask_enabled: bool = false
var _body_nodes: Array[MeshInstance3D] = []


func configure(p_profile: Dictionary) -> void:
	for key in p_profile:
		_profile[key] = p_profile[key]


func rebuild_bodies(p_snapshot) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_body_nodes.clear()

	for body_value in _extract_bodies(p_snapshot):
		var body: Dictionary = body_value
		if body.get("is_planet", false) and not bool(_profile.get("include_planet", true)):
			continue
		var source_index := int(body.get("source_index", _body_nodes.size()))
		var mesh_instance := _create_body(body, source_index)
		add_child(mesh_instance)
		_body_nodes.append(mesh_instance)
	update_bodies(p_snapshot)


func update_bodies(p_snapshot) -> void:
	var render_bodies: Array = []
	for body_value in _extract_bodies(p_snapshot):
		var body: Dictionary = body_value
		if body.get("is_planet", false) and not bool(_profile.get("include_planet", true)):
			continue
		render_bodies.append(body)
	if render_bodies.size() != _body_nodes.size():
		rebuild_bodies(render_bodies)
		return

	var position_scale := float(_profile.get("position_scale", 1.0))
	for index in range(render_bodies.size()):
		var body: Dictionary = render_bodies[index]
		var body_node := _body_nodes[index]
		var body_position := to_vector3(body.get("position", Vector3.ZERO)) * position_scale
		body_node.position = body_position
		var base_radius := float(body_node.get_meta("base_render_radius", 1.0))
		var desired_radius := _body_radius(body)
		body_node.scale = Vector3.ONE * desired_radius / maxf(base_radius, 0.001)
		body_node.visible = not (_horizon_mask_enabled and _coordinate_frame == FRAME_LOCAL_HORIZON and body_position.y <= 0.0)


func set_coordinate_frame(p_frame: String) -> void:
	_coordinate_frame = p_frame


func set_horizon_mask(p_enabled: bool) -> void:
	_horizon_mask_enabled = p_enabled


func get_body_nodes() -> Array[MeshInstance3D]:
	return _body_nodes


func _extract_bodies(p_snapshot) -> Array:
	if p_snapshot is Array:
		return p_snapshot
	if p_snapshot is Dictionary:
		if p_snapshot.has("environment"):
			return p_snapshot.get("environment", {}).get("stars", [])
		return p_snapshot.get("stars", [])
	return []


func _create_body(p_body: Dictionary, p_source_index: int) -> MeshInstance3D:
	var is_planet := bool(p_body.get("is_planet", false))
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Planet" if is_planet else "Star%d" % p_source_index
	var radius := _body_radius(p_body)
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	mesh_instance.mesh = sphere

	var color := to_color(p_body.get("color", Color.WHITE))
	if is_planet:
		var planet_shader := Shader.new()
		planet_shader.code = PLANET_SHADER_CODE
		var planet_material := ShaderMaterial.new()
		planet_material.shader = planet_shader
		mesh_instance.material_override = planet_material
		if bool(_profile.get("planet_grid", false)):
			mesh_instance.add_child(create_planet_grid(radius * 1.015))
	else:
		var star_shader := Shader.new()
		star_shader.code = STAR_SHADER_CODE
		var star_material := ShaderMaterial.new()
		star_material.shader = star_shader
		star_material.set_shader_parameter("base_color", color)
		mesh_instance.material_override = star_material
		_add_star_halo(mesh_instance, radius, color)
		if bool(_profile.get("stellar_lights", true)):
			_add_stellar_light(mesh_instance, color)
	mesh_instance.set_meta("is_planet", is_planet)
	mesh_instance.set_meta("star_index", p_source_index)
	mesh_instance.set_meta("source_color", color)
	mesh_instance.set_meta("base_render_radius", radius)
	return mesh_instance


func _body_radius(p_body: Dictionary) -> float:
	if p_body.has("render_radius"):
		return maxf(0.001, float(p_body["render_radius"]))
	var radius := float(_profile.get("fixed_radius", 0.0))
	if radius <= 0.0:
		radius = float(p_body.get("radius", 20.0)) * float(_profile.get("radius_scale", 1.0))
	return maxf(0.001, radius)


func _add_star_halo(p_star_mesh: MeshInstance3D, p_radius: float, p_color: Color) -> void:
	var halo := MeshInstance3D.new()
	halo.name = "Corona"
	var halo_sphere := SphereMesh.new()
	halo_sphere.radius = p_radius * 1.62
	halo_sphere.height = p_radius * 3.24
	halo_sphere.radial_segments = 40
	halo_sphere.rings = 20
	halo.mesh = halo_sphere
	var halo_shader := Shader.new()
	halo_shader.code = STAR_HALO_SHADER_CODE
	var halo_material := ShaderMaterial.new()
	halo_material.shader = halo_shader
	halo_material.set_shader_parameter("halo_color", Color(p_color, 0.34))
	halo.material_override = halo_material
	p_star_mesh.add_child(halo)


func _add_stellar_light(p_star_mesh: MeshInstance3D, p_color: Color) -> void:
	var light := OmniLight3D.new()
	light.name = "StellarLight"
	light.light_color = p_color.lerp(Color.WHITE, 0.28)
	light.light_energy = 4.8
	light.omni_range = 1800.0
	light.omni_attenuation = 0.72
	light.shadow_enabled = false
	p_star_mesh.add_child(light)


static func create_planet_grid(p_radius: float) -> MeshInstance3D:
	var grid := MeshInstance3D.new()
	grid.name = "PlanetGrid"
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.26, 0.62, 1.0, 0.42)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	for latitude_index in range(1, PlanetZoneManagerScript.LATITUDE_DIVISIONS):
		var latitude := deg_to_rad(-90.0 + latitude_index * 180.0 / PlanetZoneManagerScript.LATITUDE_DIVISIONS)
		immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
		for segment in range(49):
			var longitude := TAU * float(segment) / 48.0
			immediate.surface_add_vertex(Vector3(
				p_radius * cos(latitude) * cos(longitude),
				p_radius * sin(latitude),
				p_radius * cos(latitude) * sin(longitude)
			))
		immediate.surface_end()
	for longitude_index in range(PlanetZoneManagerScript.LONGITUDE_DIVISIONS):
		var longitude := TAU * float(longitude_index) / PlanetZoneManagerScript.LONGITUDE_DIVISIONS
		immediate.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
		for segment in range(25):
			var latitude := -PI * 0.5 + PI * float(segment) / 24.0
			immediate.surface_add_vertex(Vector3(
				p_radius * cos(latitude) * cos(longitude),
				p_radius * sin(latitude),
				p_radius * cos(latitude) * sin(longitude)
			))
		immediate.surface_end()
	grid.mesh = immediate
	return grid


static func to_vector3(p_value) -> Vector3:
	if p_value is Vector3:
		return p_value
	if p_value is Dictionary:
		return Vector3(p_value.get("x", 0.0), p_value.get("y", 0.0), p_value.get("z", 0.0))
	return Vector3.ZERO


static func to_color(p_value) -> Color:
	if p_value is Color:
		return p_value
	if p_value is Dictionary:
		return Color(
			p_value.get("r", 1.0), p_value.get("g", 1.0),
			p_value.get("b", 1.0), p_value.get("a", 1.0)
		)
	return Color.WHITE
