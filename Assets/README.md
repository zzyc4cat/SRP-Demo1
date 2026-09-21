# SRP Demo1 — 渲染效果技术总结

| 项 | 说明 |
|----|------|
| 工程 | SRP Demo1 |
| 引擎 | Unity 2022.3.62f3 LTS |
| 管线 | URP 14.0.12 |
| 范围 | 角色 · 草地 · Gerstner 水面 · FFT 海洋 · 毛发 · 自定义后处理 · 特效（06） · **PBR 物体（07）** |
| 入口 | 仓库根目录 [README.md](../README.md) |

---

## 1. 总体架构

本工程在 **URP Forward** 下用自定义 HLSL / Compute / RenderFeature 实现多套互不绑死的表现方案，共享主光与阴影约定。

```
Assets/
├── Resources/
│   ├── 01.Character/
│   ├── 02.Grass/
│   ├── 03.water/              # Gerstner 水面、平面反射、焦散
│   ├── 03.gpu_FFT_Ocean/      # GPU FFT 海洋（三频带 Tessendorf）
│   ├── 04.Fur/
│   ├── 05.renderfeature/      # 后处理 Shader
│   ├── 06.effect/             # 流光 / 管道 / 溶解 / 火焰 / 护盾
│   └── 07.PBR_object/         # glTF Metal-Rough BRDF 展示
├── Pipelines/Features/        # 后处理 Feature / Pass / Manager
└── Scenes/
```

共性选型：

- 着色语言：HLSL（`#include` URP `Core.hlsl` / `Lighting.hlsl`）
- 主光与阴影：`GetMainLight` + Cascade Shadowmap（草地 / 海洋接收阴影）
- 材质常量：`CBUFFER_START(UnityPerMaterial)`（兼容 SRP Batcher）
- 平台倾向：草地 / 海洋偏桌面级 GPU（Geometry / Tessellation / Compute）

特效模块速查 → [Resources/06.effect/README.md](Resources/06.effect/README.md)  
PBR BRDF 展示 → [Resources/07.PBR_object/README.md](Resources/07.PBR_object/README.md)

---

## 2. 角色渲染（01.Character）

### 2.1 目标

实现 **原神风格 NPR**，而非完整 PBR：

- 身体：Ramp 分层明暗、金属分区、卡通高光、边缘光
- 脸部：SDF 面部阴影
- 轮廓：反向扩张描边，按材质分区上色
- 双面：正面 UV0、背面 UV1

主 Shader：`Assets/Resources/01.Character/Shader/PBR-Character.shader`（`Demo/PBR-Character`）  
场景：`Assets/Scenes/01.Character.unity`

### 2.2 贴图语义

| 贴图 | 用途 |
|------|------|
| `_diffuse` | 固有色；Alpha 可作透明裁剪或自发光遮罩 |
| `_lightmap` | 身体：AO / 高光 / 金属 / 材质 ID；脸部：SDF |
| `_bumpMap` | 切线空间法线 |
| `_ramp` | Shadow Ramp；上下半图可区分昼夜 |
| `_metalMap` | 视角空间法线采样的金属反射调制 |

### 2.3 Pass 结构

| Pass | LightMode | 作用 |
|------|-----------|------|
| GenshinForward | `UniversalForward` | 正面主着色（Cull Back，UV0） |
| GenshinBackface | `UniversalForwardOnly` | 背面着色（Cull Front，UV1） |
| Outline | 描边 | 沿法线外扩，按 lightmap.a 分区描边色 |

### 2.4 关键算法

**身体 Shadow Ramp**

1. 半 Lambert + `smoothstep` 柔化 `NdotL`
2. 乘 lightmap.g（AO）
3. 用 lightmap.a 选择 Ramp 的 V 条带
4. 夜晚采样 Ramp 下半区（V + 0.5）
5. 亮面可保留半 Lambert，避免 Ramp 污染高光

**脸部 SDF**

1. FaceLightmap 左右翻转采样
2. XZ 平面前向 / 左右向与主光投影
3. SDF 阈值得到可控硬边明暗，再与 Ramp 混合

**金属 · 高光 · 边缘光 · 自发光**

- 金属：`lightmap.r` 高值区 + `_metalMap`
- 高光：Blinn-Phong，受 lightmap 与亮面遮罩调制
- 边缘光：阈值化菲涅尔
- 自发光：`diffuse.a` 遮罩 + 时间正弦闪烁

### 2.5 取舍

| 优点 | 限制 |
|------|------|
| 风格统一、分区清晰 | 非能量守恒 PBR |
| 适合二次元角色管线 | 依赖专用 Lightmap / Ramp |
| | 描边对法线质量敏感 |

---

## 3. 草丛渲染（02.Grass）

### 3.1 目标

在地面网格上 **GPU 程序化生成草叶**：密度可控、风摆、角色压草、根梢渐变、接收主光阴影。

| 资源 | 路径 |
|------|------|
| Shader | `Assets/Resources/02.Grass/Shaders/Grass.shader`（`Demo/Grass`） |
| 脚本 | `GetPlayerPos.cs`、`GrassCollider.cs` |
| 场景 | `Assets/Scenes/02.Grass.unity` |

### 3.2 管线阶段

```
Vertex → Hull / Domain（细分）→ Geometry（挤出草叶）→ Fragment
```

| 阶段 | 文件 | 职责 |
|------|------|------|
| Tessellation | `Library/CustomTessellation.hlsl` | `_TessellationUniform` 均匀细分 |
| Geometry | `Library/Grass.hlsl` | 每片细分三角挤出 1 片草（底 2 + 梢 1） |
| Fragment | `Grass.shader` | 根梢色、透光 Lambert、环境光、阴影 |

要求：`#pragma target 4.6` + `geometry` + `tessellation`；排除 GLES / Metal 等受限后端。

### 3.3 几何要点

1. 以细分三角首顶点为草根，构建 TBN
2. 随机绕法线旋转 + 前倾弯曲
3. 风力：世界 XZ 采样 `_WindDistortionMap`，随时间滚动，Rodrigues 转梢部
4. 压草：`_Players[100]` 找最近角色，距离内绕垂直轴倾倒
5. 根部只用朝向矩阵；梢部叠加风 + 角色 + 弯曲

### 3.4 片元

- `VFACE` 双面法线翻转
- `NdotL` + `_TranslucentGain` 透光
- `uv.y`：0 = 根 `_BottomColor`，1 = 梢 `_TopColor * 光照`

### 3.5 取舍

| 优点 | 限制 |
|------|------|
| 单网格大面积草 | 桌面级 API |
| 风与交互主要在 GPU | 密度过高时 Tess / GS 开销大 |
| | 交互角色上限 100 |

---

## 4. Gerstner 水面（03.water）

近岸水面，不是频谱海。波浪用若干条 Gerstner 叠加，倒影用平面反射，水底焦散由 RenderFeature 乘上去。

场景：`Assets/Scenes/03.Water.unity`

| 类型 | 路径 |
|------|------|
| 总控 | `Scripts/WaterSystem/Water.cs` |
| 波浪数据 | `Scripts/WaterSystem/Data/WaterSurfaceData.cs` |
| 渲染开关 | `Scripts/WaterSystem/Data/WaterSettingsData.cs` |
| CPU 浮力 | `Scripts/WaterSystem/GerstnerWavesJobs.cs` |
| 平面反射 | `Scripts/WaterSystem/Rendering/PlanarReflections.cs` |
| 焦散 / WaterFX | `Scripts/WaterSystem/Rendering/WaterSystemFeature.cs` |
| 水面着色 | `Shaders/Water/03.water_Water.shader`（`ZZY/03.water/Water`） |
| 焦散着色 | `Shaders/Water/03.water_Caustics.shader`（`ZZY/03.water/Caustics`） |
| 天空 | `Shaders/03.water_ProceduralSkybox.shader`（`ZZY/03.water/ProceduralSkybox`） |

### 4.1 技术栈

| 阶段 | 技术 |
|------|------|
| 波浪 | Gerstner 叠加。GPU 用 StructuredBuffer 或向量数组，公式在 `GerstnerWaves.hlsl` |
| 几何 | 相机前方多块网格，水平位置按 6.25 米对齐，避免接缝跟着镜头抖 |
| 浅水 | 正交深度相机拍第 10 层，浅处压低水平位移，并抬高顶点 |
| 水色 | 128×4 ramp：吸收、散射、泡沫密度 |
| 反射 | Cubemap、反射探针、平面反射三选一。当前场景用平面反射，管线渲染器索引 1 |
| 折射 | 采样不透明颜色，用法线偏移 UV，再按水深乘吸收色 |
| 泡沫 | 浪尖、岸线、WaterFX 的 R 通道，贴图 RGB 为厚 / 中 / 薄 |
| 焦散 | 天空之后画大平面。深度还原水下位置，沿主光采样两层噪声，`DstColor` 相乘 |
| 局部扰动 | WaterFX 半分辨率图：R 泡沫，GB 法线，A 位移。当前场景没有画这条 Pass 的物体 |
| 植被 / 悬崖 | Shader Graph，光照走 `CustomLighting.hlsl` |

### 4.2 每帧流程

```
OnEnable / Init
  生成波列 → 上传 GPU → 烤颜色 ramp → 拍岸边水深 → 打开平面反射
每相机
  反射相机（镜像 + 斜裁剪）→ WaterFX（可空）→ 不透明物 → 天空
  → 焦散乘到水下 → 海面网格（Gerstner + 折射 + 反射 + 泡沫）
LateUpdate
  Burst Job 给已登记的浮力点算高度（当前场景没有船）
```

### 4.3 取舍

| 优点 | 限制 |
|------|------|
| 近岸泡沫、水深、倒影直观 | 不是 FFT，远洋谱形不如 03.gpu_FFT_Ocean |
| 波浪条数少，顶点开销可控 | 平面反射多画一遍场景 |
| 焦散不改水面网格 | 依赖深度纹理和不透明颜色纹理 |

---

## 5. GPU FFT 海洋（03.gpu_FFT_Ocean）

> 模块速查 → [Resources/03.gpu_FFT_Ocean/README.md](Resources/03.gpu_FFT_Ocean/README.md)

### 5.1 目标

基于 Tessendorf《Simulating Ocean Water》与 [gasgiant FFT-Ocean](https://github.com/gasgiant/FFT-Ocean) 实践，在 URP 下实时生成：

- 三频带水平 / 垂直位移
- 导数法线
- Jacobian 浪尖白沫（絮状调制）

场景 `03.FFTOcean` 为**纯洋面**（无地形、无 Shore 岸线组件）。

| 类型 | 路径 |
|------|------|
| 驱动 | `Scripts/FFTOceanSimulator.cs` |
| 级联 | `Scripts/WavesCascade.cs` |
| FFT | `Scripts/FastFourierTransform.cs` + `Shaders/Compute/FastFourierTransform.compute` |
| 初始谱 | `Shaders/Compute/InitialSpectrum.compute` |
| 时变谱 | `Shaders/Compute/TimeDependentSpectrum.compute` |
| 合并 | `Shaders/Compute/WavesTexturesMerger.compute` |
| 表面 | `Shaders/FFTOcean.shader`（`Demo/FFTOcean`） |
| 配置 | `Settings/WavesSettings.asset` |
| 场景 | `Assets/Scenes/03.FFTOcean.unity` |

### 5.2 技术栈

| 阶段 | 技术 |
|------|------|
| 能量谱 | **JONSWAP** + TMA 深度修正；局地风浪 + 涌浪双谱 |
| 方向展宽 | Donelan-Banner / Cosine2s |
| 色散 | 有限水深 `ω(k)=√(gk tanh(kd))` |
| 变换 | **Stockham** GPU IFFT（横→纵，ping-pong） |
| 级联 | 三 `LengthScale`，波数环带互斥切分 |
| 白沫 | Tessendorf **Jacobian** `J=(1+λDxx)(1+λDzz)-(λDxz)²` 帧间累积 + 波峰高度 + tileable fBm/Worley |
| 着色 | URP Forward：深度水色、屏幕折射、Fresnel 天空、Blinn、SSS、主光阴影 |

### 5.3 每帧流程

```
[一次] Box-Muller 高斯噪声
         + InitialSpectrum → H0 / WavesData  × 3 cascades
         ↓
[每帧] TimeDependentSpectrum（相位推进，打包 Dx/Dy/导数）
         ↓
      Stockham IFFT × 4 路
         ↓
      Merger → Displacement / Derivatives / Turbulence
         ↓
      绑定材质 → 顶点位移 + 片元着色
```

### 5.4 Compute 分工

| Compute | Kernel | 效果段 |
|---------|--------|--------|
| `InitialSpectrum` | `CalculateInitialSpectrum` / `CalculateConjugatedSpectrum` | JONSWAP → H0 |
| `TimeDependentSpectrum` | `CalculateAmplitudes` | 时变频谱打包 |
| `FastFourierTransform` | 横/纵 IFFT · Scale · Permute | 频域→空间域 |
| `WavesTexturesMerger` | `FillResultTextures` | 位移 / 法线导 / Jacobian 泡沫 |

### 5.5 表面着色分段

1. **Vertex** — 三频带 Displacement LOD；大浪高度偏置  
2. **Normal** — Derivatives 重建坡度法线  
3. **Depth** — 场景水深 → 浅/中/深色与 Beer 吸收；开放洋面用 `_DeepDistance` 回退  
4. **Lighting** — Fresnel 反射、Blinn、SSS、阴影  
5. **Whitecaps** — 低 J 折叠 + `CrestFoam` + `_FoamNoise` 絮状  

### 5.6 关键参数

| 参数 | 含义 | 提示 |
|------|------|------|
| `fftPow` | N = 2^fftPow | 8→256 较均衡 |
| `lengthScale0/1/2` | 大/中/小浪尺度 | 默认约 250 / 17 / 5 |
| `lambda` | 水平挤压 | 影响折叠与白沫量 |
| `FoamBias` | Jacobian 白沫阈值 | 三频带求和后约 **2.85** |
| `CrestFoam` | 浪尖高度泡沫 | 参考图浪尖高亮 |
| `_FoamNoise` | 絮状噪声 | 须四方连续 |

### 5.7 相对旧海洋实现（`03.fpu_FFT_Ocean`）

曾用路径与单体 `FFTOcean.compute`（Phillips → 单贴片 IFFT → Displace/NormalBubbles）已由本模块**整体替换**：

| | 旧 | 现 |
|--|----|----|
| 目录名 | `03.fpu_FFT_Ocean` | **`03.gpu_FFT_Ocean`** |
| Compute | 单文件多 Kernel | 四 Compute 分工 |
| 谱 | Phillips | **JONSWAP** 双谱 |
| 尺度 | 单 Length | **三级联** |
| 泡沫 | bubbles 阈值 | **Jacobian 累积** + 波峰 + 无缝噪声 |
| 场景附属 | 地形 / Shore | **已移除** |

### 5.8 取舍

| 优点 | 限制 |
|------|------|
| 谱方法细节丰富、GPU 并行 | 需桌面级 Compute |
| 多频带减少单一平铺感 | 贴片仍周期重复 |
| 白沫与几何折叠一致 | 无力浮力；反射为探针级 |

---

## 6. 毛发渲染（04.Fur）

### 6.1 目标

URP Forward 下用 **Shell Texturing** 表现短毛：沿法线多层半透明壳 + 噪波镂空，配合重力、梳理与风力。驱动为 `Graphics.DrawMeshInstanced`。

| 资源 | 路径 |
|------|------|
| Shader | `Shaders/URP_StaticInstancedFur_Optimized.shader` |
| 公共库 | `Shaders/Library/FurCommon.hlsl` |
| 脚本 | `Scripts/FurInstancedRendererOptimized.cs` |
| 场景 | `Assets/Scenes/04.Fur_Optimized.unity` |
| 说明 | [04.Fur/README.md](Resources/04.Fur/README.md) |

### 6.2 流程

```
CPU（FurInstancedRendererOptimized）
  ├─ 按相机距离计算 shell 层数（LOD）
  ├─ 每层 Matrix + _LayerRatio（0→1）
  └─ DrawMeshInstanced

GPU 每层
  ├─ 顶点：挤出 + 重力 + Comb + 风
  ├─ 片元：Noise 镂空（根密梢疏）+ 根梢色
  └─ DepthOnly：Early-Z，减 Overdraw
```

### 6.3 关键技术点

| 点 | 说明 |
|----|------|
| GPU Instancing | 一层 = 一个 Instance；`_LayerRatio` 进 Instancing Buffer |
| 距离 LOD | 近 `maxShellCount` → 远 `minShellCount` |
| DepthOnly | 与 Forward 共用 `FurCommon` 形变 |
| FurSafePow | 避免负底数 `pow` |
| 风力 | MPB 写 `_WindVector`，不进 PerMaterial CBUFFER |
| Pass 顺序 | **UniversalForward 必须为 Pass 0** |

### 6.4 使用

1. 打开 `04.Fur_Optimized` 或拖入 `FurBall_Optimized` Prefab  
2. 材质勾选 **Enable GPU Instancing**  
3. 调节层数、LOD 距离、风力  

### 6.5 取舍

| 优点 | 限制 |
|------|------|
| 单 Mesh 出毛；Instancing + LOD | 层数与 Fill Rate 强相关 |
| DepthOnly 缓解壳层 Overdraw | 非真实单根毛发物理 |

---

## 7. 自定义后处理（05.PostProcessing）

### 7.1 目标

**不使用 URP Volume / 内置 PP**，用 `ScriptableRendererFeature` + 独立 Shader 组成可配置效果链；参数由场景 `CustomPostProcessManager` 驱动。

| 资源 | 路径 |
|------|------|
| Feature / Pass / Manager | `Assets/Pipelines/Features/` |
| Shader | `Assets/Resources/05.renderfeature/Shaders/` |
| 场景 | `Assets/Scenes/05.PostProcessing.unity` |
| 速查 | [README_CustomPP.md](Pipelines/Features/README_CustomPP.md) |

菜单：`SRP Demo → Post Processing → Install Custom RenderFeature`

### 7.2 效果链

```
CameraColor
  → Copy
  → HeightFog（世界 Y）
  → DepthFog（相机距离）
  → DepthOfField
  → Bloom（仅 layerMask）
  → Outline
  → ChromaticAberration
  → Tonemapping
  → 写回 CameraColor
```

相机需关闭内置 `renderPostProcessing`，并开启深度纹理。

### 7.3 效果一览

| 效果 | Shader | 要点 |
|------|--------|------|
| 高度雾 | `CustomPP_HeightFog` | 贴地浓、越高越稀 |
| 深度雾 | `CustomPP_DepthFog` | `end ≤ start` 指数；否则线性 |
| 景深 | `CustomPP_DepthOfField` | 焦点 + 近/远过渡 |
| Bloom | `CustomPP_Bloom` | **仅指定 Layer** |
| 描边 | `CustomPP_Outline` | 深度 / 颜色边缘 |
| 色差 | `CustomPP_ChromaticAberration` | 径向 RGB 分离 |
| 色调映射 | `CustomPP_Tonemapping` | Exposure / Contrast / Saturation |

### 7.4 Layer Bloom

只有 `bloom.layerMask` 内物体参与辉光提取。

1. 独立 `RenderTexture`（自带深度）Clear 黑  
2. `DrawRenderers` + `FilteringSettings(layerMask)` 真实材质重绘  
3. 无 Material `Blit` 拷贝 → Prefilter → 金字塔  
4. 上采样：模糊 + Additive（避免临时 RT 的 `_SourceTex2` 绑定失败）  
5. 结果拷到真实 RT，`Material.SetTexture` 后与场景合成  

测试约定：`BloomEmitter` → Layer `Bloom`；Manager 的 `layerMask` 仅勾选 `Bloom`。

### 7.5 踩坑摘要

| 问题 | 处理 |
|------|------|
| 与相机 Depth 共享绑 RT 失败 | Bloom 源用自带 depth 的 RT |
| `SetGlobalTexture` + 临时 RT 采成白 | 真实 RT + `SetTexture`，或 Additive 单纹理 |
| 中途 `Graphics.Blit` 打断 URP | 合成留在 `CommandBuffer` 内 |

### 7.6 取舍

| 优点 | 限制 |
|------|------|
| 效果可单独开关；Shader 拆分清晰 | 需手动挂 Feature + Manager |
| Bloom 可按 Layer 隔离 | Bloom 多一次 Layer 重绘 |
| 不绑 Volume 栈 | 非完整影视级套件 |

---

## 8. 六套效果对比

| 维度 | 角色 | 草地 | Gerstner 水面 | FFT 海洋 | 毛发 | 后处理 |
|------|------|------|---------------|----------|------|--------|
| 主要阶段 | 多 Pass VS/PS | Tess + GS + PS | VS/PS + 反射相机 | Compute + VS/PS | Instancing 多层 | Fullscreen Pass |
| 数据驱动 | Diffuse / Ramp 等 | 程序化几何 | 波列 + 水深图 | 频谱 RT | Noise / Length | 深度 + 颜色 RT |
| 风格 | NPR / Toon | 程序化植被 | 近岸海面 | 物理启发远洋 | 短毛 / 绒毛 | 画面合成 |
| 性能敏感 | 多 Pass、贴图 | 细分密度 | 反射分辨率 | FFT 分辨率 N | 壳层 Fill Rate | 全屏次数、Bloom 重绘 |
| 平台 | URP 较广 | 桌面 DX11+ | URP + 深度纹理 | 桌面 Compute | Instancing 友好平台 | URP Feature |

---

## 9. 调试建议

1. **角色**：脸部材质勾选对应选项并绑定 FaceLightmap；描边按模型尺度微调。  
2. **草地**：提高 `_TessellationUniform`；保证 `GrassCollider` + `GetPlayerPos` 绑定同一材质。  
3. **Gerstner 水面**：确认 Renderer 索引 1 是平面反射渲染器，且 `WaterSystemFeature` 的 Debug 为 Disabled。水深不对时在 Water 上执行 Capture Depth。  
4. **FFT 海洋**：Play 或勾选 `simulateInEditMode`；浪过高 / 过度折叠时减小 `lambda` 与谱 `scale`；白沫过少提高 `FoamBias` 或 `CrestFoam`。  
5. **毛发**：确认 GPU Instancing；远景靠 LOD 减层，近景再加壳层。  
6. **后处理**：确认 Feature 已安装、Manager 在场、相机深度开启；Bloom 物体 Layer 与 `layerMask` 一致。

---

## 10. 参考

**角色**  
- 原神风格 Ramp / SDF 面部阴影常见实践

**草地**  
- GPU Gems 草地 / Geometry 思路  
- URP Tessellation + Geometry

**Gerstner 水面**  
- Gerstner 叠加波（水平余弦、垂直正弦）  
- 平面反射：镜像矩阵 + 斜裁剪近平面  
- 焦散：深度还原后沿主光投影

**FFT 海洋**  
- Jerry Tessendorf, *Simulating Ocean Water*  
- gasgiant / FFT-Ocean（三频带 JONSWAP + Stockham + Jacobian 泡沫）  
- NVIDIA Ocean Surface Simulation 公开材料

**毛发**  
- URP Shell Texturing + GPU Instancing 实践

**后处理**  
- URP `ScriptableRendererFeature` / `ScriptableRenderPass`  
- 经典 Bloom 金字塔（阈值 → 降采样 → 上采样）

**特效（06）**  
- 序列帧火焰 + 噪声 UV 扭曲（Cyanilux / RiME 一类思路）  
- 透明管壳 + 程序噪声液体  
- 能量护盾：六边形 SDF、深度交界、点击涟漪

---

## 11. 特效模块（06.effect）

当前仅保留 **5** 套演示，资源与场景清单见  
[Resources/06.effect/README.md](Resources/06.effect/README.md)。

| 效果 | 要点 |
|------|------|
| 流光 | 物体空间无缝流光 + Fresnel，角色展示 |
| 管道流水 | 玻璃壳 + 软 FBM 液体与顶点微浪 |
| 溶解 | 噪声溶解、边缘 HDR、前沿流光 |
| 真实火焰 | 12×6 序列帧、双噪声扭曲、无烟雾 |
| 护盾 | 等尺寸六边形球、交界光、点击命中波 |

共用库：`Resources/06.effect/Shaders/Library/EffectCommon.hlsl`  
工具：`Assets/Editor/EffectDemoSetup.cs`（默认只更新贴图/材质，不覆盖场景）

---

## 12. PBR 物体（07.PBR_object）

glTF 2.0 Metallic-Roughness + Cook-Torrance BRDF 教学场景。  
完整说明 → [Resources/07.PBR_object/README.md](Resources/07.PBR_object/README.md)。

| 测试组 | 要点 |
|--------|------|
| MetalRoughnessGrid_5×5 | 金属度左→右 0→1，粗糙度上→下 0→1 |
| SpecularTest | 高光形状 / 强度 / Fresnel；DebugMode 隔离 D·F |
| NormalTangentMirrorTest | 切线空间法线 + BumpScale + 镜面平面 |
| TransmissionRoughnessTest | 透射 × 粗糙度、体积衰减、屏幕折射 |

- Shader：`Custom/URP_glTF_PBR` · `Custom/URP_glTF_PBR_Transmission`
- 库：`Resources/07.PBR_object/Shaders/Library/glTFPBRCommon.hlsl`
- 场景：`Assets/Scenes/07.PBR_object.unity`
- 工具：`Assets/Editor/PBRObjectDemoSetup.cs` → `SRP Demo → PBR Object → Setup Scene`

---

## 13. 结语

多套相对独立的 URP 方案覆盖：

1. **角色** — 美术可控的卡通光照分区  
2. **草地** — GPU 程序化植被与简易交互  
3. **海洋** — 三频带 JONSWAP + GPU IFFT + Jacobian 白沫  
4. **毛发** — Instancing 壳层短毛  
5. **后处理** — 可配置 RenderFeature 效果链（含 Layer Bloom）  
6. **特效** — 透明流光 / 管道 / 溶解 / 写实火焰 / 交互护盾  
7. **PBR 物体** — glTF Metal-Rough BRDF 与透射测试阵列  

学习路径：片元 NPR → 几何管线扩展 → Compute 模拟 → Instancing 层壳 → 全屏后处理 → 透明与交互特效 → 标准 PBR / BRDF。
