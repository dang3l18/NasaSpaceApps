shader_type canvas_item;
// Proyecta una imagen equirectangular real (NASA GIBS) sobre una esfera con iluminacion y atmosfera.

uniform sampler2D earth : filter_linear, repeat_enable;
uniform float rot = 0.0;
uniform bool has_tex = false;
uniform float atmo = 1.0;   // 1 = halo azul de atmosfera (Tierra); 0 = sin atmosfera (Luna)
uniform float gain = 1.0;   // brillo extra (la Luna real es oscura)
uniform vec4 fallback : source_color = vec4(0.08, 0.16, 0.32, 1.0);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r2 = dot(p, p);
	if (r2 > 1.0) {
		COLOR = vec4(0.0);
	} else {
		float z = sqrt(1.0 - r2);
		float lon = atan(p.x, z) + rot;
		float lat = asin(-p.y);
		vec2 uv = vec2(lon / 6.2831853 + 0.5, 0.5 - lat / 3.1415926);
		vec4 c = has_tex ? texture(earth, uv) : fallback;
		vec3 n = normalize(vec3(p, z));
		float light = clamp(0.30 + 0.85 * dot(n, normalize(vec3(-0.55, -0.45, 0.7))), 0.0, 1.0);
		c.rgb *= light * gain;
		float rim = pow(1.0 - z, 3.0);
		c.rgb += vec3(0.25, 0.55, 1.0) * rim * 0.9 * atmo;
		COLOR = vec4(c.rgb, 1.0);
	}
}
