# DeepSeek Chat for HarmonyOS

把 DeepSeek 官方 React 静态站 [`deepseek-ai/chat-demo`](https://github.com/deepseek-ai/chat-demo) 移植为 **HarmonyOS 7 / API 26 原生 ArkTS 应用**。

- Bundle：`com.tinse.deepseekchat`
- 目标 / 兼容 SDK：`26.0.0`
- 设备：phone / tablet / 2in1
- 构建产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`
- 当前状态：**debug / release 均 BUILD SUCCESSFUL**；release unsigned HAP 已产出；已在 **API 26 x86_64 模拟器 HGHUB_API26** 安装并完成端到端功能测试（启动、设置、真实 Key 校验、流式对话、Markdown 表格/代码块、自动标题、停止生成、会话抽屉）；未做真机测试

---

## 1. 开源调研结论

检索 GitHub / Gitee 后没有发现 `deepseek-ai/chat-demo` 的成熟 HarmonyOS 移植。能找到的鸿蒙聊天实现大多是通用 UI 模板，例如：

- Gitee `changweizhang/ChatUI`：API 9 时代聊天 UI，只有列表/气泡/输入框，没有 DeepSeek 的 SSE 流式、thinking/signature、引用、自动标题、联网搜索工具块。
- 各类 HarmonyOS 聊天 demo：偏向 IM 会话，不包含 Anthropic 兼容协议。
- 另有一类 **DeepSeek Harness / DSH** 的鸿蒙封装（Electron / ArkWeb + Node），属于另一套 Agent 工作台工程，不是 `chat-demo` React 静态站的移植，不能直接复用。

因此采用“**协议与聊天外壳自写，Markdown 渲染复用成熟三方库，系统能力全部走官方 API**”的方案。

| 模块 | 方案 | 决策 |
|---|---|---|
| Markdown / 表格 / 代码块 / LaTeX | `@luvi/lv-markdown-in` 3.4.7（ohpm，MIT） | 复用，不自己写解析器 |
| Mermaid | 同库代码块展示；ArkWeb 图表预览默认关闭 | 避免模拟器主线程阻塞（见实测记录） |
| 代码复制 / 文本选择复制 / 链接跳转 | 该库 `MarkdownController` + 系统 pasteboard / `openLink` | 复用 + 自写回调 |
| 聊天外壳、流式状态机、思考面板、引用 chips | ArkUI 自写 | 自写 |
| 会话持久化 | `relationalStore` RDB | 自写 DAO |
| API Key | `AssetStoreKit`，失败回退 `preferences` | 自写封装 |
| 设置 | `preferences` | 自写 |
| 网络 / SSE | `RemoteCommunicationKit`（RCP）`onDataReceive` + 增量 UTF-8 解码 | 自写 |
| 语音输入 / 朗读 | `AudioCapturer` / `AudioRenderer` + ASR / TTS | 自写 |
| 图片 / 文本附件 | `PhotoViewPicker` / `DocumentViewPicker` + `fileIo` | 自写 |
| 沉浸光感按钮 | API 26 `uiMaterial.ImmersiveMaterial` + `Button.systemMaterial` + module metadata | 复用官方 |
| 触感 | `vibrator` | 自写 |

---

## 2. 工程结构

```
entry/src/main/ets/
├── entryability/EntryAbility.ets      全屏窗口、状态栏、入口
├── model/
│   ├── Types.ets                      ChatMessage / ChatSession / Attachment / AppSettings
│   └── Protocol.ets                   Anthropic 兼容请求、SSE 事件、工具与引用
├── pages/Index.ets                    聊天页：Navigation 标题栏、消息列表、输入区、双 Sheet
├── service/
│   ├── ApiClient.ets                  RCP 流式、Files、ASR/TTS、Key 校验
│   ├── SseDecoder.ets                 增量 UTF-8 + SSE 帧解析
│   ├── ChatEngine.ets                 协议拼装、事件归并、60ms 刷 UI、700ms 落库
│   ├── ChatRepository.ets             RDB 会话 / 消息 CRUD
│   ├── SecretStore.ets                Asset 密钥（preferences 兜底）
│   ├── SettingsStore.ets              Preferences 设置
│   ├── AttachmentService.ets          相册 / 文档选择、沙箱落盘、文本读取
│   ├── SpeechService.ets              16k 录音 WAV、24k PCM 播放、麦克风权限
│   └── HapticService.ets              轻触反馈
├── utils/TextUtils.ets                toast / copy / openLink / 时间
└── view/
    ├── MarkdownContent.ets            lv-markdown-in 封装、主题热切换、代码复制
    ├── MessageItem.ets                用户气泡、助手消息、思考折叠、引用、复制/重试/朗读
    ├── Composer.ets                   输入、图片/文本附件、语音、发送/停止
    ├── WelcomePanel.ets               空态与建议
    ├── SessionPanel.ets               会话列表（抽屉 / 平板侧栏共用）
    ├── SettingsSheet.ets              Key、模型、思考/搜索、字号、音色、触感、清空
    └── common/Theme.ets               深浅色调色板与 Markdown 主题
```

---

## 3. 与 chat-demo 的协议对齐

| 能力 | 接口 | 关键点 |
|---|---|---|
| 校验 Key | `GET https://api.deepseek.com/models` | `Authorization: Bearer`，不产生费用 |
| 对话 | `POST /anthropic/v1/messages` | `x-api-key` + `anthropic-version: 2023-06-01` + `accept: text/event-stream` |
| 图片 / 文件 | `POST /anthropic/v1/files` | multipart，字段 `file`；图片不传 `purpose`；请求带 `anthropic-beta: files-api-2025-04-14` |
| 删除文件 | `DELETE /anthropic/v1/files/{id}` | 清理上传文件 |
| 语音识别 | `POST /v1/tools/asr` | multipart `file`，WAV 16k 单声道 16bit |
| 朗读 | `POST /v1/tools/tts` | `{text, voice_id, format:'pcm', filter_markdown:true}`，返回 24k PCM |
| 自动标题 | 请求体 `title:{enabled:true}` | 仅首轮且标题仍为“新对话”时请求；读取 `message_delta.delta.title` |

请求体关键字段：

```json
{
  "model": "deepseek-flash",
  "system": "该助手为DeepSeek，由深度求索公司创造。",
  "messages": [],
  "thinking": { "type": "enabled" },
  "tools": [
    { "type": "deepseek_read_url", "name": "deepseek_read_url" },
    { "type": "deepseek_web_search", "name": "deepseek_web_search" }
  ],
  "safety_check": { "level": "high" },
  "stream": true
}
```

SSE 处理：

- `message_start`：记录 usage（input tokens）
- `content_block_start`：`text` / `thinking` / `server_tool_use` / `web_search_tool_result` / `web_fetch_tool_result`
- `content_block_delta`：`text_delta` / `thinking_delta` / `signature_delta` / `citations_delta`
- `message_delta`：`stop_reason` / `title` / usage
- `message_stop` / `ping`
- 网络流结束后统一 `SseDecoder.flush()`，避免末尾没有换行的最后一帧丢失。

历史上下文按 chat-demo 行为简化：只回传 user 文本 + 图片 file_id，以及 assistant 文本；不回传历史 thinking/signature 与工具块，避免上下文膨胀。

---

## 4. API 26 / HarmonyOS 优势

- **沉浸光感**：`module.json5` 开启 `ohos.arkui.UIMaterial.state=enable`；标题栏圆形按钮使用 `uiMaterial.ImmersiveMaterial` + `Button.systemMaterial`，`interactive:true` 与 `lightEffect` 提供触控流光。设备不支持时自动回退到 `softColor` 背景，不出现空白按钮。
  - 关键约束：`systemMaterial` 只在支持组件级材质的组件上生效，因此标题栏用自定义 `@Builder` + 圆形 `Button`，不依赖 `Navigation` 默认标题按钮。
- **RCP**：`session.fetch` + `Configuration.tracing.httpEventsHandler.onDataReceive` 直接拿到 `ArrayBuffer`，配合增量 UTF-8 解码处理 SSE 拆包；`session.cancel` 支持停止生成。
- **RDB**：`relationalStore` 存储 sessions/messages，`ON_CONFLICT_REPLACE` 幂等写入；流式期间 700ms 节流落库，结束时强制落库。
- **Asset Store**：API Key 写入 `AssetStoreKit`，`Accessibility.DEVICE_FIRST_UNLOCKED`；不支持时透明回退 preferences。
- **音频**：录音 16k/单声道/S16LE，手写 44 字节 WAV 头；播放 24k PCM，`AudioRenderer` 分片写入后 `drain`。
- **响应式**：`onAreaChange` 判断宽度 ≥840vp，平板/2in1 显示常驻会话侧栏；手机使用 `bindSheet` 抽屉。
- **公式与图表**：LaTeX 走 `lv-markdown-in` 原生 `formula` 库渲染；Mermaid / HTML 预览依赖 ArkWeb，在 API 26 x86_64 模拟器初始化时会阻塞主线程并触发 `appfreeze`，因此默认关闭 `setMermaidEnable(false)` / `setHtmlPreviewEnable(false)`，Mermaid 以可复制的代码块展示。
- **深浅色**：`Palette` + Markdown 控制器主题同步；`uiMaterial` 的 `colorInvert` 跟随深色。

---

## 5. 构建

### DevEco Studio

打开 `E:\Harmony\DeepSeekChat`，`Build > Build Hap(s)/APP(s) > Build Hap(s)`。

### 命令行（Windows PowerShell）

项目根目录自带的 `hvigorw.bat` 来自旧模板，与 `hvigor-config.json5` 的 `modelVersion: 6.1.0` 不兼容（会报 `startsWith` 空引用）。请使用 DevEco 自带全局 CLI：

```powershell
$env:DEVECO_SDK_HOME='D:\Program Files\Huawei\DevEco Studio\sdk'
$env:Path='D:\Program Files\Huawei\DevEco Studio\tools\node;D:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin;' + $env:Path
Set-Location -LiteralPath 'E:\Harmony\DeepSeekChat'
& 'D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --mode module -p product=default --no-daemon
```

Release 构建追加 `-p buildMode=release`（使用 `entry/obfuscation-rules.txt`，默认不开启激进的名称混淆）：

```powershell
& 'D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --mode module -p product=default -p buildMode=release --no-daemon
```

已验证输出：

```
BUILD SUCCESSFUL in 19 s
entry/build/default/outputs/default/entry-default-unsigned.hap
```

### 模拟器实测记录（2026-11-17）

- 实例：`HGHUB_API26`，HarmonyOS `7.0.0.107(SP8DEVC00E999R4P11)`，ABI `x86_64`，分辨率 1080×1920。
- 启动命令：
  ```powershell
  & 'D:\Program Files\Huawei\DevEco Studio\tools\emulator\Emulator.exe' -start HGHUB_API26 -instancePath "$env:LOCALAPPDATA\Huawei\Emulator\deployed"
  ```
- 安装：`hdc install -r` 返回 `install bundle successfully`，`aa start -a EntryAbility -b com.tinse.deepseekchat` 成功，进程存活。
- 已验证：
  - 首屏、欢迎卡片、输入框、设置 Sheet 正常渲染；
  - API Key 输入、`/models` 校验（真实 Key 返回“Key 有效，模型列表已通过”）、保存与重启后保留；
  - 真实流式对话：SSE 增量输出正常，Markdown 表格、TypeScript 代码块、代码复制按钮正常渲染；
  - LaTeX：二次公式原生渲染通过；
  - Mermaid：不加 ArkWeb 预览，mermaid 代码块稳定展示；不复现图表渲染导致的 `THREAD_BLOCK_6S` appfreeze；
  - `message_delta.title` 自动标题生效（由“新对话”变为“表格与TS代码示例”）；
  - 生成中停止：消息进入“已停止”状态，工具状态“已完成搜索”可见；
  - 会话抽屉：修复了同一 `Navigation` 绑定两个 `bindSheet` 导致会话 Sheet 被设置 Sheet 覆盖的问题，改为单 Sheet + `sheetMode` 切换；菜单、新建、会话切换正常；
  - 设置持久化：联网搜索开关关闭后保存，重新打开设置仍为关闭；
  - 冷启动：`force-stop` 后重新启动，会话与 LaTeX 公式、代码块仍正常加载，进程存活。
- 测试中曾触发一次 `THREAD_BLOCK_6S` appfreeze：Mermaid/HTML 内联预览创建 ArkWeb Web 组件时阻塞主线程。已默认关闭 `setMermaidEnable(false)` / `setHtmlPreviewEnable(false)`，Mermaid 以可复制代码块展示；LaTeX 原生公式不受影响，修复后冷启动与再次对话均稳定。
- 未覆盖：真机、图片/文件附件、录音 ASR、TTS 朗读、深色模式切换。

### 签名与安装

工程默认不配置签名，`entry-default-unsigned.hap` 不能直接安装；模拟器调试签名版为 `entry/build/default/outputs/default/entry-default-emulator-signed.hap`（仅对当前模拟器实例有效）。

- **本次模拟器测试**：使用 SDK 自带 OpenHarmony 调试签名材料生成仅限当前模拟器实例的 debug profile，未使用华为开发者账号；HGHUB_API26 接受并安装成功。该签名不是华为发布签名，不能用于真机或上架。
- **真机 / 上架**：仍需在 DevEco Studio 登录华为开发者账号，使用 `Automatically generate signature` 或申请正式 Profile；`%USERPROFILE%\.ohos\config` 中现有的调试 Profile 绑定其他 Bundle，不能直接复用给当前 Bundle。

---

## 6. 使用

1. 首次启动点击右上角设置，填入 `sk-...`，点“验证”。
2. 选择模型：`deepseek-flash`（日常、响应快）或 `deepseek-v4-pro`（深度思考）。
3. 可开关深度思考 / 联网搜索；联网搜索时模型可能调用 `deepseek_web_search` / `deepseek_read_url`，消息中会显示工具状态与引用 chips。
4. 输入框左侧 `+` 选择图片（最多 4 张）或文本文件（最多 2 个，≤256 KB）。
5. 麦克风按钮录音（≤120 秒），结束后自动调用 ASR 填入输入框。
6. 助手消息底部支持复制 / 重新生成 / 朗读；生成中可点停止。

---

## 7. 已知限制 / Roadmap

- 真机未验证；API 26 x86_64 模拟器 HGHUB_API26 已完成安装与核心链路测试。当前 release HAP 仍为 unsigned，模拟器测试使用自签 OpenHarmony debug profile；上架/真机需华为开发者账号正式签名。
- Mermaid 不渲染为图表，按代码块展示；HTML 代码块预览同样关闭，避免 ArkWeb 内联组件在模拟器主线程阻塞。真机/更高算力可再评估开启 ArkWeb 预览池。
- 历史上下文 v1 只回传文本与图片，不回传历史 thinking/signature/工具块；后续可按 chat-demo `reply.ts` 完整回传。
- 文本附件只支持纯文本类后缀（txt/md/json/csv/log/xml/yaml），不支持 PDF/Word/PPT 版面解析。
- 会话列表当前 `ForEach`；会话量很大时可换 `LazyForEach` + `IDataSource`。
- 无消息分支树、ZIP 导入导出、服务卡片、后台保活。
- 沉浸光感效果依赖设备算力与系统支持；低算力设备由系统降级为颜色/阴影方案。

---

## 8. 依赖与许可

- `@luvi/lv-markdown-in` 3.4.7 — MIT，Gitee `luvi/lv-markdown-in`
- `@luvi/html2md`、`@cangjie-tpc/formula_hybrid`、`@cangjie-tpc/prism_hybrid` — 随 Markdown 库安装
- 官方系统 Kit：ArkUI、AbilityKit、ArkData、CoreFileKit、MediaLibraryKit、AudioKit、SensorServiceKit、AssetStoreKit、RemoteCommunicationKit、NetworkKit

DeepSeek 名称与图标归深度求索公司所有；本项目为学习/移植示例，非官方客户端。
