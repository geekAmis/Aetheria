shader_type spatial;
render_mode blend_mix, cull_disabled, specular_schlick_ggx;

uniform float wave_amp = 0.055;
uniform float wave_speed = 0.85;
varying vec3 wpos;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = sin(wp.x * 0.33 + TIME * wave_speed) * cos(wp.z * 0.27 + TIME * wave_speed * 0.8);
	w += sin((wp.x + wp.z) * 0.11 + TIME * 0.45) * 0.4;
	VERTEX.y += w * wave_amp;
	wpos = wp;
}

void fragment() {
	vec3 col = COLOR.rgb;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = mix(col, vec3(0.78, 0.93, 1.0), fres * 0.38);
	ALPHA = clamp(COLOR.a + fres * 0.10, 0.0, 0.96);
	ROUGHNESS = 0.055;
	METALLIC = 0.18;
	SPECULAR = 0.85;
}
