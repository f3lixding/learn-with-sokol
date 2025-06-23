@header const m = @import("../math.zig")
@ctype mat4 m.Mat4

@vs vs_grid
in vec4 position;
out vec2 uv;

void main() {
  gl_Position = position;
  uv = position.xy * 0.5 + 0.5;
}
@end

@fs fs_grid
in vec2 uv;
out vec4 frag_color;

void main() {
  // Map UV to grid coordinates (0 to 4)
  vec2 grid_coord = uv * 5.0;
  
  // Get fractional part for each cell (0 to 1 within each cell)
  vec2 cell_uv = fract(grid_coord);
  
  // Distance from cell edges (0 at edges, 0.5 at center)
  vec2 dist_from_edge = min(cell_uv, 1.0 - cell_uv);
  
  // Create grid lines
  float line = smoothstep(0.0, 0.02, min(dist_from_edge.x, dist_from_edge.y));
  
  vec3 color = mix(vec3(0.2), vec3(0.8), line);
  frag_color = vec4(color, 1.0);
}
@end

@vs vs_cube
layout(binding=0) uniform cube_vs_params {
  mat4 mvp;
};

in vec4 position;
in vec4 color0;

out vec4 color;

void main() {
  gl_Position = mvp * position;
  color = color0;
}
@end

@fs fs_cube
in vec4 color;
out vec4 frag_color;

void main() {
  frag_color = color;
}
@end

@program grid vs_grid fs_grid
@program cube vs_cube fs_cube
