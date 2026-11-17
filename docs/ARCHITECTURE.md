# DeepSeek Chat · HarmonyOS 7 原生移植架构

以 `deepseek-ai/chat-demo` 为行为基准，用 ArkTS 原生重写；目标 API 26 / HarmonyOS 7，`targetSdkVersion = compatibleSdkVersion = 26.0.0`。

## 1. 组件清单与来源

| 能力 | 采用方案 | 来源 | 决策 |
|---|---|---|---|
| Markdown / 表格 / 代码块 / LaTeX | `@luvi/lv-markdown-in` 3.4.7（ohpm，MIT，byteCodeHar，API 12+） | Gitee `luvi/lv-markdown-in` | **复用**，不自己写解析器 |
| Mermaid | 同库代码块渲染 | 三方库 | 图表预览默认关闭，避免 ArkWeb appfreeze |
| 代码块复制 / 文本选择复制 | `MarkdownController.setCodeCopyListener` + 系统 pasteboard | 三方库 + 官方 API | 复用 + 自写回调 |
| 聊天外壳、消息流、流式状态机 | ArkUI 自写 | — | **自写**；不采用 `changweizhang/ChatUI`（API 9 时代、无流式/思考/引用） |
| 顶栏 / 会话侧栏 / 输入区 / 设置面板 | ArkUI 自写 | — | 自写 |
| 沉浸光感（标题栏按钮、半模态） | `uiMaterial.ImmersiveMaterial` + `Button.systemMaterial` + module metadata `ohos.arkui.UIMaterial.state=enable` | 华为官方 API 26 | **复用官方** |
| 回退样式 | `softColor` / `border`，深色由 `Palette` 控制 | 官方 ArkUI | 复用 |
| 会话列表 | `List` + `ForEach`（v1）；大列表可换 `LazyForEach` + `IDataSource` | 官方 ArkUI | 自写 |
| 消息持久化 | `relationalStore`（RDB） | 官方 ArkData | 自写 DAO |
| API Key | `AssetStoreKit`（asset） | 官方 | 自写封装；模拟器失败回退 preferences |
| 设置 | `preferences` | 官方 | 自写 |
| 网络 / SSE | `rcp` + `onDataReceive` + `util.TextDecoder({stream:true})` | 官方 RemoteCommunicationKit；拆包方案参考华为开发者问答 | 自写 |
| 语音输入 | `AudioCapturer` 16 kHz 单声道 PCM → 手写 WAV → `/v1/tools/asr` | 官方 AudioKit | 自写 |
| 朗读 | `/v1/tools/tts` PCM 24 kHz → `AudioRenderer` | 官方 AudioKit | 自写 |
| 附件 | `PhotoViewPicker` / `DocumentViewPicker` + `fileIo.copyFile` | 官方 CoreFileKit / MediaLibraryKit | 自写 |
| 触感反馈 | `vibrator` | 官方 SensorServiceKit | 自写 |
| 图标 | 本地 SVG（中性色固定） | — | 自写 |

## 2. 工程框架（实际落地文件）

```
entry/src/main/ets/
├── entryability/EntryAbility.ets       窗口全屏、状态栏、loadContent
├── model/
│   ├── Types.ets                       会话/消息/附件/设置（@Observed）
│   └── Protocol.ets                    Anthropic 兼容协议、SSE 事件、工具/引用
├── pages/
│   └── Index.ets                       聊天页：Navigation 自定义标题栏、消息 List、Composer、双 Sheet
├── service/
│   ├── ApiClient.ets                   RCP 流式、Files、ASR/TTS、Key 校验
│   ├── SseDecoder.ets                  增量 UTF-8 + SSE 帧解析
│   ├── ChatEngine.ets                  协议拼装、事件归并、60ms 刷 UI、700ms 落库
│   ├── ChatRepository.ets              RDB 会话与消息
│   ├── SecretStore.ets                 Asset 密钥
│   ├── SettingsStore.ets               Preferences
│   ├── AttachmentService.ets           选择器、落盘、文本抽取
│   ├── SpeechService.ets               录音/播放/权限
│   └── HapticService.ets               触感
├── view/
│   ├── MarkdownContent.ets             lv-markdown-in 封装、主题热切换、复制/链接回调
│   ├── MessageItem.ets                 用户气泡 / 助手消息 / 思考折叠 / 工具态 / 引用 / 复制/重试/朗读
│   ├── Composer.ets                    输入、图片/文本附件、语音、发送/停止
│   ├── WelcomePanel.ets                空态与建议
│   ├── SessionPanel.ets                会话列表（手机 Sheet / 平板侧栏共用）
│   ├── SettingsSheet.ets               Key、模型、思考/搜索、字号、音色、触感、清空
│   └── common/Theme.ets                颜色、Markdown 主题
└── utils/
    └── TextUtils.ets                   toast / copy / openLink / 时间格式
```

## 3. 数据流

```
Composer
  → Index.send()
  → ChatEngine.send()
  → prepareAttachments()（图片先 POST /anthropic/v1/files）
  → DeepSeekClient.streamMessages()
  → rcp session.fetch(POST /anthropic/v1/messages)
  → Configuration.tracing.httpEventsHandler.onDataReceive(ArrayBuffer)
  → SseDecoder.feed() → StreamEvent
  → ChatMessage.content/thinking 累加（@Observed）
  → 60ms 节流刷 UI；700ms 节流 saveMessage
  → message_delta.title 更新会话标题
```

- UI 侧消息对象是 `@Observed`，`MessageItem` 用 `@ObjectLink` 接收增量；`ChatEngine` 只做数组快照通知结构变化。
- 历史只回传 `user` 文本/图片 + `assistant` 文本；不回传历史 thinking/signature，也不回传工具块（v1 简化）。
- 标题只在首轮且会话标题仍为“新对话”时请求，`title:{enabled:true}`；读取 `message_delta.delta.title`，失败时用首条用户文本截断兜底。

## 4. API 26 适配点

- `module.json5` 增加 `metadata: ohos.arkui.UIMaterial.state = enable`，让支持组件级材质的组件获得沉浸光感。
- 标题栏使用自定义 `@Builder`，内部圆形 `Button` 加 `.systemMaterial(material)`：`ImmersiveMaterial({ style: THIN, interactive: true, colorInvert, lightEffect: { color: brand } })`。
  - `isImmersiveMaterialSupported()` 为 false 或构造异常时，`immersive=false`，按钮回退 `softColor` 背景。
- 窗口 `setWindowLayoutFullScreen(true)` + 只保留状态栏。全屏布局**不会自动避让**状态栏/手势条，因此 `Index.aboutToAppear` 通过 `getWindowAvoidArea(TYPE_SYSTEM / TYPE_NAVIGATION_INDICATOR)` 取 px 高度，`UIContext.px2vp` 后在根 `Row` 上/下 padding；窗口非全屏时自动跳过，避免双倍留白。
- 深色模式走 `ConfigurationConstant.ColorMode` 与 `Palette`；Markdown 代码块主题同步 `light/dark`；启动页另有 `resources/dark/element/color.json` 防白闪。
- Markdown 的 Mermaid / HTML 内联预览依赖 ArkWeb。API 26 x86_64 模拟器创建 Web 组件时出现 `THREAD_BLOCK_6S` appfreeze，`applyMarkdownTheme` 默认 `setMermaidEnable(false)` / `setHtmlPreviewEnable(false)`；Mermaid 以代码块展示，LaTeX 仍走原生 `formula` 库。
- `setWindowSystemBarEnable(['status'])` 在 2in1 上不可用，已有 catch；后续可按设备类型规避。

## 5. v1 功能边界

已做：API Key 校验与安全存储、会话 CRUD、自动标题、流式、深度思考折叠、联网搜索/读链接状态、Markdown/表格/代码/LaTeX、Mermaid 代码块回退、图片与文本附件、语音输入、朗读、复制/重试/停止、深浅色、平板侧栏、触感、沉浸光感按钮。

暂不做：消息分支树、ZIP 历史导入导出、PDF/Word/PPT 富版面解析（扩展模式不支持 document）、服务卡片、后台保活。以上列入 roadmap。

## 6. 构建

项目级 `hvigorw` 来自旧模板，与 `hvigor-config.json5` 的 `modelVersion: 6.1.0` 不兼容；使用 DevEco 全局 CLI：

```powershell
$env:DEVECO_SDK_HOME='D:\Program Files\Huawei\DevEco Studio\sdk'
$env:Path='D:\Program Files\Huawei\DevEco Studio\tools\node;D:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin;' + $env:Path
Set-Location -LiteralPath 'E:\Harmony\DeepSeekChat'
& 'D:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --mode module -p product=default --no-daemon
```

Release 构建追加 `-p buildMode=release`；`entry/obfuscation-rules.txt` 保留默认 ArkGuard 行为，不主动开启属性/顶层名称混淆。

产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`，尚未配置正式签名。模拟器签名版另存为 `entry/build/default/outputs/default/entry-default-emulator-signed.hap`（OpenHarmony 调试证书，仅对 `HGHUB_API26` 的 UDID 有效）。已在 API 26 x86_64 模拟器完成安装，验证首屏、设置、Key 校验、流式对话、Markdown 表格/代码块、LaTeX 公式、Mermaid 代码块回退、自动标题、停止生成与会话抽屉；真机/上架仍需 DevEco 华为账号自动签名或正式 Profile。

**插曲**：同一 `Navigation` 上绑定两个 `bindSheet` 时，后绑定的设置 Sheet 会覆盖会话 Sheet，导致会话菜单无响应。现改为单 `bindSheet` + `sheetMode`（0=会话，1=设置）切换 `SheetBuilder`，模拟器已验证菜单可正常打开。
