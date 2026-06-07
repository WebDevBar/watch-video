# Transcription backend — caveats & upgrade paths

v1 uses **`faster-whisper` on CPU (int8)**. Fine for occasional few-minute
videos; a multi-minute Loom transcribes in well under real-time on a modern CPU.

- **CPU (default):** zero GPU setup, fully portable. Slower on long videos —
  bump to a smaller `--model` (`base`/`tiny`) if needed, or accept the wait.
- **NVIDIA / CUDA:** `faster-whisper` supports CUDA out of the box. With an
  NVIDIA GPU, set `device="cuda"`, `compute_type="float16"` in `transcribe()`
  (or expose a `--device` flag) for a ~4× speedup. Needs CUDA + cuDNN libs.
- **AMD (ROCm) / Apple Silicon / cross-vendor GPU:** `faster-whisper`
  (CTranslate2) has **no ROCm or Metal** path — it runs CPU-only on AMD/Mac.
  For GPU there, swap the backend to **`whisper.cpp` with Vulkan** (works on AMD
  RDNA, Intel, NVIDIA) or Metal (Apple). This is why the backend is kept
  isolated in `transcribe()` — it's a drop-in swap, not a rewrite. (On AMD/Apple today the pipeline runs on CPU; whisper.cpp+Vulkan/Metal is the GPU path.)

## Why this is isolated

Keeping all transcription behind a single `transcribe()` function means the
backend can be swapped without touching the download / frame-extraction / OCR /
dedupe pipeline. The reference plugins do the same thing differently
(`mlx-whisper` vs `openai-whisper` vs cloud Whisper) — see
[REFERENCE-PLUGINS.md](REFERENCE-PLUGINS.md). Our isolation point is the seam
where we'd pick up `whisper.cpp + Vulkan` for AMD GPU support.
