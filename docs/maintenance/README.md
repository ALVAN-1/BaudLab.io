# BaudLab 维护文档

> 本目录是 BaudLab（波特律动）的模块化维护文档，面向后续接手维护的开发者。
> 基于 v1.0.28 代码整理（2026-11-05），代码变更后请按文末「文档维护约定」同步更新。
> 全项目文档（含发布、工程待办、AGENTS.md）的总索引见 [../INDEX.md](../INDEX.md)。

## 文档目录

| 文档 | 内容 | 什么时候看 |
|---|---|---|
| [01-项目概览](01-项目概览.md) | 项目定位、技术栈、目录结构、命名约定 | 第一次接触本项目 |
| [02-架构总览](02-架构总览.md) | 进程模型、IPC、数据流、端口、安全模型 | 想理解整体设计 |
| [03-主进程模块](03-主进程模块.md) | main.js、preload.js 及各主进程模块，IPC 通道总表 | 改主进程 / 加 IPC |
| [04-渲染层模块](04-渲染层模块.md) | views / composables / components / utils | 改前端界面 |
| [05-数据存储](05-数据存储.md) | SQLite 表结构、schema 迁移、数据目录、备份 | 改表 / 查数据 |
| [06-串口与协议引擎](06-串口与协议引擎.md) | frame-codec 帧编解码、串口管理、AFT-1 文件传输 | 改协议 / 串口逻辑 |
| [07-AI与MCP接入](07-AI与MCP接入.md) | AI 助手、18 个工具、MCP 服务器与桥接 | 改 AI / MCP 功能 |
| [08-团队服务器](08-团队服务器.md) | server.js、内嵌主机、mDNS、管理台、备份 | 改服务器 / 部署 |
| [09-构建发布与更新](09-构建发布与更新.md) | 构建链、打包产物、发布流程、自动更新 | 发版本 |
| [10-开发与排障手册](10-开发与排障手册.md) | 环境搭建、日常开发、测试、FAQ、检查清单 | 日常开发 / 修 bug |

## 按场景快速导航

- **新人上手**：01 → 02 → 10（跑起来）→ 03/04（找代码）
- **改某个功能**：先在 03/04 找到模块 → 05（涉及数据时）→ 02（涉及跨进程时）
- **发一个版本**：09（构建与发布流程），配套见 [../RELEASE_AND_DEPLOYMENT.md](../RELEASE_AND_DEPLOYMENT.md)
- **排查线上问题**：10 的 FAQ 与日志说明
- **了解遗留风险**：[../ENGINEERING_TODO.md](../ENGINEERING_TODO.md)

## 速查表

### 常用命令

| 命令 | 作用 |
|---|---|
| `start.bat`（双击） | 一键开发启动：自动补依赖 + vite 构建 + 启动 Electron |
| `npm run dev:vite` | 启动 Vite dev server（5173），配合 `dev:electron` 热更新 |
| `npm run dev:electron` | 以 `--dev` 模式启动 Electron（加载 localhost:5173） |
| `npm run build` | vite 构建 + electron-builder 打 NSIS 安装包 |
| `npm run build:dir` | 只打免安装目录（dist/win-unpacked） |
| `npm run rebuild` | 按 Electron ABI 重编译原生模块（better-sqlite3 等） |
| `npm run test:updates` | 跑更新控制器测试（node --test） |
| `release-tools\start-release-tool.bat` | 打开发布工具 GUI（正式发版走这里） |

### 端口一览

| 端口 | 用途 | 归属 |
|---|---|---|
| 5173 | Vite dev server（仅开发） | 前端 |
| 3010（被占顺延 3011–3099） | 团队服务器 HTTP API | server.js / server-embed.js |
| 37655（向上找 10 个） | MCP 桥回环端点 | mcp-bridge.js |

### 关键路径

| 路径 | 内容 |
|---|---|
| `main.js` | Electron 主进程入口（package.json `main`） |
| `src/renderer/` | Vue 3 渲染层源码 |
| `dist/renderer/` | vite 构建产物（main.js 生产加载目标） |
| `data/`（开发态）| 本地数据：SQLite、配置、密钥缓存 |
| `%APPDATA%/BaudLab/data/`（打包态） | 同上，打包后的本地数据目录 |
| `db-schema.js` | 两端共用的表结构与迁移（**改表只改这里**） |
| `scripts/afterPack.js` | 打包后处理：裁剪体积、拷贝 MCP / 服务器运行时 |

## 文档维护约定

- **改了表结构** → 同步 05；**改了 IPC / 主进程模块** → 同步 03；**改了页面** → 同步 04。
- **改了构建 / 打包 / 发布流程** → 同步 09，并核对 `../RELEASE_AND_DEPLOYMENT.md`。
- **发现新的坑** → 先记入 `../ENGINEERING_TODO.md`，修完后在 10 的 FAQ 里沉淀通用结论。
- 文档中的版本敏感信息（版本号、端口段、目录名）改代码时顺手核对一遍。
- 每篇文档开头标注「适用版本」，大版本升级时统一刷新。
