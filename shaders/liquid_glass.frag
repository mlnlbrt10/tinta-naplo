#version 320 es

precision highp float;

#include <flutter/runtime_effect.glsl>

// Engine-populated backdrop texture size in physical pixels (slots 0, 1).
// Required as the first vec2 uniform by Flutter's ImageFilter.shader API.
uniform vec2 uSize;
// Rounded corner radius in physical pixels (slot 2).
uniform float uCornerRadius;
// Curved convex glass bezel width in physical pixels, typically 14-22dp * dpr (slot 3).
uniform float uBezelWidth;
// Optical refraction strength in physical pixels (slot 4).
uniform float uRefractionStrength;
// Chromatic dispersion (RGB index-of-refraction split) intensity (slot 5).
uniform float uChromaticAberration;
// Multi-tap frosted diffusion radius in physical pixels (slot 6).
uniform float uBlurRadius;
// Directional specular light angle in radians (slot 7).
uniform float uLightAngle;
// Scroll / interaction offset for subtle dynamic rim & caustic shift (slot 8).
uniform float uScrollOffset;
// Straight RGBA surface tint adapted for OLED dark or Light surfaces (slots 9..12).
uniform vec4 uTintColor;
// Theme luminance flag: 1.0 = dark / OLED, 0.0 = light (slot 13).
uniform float uIsDark;
// Device pixel ratio for resolution-independent 1.0-1.5dp rim stroke width (slot 14).
uniform float uPixelRatio;

// Underlying backdrop texture captured by BackdropFilter / ImageFilter.shader.
uniform sampler2D uBackdropSampler;

out vec4 fragColor;

const float PI = 3.14159265359;
const float GOLDEN_ANGLE = 2.39996322973;

float sdRoundedBox(vec2 p, vec2 halfExtents, float radius) {
  vec2 q = abs(p) - halfExtents + vec2(radius);
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

// Analytical outward gradient of the rounded-rectangle SDF.
vec2 gradRoundedBox(vec2 p, vec2 halfExtents, float radius) {
  vec2 s = vec2(p.x >= 0.0 ? 1.0 : -1.0, p.y >= 0.0 ? 1.0 : -1.0);
  vec2 q = abs(p) - halfExtents + vec2(radius);
  vec2 qMax = max(q, 0.0);
  float cornerLen = length(qMax);
  if (cornerLen > 1e-4) {
    return s * (qMax / cornerLen);
  }
  float diagBlend = smoothstep(-2.0, 2.0, q.x - q.y);
  return normalize(mix(vec2(0.0, s.y), vec2(s.x, 0.0), diagBlend) + vec2(1e-5, 0.0));
}

vec2 clampUv(vec2 uv, vec2 halfTexel) {
  return clamp(uv, halfTexel, vec2(1.0) - halfTexel);
}

void main() {
  vec2 safeSize = max(uSize, vec2(2.0));
  vec2 halfSize = safeSize * 0.5;
  float dpr = max(uPixelRatio, 1.0);
  vec2 uvPerPx = 1.0 / safeSize;
  vec2 halfTexel = uvPerPx * 0.75;

  float minHalf = min(halfSize.x, halfSize.y);
  float cornerR = clamp(uCornerRadius, 1.0, max(minHalf - 0.5, 1.0));
  vec2 fragCoord = FlutterFragCoord().xy;
  vec2 p = fragCoord - halfSize;

  // 1. SDF Rounded Rectangle & Analytical 3D Convex Bezel Surface Normal
  float sdf = sdRoundedBox(p, halfSize, cornerR);
  vec2 edgeNormal2D = gradRoundedBox(p, halfSize, cornerR);
  float distInside = max(-sdf, 0.0);

  float bezel = clamp(uBezelWidth, 4.0 * dpr, max(minHalf * 0.92, 4.0 * dpr));
  float tBezel = clamp(1.0 - (distInside / bezel), 0.0, 1.0);
  // Convex squircle dome slope: flat interior (t=0) curving smoothly into a steep optical lip (t=1)
  float curveProfile = pow(tBezel, 1.65);
  float slopeAngle = curveProfile * 1.04;
  vec3 normal3D = normalize(vec3(edgeNormal2D * sin(slopeAngle), cos(slopeAngle)));

  // 2. Physical Refraction & Chromatic Dispersion (RGB IoR Split)
  float disp = clamp(uChromaticAberration, 0.0, 1.0) * 0.085;
  float etaR = 1.0 / (1.52 - disp);
  float etaG = 1.0 / 1.52;
  float etaB = 1.0 / (1.52 + disp);

  vec3 viewRay = vec3(0.0, 0.0, -1.0);
  vec3 rRefract = refract(viewRay, normal3D, etaR);
  vec3 gRefract = refract(viewRay, normal3D, etaG);
  vec3 bRefract = refract(viewRay, normal3D, etaB);

  float lensStrength = max(uRefractionStrength, 0.0) * (0.28 + 0.72 * curveProfile);
  vec2 refractOffsetR = (rRefract.xy / max(abs(rRefract.z), 0.35)) * lensStrength * uvPerPx;
  vec2 refractOffsetG = (gRefract.xy / max(abs(gRefract.z), 0.35)) * lensStrength * uvPerPx;
  vec2 refractOffsetB = (bRefract.xy / max(abs(bRefract.z), 0.35)) * lensStrength * uvPerPx;

  // Subtle radial prismatic edge fringe along the outermost curved bevel
  vec2 prismSpread = edgeNormal2D * (max(uRefractionStrength, 0.0) * clamp(uChromaticAberration, 0.0, 1.0) * 0.24 * curveProfile) * uvPerPx;
  refractOffsetR -= prismSpread;
  refractOffsetB += prismSpread;

  vec2 baseUv = fragCoord * uvPerPx;
  vec2 uvR = clampUv(baseUv + refractOffsetR, halfTexel);
  vec2 uvG = clampUv(baseUv + refractOffsetG, halfTexel);
  vec2 uvB = clampUv(baseUv + refractOffsetB, halfTexel);

  // 3. Multi-Tap Vogel Spiral Frosted Diffusion (interior frosted, rim optically crisp)
  float effectiveBlur = max(uBlurRadius, 0.0) * mix(1.0, 0.22, curveProfile);
  vec3 frostedRgb = texture(uBackdropSampler, uvG).rgb * 1.15;
  float totalWeight = 1.15;

  if (effectiveBlur > 0.25) {
    const int TAP_COUNT = 12;
    for (int i = 0; i < TAP_COUNT; i++) {
      float fi = float(i);
      float radiusFrac = sqrt((fi + 0.5) / float(TAP_COUNT));
      float theta = fi * GOLDEN_ANGLE;
      vec2 tapDir = vec2(cos(theta), sin(theta));
      vec2 tapUv = clampUv(uvG + tapDir * (radiusFrac * effectiveBlur) * uvPerPx, halfTexel);
      float weight = 1.0 - radiusFrac * 0.45;
      frostedRgb += texture(uBackdropSampler, tapUv).rgb * weight;
      totalWeight += weight;
    }
  }
  frostedRgb /= totalWeight;

  // Blend crisp per-channel refracted RGB samples in the curved bezel zone
  vec3 glassRgb = frostedRgb;
  if (curveProfile > 0.01 && uChromaticAberration > 0.005) {
    float rSample = texture(uBackdropSampler, uvR).r;
    float gSample = texture(uBackdropSampler, uvG).g;
    float bSample = texture(uBackdropSampler, uvB).b;
    vec3 crispPrismRgb = vec3(rSample, gSample, bSample);
    glassRgb = mix(frostedRgb, crispPrismRgb, curveProfile * 0.72);
  }

  // 4. Tint & Luminance Adaptation
  vec3 tintedGlass = mix(glassRgb, uTintColor.rgb, clamp(uTintColor.a, 0.0, 0.96));

  // 5. Dynamic Specular Rim Lighting, Fresnel Reflection, & Caustic Sheen
  float fresnel = pow(1.0 - clamp(normal3D.z, 0.0, 1.0), 2.8);
  float dynamicAngle = uLightAngle + sin(uScrollOffset * 0.015) * 0.42;
  vec2 lightDir2D = vec2(cos(dynamicAngle), sin(dynamicAngle));
  vec3 lightDir3D = normalize(vec3(lightDir2D * 0.72, 0.69));
  vec3 halfVec = normalize(lightDir3D + vec3(0.0, 0.0, 1.0));

  // Sharp 1.0px-1.5px (dpr-scaled) luminous inner rim highlight
  float rimInner = smoothstep(1.95 * dpr, 0.22 * dpr, distInside) *
                   smoothstep(-0.65 * dpr, 0.25 * dpr, -sdf);
  float dirAlign = dot(edgeNormal2D, lightDir2D);
  float primarySpec = pow(max(dirAlign, 0.0), 2.0);
  float bounceSpec = pow(max(-dirAlign, 0.0), 3.0) * 0.48;
  float rimIntensity = rimInner * (0.18 + 0.88 * primarySpec + bounceSpec);

  vec3 warmPrism = vec3(1.0, 0.94, 0.84);
  vec3 coolPrism = vec3(0.84, 0.95, 1.0);
  vec3 prismTint = mix(coolPrism, warmPrism, 0.5 + 0.5 * dirAlign);
  vec3 rimColor = mix(vec3(1.0), prismTint, clamp(uChromaticAberration * 1.4, 0.0, 0.65));

  float specBevel = pow(max(dot(normal3D, halfVec), 0.0), 16.0) * curveProfile;
  vec2 normP = p / max(max(halfSize.x, halfSize.y), 1.0);
  float causticPhase = dot(normP, lightDir2D) * 2.5 + uScrollOffset * 0.009;
  float causticSheen = exp(-pow(sin(causticPhase) * 1.75, 2.0)) * (0.03 + 0.07 * curveProfile);

  vec3 finalRgb = tintedGlass;
  if (uIsDark > 0.5) {
    finalRgb += vec3(0.92, 0.96, 1.0) * (fresnel * 0.16);
    finalRgb += rimColor * (causticSheen * 0.55 + specBevel * 0.28 + rimIntensity * 0.66);
  } else {
    finalRgb += vec3(1.0) * (causticSheen * 0.32);
    finalRgb += rimColor * (specBevel * 0.30 + rimIntensity * 0.58);
    // Crisp lower-right outer separation edge on bright light-mode backgrounds
    float shadowEdge = rimInner * (0.30 + 0.70 * max(-dirAlign, 0.0));
    finalRgb -= vec3(0.075) * shadowEdge;
  }

  fragColor = vec4(clamp(finalRgb, 0.0, 1.0), 1.0);
}
