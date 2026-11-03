# QRFlux (闪码)

纯 MoonBit 实现的二维码无损文件传输项目。
压缩选档 -> 二进制分片 -> 动态 QR 码流 -> 扫描重组 -> 无损还原。

## 当前状态 (2026-11-03)

### 已完成：自研 QR 编码器（纯 MoonBit，零三方依赖）

- `src/qr/` 编码器核心：字节模式编码、版本/纠错级选择、GF(256) 域运算、Reed-Solomon ECC、功能图案绘制（finder/timing/alignment/format/version）、掩码选择与惩罚评分。
- 跨版本交叉验证：v1~v11、L/M/Q/H 四档纠错、10~300 字节随机负载，**8/8 全部通过**业界标准解码器（zxing-cpp）无损还原。

```text
a: ver=1  ecl=L mask=0 n=10  -> OK
b: ver=1  ecl=M mask=0 n=10  -> OK
c: ver=2  ecl=H mask=0 n=10  -> OK
d: ver=2  ecl=L mask=0 n=30  -> OK
e: ver=3  ecl=Q mask=0 n=30  -> OK
f: ver=6  ecl=M mask=0 n=100 -> OK
g: ver=9  ecl=L mask=0 n=200 -> OK
h: ver=11 ecl=L mask=0 n=300 -> OK
```

### 待办路线

- [x] QR 编码器（含 ECC、掩码）——已验证
- [x] 压缩率选档（首版可选的 deflate 级压缩 + 二进制打包）——已跳过，优先动态码流
- [x] 动态码流协议（>1KB 分片多帧 QR + LT 喷泉码）——已完成
- [ ] 网页演示（`--target js` 嵌网页 + 摄像头解码边界）

## 验证方法

```sh
moon test --target js       # 测试（JS 目标为权威）
moon run cmd/main > batch.txt   # 生成 8 组参考矩阵
pip install zxing-cpp
python scripts/verify_qr.py batch.txt   # 8/8 OK
```

## 网页演示

```sh
# 启动网页演示
cd web
node server.js
# 访问 http://localhost:3000
```

## WASM 输出

```sh
# 生成 WASM
moon build --target wasm
# 输出文件: _build/wasm/debug/build/cmd/main/main.wasm (60KB)
```

**注意**：完整的 WASM 集成需要额外的 JavaScript 绑定配置。当前 WASM 文件已生成，但需要手动创建绑定代码才能在网页中使用。

## 目录结构

```text
src/qr/         编码器（qrcode.mbt / gf256.mbt / segment.mbt / ...）
cmd/main/       CLI 入口（批量输出矩阵供验证）
scripts/        交叉验证脚本
```

## 备注

- 单张静态 QR 容量上限：V40 L=2953 / M=2331 / Q=1663 / H=1273 字节；>1KB 走动态码流。
- moon 0.1.20261016 依赖解析（moon add/import）存在 registry 兼容问题，故保持零三方依赖、纯自研路线。
