# 06.effect — URP 特效样例（保留 5 套）

Unity URP 下的五组独立特效演示。资源统一在本目录，场景在 `Assets/Scenes/06.effect_*.unity`。

| 效果 | 场景 | 主要 Shader | 说明 |
|------|------|-------------|------|
| 流光 | `06.effect_FlowTranslucent` | `FlowTranslucent` | 半透明角色 + 物体空间无缝流光带 |
| 管道流水 | `06.effect_FlowPipe` | `FlowPipe` + `FlowPipeGlass` | S 形玻璃管 + 管内软液体流动 |
| 溶解 | `06.effect_DissolveFlow` | `DissolveFlow` | 噪声溶解、边缘光、前沿流光 |
| 真实火焰 | `06.effect_FireRealistic` | `FireRealistic` | 序列帧 + 噪声扭曲（无烟雾） |
| 护盾 | `06.effect_Shield` | `Shield` | 六边形能量罩 + 点击涟漪 |

---

## 目录

```
06.effect/
├── Shaders/
│   ├── Library/EffectCommon.hlsl   # 共用函数
│   ├── FlowTranslucent.shader
│   ├── FlowPipe.shader / FlowPipeGlass.shader
│   ├── DissolveFlow.shader
│   ├── FireRealistic.shader
│   └── Shield.shader
├── Materials/                      # 与上表一一对应（火焰含 _B 层）
├── Textures/                       # 噪声 / 流光 / 火焰序列帧 / 护盾贴图等
├── Models/
│   ├── FlowPipe.fbx                # PipeGlass + PipeLiquid
│   └── ShieldHexSphere_Runtime.asset
├── Scripts/
│   ├── DissolveFlowController.cs
│   └── ShieldHitController.cs
└── README.md                       # 本文件
```

编辑器工具：`Assets/Editor/EffectDemoSetup.cs`  
菜单：`SRP Demo → Effect → Setup Materials & Textures`（**不**重建场景）

---

## 效果说明

### 1. 流光（FlowTranslucent）

- Fresnel 外轮廓 + Additive 流光
- 流光 UV 使用物体空间采样无缝 `EffectFlow.png`，避免角色 UV 接缝断流
- 演示模型：角色 `Funingna/FuFu.fbx`（若缺失则用胶囊体兜底）

### 2. 管道流水（FlowPipe）

- `FlowPipe.fbx`：外层玻璃、内层液体
- 液体：软 FBM 域扭曲 + 中心密度 + 轻微顶点波
- 玻璃：低 alpha + 软 Fresnel，叠在液体外层

### 3. 溶解（DissolveFlow）

- 噪声阈值裁剪 + HDR 边缘色 + 溶解前沿叠加流光
- `DissolveFlowController` 在 Play 中驱动 `_DissolveAmount`

### 4. 真实火焰（FireRealistic）

- `fire_src_1.png`（12×6）序列帧插值
- 双层噪声 UV 扭曲、FBM 尖端碎边、HDR 白→橙→红
- 交叉 billboard + 点光打地；**不含烟雾**

### 5. 护盾（Shield）

- 等尺寸六边形球面网格 + 面 UV 六边形描边
- 深度交界光、Fresnel、可选溶解
- `ShieldHitController`：左键点击写入全局命中数组，Shader 画涟漪
- 相机需开启深度纹理

---

## 共用库要点（EffectCommon.hlsl）

| 函数 | 主要用途 |
|------|----------|
| `EffectObjectFlowUV` / `EffectFlowUV` | 流光、溶解前沿 |
| `EffectFresnel` | 流光 / 管 / 溶解 / 护盾 |
| `EffectDissolve` | 溶解边缘 |
| `EffectFBM` / `EffectNoise2D` | 火焰、管内液体 |
| `EffectHexSDF` / `EffectHexEdge` | 护盾六边形 |
| `EffectDepthIntersection` | 护盾与场景交界 |

---

## 清理说明

已移除未再使用的测试资源（卡通火 / 序列帧火 / 粒子火 / 金属流光 / 护盾 Debug / 旧管段网格等）。  
当前目录仅保留上述 5 套效果及其依赖。
