shader_type canvas_item;

// Wind / Speed lines trail shader
// Creates three horizontal speed lines behind the dashing player:
// - Top line
// - Middle line
// - Bottom line
// All white, 75% maximum opacity, with smooth fade-in at the start (tail)

uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 0.75);
uniform float line_thickness : hint_range(0.01, 0.2) = 0.045;
uniform float line_spacing : hint_range(0.1, 0.4) = 0.25;
uniform float fade_in_length : hint_range(0.0, 1.0) = 0.42;
uniform float fade_out_length : hint_range(0.0, 1.0) = 0.12;
uniform float flow_speed : hint_range(0.0, 50.0) = 14.0;

// Individual horizontal offsets & lengths for the 3 staggered lines:
// Line 1: top, slightly shorter
// Line 2: middle, longest
// Line 3: bottom, medium
uniform vec3 line_offsets = vec3(0.08, 0.0, 0.05);
uniform vec3 line_lengths = vec3(0.88, 1.0, 0.92);

void fragment() {
    // 3 line centers vertically
    float y1 = 0.5 - line_spacing; // Top line (~0.25)
    float y2 = 0.5;                // Middle line (0.50)
    float y3 = 0.5 + line_spacing; // Bottom line (~0.75)

    // Distance from pixel Y to each line center
    float d1 = abs(UV.y - y1);
    float d2 = abs(UV.y - y2);
    float d3 = abs(UV.y - y3);

    // Anti-aliased line mask
    float half_thick = line_thickness * 0.5;
    float m1 = 1.0 - smoothstep(half_thick * 0.5, half_thick, d1);
    float m2 = 1.0 - smoothstep(half_thick * 0.5, half_thick, d2);
    float m3 = 1.0 - smoothstep(half_thick * 0.5, half_thick, d3);

    // Horizontal normalized positions along each line
    // UV.x = 0.0 is the start (tail end, furthest from player)
    // UV.x = 1.0 is near the player
    float x1 = (UV.x - line_offsets.x) / max(line_lengths.x, 0.001);
    float x2 = (UV.x - line_offsets.y) / max(line_lengths.y, 0.001);
    float x3 = (UV.x - line_offsets.z) / max(line_lengths.z, 0.001);

    // Fade-in at the start (tail) and fade-out near the player
    float in1 = smoothstep(0.0, fade_in_length, x1);
    float out1 = 1.0 - smoothstep(1.0 - fade_out_length, 1.0, x1);
    float fade1 = in1 * out1 * step(0.0, x1) * step(x1, 1.0);

    float in2 = smoothstep(0.0, fade_in_length, x2);
    float out2 = 1.0 - smoothstep(1.0 - fade_out_length, 1.0, x2);
    float fade2 = in2 * out2 * step(0.0, x2) * step(x2, 1.0);

    float in3 = smoothstep(0.0, fade_in_length, x3);
    float out3 = 1.0 - smoothstep(1.0 - fade_out_length, 1.0, x3);
    float fade3 = in3 * out3 * step(0.0, x3) * step(x3, 1.0);

    // Subtle wind flow / streaming shimmer
    float wave1 = 0.90 + 0.10 * sin(TIME * flow_speed + UV.x * 10.0);
    float wave2 = 0.90 + 0.10 * sin(TIME * flow_speed + UV.x * 10.0 + 1.2);
    float wave3 = 0.90 + 0.10 * sin(TIME * flow_speed + UV.x * 10.0 + 2.4);

    float alpha1 = m1 * fade1 * wave1;
    float alpha2 = m2 * fade2 * wave2;
    float alpha3 = m3 * fade3 * wave3;

    float combined_alpha = clamp(alpha1 + alpha2 + alpha3, 0.0, 1.0) * line_color.a;

    COLOR = vec4(line_color.rgb, combined_alpha);
}
