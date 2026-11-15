// ============================================================================
//  AlienOcean — 만화풍(툰) 외계 바다
// ----------------------------------------------------------------------------
//  [바탕으로 한 갤러리 항목 — 두 개를 섞었다]
//    C1 물결 수면   : 사인파 3개로 정점을 오르내리게 하고, 법선을 다시 구해 프레넬과 반사광을 칠한다.
//    A1 램프 툰 조명 : 매끈한 밝기를 몇 개의 띠(단계)로 끊어 만화풍 음영을 만든다.
//
//  [갤러리에서 바꾸거나 더한 것]
//    - 툰 물빛     : C1 은 프레넬로 물빛→하늘빛을 부드럽게 섞지만, 여기서는 그 값을 띠로 끊어 색 띠로 칠한다.
//    - 툰 음영     : A1 의 dot(N, L) 띠를 물결에 적용해, 광원(Directional Light)을 향한 물결 면만 밝은 띠가 된다.
//    - 툰 반사광   : 점점 흐려지는 반짝임 대신, 기준값을 넘으면 켜지는 또렷한 반짝임 조각.
//    - 툰 거품(발광): 파도가 일정 높이를 넘은 마루에만 경계가 또렷한 발광 거품이 생긴다.
//    - 툰 섞기 슬라이더 : 0 = 갤러리 C1 그대로(매끈), 1 = 툰. 둘을 비교해 볼 수 있다.
//    - 불투명 / 200 m 바다 크기 / 외계 색 / 단계 보기
//
//  [사용법]
//    1) 빈 GameObject 에 AlienOceanGrid 스크립트를 붙이고, MeshRenderer 에 이 머티리얼을 넣는다.
//    2) 씬의 Directional Light 방향과 색을 그대로 쓴다. 빛을 낮게 비출수록 밝은 띠와 그늘 띠가 또렷하게 나뉜다.
//       (빛이 위에서 내리꽂으면 거의 모든 물결 면이 밝은 띠가 되어 툰 느낌이 약해진다)
// ============================================================================

Shader "MyShaders/AlienOcean"
{
    Properties
    {
        [Header(Waves)]
        _WaveHeight ("파도 높이 (m)", Range(0, 2)) = 0.6
        _WaveLength ("파장 (m, 마루 사이 거리)", Range(4, 40)) = 14
        _WaveSpeed  ("파도 속도 (m/초)", Range(0, 10)) = 3
        _WaveAngle  ("파도 방향 (도, 0 = +Z 쪽)", Range(0, 360)) = 200

        [Header(Color)]
        _DeepColor  ("물빛 (내려다볼 때)", Color) = (0.02, 0.16, 0.20, 1)
        _SkyColor   ("하늘빛 (비스듬히 볼 때)", Color) = (0.40, 0.22, 0.55, 1)
        _ShadeColor ("그늘 색 (광원을 등진 물결)", Color) = (0.45, 0.35, 0.75, 1)

        [Header(Toon)]
        _ToonBlend   ("툰 섞기 (0 = 갤러리 매끈, 1 = 툰)", Range(0, 1)) = 1
        _Bands       ("띠 수", Range(2, 5)) = 3
        _Softness    ("띠 경계 부드러움", Range(0, 0.5)) = 0.05
        _ShadeShift  ("그늘 넓이", Range(-0.25, 0.6)) = 0

        [Header(Specular)]
        _SpecStrength  ("반사광 세기", Range(0, 3)) = 1.5
        _SpecPower     ("반사광 날카로움", Range(4, 256)) = 120
        _SpecThreshold ("툰 반사광 기준값 (클수록 조각이 작아짐)", Range(0.05, 0.95)) = 0.5

        [Header(Foam Glow)]
        [HDR] _GlowColor ("거품 발광 색", Color) = (0.3, 1.8, 1.4, 1)
        _GlowStart       ("거품 시작 높이 (0 = 골, 1 = 마루)", Range(0, 1)) = 0.75
        _GlowPulse       ("깜빡임 속도", Range(0, 5)) = 1

        [Header(Debug)]
        [Enum(Final,0, Height,1, Normal,2, Fresnel,3, WaterBand,4, LightBand,5, Specular,6, Foam,7)] _DebugStep ("단계 보기", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Geometry" "RenderPipeline" = "UniversalPipeline" }

        Pass
        {
            Name "Forward"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"  // GetMainLight()

            CBUFFER_START(UnityPerMaterial)
                float  _WaveHeight;
                float  _WaveLength;
                float  _WaveSpeed;
                float  _WaveAngle;
                float4 _DeepColor;
                float4 _SkyColor;
                float4 _ShadeColor;
                float  _ToonBlend;
                float  _Bands;
                float  _Softness;
                float  _ShadeShift;
                float  _SpecStrength;
                float  _SpecPower;
                float  _SpecThreshold;
                float4 _GlowColor;
                float  _GlowStart;
                float  _GlowPulse;
                float  _DebugStep;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionOS : TEXCOORD0;  // 오브젝트 공간 위치 (파도를 다시 계산할 때 씀)
                float3 positionWS : TEXCOORD1;  // 월드 위치 (시선 방향을 구할 때 씀)
            };

            #define TAU 6.2831853   // 2π (한 바퀴)

            // ================================================================
            //  갤러리 C1 : 파도
            // ================================================================

            // 파도 하나
            //   높이 = 진폭 × sin(위상)
            //   돌려주는 값 float3(높이, x 기울기, z 기울기). 기울기는 sin 을 미분한 cos 으로 바로 구한다.
            float3 WaveOne(float2 xz, float angleDeg, float wavelength, float amplitude, float speed)
            {
                float  rad = radians(angleDeg);
                float2 dir = float2(sin(rad), cos(rad));   // 0도 = +Z, 90도 = +X
                float  k   = TAU / wavelength;

                // frac 으로 한 주기 안에 감싸면, 오래 켜 두어도 숫자가 커지지 않아 파도가 떨리지 않는다.
                float phase = k * dot(dir, xz) - TAU * frac(_Time.y * speed / wavelength);

                float height = amplitude * sin(phase);
                float slope  = amplitude * k * cos(phase);
                return float3(height, slope * dir.x, slope * dir.y);
            }

            // 파도 3개 더하기 : 방향과 파장을 엇갈려야 골판지처럼 한 줄로 늘어서지 않는다.
            float3 WaveSum(float2 xz)
            {
                float3 w = WaveOne(xz, _WaveAngle,        _WaveLength,        _WaveHeight,       _WaveSpeed);
                w       += WaveOne(xz, _WaveAngle + 55.0, _WaveLength * 0.77, _WaveHeight * 0.6, _WaveSpeed * 0.88);
                w       += WaveOne(xz, _WaveAngle - 40.0, _WaveLength * 0.58, _WaveHeight * 0.4, _WaveSpeed * 0.76);
                return w;
            }

            // ================================================================
            //  갤러리 A1 : 띠로 끊기
            // ----------------------------------------------------------------
            //  0~1 의 매끈한 값을 _Bands 개의 계단으로 만든다.
            //  예) 띠 3개 → 결과는 0, 0.5, 1 셋 중 하나
            //  경계에서만 _Softness 만큼 살짝 부드럽게 넘어가서 계단 현상(지글거림)을 막는다.
            // ================================================================
            float ToonBands(float value)
            {
                float bands = max(round(_Bands), 2.0);
                float t     = value * bands - 0.5;
                float cell  = floor(t);        // 몇 번째 계단인지
                float f     = t - cell;        // 계단 안에서의 위치 (0.5 가 경계)

                // fwidth(t) = 옆 픽셀과의 차이. 경계가 픽셀 하나보다 얇아지지 않게 해 준다.
                float w = clamp(max(_Softness, fwidth(t)), 0.001, 0.5);
                return saturate((cell + smoothstep(0.5 - w, 0.5 + w, f)) / (bands - 1.0));
            }

            // 정점 셰이더 : 정점을 파도 높이만큼 위아래로 민다
            Varyings vert(Attributes input)
            {
                float3 pos = input.positionOS.xyz;
                pos.y += WaveSum(pos.xz).x;

                Varyings output;
                output.positionOS = pos;
                output.positionWS = TransformObjectToWorld(pos);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                return output;
            }

            // 픽셀 셰이더
            float4 frag(Varyings input) : SV_Target
            {
                // ---- 재료 준비 (갤러리 C1 과 같다) ------------------------------------

                // 이 픽셀 자리의 파도를 한 번 더 계산한다. (높이와 기울기가 필요해서)
                float3 w = WaveSum(input.positionOS.xz);

                // 1. 높이 : 0 = 골, 1 = 마루. (파도 3개 진폭의 합이 2 배라 그만큼 나눈다)
                float height01 = saturate(0.5 + 0.5 * w.x / max(_WaveHeight * 2.0, 0.0001));

                // 2. 법선 : 기울기가 (x 기울기, z 기울기) 인 면의 법선은 (-x 기울기, 1, -z 기울기) 방향이다.
                //    (흔한 실수: 정점만 밀고 평면 법선(위쪽)을 그대로 쓰면, 출렁이는데도 평평한 판처럼 빛난다)
                float3 normalWS = normalize(TransformObjectToWorldNormal(float3(-w.y, 1.0, -w.z)));
                float3 viewWS   = GetWorldSpaceNormalizeViewDir(input.positionWS);
                Light  light    = GetMainLight();

                // 3. 프레넬 : 정면에서 내려다보면 0, 수면을 스치듯 볼수록 1
                float facing  = saturate(dot(normalWS, viewWS));
                float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 5.0);   // 갤러리 C1 의 식 (실제 물의 반사율)

                // 반사광 재료 : 빛 방향과 시선의 가운데 방향(halfDir)이 법선과 맞을수록 1
                float3 halfDir = normalize(light.direction + viewWS);
                float  specRaw = pow(saturate(dot(normalWS, halfDir)), _SpecPower);

                // 거품 발광이 생물처럼 천천히 깜빡이게 하는 값 (매끈/툰 공통)
                float pulse = 0.7 + 0.3 * sin(_Time.y * _GlowPulse);

                // ---- [A] 갤러리 C1 그대로 : 매끈한 물 ------------------------------
                float  glowSmooth   = smoothstep(_GlowStart, 1.0, height01);
                float3 smoothColor  = lerp(_DeepColor.rgb, _SkyColor.rgb, fresnel)
                                    + light.color * specRaw * _SpecStrength
                                    + _GlowColor.rgb * glowSmooth * pulse;

                // ---- [B] 툰 물 (갤러리 A1 을 섞은 부분) -----------------------------

                // 4. 물빛 띠 : 프레넬 재료(1 - facing)를 띠로 끊어, 물빛 → 하늘빛을 몇 개의 색 띠로 칠한다.
                //    (실제 프레넬 식은 대부분 0 근처라 띠가 거의 안 생겨서, 더 고르게 퍼진 1 - facing 을 쓴다)
                float  waterBand  = ToonBands(1.0 - facing);
                float3 waterColor = lerp(_DeepColor.rgb, _SkyColor.rgb, waterBand);

                // 5. 빛 띠 (A1 의 핵심) : dot(N, L) 을 띠로 끊는다. 광원을 향한 물결 면만 밝은 띠가 된다.
                //    그늘 넓이로 경계를 밀고, 그늘은 검게 하지 않고 그늘 색으로 물들인다.
                float  ndl       = dot(normalWS, light.direction);
                float  lightBand = ToonBands(saturate((ndl - _ShadeShift) / (1.0 - _ShadeShift)));
                float3 tint      = lerp(_ShadeColor.rgb, light.color, lightBand);

                // 6. 툰 반사광 : 기준값을 넘은 곳만 켠다 → 경계가 또렷한 반짝임 조각
                float specToon = smoothstep(_SpecThreshold - 0.02, _SpecThreshold + 0.02, specRaw);

                // 7. 툰 거품 : 거품 시작 높이를 넘은 마루만 1. 경계를 아주 좁게 해서 만화 거품처럼 또렷하게.
                float foamToon = smoothstep(_GlowStart - 0.01, _GlowStart + 0.01, height01);

                float3 toonColor = waterColor * tint
                                 + light.color * specToon * _SpecStrength;
                toonColor = lerp(toonColor, _GlowColor.rgb * pulse, foamToon);   // 거품은 위에 덮는다

                // ---- 단계 보기 ------------------------------------------------------
                if (_DebugStep == 1) return float4(height01.xxx, 1);
                if (_DebugStep == 2) return float4(normalWS * 0.5 + 0.5, 1);
                if (_DebugStep == 3) return float4(fresnel.xxx, 1);
                if (_DebugStep == 4) return float4(waterBand.xxx, 1);
                if (_DebugStep == 5) return float4(lightBand.xxx, 1);
                if (_DebugStep == 6) return float4(specToon.xxx, 1);
                if (_DebugStep == 7) return float4(foamToon.xxx, 1);

                // ---- 최종 : 툰 섞기 슬라이더로 [A] 매끈 ↔ [B] 툰 -------------------
                float3 color = lerp(smoothColor, toonColor, _ToonBlend);
                return float4(color, 1);
            }
            ENDHLSL
        }
    }

    Fallback Off
}
