shader_type canvas_item;

uniform vec4 tint_color : source_color;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    float luminosity = dot(tex.rgb, vec3(1.0, 1.0, 0.7));
    vec3 result = luminosity * vec3(1,1,1);

    COLOR = vec4(result, tex.a);
}
