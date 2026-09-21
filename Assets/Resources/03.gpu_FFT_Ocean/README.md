# 03.gpu_FFT_Ocean — GPU FFT 海洋

URP Forward · Tessendorf / gasgiant 风格三频带 GPU FFT 海面。  
场景：`Assets/Scenes/03.FFTOcean.unity`（纯洋面，无地形 / 无岸线 Shore）。

---

## 技术栈一览

| 层 | 技术 | 文件 |
|----|------|------|
| 谱模型 | JONSWAP + TMA + Donelan-Banner / Cosine2s 方向展宽；局地风浪 + 涌浪叠加 | `InitialSpectrum.compute` · `WavesSettings.cs` |
| 时变 | Tessendorf 相位 `h₀e^{iωt}+h₀*e^{-iωt}`，打包位移与导数频谱 | `TimeDependentSpectrum.compute` |
| 变换 | Stockham GPU IFFT（横→纵 ping-pong） | `FastFourierTransform.compute` · `.cs` |
| 输出图 | Displacement / Derivatives / Jacobian Turbulence × 3 级联 | `WavesTexturesMerger.compute` · `WavesCascade.cs` |
| 驱动 | 三级联 LengthScale 波数切分 + 运行时平面网格 | `FFTOceanSimulator.cs` |
| 表面 | URP Forward：深度水色、折射、Fresnel、Blinn、SSS、浪尖白沫 | `FFTOcean.shader`（`Demo/FFTOcean`） |
| 泡沫噪声 | 四方连续 fBm + Worley（编辑器生成） | `T_FoamNoise.png` · `FFTOceanDemoSetup` |

---

## 每帧数据流

```
WavesSettings (JONSWAP α / ωp / λ)
        │
        ▼  [一次 / 参数变更]
InitialSpectrum → H0 + WavesData   × 3 cascades（波数环带互斥）
        │
        ▼  [每帧]
TimeDependentSpectrum → DxDz / Dy / 导数 复数缓冲
        │
        ▼
Stockham IFFT × 4 路 → 空间域
        │
        ▼
WavesTexturesMerger
  ├─ Displacement  (λ·Dx, Dy, λ·Dz)
  ├─ Derivatives   (坡度 / 曲率 → 法线)
  └─ Turbulence    (Jacobian J 累积 → 白沫)
        │
        ▼
Demo/FFTOcean 顶点位移 + 片元着色
```

---

## 表面着色分段

| 段 | 作用 |
|----|------|
| Vertex | 三频带 Displacement LOD 混合；大浪高度供 SSS / 浪尖 |
| Normal | Derivatives 重建坡度法线 |
| Depth | 场景深度 → 浅/中/深水色、Beer 吸收；无海底时用 DeepDistance 回退 |
| Lighting | Fresnel 天空、Blinn 高光、透光 SSS、主光阴影 |
| Whitecaps | 低 Jacobian 折叠 + 波峰高度 + 双层错速噪声絮状 |

---

## 与旧版差异（曾用 `03.fpu_FFT_Ocean`）

| | 旧单 Compute 管线 | 当前 GPU FFT |
|--|-------------------|--------------|
| 目录 | `03.fpu_FFT_Ocean` | **`03.gpu_FFT_Ocean`** |
| Compute | 单体 `FFTOcean.compute` | 四文件：Initial / Time / FFT / Merger |
| 频谱 | Phillips × Donelan-Banner | **JONSWAP** + 局地/涌浪双谱 |
| 级联 | 单尺度贴片 | **三 LengthScale** 频带切分 |
| 泡沫 | 差分雅可比 / bubbles 阈值 | **Tessendorf Jacobian 累积** + 波峰 + tileable 噪声 |
| 场景 | 曾含地形 / Shore | **纯洋面** |
| 网格 | `OceanMeshBuilder` | Simulator 内建平面 |

旧路径与单文件管线文档已废弃，以本 README 与 `Assets/README.md` §4 为准。

---

## 关键参数

| 参数 | 含义 |
|------|------|
| `fftPow` | N = 2^fftPow（默认 8 → 256） |
| `lengthScale0/1/2` | 大/中/小浪周期尺度 |
| `WavesSettings.lambda` | 水平挤压；影响折叠与白沫 |
| `FoamBias` ≈ 2.85 | 三频带 J 求和后的白沫阈值 |
| `CrestFoam` | 大浪尖峰额外白沫 |
| `_FoamNoise` | 絮状调制，需四方连续 |

---

## 编辑器菜单

- `SRP Demo/FFT Ocean/Rebuild Scene (03.FFTOcean)`
- `SRP Demo/FFT Ocean/Regenerate Seamless Foam Noise`
- `SRP Demo/FFT Ocean/Apply Calm|Storm Preset`
- `SRP Demo/FFT Ocean/Quality/*`
