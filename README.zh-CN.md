[English](README.md) | 中文

<p align="center">
  <img src="docs/app-icon.png" alt="Friday 应用图标" width="128" height="128">
</p>

# Friday

[![CI](https://github.com/FlyingFSR/friday/actions/workflows/ci.yml/badge.svg)](https://github.com/FlyingFSR/friday/actions/workflows/ci.yml)
[![最新版本](https://img.shields.io/github/v/release/FlyingFSR/friday)](https://github.com/FlyingFSR/friday/releases/latest)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![平台](https://img.shields.io/badge/platform-macOS%2013%2B%20arm64-lightgrey)](#运行要求)

**为中英混说而做的 macOS 本地语音输入。** 按住一个键说话,松手,文字就转写好并直接落在
你正在用的那个应用的光标处。转写全程在本机跑,用的是
[whisper.cpp](https://github.com/ggerganov/whisper.cpp),不上云、不需要账号、没有任何
遥测,录音不会离开你的 Mac。

<p align="center">
  <img src="docs/demo.gif" alt="Friday 演示 —— 按住快捷键、说话、松手" width="500">
</p>

> Friday 待在菜单栏里,不按快捷键就不打扰你。它是给那些想口述、又不愿意把自己的声音
> 送到别人服务器上的人用的。

<p align="center">
  <a href="https://github.com/FlyingFSR/friday/releases/latest"><b>⬇&nbsp; 下载最新版本</b></a><br>
  <sub>目前是未签名的预览版,第一次打开需要走一遍 <a href="#安装下载版">「仍要打开」</a>。也可以 <a href="#开发">从源码构建</a>。</sub>
</p>

## 功能

- **中英混说听写** —— Friday 存在的理由。一口气里中英文来回切换,句子不会被吞掉;
  配有品牌词和技术词的偏置与后处理,并在 0.4.0 用一套录好的评测样本调过
  (中文字错误率 3.8% → 2.2%,英文词错误率 28.6% → 3.8%;详见
  [评测记录](docs/language-detection-findings-2026-08.md) 和 [已知限制](#已知限制))。
- **全部在本机跑** —— 用 `whisper.cpp` 转写,录音不出这台机器。
- **快捷键可选** —— 右/左 Command、右/左 Option、右 Control 任选一个,按住录音、松手转写。
  默认仍是右 Command。
- **粘到任何地方** —— 文字插在当前光标处,之后会把剪贴板还原回去。
- **认得安全输入框** —— 密码框之类的受保护场景会自动拒绝粘贴。
- **首次使用有引导** —— 权限授予和模型下载都有向导带着走。

## 运行要求

- Apple 芯片的 Mac(macOS 13 及以上)
- **下载的正式版本不需要额外装东西** —— 安装包里自带了 `whisper-server` 和运行库。

## 安装(下载版)

1. 从 [Releases](https://github.com/FlyingFSR/friday/releases/latest) 下载最新的 zip,
   把 `Friday.app` 拖进「应用程序」文件夹。
2. 目前的发布包还没签名,所以在一台干净的 Mac 上第一次打开时,系统会弹出
   「Apple 无法验证 Friday」,并且只给「完成」和「移到废纸篓」两个选项。点**完成**。
3. 打开**系统设置** → **隐私与安全性**。
4. 在**安全性**一栏里,给 Friday 点**仍要打开**。
5. 再确认一次**仍要打开**,然后输入管理员密码。

这套绕行只适用于早期测试版本。正式发布之前应该先做 Developer ID 签名和公证,
才谈得上「双击就能装」。

第一次启动时,需要授予 macOS 对语音输入工具要求的三项权限:

1. **麦克风** —— 用来采集你的说话声
2. **辅助功能** —— 用来把文字粘进别的应用
3. **输入监控** —— 用来识别按住快捷键这个动作

然后确认 **Medium** 模型已经装好,在菜单栏或设置向导里选一个快捷键,试一下:
按住、说话、松手。

## 模型

- Friday 只带一个转写模型:**Medium**。它在日常中英文听写上够准,内存占用也不重。
- 模型下载到 `~/Library/Application Support/Friday/models`
- 下载体积大致是:Medium 约 1.5 GB
- 语音活动检测(VAD)分段的代码已经完整实现,但当前版本**默认关闭**,还在验证质量;
  只有开启 VAD 时才会去下载 Silero VAD 模型(参见 [已知限制](#已知限制);设计过程记录在
  [docs/VAD_CHANGELOG.md](docs/VAD_CHANGELOG.md),语言:英文)

## 已知限制

Friday 还是早期软件。有几件事我宁可写清楚 —— 这里是简版,带测量数据和推理过程的
完整版在 [docs/LIMITATIONS.md](docs/LIMITATIONS.md)(语言:英文)。

- **中英混说仍有边角情况。** 整段录音目前还是一次解码、只自动判定一种语言。0.4.0 修掉了
  英文里的中文插句被整句丢掉、以及整段英文被误翻成中文这两个故障,但被救回来的中文插句
  仍可能带错字,长段中文叙述里也可能残留几个繁体字。0.4.0 的评测是单一说话人的 21 段
  样本,不是通用基准。
- **句末不加标点。** 默认的 smart 清理会故意去掉一句话末尾的句号或问号:模型给出的那个
  标点只是在猜你的意图,猜错比不给更糟。句子内部的标点会保留。
- **未签名,且只支持 Apple 芯片。** 发布包还没签名和公证,第一次打开要走「仍要打开」。
  只支持 Apple 芯片上的 macOS 13+,没有 Intel 版本。
- **只有一个模型,VAD 也关着。** Friday 只带 Medium —— Large v3 和 Turbo 都已退役,
  老用户会被自动迁移过去。逐段的语音活动检测已经实现,但在准确性验证完之前保持关闭。
- **文本清理很有主见。** Friday 会在**所有**清理模式下改写听起来像 AI 工具名的词
  (cloud → Claude、codec → Codex 等等),目前没有开关 —— 也就是说,一些普通英文单词
  也会被替换掉。它还会把韩文和日文假名的连续片段当作幻觉产物删掉,所以 Friday 目前
  不适合用来听写这两种语言。可自定义词表已经在计划里。

提 issue 之前建议先看一遍[完整清单](docs/LIMITATIONS.md):其中好几条是有意为之的。

## 隐私

Friday 从设计上就是本地优先。你的录音在自己的机器上转写,不会被上传、不会被远程记录、
不会送给任何第三方。模型文件在第一次需要时直接从来源处下载。

## 开发

从源码构建还需要在 `PATH` 上有 whisper.cpp 的 `whisper-server`
(比如 `/opt/homebrew/bin/whisper-server`)。用这个脚本装:

```bash
bash scripts/setup-whisper.sh   # 如果有 Homebrew,会走 brew install whisper-cpp
```

然后:

```bash
swift build          # 构建
swift test           # 跑测试
swift run FridayMac  # 运行
```

从源码第一次启动,同样要授予那三项权限、装好模型,步骤见[安装(下载版)](#安装下载版)。

如果菜单栏的状态看起来不对劲,干净重启一次:

```bash
pkill -f FridayMac || true
swift build
.build/debug/FridayMac &
```

### 从源码装成应用

一步完成构建、安装、启动 `Friday.app`:

```bash
bash scripts/install-local-app.sh
```

- 装到 `/Applications/Friday.app`(必要时退回 `~/Applications`)
- 在 Finder 里双击即可启动
- 幂等 —— 会干净地替换掉上一次的安装

只构建包、不安装:

```bash
bash scripts/build-local-app.sh
# 产物:dist/Friday.app
```

### 分发签名版本

要在别人的 Mac 上安装而不出现「无法验证开发者」的警告,需要 Developer ID 签名加上
Apple 公证。

凭据存一次就好(保存在你的钥匙串里):

```bash
FRIDAY_APPLE_ID="you@example.com" \
FRIDAY_TEAM_ID="ABCD123456" \
FRIDAY_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
bash scripts/store-notary-credentials.sh
```

构建签名并公证过的 DMG:

```bash
FRIDAY_SIGN_IDENTITY="Developer ID Application: Your Name (ABCD123456)" \
FRIDAY_NOTARY_PROFILE="FridayNotary" \
bash scripts/release-signed-notarized-dmg.sh
# 产物:dist/Friday.dmg
```

拿到的人第一次运行时仍然要授予麦克风、辅助功能、输入监控权限 —— 这是 macOS 的安全
要求,躲不掉。

参与方式见 [CONTRIBUTING.md](CONTRIBUTING.md)(语言:英文)。

## 缘起

Friday 最早是一个私人的 macOS 原型,起因很普通:我想口述笔记、prompt 和跟代码沾边的
文字,又不想把自己的声音交给云服务,也不想为此离开手上正在用的那个应用。我一整天说话
都是中英文混在同一句里,而本地能用的工具没有一个把这件事处理好。

公开仓库还很年轻,但这个项目不是一天做出来的演示。开源之前,Friday 经历了几个月的
日常使用迭代:菜单栏应用外壳、按住说话的录音、粘贴后还原剪贴板、权限引导、安全输入
检查、本地模型管理、中英混合文本清理、VAD 实验,以及从只能开发时用的 whisper 配置
搬到自带 `whisper-server` 的发布包。

这段经历也是 README 为什么把限制写得这么具体的原因。Friday 已经好用到能真正派上用场,
但它仍然是早期的公开软件:未签名的预览版、中英混说的边角情况、以及一些键盘兼容性的
工作,都还在。

它开源,是因为一个本地优先的语音输入工具,本来就应该让人能看、能改、能信。欢迎提
issue 和 pull request,尤其欢迎在真实的 Mac 上、真实的听写场景里试过之后的反馈。

## 相关项目

同一作者的其他开源工具:

- [critical-second-pass](https://github.com/FlyingFSR/critical-second-pass) ——
  一个 Codex skill,用来对计划、diff 或草稿做一次诚实、更狠的复读。
- [conversation-archive](https://github.com/FlyingFSR/conversation-archive) ——
  一个给 AI 助手用的 skill,把对话变成有结构的归档,留住的不只是文字,还有质感。

## 许可

[MIT](LICENSE) © Friday Mac contributors
