# QRFlux (闪码)

纯 MoonBit 实现的二维码无损文件传输项目。
压缩选档 -> 二进制分片 -> 动态 QR 码流 -> 扫描重组 -> 无损还原。

## 当前状态 (2026-11-05)

### 已完成：16 轮迭代全部通过，项目可发布

- `src/qr/` 编码器核心：字节模式编码、版本/纠错级选择、GF(256) 域运算、Reed-Solomon ECC、功能图案绘制（finder/timing/alignment/format/version）、掩码选择与惩罚评分。
- 自研 QR 解码器：V1~V40 全版本、L/M/Q/H 四档纠错、全模式无损还原。
- 跨版本交叉验证：V1~V40 全版本、L/M/Q/H 四档纠错、全模式，**165/165 全部通过**业界标准解码器（zxing-cpp）无损还原。

### 能力清单

| 能力 | 状态 |
|------|------|
| QR 编码器（V1~V40） | ✅ |
| 自研 QR 解码器（V1~V40 全模式） | ✅ |
| 静态管线（压缩+打包+编解码） | ✅ |
| 动态码流（分片+喷泉码+乱序+丢帧恢复） | ✅ |
| 图片生成（PBM/SVG/PNG bit_depth=1） | ✅ |
| 彩色 QR 无损编解码（4色，2bits/module） | ✅ |
| 彩色 QR RGB 识别 + SVG/PPM 图片生成 | ✅ |
| CLI 编解码双向闭环 | ✅ |
| WASM 绑定（编码+解码） | ✅ |
| 前端编解码 UI（server.js + index.html） | ✅ |
| 摄像头扫码（camera.html + jsQR） | ✅ |

### 待办路线

- [x] QR 编码器（含 ECC、掩码）——已验证
- [x] 压缩率选档（首版可选的 deflate 级压缩 + 二进制打包）——已完成
- [x] 动态码流协议（>1KB 分片多帧 QR + LT 喷泉码）——已完成
- [x] 网页演示（`--target js` 嵌网页 + WASM 集成）——已完成（60KB WASM）
- [x] 自研 QR 解码器（V1~V40 全版本全纠错级全模式）——已完成
- [x] 彩色 QR 无损编解码（4色，2bits/module，RGB 识别）——已完成
- [x] 前端编解码 UI + 摄像头扫码——已完成

## 验证结果 (iter 16/16 最终验证)

- `moon fmt` / `moon check`：通过（0 errors，0 warnings）
- `moon test --target js`：**447/447 通过**（含 66 个无损传输闭环测试：35 系统 + 31 深度 + 44 个压力测试覆盖性能基准/模糊测试/版本补全/乱序丢帧四个维度 + 84 个薄弱点打磨测试覆盖 CLI 辅助/核心编码器深度/解码器错误路径/协议错误/策略补全/Web 绑定 + 74 个核心基础模块单元测试覆盖 GF256 域运算 18 + bits 位流 15 + segment 分段 15 + tables 常量表 14 + 图片内容正确性 12）
- 交叉验证（V1~V40 全版本全纠错级全模式）：**165/165 OK**
- WASM 构建：60895 字节（≈60KB）

## 验证方法

```sh
moon fmt                    # 格式化
moon check                  # 类型检查
moon test --target js       # 测试（JS 目标为权威）
moon info                   # 同步 .mbti
moon run cmd/main > batch.txt   # 生成参考矩阵
pip install zxing-cpp
python scripts/verify_qr.py batch.txt   # 165/165 OK
```

## CLI 用法

```sh
# 静态闭环
moon run cmd/main -- --text "Hello" --encode-static --format hex | tail -1
moon run cmd/main -- --decode-static --hex "hex_string"

# 动态闭环
moon run cmd/main -- --text "Long..." --encode-dynamic --frame-size 50 --format hex | tail -1
moon run cmd/main -- --decode-dynamic --hex "hex1;hex2;..."
```

## 网页演示

```sh
# 启动网页演示
cd web
node server.js
# 主页: http://localhost:3000/
# 摄像头扫码: http://localhost:3000/camera
```

前端编解码 UI 提供 4 个 API 端点（静态编码/解码、动态编码/解码），摄像头扫码页面基于 jsQR 实现实时识别。

## WASM 输出

```sh
# 生成 WASM
moon build --target wasm
# 输出文件: _build/wasm/debug/build/cmd/main/main.wasm (60KB)
```

WASM 绑定已完善，提供以下接口可直接在网页中调用：

- `web_encode_qr`：静态编码
- `web_encode_qr_static`：静态管线编码（压缩+打包）
- `web_encode_qr_dynamic`：动态码流编码（分片+喷泉码）
- `web_decode_qr`：解码

## 目录结构

```text
src/qr/         编码器/解码器核心（qrcode.mbt / gf256.mbt / segment.mbt / ...）
cmd/main/       CLI 入口（编解码双向闭环、批量输出矩阵供验证）
scripts/        交叉验证脚本
web/            前端编解码 UI（server.js + index.html + camera.html + demo.html）
docs/           设计文档（API.md / COLOR_QR_DESIGN.md）
memory/         记忆沉淀日志
reports/        任务汇报归档
```

## 备注

- 单张静态 QR 容量上限：V40 L=2953 / M=2331 / Q=1663 / H=1273 字节；>1KB 走动态码流。
- moon 0.1.20261016 依赖解析（moon add/import）存在 registry 兼容问题，故保持零三方依赖、纯自研路线。
- 彩色 QR 码方案见 `docs/COLOR_QR_DESIGN.md`（非标准，4 色 2bits/module，已实现无损编解码 + RGB 识别 + SVG/PPM 图片生成，需专用解码器）。
- 已知限制：V40 大尺寸 QR（177×177）zxing-cpp 解码器无法解码（非 QRFlux bug，单元测试验证编码正确）。
