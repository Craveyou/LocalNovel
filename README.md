# XLib

XLib 是一个原生多端 TXT 阅读器 monorepo。当前包含 Android、iOS、阅读进度同步后端，以及供 Apple 平台复用的纯 Swift 阅读核心；macOS 客户端处于规划状态。

## 仓库结构

```text
xlib/
├── apps/
│   ├── android/              # Java / Gradle Android 应用
│   ├── ios/                  # SwiftUI / UIKit iOS 应用
│   └── macos/                # planned，尚无可构建应用
├── services/backend/         # TypeScript / Fastify / PostgreSQL 同步服务
├── contracts/openapi.yaml    # HTTP API 合同
├── packages/apple-shared/    # iOS/macOS 共用的纯 Swift 核心
├── docs/                     # 产品、架构、API 和功能文档
├── releases/                 # monorepo 发布清单
├── scripts/                  # 可重复的开发、构建和发布检查
└── .github/workflows/        # CI 与 release workflow
```

## 当前组件

| 组件 | 状态 | 版本 |
| --- | --- | --- |
| Android | active | `0.13.1`；build 以源码为准 |
| iOS | active | `0.13.0`；build 以源码为准 |
| Backend | active | `0.10.0` |
| macOS | planned | — |
| API contract | active | TXT `v1` / 文档 `v2` |

当前开发状态见 [CURRENT](docs/CURRENT.md)，0.14.1 是需求目标，不表示已发布。现有清单未匹配当前组件组合；0.10.0 是已发布的 SQLite 迁移基线。旧清单是历史发布记录，不作为当前能力需求。

## 快速开始

需要 Java 17、Android SDK 35、Xcode/Swift 6、Node.js 22、pnpm 11 和 Ruby。

```bash
make bootstrap
make check
```

常用入口：

```bash
make test-backend
make test-apple-shared
make build-android-debug
make build-ios-debug
make check-alpha
make release-check RELEASE=0.11.0
```

根构建入口默认保持组件版本名；Android versionCode / iOS CURRENT_PROJECT_VERSION 每次客户端构建递增。只有显式提供 `VERSION` 才更新组件版本名；不由此自动创建发布清单、提交或发布。

`make check` 默认执行开发检查（敏感数据、契约/夹具、迁移政策、发布检查回归、Backend、Kindle 核心、AppleShared、Android 单元/lint、iOS 构建），不隐式选用历史发布清单。显式 `RELEASE=<版本>` 或 `RELEASE_VERSION` 会在构建前严格校验该清单，包括 build 号；缺失或不匹配即失败。`make check-alpha` 与 `make release-check` 仍默认选择 0.12.0，正式验收应明确指定真实匹配的 `RELEASE`，不能通过改写历史记录绕过。直接运行 `release-check.sh` 时显式参数优先于环境。UI/真实 PostgreSQL 等专用回归还应使用对应测试入口，开发检查不代替全部验收。

## 环境与安全

根目录 `.env.example` 是同步后端环境变量模板：

```bash
cp .env.example .env
```

`.env`、签名密钥、keystore、Token 和构建产物不得提交。同步服务的固定 Token 模型属于 Alpha 阶段已接受的产品风险，详情见 [API 文档](docs/API.md) 和 [同步设计](docs/features/sync-server.md)。

## 文档

- [产品能力与客户端实现体系](docs/product/README.md)
- [产品愿景](docs/VISION.md)
- [当前状态](docs/CURRENT.md)
- [架构](docs/architecture.md)
- [API](docs/API.md)
- [Alpha 标准](docs/ALPHA.md)
- [决策记录](docs/DECISIONS.md)
- [iOS 当前功能与运行逻辑](docs/features/ios.md)
- [功能文档](docs/features/)

迁移前本地恢复副本存放在 `backup/`，该目录被 Git 忽略，不应提交或发布。
