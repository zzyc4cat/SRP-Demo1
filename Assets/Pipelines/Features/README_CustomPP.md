# 自定义后处理（RenderFeature）

不依赖 URP Volume / 内置 Post-processing。  
技术详解见 [Assets/README.md](../../README.md) 第 6 节；工程入口见根目录 [README.md](../../../README.md)。

---

## 路径

| 类型 | 路径 |
|------|------|
| 脚本 | `Assets/Pipelines/Features/` |
| Shader | `Assets/Resources/05.renderfeature/Shaders/` |
| 场景 | `Assets/Scenes/05.PostProcessing.unity` |

安装菜单：`SRP Demo → Post Processing → Install Custom RenderFeature`

---

## 效果链

```
Copy → HeightFog → DepthFog → DoF → Bloom(Layer) → Outline → CA → Tonemap
```

| 效果 | 说明 |
|------|------|
| 高度雾 | 世界 Y，贴地浓 |
| 深度雾 | 相机距离；`end ≤ start` 为指数，否则线性 |
| 景深 | 焦点距离 + 近/远过渡 |
| Bloom | **仅 `layerMask` 指定层**参与提取 |
| 描边 | 深度 / 颜色边缘 |
| 色差 | 径向 RGB 分离 |
| 色调映射 | Exposure / Contrast / Saturation |

---

## Bloom Layer

1. 在 `CustomPostProcessManager.bloom.layerMask` 勾选目标层（如 `Bloom`）  
2. 将发光物体设到同一 Layer（测试：`BloomEmitter` → `Bloom`）  
3. Pass 离屏重绘该层 → 阈值 / 金字塔 → 叠回全图  

相机需关闭内置 Post-processing，并开启深度纹理。
