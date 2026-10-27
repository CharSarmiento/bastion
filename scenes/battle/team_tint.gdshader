shader_type canvas_item;
// Tiñe el uniforme: cambia los tonos verdes del sprite por otro color.
// Sirve para distinguir al bando enemigo con los mismos sprites del pack.

// Tono nuevo (0-1 en la rueda de color; 0.6 = azul).
uniform float target_hue : hint_range(0.0, 1.0) = 0.6;
uniform float saturation_scale = 0.6;
uniform float value_scale = 0.95;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	// En Godot 4, COLOR ya llega con el color de la textura incluido.
	vec3 hsv = rgb_to_hsv(COLOR.rgb);
	// Peso del cambio: 1 en los verdes y amarillos verdosos, 0 en el resto (piel, mochila...).
	float green = smoothstep(0.11, 0.16, hsv.x) * (1.0 - smoothstep(0.42, 0.48, hsv.x));
	vec3 tinted = hsv_to_rgb(vec3(target_hue, hsv.y * saturation_scale, hsv.z * value_scale));
	COLOR.rgb = mix(COLOR.rgb, tinted, green);
}
