// ============================================================================
//  ReplicatingCrystal — 자기 복제 분자에 잠식되어 가는 외계 수정
// ----------------------------------------------------------------------------
//  [바탕으로 한 갤러리 항목]
//    A2 프레넬 림 빛 : 비스듬히 보이는 가장자리만 밝힌다 → 수정의 반짝이는 테두리
//    B1 디졸브       : 노이즈와 임계값으로 경계를 만들고, 경계 바로 옆 띠를 빛나게 한다 → 번져 가는 감염 경계
//
//  [갤러리에서 바꾸거나 더한 것]
//    - 디졸브는 경계 너머를 "지우지만"(구멍), 여기서는 지우지 않고 "다른 재질로 바꾼다"(감염).
//    - 디졸브의 임계값 슬라이더 대신, 감염 경계가 바닥에서 꼭대기로 스스로 올라가고,
//      그 뒤를 회복 경계가 똑같이 아래에서 위로 쓸어 올리며 수정을 되돌린다.
//    - 세포 분열(추가) : 감염된 곳에 빛나는 점(분자)들이 둘로 갈라지기를 반복한다.
//    - 군체 연출(추가) : 수정마다 놓인 위치가 다르면 감염 시점도 달라져, 여러 개를 놓으면 번식 중인 군체처럼 보인다.
//    - 단계 보기(추가) : 인스펙터에서 중간 계산값을 화면에 띄워 볼 수 있다.
//
//  [핵심 아이디어]
//    "이 픽셀의 높이(y) 가 감염 경계보다 아래인가?" → 아래면 감염, 위면 순수한 수정
//    UV 대신 오브젝트 공간 위치를 쓰므로, 받아 온 메시의 UV 가 엉망이어도 무늬가 깨지지 않는다.
// ============================================================================

Shader "MyShaders/ReplicatingCrystal"
{
    Properties
    {
        [Header(Crystal)]
        _BaseColor          ("수정 색", Color) = (0.55, 0.85, 0.95, 1)
        [HDR] _RimColor     ("림 색", Color) = (0.6, 1.5, 2.0, 1)
        _RimPower           ("림 좁히기 (클수록 얇음)", Range(0.5, 8)) = 3
        _RimIntensity       ("림 세기", Range(0, 4)) = 1

        [Header(Infection Spread)]
        _HeightMin          ("수정 바닥 높이 (오브젝트 y)", Float) = 0
        _HeightMax          ("수정 꼭대기 높이 (오브젝트 y)", Float) = 2.5
        _SpreadSpeed        ("번지는 속도 (1초에 감염→회복 몇 번)", Range(0, 0.5)) = 0.08
        _PhaseOffset        ("시작 시점 밀기", Range(0, 1)) = 0
        _NoiseScale         ("경계 울퉁불퉁 크기", Range(0.5, 10)) = 3
        _FrontNoise         ("경계 울퉁불퉁 세기", Range(0, 1)) = 0.4
        [HDR] _EdgeColor    ("경계 발광 색", Color) = (3, 1, 2.5, 1)
        _EdgeWidth          ("경계 발광 두께", Range(0.01, 0.5)) = 0.12

        [Header(Replicating Cells)]
        _InfectedColor      ("감염된 수정 색", Color) = (0.25, 0.05, 0.3, 1)
        [HDR] _CellColor    ("분자 색", Color) = (2.5, 0.4, 1.8, 1)
        _CellDensity        ("분자 촘촘함", Range(1, 20)) = 6
        _CellSize           ("분자 크기", Range(0.05, 0.24)) = 0.18
        _SplitSpeed         ("분열 속도", Range(0, 3)) = 0.5

        [Header(Debug)]
        [Enum(Final,0, Lighting,1, Rim,2, Infected,3, Edge,4, Cells,5)] _DebugStep ("단계 보기", Float) = 0
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"  // GetMainLight(), SampleSH()

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _RimColor;
                float  _RimPower;
                float  _RimIntensity;
                float  _HeightMin;
                float  _HeightMax;
                float  _SpreadSpeed;
                float  _PhaseOffset;
                float  _NoiseScale;
                float  _FrontNoise;
                float4 _EdgeColor;
                float  _EdgeWidth;
                float4 _InfectedColor;
                float4 _CellColor;
                float  _CellDensity;
                float  _CellSize;
                float  _SplitSpeed;
                float  _DebugStep;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionOS : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS   : TEXCOORD2;
            };

            // ----------------------------------------------------------------
            // 갤러리 B1 디졸브에서 가져온 도우미 함수 2개
            // ----------------------------------------------------------------

            // 격자 칸마다 고정된 난수 (같은 칸은 항상 같은 값)
            float Hash(float3 p)
            {
                p = frac(p * 0.1031);
                p = p + dot(p, p.zyx + 31.32);
                return frac((p.x + p.y) * p.z);
            }

            // 3D 값 노이즈 : 격자 꼭짓점 8개의 난수를 부드럽게 섞어 구름 같은 얼룩을 만든다. 결과는 0~1.
            float ValueNoise(float3 p)
            {
                float3 cell = floor(p);
                float3 f = frac(p);
                f = f * f * (3.0 - 2.0 * f);
                float x00 = lerp(Hash(cell + float3(0, 0, 0)), Hash(cell + float3(1, 0, 0)), f.x);
                float x10 = lerp(Hash(cell + float3(0, 1, 0)), Hash(cell + float3(1, 1, 0)), f.x);
                float x01 = lerp(Hash(cell + float3(0, 0, 1)), Hash(cell + float3(1, 0, 1)), f.x);
                float x11 = lerp(Hash(cell + float3(0, 1, 1)), Hash(cell + float3(1, 1, 1)), f.x);
                return lerp(lerp(x00, x10, f.y), lerp(x01, x11, f.y), f.z);
            }

            // ----------------------------------------------------------------
            // 세포 분열 무늬 (추가)
            //   1) 공간을 작은 정육면체 칸으로 나눈다.
            //   2) 칸 가운데에 점(분자)이 하나 있다.
            //   3) 시간이 지나면 점이 좌우로 갈라져 두 개가 된다 → 끝나면 처음부터 반복.
            //   칸마다 난수로 시작 시점을 다르게 해서, 모든 점이 한꺼번에 갈라지지 않게 한다.
            // ----------------------------------------------------------------
            float Cells(float3 positionOS)
            {
                float3 p     = positionOS * _CellDensity;
                float3 id    = floor(p);          // 몇 번째 칸인지
                float3 local = frac(p) - 0.5;     // 칸 안의 위치 (가운데가 0)

                // cycle : 0 → 1 로 흐르고 다시 0 으로 (분열 한 번)
                float cycle = frac(_Time.y * _SplitSpeed + Hash(id));

                // 두 점의 위치 : 가운데에서 시작해 좌우로 0.25 까지 벌어진다
                float  gap  = cycle * 0.25;
                float  dA   = length(local - float3(gap, 0, 0));
                float  dB   = length(local + float3(gap, 0, 0));
                float  dist = min(dA, dB);        // 둘 중 가까운 점까지의 거리

                // 점 모양 : 가까우면 1, CellSize 보다 멀면 0
                float dots = 1.0 - smoothstep(_CellSize * 0.6, _CellSize, dist);

                // 반복 시작/끝에서 점이 툭 튀지 않게, 사이클 중간에 가장 밝고 양 끝에서 사라지게 한다
                return dots * sin(cycle * PI);
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionOS = input.positionOS.xyz;
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                output.normalWS   = TransformObjectToWorldNormal(input.normalOS);
                return output;
            }

            float4 frag(Varyings input) : SV_Target
            {
                float3 normalWS = normalize(input.normalWS);
                float3 viewWS   = GetWorldSpaceNormalizeViewDir(input.positionWS);
                Light  light    = GetMainLight();

                // 1. 조명 : 빛을 정면으로 받는 면은 밝고, 등진 면은 어둡다 (램버트).
                //    SampleSH 는 주변 환경(하늘)에서 오는 은은한 빛이다. 그늘이 새까맣게 되지 않게 해 준다.
                float3 lighting = light.color * saturate(dot(normalWS, light.direction)) + SampleSH(normalWS);

                // 2. 림 (갤러리 A2) : 정면은 0, 윤곽으로 갈수록 1 → 거듭제곱으로 윤곽 근처만 남긴다.
                float rim = pow(max(1.0 - saturate(dot(normalWS, viewWS)), 0.0001), _RimPower) * _RimIntensity;

                // 3. 감염 경계 두 개 (갤러리 B1 을 응용)
                //    경계 A (감염) : 바닥에서 꼭대기로 올라가며 수정을 감염시킨다.
                //    경계 B (회복) : A 를 뒤따라 바닥에서 꼭대기로 올라가며 수정을 원래대로 되돌린다.
                //    "A 보다 아래 그리고 B 보다 위" 인 곳만 감염 상태다.
                //
                //    cycle : 0 → 1 로 흐르다가 다시 0 으로 돌아가는 시간 (frac)
                //      0   ~ 0.5 : A 가 올라간다 (riseA 0 → 1), B 는 바닥에서 기다림
                //      0.5 ~ 1   : B 가 올라간다 (riseB 0 → 1), A 는 꼭대기 위에서 기다림
                //    cycle 이 1 → 0 으로 튀는 순간, 두 경계 모두 수정 바깥에 있어 화면에는 변화가 없다.
                //
                //    (흔한 실수: 경계 하나를 frac(...) 로 올리기만 하면, 꼭대기에 닿은 다음 프레임에 바닥으로 튀어서
                //     다 감염된 수정이 한순간에 깨끗한 색으로 바뀐다. 회복도 경계로 "쓸어 올리면" 끊기는 순간이 없다)
                //
                //    수정의 월드 위치로 시작 시점을 조금씩 다르게 해서, 여러 개를 놓으면 서로 다른 단계에 있게 된다.
                float3 objectWS  = TransformObjectToWorld(float3(0, 0, 0));
                float  autoPhase = frac(dot(objectWS, float3(0.173, 0.0, 0.271)));
                float  cycle     = frac(_Time.y * _SpreadSpeed + _PhaseOffset + autoPhase);
                float  riseA     = saturate(cycle * 2.0);         // 앞 절반 동안 0 → 1
                float  riseB     = saturate(cycle * 2.0 - 1.0);   // 뒤 절반 동안 0 → 1

                //    경계 높이 : 바닥보다 조금 아래 ~ 꼭대기보다 조금 위까지 올라간다 (완전히 깨끗한 순간과 다 잠긴 순간이 생기게)
                //    노이즈로 경계를 울퉁불퉁하게 만든다. 두 경계의 모양이 같지 않도록 B 는 노이즈를 다른 자리에서 읽는다.
                float  bottom = _HeightMin - 0.3;
                float  top    = _HeightMax + 0.3;
                float  noiseA = ValueNoise(input.positionOS * _NoiseScale);
                float  noiseB = ValueNoise(input.positionOS * _NoiseScale + 17.3);
                float  frontA = lerp(bottom, top, riseA) + (noiseA - 0.5) * _FrontNoise;
                float  frontB = lerp(bottom, top, riseB) + (noiseB - 0.5) * _FrontNoise;

                //    dA : 감염 경계보다 얼마나 아래에 있나 (양수 = 감염된 쪽)
                //    dB : 회복 경계보다 얼마나 위에 있나   (양수 = 아직 회복 안 된 쪽)
                float dA       = frontA - input.positionOS.y;
                float dB       = input.positionOS.y - frontB;
                float infected = step(0.0, dA) * step(0.0, dB);

                // 4. 경계 발광 (갤러리 B1 과 같은 식) : 두 경계 각각 감염된 쪽으로 EdgeWidth 만큼의 띠만 1
                float edgeA = 1.0 - smoothstep(0.0, _EdgeWidth, dA);
                float edgeB = 1.0 - smoothstep(0.0, _EdgeWidth, dB);
                float edge  = infected * max(edgeA, edgeB);

                // 5. 세포 분열 무늬 (감염된 곳에서만 보인다)
                float cells = Cells(input.positionOS) * infected;

                // 단계 보기
                if (_DebugStep == 1) return float4(lighting, 1);
                if (_DebugStep == 2) return float4(rim.xxx, 1);
                if (_DebugStep == 3) return float4(infected.xxx, 1);
                if (_DebugStep == 4) return float4(edge.xxx, 1);
                if (_DebugStep == 5) return float4(cells.xxx, 1);

                // 최종
                //   순수한 수정 : 수정 색 × 조명 + 림
                //   감염된 수정 : 어두운 보라 × 조명 + 빛나는 분자 + 약한 림
                //   lerp 로 둘 중 하나를 고르고, 마지막으로 경계 띠를 발광 색으로 덮는다.
                float3 pureColor     = _BaseColor.rgb * lighting + _RimColor.rgb * rim;
                float3 infectedColor = _InfectedColor.rgb * lighting + _CellColor.rgb * cells + _RimColor.rgb * rim * 0.5;
                float3 color = lerp(pureColor, infectedColor, infected);
                color = lerp(color, _EdgeColor.rgb, edge);
                return float4(color, 1);
            }
            ENDHLSL
        }
    }

    Fallback Off
}
