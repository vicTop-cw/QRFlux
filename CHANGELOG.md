# Changelog

## 0.2.0 (2026-11-15)

### Added
- 图像入口解码：Otsu 二值化 + finder 定位 + 仿射重采样 + 四向旋转重试（`decode_from_pixels`）
- 透视校正：alignment pattern 锚定四点 homography（V2+），仿射失败自动回退
- PNG 文件直读：自研 chunk 解析 + 反 filter（5 种）+ 位深/色彩展开（灰度 1/2/4/8bit、RGB、灰度+Alpha、RGBA）
- BMP 文件直读：24/32bpp BGR(A) + 8/1bit 调色板，bottom-up/top-down
- 统一图像入口 `decode_image_gray`：PNG/BMP 魔数自动分流，web 与 CLI 共用
- 自适应阈值：tile×tile 分块 Otsu（全局失败后自适应重试），亮度不均/侧光场景可解；渐变光照 25%-100% E2E 用例
- CLI `--decode-image-b64`：格式自动探测的截图解码（含命令行长度预算检查）
- 多格式截图 E2E（`scripts/verify_image_pipeline.py`）：PNG/BMP raw/GIF/TIFF/JPEG q70-95/WebP + 渐变光照 + 多帧序列，21/21
- **动态码流忠实图像 E2E**：`--encode-dynamic --format png`（每帧输出 PNG + FRAME_HEX）→ 截图扰动 → `--decode-image-b64`（IMAGE_HEX）→ `--decode-dynamic --hex`（REASSEMBLED_HEX）→ 原始 payload，接缝闭环
- **浏览器内引擎启用**：MoonBit js 产物（`/wasmapi.js`）作为 camera.html 主解码路径，server API 与 jsQR 降级
- WASM/JS 导出面（`src/wasmapi`，foreign_library + `#export_name`）：js 产物 ESM 接线；wasm-gc 符号亦验证（host 侧 non-null externref 仍受 JS API 限制）
- 复现脚本 `scripts/repro_wasm_export_issue.cjs`（修复后 not reproduced，留作回归）

### Fixed
- **hex 格式化 bug（js 后端）**：`String[i]` 在 js 后端返回 UTF-16 码点 Int，`digits[i].to_string()` 输出数字字符串（"f" → "102"），导致引擎 payload 静默错乱（表现即 moon#2527）；改用整数 `match` 字面量修复。由 MoonBit 官方在 moon#2527 源级诊断确认
- BMP bottom-up 行分配时序错误：循环内按 row 索引重新分配覆盖了转置行 y 的写入数据（top-down 侥幸正确）
- `web/server.js` 命令行长度上限：`execSync` 经 cmd.exe 有 ~8191 字符上限，长 base64 必然失败；改 `spawnSync` argv 数组直走 CreateProcess

### Changed
- moon fmt 语法迁移：`} derive(...)` → 前置 `#derive(...)`（moon 0.1.20261104 起 deprecated_syntax）
- README/申报书读数与实测对齐（测试 1287 → 1332、WASM 尺寸按当前构建、V40 H 容量 1273）

### Known limitations
- V40 大尺寸 QR 在部分第三方解码器上存在解码限制（自研解码器可正常还原）
- 浏览器内引擎未启用（issue #2527）；前端走本地 Node 服务转发
- CLI 图片传参受命令行长度限制（base64 ≈30KB），超大截图需先裁剪/缩放
- 无局部自适应阈值（亮度不均场景需调用方预处理）；V1 无 alignment pattern，仅仿射

## 0.1.0 (2026-11-02)

- 初始版本：QR 编码器（V1~V40 全版本，L/M/Q/H 四档纠错）、自研解码器（矩阵入口）、静态/动态码流管线（LT 喷泉码）、彩色 QR（4 色 2bits/module）、WASM 绑定、前端演示、交叉验证（zxing-cpp）
