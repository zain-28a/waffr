// Liquid glass lens: bends the backdrop near the rounded edge of a glass
// shape. Used as an ImageFilter.shader on a BackdropFilter (Impeller only).
//
// The displacement comes from the shape itself: the rounded-rect signed
// distance gives how far a pixel sits in from the outline, a convex squircle
// bezel profile gives the surface slope there, and Snell's law turns the
// slope into a sideways shift. The flat middle of the glass is untouched.

#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// Set by the engine: size of the backdrop texture, in its own pixels.
uniform vec2 u_size;
// Glass rectangle in backdrop pixels: left, top, width, height.
uniform vec4 u_rect;
// Corner radius, bezel width and maximum shift, in backdrop pixels.
uniform float u_radius;
uniform float u_bezel;
uniform float u_scale;
// Red/blue split as a share of the shift.
uniform float u_chroma;
// Set by the engine: the backdrop.
uniform sampler2D u_texture;

out vec4 fragColor;

// Convex squircle bezel: height at x (0 = outline, 1 = flat top).
float profile(float x) {
  return pow(1.0 - pow(1.0 - x, 4.0), 0.25);
}

// Sideways shift of a vertical ray entering the bezel at x, about 1 at the
// outline and 0 where the bezel meets the flat top.
float magnitude(float x) {
  x = clamp(x, 0.01, 0.99);
  float slope = (profile(x + 0.01) - profile(x - 0.01)) / 0.02;
  float incoming = atan(slope);
  float refracted = asin(sin(incoming) / 1.5);
  return clamp(tan(incoming - refracted) * (0.35 + profile(x)) / 0.75, 0.0, 1.0);
}

vec4 backdrop(vec2 pixel) {
  vec2 uv = pixel / u_size;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(u_texture, clamp(uv, vec2(0.0), vec2(1.0)));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 halfSize = u_rect.zw * 0.5;
  vec2 p = frag - (u_rect.xy + halfSize);
  float radius = min(u_radius, min(halfSize.x, halfSize.y));
  vec2 q = abs(p) - (halfSize - radius);
  float inside = -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius);

  vec2 shift = vec2(0.0);
  if (u_scale > 0.0 && inside > 0.0 && inside < u_bezel) {
    vec2 normal;
    if (q.x > 0.0 && q.y > 0.0) {
      normal = normalize(q);
    } else if (q.x > q.y) {
      normal = vec2(1.0, 0.0);
    } else {
      normal = vec2(0.0, 1.0);
    }
    normal *= sign(p);
    // Convex glass samples toward its middle.
    shift = -normal * magnitude(inside / u_bezel) * u_scale;
  }

  if (u_chroma > 0.0 && shift != vec2(0.0)) {
    float r = backdrop(frag + shift * (1.0 + u_chroma)).r;
    vec4 g = backdrop(frag + shift);
    float b = backdrop(frag + shift * (1.0 - u_chroma)).b;
    fragColor = vec4(r, g.g, b, g.a);
  } else {
    fragColor = backdrop(frag + shift);
  }
}
