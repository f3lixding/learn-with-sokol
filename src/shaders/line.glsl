@header const m = @import("../math.zig")
@ctype mat4 m.Mat4

@vs vs_shape 
layout(binding=0) uniform shape_vs_params {
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

@fs fs_shape
in vec4 color;
out vec4 frag_color;
void main() {
  frag_color = color;
}
@end

@program shape vs_shape fs_shape
