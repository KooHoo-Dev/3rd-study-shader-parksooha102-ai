// ============================================================================
//  BlackHole — 멀리 떠 있는 블랙홀
// ----------------------------------------------------------------------------
//  [바탕으로 한 갤러리 항목]
//    F1 SDF 도형    : "중심에서의 거리" 하나로 원과 고리를 그리는 방법
//    D3 충격파 왜곡 : 화면 사진(Opaque Texture)을 밀린 좌표로 읽어 뒤 장면을 휘게 하는 방법
//
//  [갤러리에서 바꾸거나 더한 것]
//    - 충격파는 "고리 하나" 만 바깥으로 밀지만, 여기서는 원 전체를 "중심 쪽으로 당겨"
//      돋보기처럼 뒤쪽 하늘이 늘어나 보이게 했다. (중력 렌즈 흉내)
//    - 충격파는 화면 전체에 거는 후처리지만, 여기서는 Quad 한 장 위에서만 휘게 했다.
//    - SDF 원과 고리를 겹쳐 그림자, 빛 고리, 빙글빙글 도는 강착원반을 만들었다.
//
//  [셰이더를 처음 본다면]
//    셰이더는 "화면의 픽셀 하나하나마다 실행되는 작은 함수" 입니다.
//    맨 아래 frag() 가 "이 픽셀은 무슨 색이야?" 에 답하는 곳이에요. 위에서 아래로 1, 2, 3 … 순서대로 읽으면 됩니다.
//
//  [핵심 아이디어는 딱 하나]
//    r = "이 픽셀이 블랙홀 중심에서 얼마나 떨어져 있나"
//      r = 0 → 한가운데,  r = 1 → 네모 판의 가장자리
//
//  [사용법]
//    1) GameObject > 3D Object > Quad 를 만들고 이 머티리얼을 넣습니다. (Mesh Collider 는 지워도 됨)
//    2) Quad 를 바다 너머 멀리 두고, Rotation 을 카메라의 Rotation 과 똑같이 맞춥니다.
//    3) URP 설정(PC_RPAsset)의 Opaque Texture 가 켜져 있어야 렌즈가 보입니다. (켜 두었음)
// ============================================================================

Shader "MyShaders/BlackHole"
{
    // Range(최소, 최대) = 슬라이더,  Color = 색,  [HDR] = 1 보다 밝은 색 허용 (Bloom 으로 빛이 번짐)
    Properties
    {
        [Header(Shadow)]
        _ShadowRadius ("그림자 크기", Range(0.05, 0.4)) = 0.18

        [Header(Lens)]
        _LensStrength ("렌즈 세기 (뒤쪽 하늘이 휘는 정도)", Range(0, 0.9)) = 0.5

        [Header(Light Ring)]
        [HDR] _RingColor ("빛 고리 색", Color) = (4, 3, 2.2, 1)
        _RingWidth       ("빛 고리 두께", Range(0.002, 0.05)) = 0.01

        [Header(Disk)]
        [HDR] _DiskInnerColor ("원반 안쪽 색", Color) = (6, 4.2, 2.6, 1)
        [HDR] _DiskOuterColor ("원반 바깥쪽 색", Color) = (2.2, 0.6, 0.15, 1)
        _DiskInner   ("원반 안쪽 반지름", Range(0.1, 0.6)) = 0.26
        _DiskOuter   ("원반 바깥쪽 반지름", Range(0.3, 1.0)) = 0.85
        _DiskTilt    ("원반 기울기 (작을수록 납작)", Range(0.05, 1)) = 0.2
        _DiskSpeed   ("원반 도는 속도", Range(0, 5)) = 1
        _StreakCount ("원반 줄무늬 개수", Range(1, 30)) = 12
    }

    SubShader
    {
        // 투명(Transparent) 순서로 그린다.
        //   URP 는 하늘과 불투명 물체를 다 그린 뒤 그 화면을 사진처럼 복사해 둔다(Opaque Texture).
        //   투명 물체는 그 다음에 그려지니, 블랙홀은 그 사진을 가져와 휘게 할 수 있다.
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" "RenderPipeline" = "UniversalPipeline" }

        Blend SrcAlpha OneMinusSrcAlpha  // 알파를 쓴다 → 네모 판의 모서리를 투명하게 지울 수 있음
        ZWrite Off                       // 투명 물체는 보통 깊이를 쓰지 않는다
        Cull Off                         // 판의 앞뒷면 모두 그림

        Pass
        {
            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            // SampleSceneColor(uv) : 복사해 둔 화면 사진에서 색을 읽는 함수
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            // Properties 의 값을 코드에서 쓰려면 같은 이름으로 한 번 더 적는다. (SRP Batcher 호환)
            CBUFFER_START(UnityPerMaterial)
                float  _ShadowRadius;
                float  _LensStrength;
                float4 _RingColor;
                float  _RingWidth;
                float4 _DiskInnerColor;
                float4 _DiskOuterColor;
                float  _DiskInner;
                float  _DiskOuter;
                float  _DiskTilt;
                float  _DiskSpeed;
                float  _StreakCount;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;   // 정점 위치
                float2 uv         : TEXCOORD0;  // 판의 왼쪽 아래 (0,0) ~ 오른쪽 위 (1,1)
            };

            struct Varyings
            {
                float4 positionCS      : SV_POSITION;
                float2 uv              : TEXCOORD0;
                float4 screenPos       : TEXCOORD1;  // 이 픽셀이 화면 어디에 있나
                float4 centerScreenPos : TEXCOORD2;  // 블랙홀 중심이 화면 어디에 있나
            };

            // ----------------------------------------------------------------
            // SDF 고리 (갤러리 D3 의 shockwaveRing 과 같은 식)
            //   abs(거리 - 반지름) = 고리 선에서 얼마나 떨어졌나
            //   선 위면 1, 두께만큼 떨어지면 0
            // ----------------------------------------------------------------
            float Ring(float dist, float radius, float width)
            {
                return 1.0 - smoothstep(0.0, width, abs(dist - radius));
            }

            // ----------------------------------------------------------------
            // 강착원반 : 블랙홀 둘레를 도는 빛나는 가스 고리
            //   q 는 납작한 타원을 동그랗게 편 좌표 (frag 의 3단계 참고)
            // ----------------------------------------------------------------
            float3 Disk(float2 q)
            {
                float dist = length(q);

                // 1. 고리 모양: 안쪽 반지름보다 바깥이면서, 바깥 반지름보다 안쪽인 곳만 1
                //    smoothstep(a, b, x) : x ≤ a 면 0, x ≥ b 면 1, 사이는 부드럽게
                float outsideInner = smoothstep(_DiskInner, _DiskInner + 0.03, dist);
                float insideOuter  = 1.0 - smoothstep(_DiskOuter - 0.3, _DiskOuter, dist);
                float shape = outsideInner * insideOuter;

                // 2. 색: 안쪽(뜨거움)은 하얗게, 바깥은 주황으로
                //    lerp(A, B, t) : t=0 이면 A, t=1 이면 B, 사이는 섞은 색 / saturate : 0~1 로 자르기
                float t = saturate((dist - _DiskInner) / (_DiskOuter - _DiskInner));
                float3 color = lerp(_DiskInnerColor.rgb, _DiskOuterColor.rgb, t);

                // 3. 도는 줄무늬: atan2 로 각도를 구하고 sin(각도 × 개수) 로 원을 따라 줄을 만든다.
                //    + dist × 20 은 줄을 비틀어 소용돌이로, - 시간 × 속도 는 줄을 돌린다.
                //    개수를 round 로 정수로 만들어야 각도가 한 바퀴 도는 지점에서 줄이 끊기지 않는다.
                float angle   = atan2(q.y, q.x);
                float streaks = sin(angle * round(_StreakCount) + dist * 20.0 - _Time.y * _DiskSpeed) * 0.5 + 0.5;

                return color * shape * (0.4 + 0.6 * streaks);
            }

            // 정점 셰이더 : 판을 화면 위치로 옮긴다 (거의 모든 셰이더에 있는 기본 코드)
            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS      = TransformObjectToHClip(input.positionOS.xyz);
                output.uv              = input.uv;
                output.screenPos       = ComputeScreenPos(output.positionCS);
                output.centerScreenPos = ComputeScreenPos(TransformObjectToHClip(float3(0, 0, 0))); // 판의 중심 = 블랙홀 중심
                return output;
            }

            // 픽셀 셰이더 : "이 픽셀은 무슨 색?"
            float4 frag(Varyings input) : SV_Target
            {
                // 1. 중심 거리: uv(0~1) 를 ×2-1 해서 중심이 0 이 되게 하고, 길이를 잰다.
                //    (갤러리 D3 은 화면이 가로로 길어서 화면비를 곱했지만, Quad 의 uv 는 정사각형이라 필요 없다)
                float2 p = input.uv * 2.0 - 1.0;
                float  r = length(p);

                // 2. 렌즈: 화면 사진을 읽는 위치를 중심 쪽으로 당긴다.
                //    가운데일수록 많이 당겨서 가운데 하늘이 크게 늘어나 보인다 (돋보기).
                //    가장자리(r = 1)에서는 0 이라 판 바깥과 이음매 없이 이어진다.
                //    (갤러리 D3 은 "uv - offset" 으로 고리 위만 바깥으로 밀었다. 여기서는 원 전체를 안쪽으로 당긴다)
                float2 screenUV = input.screenPos.xy       / input.screenPos.w;
                float2 centerUV = input.centerScreenPos.xy / input.centerScreenPos.w;
                float  pull     = _LensStrength * (1.0 - saturate(r));
                float3 col      = SampleSceneColor(lerp(screenUV, centerUV, pull));

                // 3. 원반 좌표: 원반은 비스듬히 누워 납작한 타원으로 보인다.
                //    y 를 기울기로 나누면 타원이 원으로 펴져서 Disk() 가 원으로 계산할 수 있다.
                float2 q = float2(p.x, p.y / _DiskTilt);

                // 4. 원반 뒤쪽 절반: 화면 위쪽(p.y > 0)은 블랙홀 "뒤" 를 지난다. 다음 단계의 그림자에 가려진다.
                //    step(0, p.y) : p.y ≥ 0 이면 1, 아니면 0
                col += Disk(q) * step(0.0, p.y);

                // 5. 그림자 (SDF 원): r 이 반지름보다 작으면 0 을 곱해 검게 칠한다.
                col *= smoothstep(_ShadowRadius - 0.005, _ShadowRadius + 0.005, r);

                // 6. 빛 고리 (SDF 고리): 그림자 테두리에 얇고 밝은 링을 더한다.
                col += _RingColor.rgb * Ring(r, _ShadowRadius, _RingWidth);

                // 7. 원반 앞쪽 절반: 화면 아래쪽(p.y < 0)은 블랙홀 "앞" 을 지난다.
                //    그림자보다 나중에 더하니까 검은 원 위로 원반이 지나가 보인다.
                col += Disk(q) * step(p.y, 0.0);

                // 최종: 네모 판의 모서리는 투명하게 → 동그란 모양만 남는다.
                float alpha = 1.0 - smoothstep(0.9, 1.0, r);
                return float4(col, alpha);
            }
            ENDHLSL
        }
    }

    Fallback Off
}
