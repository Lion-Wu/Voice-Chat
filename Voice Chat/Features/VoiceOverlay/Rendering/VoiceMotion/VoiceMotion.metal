#include <metal_stdlib>
using namespace metal;

struct VoiceMotionUniforms {
    float2 resolution;
    float time;
    float stateTime;
    float4 stateWeights;
    float4 stateData;
    float4 audio;
    float4 accent;
    float4 controls;
    float4 layout;
};

constant float TAU = 6.28318530717958647692;
constant int MORPH_CELL_COUNT = 5;
constant int SPEAKING_BAR_COUNT = 4;
constant float SPEAKING_LAYOUT_CODE_MAX = 1023.0;
constant float CONNECTING_ROTATION_SPEED = 1.6;
constant float3 ERROR_ACCENT_LINEAR = float3(0.37626212, 0.39675523, 0.43415364);

float saturateValue(float value) { return clamp(value, 0.0, 1.0); }
float wrapPhase(float phase) { return fmod(fmod(phase, TAU) + TAU, TAU); }
float smoother(float value) {
    value = saturateValue(value);
    return value * value * value * (value * (value * 6.0 - 15.0) + 10.0);
}
float easedWeight(float value) {
    value = saturateValue(value);
    return value * value * (3.0 - 2.0 * value);
}
float sdCircle(float2 point, float radius) { return length(point) - radius; }
float sdCapsule(float2 point, float2 start, float2 end, float radius) {
    float2 pa = point - start;
    float2 ba = end - start;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.00001), 0.0, 1.0);
    return length(pa - ba * h) - radius;
}
float smoothMin(float a, float b, float radius) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(radius, 0.0001), 0.0, 1.0);
    return mix(b, a, h) - radius * h * (1.0 - h);
}
float dominantStateWeight(float4 weights, float errorWeight) {
    return max(max(max(weights.x, weights.y), max(weights.z, weights.w)), errorWeight);
}
float transitionAmount(float4 weights, float errorWeight) {
    return smoother((1.0 - dominantStateWeight(weights, errorWeight)) * 2.2);
}

float sharedOrbitPhase(float time, float motion, float seed) {
    float primary = saturateValue(motion);
    float boost = saturateValue(motion - 1.0);
    float speed = mix(0.52, 1.02, primary) + 0.16 * boost;
    float clockwisePhase = time * speed
        + 0.050 * sin(time * 0.47 + 0.2) * motion;
    return wrapPhase(
        seed * TAU - clockwisePhase
    );
}

float2 circularOrbitPosition(float phase, float radius) {
    return float2(cos(phase), sin(phase)) * radius;
}

float4 connectingCell(
    float time,
    float motion,
    float presence,
    float seed
) {
    float phase = sharedOrbitPhase(
        time * CONNECTING_ROTATION_SPEED,
        motion,
        seed
    );
    float2 center = circularOrbitPosition(phase, 0.145);
    float radius = 0.025 * (
        1.0 + 0.012 * sin(time * 2.2 + 0.4) * motion * presence
    );
    return float4(center, radius, 0.0);
}

float4 listeningCell(float time, float4 audio, float motion) {
    float rms = saturateValue(audio.x);
    float radius = 0.116
        + 0.0038 * sin(time * 1.12 + 0.4) * motion
        + 0.052 * pow(rms, 0.72);
    return float4(0.0, 0.0, radius, 0.0);
}

int speakingBarIndex(int cellIndex, float packedLayout) {
    int code = int(floor(clamp(packedLayout, 0.0, SPEAKING_LAYOUT_CODE_MAX) + 0.5));
    int divisor = 1;
    if (cellIndex == 1) divisor = 4;
    else if (cellIndex == 2) divisor = 16;
    else if (cellIndex == 3) divisor = 64;
    else if (cellIndex >= 4) divisor = 256;
    return (code / divisor) % SPEAKING_BAR_COUNT;
}

float4 thinkingCell(
    int index,
    float time,
    float4 audio,
    float motion,
    float presence,
    float seed
) {
    float item = float(index);
    float slot = TAU * item / 5.0;
    float phase = wrapPhase(
        sharedOrbitPhase(time, motion, seed)
            + slot
            + 0.022 * sin(time * 1.24 + slot + 0.5) * motion * presence
    );
    float orbit = 0.116
        + 0.0055 * sin(time * 0.86 + 0.35) * motion * presence;
    float radial = orbit
        + 0.0048 * sin(time * 1.52 + slot + 0.9) * motion * presence;
    float2 center = circularOrbitPosition(phase, radial);
    float beat = 0.5 + 0.5 * sin(time * 2.02 + slot + 0.3);
    float radius = 0.0305 * (
        1.0 + 0.055 * (beat - 0.5) * motion * presence
    ) + 0.0012 * saturateValue(audio.z) * presence;
    return float4(center, radius, 0.0);
}

float4 speakingBarCell(
    int index,
    float time,
    float4 audio,
    float motion,
    float presence
) {
    float item = float(index);
    float normalized = (item - 1.5) / 1.5;
    float rms = saturateValue(audio.x);
    float low = saturateValue(audio.y);
    float mid = saturateValue(audio.z);
    float high = saturateValue(audio.w);
    float energy = pow(max(rms, 0.03), 0.62);
    float band = mix(mid, low, saturateValue(-normalized));
    band = mix(band, high, saturateValue(normalized));
    float wave = 0.5 + 0.5 * sin(
        time * (3.65 + 0.18 * item)
        + item * 1.47
        + 0.42 * sin(time * 0.71 + item * 0.38)
    );
    float echo = 0.5 + 0.5 * sin(
        time * (2.20 + 0.11 * item)
        + item * 2.15
        + 0.6
    );
    float phrase = 0.5 + 0.5 * sin(
        time * 0.84 + 0.30 * sin(time * 0.31 + 0.4)
    );
    float animation = saturateValue(motion * presence);
    float dynamicCadence = 0.08
        + 0.66 * pow(wave, 0.70)
        + 0.18 * echo
        + 0.08 * phrase;
    float cadence = mix(0.48, dynamicCadence, animation);
    float profile = 1.0 - 0.08 * abs(normalized);
    float radius = 0.0225
        + 0.0016 * energy * (0.4 + 0.6 * band);
    float stem = 0.014 + 0.003 * (1.0 - abs(normalized));
    stem += profile
        * energy
        * (0.030 + 0.018 * band)
        * (0.30 + 0.72 * cadence);
    float y = 0.0018
        * sin(time * 1.55 + item * 1.10)
        * animation
        * (0.25 + energy);
    return float4(normalized * 0.105, y, radius, stem);
}

float4 speakingCell(
    int cellIndex,
    float time,
    float4 audio,
    float motion,
    float presence,
    float packedLayout
) {
    return speakingBarCell(
        speakingBarIndex(cellIndex, packedLayout),
        time,
        audio,
        motion,
        presence
    );
}

float speakingBarDistance(
    int barIndex,
    float2 point,
    float time,
    float4 audio,
    float motion
) {
    float4 cell = speakingBarCell(barIndex, time, audio, motion, 1.0);
    float2 local = point - cell.xy;
    float stem = max(cell.w, 0.0);
    return sdCapsule(
        local,
        float2(0.0, -stem),
        float2(0.0, stem),
        max(cell.z, 0.001)
    );
}

float4 errorCell() {
    return float4(0.0, 0.0, 0.116, 0.0);
}

float listeningJelly(
    float2 local,
    float time,
    float4 audio,
    float motion,
    float presence
) {
    float angle = atan2(local.y, local.x);
    float low = saturateValue(audio.y);
    float mid = saturateValue(audio.z);
    float high = saturateValue(audio.w);
    return motion * presence * (
        sin(angle * 3.0 + time * 1.05) * (0.0025 + 0.0070 * low)
        + sin(angle * 5.0 + time * 1.58 + 1.3) * (0.0015 + 0.0045 * mid)
        + sin(angle * 8.0 + time * 2.18 + 2.1) * (0.0008 + 0.0028 * high)
    );
}

float4 morphCellDescriptor(
    int index,
    float time,
    float4 weights,
    float errorWeight,
    float4 audio,
    float motion,
    float speakingLayoutCode,
    float seed
) {
    float4 blendWeights = float4(
        easedWeight(weights.x),
        easedWeight(weights.y),
        easedWeight(weights.z),
        easedWeight(weights.w)
    );
    float errorBlend = easedWeight(errorWeight);
    float blendSum = dot(blendWeights, float4(1.0)) + errorBlend;
    blendWeights /= max(blendSum, 0.00001);
    errorBlend /= max(blendSum, 0.00001);

    float4 cell = float4(0.0);
    if (blendWeights.x > 0.00001) {
        cell += connectingCell(
            time,
            motion,
            smoother(weights.x),
            seed
        ) * blendWeights.x;
    }
    if (blendWeights.y > 0.00001) {
        cell += listeningCell(time, audio, motion) * blendWeights.y;
    }
    if (blendWeights.z > 0.00001) {
        cell += thinkingCell(
            index,
            time,
            audio,
            motion,
            smoother(weights.z),
            seed
        ) * blendWeights.z;
    }
    if (blendWeights.w > 0.00001) {
        cell += speakingCell(
            index,
            time,
            audio,
            motion,
            smoother(weights.w),
            speakingLayoutCode
        ) * blendWeights.w;
    }
    if (errorBlend > 0.00001) {
        cell += errorCell() * errorBlend;
    }
    return cell;
}

float morphCellDistance(
    int index,
    float2 point,
    float time,
    float4 weights,
    float errorWeight,
    float4 audio,
    float motion,
    float speakingLayoutCode,
    float seed
) {
    float4 cell = morphCellDescriptor(
        index,
        time,
        weights,
        errorWeight,
        audio,
        motion,
        speakingLayoutCode,
        seed
    );
    float2 local = point - cell.xy;
    float listeningPresence = smoother(weights.y);
    float rms = saturateValue(audio.x);
    float low = saturateValue(audio.y);
    float mid = saturateValue(audio.z);
    float squeeze = 0.035 * rms * motion * listeningPresence;
    float2 deformed = local;
    deformed.x *= 1.0 + squeeze * (0.35 + 0.65 * low);
    deformed.y *= 1.0 - squeeze * (0.25 + 0.75 * mid);

    float stem = max(cell.w, 0.0);
    float distance = sdCapsule(
        deformed,
        float2(0.0, -stem),
        float2(0.0, stem),
        max(cell.z, 0.001)
    );
    distance -= listeningJelly(
        local,
        time,
        audio,
        motion,
        listeningPresence
    );
    return distance;
}

float combinedOuterDistance(
    float2 point,
    float time,
    float stateTime,
    float4 weights,
    float errorWeight,
    float4 audio,
    float motion,
    float speakingLayoutCode,
    float seed
) {
    if (weights.w > 0.9995) {
        float steady = speakingBarDistance(0, point, time, audio, motion);
        for (int index = 1; index < SPEAKING_BAR_COUNT; ++index) {
            steady = min(
                steady,
                speakingBarDistance(index, point, time, audio, motion)
            );
        }
        return steady;
    }

    if (weights.x > 0.9995 || weights.y > 0.9995 || errorWeight > 0.9995) {
        return morphCellDistance(
            0,
            point,
            time,
            weights,
            errorWeight,
            audio,
            motion,
            speakingLayoutCode,
            seed
        );
    }

    if (weights.z > 0.9995) {
        float steady = morphCellDistance(
            0,
            point,
            time,
            weights,
            errorWeight,
            audio,
            motion,
            speakingLayoutCode,
            seed
        );
        for (int index = 1; index < MORPH_CELL_COUNT; ++index) {
            steady = min(
                steady,
                morphCellDistance(
                    index,
                    point,
                    time,
                    weights,
                    errorWeight,
                    audio,
                    motion,
                    speakingLayoutCode,
                    seed
                )
            );
        }
        return steady;
    }

    float blend = transitionAmount(weights, errorWeight);
    float compactWeight = saturateValue(weights.x + weights.y + errorWeight);
    float compactInfluence = smoother(saturateValue(compactWeight * 1.50));
    float maximumFusion = mix(0.0105, 0.0420, compactInfluence);
    float age = 1.0 - exp(-max(stateTime, 0.0) * 6.0);
    float fusion = mix(0.00015, maximumFusion, blend) * mix(0.94, 1.0, age);
    float distance = morphCellDistance(
        0,
        point,
        time,
        weights,
        errorWeight,
        audio,
        motion,
        speakingLayoutCode,
        seed
    );
    for (int index = 1; index < MORPH_CELL_COUNT; ++index) {
        distance = smoothMin(
            distance,
            morphCellDistance(
                index,
                point,
                time,
                weights,
                errorWeight,
                audio,
                motion,
                speakingLayoutCode,
                seed
            ),
            fusion
        );
    }
    float fusionCompensation = mix(0.08, 0.010, compactInfluence);
    return distance + fusion * fusionCompensation * blend;
}

float3 errorApertureLayout(
    float time,
    float4 weights,
    float errorWeight,
    float4 audio,
    float motion,
    float speakingLayoutCode,
    float seed
) {
    if (errorWeight > 0.9995) return float3(0.0, 0.0, 1.0);

    float2 centerSum = float2(0.0);
    float squaredCenterSum = 0.0;
    for (int index = 0; index < MORPH_CELL_COUNT; ++index) {
        float2 center = morphCellDescriptor(
            index,
            time,
            weights,
            errorWeight,
            audio,
            motion,
            speakingLayoutCode,
            seed
        ).xy;
        centerSum += center;
        squaredCenterSum += dot(center, center);
    }

    float2 center = centerSum / float(MORPH_CELL_COUNT);
    float meanSquaredRadius = squaredCenterSum / float(MORPH_CELL_COUNT);
    float spread = sqrt(max(meanSquaredRadius - dot(center, center), 0.0));
    float consolidation = 1.0 - smoother(saturateValue((spread - 0.010) / 0.030));
    return float3(center, consolidation);
}

float combinedDistance(
    float2 point,
    float time,
    float stateTime,
    float4 weights,
    float errorWeight,
    float targetStateIndex,
    float errorApertureProgress,
    float4 audio,
    float motion,
    float speakingLayoutCode,
    float seed
) {
    float outer = combinedOuterDistance(
        point,
        time,
        stateTime,
        weights,
        errorWeight,
        audio,
        motion,
        speakingLayoutCode,
        seed
    );

    float errorPresence = smoother(errorWeight);
    float apertureProgress = saturateValue(errorApertureProgress);
    if (errorPresence <= 0.0001 || apertureProgress <= 0.0001) return outer;

    float3 apertureLayout = errorApertureLayout(
        time,
        weights,
        errorWeight,
        audio,
        motion,
        speakingLayoutCode,
        seed
    );
    float enteringError = step(3.5, targetStateIndex);
    float enteringAperture = easedWeight(
        saturateValue((apertureProgress - 0.120) / 0.880)
    );
    float timedAperture = mix(apertureProgress, enteringAperture, enteringError);
    float exitPresenceGate = smoother(errorPresence);
    float presenceGate = mix(exitPresenceGate, 1.0, enteringError);
    float holeProgress = timedAperture * presenceGate * apertureLayout.z;
    float apertureCutoff = mix(0.060, 0.0001, enteringError);
    if (holeProgress <= apertureCutoff) return outer;
    float innerRadius = 0.086 * holeProgress;
    float outsideInnerCircle = innerRadius - length(point - apertureLayout.xy);
    return max(outer, outsideInnerCircle);
}

float connectingTrail(
    float2 point,
    float time,
    float connectingWeight,
    float motion,
    float seed
) {
    float trail = 0.0;
    float weight = smoother(connectingWeight);
    float headPhase = sharedOrbitPhase(
        time * CONNECTING_ROTATION_SPEED,
        motion,
        seed
    );

    for (int index = 1; index <= 18; ++index) {
        float item = float(index);
        float normalized = item / 18.0;
        float phase = headPhase + item * 0.045;
        float2 center = circularOrbitPosition(phase, 0.145);
        float sampleRadius = 0.025 * mix(0.98, 0.82, normalized);
        float signedDistance = sdCircle(point - center, sampleRadius);
        float softness = mix(0.0065, 0.0095, normalized);
        float body = 1.0 - smoothstep(
            -softness,
            softness * 1.55,
            signedDistance
        );
        float halo = 0.20
            * exp(-max(signedDistance, 0.0) * 72.0)
            * (1.0 - body);
        float fade = mix(0.92, 0.14, pow(normalized, 0.88));
        trail = max(trail, (body + halo) * fade);
    }

    return trail * weight;
}

vertex float4 voiceMotionVertex(uint vertexID [[vertex_id]]) {
    float2 position;
    if (vertexID == 0) position = float2(-1.0, -1.0);
    else if (vertexID == 1) position = float2(3.0, -1.0);
    else position = float2(-1.0, 3.0);
    return float4(position, 0.0, 1.0);
}

fragment float4 voiceMotionFragment(
    float4 position [[position]],
    constant VoiceMotionUniforms &uniforms [[buffer(0)]]
) {
    float2 resolution = max(uniforms.resolution, float2(1.0));
    float minimumDimension = min(resolution.x, resolution.y);
    float2 center = uniforms.layout.xy * resolution;
    float controlDiameter = max(
        uniforms.layout.z * minimumDimension,
        1.0
    );
    float2 point = (position.xy - center)
        / (controlDiameter * max(uniforms.layout.w, 0.0001));
    point.y = -point.y;

    float4 weights = max(uniforms.stateWeights, float4(0.0));
    float errorWeight = max(uniforms.stateData.x, 0.0);
    float weightSum = dot(weights, float4(1.0)) + errorWeight;
    if (weightSum <= 0.00001) {
        weights = float4(1.0, 0.0, 0.0, 0.0);
        errorWeight = 0.0;
    } else {
        weights /= weightSum;
        errorWeight /= weightSum;
    }

    float4 audio = clamp(uniforms.audio, 0.0, 1.0);
    float motion = clamp(uniforms.controls.x, 0.0, 2.0);
    float errorAppearance = smoother(errorWeight);
    float3 stateAccent = mix(
        max(uniforms.accent.rgb, float3(0.0)),
        ERROR_ACCENT_LINEAR,
        errorAppearance
    );
    float glowStrength = max(uniforms.controls.y, 0.0) * mix(1.0, 0.86, errorAppearance);
    float distance = combinedDistance(
        point,
        uniforms.time,
        uniforms.stateTime,
        weights,
        errorWeight,
        clamp(uniforms.stateData.y, 0.0, 4.0),
        uniforms.stateData.w,
        audio,
        motion,
        uniforms.stateData.z,
        uniforms.controls.z
    );

    float antialias = max(fwidth(distance), 0.00075);
    float fill = 1.0 - smoothstep(-antialias, antialias, distance);
    float2 gradient = float2(dfdx(distance), dfdy(distance));
    float2 normal = gradient / max(length(gradient), 0.00001);
    float directional = pow(
        max(dot(normal, normalize(float2(-0.62, 0.78))), 0.0),
        7.0
    );
    float rim = exp(-abs(distance) * 160.0) * directional * fill;
    float outside = max(distance, 0.0);
    float glow = (
        0.18 * exp(-outside * 58.0)
        + 0.035 * exp(-outside * 17.0)
    ) * (1.0 - fill) * glowStrength;
    float trail = 0.0;
    if (weights.x > 0.0005) {
        trail = connectingTrail(
            point,
            uniforms.time,
            weights.x,
            motion,
            uniforms.controls.z
        ) * 0.180 * weights.x * glowStrength;
    }

    float opacity = saturateValue(fill + glow * 0.74 + trail * 0.95);
    float luminance = min(
        fill * 0.985 + rim * 0.055 + glow * 0.91 + trail * 0.78,
        opacity
    );
    float alpha = saturateValue(uniforms.accent.a);
    float outputAlpha = opacity * alpha;
    if (outputAlpha <= 0.0009765625) {
        return float4(0.0);
    }

    return float4(
        stateAccent * luminance * alpha,
        outputAlpha
    );
}
