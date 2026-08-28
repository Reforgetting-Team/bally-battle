shader_type canvas_item;

uniform vec4 skin_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec4 tex = texture(TEXTURE, UV);
    float luminance = dot(tex.rgb, vec3(0.299, 0.587, 0.114));
    vec3 tinted = skin_color.rgb * luminance;
    COLOR = vec4(tinted, tex.a);
}