@vs vs_shape 
in vec2 position;
void main() {
  gl_Position = vec4(position, 0.5, 1.0);
}
@end

@fs fs_shape
out vec4 frag_color;
void main() {
  frag_color = vec4(1.0, 1.0, 1.0, 1.0);
}
@end

@program shape vs_shape fs_shape
