# Local models for a lean macOS browser

_Researched 2026-10-10 for a Swift + WKWebView browser on macOS 26.3 (Apple silicon). Every factual claim has a source URL. Where sources are secondary, vendor-reported or contradictory, that is flagged._

## TL;DR

- **"RLCD" + "jev" almost certainly means TypeSafe AI's Jev**, a "System One" decision model launched 2026-09-15 and trained with **RLCD = Reinforcement Learning for Calibrated Decisions**. Both terms show up together in TypeSafe's launch post ([typesafe.ai](https://typesafe.ai/blog/introducing-system-one-models-and-jev)). Jev is hosted-API-only in early access. No open weights or local build is documented.
- **Local stand-ins for Jev:** Apple's on-device Foundation Models with `@Generable` enums (constrained decoding, built in, no download), a small MLX LLM with constrained output, or a Create ML / `NLModel` classifier for fixed decisions. None of them returns Jev-style calibrated probabilities out of the box. That part has to be built.
- **Open-weight Jev clones do exist (see section 5).** All six names from the AI-search list are real projects: Laya, Kev, Von, SemIf and Nimble check out, and NanoJev exists but is a game-decision research replica rather than an edge model. Laya, Kev and Von serve TypeSafe's `POST /v1/systemone` wire format, so Jev clients work against them unchanged. All are Python-first and none ships Core ML. The best fit for a Swift app is **Laya** (Apache 2.0, a 322M-421M ModernBERT/mmBERT encoder) through its ONNX export. **Kev-0.8B** on MLX, run as a local sidecar, is the runner-up.
- **The built-in floor is strong on macOS 26:** Foundation Models (about 3B parameters, 2-bit, 4096-token context, guided generation and tool calling), SpeechAnalyzer (STT, benchmarked faster than Whisper), AVSpeechSynthesizer (TTS), Translation (on-device), Vision (OCR / documents), NaturalLanguage (tagging, embeddings) and NSDataDetector. None of these ship model weights in your app.
- **Biggest built-in limitation:** the 4096-token Foundation Models window covers input and output together ([Apple TN3193](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)). "Summarize page" needs chunking or a map-reduce pass. Foundation Models also requires Apple Intelligence to be enabled.
- **Best downloads if built-ins fall short:** Qwen3.5 0.8B/2B/4B or Gemma 4 E2B (Apache 2.0) as the LLM, Parakeet TDT 0.6B v3 or Whisper large-v3-turbo for STT, Kokoro-82M for TTS (Apache 2.0), and EmbeddingGemma 300M or Qwen3-Embedding-0.6B for semantic history.
- **Image generation is the weakest local category.** ImageCreator (the programmatic Image Playground API) is reportedly being discontinued in the macOS 27 cycle (secondary source, unverified). SD-Turbo Core ML is about 2.5 GB at fp16. Skip image gen for a lean browser.
- **Recommendation:** ship built-ins only, behind `availability` checks. Add downloadable models later as opt-in, user-initiated downloads.

---

## 1. Disambiguating "RLCD" and "jev"

The original request (voice-dictated): _"models trained with RLCD (research jev and its local alternatives)"_.

### Most plausible reading (high confidence): TypeSafe AI's Jev, trained with RLCD

- TypeSafe AI's launch post introduces "System One Models" and **Jev**, its first public one. The post expands **RLCD as "Reinforcement Learning for Calibrated Decisions"** ([typesafe.ai launch post](https://typesafe.ai/blog/introducing-system-one-models-and-jev)). The phrase "models trained with RLCD … jev" matches this exactly, and that is the main evidence.
- Launched 2026-09-15, after about two years in stealth. CEO Diogo Almeida says he co-invented RLHF/InstructGPT at OpenAI. TypeSafe positions RLCD as a replacement for RLHF ([DataNorth summary](https://datanorth.ai/blog/jev-what-it-is-and-why-this-new-model-matters), [GIGAZINE](https://www.gigazine.net/news/20260916-system-one-jev/)).
- **What it does:** it takes a "state" (string, JSON or array of text) plus typed questions and returns typed decisions, never prose. There are three question types: **Choice** (pick from up to 255 options), **Score** (ordered rubric), and **Noul** (truth value 0-1). Each answer comes back with probabilities and, for Choice and Score, a confidence ([TypeSafe docs](https://docs.typesafe.ai/introduction), [launch post](https://typesafe.ai/blog/introducing-system-one-models-and-jev)).
- **Vendor claims:**
  - 70-500 ms end to end, measured from West Coast laptops.
  - Up to 193.6x faster and 444.6x cheaper than frontier LLMs, on TypeSafe's own workflow evals.
  - $0.042 per million input tokens; output is free.
  - 64k context, which is from the secondary summary only.

  Sources: [launch post](https://typesafe.ai/blog/introducing-system-one-models-and-jev), [DataNorth](https://datanorth.ai/blog/jev-what-it-is-and-why-this-new-model-matters). TypeSafe publishes no public benchmark scores ([DataNorth](https://datanorth.ai/blog/jev-what-it-is-and-why-this-new-model-matters)).
- **Local / small versions:** none found. The launch post does not mention weights, parameter count, or on-device / edge deployment. Access is waitlist and early-access API ([launch post](https://typesafe.ai/blog/introducing-system-one-models-and-jev)). Official SDKs are Python and JS/TS; no Swift SDK was found ([aiskill.market write-up](https://aiskill.market/blog/typesafe-official-sdks-js-and-python), [OpenRouter guide](https://openrouter.ai/docs/guides/community/typesafe-sdk)). The launch post also links a `system-one-adapter-python` wrapper that constrains *LLMs* to emit structured decisions ([launch post](https://typesafe.ai/blog/introducing-system-one-models-and-jev)). I could not locate that repo independently, so its scope is unverified.
- **Relevance to the browser:** this kind of model fits palette command routing (pick 1 of N actions), "is this page a login / article / shop?" classification, and guardrails. Calling a cloud API conflicts with "use what macOS ships".

**Local alternatives to Jev-style typed decisions:**

| Approach | How | Gap vs Jev |
|---|---|---|
| Apple Foundation Models + `@Generable` enum | Constrained decoding guarantees the output is one of your enum cases ([Apple ML research](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)) | No calibrated probability. I found no documented log-prob / confidence API (unverified, check the docs) |
| Small MLX LLM (Qwen3.5 0.8B/2B) with constrained choice | Score each option's likelihood and normalize to get a probability distribution | You build and calibrate it yourself. A download is required |
| Create ML text classifier to `NLModel` | Train on your own labeled examples; ships as a tiny model ([NLModel docs](https://developer.apple.com/documentation/naturallanguage/nlmodel)) | Fixed label set and needs training data. `NLModel.predictedLabelHypotheses` gives per-label scores ([docs](https://developer.apple.com/documentation/naturallanguage/nlmodel/predictedlabelhypotheses(for:maximumcount:))) |
| Embedding nearest-neighbour | Embed each command description, then cosine-match the user's query (NLEmbedding or EmbeddingGemma) | Similarity is not calibrated probability, but it is cheap and fast |

### Alternative reading A: "RLCD" = Yang et al. 2023 (low relevance)

- **RLCD: Reinforcement Learning from Contrast Distillation** (Yang, Klein, Celikyilmaz, Peng, Tian), arXiv 2307.12950. It generates preference pairs from a positive and a negative prompt, trains a preference model, then runs RL, all without human labels. It beat RLAIF and context distillation at 7B/30B ([arXiv](https://arxiv.org/abs/2307.12950v2)). Note the official title says "Contrast", not "Contrastive".
- This is a training *method*, not a model family. I know of no "RLCD-trained" small model line. It matters only for fine-tuning, and it is irrelevant to shipping a browser.

### Alternative reading B: "jev" = JEPA (Meta / LeCun), plausible-sounding but weak fit

- "Jev" could be a mis-hearing of "JEPA". Relevant members of the JEPA family:
  - **V-JEPA 2:** video world model with ViT-L 300M to ViT-g 1B encoders; open checkpoints on Hugging Face ([arXiv 2506.09985](https://arxiv.org/pdf/2506.09985), [HF Transformers docs](https://huggingface.co/docs/transformers/model_doc/vjepa2)).
  - **VL-JEPA:** vision-language, about 1.6B parameters; predicts text embeddings instead of tokens ([ICLR 2026](https://iclr.cc/virtual/2026/poster/10006956)).
  - **LLM-JEPA:** a training objective added to LLM fine-tuning ([arXiv 2509.14252](https://arxiv.org/html/2509.14252v2)).
- JEPA is not trained "with RLCD", and none of these is a browser-ready assistant. The ViT-L variants are small enough for a Mac, but I found no MLX / Core ML ports to cite.
- A third sound-alike, **GEPA** (reflective prompt evolution, ICLR 2026), is a prompt optimizer, not a model ([arXiv 2507.19457](https://arxiv.org/pdf/2507.19457)).

**Verdict:** TypeSafe Jev + RLCD (Calibrated Decisions) is the clear best guess, because the two terms co-occur in one primary source dated a month ago. Confirm with the requester if something else was meant.

---

## 2. Built into macOS 26 (no download by the app)

> Note: WWDC26 announced macOS 27 changes, including a second, larger on-device model needing 12 GB RAM, image input in Foundation Models, and a new "Core AI" framework ([Apple WWDC26 macOS guide](https://developer.apple.com/wwdc26/guides/macos/), [Callstack](https://callstack.com/blog/on-device-ai-after-wwdc-2026-whats-new), [Implicator](https://www.implicator.ai/apple-expands-xcode-and-foundation-models-for-wwdc-ai-developers/)). Everything below targets macOS 26.

### Foundation Models framework (on-device LLM)

- **Model:**
  - About 3B parameters; decoder weights 2-bit (QAT), embeddings 4-bit, KV cache 8-bit; 15 languages ([Apple ML research](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)).
  - About 3 GB on disk, downloaded automatically with Apple Intelligence. This figure is from a third-party guide only ([Atelier Socle](https://www.atelier-socle.com/en/articles/foundation-models-api-guide)).
  - Lives in the system, so it adds nothing to the app bundle.
- **Context:** 4096 tokens per session, shared by instructions, prompt, tool definitions/output and the response ([TN3193](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window), [Apple docs](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)). 26.4 adds `contextSize` and `tokenCount(for:)` ([InfoQ](https://infoq.com/news/2026/03/apple-foundation-models-context)).
- **Capabilities:**
  - **Guided generation** via `@Generable` / `@Guide` on Swift structs and enums, with constrained decoding ([Apple ML research](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)).
  - **Tool calling** via the `Tool` protocol, with parallel and serial calls (same source).
  - Streaming of partial typed results ([WWDC25 notes](https://wwdcnotes.com/documentation/wwdc25-286-meet-the-foundation-models-framework/)).
  - LoRA adapters (rank 32) trainable with Apple's Python toolkit; they must be retrained for each base-model version ([Apple ML research](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)).
- **API shape:** `SystemLanguageModel.default.availability`, then `LanguageModelSession(instructions:)`, then `respond(to:generating:)` / `streamResponse(to:)` ([Apple docs](https://developer.apple.com/documentation/foundationmodels), [WWDC25 session 286 notes](https://wwdcnotes.com/documentation/wwdc25-286-meet-the-foundation-models-framework/)).
- **Requirements:** Apple-Intelligence-capable Mac (M1 or later) with Apple Intelligence enabled and the model downloaded. `availability` reports why it is unavailable ([Atelier Socle](https://www.atelier-socle.com/en/articles/foundation-models-api-guide)). This is a third-party list; confirm against Apple docs.
- **Browser uses:**
  - Summarize page (chunked).
  - Natural-language palette commands, with tools such as `openTab`, `searchHistory`, `setZoom`.
  - Tag pages for history.
  - Rewrite selected text.
- **Latency:** Apple publishes no throughput numbers ([Apple ML research](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)). Measure it yourself.

### SpeechAnalyzer / SpeechTranscriber (STT)

- New in macOS 26. Locale models install into system storage through `AssetInventory.assetInstallationRequest(supporting:)`; check `SpeechTranscriber.supportedLocales` / `installedLocales` first ([WWDC25 session 277](https://developer.apple.com/fr/videos/play/wwdc2025/277/), [Apple forums](https://developer.apple.com/forums/thread/790108)).
- `DictationTranscriber` reuses the system dictation models and supports older devices ([Apple docs](https://developer.apple.com/documentation/speech/dictationtranscriber)).
- **Speed:** MacStories transcribed a 34-minute video in 45 s, versus 1:41 for MacWhisper Large-v3 Turbo ([MacStories](https://www.macstories.net/stories/hands-on-how-apples-new-speech-apis-outpace-whisper-for-lightning-fast-transcription/)). A LibriSpeech test reported 2.12% WER on clean audio, but that comes via secondary coverage ([GIGAZINE](https://www.gigazine.net/gsc_news/en/20250619-apple-speech-analyzer)).
- **Browser uses:** dictate into web form fields (insert via JS into the focused element), and voice commands for the palette.

### AVSpeechSynthesizer / Personal Voice (TTS)

- System voices, including downloaded premium voices, can be used with no app payload ([AVSpeechSynthesizer docs](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizer)).
- Personal Voice needs `requestPersonalVoiceAuthorization`, and Apple says it should be used primarily for AAC apps ([WWDC23 notes](https://wwdcnotes.com/notes/wwdc23/10033), [Ben Dodson](https://bendodson.com/weblog/2024/04/03/using-your-personal-voice-in-an-ios-app/)).
- **Browser use:** read the page aloud, using Readability-style extraction followed by `AVSpeechUtterance`. Latency is effectively immediate in practice, but I found no published number.

### Image Playground / ImageCreator (image generation)

- The `ImagePlayground` framework generates images in system styles from text and/or an image; `ImagePlaygroundStyle` has been available since macOS 15.4 ([Apple docs](https://developer.apple.com/documentation/imageplayground), [ImagePlaygroundStyle](https://developer.apple.com/documentation/imageplayground/imageplaygroundstyle)).
- Programmatic path: `ImageCreator().images(for:style:limit:)` ([Blake Crosley](https://blakecrosley.com/blog/image-playground-api-integration)). The same blog says ImageCreator stops working in the macOS 27 cycle and only the sheet UI remains. This is **unverified** against Apple docs.
- **Browser use:** little. A cartoon-style generator has no core browser job, so skip it.

### Vision

- On-device OCR (`RecognizeTextRequest`). New in 26: `RecognizeDocumentsRequest`, which returns structured paragraphs, tables, lists and QR codes in 26 languages ([WWDC25 session 272 notes](https://wwdcnotes.com/documentation/wwdc25-272-read-documents-using-the-vision-framework/)).
- Image classification and feature prints ([Vision docs](https://developer.apple.com/documentation/vision)).
- **Browser uses:**
  - Rough alt-text from classification labels plus OCR text.
  - Text from screenshots or images.
  - Finding QR codes in images.

  Real caption-quality alt-text on 26 needs an LLM with image input. Foundation Models image input is a macOS 27 feature ([WWDC26 guide](https://developer.apple.com/wwdc26/guides/macos/)). On 26.3 that means a download, or Vision labels plus OCR fed to the text model.

### NaturalLanguage

- `NLTagger`: language identification, tokenization, lemmas, part-of-speech and named entities ([NLTagger docs](https://developer.apple.com/documentation/naturallanguage/nltagger)).
- `NLEmbedding`: word and sentence embeddings (`sentenceEmbedding(for:)`); Apple recommends it for similarity ([NLEmbedding docs](https://developer.apple.com/documentation/naturallanguage/nlembedding)).
- `NLContextualEmbedding` (BERT-based, macOS 14+, per-token vectors that you pool yourself) is aimed at classification and tagging ([docs](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding)). Dimensions are reported as 512, possibly 768 on macOS ([Callstack](https://callstack.com/blog/on-device-ai-introducing-apple-embeddings-in-react-native), [NaturalLanguageEmbeddings pkg](https://swiftpackageregistry.com/buh/NaturalLanguageEmbeddings)). Both figures are third-party and unverified.
- **Browser uses:** semantic history search with zero download (quality is modest), auto-detecting page language for translate, and extracting entities for the palette.

### Translation framework (bonus; not in the brief but directly relevant)

- `TranslationSession` processes all translation on device. Missing languages are downloaded with user consent through SwiftUI `.translationTask`. macOS 26.4 adds a `highFidelity` strategy that uses Apple Intelligence models ([TranslationSession docs](https://developer.apple.com/documentation/translation/translationsession), [init docs](https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:preferredstrategy:))).
- **Browser use:** translate the page by extracting text nodes, batch-translating them, and writing them back.

### NSDataDetector

- Detects dates, addresses, links, phone numbers and transit info in strings using classic rules and heuristics, not an ML model ([NSDataDetector docs](https://developer.apple.com/documentation/foundation/nsdatadetector)). It is effectively zero cost.
- **Browser uses:** "add to calendar" or "open in Maps" actions for selected text, and palette parsing ("remind me tomorrow 3pm").

---

## 3. Downloadable models (MLX / Core ML)

Sizes are approximate. Speed figures are mostly community or vendor estimates; benchmark on your own Mac.

### LLMs (≤4B)

| Model | Size / disk | Speed on Apple silicon | License |
|---|---|---|---|
| Qwen3.5 0.8B / 2B / 4B (Mar 2026; native vision, 262K ctx) | 4B ≈ 5-6 GB VRAM at 4-bit ([Ertas](https://www.ertas.ai/best/best-small-llm-for-local-deployment)) | 4B ≈ 25-35 tok/s, an estimate ([InsiderLLM](https://insiderllm.com/guides/best-local-llms-mac-2026/)) | Apache 2.0 ([Artificial Analysis](https://artificialanalysis.ai/articles/qwen3-5-small-models)) |
| Gemma 4 E2B / E4B (Apr 2026; text, image and audio input) | E2B ≈ 1.5 GB at Q4_K_M ([Ertas](https://www.ertas.ai/best/best-small-llm-for-local-deployment)) | E2B ≈ 30-45 tok/s, an estimate ([InsiderLLM](https://insiderllm.com/guides/best-local-llms-mac-2026/)) | Apache 2.0 ([Let's Data Science](https://letsdatascience.com/news/google-releases-gemma-4-open-models-05c4c02a)) |
| SmolLM3 3B (128K ctx, 6 languages) | not verified | not verified | Apache 2.0 ([dev.co listing](https://dev.co/ai/llms/smollm3-3b)) |
| Llama 3.2 1B / 3B | not verified | not verified | Llama 3.2 Community License: "Built with Llama" attribution and AUP ([HF card](https://huggingface.co/meta-LLaMA/LLaMA-3.2-1B)) |

Runtime note: MLX is reportedly about 2x faster at decode than Ollama's llama.cpp backend ([InsiderLLM](https://insiderllm.com/guides/qwen35-mac-mlx-vs-ollama/)). Gemma 4 E2B with audio and image input could cover alt-text plus dictation in one download, but I have not verified MLX support for its audio path.

### STT

| Model | Size | Speed | License |
|---|---|---|---|
| Whisper large-v3-turbo | 809M params | 12 min transcribed in 14 s on M2 Ultra via mlx-whisper ([Simon Willison](https://simonwillison.net/2024/Oct/1/whisper-large-v3-turbo-model/)) | MIT (same source) |
| Parakeet TDT 0.6B v3 | Core ML INT8 ≈ 500 MB ([soniqo](https://soniqo.audio/guides/parakeet)) | about 32x real time on the Neural Engine, vendor claim (same) | CC-BY-4.0 ([HF Core ML card](https://huggingface.co/DictionLabs/parakeet-tdt-0.6b-v3-coreml)) |
| Moonshine Tiny | 27M params; compute scales with audio length ([arXiv 2509.02523](https://arxiv.org/html/2509.02523v1)) | not verified | MIT (per mirrors; [HF](https://huggingface.co/handy-computer/moonshine-streaming-tiny-gguf)) |

Whisper models may already be cached under `~/.cache/huggingface/hub` by other apps. That is useful for experiments, but SpeechTranscriber makes STT downloads mostly unnecessary.

### TTS

| Model | Size | Speed | License |
|---|---|---|---|
| Kokoro-82M | 82M params | 30 s of audio in 379 ms on a Mac Studio with the Core ML port, which claims 2x faster than MLX (author's own benchmark) ([kokoro-coreml](https://huggingface.co/mattmireles/kokoro-coreml)) | Apache 2.0 weights; kokoro-mlx code is MIT ([kokoro-mlx](https://github.com/gabrimatic/kokoro-mlx)) |

### Image generation

| Model | Size | Speed | License |
|---|---|---|---|
| SD-Turbo via apple/ml-stable-diffusion | about 2.5 GB at fp16. A 6-bit, 384 px community build runs about 2.2 s per image on an iPhone 13 mini ([HF](https://huggingface.co/jivenchy/sd-turbo-coreml-384-6bit)) | see size | Conflicting reports (Stability Community License vs non-commercial); **verify on the official card** ([HF ONNX mirror](https://huggingface.co/Heliosoph/sd-turbo-onnx)) |

### Embeddings

| Model | Size | Notes | License |
|---|---|---|---|
| EmbeddingGemma 300M (308M) | under 200 MB RAM quantized ([Google DeepMind](https://deepmind.google/models/gemma/embeddinggemma/)) | 768-d, truncatable to 512/256/128; 2K ctx; 100+ languages ([HF blog](https://huggingface.co/blog/embeddinggemma)) | Gemma Terms of Use, not Apache ([MLX card](https://huggingface.co/AutomatosX/AX-EmbeddingGemma-300M-MLX-8bit)) |
| Qwen3-Embedding-0.6B | about 0.6B params | up to 1024-d (MRL 32-1024), 32K ctx, MMTEB about 64.3 ([Vast.ai](https://vast.ai/model/qwen3-embedding)) | Apache 2.0 ([arXiv 2506.05176](https://arxiv.org/abs/2506.05176v3)) |

---

## 4. Feature map

| Browser feature | Best built-in (macOS 26) | Best downloadable |
|---|---|---|
| Summarize page | Foundation Models; chunk to fit 4096 tokens, map-reduce | Qwen3.5 4B (262K ctx) or Gemma 4 E4B via MLX |
| Natural-language palette commands | Foundation Models `@Generable` enum + `Tool`s; NSDataDetector for dates | Qwen3.5 0.8B/2B with constrained choice; (cloud: Jev) |
| Semantic history search | `NLEmbedding.sentenceEmbedding` + local vector table | EmbeddingGemma 300M or Qwen3-Embedding-0.6B |
| Read page aloud | AVSpeechSynthesizer (premium system voices) | Kokoro-82M |
| Dictate into fields | SpeechAnalyzer / SpeechTranscriber | Parakeet TDT 0.6B v3 or Whisper large-v3-turbo |
| Alt-text for images | Vision labels + OCR, optionally phrased by Foundation Models (image input only arrives in macOS 27) | Gemma 4 E2B or Qwen3.5 2B/4B (native vision) |
| Translate page | Translation framework (`TranslationSession`, on device) | Qwen3.5 / Gemma 4 (multilingual); no dedicated MT model researched |

## Open questions / not verified

- Whether Foundation Models exposes token probabilities or confidence, which is needed for Jev-like calibrated decisions.
- Whether TypeSafe will ship any local or on-device Jev. Nothing is published as of 2026-10-10.
- Official SD-Turbo license, and the ImageCreator deprecation in Apple's own docs.
- Measured MLX tok/s for 1-4B models on a specific Mac.

---

## 5. Local Jev alternatives (verified)

_Checked 2026-10-10 against primary sources: Hugging Face cards, GitHub READMEs and file listings. The list came from an AI search app that cited DataCamp ([DataCamp: top open-source Jev alternatives](https://www.datacamp.com/blog/top-open-source-jev-alternatives)). DataCamp also lists a seventh project, "Rizzo Flow", which was not checked. Every accuracy and latency figure below is self-reported by the project authors. None has been reproduced independently._

**Status key:** VERIFIED means the item exists and the claims hold. PARTLY means it exists, but some claims differ. NOT FOUND means no trace of it.

| Item | Status | Maker | License | Size on disk | Weights | Apple silicon | Jev API match |
|---|---|---|---|---|---|---|---|
| **Laya** | VERIFIED | Convai Innovations (GitHub `NandhaKishorM`) | Apache 2.0 | `laya` 421M ≈ 808 MB; `laya-multilingual` 322M ≈ 647 MB; all three checkpoints ≈ 2.3 GB | Yes, [HF `convaiinnovations/laya`](https://huggingface.co/convaiinnovations/laya) | PyTorch MPS (auto-selected) and **ONNX** (`laya[onnx]`, measured on an M1). No MLX or Core ML | **High.** `laya-serve` speaks `POST /v1/systemone`; types are choice / score / noul with probabilities |
| **Kev** | VERIFIED (size range understated) | Jared Palmer | Apache 2.0 | Kev-0.8B repo is 65.6 MB (LoRA 43.3 MB + `head.pt` 2.1 MB + tokenizer). The Qwen3.5-0.8B base is downloaded separately. Kev-27B is 51 GB | Yes, [HF collection](https://huggingface.co/jaredpalmer/kev-0.8b), [GitHub](https://github.com/jaredpalmer/kev) | **MLX** is used automatically on Apple silicon; MPS for training. 0.8B and 4B are measured on MLX | **Highest.** The TypeSafe Python SDK works unchanged; noul / choice / score with `probabilities` + `confidence` |
| **NanoJev** | PARTLY | Tianyu (GitHub `TianyuCodings`, HF `C-Tianyu`) | MIT (code); Qwen base keeps its own license | Not stated (`best.safetensors` + backbone) | Yes, [HF `C-Tianyu/NanoJev`](https://huggingface.co/C-Tianyu/NanoJev), [GitHub](https://github.com/TianyuCodings/NanoJev) | Not documented. The quick start is CUDA / bf16 only | **Medium.** Choice (2-255) / Boolean / Score with probabilities, but on its own endpoint (`POST /api/evaluate`), not `/v1/systemone` |
| **Von** | VERIFIED | Victor Hugo Panisa (`wfzyx`) | Apache 2.0 | 1.5 GB fp32 weights; about 3 GB fetched on first use | Yes, [HF `wfzyx/von`](https://huggingface.co/wfzyx/von), [GitHub](https://github.com/wfzyx/von) | PyTorch **MPS**; also CPU via OpenVINO, CUDA and ROCm. No ONNX, Core ML or MLX | **High.** `von serve` exposes `/v1/systemone`, described as "byte-compatible" with TypeSafe; `decide` / `judge` / `rate` |
| **SemIf** (formerly OpenJev) | VERIFIED | `TheoLeeCJ` and contributors | MIT (code) | No weights of its own. Uses upstream models, e.g. Qwen3-0.6B Q8 639 MB or Qwen3.5-4B Q4_K_M 3.01 GB | N/A: frozen upstream models | **MLX** backend or PyTorch MPS; **llama.cpp / GGUF** on CPU; also a WebGPU demo | **Medium.** Option probabilities from logits with optional temperature calibration, through a `semif-score` CLI. No `/v1/systemone` endpoint documented |
| **Nimble** | VERIFIED | Bespoke Labs | Apache 2.0 (HF card; the README states none) | LoRA adapter ≈ 165-173 MB plus the Qwen3.5-9B base (≈ 18 GB unquantized) | Yes, [HF `bespokelabs/Bespoke-Nimble-9B-v2`](https://huggingface.co/bespokelabs/Bespoke-Nimble-9B-v2), [GitHub](https://github.com/bespokelabsai/nimble) | **MLX**, but only after a CPU merge of the adapter (64 GB RAM suggested). No quantized weights. The HF quick start is CUDA | **Medium.** Enum (1-255) or boolean fields, each with per-candidate probabilities. No Score type and no Jev endpoint |

### Where each claim was right or wrong

- **Laya: matches.** Two checkpoint families are confirmed: ModernBERT-large (421M) and mmBERT-base (322M, 100+ languages, 1,024-token context). Both answer without generating text. The authors claim 32.8 ms per decision against 236-276 ms for Jev, and 0.766 against 0.727 accuracy, but they say they did not measure Jev themselves.
  - **Weak spot:** accuracy collapses past about 20 options (Banking77 0.425 vs Jev 0.870, per [orcarouter](https://www.orcarouter.ai/blog/laya-vs-decider)).
  - **Server limits:** the server rejects more than 100 choice options.
  - **Confidence:** this is 1 minus normalized entropy, so Jev thresholds do not transfer ([GitHub](https://github.com/NandhaKishorM/laya)).
- **Kev: matches, and the "0.8B-9B" range is incomplete.** Kev 1.0 ships 0.8B, 4B, 9B and **27B**. Older Qwen3 and Qwen2.5 checkpoints (0.5B, 0.6B, 4B, 8B) are frozen. Each checkpoint is a rank-16 LoRA plus a pointer head; 27B is a full fine-tune ([GitHub](https://github.com/jaredpalmer/kev)).
- **NanoJev: partly matches.** The 0.6B model on a Qwen3 base is correct. The claim of "low-latency agent loops / edge" is not supported by the sources. The card and README cover game decisions (Maze, Snake, ViZDoom), publish no inference latency and target CUDA. Several HF accounts mirror the card. An unrelated `sdmlai/nano-jev` also exists: a 33.4M MiniLM cross-encoder for RAG checks.
- **Von: matches.** It is ModernBERT-large, 395M, with an Option-Marker head. The latency claims are inconsistent: the About blurb says "sub-15ms", but the README table gives a 0.34 s CPU p50 and a 0.096 s p50 on a 4-vCPU Xeon (OpenVINO).
- **SemIf: matches.** It does no training and reads typed option probabilities from frozen open models. The authors report 0.845 agreement with Jev on a 102-row subset (Jev scored 0.883 on the same subset), and 5.21x faster than generating JSON ([README](https://raw.githubusercontent.com/TheoLeeCJ/SemIf/master/README.md)). It is the only option here that runs through **llama.cpp**.
- **Nimble: matches.** It is a Qwen3.5-9B LoRA trained on answer tokens only, with open data curation, training and serving code. The authors report 90.1% agreement with reference labels against 93.2% for Jev 1.13.0, on 324 examples. They state it was "built in one day" and was not distilled from Jev. It is too heavy for an app-embedded model.

### Fit for a Swift macOS app

None of the six ships Core ML or a Swift SDK, and all are Python-first. Ranked by how easily they embed:

1. **Laya (`laya-multilingual`, 322M, ≈ 647 MB): best candidate.**
   - It is an encoder, so the ONNX export runs from Swift through ONNX Runtime's Apple package without a Python sidecar. The encoder could also be converted to Core ML later (unverified).
   - It is multilingual, which covers Spanish.
   - It suits palette routing with fewer than about 20 options.
2. **Kev-0.8B (≈ 66 MB adapter + Qwen3.5-0.8B base): runner-up.** It has the best Jev API parity and native MLX support, but today it needs a local Python server. A pure MLX Swift port would have to reimplement the pointer head.
3. **Von: possible.** It is about the same size as Laya, but heavier on disk and MPS/Python only.
4. **SemIf + Qwen3-0.6B GGUF: possible.** It could reuse llama.cpp, but it has no calibrated head of its own.
5. **NanoJev and Nimble: not suitable for in-app use.** NanoJev is CUDA-oriented and game-focused. Nimble needs a 9B base and a 64 GB merge.
