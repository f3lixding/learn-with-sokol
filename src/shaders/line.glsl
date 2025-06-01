@header const m = @import("../math.zig")
@ctype mat4 m.Mat4

@vs vs_shape 
layout(binding=0) uniform shape_vs_params {
  mat4 mvp;
};

in vec4 position;
void main() {
  gl_Position = mvp * position;
}
@end

@fs fs_shape
out vec4 frag_color;
void main() {
  frag_color = vec4(1.0, 1.0, 1.0, 1.0);
}
@end

@program shape vs_shape fs_shape
