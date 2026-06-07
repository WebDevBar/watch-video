# Why watch-video exists

## The problem

LLM coding agents (Claude Code, etc.) can't watch a video. But clients
increasingly hand us **screen recordings** — usually **Loom** — instead of
written tickets. Those recordings:

- carry **sparse, non-technical instructions** ("make this bit look like that
  thing I showed you") that only make sense alongside what's on screen, and
- frequently show **financial figures** — dashboard numbers, invoice totals,
  Stripe amounts — that are *shown* on screen and never spoken aloud.

To act on one, an agent needs the video turned into something it can actually
read: a **timestamped transcript**, a **deduplicated set of key frames**, and
**OCR of the on-screen text** (so the numbers survive).

## Why not just adopt an existing plugin?

Two mature Claude-Code video plugins already exist (see
[REFERENCE-PLUGINS.md](REFERENCE-PLUGINS.md)), and we will reuse their
**packaging**. But neither meets our **content** requirements:

| Requirement | `bradautomates/claude-video` | `mathiaschu/watch` | We need |
|---|---|---|---|
| Transcription stays **local** | ❌ cloud (Groq / OpenAI Whisper API) | ✅ local (mlx/openai-whisper) | ✅ **mandatory** |
| **OCR** of on-screen text | ❌ none | ❌ none | ✅ **mandatory** |
| **Frame dedupe** (static screencasts) | ❌ none | ❌ none | ✅ |
| **Loom** private/team links | ❌ "not private/authenticated" | ✅ via cookies | ✅ |

The blockers:

1. **Privacy.** `claude-video` ships audio to Groq/OpenAI for transcription.
   Our recordings contain private and financial client data — transcription and
   OCR **must run entirely on-device**. This alone rules out the original.
2. **No OCR anywhere.** `watch` is local and privacy-first, but like the
   original it has **no OCR**. On-screen financial figures (numbers in a
   dashboard, an invoice total) are not spoken, and frames-as-images read
   numbers unreliably at the low frame/token budgets these tools enforce.
   Without OCR the most important data on the screen is the data most likely to
   be lost.
3. **No dedupe.** Screen recordings are mostly static — long stretches of an
   unchanged screen. Neither tool dedupes frames, so they spend token budget
   shipping near-identical images. We dedupe to keep only meaningfully
   different frames.

The build-vs-adopt decision was peer-reviewed with Codex: no popular maintained
tool fits the **local + Loom-native + financial-OCR** combination. The closest
maintained option at ~1.7k★ is cloud-transcription.

## What watch-video adds (the edge we keep)

On top of the packaging we borrow, watch-video contributes:

1. **Local OCR (tesseract)** → `frames/ocr-combined.md`. Reads numbers and
   labels off the screen even when nothing is said about them.
2. **`faster-whisper` (CTranslate2, int8) backend**, deliberately isolated in
   one `transcribe()` function so it's a drop-in swap to **whisper.cpp + Vulkan**
   on AMD/Intel GPUs (see [TRANSCRIPTION-BACKENDS.md](TRANSCRIPTION-BACKENDS.md)).
3. **Perceptual-hash frame dedupe** (`--dedupe-distance`) — only
   meaningfully-different frames are kept, cutting token cost on static screens.
4. **Loom-native** capture, including private/team links via
   `--cookies-from-browser`.
5. **Persistent, re-readable output folder** with a `SUMMARY.md` the agent reads
   first — auditable after the fact, not just streamed once into context.
6. **Contact sheet** (`contact-sheet.jpg`) for a fast human/agent overview.

## Where this is going

Today watch-video is a single-file CLI: the agent runs it and reads the output
folder. The next step is packaging it as a native Claude Code skill/plugin so
the agent invokes it and gets frames + transcript **directly in-context** —
reusing the layout the reference plugins already solved. See
[PACKAGING.md](PACKAGING.md).
