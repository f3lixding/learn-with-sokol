@vs vs

in vec2 pos;
in vec4 color0;
in vec2 uv0;

out vec4 color;
out vec2 uv;

void main() {
  // Note that this is x, y, z, w
  // w should be 1.0 for proper 2D rendering
  gl_Position = vec4(pos, 0.0, 1.0);
  color = color0;
  uv = vec2(uv0.x, 1.0 - uv0.y);
}
@end

@fs fs
layout(binding=0) uniform texture2D tex;
layout(binding=0) uniform sampler smp;

in vec4 color;
in vec2 uv;
out vec4 frag_color;

void main() {
  frag_color = texture(sampler2D(tex, smp), uv) * color;
}
@end

@program spritetwo vs fs
