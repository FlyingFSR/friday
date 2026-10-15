# Qwen3-ASR Swift 搬迁:审查记录与对答案结果(2026-10-12)

> Internal review notes for the code in `Sources/Qwen3ASR`, Chinese only.
>
> **Abstract (English).** The Qwen3-ASR inference code in soniqo/speech-swift was
> extracted, trimmed and reviewed line by line, then compared with the Python
> reference implementation (mlx-qwen3-asr) and with the source of Alibaba's
> official `qwen-asr` package. The ported files only read the model directory: no
> network, no file writes, no child processes. Twelve problems were fixed during
> the port, among them a mel spectrogram that did not match the official one, an
> extra no-repeat rule on audio longer than 15 seconds, a missing end-of-text
> token, silent zero-filled weights when a tensor was missing, and model size
> guessed from the file name instead of read from the config. After the fixes the
> Swift port matched the Python reference on 40 of 41 recordings and 99 of 100
> two-sentence recordings; the remaining differences are exact ties in the model's
> own scores. Friday uses Alibaba's official chunking and decoding workflow. The
> 8-bit weights were reproduced from Alibaba's checkpoint and are identical,
> tensor for tensor, to the published file Friday downloads.

目标是把 soniqo/speech-swift 里 Qwen3-ASR 的识别代码搬出来、精简、逐行审,在 Friday 外面跑通,并和 Python 参照版(mlx-qwen3-asr)对答案。这一步没有改 Friday 本体;审完的代码后来成为 `Sources/Qwen3ASR`。

## 结论

1. **Swift 版跑通了,结果与 Python 参照版基本一字不差。** 同一份模型文件、同样"指定中文 + 热词":41 段老录音 40 段完全相同;50 段中英两句式带热词 50/50、不带热词 49/50 完全相同。剩下 2 处差异(一个逗号/句号、一个逗号)都查到了原因:参照版自己在那一步算出的两个候选得分完全相同(半精度下打平),两套实现的计算顺序略有不同,所以选了不同的一个。这不是错误。
2. **对 Whisper 打分与参照版完全相同**:中文错字率 1.3%(Whisper 2.0%),英文错词率 1.3%(Whisper 2.2%),名字写对 68/72,错的也是同样 4 处。中位耗时 0.57 秒(参照版 0.60 秒,Whisper 1.58 秒)。
3. **speech-swift 原样照搬不行,但修得好,不需要推倒重写。** 代码读得懂,没有联网、写文件、启动进程之类的问题;有几处会让结果和官方对不上的数值和流程问题,已在搬迁时修掉(见下)。
4. **自己用阿里官方原版压的 8-bit 文件,与 moona3k 发布的 8-bit 文件逐个数值完全相同**(1395 个数据块全同,配置和词表也同)。所以之前 `qwen3-asr-eval-2026-10.md` 里 8-bit 的成绩可以直接沿用,不需要重跑。

## 审查发现

**安全面。** 搬过来的文件只读模型目录(权重、词表、配置),不联网、不写文件、不启动其他进程。原项目会联网的 Hugging Face 下载器、修改进程 GPU 内存上限的 `pinMemory`、全局缓存上限协调器都没有搬。

**会让结果对不上官方的问题(都已修):**

1. **频谱图算法不对。** 声音要先换算成"梅尔频谱图"(一张随时间变化的音高能量图)再送进模型。官方用 400 点的变换,原代码为了用苹果加速库把它补零成 512 点,并据此重算滤波器——相当于换了一副耳朵。实测与官方特征平均每个数值偏 0.04、最大偏约 1.0(整张图数值范围约 2)。改成严格按官方步骤用 MLX 计算后,与参照版最大只差 0.00000024。
2. **长录音 15 秒以上自动加"不许重复"约束。** 原代码对超过 15 秒的音频自动禁止任何 3 个字词片段重复出现,阿里原版和参照版都没有这个规则,中文里正常的重复也会被拦。已去掉。
3. **结束条件不完整。** 原代码只认一种结束符;阿里原版认两种。已对齐。
4. **长录音的切段、输出上限:原代码其实更接近阿里原版。** 原代码最多吃 20 分钟、超出部分直接截掉;阿里原版是超过 20 分钟才切段,不截;参照版超过 30 秒就切。搬迁时我先照参照版做了,后来对照阿里原版代码发现这是参照版自己的做法,于是加了一个开关,两种流程都能跑(见下文"对照阿里原版代码")。
5. **不指定语言时提示词与官方模板不同**(总是多塞一个 `<asr_text>` 标记);语言要写英文全称 "Chinese"。Friday 一定会指定中文,影响不大,已对齐官方模板。
6. **精度细节。** 位置编码表以 32 位精度加到 16 位的计算上,会把后面整个音频编码器悄悄升级成 32 位(慢,且与官方不同);官方每层之后的 16 位溢出保护也缺失。已修。
7. **分词(把文字切成模型认识的编号)是简化写法。** 预想会让热词编号不同,实测影响很小:热词串和 15 种中英数字标点混合句都与官方一致,只有"连续空行"不同。仍按官方规则补齐,8 组测试逐个一致。

**可靠性问题(都已修):**

8. **加载模型时缺了权重或形状不对不报错**,缺的部分保持全零,结果是乱码而不是报错。现在缺一个、形状错一个、文件里多一个没用上的,都会直接报错。
9. **模型大小和压缩位数靠模型名字里的 "1.7B"、"8bit" 来猜**,不读配置文件。现在读 `config.json` 和 `quantization_config.json`。
10. **不认"音频编码部分也压缩过"的文件格式。** 参照版(以及 moona3k)的文件把音频编码部分也压成了 8-bit,原代码会把整数当小数用。现在压缩与否都能读,官方原版也能直接读。
11. **词表文件缺失时不报错**,输出会变成一串数字编号、语言和热词提示被悄悄忽略。现在缺了直接报错。
12. 重采样失败时会悄悄返回原采样率的数据。没有搬,现在要求输入 16 kHz 单声道(Friday 录音本来就是)。

另外删掉了没用的代码:流式识别、强制对齐、Core ML 版本、批量解码、采样和重复惩罚等。

## 对照阿里原版代码(同日追加)

模型是阿里的,但让模型跑起来的程序,我们手里的两个都出自个人开发者:speech-swift(Swift)和 mlx-qwen3-asr(Python 参照版)。阿里自己也有运行程序 `qwen-asr`,但它是 Python + PyTorch,放不进 Friday,所以才需要别人的 Mac 版。为确认这些"翻译版"没走样,下载了阿里官方 `qwen-asr` 0.0.6 的源代码(PyPI,147 KB,Apache 2.0,作者阿里通义千问团队)逐条对照,没有安装、没有运行。

**模型本体的计算:Swift 版与阿里原版一致。** 频谱图设置(400 点、10 毫秒一帧、128 个频带、单条不补齐)、编码器每 100 帧一块并在块内补零、位置编码每块从 0 开始、每 8 块一个注意力窗口、16 位溢出保护、旋转位置编码、各处归一化参数都一致。参照版有一处与阿里不同:q/k 归一化的小参数用了 1e-5(阿里 1e-6),Swift 版用阿里的值;两边识别结果仍一致,说明影响可忽略。提示词模板、两种结束符、输出后的重复清理也一致。

**外围流程有 4 处是参照版自己的做法,不是阿里的:**

| | 阿里原版 | 参照版 |
| --- | --- | --- |
| 什么时候切段 | 超过 20 分钟才切,切点在目标位置前后 5 秒内最安静处 | 超过 30 秒就切,切点在中间 60% 里最安静的半秒 |
| 输出长度上限 | 固定 512 个字词片段 | 按时长算,128–512 |
| 边生成边查重复 | 没有,只在事后清理文字 | 同一片段重复 20 次就提前停 |
| 不到 0.5 秒的录音 | 补静音到 0.5 秒 | 不补 |

Swift 版加了 `--workflow official` 开关按阿里原版流程跑(切段函数照阿里代码翻译)。41 段录音结果:36 段与参照版流程一字不差,不同的正是 5 段超过 30 秒的长录音,差别基本是标点——参照版在 30 秒切开处会断句,阿里流程整段识别更连贯;long-zh-01 开头那个凭空多出的"嗯。"也没了(`qwen3-asr-eval-2026-10.md` 记过这个问题;整段识别时不再出现,看来与 30 秒切段有关,但只有这一个样本)。5 段都正常结束,没有被 512 上限截断(最长的 long-zh-01 是 62 秒,输出 231 个字、157 个字词片段)。

| 流程 | 中文错字率 | 英文错词率 | 名字写对 | 中位耗时 |
| --- | --- | --- | --- | --- |
| Whisper(现役) | 2.0% | 2.2% | 72/72 | 1.58 秒 |
| Swift,参照版流程 | 1.3% | 1.3% | 68/72 | 0.57 秒 |
| Swift,阿里原版流程 | 1.2% | 1.3% | 68/72 | 0.60 秒 |

**建议接进 Friday 时用阿里原版流程。** 唯一要留意的是 512 上限:按 long-zh-01 的速度(每秒约 2.5 个片段),大约 3 分多钟的单段中文口述就会触顶被截断,接入时应按时长放宽上限(阿里另一套 vLLM 后端默认是 4096)。0.5.0 已这样做:上限为每秒音频 8 个片段,最少 512。没有"边生成边查重复"的代价是:模型万一卡在重复里,会一直生成到上限(慢几秒),最终文字仍会被清理。

## 模型文件

用参照版自带的压缩函数(`load_model` + `quantize_model`,8-bit、每 64 个数一组)把阿里官方 `Qwen/Qwen3-ASR-1.7B`(版本 7278e1e)压成 8-bit,格式与 mlx-qwen3-asr 相同。与 moona3k 的 8-bit 文件逐个比对:1395 个数据块全部相同。Swift 版和 Python 参照版读的是同一份文件。

## 编译环境:一个事先没预料到的问题

这台 Mac 只有苹果命令行开发工具,没有完整 Xcode,也就没有编译 GPU 程序的 `metal` 工具。mlx-swift 需要把一批 GPU 计算程序编成"着色器库"。绕法:从 MLX 官方 Python 安装包 `mlx-metal 0.32.2` 里取出已编好的 `mlx.metallib`,放在程序旁边;版本必须与 mlx-swift 锁定的核心版本一致(0.32.2,不能用现有 Python 环境里的 0.32.3)。为此改了 mlx-swift 的 `Package.swift`:不编译着色器源码,swift-numerics 改用本地副本(这样编译时不联网)。用这种方式,矩阵乘法、频谱变换、8-bit 矩阵乘法、注意力的小测试结果都正确,整套识别也与参照版一致。

**这直接影响下一步接进 Friday:** Friday 现在用同一套命令行工具编译。接入时要么在打包流程里放一份版本对上的 `mlx.metallib`(要处理来源、升级时版本同步),要么改为用 Xcode 编译。另外 mlx-swift 0.32.3 要求 macOS 14 起步,Friday 目前写的是 macOS 13,至少要升到 14。(0.5.0 采用了前一种做法:`scripts/fetch-mlx-metallib.sh` 按校验值取这份着色器库,打包时放进应用;最低系统升到 macOS 14。)

## 资源占用

一次跑完 41 段:进程峰值内存约 3.6 GB(常驻约 2.3 GB);参照版 Python 约 3.0 GB。建模型对象约 0.3 秒,但权重是第一次识别时才真正从磁盘读入,所以第一次识别会慢一些(测试里先空跑一段预热,与参照版做法相同);接入 Friday 时应在启动后后台预热。
