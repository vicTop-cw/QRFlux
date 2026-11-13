# 图像入口解码（T0.5）汇报

**日期**：2026-11-13
**任务**：T0.5 图像入口解码（补齐「截图/像素 → 矩阵」断点）
**执行人**：小拳（FIST 化身搭子）

## 结果摘要

补齐了解码侧缺失的「图像 → 矩阵」入口全链路：**灰度像素 → Otsu 二值化 → finder 定位 → 仿射重采样 → decode_qr（四向旋转重试）**，全部纯 MoonBit 自研零依赖。新增 26 格测试，**1313/1313 全绿**，交叉验证 **165/165 零回归**。

## 背景（用户点出的断点）

真实场景是「远端电脑生成 QR 图片 → 截图传输 → 本地解码」。侦察实测发现：`decode_qr` 只接受 0/1 干净矩阵，`decoder.mbt` 内无任何 finder 定位 / 二值化 / 采样能力（grep 零命中），前端扫码靠 jsQR、交叉验证靠 zxing-cpp。**图像入口层完全缺失**。

## 交付物

| 文件 | 内容 |
|---|---|
| `src/qr/image_decode.mbt` | 新，429 行：二值化 + finder 定位 + 重采样 + `decode_from_pixels` |
| `src/qr/image_decode_test.mbt` | 新：黑盒 E2E 12 格 + 退化/变异 5 格 |
| `src/qr/image_decode_wbtest.mbt` | 新：白盒 9 格（内部判据直测） |
| `README.md` | 能力清单 + 图像入口章节 |
| `FIST-TASK-TREE.md` | T0.5 任务树（5 个子任务） |
| `memory/2026-11-13.md` | 迭代日志 |

## 技术要点

- **二值化**：Otsu 全局阈值（256 直方图类间方差最大化），全白/全黑/空图优雅返回 None
- **定位**：行扫描 + 列扫描各自 RLE 后滑窗匹配 1:1:3:1:1，交叉配对成候选点，近邻合并
- **重采样**：三 finder 中心建立仿射网格，每 module 取 3×3 邻域多数投票
- **鲁棒性**：候选三点枚举 + 6 种指派 + 4 向旋转重试，`decode_qr` 作最终裁决（天然处理朝向/镜像/alignment 假阳性）

## 资源消耗

- 时间：约 1.5 小时（含 3 轮真 bug 定位与修复）
- 验证：moon fmt/check/test 全链路复跑多轮 + 交叉验证复跑
- 计算：1313 测试 + 165 交叉验证

## 遗留风险

1. **无透视校正**：仿射模型覆盖缩放/平移/90°倍旋转，斜拍强透视不覆盖
2. **无局部自适应阈值**：亮度极端不均（阴影/反光）会失效
3. **PNG 文件直读未做**：像素由调用方提取（浏览器 canvas / Python PIL）
4. `batch.txt.bak` 临时备份待清理

## 后续建议

1. **P1 透视校正**：加 homography（第四角由 alignment pattern 定位），覆盖斜拍场景
2. **P1 CLI/WASM 接线**：CLI 加 `--decode-image <png>`、WASM 加 canvas 像素入口，打通端到端演示
3. **P2 局部自适应阈值**：Sauvola/分块 Otsu，抗亮度不均
4. **P2 交叉验证升级**：`verify_qr.py` 增加「加噪截图 → 自研像素解码」环节，形成业界解码器 + 自研解码器双证

## P1 追加：PNG 文件直读 + CLI 端到端 + 前端接线

| 交付 | 说明 |
|---|---|
| `src/qr/png_decode.mbt` | PNG 解码：chunk 解析 + 反 filter + 位深/色彩展开自研，zlib 走标准库 |
| `src/qr/png_decode_test.mbt` | 6 格：to_png 闭环 + 坏签名/截断/空输入拒收 |
| CLI `--decode-image-b64` | base64 PNG → 自研像素解码 → payload |
| `scripts/verify_image_pipeline.py` | 真实截图 E2E，9/9 OK |
| `web/server.js` `/api/decode-image` | 本地 API 转发到 CLI 自研解码器 |
| `web/camera.html` | 主路径走自研，jsQR 降级 |

**实测**：moon test 1319/1319；CLI 端到端「Hello QRFlux image entry」24 字节还原；脚本 9/9（噪声/缩放/模糊/RGB/V3/V5）。

**新发现落差**：wasm 产物只导出 memory + _start（QR 函数未导出），wasm_test.html 为空壳；README 的「WASM 绑定 ✅」已改为如实表述。

**已知边界**：CLI 传参 ≈28KB 上限；无透视校正。

## 来源

- 任务包：FIST-TASK-TREE.md T0.5
- 产出物：`src/qr/image_decode.mbt` 等三文件 + README/TASK-TREE 同步
