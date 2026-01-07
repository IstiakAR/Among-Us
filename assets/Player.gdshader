shader_type canvas_item;

uniform vec4 tint_color : source_color;

void fragment() {
    vec4 tex = texture(TEXTURE, UV);

    float luminosity = dot(tex.rgb, vec3(1.0, 1.0, 0.7));
    vec3 result = luminosity * vec3(1,1,1);
    // Apply tint color to grayscale result; use tint alpha for overall intensity.
    vec3 colored = result * tint_color.rgb;
    COLOR = vec4(colored, tex.a * tint_color.a);
}
