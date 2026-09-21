# 04.Fur — Shell Texturing（GPU Instancing）

URP 下基于 **Shell Texturing + `DrawMeshInstanced`** 的短毛 Demo（优化版）。

技术详解见仓库 [Assets/README.md](../../README.md) 第 5 节，工程入口见根目录 [README.md](../../../README.md)。

---

## 目录

| 路径 | 内容 |
|------|------|
| `Shaders/` | `URP_StaticInstancedFur_Optimized.shader` |
| `Shaders/Library/` | `FurCommon.hlsl`（形变 / 裁剪 / SafePow） |
| `Scripts/` | `FurInstancedRendererOptimized.cs`（Instancing + 距离 LOD） |
| `Materials/` | 毛发材质（需开启 GPU Instancing） |
| `Textures/` | 噪波发丝图、长度遮罩 |
| `Prefabs/` | `FurBall_Optimized` |
| 场景 | `Assets/Scenes/04.Fur_Optimized.unity` |

---

## 快速使用

1. 打开 `Assets/Scenes/04.Fur_Optimized.unity`，进入 Play  
2. 或将 `Prefabs/FurBall_Optimized` 拖入场景  
3. 在组件上调节：壳层数、LOD 近/远距离、风力  

材质务必勾选 **Enable GPU Instancing**。

---

## 优化要点

| 项 | 说明 |
|----|------|
| 距离 LOD | 远距自动减少 shell 层数 |
| DepthOnly | Early-Z，降低半透明 Overdraw |
| FurSafePow | 消除负底数 `pow` 警告 |
| 风力 / 高光 | MPB 驱动风场 + 轻量高光 |
| 公共 HLSL | Forward / DepthOnly 共用形变逻辑 |

> 注意：Shader 中 **UniversalForward 必须为 Pass 0**，否则部分 `DrawMeshInstanced` 路径可能只写深度。
