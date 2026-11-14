// Liquid glass lens: displaces the backdrop behind a glass shape, so what
// lies under the glass looks bent through it. Used as an ImageFilter.shader
// on a BackdropFilter (Impeller only).
//
// The displacement follows the shape. The rounded-rect signed distance
// gives how far a pixel sits in from the outline and which way the outline
// faces there. Inside a band along the outline (the lens) each pixel shows
// the backdrop from further in, most at the outline and easing to nothing
// where the band ends, like the thick curved rim of a glass slab. The flat
// middle of the glass is untouched.

#version 460 core
#include <flutter/runtime_effect.glsl>

precision highp float;

// Set by the engine: size of the backdrop texture, in its own pixels.
uniform vec2 u_size;
// Glass rectangle in backdrop pixels: left, top, width, height.
uniform vec4 u_rect;
// Corner radius, depth of the lens band and largest shift (at the outline),
// in backdrop pixels.
uniform float u_radius;
uniform float u_depth;
uniform float u_scale;
// Set by the engine: the backdrop.
uniform sampler2D u_texture;

out vec4 fragColor;

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
  float minHalf = min(halfSize.x, halfSize.y);
  float depth = min(u_depth, minHalf);

  // The lens follows a shape whose corners are at least as round as the
  // band is deep. Every contour inside the band is then a smooth curve, so
  // the direction of the shift never jumps (a sharp inner corner would
  // show as a crease along the diagonal).
  float radius = clamp(max(u_radius, depth), 0.0, minHalf);
  vec2 q = abs(p) - (halfSize - radius);
  float inside = radius - length(max(q, 0.0)) - min(max(q.x, q.y), 0.0);

  vec2 shift = vec2(0.0);
  if (u_scale > 0.0 && depth > 0.0 && inside < depth) {
    // Which way the outline faces at this pixel.
    vec2 normal;
    if (q.x > 0.0 && q.y > 0.0) {
      normal = normalize(q);
    } else if (q.x > q.y) {
      normal = vec2(1.0, 0.0);
    } else {
      normal = vec2(0.0, 1.0);
    }
    normal *= vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);

    // 1 at the outline, 0 at the inner end of the band, with no slope
    // there: the bend fades out instead of stopping.
    float t = 1.0 - clamp(inside / depth, 0.0, 1.0);
    float bend = t * t;
    // Convex glass shows what is further in.
    shift = -normal * bend * u_scale;
  }

  fragColor = backdrop(frag + shift);
}
