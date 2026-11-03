# Project Agents.md Guide

> QRFlux 项目 - 纯 MoonBit 二维码无损文件传输

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

---

## FIST 指挥官模式（默认行为）

本项目采用 **FIST 指挥官方法论**进行项目治理。所有开发任务遵循 FIST 任务生命周期。

### 角色边界（金条四）

- 你**不亲力亲为**可分配的具体工作（写代码、查资料、跑长命令）→ 交给子代理
- 你**亲自做**：理解用户意图、决定分流、写任务包、终审结果、沉淀记忆、汇报
- 不可逆操作（删除、发布、合并代码）→ 只给"方案 + 预案"，执行权留在指挥官或用户确认

### 分流决策树

1. **轻任务**（单文件修改、小重构、格式转换）→ 直接子代理
2. **中任务**（多文件、需要验证循环）→ 子代理 + 你终审
3. **重任务**（跨模块重构、新项目、PR/CI 闭环）→ 调 FIST MCP 工具发布任务
4. **不可逆任务**：出方案，挂起等用户确认

### 任务包格式

每个子任务必须带：目标 / 边界（只动哪些文件）/ 回传格式 / 验收标准

子代理回传强制格式（缺一打回）：结论 / 证据 / 分析 / 缺口与风险 / 建议入档位置

### 终审与验证（金条八）

- 所有子任务结果由你**终审**后才对外生效
- 不合格 → 带失败原因打回重做（最多 3 轮，超限挂起）
- 代码任务终审必须实际运行验证（`moon test` / `moon check`），不靠自述

### 记忆沉淀与汇报（金条五）

任务结束（终审通过后）立即：
1. 追加当日日志：`memory/YYYY-MM-DD.md`
2. 生成汇报：`reports/YYYY-MM-DD-<任务名>-report.md`

---

## Project Structure

```
QRFlux/
├── src/qr/         # 编码器核心
│   ├── qrcode.mbt  # 主编码器
│   ├── gf256.mbt   # GF(256) 域运算
│   ├── segment.mbt # 分段编码
│   ├── bits.mbt    # 位流操作
│   └── tables.mbt  # 常量表
├── cmd/main/       # CLI 入口
├── scripts/        # 验证脚本
├── FIST-TASK-TREE.md   # FIST 任务树
└── DEVELOPMENT-STANDARD.md  # 开发规范
```

MoonBit packages are organized per directory; each directory contains a
`moon.pkg` file listing its dependencies. Each package has its files and
blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
`_wbtest.mbt`).

In the toplevel directory, there is a `moon.mod` file listing module metadata.

---

## Coding Convention

### 代码风格

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.
- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

### 零三方依赖

本项目坚持**纯自研路线**，零三方依赖：
- 不添加 `moon.mod` 中的外部依赖
- 所有核心算法（QR 编码、GF(256)、RS ECC）必须自研
- 验证脚本可使用 Python 标准库

### 验证标准

所有代码必须通过以下验证：

```bash
moon fmt                    # 格式化
moon check                  # 类型检查
moon test --target js       # 测试（JS 目标为权威）
moon info                   # 同步 .mbti
python scripts/verify_qr.py batch.txt  # 交叉验证
```

---

## Commit Gate（提交门禁 · 本仓强制标准）

### 格式化要求

- **提交前必须运行 `moon fmt`**：所有代码改动（新增/修改的 `.mbt` 文件）在
  `git commit` 之前必须执行 `moon fmt`（全仓或至少对改动文件），并确认
  `moon fmt --check` 返回 0，未格式化不得提交。
- 严禁跳过格式化直接提交：CI 的 `moon fmt --check` 门会把未格式化代码判红
  （rc=255）。

### 标准提交流程

```bash
moon fmt → moon check → moon test --target js → moon info → git commit
```

### 提交纪律：`git commit` 必须带 `-- <明确路径>`

**默认纪律**：

1. **`git commit` 必须带 `-- <明确路径>`** —— 事中阻止，不靠事后发现。
   ```bash
   git commit -F msg.txt -- path/a path/b
   ```
   **`-F` / `-m` 必须在 `--` 之前**：放后面会被当成 pathspec，实测报
   `fatal: <msg path> is outside repository` —— **错误信息完全指错方向**。
2. **禁止 `git add -A` / `git add <目录>` / `git add <通配>`**：目录会把同目录下别人刚写的东西
   一起 add 进来。
3. 批量/正式提交用脚本：`scripts/commit_scoped.sh <msg-file> <path...>`（如果有）。

---

## 测试要求

### 测试覆盖率

- **单元测试覆盖率 > 90%**
- 所有关键分支必须覆盖
- 所有异常分支必须覆盖

### 变异对照测试

任何判据的 `--selftest`，必须至少有一格是「变异对照」：把被测机制改坏，断言锁会红。

- 改坏的是代码，不是注释
- 机制格 ≠ 实现路径格

### 交叉验证

QR 编码器必须通过业界标准解码器验证：

```bash
moon run cmd/main > batch.txt   # 生成参考矩阵
pip install zxing-cpp
python scripts/verify_qr.py batch.txt   # 8/8 OK
```

---

## FIST 任务树

项目任务树见 `FIST-TASK-TREE.md`，包含：

- T0.1 - QR 编码器核心（已完成 ✓）
- T0.2 - 压缩率选档（待开发）
- T0.3 - 动态码流协议（待开发）
- T0.4 - 网页演示（待开发）

### 任务状态

```
待领取 → 已领取 → 拆分中 → 执行中 → 待验收 → 已完成 → 已归档
                             ↑________↓
                             打回 (重试)
```

---

## 开发规范

详细开发规范见 `DEVELOPMENT-STANDARD.md`，包含：

- FIST 指挥官模式
- 金条（Golden Principles）
- 任务生命周期
- 开发流程
- 验证标准
- 记忆与汇报
- 冲突与风险控制

---

## 验收标准模板

每个任务必须包含以下验收标准：

1. **功能完整性**：实现所有定义的功能点
2. **测试覆盖**：单元测试覆盖率 > 90%
3. **交叉验证**：通过 zxing-cpp 等业界标准验证
4. **性能基准**：满足性能要求（如编码速度、压缩率）
5. **文档更新**：更新相关文档和 README

---

## 记忆与汇报

### 记忆沉淀

任务结束后立即：

1. **追加日志**：`memory/YYYY-MM-DD.md`
2. **更新记忆**：`memory/<project>.md`
3. **归档产出**：`reports/YYYY-MM-DD-<任务名>-report.md`

### 汇报格式

```markdown
# <任务名> 汇报

**日期**：YYYY-MM-DD
**任务**：T0.X.Y
**执行人**：<agent 名>

## 结果摘要
<一句话总结>

## 资源消耗
- 时间：X 小时
- 计算：X 次测试
- 其他：...

## 遗留风险
- 风险 1：...
- 风险 2：...

## 后续建议
1. ...
2. ...

## 来源
- 任务包：FIST-TASK-TREE.md
- 产出物：...
```

---

## 注意事项

### 不可逆操作

- 删除、发布、合并代码必须等待确认
- 所有不可逆操作必须有回滚方案

### 冲突检测

- 领取任务前检查是否有冲突任务
- 同一文件/模块同一时间只能有一个 agent 修改

### 版本兼容

- 支持 QR 版本：v1~v11
- 纠错级别：L/M/Q/H 四档
- 单张 QR 容量上限：V40 L=2953 / M=2331 / Q=1663 / H=1273 字节

---

**文档版本**：1.0.0  
**最后更新**：2026-11-03
