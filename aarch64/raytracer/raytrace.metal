#include <metal_stdlib>
using namespace metal;

// ═══════════════════════════════════════════════════════════════════
// Data structures — layout must match host assembly (see defs.s)
// Using float4 everywhere for predictable 16-byte alignment.
// ═══════════════════════════════════════════════════════════════════

struct Light {
    float4 position;    // .xyz = position, .w = intensity
    float4 color;       // .xyz = color
};
// 32 bytes

struct Uniforms {
    float  time;            // offset 0
    uint   frame_count;     // offset 4
    uint   num_shapes;      // offset 8
    uint   num_lights;      // offset 12
    float4 resolution;      // offset 16 (.xy = width, height)
    float4 camera_pos;      // offset 32 (.xyz)
    float4 camera_look_at;  // offset 48 (.xyz, .w = fov)
    Light  lights[4];       // offset 64, 4 × 32 = 128
};
// total = 192 bytes

struct Shape {
    float4 type_info;   // .x = type (0=sphere,1=box,2=plane), .y = roughness, .z = reflectivity
    float4 position;    // .xyz
    float4 size;        // .xyz (radius for sphere, half-extents for box, normal for plane)
    float4 color;       // .xyz
};
// 64 bytes

// ═══════════════════════════════════════════════════════════════════

struct Ray {
    float3 origin;
    float3 direction;
};

struct Hit {
    float  t;
    float3 position;
    float3 normal;
    float3 color;
    float  roughness;
    float  reflectivity;
};

// ── Intersection routines ───────────────────────────────────────────

static Hit intersect_sphere(Ray ray, float3 center, float radius) {
    Hit hit;
    hit.t = -1.0;
    float3 oc = ray.origin - center;
    float b = dot(oc, ray.direction);
    float c = dot(oc, oc) - radius * radius;
    float disc = b * b - c;
    if (disc > 0.0) {
        float sq = sqrt(disc);
        float t = -b - sq;
        if (t < 0.001) t = -b + sq;
        if (t > 0.001) {
            hit.t = t;
            hit.position = ray.origin + t * ray.direction;
            hit.normal = normalize(hit.position - center);
        }
    }
    return hit;
}

static Hit intersect_plane(Ray ray, float3 point, float3 normal) {
    Hit hit;
    hit.t = -1.0;
    float denom = dot(normal, ray.direction);
    if (abs(denom) > 0.0001) {
        float t = dot(point - ray.origin, normal) / denom;
        if (t > 0.001) {
            hit.t = t;
            hit.position = ray.origin + t * ray.direction;
            hit.normal = normal;
        }
    }
    return hit;
}

static Hit intersect_box(Ray ray, float3 center, float3 half_ext) {
    Hit hit;
    hit.t = -1.0;
    float3 m = 1.0 / ray.direction;
    float3 n = m * (ray.origin - center);
    float3 k = abs(m) * half_ext;
    float3 t1 = -n - k;
    float3 t2 = -n + k;
    float tN = max(max(t1.x, t1.y), t1.z);
    float tF = min(min(t2.x, t2.y), t2.z);
    if (tN > tF || tF < 0.0) return hit;
    float t = tN > 0.001 ? tN : tF;
    if (t < 0.001) return hit;
    hit.t = t;
    hit.position = ray.origin + t * ray.direction;
    float3 d = (hit.position - center) / half_ext;
    float3 ad = abs(d);
    if (ad.x > ad.y && ad.x > ad.z)
        hit.normal = float3(sign(d.x), 0.0, 0.0);
    else if (ad.y > ad.z)
        hit.normal = float3(0.0, sign(d.y), 0.0);
    else
        hit.normal = float3(0.0, 0.0, sign(d.z));
    return hit;
}

// ── Scene intersection ──────────────────────────────────────────────

static Hit trace_scene(Ray ray, constant Shape* shapes, uint num_shapes) {
    Hit closest;
    closest.t = -1.0;
    for (uint i = 0; i < num_shapes; i++) {
        uint type = uint(shapes[i].type_info.x);
        Hit h;
        if (type == 0)
            h = intersect_sphere(ray, shapes[i].position.xyz, shapes[i].size.x);
        else if (type == 1)
            h = intersect_box(ray, shapes[i].position.xyz, shapes[i].size.xyz);
        else
            h = intersect_plane(ray, shapes[i].position.xyz, normalize(shapes[i].size.xyz));

        if (h.t > 0.0 && (closest.t < 0.0 || h.t < closest.t)) {
            closest = h;
            closest.color = shapes[i].color.xyz;
            closest.roughness = shapes[i].type_info.y;
            closest.reflectivity = shapes[i].type_info.z;
        }
    }
    return closest;
}

// ── Shading ─────────────────────────────────────────────────────────

static float3 shade(Hit hit, Ray ray, constant Uniforms& u, constant Shape* shapes) {
    float3 ambient = 0.05 * hit.color;
    float3 result = ambient;

    for (uint i = 0; i < u.num_lights; i++) {
        float3 light_pos = u.lights[i].position.xyz;
        float  intensity = u.lights[i].position.w;
        float3 light_col = u.lights[i].color.xyz;

        float3 L = light_pos - hit.position;
        float light_dist = length(L);
        L = normalize(L);

        // Shadow ray
        Ray shadow_ray;
        shadow_ray.origin = hit.position + hit.normal * 0.002;
        shadow_ray.direction = L;
        Hit shadow_hit = trace_scene(shadow_ray, shapes, u.num_shapes);
        if (shadow_hit.t > 0.0 && shadow_hit.t < light_dist)
            continue;

        // Diffuse
        float NdotL = max(dot(hit.normal, L), 0.0);
        float3 diffuse = hit.color * NdotL;

        // Blinn-Phong specular
        float3 V = normalize(-ray.direction);
        float3 H = normalize(L + V);
        float NdotH = max(dot(hit.normal, H), 0.0);
        float shininess = mix(8.0, 128.0, 1.0 - hit.roughness);
        float3 spec = float3(1.0) * pow(NdotH, shininess);

        // Attenuation
        float atten = intensity / (1.0 + 0.05 * light_dist * light_dist);
        result += (diffuse + spec * (1.0 - hit.roughness)) * light_col * atten;
    }
    return result;
}

// ── Camera ──────────────────────────────────────────────────────────

static Ray make_camera_ray(float2 uv, float3 pos, float3 look_at, float fov) {
    float3 forward = normalize(look_at - pos);
    float3 right = normalize(cross(forward, float3(0.0, 1.0, 0.0)));
    float3 up = cross(right, forward);
    float half_fov = tan(fov * 0.5);

    Ray ray;
    ray.origin = pos;
    ray.direction = normalize(forward + right * uv.x * half_fov + up * uv.y * half_fov);
    return ray;
}

// ── Main kernel ─────────────────────────────────────────────────────

kernel void raytrace_kernel(
    texture2d<float, access::write> output [[texture(0)]],
    constant Uniforms& uniforms            [[buffer(0)]],
    constant Shape* shapes                 [[buffer(1)]],
    uint2 gid                              [[thread_position_in_grid]]
) {
    uint width  = output.get_width();
    uint height = output.get_height();
    if (gid.x >= width || gid.y >= height) return;

    float aspect = uniforms.resolution.x / uniforms.resolution.y;
    float2 uv = float2(
        (float(gid.x) / float(width)  - 0.5) * 2.0 * aspect,
        (0.5 - float(gid.y) / float(height)) * 2.0
    );

    float fov = uniforms.camera_look_at.w;
    Ray ray = make_camera_ray(uv, uniforms.camera_pos.xyz, uniforms.camera_look_at.xyz, fov);

    Hit hit = trace_scene(ray, shapes, uniforms.num_shapes);
    float3 color;
    if (hit.t < 0.0) {
        float t = 0.5 * (ray.direction.y + 1.0);
        color = mix(float3(0.1, 0.1, 0.12), float3(0.02, 0.02, 0.05), t);
    } else {
        color = shade(hit, ray, uniforms, shapes);

        // Single-bounce reflection
        if (hit.reflectivity > 0.0) {
            Ray refl_ray;
            refl_ray.origin = hit.position + hit.normal * 0.002;
            refl_ray.direction = reflect(ray.direction, hit.normal);
            Hit refl_hit = trace_scene(refl_ray, shapes, uniforms.num_shapes);
            float3 refl_color;
            if (refl_hit.t < 0.0) {
                float t = 0.5 * (refl_ray.direction.y + 1.0);
                refl_color = mix(float3(0.1, 0.1, 0.12), float3(0.02, 0.02, 0.05), t);
            } else {
                refl_color = shade(refl_hit, refl_ray, uniforms, shapes);
            }
            color = mix(color, refl_color, hit.reflectivity);
        }
    }

    // Reinhard tone mapping + gamma
    color = color / (color + 1.0);
    color = pow(color, float3(1.0 / 2.2));

    output.write(float4(color, 1.0), gid);
}
