// 바다용 촘촘한 평면 메시를 만들어 MeshFilter 에 넣는다. (갤러리 C1 의 WaterSurfaceGrid 를 간단히 줄인 버전)
// Unity 기본 Plane 은 칸이 10 개뿐이라, 정점을 움직이는 파도가 각진 선으로 보인다.
// 사용법: 빈 GameObject 에 붙이고, MeshRenderer 에 AlienOcean 머티리얼을 넣는다.
using UnityEngine;

[ExecuteAlways]
[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class AlienOceanGrid : MonoBehaviour
{
    [Tooltip("바다 한 변의 길이 (m)")]
    [SerializeField, Min(1f)] float size = 200f;

    [Tooltip("한 변의 칸 수. 많을수록 파도가 매끈하지만 무거워진다. (254 가 최대)")]
    [SerializeField, Range(10, 254)] int cells = 254;

    [Tooltip("1 = 칸 간격이 모두 같음. 클수록 가운데(카메라 근처)는 촘촘하고 가장자리(수평선)는 성글어진다.\n" +
             "수평선까지 닿는 넓은 바다를 칸 수를 늘리지 않고 만들 때 쓴다.")]
    [SerializeField, Range(1f, 4f)] float centerDensity = 1f;

    Mesh mesh;
    bool dirty;

    void OnEnable() { Build(); }

    // 인스펙터 값을 바꾸면 불린다. 여기서 바로 메시를 바꾸면 Unity 가 경고하므로, 표시만 하고 Update 에서 만든다.
    void OnValidate()
    {
        dirty = true;
#if UNITY_EDITOR
        UnityEditor.EditorApplication.QueuePlayerLoopUpdate();  // 편집 모드에서도 곧바로 Update 가 한 번 돌게 한다
#endif
    }

    void Update()
    {
        if (dirty) Build();
    }

    void Build()
    {
        dirty = false;
        if (mesh == null)
        {
            // DontSave : 씬 파일에 메시를 저장하지 않고, 켤 때마다 새로 만든다.
            mesh = new Mesh { name = "AlienOceanGrid", hideFlags = HideFlags.DontSave };
        }

        int n = cells + 1;                       // 한 줄의 정점 수
        var positions = new Vector3[n * n];
        var uvs       = new Vector2[n * n];

        // 정점: 가운데가 원점이 되도록 -size/2 ~ +size/2 에 놓는다.
        for (int z = 0; z < n; z++)
        {
            for (int x = 0; x < n; x++)
            {
                float u = x / (float)cells;
                float v = z / (float)cells;
                positions[z * n + x] = new Vector3(Spread(u) * size * 0.5f, 0f, Spread(v) * size * 0.5f);
                uvs[z * n + x]       = new Vector2(u, v);
            }
        }

        // 삼각형: 칸 하나 = 삼각형 2개 = 정점 번호 6개. 위에서 볼 때 시계 방향이어야 앞면이 위를 향한다.
        var indices = new int[cells * cells * 6];
        int k = 0;
        for (int z = 0; z < cells; z++)
        {
            for (int x = 0; x < cells; x++)
            {
                int a = z * n + x;   // 왼쪽 아래
                int b = a + n;       // 왼쪽 위
                int c = a + 1;       // 오른쪽 아래
                int d = b + 1;       // 오른쪽 위
                indices[k++] = a; indices[k++] = b; indices[k++] = c;
                indices[k++] = c; indices[k++] = b; indices[k++] = d;
            }
        }

        mesh.Clear();
        mesh.vertices  = positions;
        mesh.uv        = uvs;
        mesh.triangles = indices;
        mesh.RecalculateNormals();

        // 셰이더가 정점을 위아래로 밀기 때문에, 경계 상자를 넉넉히 키워 둔다.
        // (작으면 카메라가 "화면 밖" 이라고 오해해서 바다가 사라질 수 있다)
        mesh.bounds = new Bounds(Vector3.zero, new Vector3(size, 10f, size));

        GetComponent<MeshFilter>().sharedMesh = mesh;
    }

    // 0~1 → -1~1 로 바꾸되, 거듭제곱으로 가운데를 촘촘하게 모은다.
    // 예) centerDensity = 3 이면 가운데 10% 칸이 실제로는 0.1% 거리 안에 들어간다 → 카메라 근처 파도가 매끈하다.
    float Spread(float t)
    {
        float s = t * 2f - 1f;                                   // -1 ~ 1
        return Mathf.Sign(s) * Mathf.Pow(Mathf.Abs(s), centerDensity);
    }

    void OnDestroy()
    {
        // 코드로 만든 메시는 직접 지워야 메모리에 남지 않는다.
        if (mesh == null) return;
        if (Application.isPlaying) Destroy(mesh);
        else DestroyImmediate(mesh);
    }
}
