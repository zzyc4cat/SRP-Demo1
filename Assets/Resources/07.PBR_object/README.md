# 07.PBR_object — glTF PBR（BRDF）效果展示

URP 下基于 **glTF 2.0 Metallic-Roughness** 工作流的 Cook-Torrance BRDF 教学 / 测试场景。  
全部演示物体使用 Unity 内置 **Sphere**，贴图通道与参数语义对齐 glTF 规范。

| 项 | 说明 |
|----|------|
| 场景 | `Assets/Scenes/07.PBR_object.unity` |
| 不透明 Shader | `Custom/URP_glTF_PBR` |
| 透射 Shader | `Custom/URP_glTF_PBR_Transmission` |
| 公共库 | `Shaders/Library/glTFPBRCommon.hlsl` |
| 一键搭建 | 菜单 `SRP Demo → PBR Object → Setup Scene` |

技术入口见仓库根目录 [README.md](../../../README.md)，工程总览见 [Assets/README.md](../../README.md)。

---

## 目录结构

```
07.PBR_object/
├── Shaders/
│   ├── URP_glTF_PBR.shader                 # 不透明：Metal-Rough / Specular / Normal
│   ├── URP_glTF_PBR_Transmission.shader    # 透射：玻璃 / 液体
│   └── Library/glTFPBRCommon.hlsl          # BRDF 全部分段实现
├── Materials/                              # 梯度球 / Specular / Normal / Transmission 材质
├── Textures/                               # BaseColor · MetallicRoughness · Normal · AO 等
├── Scripts/ · Prefabs/
└── README.md                               # 本文件
```

编辑器工具：`Assets/Editor/PBRObjectDemoSetup.cs`

---

## 测试点一览

| 场景组 | 测试目标 | 观感要点 |
|--------|----------|----------|
| **MetalRoughnessGrid_5×5** | 金属度 × 粗糙度全组合 | 左→右金属度 0→1；上→下粗糙度 0→1 |
| **SpecularTest** | 高光 BRDF 形状 / 强度 / 边缘 | 金属金、电介质白扫掠；Debug 球隔离 D / Fresnel |
| **NormalTangentMirrorTest** | 切线空间法线正确性 | BumpScale 0 / 0.5 / 1 / 2 + 镜面平面 |
| **TransmissionRoughnessTest** | 透射 BRDF（玻璃 / 液体） | 透射度 × 粗糙度矩阵 + 染色液体球 |

### Metal-Roughness 梯度阵列

```
        M=0 ──────────────► M=1
R=0  ● ● ● ● ●     上：镜面高光尖、环境倒影清晰
 │   ● ● ● ● ●
 │   ● ● ● ● ●     左：电介质（漫反射明显）
 │   ● ● ● ● ●     右：金属（漫反射衰减，F0=BaseColor）
R=1  ● ● ● ● ●     下：高光展宽变暗、倒影模糊
```

---

## 快速使用

1. 打开 `Assets/Scenes/07.PBR_object.unity`，进入 Play。
2. 若需重建：`SRP Demo → PBR Object → Setup Scene`（会覆盖该场景）。
3. 仅重生成贴图：`SRP Demo → PBR Object → Generate Textures Only`。

**透射建议**：URP Asset 开启 **Opaque Texture**（本工程已开），以便屏幕空间折射。

---

## Shader 与 Pass

### 不透明 `Custom/URP_glTF_PBR`

| Pass | LightMode | 作用 |
|------|-----------|------|
| ForwardLit | `UniversalForward` | 全通道 PBR 着色 |
| ShadowCaster | `ShadowCaster` | 阴影（本地 Bias，不依赖 `Shadows.hlsl`） |
| DepthOnly | `DepthOnly` | 深度预通道 |

### 透射 `Custom/URP_glTF_PBR_Transmission`

| Pass | 队列 / 混合 | 作用 |
|------|-------------|------|
| ForwardTransmission | Transparent · `One OneMinusSrcAlpha` | 高光保留 + 折射透射 + 体积衰减 |

---

## 贴图通道（glTF）

| 贴图 | 通道 | 语义 |
|------|------|------|
| BaseColor | RGB · A | 固有色 · 不透明度 |
| MetallicRoughness | **G** · **B** | **Roughness** · **Metallic**（R 未定义） |
| Normal | TS XYZ | 切线空间，OpenGL +Y；`BumpScale` = glTF scale |
| Occlusion | **R** | AO；`OcclusionStrength` 混回 1 |
| Emission | RGB | 自发光 × HDR Factor |

核心换算：

```
F0           = lerp(0.04, baseColor, metallic)
diffuseColor = baseColor * (1 - metallic)
roughness α  = perceptualRoughness²
```

---

## BRDF 管线（库内十段）

公共实现均在 `glTFPBRCommon.hlsl`，按效果分段注释。

| # | 模块 | 函数 / 要点 | 对应测试 |
|---|------|-------------|----------|
| 1 | 数学工具 | `Pow5` · `α = r²` | — |
| 2 | Fresnel | Schlick（直接光）· 粗糙度修正（IBL） | Specular 边缘 |
| 3 | 高光 BRDF | GGX **D** · Smith **G** · **F** → Cook-Torrance | Specular 形状 / 强度 |
| 4 | 漫反射 | Lambert / π · 金属时趋近 0 | Metal 梯度 |
| 5 | 法线 | TBN · `UnpackNormalScale` | Normal-Tangent |
| 6 | 表面采样 | 贴图 × Factor → `GltfSurfaceData` | 全通道 |
| 7 | 直接光 | 主光 + 附加光 · `(diff·(1-F) + spec) · NdotL` | 阵列整体 |
| 8 | 环境 IBL | SH 漫反射 + Cubemap mip(roughness) · × AO | 倒影清晰度 |
| 9 | 透射 | `refract` · mip 模糊 · 屏幕折射 · Beer-Lambert | Transmission |
| 10 | Debug / 入口 | `GltfApplyDebug` · `GltfEvaluateLighting` | SpecularTest |

片元调用顺序：

```
采样表面 → 法线贴图 → 直接光 → IBL → 透射 → 自发光 → Debug → Fog / Alpha
```

---

## Debug Mode（SpecularTest）

材质 `_DebugMode`：

| 值 | 显示 | 用途 |
|----|------|------|
| 0 | Full | 完整光照 |
| 1 | Specular Only | 高光瓣 |
| 2 | Diffuse Only | 漫反射（金属应变暗） |
| 3 | D_GGX | 高光几何形状 |
| 4 | Fresnel | 掠射边缘 |
| 5~10 | Metal / Rough / N / AO / Base / F0 | 通道核对 |

---

## 透射参数（KHR 风格）

| 参数 | 作用 |
|------|------|
| `_TransmissionFactor` | 透射比例 0→1 |
| `_ThicknessFactor` | 体积厚度 |
| `_AttenuationColor` / `_AttenuationDistance` | 液体 / 染色玻璃吸收 |
| `_IOR` | 折射弯折 |
| `_RefractionStrength` | 屏幕折射偏移 |
| `_TransmissionRoughnessBoost` | 额外磨砂 |

能量约定：透射只带走 `(1 - F) * transmission`，表面仍保留镜面反射。

---

## 场景布局（示意）

```
Z≈0   MetalRoughnessGrid_5×5     SpecularTest
Z≈5.5 NormalTangentMirrorTest    TransmissionRoughnessTest
      + Ground 棋盘 · Directional/Fill · Reflection Probe
```

---

## 相关文件

| 路径 | 说明 |
|------|------|
| `Assets/Scenes/07.PBR_object.unity` | 演示场景 |
| `Assets/Editor/PBRObjectDemoSetup.cs` | 贴图 / 材质 / 场景一键生成 |
| `Assets/Pipelines/New Universal Render Pipeline Asset.asset` | Opaque Texture（透射折射） |
