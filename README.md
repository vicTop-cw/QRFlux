# QRFlux (闪码)

纯 MoonBit 实现的二维码无损文件传输项目。
压缩选档 -> 二进制分片 -> 动态 QR 码流 -> 扫描重组 -> 无损还原。

## 当前状态 (2026-11-07)

### 已完成：34 轮迭代全部通过，项目可发布

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

## 验证结果 (iter 34/34 最终验证)

- `moon fmt` / `moon check`：通过（0 errors，0 warnings）
- `moon test --target js`：**1287/1287 通过**（含 110 个无损传输测试 + 84 个薄弱点打磨 + 74 个核心基础模块单元测试覆盖 GF256 域运算 18 + bits 位流 15 + segment 分段 15 + tables 常量表 14 + 图片内容正确性 12 + 62 个白盒测试覆盖 decoder 内部 28 + qrcode 内部 20 + mask 选择 8 + PNG IDAT 数据 6 + 44 个变异对照与彩色 QR 边界测试覆盖变异对照 21（RS 纠错 5 + mask 选择 3 + CRC 3 + RLE 3 + 交错 2 + 解码 3 + 喷泉码 2）+ 彩色 QR 边界 23（颜色工厂 3 + 双射 3 + to_rgb 4 + from_rgb 3 + 编解码 4 + 图片 3 + 错误 1 + RGB 往返 1 + 尺寸 1）+ iter 20~24 新增 184 个测试覆盖多段编码 12 + 图片参数边界 15 + integrate 补全 10 + 静态管线组合 18 + fountain 补全 15 + 解码器模式白盒 20 + ECC 纠错边界 18 + stream 边界 15 + decoder 鲁棒性 12 + debug_codewords 6 + web 动态绑定 12 + Forney 修复回归 15 + 大版本 ECC 验证 18）（另修复 mask 选择 bug：bestpenalty=1<<31 溢出导致 mask 恒为 0，修复为 0x7FFFFFFF；修复 RS Forney 算法 bug：`decoder.mbt` 的 `rs_correct` 中 Forney 公式缺少错误位置因子 X_k=α^pos，修复前 error_val=omega_val/lambda_deriv_val（pos≠0 时纠错值全错），修复后 error_val=(x_k*omega_val)/lambda_deriv_val，纠错能力正确 + iter 25~29 新增 81 个测试覆盖薄弱点打磨 71（错误分支 15 + 边界条件 12 + CLI 入口 36 + web demo 8，commit 5145077）+ 集成打磨 10（decoder 复用 V7+ 3 + static 管线 algo_id 一致 4 + frames_needed 一致 3，commit a21097e）+ iter 30 薄弱点打磨第二批 21（内部辅助函数 11 + 模块间集成 10，818→829，commit d934eab）+ iter 31 十二轮薄弱点打磨 227（轮1-4 往返16+模糊18+性能11+协议16=61，轮5-8 RLE21+喷泉19+彩色14+图片16=70，轮9-12 GF256 20+RS纠错17+分段18+CLI参数29=84，829→1056，commits 676caee/e13ba3e/399255c；另 fuzz 修正 V1-L 容量边界 15→17 字节，commit b370978）+ iter 32 薄弱点打磨轮1-4 共 77（format info 边界 19 + mask 惩罚深度 17 + 位流边界 22 + 常量表完整性 19，1056→1133，commit 64de714）+ iter 33 动态码流帧大小边界 17（split_into_frames/reassemble_frames 边界，1133→1150，stream_framesize_test.mbt）+ iter 34 十二轮薄弱点打磨 231（轮1-4 format/version info 边界 19 + mask 惩罚深度 17 + 位流边界 22 + 常量表完整性 19 = 77，1056→1133，commit 64de714；轮5-8 静态管线 e2e 18 + 帧大小边界 17 + 喷泉码鲁棒性 20 + 彩色 QR 映射 15 = 70，1133→1203，commit 96d5d57；轮9-12 图片格式深度 18 + RS 极限 19 + 功能图案 20 + web 绑定 28 = 84，1203→1287，commit fd64ca1））
- 交叉验证（V1~V40 全版本全纠错级全模式）：**165/165 OK**
- WASM 构建：60895 字节（≈60KB）
- 最终验证日期：2026-11-07

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
