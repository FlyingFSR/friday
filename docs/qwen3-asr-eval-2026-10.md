# Qwen3-ASR 1.7B(4-bit)实测:对比 Friday 现役 Whisper(2026-10-12)

> Internal evaluation notes for the 0.5.0 engine change, Chinese only.
>
> **Abstract (English).** Before porting anything, Qwen3-ASR 1.7B was run in
> Python/MLX on 41 of the maintainer's recordings and scored against Friday 0.4's
> Whisper Medium, with the same text cleanup applied to both. Letting the model
> detect the language made it translate Chinese inside mixed speech into English;
> forcing Chinese stopped that while keeping English sentences in English. With
> Chinese forced plus a hot-word list, the 8-bit model scored 1.3% Chinese
> character errors and 1.3% English word errors against Whisper's 2.0% and 2.2%,
> about 2.6x faster, and kept both sentences in all 50 short
> "one sentence Chinese, one sentence English" recordings. The hot-word list can
> pull a similar-sounding word toward a hot word (Cursor -> Claude once). One
> speaker, one quiet room.

这是换引擎的第一步:在 Friday 外面只测模型本身,不改 Friday。

## 怎么测的

- 模型:`moona3k/mlx-qwen3-asr-1.7b-4bit`(1.31 GB,工具作者用阿里官方权重压缩),用 `mlx-qwen3-asr` 0.4.4 在 Python 3.12 / MLX 下跑,M3 MacBook Air 16 GB。
- 录音:21 段旧评测样本 + 2026-10-12 维护者录的 20 段 AI 名字样本,共 41 段。
- Qwen 的输出也过一遍 Friday 现役的文字清理(PostProcessService,smart 模式),与 Whisper 同一把尺子。
- 对照:Friday 现役 Whisper Medium + 现役提示词(0.4 后期加入 AI 名字的版本)。
- 热词:Qwen 的 `context` 参数,内容与 Whisper 提示词的词表部分相同(不含例句)。
- 中文错字率排除 long-num-01(Whisper 写阿拉伯数字、参考稿写汉字数字,不可比)。

## 结果

| 配置 | 中文错字率 | 英文错词率 | 名字写对(72 处) | 内容丢失 / 被翻译 | 中位耗时 |
| --- | --- | --- | --- | --- | --- |
| Whisper(现役) | 2.0% | 2.2% | 72 | 无 | 1.58 秒 |
| Qwen,自动判断语言 | 3.7% | 9.7% | 60 | long-en-01 一句中文被翻成英文 | 0.42 秒 |
| Qwen,自动 + 热词 | 5.7% | 13.7% | 67 | 再加 brand-03 整句中文被翻成英文 | 0.46 秒 |
| Qwen,指定中文 | 1.6% | 1.8% | 60 | 无 | 0.38 秒 |
| **Qwen,指定中文 + 热词** | **1.5%** | **1.8%** | 65 | 无 | 0.43 秒 |

分组看(指定中文 + 热词 对 Whisper):纯中文 1.1% 对 2.0%;纯英文 2.6% 对 5.3%;英文为主的长混说也不再翻译。

## 结论

1. **语言必须指定为中文。** 让 Qwen 自己判断语言时,它会把中英混说里的中文翻成英文,加热词后更严重——这正是 Friday 的硬门槛。指定"中文"后翻译消失,英文句子照样输出英文。
2. **指定中文 + 热词这一档,中英文准确度都略好于现役 Whisper,速度约快 3.7 倍,无丢句。**
3. **名字 65 对 72 不是公平比较:** Whisper 那边的提示词和清理规则正是用这批录音调出来的,Qwen 没做任何针对性调整。Qwen 剩下的错多数是清理层能补的形态(通一千万、G L M、GPT五、差GPT、Carla→Cursor)。
4. **热词有副作用:** ds-2 里把 Kimi 换成了热词里的 Qwen——热词会把读音相近的真词"吸"成热词。
5. 内存:跑长音频时峰值约 2.2 GB(含 Python 本身);现役 whisper-server 常驻约 1 GB。

## 追加:1.7B 8-bit(同日)

模型 `moona3k/mlx-qwen3-asr-1.7b-8bit`(2.17 GB,限速下载后逐文件核对过 SHA-256),测法完全相同。

| 配置 | 中文错字率 | 英文错词率 | 名字写对(72 处) | 内容丢失 / 被翻译 | 中位耗时 |
| --- | --- | --- | --- | --- | --- |
| Whisper(现役) | 2.0% | 2.2% | 72 | 无 | 1.58 秒 |
| 8-bit,自动判断语言 | 3.6% | 6.2% | 62 | long-en-01 仍被翻译 | 0.62 秒 |
| 8-bit,自动 + 热词 | 3.3% | 5.7% | 68 | long-en-01 仍被翻译 | 0.67 秒 |
| 8-bit,指定中文 | 1.3% | 1.3% | 62 | 无 | 0.56 秒 |
| **8-bit,指定中文 + 热词** | **1.3%** | **1.3%** | **68** | 无 | 0.60 秒 |

分组(8-bit 指定中文 + 热词 对 Whisper):纯中文 1.3% 对 2.0%;纯英文 2.6% 对 5.3%;短混说中英都 0 错,与 Whisper 打平(4-bit 在这组有错);长混说中文 2.1% 对 3.1%、英文持平。

- 4-bit 的两个问题在 8-bit 消失:brand-03 的 ChatGPT 写对了;热词把 Kimi 吸成 Qwen 的情况没再出现。
- 热词"吸词"仍在:other-07 的 Cursor 被写成热词里的 Claude。剩下的错是"通一千万"两次、"GPT五"一次,都是清理层能补的形态。
- 自动判断语言照样会翻译,"必须指定中文"的结论不变。
- 内存峰值约 3.0 GB(4-bit 约 2.2 GB),速度仍约为 Whisper 的 2.6 倍。

结论:8-bit 指定中文 + 热词在每一组上都不差于现役 Whisper,是进入下一步的候选。

## 追加:一句中文接一句英文(同日)

从旧样本拼出 50 段两句式短录音(中→英、英→中各 25),8-bit 指定中文跑,带热词与不带各一遍,对照 Friday 现役(含 10 月的漏句补救)。

- 三者都是 50/50 两句都在,没有一段被翻译成另一种语言:中文句写成中文,英文句写成英文。
- "指定中文"的含义是告诉模型这段录音以中文为主,不是把所有内容都转成中文。

## 局限与下一步要回答的问题

- 只有维护者一个人、安静环境、41 段。
- 指定中文对"整段纯英文长口述"只测了 5 段英文为主的样本,都没问题,但样本少。
- 长中文开头偶发一个凭空多出的字("I." / "嗯。"),需要清理层处理。
- 这是 Python + MLX 跑的;接进 Friday 要走 Swift。此前调研时"FluidAudio 能跑 Qwen3-ASR"一说已过时(其 0.15.x 移除了 Qwen3 支持),可选路线是 soniqo 的 Qwen3ASR Swift 模块或现成的 Core ML 版本,速度和准确度需要在那条路线上重测。
