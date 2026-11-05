shader_type sky;

uniform vec3 sky_top : source_color = vec3(0.22, 0.45, 0.78);
uniform vec3 sky_horizon : source_color = vec3(0.72, 0.85, 0.92);
uniform vec3 ground_color : source_color = vec3(0.18, 0.22, 0.18);
uniform vec3 sun_color : source_color = vec3(1.0, 0.92, 0.75);
uniform vec3 sun_dir = vec3(0.4, 0.5, 0.3);
uniform float sun_energy = 1.0;
uniform float star_amount = 0.0;
uniform float cloud_amount = 0.0;
uniform vec3 cloud_color : source_color = vec3(1.0);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = mix(mix(mix(hash(i + vec3(0,0,0)), hash(i + vec3(1,0,0)), f.x),
	                  mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x), f.y),
	              mix(mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x),
	                  mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x), f.y), f.z);
	return n;
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise3(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = EYEDIR;
	float y = dir.y;
	vec3 col = mix(sky_horizon, sky_top, smoothstep(-0.04, 0.55, y));
	// мягкое свечение у горизонта
	col += sky_horizon * 0.10 * smoothstep(0.3, 0.0, abs(y - 0.02));
	if (y < 0.0) {
		col = mix(sky_horizon, ground_color, smoothstep(0.0, -0.45, y));
	}
	// солнце
	float sd = max(dot(dir, normalize(sun_dir)), 0.0);
	col += sun_color * pow(sd, 900.0) * 8.0 * sun_energy;
	col += sun_color * pow(sd, 12.0) * 0.14 * sun_energy;
	col += sun_color * pow(sd, 3.0) * 0.04 * sun_energy;
	// звёзды
	if (y > 0.0 && star_amount > 0.01) {
		vec3 sp = dir * 380.0;
		float h = hash(floor(sp));
		float s = smoothstep(0.995, 0.9995, h) * star_amount * smoothstep(0.0, 0.2, y);
		float tw = 0.65 + 0.35 * sin(TIME * 1.8 + h * 80.0);
		col += vec3(0.85, 0.9, 1.0) * s * tw * 1.6;
	}
	// высокие облака
	if (cloud_amount > 0.01 && y > 0.0) {
		vec3 cp = dir / max(y, 0.08);
		float c = fbm(cp * vec3(1.1, 2.2, 1.1) + vec3(TIME * 0.006, 0.0, TIME * 0.003));
		c = smoothstep(0.52, 0.78, c) * cloud_amount * smoothstep(0.0, 0.25, y);
		col = mix(col, cloud_color, c * 0.55);
	}
	COLOR = col;
}
