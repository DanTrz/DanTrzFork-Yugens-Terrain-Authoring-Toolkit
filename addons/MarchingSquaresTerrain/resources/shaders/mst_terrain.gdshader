shader_type spatial;
render_mode diffuse_toon, depth_prepass_alpha;

group_uniforms Albedo;
uniform float wall_threshold : hint_range(0.0, 0.5) = 0.0;
uniform ivec3 chunk_size = ivec3(33, 32, 33);
uniform vec4 ground_albedo : source_color = vec4(0.392, 0.471, 0.318, 1.0);
uniform vec4 ground_albedo_2 : source_color = vec4(0.322, 0.482, 0.384, 1.0);
uniform vec4 ground_albedo_3 : source_color = vec4(0.373, 0.424, 0.294, 1.0);
uniform vec4 ground_albedo_4 : source_color = vec4(0.392, 0.475, 0.255, 1.0);
uniform vec4 ground_albedo_5 : source_color = vec4(0.29, 0.494, 0.365, 1.0);
uniform vec4 ground_albedo_6 : source_color = vec4(0.443, 0.447, 0.365, 1.0);
uniform vec4 wall_albedo : source_color = vec4(0.369, 0.337, 0.271, 1.0);
uniform sampler2D wall_texture : source_color, repeat_enable;
group_uniforms;

group_uniforms Vertex_Colors;
uniform sampler2D vc_tex_rr : source_color; // Standard floor texture
uniform sampler2D vc_tex_rg : source_color;
uniform sampler2D vc_tex_rb : source_color;
uniform sampler2D vc_tex_ra : source_color;
uniform sampler2D vc_tex_gr : source_color;
uniform sampler2D vc_tex_gg : source_color;
uniform sampler2D vc_tex_gb : source_color;
uniform sampler2D vc_tex_ga : source_color;
uniform sampler2D vc_tex_br : source_color;
uniform sampler2D vc_tex_bg : source_color;
uniform sampler2D vc_tex_bb : source_color;
uniform sampler2D vc_tex_ba : source_color;
uniform sampler2D vc_tex_ar : source_color;
uniform sampler2D vc_tex_ag : source_color;
uniform sampler2D vc_tex_ab : source_color;
uniform sampler2D vc_tex_aa : source_color; // Void texture
group_uniforms;

group_uniforms Shading;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.00;
group_uniforms;

varying vec3 vertex_normal;
varying flat int material_index;
varying vec4 custom1;

int get_material_index(vec4 vc_col_0, vec4 vc_col_1) {
	int index = 0;
	if (vc_col_0.r > 0.1) {
		if (vc_col_1.r > 0.1)
			index = 0;
		else if (vc_col_1.g > 0.1)
			index = 1;
		else if (vc_col_1.b > 0.1)
			index = 2;
		else if (vc_col_1.a > 0.1)
			index = 3;
	}
	else if (vc_col_0.g > 0.1) {
		if (vc_col_1.r > 0.1)
			index = 4;
		else if (vc_col_1.g > 0.1)
			index = 5;
		else if (vc_col_1.b > 0.1)
			index = 6;
		else if (vc_col_1.a > 0.1)
			index = 7;
	}
	else if (vc_col_0.b > 0.1) {
		if (vc_col_1.r > 0.1)
			index = 8;
		else if (vc_col_1.g > 0.1)
			index = 9;
		else if (vc_col_1.b > 0.1)
			index = 10;
		else if (vc_col_1.a > 0.1)
			index = 11;
	}
	else if (vc_col_0.a > 0.1) {
		if (vc_col_1.r > 0.1)
			index = 12;
		else if (vc_col_1.g > 0.1)
			index = 13;
		else if (vc_col_1.b > 0.1)
			index = 14;
		else if (vc_col_1.a > 0.1)
			index = 15;
	}
	return index;
}

vec4 get_material(vec2 uv) {
	// Define materials
	vec4 rr_material = texture(vc_tex_rr, uv); // Standard floor texture
	rr_material *= ground_albedo;
	vec4 rg_material = texture(vc_tex_rg, uv);
	rg_material *= ground_albedo_2;
	vec4 rb_material = texture(vc_tex_rb, uv);
	rb_material *= ground_albedo_3;
	vec4 ra_material = texture(vc_tex_ra, uv);
	ra_material *= ground_albedo_4;

	vec4 gr_material = texture(vc_tex_gr, uv);
	gr_material *= ground_albedo_5;
	vec4 gg_material = texture(vc_tex_gg, uv);
	gg_material *= ground_albedo_6;
	vec4 gb_material = texture(vc_tex_gb, uv);
	vec4 ga_material = texture(vc_tex_ga, uv);

	vec4 br_material = texture(vc_tex_br, uv);
	vec4 bg_material = texture(vc_tex_bg, uv);
	vec4 bb_material = texture(vc_tex_bb, uv);
	vec4 ba_material = texture(vc_tex_ba, uv);

	vec4 ar_material = texture(vc_tex_ar, uv);
	vec4 ag_material = texture(vc_tex_ag, uv);
	vec4 ab_material = texture(vc_tex_ab, uv);
	vec4 aa_material = texture(vc_tex_aa, uv);

	// Get materials from an array to skip 15 if else statements
	vec4 materials[16] = vec4[16](
		rr_material, rg_material, rb_material, ra_material,
		gr_material, gg_material, gb_material, ga_material,
		br_material, bg_material, bb_material, ba_material,
		ar_material, ag_material, ab_material, aa_material
	);
	return materials[material_index];
}

void vertex() {
	material_index = get_material_index(COLOR, CUSTOM0);
	vertex_normal = NORMAL;
	custom1 = CUSTOM1;
}

void fragment() {
	vec2 tiling_factor_floor = vec2(1.0 / float(chunk_size.x), 1.0 / float(chunk_size.z));
	vec2 tiling_factor_wall = vec2(1.0 / float(chunk_size.x), 1.0 / float(chunk_size.y));
	float is_ridge = custom1.g;
	bool use_floor = dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > wall_threshold && is_ridge < 0.5;
	if (use_floor) {
		vec4 current_texture = get_material(UV2 * tiling_factor_floor);
		ALBEDO = current_texture.rgb;
		ALPHA = current_texture.a;
	}
	else {
		vec4 vertex_pos = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
		vec3 abs_normal = abs(vertex_normal);

		vec3 weights = vec3(abs_normal.x, 0.0, abs_normal.z);
		weights /= (weights.x + weights.z);

		vec2 uv_x = vertex_pos.zy;
		vec2 uv_z = vertex_pos.xy;

		vec3 texture_x = texture(wall_texture, uv_x * tiling_factor_wall * 2.0).rgb * weights.x;
		vec3 texture_z = texture(wall_texture, uv_z * tiling_factor_wall * 2.0).rgb * weights.z;

		ALBEDO = wall_albedo.rgb * (texture_x + texture_z);
	}
}

void light() {
	float NdotL = dot(NORMAL, LIGHT);
	NdotL = clamp(NdotL, 0.0, 1.0);

	float stepped = ceil(NdotL * float(bands)) / float(bands);
	float toon_light = mix(shadow_intensity, 0.3, stepped);

	toon_light *= ATTENUATION;

	vec3 light_color = mix(shadow_color.rgb, LIGHT_COLOR.rgb, toon_light);

	DIFFUSE_LIGHT += light_color;
}