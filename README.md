# SRP Demo1

Unity **2022.3.62f3 LTS** · **URP 14** 自定义渲染样例。

在 URP Forward 下用独立 Shader / Compute / RenderFeature 演示多类效果，便于学习与复盘。

---

## 环境

| 项 | 值 |
|----|-----|
| 引擎 | Unity 2022.3.62f3 LTS |
| 管线 | URP 14.0.12 |
| 着色 | HLSL（URP `Core.hlsl` / `Lighting.hlsl` 等） |

---

## 模块一览

| # | 模块 | 技术要点 | 资源 | 场景 |
|---|------|----------|------|------|
| 01 | 角色 | NPR Ramp / SDF 脸影 / 描边 | `Assets/Resources/01.Character/` | `Assets/Scenes/01.Character.unity` |
| 02 | 草地 | Tessellation + Geometry | `Assets/Resources/02.Grass/` | `Assets/Scenes/02.Grass.unity` |
| 03 | Gerstner 水面 | 叠加波 · 平面反射 · 岸线泡沫 · 焦散 | `Assets/Resources/03.water/` | `Assets/Scenes/03.Water.unity` |
| 03 | FFT 海洋 | 三频带 JONSWAP + Stockham IFFT + Jacobian 白沫 | `Assets/Resources/03.gpu_FFT_Ocean/` | `Assets/Scenes/03.FFTOcean.unity` |
| 04 | 毛发 | Shell Texturing + GPU Instancing | `Assets/Resources/04.Fur/` | `Assets/Scenes/04.Fur_Optimized.unity` |
| 05 | 后处理 | 自定义 RenderFeature（非 Volume） | `Assets/Pipelines/Features/` · `Assets/Resources/05.renderfeature/` | `Assets/Scenes/05.PostProcessing.unity` |
| 06 | 特效 | 流光 · 管道 · 溶解 · 真实火焰 · 护盾 | `Assets/Resources/06.effect/` | `Assets/Scenes/06.effect_*.unity`（5 个） |
| 07 | PBR 物体 | glTF Metal-Rough BRDF · Specular / Normal / Transmission | `Assets/Resources/07.PBR_object/` | `Assets/Scenes/07.PBR_object.unity` |

**技术详解 → [Assets/README.md](Assets/README.md)**  
**特效包说明 → [Assets/Resources/06.effect/README.md](Assets/Resources/06.effect/README.md)**  
**PBR BRDF 展示 → [Assets/Resources/07.PBR_object/README.md](Assets/Resources/07.PBR_object/README.md)**

---

## 06.effect 保留效果（5）

| 效果 | 场景 | Shader |
|------|------|--------|
| 流光 | `06.effect_FlowTranslucent` | `ZZY/06.effect/FlowTranslucent` |
| 管道流水 | `06.effect_FlowPipe` | `FlowPipe` + `FlowPipeGlass` |
| 溶解 | `06.effect_DissolveFlow` | `ZZY/06.effect/DissolveFlow` |
| 真实火焰 | `06.effect_FireRealistic` | `ZZY/06.effect/FireRealistic` |
| 护盾 | `06.effect_Shield` | `ZZY/06.effect/Shield` |

编辑器菜单（默认不覆盖场景）：

- `SRP Demo → Effect → Setup Materials & Textures`
- `SRP Demo → Effect → Rebuild Scene → …`（会覆盖对应场景，慎用）

---

## 目录结构

```
Assets/
├── Resources/
│   ├── 01.Character/          # 角色 Toon / Ramp
│   ├── 02.Grass/              # 草地
│   ├── 03.water/              # Gerstner 水面、反射、焦散
│   ├── 03.gpu_FFT_Ocean/      # GPU FFT 海洋（三频带）
│   ├── 04.Fur/                # Shell 毛发
│   ├── 05.renderfeature/      # 后处理 Shader
│   ├── 06.effect/             # 特效（流光 / 管 / 溶解 / 火 / 护盾）
│   └── 07.PBR_object/         # glTF PBR / BRDF 展示
├── Pipelines/Features/        # 后处理 Feature / Pass / Manager
├── Editor/FFTOceanDemoSetup.cs # 03 海洋场景 / 泡沫噪声
├── Editor/EffectDemoSetup.cs  # 06.effect 贴图 / 材质工具
├── Editor/PBRObjectDemoSetup.cs # 07.PBR 场景一键搭建
└── Scenes/                    # 各模块演示场景
```

---

## 快速开始

1. 用 Unity 2022.3 LTS 打开本工程，等待 URP 资源导入完成。
2. 打开上表对应场景，进入 Play 查看效果。
3. **后处理**额外确认：
   - URP Renderer 已挂载 `CustomPostProcessFeature`
   - 场景中有 `CustomPostProcessManager`
   - 相机关闭内置 Post-processing，并开启深度纹理  
   - 菜单：`SRP Demo → Post Processing → Install Custom RenderFeature`
4. **护盾**场景需相机开启深度纹理（场景已配置）；Play 后左键点击护盾看涟漪。
5. **PBR**：打开 `07.PBR_object`；重建用 `SRP Demo → PBR Object → Setup Scene`。

---

## 文档索引

| 文档 | 内容 |
|------|------|
| [README.md](README.md)（本页） | 工程入口、模块索引、快速开始 |
| [Assets/README.md](Assets/README.md) | 各模块完整技术总结 |
| [Assets/Resources/06.effect/README.md](Assets/Resources/06.effect/README.md) | 特效 5 件套资源与用法 |
| [Assets/Resources/07.PBR_object/README.md](Assets/Resources/07.PBR_object/README.md) | glTF PBR / BRDF 测试场景说明 |
| [Assets/Resources/04.Fur/README.md](Assets/Resources/04.Fur/README.md) | 毛发目录与使用说明 |
| [Assets/Pipelines/Features/README_CustomPP.md](Assets/Pipelines/Features/README_CustomPP.md) | 后处理效果链速查 |

---

## 能力阶梯

```
片元 NPR（角色）
  → Tessellation / Geometry（草）
  → Gerstner 叠加波 + 平面反射（水面）
  → Compute 频谱（FFT 海）
  → GPU Instancing 壳层（毛发）
  → ScriptableRendererFeature 后处理
  → 透明 / 序列帧 / 交互特效（06.effect）
  → glTF Metal-Rough BRDF / 透射（07.PBR_object）
```
