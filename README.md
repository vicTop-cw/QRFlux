# QRFlux (闪码)

> 纯 MoonBit 二维码无损文件传输——把二维码从「扫码跳转」升级为「无网环境下的文件传输媒介」。

[![Made with MoonBit](https://img.shields.io/badge/MoonBit-0.1.20261104-blue)](https://www.moonbitlang.com)
[![Version](https://img.shields.io/badge/version-0.2.0-blue)](./CHANGELOG.md)
[![License](https://img.shields.io/badge/License-Apache--2.0-green)](./LICENSE)
[![Tests](https://img.shields.io/badge/tests-1287%2F1287-brightgreen)](./src)
[![Cross-validation](https://img.shields.io/badge/zxing--cpp-165%2F165-brightgreen)](./scripts)

**QRFlux** 用纯 MoonBit 实现了完整的二维码无损文件传输链路：**压缩选档 → 二进制分片 → 动态 QR 码流 → 扫码重组 → 无损还原验证**。零三方依赖——QR 编码器、GF(256) 域运算、Reed-Solomon ECC、LT 喷泉码全部自研。

在无网环境（内网、野外、涉密场所、设备间直连），传统传输手段受限。QR 码只需一部能扫码的手机即可接收，天然适配「无网、低带宽、点对点」场景。QRFlux 让这条链路完整跑通，且自带自研全版本解码器，编解码双向闭环。

## 当前状态

48 轮迭代 + 图像入口（T0.5）与多格式（T0.6）交付后项目可发布。**1332/1332 测试全绿，165/165 交叉验证通过**（2026-11-15 本机实测）。详细用法见 [USAGE.md](USAGE.md)。

## 能力清单

| 能力 | 状态 |
|------|------|
| QR 编码器（V1~V40 全版本，L/M/Q/H 四档纠错） | ✅ |
| 自研 QR 解码器（V1~V40 全版本全模式，矩阵入口） | ✅ |
| **图像入口解码（截图/像素 → 矩阵，自研全链路）** | ✅ |
| **透视校正（斜拍，homography + alignment pattern）** | ✅ V2+ |
| **PNG 文件解码（灰度/RGB/RGBA，自研 chunk + 反 filter）** | ✅ |
| **BMP 文件解码（24/32bpp + 8/1bit 调色板，自研）** | ✅ |
| 静态管线（压缩 + 打包 + 编解码） | ✅ |
| 动态码流（分片 + LT 喷泉码 + 乱序 + 丢帧恢复） | ✅ |
| 图片生成（PBM / SVG / PNG bit_depth=1） | ✅ |
| 彩色 QR 无损编解码（4 色，2bits/module） | ✅ |
| 彩色 QR RGB 识别 + SVG/PPM 图片生成 | ✅ |
| CLI 编解码双向闭环 | ✅ |
| WASM/JS 导出（wasm-gc 与 js 后端） | ⚠️ 导出符号已验证；js 后端长输入有构建上下文问题，前端走本地 API |
| 前端编解码 UI（server.js + index.html） | ✅ |
| 摄像头扫码（camera.html + jsQR） | ✅ |

## 图像入口解码（自研，零依赖）

解码器原先只接受「干净模块矩阵」，无法处理真实截图。T0.5 补齐了图像入口全链路，让**远端电脑生成 QR 图片 → 截图传输 → 本地像素解码**成为自研闭环：

```
灰度像素 → Otsu 自适应二值化 → finder 定位（1:1:3:1:1 行/列扫描交叉配对）
         → 仿射网格重采样（三点定位 + 多数投票）→ decode_qr（四向旋转重试）
```

- **输入**：灰度像素矩阵（调用方从截图 / 相机帧 / 图片文件提取像素）
- **鲁棒性**：支持缩放、平移、灰度噪声、非纯黑白屏幕、任意 90° 倍数旋转
- **透视校正**：三点仿射失败后，自动用右下 alignment pattern 锚定四点 homography 重采样（V2+ 有 alignment；V1 仅仿射）
- **等价边界**：亮度极端不均场景需调用方预处理；V1 无 alignment pattern 故不覆盖强透视

**PNG 文件直读（自研）**：`decode_png_gray(bytes)` 支持非隔行灰度（bit depth 1/2/4/8）、
RGB、灰度+Alpha、RGBA（8 位）；chunk 解析、反 filter（5 种）、位深/色彩展开自研，
zlib 解压复用 MoonBit 标准库。CLI 可直接解码截图：

```sh
# PowerShell: 把 PNG 截图转 base64 交给自研解码器
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes("shot.png"))
moon run cmd/main -- --decode-image-b64 $b64
```

真实截图端到端验证（PIL 模拟灰度 / 缩放 / 模糊 / 噪声 / RGB / V3 / V5）：

```sh
python scripts/verify_image_pipeline.py    # 16/16 OK（PNG/BMP/GIF/TIFF/JPEG/WebP 多格式 + 扰动矩阵）
```

**前端解码**：`web/camera.html` 主路径走本地 `/api/decode-image`（server.js 用 `spawnSync`
以 argv 数组转发到 CLI 自研解码器，绕过 Windows cmd.exe 的 ~8KB 命令行上限），jsQR 降级为
fallback；外部图像库不再在主路径上。

**导出面（`src/wasmapi`，foreign_library）**：`qrflux_encode_qr` / `qrflux_decode_image_png` /
`qrflux_decode_qr` 三个符号在 wasm-gc 与 js 产物中均已验证存在（`WebAssembly.Module.exports`
与 ESM `export {...}` 实测）。**未投入使用**：同一份逻辑在普通构建与 native 下正确，
但经该 foreign_library 构建在 js 后端对长输入返回错误字节（长度正确、内容错乱），
已隔离到跨包长字符串参数；详见 memory/2026-11-13.md 与 `src/wasmapi/api.mbt` 头注释。


## 验证结果

| 门禁项 | 读数 | 复现命令 |
|---|---|---|
| moon fmt --check | 通过 | `moon fmt --check` |
| moon check | 0 errors, 0 warnings | `moon check` |
| moon test --target js | **1332/1332** | `moon test --target js` |
| 交叉验证（zxing-cpp，V1~V40 全版本全纠错级全模式） | **165/165 OK** | `moon run cmd/main > batch.txt && python scripts/verify_qr.py batch.txt` |
| WASM（release） | 56968 字节（≈56KB） | `moon build --target wasm --release` |

### 测试覆盖分类（1332 个测试）

| 类别 | 数量 | 覆盖内容 |
|------|------|----------|
| 无损传输闭环 | 110 | 系统级 35 + 深度 31 + 压力 44 |
| 核心基础模块 | 74 | GF256 域运算 18 + bits 位流 15 + segment 分段 15 + tables 常量表 14 + 图片内容 12 |
| 白盒测试 | 62 | decoder 内部 28 + qrcode 内部 20 + mask 选择 8 + PNG IDAT 6 |
| 变异对照 | 21 | RS 纠错 5 + mask 3 + CRC 3 + RLE 3 + 交错 2 + 解码 3 + 喷泉码 2 |
| 彩色 QR 边界 | 23 | 颜色工厂 3 + 双射 3 + to_rgb 4 + from_rgb 3 + 编解码 4 + 图片 3 + 错误 1 + RGB 往返 1 + 尺寸 1 |
| 薄弱点打磨 | 184 | 错误分支 15 + 边界 12 + CLI 36 + web demo 8 + 内部辅助 11 + 集成 10 + 第二批 21 + 十二轮 227 + 第二轮十二轮 231 |
| 多段/管线/解码 | 153 | 多段编码 12 + 图片参数 15 + integrate 10 + 静态管线组合 18 + fountain 15 + 解码器白盒 20 + ECC 边界 18 + stream 边界 15 + decoder 鲁棒性 12 + debug_codewords 6 + web 动态 12 + Forney 回归 15 + 大版本 ECC 18 |
| Forney 修复 | 1 | RS Forney 算法 bug 修复（pos≠0 时纠错值全错 → 正确） |
| **图像入口解码** | **26** | 二值化 3 + finder 扫描 3 + 旋转 1 + 重采样 2 + 灰度图 E2E 12 + 退化/变异 5 |

> 另修复 mask 选择 bug：`bestpenalty=1<<31` 溢出导致 mask 恒为 0，修复为 `0x7FFFFFFF`。

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
cd web
node server.js
# 主页: http://localhost:3000/
# 摄像头扫码: http://localhost:3000/camera
```

前端编解码 UI 提供 4 个 API 端点（静态编码/解码、动态编码/解码），摄像头扫码页面基于 jsQR 实现实时识别。

## WASM 输出

```sh
moon build --target wasm --release
# 输出: _build/wasm/release/build/cmd/main/main.wasm (56KB)
```

WASM 绑定提供以下接口可直接在网页中调用：

- `web_encode_qr`：静态编码
- `web_encode_qr_static`：静态管线编码（压缩 + 打包）
- `web_encode_qr_dynamic`：动态码流编码（分片 + 喷泉码）
- `web_decode_qr`：解码

## 目录结构

```text
src/qr/         编码器/解码器核心（qrcode.mbt / gf256.mbt / segment.mbt / decoder.mbt / fountain.mbt / ...）
cmd/main/       CLI 入口（编解码双向闭环、批量输出矩阵供验证）
scripts/        交叉验证脚本（verify_qr.py / verify_static.py / verify_dynamic.py / ...）
web/            前端编解码 UI（server.js + index.html + camera.html + demo.html）
docs/           设计文档（API.md / COLOR_QR_DESIGN.md）
competition/    项目申报书
memory/         记忆沉淀日志
reports/        任务汇报归档
```

## 备注

- 单张静态 QR 容量上限：V40 L=2953 / M=2331 / Q=1663 / H=1273 字节；>1KB 走动态码流。
- 零三方依赖：不添加 `moon.mod` 外部依赖，所有核心算法自研。
- 彩色 QR 码方案见 `docs/COLOR_QR_DESIGN.md`（非标准，4 色 2bits/module，已实现无损编解码 + RGB 识别 + SVG/PPM 图片生成，需专用解码器）。
- 已知限制：V40 大尺寸 QR（177×177）部分第三方解码器存在解码限制（非 QRFlux 编码错误，单元测试验证编码正确，自研解码器可正常还原）。
- CLI 图片传参受命令行长度限制（base64 ≈28KB）：大图 / 强噪声截图需先缩放或裁剪 QR 区域（超限会明确报错）。
- 图像入口解码：仿射模型覆盖缩放 / 平移 / 90° 倍数旋转，**V2+ 追加透视校正**（alignment pattern 锚定 homography）；V1 无 alignment pattern，仅仿射。
- 前端图像解码经本地 server 转发给 CLI（浏览器内引擎的 js 后端长输入仍有构建上下文问题，未启用）。
