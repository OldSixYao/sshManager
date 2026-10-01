# SSH Manager

一个原生 SwiftUI 的 macOS 小工具，用于管理本机 `~/.ssh/config` 与 API 密钥：主机增删改查、分组搜索、一键调起终端连接、端口转发管理、密钥与指纹查看，以及 LLM API Key（BaseURL / 密钥 / 模型 / 官网）的管理与连通性测试。

不引入自有配置格式、不碰密钥内容、不常驻后台——`~/.ssh/config` 始终是唯一事实来源，命令行 `ssh` 和其他工具照常工作。

---

## 目录

- [功能特性](#功能特性)
- [使用说明](#使用说明)
- [技术栈](#技术栈)
- [环境要求](#环境要求)
- [构建 / 运行 / 测试](#构建--运行--测试)
- [架构与代码结构](#架构与代码结构)
- [数据与安全模型](#数据与安全模型)
- [常见问题](#常见问题)
- [已知边界（首版）](#已知边界首版)

---

## 功能特性

| 功能 | 说明 |
|---|---|
| 主机管理 | 表单式新增 / 编辑 / 删除 `~/.ssh/config` 中的 Host 块（别名、HostName、用户、端口、密钥、跳板、转发等） |
| 快速连接 | 一键在 iTerm2（新建标签页）或 Terminal.app（新建窗口）中执行 `ssh <alias>` |
| 分组与搜索 | 分组存放在独立元数据文件中，不污染 ssh config；按名称 / 主机名 / 用户 / 标签搜索 |
| 端口转发 | 管理 LocalForward / RemoteForward，一键后台启停 `ssh -N -L/-R` 进程，显示运行状态与错误输出 |
| 密钥与指纹 | 扫描 `~/.ssh` 密钥并展示指纹；浏览 known_hosts、查询主机指纹、一键哈希化 known_hosts |
| API 密钥管理 | 管理 LLM API Key（名称 / BaseURL / 密钥 / 官网 / 多模型），一键复制（密钥默认打码）、连通性测试、复制 curl 示例、打开官网 |
| 生效配置 | 详情页查看 `ssh -G <alias>` 输出的最终生效配置（含全局默认值合并结果） |
| 自动刷新 | 外部（编辑器 / 命令行）修改 `~/.ssh/config` 后自动重新加载 |
| 自动备份 | 每次写盘前自动备份原文件，保留最近 10 份 |

---

## 使用说明

### 启动与界面

```bash
open dist/SSHManager.app        # 或直接双击
```

主界面为三栏布局：

```
┌────────────┬──────────────┬──────────────────────────┐
│  侧栏       │  主机列表      │  详情面板                  │
│            │  (可搜索)     │                          │
│  全部主机   │  ▸ host-a    │  host-a                  │
│  ▸ 分组 1   │  ▸ host-b    │  root@10.0.0.1:22        │
│  ▸ 分组 2   │              │  [连接] [编辑…] [删除…]      │
│            │              │  连接信息 / 转发 / 其他选项    │
│  工具       │              │                          │
│  端口转发   │              │                          │
│  密钥与…    │              │                          │
└────────────┴──────────────┴──────────────────────────┘
```

- **侧栏**：`全部主机` 按分组浏览；`工具` 区进入端口转发管理页和密钥管理页
- **主机列表**：顶部搜索框实时过滤（匹配别名 / 主机名 / 用户 / 标签）；右键行可连接 / 编辑 / 删除
- **详情面板**：选中主机后展示全部信息与操作

### 主机管理

- **新增**：工具栏 `+` 按钮，或菜单栏 文件 → 新建主机（`⌘N`）
- **编辑**：详情面板 `编辑…`，或列表右键 → 编辑
- **删除**：详情面板 `删除…`（有确认弹窗），或列表右键 → 删除
- **表单字段**：
  - 基本：别名（空格分隔可设多个，如 `web web01`）、HostName、用户、端口、分组
  - 认证：IdentityFile（文件选择器，自动存为 `~/...` 缩写形式）、IdentitiesOnly、ServerAliveInterval
  - 跳板 / 代理：ProxyJump、ProxyCommand
  - 转发：本地转发、远程转发（每行一条，如 `8080:localhost:80`）
  - 其他选项：config 中表单未覆盖的指令（如自定义 `ForwardAgent`）在此原样保留并写回
- 保存校验：别名必填且不能含空格、端口 1–65535、转发条目必须含 `:`

### 分组

分组与 SSH config 无关，保存在独立元数据文件中（详见[数据与安全模型](#数据与安全模型)）：

- 编辑表单里填写分组名（或从已有分组中选取）
- 详情面板右上角的分组下拉可直接换组
- 删除主机时其分组信息一并清理

### 快速连接

- 详情面板 `连接` 按钮 / 列表右键 → 连接
- 默认调起 **iTerm2** 并在当前窗口新建标签页执行 `ssh <alias>`；未装 iTerm2 时自动回退 Terminal.app（新窗口）
- 可在 `⌘,` 设置页手动切换终端
- 通配符模式块（如 `Host *`）不可直接连接

### 端口转发

1. 在主机编辑表单中添加本地 / 远程转发条目（即写入 config 的 `LocalForward` / `RemoteForward`）
2. 侧栏 → `端口转发` 进入管理页，或在主机详情页直接操作单条转发
3. `启动`：后台运行 `ssh -N -o ExitOnForwardFailure=yes -L/-R <spec> <alias>`
4. 运行状态以绿点标识；`停止` 发送 SIGTERM 结束进程
5. 进程启动后 2 秒内退出视为失败，会展示 ssh 的 stderr（如端口占用错误）
6. 工具栏 `全部停止` 一键停掉所有转发进程

### 密钥与 known_hosts

- **密钥列表**：扫描 `~/.ssh` 下的密钥文件（自动跳过 config、known_hosts、备份等），显示位数、SHA256 指纹、算法、注释；带 `.pub` 配对的会标注；无 `.pub` 的私钥也能读取指纹；加密私钥会提示无法读取
- 每行可在访达中显示原文件
- **known_hosts**：显示记录条数、已哈希条目数、每条记录的主机名与算法
- **哈希化**：一键执行 `ssh-keygen -H`（会自动生成 `known_hosts.old` 备份），把明文主机名替换为不可逆哈希，防止泄露连接过的主机列表

### 生效配置

主机详情页 → `查看生效配置`：执行 `ssh -G <alias>` 并展示最终生效的完整配置（含全局默认、模式匹配合并后的结果），排查"为什么连不上 / 走了哪个密钥"时很有用。

### 数据与文件位置

| 文件 | 用途 |
|---|---|
| `~/.ssh/config` | 唯一的主机配置事实来源（应用直接读写） |
| `~/.ssh/config.sshm-backup-<时间戳>` | 每次写盘前的自动备份，保留最近 10 份 |
| `~/Library/Application Support/SSHManager/metadata.json` | 分组 / 标签元数据（按主别名存储） |
| `~/Library/Application Support/SSHManager/apikeys.json` | API 密钥库（600 权限，原子写入） |
| `~/.ssh/known_hosts` / `known_hosts.old` | 主机指纹库及其哈希化备份 |

---

## 使用说明：API 密钥

管理 LLM API Key（OpenAI 兼容约定为主）。侧栏 → `API 密钥` → `全部密钥`。

- **新增 / 编辑 / 删除**：列表右上角 `+` 或详情页 `编辑…`；字段为名称、BaseURL、网站（可选）、API Key（可切换明文/掩码）、模型列表（可多个）
- **搜索**：按名称 / 供应商 / 域名 / 模型实时过滤
- **供应商分组**：编辑表单里填写供应商名（可新建或从已有选择），侧栏 API 密钥区按供应商分组浏览（带数量徽标）；详情页右上角可快捷改组；选已有供应商会自动带出其 BaseURL / 网站 / AI 厂商
- **AI 厂商**：以「图标 + 名称」芯片网格选择（OpenAI / Claude / DeepSeek / Gemini / 智谱 GLM / Kimi / 通义千问 / Grok / Mistral / 通用），列表与详情页显示厂商徽章
- **导入到 CC Switch**：详情页或右键菜单一键生成 `ccswitch://v1/import` 深度链接（app 类型按厂商映射：claude→claude、gemini→gemini、其余→codex），由 CC Switch 弹窗确认后完成导入；需本机装有 CC Switch
- **一键复制**：详情页 BaseURL、API Key、每个模型旁都有复制按钮；API Key 默认完整显示（空间放不下自动中段省略），可点眼睛按钮临时隐藏；编辑表单中默认为掩码输入
- **连通性测试**：详情页 `连通性测试` 按钮请求 `{BaseURL}` 的模型列表接口（`/v数字` 结尾的路径接 `/models`，否则拼 `/v1/models`），结果显示有效性、延迟与原因（401/403 密钥无效、429 有效但限流、404 端点不对等）
- **自动获取模型**：编辑表单里填好 BaseURL 与 API Key 后，点「自动获取模型」拉取该 key 可用的全部模型 id 并去重合并进模型列表（兼容 OpenAI `data[].id` 与 Gemini 风格 `models[].name` 两种响应）
- **复制 curl 示例**：生成可直接回车的 `curl -s <models-url> -H "Authorization: Bearer <key>"`（含真实密钥，便于终端调试）
- **打开官网**：一键跳转服务商控制台
- **存储**：`~/Library/Application Support/SSHManager/apikeys.json`，权限 600、原子写入；连通性测试只会访问你自己填写的 BaseURL

---

## 技术栈

| 层 | 技术 |
|---|---|
| 语言 | Swift 6.4 工具链（Swift 5 语言模式，规避严格并发检查的迁移成本） |
| UI | SwiftUI（`NavigationSplitView` / `Form` / `Grid`，macOS 14+）+ AppKit（`NSOpenPanel`、`NSWorkspace`） |
| 状态管理 | `ObservableObject` + `@Published` + `@EnvironmentObject`，单例 AppModel 持有全部应用状态 |
| 并发 | 主线程驱动的 UI 状态；子进程与文件 IO 用 `DispatchQueue` / `Task.detached` 派发 |
| 子进程封装 | 自研 `ShellTask`（stdin 接 /dev/null、带超时、收集 stdout/stderr），驱动 `ssh` / `ssh-keygen` / `osascript` |
| 终端集成 | AppleScript（`osascript`）：iTerm2 新建标签页、Terminal.app 新建窗口 |
| 进程管理 | `Foundation.Process` 运行端口转发，`readabilityHandler` 采集 stderr，`terminationHandler` 上报状态 |
| 文件监听 | `DispatchSourceFileSystemObject`（vnode 事件 + 防抖 + 原子替换后自动重挂） |
| 配置解析 | 自研 OpenSSH config 解析器（Host/Match 块、`Key value` 与 `Key=value`、引号值、Include 递归展开、glob(3)） |
| 图标 | CoreGraphics + CoreText 程序化绘制（无外部素材），`sips` + `iconutil` 生成 icns |
| 测试 | swift-testing（`import Testing` / `@Test` / `#expect`） |
| 构建 | SwiftPM（`swift-tools-version:5.9`）+ 自写 shell 脚本组装 .app bundle + ad-hoc codesign |

设计原则：**不自己实现任何密码学与协议**——指纹、生效配置、哈希化全部委托系统 OpenSSH 工具。

---

## 环境要求

### 运行

- macOS 14.0 及以上（Apple Silicon / Intel 均可，本项目在 arm64 上构建）
- 系统自带 OpenSSH（`/usr/bin/ssh`、`/usr/bin/ssh-keygen`）
- 可选：iTerm2（更好的标签页体验；未装则回退 Terminal.app）

### 构建

需要以下二者之一：

| 环境 | 说明 |
|---|---|
| 完整 Xcode | 无特殊处理，脚本自动走默认构建 |
| 仅 Command Line Tools | ⚠️ 需要规避一个已知问题，见下 |

**⚠️ 仅装 CLT 的机器必须注意**：macOS 27 SDK 中 SwiftUI 的 `@State` 等属性包装器已改为宏实现（`SwiftUIMacros`），而 CLT 不随附该宏插件，直接 `swift build` 会报
`plugin for module 'SwiftUIMacros' not found`。本项目脚本的规避方案：

- 用 `--build-system native` + `-Xswiftc -sdk MacOSX26*.sdk` 编译（26.x SDK 中 `@State` 仍是普通属性包装器；默认的 swiftbuild 构建系统会忽略 `-Xswiftc -sdk`，必须换 native）
- 测试改用 swift-testing（CLT 不带 XCTest），并显式传 `-F /Library/Developer/CommandLineTools/Library/Developer/Frameworks`

这些逻辑已内置在 `build.sh` / `test.sh` 中，无需手动处理。

---

## 构建 / 运行 / 测试

```bash
./build.sh          # swift build release + 组装 dist/SSHManager.app + ad-hoc 签名
open dist/SSHManager.app
./test.sh           # 运行 swift-testing 测试套件（解析 / 块级写回 / 备份 / Include）
```

图标重新生成（修改 `Scripts/make_icon.swift` 后）：

```bash
swift Scripts/make_icon.swift Resources/icon_1024.png
./Scripts/make_icns.sh
./build.sh
```

---

## 架构与代码结构

```
sshManager/
├── Package.swift                 # SwiftPM：executableTarget + testTarget
├── build.sh / test.sh            # 构建（含 CLT 规避逻辑）/ 测试
├── Scripts/
│   ├── make_icon.swift           # CoreGraphics 绘制图标母版
│   └── make_icns.sh              # 母版 → 全尺寸 icns
├── Resources/                    # icon_1024.png + AppIcon.icns
└── Sources/SSHManager/
    ├── SSHManagerApp.swift       # @main 入口、菜单命令（⌘N）、Settings 场景
    ├── Models/
    │   ├── SSHHost.swift         # SSHHost / PortForward / RawOption / HostMetadata
    │   └── APIKey.swift          # APIKey（名称 / BaseURL / 密钥 / 官网 / 多模型）
    ├── Services/
    │   ├── ConfigParser.swift    # OpenSSH config 解析 → 块 + 行区间
    │   ├── ConfigWriter.swift    # 块级文本手术（替换 / 追加 / 删除）+ 校验
    │   ├── ConfigStore.swift     # 原子写（tmp+rename，600 权限）+ 时间戳备份
    │   ├── AppModel.swift        # 应用状态：主机列表、分组元数据、增删改
    │   ├── APIKeyStore.swift     # apikeys.json 原子读写（600 权限）
    │   ├── APIKeysModel.swift    # API 密钥状态 + 自动持久化
    │   ├── APIKeyTester.swift    # URL 规范化 / curl 生成 / 打码 / 连通性测试
    │   ├── TerminalLauncher.swift# osascript 调起 iTerm2 / Terminal
    │   ├── ForwardRunner.swift   # 端口转发进程生命周期管理
    │   ├── KeyInspector.swift    # ssh-keygen / ssh -G / known_hosts 封装
    │   └── SettingsStore.swift   # 偏好设置（默认终端等）
    ├── Views/
    │   ├── ContentView.swift     # NavigationSplitView + 侧栏
    │   ├── HostsPane.swift       # 主机列表（搜索 / 右键菜单）+ 详情切换
    │   ├── HostDetailView.swift  # 详情、连接、转发启停、生效配置
    │   ├── HostEditorSheet.swift # 主机新增 / 编辑表单
    │   ├── APIKeysPane.swift     # API 密钥列表 + 详情（复制 / 测活 / 官网）
    │   ├── APIKeyEditorSheet.swift # API 密钥新增 / 编辑表单
    │   ├── ForwardingView.swift  # 全部转发的管理页
    │   ├── KeysView.swift        # SSH 密钥指纹 + known_hosts
    │   └── SettingsView.swift    # 设置页
    └── Utils/
        ├── ShellTask.swift       # 子进程封装（超时 / 管道）
        ├── Glob.swift            # glob(3) 封装（Include 展开）
        └── ConfigWatcher.swift   # config 文件变化监听
```

核心数据流：`ConfigStore` 读文件 → `ConfigParser` 解析为带行区间的块 → UI 展示 → 编辑时 `ConfigWriter` 只对目标块做文本替换 → `ConfigStore` 备份 + 原子写回 → `ConfigWatcher`/手动刷新重新解析。

---

## 数据与安全模型

写坏用户的 `~/.ssh/config` 是这类工具最大的风险，本项目用四层防护：

1. **块级文本手术**：不做整文件重生成。解析时记录每个 Host 块在文件中的行区间，编辑 / 删除只替换目标块，其余内容（注释、全局配置、Match 块）逐字节原样保留
2. **未知指令保真**：表单未覆盖的指令（如 `ProxyCommand`）进入「其他选项」，编辑时原样跟随块写回，不丢失、不改写
3. **原子写入**：同目录临时文件 + rename，权限固定 `600`，不会出现写了一半的 config
4. **写前备份**：每次保存先复制一份 `~/.ssh/config.sshm-backup-<时间戳>`（同秒多次写入自动加序号），自动保留最近 10 份

其他安全相关的取舍：

- **只读边界**：Include 引用文件中的主机以只读展示（首版不允许应用内修改）；Match 块与全局指令只保留不编辑
- **不碰密钥**：应用只调用 `ssh-keygen -lf` 读取指纹，从不读取 / 存储 / 传输私钥内容
- **无网络行为**：除你主动触发的 ssh 连接外，应用自身不发起任何网络请求
- **known_hosts 哈希化**是显式确认操作，且 `ssh-keygen -H` 自带 `.old` 备份

---

## 常见问题

**Q: 编辑保存后 diff 显示整个文件变了？**
只有在文件含 CRLF 换行时才会整体规范化为 LF（解析器统一换行处理）。纯 LF 文件只会变更目标块。

**Q: 点了连接没反应？**
检查设置页（`⌘,`）选择的终端是否已安装；iTerm2 需要"当前窗口"存在或允许新建窗口（默认允许）。

**Q: 端口转发启动后立刻显示红色错误？**
看错误文本，最常见是本地端口被占用（`bind [::]:8080: Address already in use`）或需要跳板的机器不可达。

**Q: 外部改了 config 但应用没刷新？**
侧栏顶部有刷新按钮；文件监听基于 vnode 事件，编辑器若用"另存为替换文件"方式写入也会触发（监听会自动重挂）。

**Q: 想恢复某次修改？**
到 `~/.ssh/` 找 `config.sshm-backup-*`，按时间戳选一份覆盖回 `config` 即可（应用会自动重新加载）。

---

## 已知边界（首版）

- Include 引用文件中的主机只读展示，不支持应用内编辑（你的 config 无 Include 时无影响）
- Match 块与全局指令只保留不编辑
- 不做应用内嵌终端、不做密钥生成、不做多配置文件管理
- Terminal.app 调起为新窗口（其 AppleScript 无免辅助权限的新建标签页 API）
- macOS 26 侧栏 `List(selection:)` 存在点击不可靠的系统问题，本项目已改用按钮行 + 手动高亮规避
