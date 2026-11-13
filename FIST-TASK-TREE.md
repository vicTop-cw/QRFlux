# QRFlux FIST 任务树

> 基于 FIST 指挥官方法论的项目治理结构
> 版本：0.1.0 | 创建日期：2026-11-03

## 项目概览

**项目名称**：QRFlux (闪码)  
**项目描述**：纯 MoonBit 二维码无损文件传输  
**当前状态**：48 轮迭代全部完成，项目处于可发布状态（1287/1287 单元测试通过，165/165 交叉验证通过，0 warnings，彩色QR+前端UI+摄像头扫码+无损传输深度测试+无损传输压力测试+薄弱点打磨测试+核心基础模块单元测试+decoder/编码器白盒测试+mask选择bug修复+变异对照测试+彩色QR边界测试+多段编码/图片参数/integrate/静态管线组合/fountain补全/解码器模式白盒/ECC纠错边界/stream边界/decoder鲁棒性/debug_codewords/web动态绑定/Forney修复回归/大版本ECC验证全部完成）

---

## 任务树结构 (T0 Root)

```
T0 (Root) - QRFlux 完整项目
├── T0.1 - QR 编码器核心 (已完成 ✓)
│   ├── T0.1.1 - 字节模式编码
│   ├── T0.1.2 - 版本/纠错级选择
│   ├── T0.1.3 - GF(256) 域运算
│   ├── T0.1.4 - Reed-Solomon ECC
│   ├── T0.1.5 - 功能图案绘制
│   └── T0.1.6 - 掩码选择与惩罚评分
│
├── T0.2 - 压缩率选档 (已完成 ✓)
│   ├── T0.2.1 - deflate 级压缩实现
│   ├── T0.2.2 - 二进制打包协议
│   └── T0.2.3 - 压缩率策略选择
│
├── T0.3 - 动态码流协议 (已完成 ✓)
│   ├── T0.3.1 - 分片多帧 QR 协议
│   ├── T0.3.2 - LT 喷泉码实现
│   └── T0.3.3 - 重组与验证逻辑
│
└── T0.4 - 网页演示 (已完成 ✓)
    ├── T0.4.1 - JS target 编译适配
    ├── T0.4.2 - 网页 UI 与交互
    └── T0.4.3 - 摄像头解码边界 (已完成 ✓)
```

---

## 任务详情

### T0.1 - QR 编码器核心 ✓ (已完成)

**状态**：已完成  
**验收标准**：v1~v11、L/M/Q/H 四档纠错、10~300 字节随机负载，8/8 通过 zxing-cpp 无损还原  
**产出物**：
- `src/qr/qrcode.mbt` - 编码器核心
- `src/qr/gf256.mbt` - GF(256) 域运算
- `src/qr/segment.mbt` - 分段编码
- `src/qr/bits.mbt` - 位流操作
- `src/qr/tables.mbt` - 常量表

---

### T0.2 - 压缩率选档 (已完成 ✓)

**状态**：已完成  
**优先级**：高  
**K 值**：2 (可继续分解)  
**预估工时**：3-5 天  
**验收标准**：RLE 压缩 + 二进制打包协议 + 策略选择，单元测试通过  

#### T0.2.1 - deflate 级压缩实现

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：实现可选 deflate 压缩层  
**边界**：
- 只动：`src/qr/` 新增压缩模块
- 不动：现有编码器核心  
**验收标准**：
- 支持无压缩/快速/标准/最优四级
- 压缩率可测量，输出可还原
- 单元测试覆盖率 > 90%

#### T0.2.2 - 二进制打包协议

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：定义文件头 + 负载的二进制打包格式  
**边界**：
- 只动：`src/qr/` 打包模块 + `scripts/` 验证脚本
- 不动：编码器核心

#### T0.2.3 - 压缩率策略选择

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：根据文件大小和类型自动选择压缩策略

---

### T0.3 - 动态码流协议 (已完成 ✓)

**状态**：已完成  
**优先级**：最高  
**K 值**：2 (可继续分解)  
**预估工时**：5-7 天  
**验收标准**：分片多帧 QR + LT 喷泉码 + 重组验证，端到端测试通过  

#### T0.3.1 - 分片多帧 QR 协议

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：定义 >1KB 文件的分片协议  
**边界**：
- 只动：`src/qr/` 分片模块 + `cmd/main/` CLI
- 不动：编码器核心
**验收标准**：
- 支持单文件分片为多帧 QR
- 帧头包含：总帧数、当前帧、校验和
- 重组后无损还原

#### T0.3.2 - LT 喷泉码实现

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：实现 Luby Transform 喷泉码，支持任意数量丢包恢复

#### T0.3.3 - 重组与验证逻辑

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：实现接收端的重组与验证逻辑

---

### T0.4 - 网页演示 (已完成 ✓)

**状态**：已完成  
**优先级**：中  
**K 值**：2 (可继续分解)  
**预估工时**：3-5 天  
**验收标准**：JS target 编译 + 网页 UI + WASM 集成（60KB），演示可运行  

#### T0.4.1 - JS target 编译适配

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：确保核心代码可编译为 JS 目标

#### T0.4.2 - 网页 UI 与交互

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：实现文件上传、QR 显示、扫描交互

#### T0.4.3 - 摄像头解码边界

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：实现摄像头扫码解码，处理边界情况

---

### T0.5 - 图像入口解码 (已完成 ✓)

**状态**：已完成 ✓  
**优先级**：最高（初审关键缺口：解码器只吃干净矩阵，无法从截图/图片解码）  
**K 值**：2 (可继续分解)  
**背景**：真实应用场景是「远端电脑生成 QR 图片 → 截图传输 → 本地解码」。当前 `decode_qr` 只接受 0/1 干净矩阵，图像 → 矩阵的入口层（二值化/定位/采样）完全缺失，前端扫码依赖外部 jsQR，交叉验证依赖外部 zxing-cpp。本任务补齐自研像素入口，形成「自研编解码 + 图片级闭环」。

#### T0.5.1 - 灰度二值化

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：灰度像素矩阵 → 0/1 位图（Otsu 全局自适应阈值）  
**验收标准**：明暗分离正确；全白/全黑边界优雅报错；单元测试覆盖

#### T0.5.2 - finder 定位

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：行/列扫描 1:1:3:1:1 模式定位三个 finder（左上/右上/左下），推算 module 像素尺寸与 QR 版本  
**验收标准**：合成图定位准确；少于三个 finder 优雅报错

#### T0.5.3 - 模块重采样

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：由三个 finder 中心建立仿射网格，逐 module 邻域多数投票采样 → N×N 干净矩阵  
**验收标准**：放大/平移后采样还原正确；朝向未知时四向旋转重试

#### T0.5.4 - 像素解码入口

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：`decode_from_pixels(gray)` 串联二值化 → 定位 → 采样 → `decode_qr`  
**验收标准**：与 `encode_qr` 端到端无损还原

#### T0.5.5 - 图像级 E2E 测试

**状态**：已完成 ✓  
**K 值**：1 (原子任务)  
**目标**：矩阵 → 放大 → 平移 → 灰度噪声 → 像素解码闭环；变异对照（改坏定位阈值断言锁红）  
**验收标准**：多版本/多缩放/多旋转全绿

---

## 任务状态机

```
待领取 → 已领取 → 拆分中 → 执行中 → 待验收 → 已完成 → 已归档
                             ↑________↓
                             打回 (重试)
```

**状态说明**：
- **待领取**：任务可用，等待 agent 领取
- **已领取**：agent 已认领，正在规划
- **拆分中**：任务正在被分解为子任务
- **执行中**：agent 正在开发
- **待验收**：产出物已提交，等待验证
- **已完成**：验证通过，任务完成
- **已归档**：冻结存档，不可修改
- **打回**：验证失败，需要重试

---

## 验收标准模板

每个任务必须包含以下验收标准：

1. **功能完整性**：实现所有定义的功能点
2. **测试覆盖**：单元测试覆盖率 > 90%
3. **交叉验证**：通过 zxing-cpp 等业界标准验证
4. **性能基准**：满足性能要求（如编码速度、压缩率）
5. **文档更新**：更新相关文档和 README

---

## 下一步行动

1. **领取任务**：agent 选择待领取任务
2. **规划方案**：制定详细开发方案
3. **执行开发**：按方案实施
4. **提交验收**：提交产出物和验证报告
5. **终审归档**：验证通过后归档

---

## 48 轮迭代完成总结

| 迭代 | 内容 | 结果 |
|------|------|------|
| iter(1/14) | QR 编码器核心 | 8/8 交叉验证通过 |
| iter(2/14) | 动态码流完整 | 端到端测试通过 |
| iter(3/14) | WASM 集成 | 导出函数完成，60KB WASM |
| iter(4/14) | 摄像头扫码 | 原型完成 |
| iter(5/14) | 压缩算法优化 | 改进 RLE 压缩 |
| iter(6/14) | 性能优化 | 添加性能测试 |
| iter(7/14) | 测试覆盖度提升 | 添加边界测试 |
| iter(8/14) | 文档完善 | 添加 API 文档 |
| iter(9/14) | 彩色 QR 原型 | 4 色 QR 实现 |
| iter(10/14) | API 设计 | 统一接口文档 |
| iter(11/14) | 错误处理 | 边界情况测试 |
| iter(12/14) | 最终验证 | 66/66 单元测试通过，8/8 交叉验证通过 |
| iter(13/14) | 无损传输深度测试 | 66 个闭环测试（35 系统 + 31 深度），245 测试基线 |
| iter(14/14) | 无损传输压力测试 | 新增 44 个压力测试（性能基准 8 / 模糊测试 15 / 版本补全 13 / 乱序丢帧 8），245→289，文件 `src/qr/lossless_stress_test.mbt` |
| iter(15/18) | 薄弱点打磨 | CLI辅助21+编码器深度20+解码器错误11+协议错误12+策略补全12+Web绑定8=84个，289→373 |
| iter(16/18) | 核心基础模块 | gf256域运算18+bits位流15+segment分段15+tables常量表14+图片内容12=74个，373→447 |
| iter(17/18) | decoder白盒+编码器白盒 | decoder内部28+qrcode内部20+mask选择8+PNG_IDAT6=62个，447→509 |
| iter(18/18) | mask选择bug修复 | `bestpenalty=1<<31`溢出导致mask恒为0，修复为`0x7FFFFFFF`，509/509通过 |
| iter(19/19) | 变异对照+彩色QR边界 | 变异对照21（RS纠错5+mask选择3+CRC3+RLE3+交错2+解码3+喷泉码2）+彩色QR边界23（颜色工厂3+双射3+to_rgb4+from_rgb3+编解码4+图片3+错误1+RGB往返1+尺寸1）=44个，509→553，batch.txt重新生成 |
| iter(20/24) | 多段编码/图片参数/integrate/静态管线组合/fountain补全 | 新增5个测试文件70个测试：multi_segment_test(12)+image_params_test(15)+integrate_extra_test(10)+static_combo_test(18)+fountain_extra_test(15)，553→623，commit c833619 |
| iter(21/24) | 解码器模式白盒/ECC纠错边界/stream边界/decoder鲁棒性/debug_codewords | 新增5个测试文件71个测试：decoder_mode_wbtest(20白盒)+decoder_ecc_boundary_test(18)+stream_boundary_test(15)+decoder_robustness_test(12)+debug_codewords_test(6)，623→691，commit 7481296 |
| iter(22/24) | web动态绑定 | 新增1个测试文件12个测试：web_dynamic_test(web_encode_dynamic 8+wasm_calculate_frames 4)，691→703，commit e68519d，至此所有公开函数均有测试覆盖 |
| iter(23/24) | Forney修复回归 | 修复RS Forney算法bug：decoder.mbt的rs_correct中Forney公式缺少错误位置因子X_k=α^pos，修复前error_val=omega_val/lambda_deriv_val（pos≠0时纠错值全错），修复后error_val=(x_k*omega_val)/lambda_deriv_val，新增forney_regression_wbtest(15白盒)+更新decoder_robustness_test(新增1个双bit翻转测试)，703→719，commit 120f9ea |
| iter(24/24) | 大版本ECC验证 | 新增big_version_ecc_test(18黑盒)：V15/V20/V30/V40各4个ECC级翻转1~4个data bit严格验证+2个无错误基线(V20 M/V40 H)，V40 H有20个RS块是最复杂交错场景，719→737，commit 62f4c9e |
| iter(25/29) | 文档数字同步 | 24 轮/737 同步至文档，无代码改动，commit 14bbcc4 |
| iter(26/29) | 无改动巡检 | 门禁全绿 737/737，无待办 |
| iter(27/29) | .gitignore 卫生修复 | 忽略 .codeartsdoer/ 索引目录，commit 8c5087d |
| iter(28/29) | 无改动巡检 | 门禁全绿 737/737，项目进入稳定期 |
| iter(29/29) | 遗留测试产出提交+文档同步 | 薄弱点打磨 71（737→808，commit 5145077）+ 集成打磨 10（808→818，commit a21097e），818/818 全绿 |
| iter(30/30) | 薄弱点打磨第二批 | 内部辅助函数 11 + 模块间集成 10，818→829，commit d934eab |
| iter(31/31) | 十二轮薄弱点打磨 | 227 个测试（轮1-4 61 + 轮5-8 70 + 轮9-12 84 + fuzz 修正），829→1056，commits 676caee/e13ba3e/399255c/b370978 |
| iter(32/32) | 薄弱点打磨轮1-4 | 77 个测试（format info 边界 19 + mask 惩罚深度 17 + 位流边界 22 + 常量表完整性 19），1056→1133，commit 64de714 |
| iter(33/33) | 薄弱点打磨轮5-8 | 70 个测试（静态管线 e2e 18 + 帧大小边界 17 + 喷泉码鲁棒性 20 + 彩色 QR 映射 15），1133→1203，commit 96d5d57 |
| iter(34/34) | 薄弱点打磨轮9-12 | 84 个测试（图片格式深度 18 + RS 极限 19 + 功能图案 20 + web 绑定 28），1203→1287，commit fd64ca1 |
| iter(35~48) | 稳定期门禁巡检 | 14 轮无改动巡检，门禁全绿 1287/1287，项目进入稳定期，commits 5eb2d1d~83d7dad |

> 截至 2026-11-07，项目已扩展至 1287/1287 测试，新增彩色QR无损编解码、自研全版本解码器（V1~V40）、前端UI、摄像头扫码、无损传输深度测试（喷泉码丢帧/大文件/容量边界/彩色QR/管线/稳定性/图片格式，66 个闭环测试 = 35 系统 + 31 深度）、无损传输压力测试（44 个，覆盖性能基准 8 / 模糊测试 15 / 版本补全 13 / 乱序丢帧 8 四个维度，文件 `src/qr/lossless_stress_test.mbt`）、薄弱点打磨测试（84 个，覆盖 CLI 辅助 21 + 核心编码器深度 20 + 解码器错误 11 + 协议错误 12 + 策略补全 12 + Web 绑定 8）、核心基础模块单元测试（74 个，覆盖 GF256 域运算 18 + bits 位流 15 + segment 分段 15 + tables 常量表 14 + 图片内容正确性 12，5 个文件：src/qr/gf256_test.mbt、src/qr/bits_test.mbt、src/qr/segment_test.mbt、src/qr/tables_test.mbt、src/qr/image_content_test.mbt）、decoder/编码器白盒测试（62 个，覆盖 decoder 内部 28 + qrcode 内部 20 + mask 选择 8 + PNG IDAT 数据 6，4 个文件：src/qr/decoder_internals_wbtest.mbt、src/qr/qrcode_internals_wbtest.mbt、src/qr/mask_selection_test.mbt、src/qr/png_data_test.mbt）、mask 选择 bug 修复（bestpenalty=1<<31 溢出导致 mask 恒为 0，修复为 0x7FFFFFFF）、变异对照测试（21 个，覆盖 RS 纠错 5 + mask 选择 3 + CRC 3 + RLE 3 + 交错 2 + 解码 3 + 喷泉码 2，文件 src/qr/variant_contrast_test.mbt）、彩色 QR 边界测试（23 个，覆盖颜色工厂 3 + 双射 3 + to_rgb 4 + from_rgb 3 + 编解码 4 + 图片 3 + 错误 1 + RGB 往返 1 + 尺寸 1，文件 src/qr/color_qr_edge_test.mbt）、iter 20 多段编码/图片参数/integrate/静态管线组合/fountain 补全测试（70 个，5 个文件：src/qr/multi_segment_test.mbt 12 + src/qr/image_params_test.mbt 15 + src/qr/integrate_extra_test.mbt 10 + src/qr/static_combo_test.mbt 18 + src/qr/fountain_extra_test.mbt 15，commit c833619）、iter 21 解码器模式白盒/ECC 纠错边界/stream 边界/decoder 鲁棒性/debug_codewords 测试（71 个，5 个文件：src/qr/decoder_mode_wbtest.mbt 20 白盒 + src/qr/decoder_ecc_boundary_test.mbt 18 + src/qr/stream_boundary_test.mbt 15 + src/qr/decoder_robustness_test.mbt 12 + src/qr/debug_codewords_test.mbt 6，commit 7481296）、iter 22 web 动态绑定测试（12 个，1 个文件：src/web/web_dynamic_test.mbt，覆盖 web_encode_dynamic 8 + wasm_calculate_frames 4，commit e68519d，至此所有公开函数均有测试覆盖）、iter 23 RS Forney 算法 bug 修复及回归测试（修复 decoder.mbt 的 rs_correct 中 Forney 公式缺少错误位置因子 X_k=α^pos，修复前 error_val=omega_val/lambda_deriv_val 导致 pos≠0 时纠错值全错，修复后 error_val=(x_k*omega_val)/lambda_deriv_val 即正确 Forney 公式 e_k=X_k·Ω(X_k^{-1})/Λ'(X_k^{-1})，新增 src/qr/forney_regression_wbtest.mbt 15 白盒 + 更新 src/qr/decoder_robustness_test.mbt 新增 1 个双 bit 翻转测试，共 16 个，commit 120f9ea）、iter 24 大版本 ECC 验证测试（18 个，1 个文件：src/qr/big_version_ecc_test.mbt，V15/V20/V30/V40 各 4 个 ECC 级翻转 1~4 个 data bit 严格验证 + 2 个无错误基线 V20 M/V40 H，V40 H 有 20 个 RS 块是最复杂交错场景，commit 62f4c9e），165/165 交叉验证通过，0 warnings。iter 25 文档数字同步（24 轮/737 同步至文档，无代码改动，commit 14bbcc4）、iter 26 无改动巡检（门禁全绿 737/737）、iter 27 .gitignore 卫生修复（忽略 .codeartsdoer/ 索引目录，commit 8c5087d）、iter 28 无改动巡检（门禁全绿 737/737，项目进入稳定期）、iter 29 遗留测试产出提交（薄弱点打磨 71 个测试：错误分支 15 + 边界条件 12 + CLI 入口 36 + web demo 8，737→808，commit 5145077；集成打磨 10 个测试：decoder 复用 V7+ 3 + static 管线 algo_id 一致 4 + frames_needed 一致 3，808→818，commit a21097e），818/818 全绿。iter 30 薄弱点打磨第二批（21 个测试：内部辅助函数 11 + 模块间集成 10，818→829，commit d934eab），829/829 全绿。

> iter 32-34 薄弱点打磨轮1-12 共 231 个测试（iter 32 轮1-4 77 个 1056→1133 commit 64de714；iter 33 轮5-8 70 个 1133→1203 commit 96d5d57；iter 34 轮9-12 84 个 1203→1287 commit fd64ca1），12 个新方向：format/version info 边界 | mask 惩罚深度 | 位流边界 | 常量表完整性 | 静态管线 e2e | 帧大小边界 | 喷泉码鲁棒性 | 彩色 QR 映射 | 图片格式深度 | RS 极限 | 功能图案 | web 绑定

**最终验证日期**：2026-11-07  
**最终验证结果**：
- `moon fmt`：通过
- `moon check`：0 errors，0 warnings
- `moon test --target js`：1287/1287 通过
- `moon info`：0 errors
- 交叉验证（V1~V40 全版本全纠错级全模式）：165/165 OK
- WASM 构建：60895 字节（≈60KB）

**已知限制**：
- V40 大尺寸 QR（177×177）zxing-cpp 解码器无法解码（非 QRFlux bug，单元测试验证编码正确）
