// ============================================================================
//  AlienSky — 외계 행성의 하늘 (스카이박스 셰이더)
// ----------------------------------------------------------------------------
//  하는 일 (위에서 아래로 차례대로 색을 "쌓아" 올립니다)
//    1) 그라데이션 : 수평선은 밝은 보라, 하늘 꼭대기는 거의 검은 남색
//    2) 수평선 빛  : 수평선 바로 위에 얇게 번지는 대기 빛
//    3) 별         : 하늘을 3D 격자로 잘게 나누고, 칸마다 난수로 별을 찍음
//                    + 시간에 따라 반짝임
//
//  핵심 아이디어
//    스카이박스는 "카메라를 감싼 아주 큰 공"이라고 생각하면 됩니다.
//    공의 한 점 = 카메라에서 바라본 "방향" 하나.
//    그래서 이 셰이더는 위치가 아니라 "방향 벡터(dir)" 하나만 가지고
//    모든 색을 계산합니다.
//      dir.y =  1  → 바로 위(천정)
//      dir.y =  0  → 수평선
//      dir.y = -1  → 바로 아래(땅/바다)
//
//  확인 방법
//    Window > Rendering > Lighting > Environment > Skybox Material 에
//    AlienSky 머티리얼을 넣으세요.
// ============================================================================

Shader "MyShaders/AlienSky"
{
    // ------------------------------------------------------------------------
    // Properties : 머티리얼 인스펙터에 노출되는 값들
    //   [HDR] 이 붙은 색은 1보다 밝게 설정할 수 있어서 Bloom(번짐)이 잘 걸립니다.
    // ------------------------------------------------------------------------
    Properties
    {
        [Header(Gradient)]
        _ZenithColor   ("Zenith Color (하늘 꼭대기)", Color) = (0.015, 0.01, 0.05, 1)
        _HorizonColor  ("Horizon Color (수평선)", Color)     = (0.30, 0.10, 0.40, 1)
        _GroundColor   ("Ground Color (수평선 아래)", Color)  = (0.02, 0.015, 0.04, 1)
        _GradientPower ("Gradient Power (높을수록 수평선 색이 넓게)", Range(0.05, 3)) = 0.45

        [Header(Horizon Glow)]
        [HDR] _GlowColor   ("Glow Color", Color) = (0.9, 0.35, 0.65, 1)
        _GlowIntensity     ("Glow Intensity", Range(0, 3)) = 0.5
        _GlowSharpness     ("Glow Sharpness (높을수록 얇은 띠)", Range(1, 60)) = 14

        [Header(Stars)]
        _StarDensity     ("Star Density (격자 촘촘함)", Range(20, 400)) = 100
        _StarProbability ("Star Probability (칸에 별이 있을 확률)", Range(0, 1)) = 0.35
        _StarSize        ("Star Size", Range(0.02, 0.2)) = 0.15
        _StarBrightness  ("Star Brightness", Range(0, 10)) = 3
        [HDR] _StarColorA ("Star Color A", Color) = (1.0, 0.95, 0.9, 1)
        [HDR] _StarColorB ("Star Color B", Color) = (0.55, 0.75, 1.0, 1)
        _TwinkleSpeed    ("Twinkle Speed", Range(0, 10)) = 2
        _StarHorizonFade ("Star Horizon Fade (수평선 근처에서 흐려지는 폭)", Range(0.01, 0.5)) = 0.15
    }

    SubShader
    {
        // 스카이박스용 태그
        //   Queue = Background  : 가장 먼저(가장 뒤에) 그려짐
        //   PreviewType = Skybox: 머티리얼 미리보기를 하늘 모양으로 표시
        Tags
        {
            "RenderType"     = "Background"
            "Queue"          = "Background"
            "PreviewType"    = "Skybox"
            "RenderPipeline" = "UniversalPipeline"
        }

        Cull Off     // 공의 "안쪽"에서 보니까 뒷면 컬링을 끔
        ZWrite Off   // 하늘은 깊이를 기록하지 않음 (모든 물체 뒤에 있어야 하니까)

        Pass
        {
            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag

            // URP 기본 함수들(TransformObjectToHClip 등)이 들어 있는 파일
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // ----------------------------------------------------------------
            // 머티리얼 값들 — Properties 이름과 똑같이 선언해야 연결됩니다.
            // UnityPerMaterial 버퍼에 넣으면 SRP Batcher 와 호환됩니다.
            // ----------------------------------------------------------------
            CBUFFER_START(UnityPerMaterial)
                half4 _ZenithColor;
                half4 _HorizonColor;
                half4 _GroundColor;
                float _GradientPower;

                half4 _GlowColor;
                float _GlowIntensity;
                float _GlowSharpness;

                float _StarDensity;
                float _StarProbability;
                float _StarSize;
                float _StarBrightness;
                half4 _StarColorA;
                half4 _StarColorB;
                float _TwinkleSpeed;
                float _StarHorizonFade;
            CBUFFER_END

            // ----------------------------------------------------------------
            // 정점 셰이더 입력 / 출력
            // ----------------------------------------------------------------
            struct Attributes
            {
                float4 positionOS : POSITION;   // 스카이박스 메시의 정점 위치(오브젝트 공간)
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION; // 화면(클립 공간) 위치
                float3 dir        : TEXCOORD0;   // 이 픽셀이 가리키는 "방향"
            };

            // ----------------------------------------------------------------
            // Hash33 : 정수 칸 좌표 → 0~1 사이 난수 3개
            //   같은 칸에는 항상 같은 값이 나옵니다. (그래서 별이 깜빡이며 이동하지 않음)
            //   sin() 대신 frac/dot 만 써서 GPU 마다 결과가 달라지는 문제를 줄인 방식입니다.
            // ----------------------------------------------------------------
            float3 Hash33(float3 p)
            {
                p = frac(p * float3(0.1031, 0.1030, 0.0973));
                p += dot(p, p.yxz + 33.33);
                return frac((p.xxy + p.yxx) * p.zyx);
            }

            // ----------------------------------------------------------------
            // 별 그리기
            //   1) 방향 벡터에 Density 를 곱해 3D 공간을 큰 격자로 키웁니다.
            //   2) floor() 로 "몇 번째 칸인지", frac() 로 "칸 안의 어디인지" 를 구합니다.
            //   3) 칸마다 난수로 ① 별이 있는지 ② 별의 위치 ③ 밝기/색/반짝임 박자 를 정합니다.
            //   4) 픽셀과 별 위치 사이의 거리가 가까울수록 밝게 칠합니다.
            // ----------------------------------------------------------------
            float3 Stars(float3 dir)
            {
                float3 p     = dir * _StarDensity;
                float3 cell  = floor(p);   // 칸 번호 (정수)
                float3 local = frac(p);    // 칸 안에서의 위치 (0~1)

                float3 rndPos  = Hash33(cell);          // 별 위치용 난수
                float3 rndAttr = Hash33(cell + 71.37);  // 별 속성용 난수 (위치와 다른 값이 나오도록 칸 번호를 밀어 줌)

                // ① 확률보다 작을 때만 별이 존재 (step(a, b) = b >= a 이면 1, 아니면 0)
                float exists = step(rndAttr.x, _StarProbability);

                // ② 별 위치를 칸의 0.2~0.8 범위에 둡니다.
                //    가장자리에서 떨어뜨려야 별이 칸 경계에서 잘려 보이지 않습니다.
                //    (그래서 StarSize 최대값을 0.2 로 제한했습니다)
                float3 starPos = 0.2 + 0.6 * rndPos;

                // ④ 거리 → 밝기. 중심은 1, StarSize 만큼 떨어지면 0.
                float  dist  = length(local - starPos);
                float  shape = saturate(1.0 - dist / _StarSize);
                shape = shape * shape * shape;          // 세제곱: 중심만 쨍하고 가장자리는 빠르게 어두워짐

                // ③ 밝기는 별마다 다르게 (제곱하면 어두운 별이 많고 밝은 별이 드물어짐)
                float brightness = 0.2 + 0.8 * rndAttr.y * rndAttr.y;

                //    반짝임: 별마다 속도와 시작 시점(위상)이 다른 sin 파
                float twinkle = 0.6 + 0.4 * sin(_Time.y * _TwinkleSpeed * (0.5 + rndAttr.z)
                                                + rndAttr.z * 6.2831);

                //    색: 두 색 사이를 별마다 다르게 섞음
                float3 color = lerp(_StarColorA.rgb, _StarColorB.rgb, frac(rndAttr.z * 13.7));

                return color * (exists * shape * brightness * twinkle * _StarBrightness);
            }

            // ----------------------------------------------------------------
            // 정점 셰이더
            //   스카이박스 메시는 원점을 중심으로 한 공/큐브라서,
            //   정점의 오브젝트 위치가 곧 "원점에서 그 정점을 향하는 방향" 입니다.
            // ----------------------------------------------------------------
            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.dir        = input.positionOS.xyz;
                return output;
            }

            // ----------------------------------------------------------------
            // 프래그먼트(픽셀) 셰이더 — 실제 색을 계산하는 곳
            // ----------------------------------------------------------------
            half4 frag(Varyings input) : SV_Target
            {
                // 정점 사이에서 보간된 방향은 길이가 1이 아닐 수 있으므로 다시 정규화
                float3 dir = normalize(input.dir);
                float  h   = dir.y;   // 높이: 위 = 1, 수평선 = 0, 아래 = -1

                // ---- 1) 그라데이션 ----------------------------------------
                // pow 로 곡선을 휘게 합니다. Power 가 1보다 작으면
                // 수평선 색이 위쪽까지 넓게 퍼지고, 크면 금방 꼭대기 색으로 바뀝니다.
                float  upT      = pow(saturate(h), _GradientPower);
                float3 skyColor = lerp(_HorizonColor.rgb, _ZenithColor.rgb, upT);

                // 수평선 아래는 짧은 구간에서 GroundColor 로 빠르게 어두워짐
                float3 belowColor = lerp(_HorizonColor.rgb, _GroundColor.rgb, saturate(-h * 8.0));

                // h >= 0 이면 하늘색, 아니면 아래색 (step 으로 if 문 없이 고르기)
                float3 col = lerp(belowColor, skyColor, step(0.0, h));

                // ---- 2) 수평선 빛 -----------------------------------------
                // exp(-|h| * k) : h = 0(수평선)에서 1, 멀어질수록 0 으로 빠르게 줄어드는 곡선.
                // k(Sharpness)가 클수록 더 빨리 줄어들어 얇은 띠가 됩니다.
                float glow = exp(-abs(h) * _GlowSharpness);
                col += _GlowColor.rgb * glow * _GlowIntensity;

                // ---- 3) 별 -----------------------------------------------
                // 수평선 근처에서는 두꺼운 대기 때문에 별이 흐려진다고 가정하고 서서히 지웁니다.
                float starMask = smoothstep(0.0, _StarHorizonFade, h);
                col += Stars(dir) * starMask;

                return half4(col, 1.0);
            }
            ENDHLSL
        }
    }

    Fallback Off
}
