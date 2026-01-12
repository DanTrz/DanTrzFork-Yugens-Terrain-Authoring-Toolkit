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

group_uniforms Blending;
// 0.0 = smooth gradient blend, 5.0 = sharp (original behavior)
uniform float blend_sharpness : hint_range(0.0, 5.0, 0.1) = 2.5;
uniform float blend_noise_scale : hint_range(0.0, 50.0, 1.0) = 10.0;
uniform float blend_noise_strength : hint_range(0.0, 1.0, 0.05) = 0.0;
group_uniforms;

group_uniforms Vertex_Colors;
uniform sampler2D vc_tex_rr : source_color;
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
uniform sampler2D vc_tex_aa : source_color;
group_uniforms;

group_uniforms Shading;
uniform vec4 shadow_color : source_color;
uniform int bands : hint_range(1, 10) = 5;
uniform float shadow_intensity : hint_range(-1.0, 0.5, 0.05) = 0.00;
group_uniforms;

varying vec3 vertex_normal;
varying vec4 vc_color_0;
varying vec4 vc_color_1;
varying vec4 custom1;
varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec4 sample_material_by_index(int index, vec2 uv) {
	vec4 result;
	switch(index) {
		case 0: result = texture(vc_tex_rr, uv) * ground_albedo; break;
		case 1: result = texture(vc_tex_rg, uv) * ground_albedo_2; break;
		case 2: result = texture(vc_tex_rb, uv) * ground_albedo_3; break;
		case 3: result = texture(vc_tex_ra, uv) * ground_albedo_4; break;
		case 4: result = texture(vc_tex_gr, uv) * ground_albedo_5; break;
		case 5: result = texture(vc_tex_gg, uv) * ground_albedo_6; break;
		case 6: result = texture(vc_tex_gb, uv); break;
		case 7: result = texture(vc_tex_ga, uv); break;
		case 8: result = texture(vc_tex_br, uv); break;
		case 9: result = texture(vc_tex_bg, uv); break;
		case 10: result = texture(vc_tex_bb, uv); break;
		case 11: result = texture(vc_tex_ba, uv); break;
		case 12: result = texture(vc_tex_ar, uv); break;
		case 13: result = texture(vc_tex_ag, uv); break;
		case 14: result = texture(vc_tex_ab, uv); break;
		case 15: result = texture(vc_tex_aa, uv); break;
		default: result = texture(vc_tex_rr, uv) * ground_albedo; break;
	}
	return result;
}

void calculate_blend_weights(vec4 vc0, vec4 vc1, float sharpness, out float weights[16]) {
	for (int i = 0; i < 16; i++) {
		weights[i] = 0.0;
	}

	// Gives proximity to vertices using that material pair
	float raw_weights[16];
	raw_weights[0]  = vc0.r * vc1.r;
	raw_weights[1]  = vc0.r * vc1.g;
	raw_weights[2]  = vc0.r * vc1.b;
	raw_weights[3]  = vc0.r * vc1.a;
	raw_weights[4]  = vc0.g * vc1.r;
	raw_weights[5]  = vc0.g * vc1.g;
	raw_weights[6]  = vc0.g * vc1.b;
	raw_weights[7]  = vc0.g * vc1.a;
	raw_weights[8]  = vc0.b * vc1.r;
	raw_weights[9]  = vc0.b * vc1.g;
	raw_weights[10] = vc0.b * vc1.b;
	raw_weights[11] = vc0.b * vc1.a;
	raw_weights[12] = vc0.a * vc1.r;
	raw_weights[13] = vc0.a * vc1.g;
	raw_weights[14] = vc0.a * vc1.b;
	raw_weights[15] = vc0.a * vc1.a;

	// Power function amplifies weight differences: higher power = sharper transitions
	float power = 1.0 + sharpness * 2.0;
	float total = 0.0;

	for (int i = 0; i < 16; i++) {
		weights[i] = pow(max(raw_weights[i], 0.0), power);
		total += weights[i];
	}

	if (total > 0.001) {
		for (int i = 0; i < 16; i++) {
			weights[i] /= total;
		}
	} else {
		// Fallback when weights collapse (prevents empty triangles at boundaries)
		float max_raw = 0.0;
		int max_idx = 0;
		for (int i = 0; i < 16; i++) {
			if (raw_weights[i] > max_raw) {
				max_raw = raw_weights[i];
				max_idx = i;
			}
		}
		for (int i = 0; i < 16; i++) {
			weights[i] = (i == max_idx) ? 1.0 : 0.0;
		}
	}
}

void vertex() {
	vc_color_0 = COLOR;
	vc_color_1 = CUSTOM0;
	vertex_normal = NORMAL;
	custom1 = CUSTOM1;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 tiling_factor_floor = vec2(1.0 / float(chunk_size.x), 1.0 / float(chunk_size.z));
	vec2 tiling_factor_wall = vec2(1.0 / float(chunk_size.x), 1.0 / float(chunk_size.y));
	float is_ridge = custom1.g;
	bool use_floor = dot(vertex_normal, vec3(0.0, 1.0, 0.0)) > wall_threshold && is_ridge < 0.5;

	if (use_floor) {
		vec2 floor_uv = UV2 * tiling_factor_floor;

		float effective_sharpness = blend_sharpness;
		if (blend_noise_strength > 0.0) {
			float n = noise(world_pos.xz * blend_noise_scale);
			effective_sharpness = mix(blend_sharpness, blend_sharpness * (0.5 + n), blend_noise_strength);
		}

		float weights[16];
		calculate_blend_weights(vc_color_0, vc_color_1, effective_sharpness, weights);

		vec4 final_color = vec4(0.0);
		float total_weight = 0.0;

		for (int i = 0; i < 16; i++) {
			if (weights[i] > 0.01) {
				vec4 mat_color = sample_material_by_index(i, floor_uv);
				final_color += mat_color * weights[i];
				total_weight += weights[i];
			}
		}

		if (total_weight > 0.001) {
			final_color /= total_weight;
		}

		ALBEDO = final_color.rgb;
		ALPHA = final_color.a;
	}
	else {
		vec4 vertex_pos = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
		vec3 abs_normal = abs(vertex_normal);

		vec3 weights_wall = vec3(abs_normal.x, 0.0, abs_normal.z);
		weights_wall /= (weights_wall.x + weights_wall.z);

		vec2 uv_x = vertex_pos.zy;
		vec2 uv_z = vertex_pos.xy;

		vec3 texture_x = texture(wall_texture, uv_x * tiling_factor_wall * 2.0).rgb * weights_wall.x;
		vec3 texture_z = texture(wall_texture, uv_z * tiling_factor_wall * 2.0).rgb * weights_wall.z;

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
