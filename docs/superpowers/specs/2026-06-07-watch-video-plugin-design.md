# watch-video → Claude/Codex plugin — design spec

**Date:** 2026-06-07
**Status:** design approved in brainstorming; Codex peer-reviewed (13 rounds, all findings triaged + resolved); pending user sign-off
**Repo:** `webdevbar/watch-video`

## 1. Goal

Package the existing `watch-video` CLI as a native skill/plugin for **Claude
Code**, **Codex**, and **claude.ai web** (web = best-effort) so an agent can
invoke it and pull a client screen-recording's transcript + key frames + OCR
directly into context — while the current CLI keeps working unchanged
throughout development.

See [`docs/WHY.md`](../../WHY.md) for rationale (privacy, Loom-native,
financial-OCR) and [`docs/REFERENCE-PLUGINS.md`](../../REFERENCE-PLUGINS.md) for
the packaging templates (`mathiaschu/watch`, `bradautomates/claude-video`).

## 2. Hard constraints

1. **The working CLI must never break during development.** It is usable today
   (verified 2026-06-07: `uv` 0.11.15, ffmpeg + tesseract present,
   `./watch-video --help` exits 0). All CLI changes are **additive**: no
   existing flag, default value, or output *filename* changes meaning, and no
   existing output file is removed, renamed, or has its content altered. The
   default run may gain **new additive files** — a `.watch-video.json` run
   manifest (§5.6) and `timeline.md` (§5.3) — because they don't touch anything
   that already exists. New *opt-in* flags may also suppress output when
   explicitly passed (e.g. `--no-transcribe` skips the transcript); **existing**
   output files are unchanged unless the user passes the flag. An opt-in flag
   may also *change the content* of an output when explicitly passed (e.g.
   `--ocr-tuned` improves OCR text) — again, only when the user opts in.
   Precise statement of the guarantee:
   - **Data outputs** (`transcript.md`/`.txt`, `frames/*.jpg`,
     `frames/ocr/*.txt`, `frames/ocr-combined.md`, `contact-sheet.jpg`) keep
     their name, format, and default-run byte content.
   - **`SUMMARY.md` is the human/agent index** — its explicit job is to
     enumerate the artifacts a run produced, so it legitimately gains lines for
     new additive artifacts (`timeline.md`, and a note for `.watch-video.json`).
     It never *removes or renames* an existing entry; it only grows. This file
     is therefore **excluded from the byte-identical clause** by design.
   - The default file *set* may grow by `timeline.md` + `.watch-video.json`.
   - **Scope.** This guarantee is about *what a single run produces* and the
     default **fresh-folder** run — it is not a promise to preserve artifacts
     from a *previous* run when you re-run into the same deterministic folder.
     Re-running is inherently a replace operation (the current CLI already
     overwrites `transcript.md` and rewrites `frames/` on re-run); §5.7 makes
     that reconciliation explicit and correct. No *unrelated* (non-watch-video)
     file is ever removed or renamed.
2. **Single source of truth.** The packaging layer is a *thin wrapper* that
   shells out to the existing single-file `watch-video`. No second copy of the
   pipeline, no parallel runtime.
3. **Everything stays local — on local surfaces.** Transcription + OCR never
   leave the machine; privacy is the reason the tool exists. This guarantee
   holds for **Claude Code** and **Codex**, which run on the user's machine.
   ⚠️ **claude.ai web runs in a hosted sandbox** — sending a recording there
   means it leaves the user's machine. **Decision (2026-06-07): ship web, but
   with a hard privacy warning** — the web surface is for **non-sensitive /
   public videos only**; sensitive videos must stay on Claude Code or Codex.
   `SKILL.md` and `commands/watch.md` must carry this warning prominently
   (see §9).

## 3. Architecture — thin wrapper

```
agent → /watch command  →  scripts/watch-run.py  →  uv run --script watch-video (single-file, unchanged)
                                                     ↓
                                            output folder (persistent)
agent ← reads SUMMARY.md, timeline.md, transcript.md, frames/*.jpg, frames/ocr-combined.md
```

The CLI remains the only implementation of the pipeline. The plugin adds:
invocation surface (SKILL.md + command), bootstrap (setup.py), packaging
metadata, build/release tooling, and a read-order contract for the agent.

## 4. Repository layout

Additive around the existing files (existing files marked *unchanged* keep
working standalone):

```
watch-video                     # existing CLI — *additive flags only*
README.md                       # existing — updated to mention plugin form
docs/                           # existing docs (WHY, REFERENCE-PLUGINS, PACKAGING, …)
SKILL.md                        # NEW — skill contract loaded across all surfaces
.claude-plugin/
  plugin.json                   # NEW — plugin manifest
  marketplace.json              # NEW — marketplace metadata
.codex-plugin/
  plugin.json                   # NEW — Codex plugin manifest (format verified at impl)
commands/
  watch.md                      # NEW — the /watch slash command
scripts/
  watch-run.py                  # NEW — the wrapper the /watch command calls (see §9)
  setup.py                      # NEW — per-OS bootstrap (uv + ffmpeg + tesseract)
  build-skill.sh                # NEW — emit distributable watch.skill bundle
.github/workflows/
  release.yml                   # NEW — build the .skill bundle on tag
tests/
  smoke_test.sh                 # NEW — tiny-clip end-to-end + --clean check
CHANGELOG.md                    # NEW
LICENSE                         # NEW
```

## 5. CLI additions (non-destructive)

All default behavior unchanged. New flags:

### 5.1 Cleanup (`--clean`)
A janitorial mode, mutually exclusive with a normal run. Cleanup mode is
triggered when **either** `--clean <arg>` **or** `--clean-older-than DAYS` is
present (both are standalone — neither requires the other, and they are not
combined). In cleanup mode the tool purges and exits without processing a video;
`source` is not required.

**Base directory.** The existing CLI treats `--out DIR` as the *exact* output
folder for a run, **not** a base. Cleanup therefore defines its own base, the
**default output base** `./watch-video-out/`, and operates only within it:

- `watch-video --clean <slug>` — a **bare token** (no path separator, not
  absolute) is *always* a slug, resolved under the default base →
  `./watch-video-out/<slug>/`. A bare token is never interpreted as a path, even
  if a same-named directory exists in the cwd (removes the `demo` vs `./demo`
  ambiguity).
- **`all` is a reserved keyword** (see next), not a slug. To clean a run folder
  literally named `all`, use its path: `watch-video --clean ./watch-video-out/all`.
- `watch-video --clean <path>` — an argument that **contains a path separator
  (`/`, or `\` on Windows) or is absolute** is treated as an explicit directory
  path; delete that exact folder **only after the ownership check passes** (see
  below). Path detection uses the platform's separators, so a Windows relative
  path like `.\watch-video-out\demo` is correctly treated as a path, not a slug.
  This is how ephemeral
  mode cleans a custom `--out DIR` run (the wrapper always passes a path with a
  separator, never a bare token).
- `watch-video --clean all` — delete every immediate subfolder of the default
  base **that passes the ownership check**. Other directories under the base are
  left untouched and reported as skipped.
- `watch-video --clean-older-than DAYS` — same as `all`, restricted to
  ownership-checked subfolders whose **age is older than DAYS, measured from the
  manifest's `"created"` timestamp** (§5.6) — *not* directory mtime, which
  ordinary file reads/writes (or back-filling a manifest into a legacy folder)
  can bump independently of run age. If a folder's manifest lacks a parseable
  `"created"`, it is skipped (reported), never deleted by age.

**Ownership check (the deletion gate).** A directory is deletable only if it
contains a valid **`.watch-video.json` run manifest** (§5.6) — a hidden,
tool-specific marker watch-video writes on every run, whose content carries a
signature (`{"tool": "watch-video", "version": …, "source": …, "created": …}`).
Cleanup parses the file and verifies the `"tool": "watch-video"` signature —
**not merely the filename's presence**. A human-facing `SUMMARY.md` is *not*
sufficient (that filename is common elsewhere). This makes accidental deletion
of an unrelated directory effectively impossible, including for an explicit
`--clean <path>` outside the default base.

**Safety guard.** *Every* cleanup operation requires the validated
`.watch-video.json` signature. Directories under the default base that lack it
are skipped (reported). An explicit `--clean <path>` may sit outside the default
base but still must pass the same signature check. Cleanup never deletes a
directory lacking a valid manifest, and never recurses outside these rules.
Prints what it deleted and what it skipped.

**Ephemeral interaction.** Because a custom `--out DIR` run is not locatable by
slug, the wrapper (and the `/watch --ephemeral` orchestration) **records the
actual output directory** the CLI used and passes that exact path to
`--clean <path>` — never a guessed slug.

### 5.2 Source pruning (`--no-source`)
After frames + transcript are extracted, delete the downloaded `source.*` file
**— but only a file that yt-dlp downloaded into the output directory.** It must
**never** delete a user-provided local input file. To make this safe rather than
heuristic, **`acquire()` is changed (additively) to return provenance** — a
`(path, was_downloaded)` pair instead of just a path. `--no-source` unlinks
**only when `was_downloaded` is true**; a local input passed by the user is
never deleted, even if it happens to sit inside the output directory. Default remains **keep
source** (so a re-run with different `--periodic` doesn't re-download). The raw
downloaded video is the largest and most sensitive single artifact, so
`--no-source` is offered for disk + data-at-rest hygiene.

### 5.3 Timeline output (`--timeline`, on by default)
Emit `timeline.md` (see §6.1). On by default because it is the agent's primary
comprehension doc; `--no-timeline` disables it. *(Naming note: follows the
existing `--no-ocr` / `--no-contact-sheet` convention.)*

### 5.4 OCR tuning (`--ocr-tuned`, opt-in)
A tuned OCR path: upscale small frames, grayscale + adaptive threshold, and a
tuned tesseract PSM for denser on-screen text — improving on-screen number
accuracy. **Opt-in (default off)** so the default CLI's OCR output stays
byte-identical to today (honors §2.1); the `/watch` command enables it by
default (§7). Output filenames and `--no-ocr` behavior unchanged — only the OCR
*text content* improves, and only when the flag is passed.

### 5.5 `--no-transcribe` (additive; enables offline tests)
Skip the faster-whisper transcription pass entirely. When set, no
`transcript.md`/`transcript.txt` is written and `timeline.md` shows frames +
OCR only. This exists so the smoke test (§10) can exercise the
acquire→frames→dedupe→OCR→timeline→clean path **without the Whisper model
download** (the runtime network dependency) — faster-whisper would otherwise
fetch the model on first run. This removes the *model* network need; the
one-time `uv` dependency resolution is a separate concern handled by a warm
cache (see §10 for the precise offline conditions). Default behavior
(transcribe) is unchanged.

### 5.6 `.watch-video.json` run manifest (additive; the cleanup ownership marker)
On **every** run, watch-video writes a small hidden `.watch-video.json` into the
output folder, e.g.:
```json
{"tool": "watch-video", "version": "1.x", "source": "<source>", "created": "<iso8601>"}
```
This is the tool-specific ownership marker the cleanup gate (§5.1) validates by
signature before deleting anything — far safer than relying on a `SUMMARY.md`
filename. It is a new additive file (hidden, never alters/removes existing
output), permitted under §2.1. It also doubles as lightweight run metadata.

### 5.7 Stale-artifact policy (reused output folders)
The CLI reuses a deterministic folder (`./watch-video-out/<slug>/`), so a second
run into the same folder could leave artifacts from the first. Because §7's
contract says `SUMMARY.md` lists exactly what *this* run produced, each run must
**reconcile the folder to its own artifact set**: before writing, the CLI
removes any prior watch-video-generated artifact that this run will *not*
produce — `transcript.md`/`.txt` under `--no-transcribe`, `ocr*`/`ocr-combined.md`
under `--no-ocr`, `timeline.md` under `--no-timeline`, `contact-sheet.jpg` under
`--no-contact-sheet`, and stale `frames/*` from a prior run. The downloaded
`source.*` is preserved (it is intentionally cached for cheap re-runs, §5.2).
Only watch-video-generated files are touched — never anything else in the
folder. This keeps `SUMMARY.md` accurate and prevents the agent from reading a
stale artifact a suppressing flag was meant to omit.

## 6. v1 feature additions (detail)

### 6.1 `timeline.md` — frame ↔ transcript interleave
A single chronological document merging the two existing data sources by
timestamp:

- Walk kept frames and transcript segments in time order.
- For each kept frame at time *t*, emit the frame reference and the transcript
  line(s) whose start falls between this frame and the next.
- If OCR ran, include a short OCR snippet for that frame inline.

Example shape:
```
## 0:00
![frame](frames/frame_000_0m00s.jpg)
> (transcript) "Okay so this is the dashboard…"
OCR: Revenue  $4,200   MRR  $1,180

## 0:12
![frame](frames/frame_001_0m12s.jpg)
> (transcript) "…and this number here is wrong, it should be…"
```

Built purely from data the pipeline already produces (frame list + timestamps,
transcript segments, OCR text). No new heavy dependency.

**Degrades gracefully.** Each of the three inputs is optional: with
`--no-transcribe` there are no transcript segments (timeline shows frames + OCR
only); with `--no-ocr` there is no OCR line; with neither, the timeline is still
a valid frames-only timeline. Timeline generation must tolerate any missing
input — this is what lets the offline smoke test (§10) assert `timeline.md`
under `--no-transcribe`.

### 6.2 OCR tuning (behind `--ocr-tuned`, §5.4)
Goal: more reliable reading of on-screen numbers (the financial-OCR purpose).
When `--ocr-tuned` is passed, preprocess each frame before tesseract: upscale if
width < threshold, convert to grayscale, apply adaptive/Otsu threshold, and
select a PSM suited to screen UI text. Default (flag absent) OCR is unchanged.
Keep the raw frame image as ground truth in `SUMMARY.md` guidance (OCR can still
misread).

## 7. Return contract & SKILL.md behavior

- **Default: persistent output folder + read-order contract.** `SKILL.md`
  tells the agent to read, **in this order, skipping any file that is not
  present**: `SUMMARY.md → timeline.md → transcript.md → frames/*.jpg →
  frames/ocr-combined.md`. `SUMMARY.md` is always written and lists exactly
  which artifacts this run produced, so the agent reads `SUMMARY.md` first and
  then only the artifacts it names — runs with `--no-transcribe` / `--no-ocr` /
  `--no-timeline` legitimately omit the corresponding file, and the contract
  tolerates that rather than assuming all five always exist. (OCR lives **under
  `frames/`** — the CLI writes `frames/ocr-combined.md`; the read order matches
  the on-disk path, which §12 forbids renaming.)
- **Ephemeral mode is a two-step, agent-driven orchestration — not a single
  call.** A wrapper invocation cannot both return control so the agent can read
  the files *and* resume later to delete them. So `/watch … --ephemeral` is
  explicitly two commands the **agent** runs in sequence, per `SKILL.md`:
  1. **Step 1 — run:** the wrapper runs the CLI and surfaces the **output
     directory** to the agent, derived from the CLI's single stdout line (the
     `SUMMARY.md` path → its parent dir; §9 output-dir contract). It does
     **not** clean up.
  2. **Step 2 — read, then clean:** the agent reads the artifacts into context,
     then runs `scripts/watch-run.py --clean <output-dir-from-step-1>` (the
     wrapper's cleanup pass-through, §9 — which resolves the bundled CLI so this
     works even when `watch-video` is not on `PATH`) as a separate command.
     `SKILL.md` instructs the agent to perform step 2 only after it has finished
     reading.
  Built on the §5.1 `--clean` primitive; the path is the exact directory from
  step 1, never a guessed slug.
- `SKILL.md` states the privacy posture: local-only transcription/OCR; output
  folders may contain private/financial data and must never be committed or
  uploaded.
- **Command defaults.** The `/watch` command invokes the CLI with `--ocr-tuned`
  enabled by default (better on-screen-number accuracy for the agent use case),
  while the bare CLI leaves it off (§5.4). `timeline.md` is produced regardless
  (CLI default-on, §5.3). Users can still pass `--no-ocr` / `--no-timeline`
  through the command.

## 8. Bootstrap (`scripts/setup.py`)

- Ensure `uv` is installed (official install script if missing). **No-install
  fallback:** if `uv` cannot be installed (no network, no shell permission, no
  writable install location), setup.py does **not** silently fail — it exits
  non-zero with a clear message listing `uv` as a manual prerequisite and a link
  to the install docs. The same hard-fail fallback applies to `ffmpeg` (also
  required); `tesseract` is the exception — it is optional and warn-only (next
  bullets).
- Ensure `ffmpeg` (**required**) via the OS package manager: `brew` (macOS),
  `apt`/`dnf` (Linux), `winget` (Windows). Fall back to a clear manual-install
  message (non-zero exit) if ffmpeg can't be installed.
- `tesseract` is **optional** (OCR-only; the CLI already skips OCR when it's
  absent). setup.py attempts to install it best-effort and **warns but does not
  hard-fail** if it can't — consistent with §10 treating tesseract as the one
  optional dependency.
- Required prerequisites (`uv`, `ffmpeg`) and the optional one (`tesseract`) are
  documented in `SKILL.md` and README so a locked-down environment can
  preinstall them rather than relying on setup.py's auto-install.
- Python **packages** are handled by `uv` via the script's inline dependency
  block — setup.py does not duplicate them. The **Whisper model is a separate
  concern**: it is *not* a uv dependency — faster-whisper fetches it at runtime
  when `WhisperModel(...)` is first constructed, then caches it. setup.py may
  optionally pre-warm the model (download `--model small` once) so first real
  use is offline; if it does not, document that the first transcribe needs
  network for the model fetch.
- **Surface tiers:** Claude Code + Codex (real machines) are first-class.
  **claude.ai web is best-effort** — whether the sandbox permits system-package
  installs and persists the model download is **verified during
  implementation**, not promised here. If web cannot bootstrap, document the
  limitation rather than block the release.

## 9. Packaging files

- `SKILL.md` — name, description, when-to-use, the run + read-order contract,
  privacy note, dependency note (points at setup.py). **Must carry the web
  privacy warning prominently:** on Claude Code/Codex everything stays local;
  the **claude.ai web surface runs in a hosted sandbox, so it is for
  non-sensitive / public videos only — never send a sensitive video to the web
  surface.**
- `.claude-plugin/plugin.json` + `marketplace.json` — modelled on the reference
  plugins; marketplace install path `/plugin marketplace add … && /plugin
  install watch@…`.
- `.codex-plugin/plugin.json` — Codex plugin manifest. The exact Codex plugin
  schema is **not assumed**: at implementation, confirm the current format
  against Codex docs and the reference plugins' `.codex-plugin/` layouts
  (`bradautomates/claude-video`), then write the concrete manifest. The skill
  body (run + read-order + privacy contract) is shared with `SKILL.md`.
- `scripts/watch-run.py` — **the wrapper**; the concrete component the `/watch`
  command invokes (step 1 of §7's ephemeral flow). Responsibilities: (1) resolve
  the path to the root `watch-video` CLI **relative to the skill's own install
  directory** (not cwd), and invoke it **portably as
  `uv run --script <path-to-watch-video> …`** — never by executing the
  extensionless shebang file directly, which fails on Windows; (2) apply
  `/watch` defaults (`--ocr-tuned` on, §7) and pass through user flags, **but
  intercept the wrapper-only `--ephemeral` flag and NOT forward it to the CLI**
  (the CLI has no such flag; forwarding it would make argparse reject the run) —
  on `--ephemeral` the wrapper behaves identically to a normal run and just emits
  the one output-dir line (the §7 step-2 cleanup instructions are static text in
  `commands/watch.md`/`SKILL.md`, not printed at runtime — see the output-dir
  contract below); (3) run the CLI, read the CLI's single stdout
  line (the `SUMMARY.md` path), and **emit exactly one stdout line of its own —
  the output directory** (that line's parent; the two-layer output-dir contract
  below); (4) support a **cleanup pass-through mode**
  (`watch-run.py --clean <dir>`) that resolves the bundled CLI and runs
  `uv run --script watch-video --clean <dir>` for it — this is what the agent
  calls in ephemeral step 2, so cleanup never depends on `watch-video` being on
  `PATH`. **Cleanup mode forwards only cleanup flags** (`--clean` /
  `--clean-older-than`) and does **not** apply the `/watch` processing defaults
  like `--ocr-tuned` (cleanup is a janitorial run, mutually exclusive with
  processing per §5.1 — mixing them would be rejected by argparse).
  The wrapper holds no pipeline logic; it only orchestrates the unchanged CLI.
- **Output-dir contract (single, pinned, two layers).** The contract is layered
  so each component has exactly one stdout line:
  - **CLI layer:** the existing CLI prints exactly one stdout line — the
    `SUMMARY.md` path — with all logs on stderr. Unchanged.
  - **Wrapper layer:** the wrapper reads that line, derives the **output
    directory** as its parent, and emits **exactly one stdout line of its own:
    the output directory**. That single line is the wrapper's contract with the
    agent (the value passed to ephemeral step-2 cleanup). No human-text parsing;
    no second line.
  - **Step-2 instructions are static, not runtime stdout.** The "read, then run
    `watch-run.py --clean <dir>`" guidance lives in `commands/watch.md` /
    `SKILL.md` (text the agent already has), so the wrapper never needs to print
    instructions — only the one output-dir line.
  - `--print-output-dir` is **not** part of this flow (dropped to avoid a second
    conflicting CLI stdout contract).
- `commands/watch.md` — the `/watch <url|file> [options]` slash command; calls
  `scripts/watch-run.py`; documents `--ephemeral` as the orchestration mode, and
  repeats the web privacy warning (non-sensitive / public videos only on the web
  surface).
- `scripts/build-skill.sh` — bundle into a distributable `watch.skill` for
  claude.ai web upload + manual install. **The bundle MUST include the
  `watch-video` CLI itself** (plus `SKILL.md`, `commands/`, `scripts/`) — the
  wrapper shells out to `./watch-video`, so a bundle without it would have
  nothing to execute. Defined artifact layout: the CLI ships at the bundle root
  as `watch-video`, and the wrapper resolves it **relative to the skill's own
  install directory** (not the cwd), so it works regardless of where the skill
  is installed. build-skill.sh asserts the CLI is present in the staged bundle
  before packaging.
- `.github/workflows/release.yml` — on tag, run build-skill.sh and attach the
  bundle to the release.

## 10. Testing

- `tests/smoke_test.sh` (offline core) — generate a tiny synthetic clip locally
  (ffmpeg test source + short tone, no network), run
  `watch-video --no-transcribe` against it, and assert: `SUMMARY.md`,
  `timeline.md`, at least one `frames/*.jpg`, and `.watch-video.json` exist;
  **when tesseract is present, also assert `frames/ocr-combined.md` exists**
  (so the OCR path §5.5 claims is actually exercised). `--no-transcribe` (§5.5)
  avoids the **Whisper model download** (the runtime network dependency). The
  remaining network need is the one-time `uv` dependency resolution; CI/dev
  **pre-warms the uv cache** (or preinstalls deps) so the test body itself runs
  offline. Honest claim: *offline once uv deps are cached; no model download
  ever*. **Hard prerequisites: `uv`, `ffmpeg`, and the script's Python deps
  available via a warm `uv` cache (or preinstalled).** Without `uv` the CLI
  can't start; without a warm cache + no network the deps can't resolve; ffmpeg
  is needed for the synthetic clip + frame extraction. The test skips entirely
  if any of these is unmet. **tesseract is the only *optional* dependency** — if
  it's missing the test still runs the core path and **only the OCR assertion is
  skipped** (the CLI already degrades by skipping OCR).
- Transcription test (network-permitted / model-cached) — separate, opt-in:
  run with `--model tiny` and assert `transcript.md` exists. Documented as
  requiring a one-time model fetch; skipped when offline or model uncached.
- `--clean` check — create `./watch-video-out/<slug>/.watch-video.json` (a valid
  manifest under the **default base**, matching the documented slug resolution),
  run `--clean <slug>`, assert it is gone; then assert a directory **lacking a
  valid `.watch-video.json` signature is refused** (even if it contains a
  `SUMMARY.md`), and that a bare token is resolved under the default base, never
  as a cwd path.
- Keep tests local + fast (project test-time-limit rules).

## 11. Deferred (documented scope, not in v1)

Each is a deliberate scope exclusion with rationale:

- **GPU / `--device` flag** — this machine is AMD (faster-whisper is CPU-only
  on AMD/Mac); the real AMD GPU path is the whisper.cpp+Vulkan backend swap,
  already a documented upgrade path in
  [`docs/TRANSCRIPTION-BACKENDS.md`](../../TRANSCRIPTION-BACKENDS.md). Not worth
  v1 complexity.
- **Native-captions fast path** — mostly a YouTube speed win; Loom (the primary
  source) usually has no captions, so Whisper runs anyway.
- **`--start/--end` windowing** — client Looms are typically short; whole-video
  sampling is sufficient for now.
- **Agent-facing structured JSON output** — a public results manifest (frames +
  timestamps + transcript segments + OCR as machine-readable data, e.g.
  `results.json`). The agent reads the markdown fine today; add only when a
  consumer needs structured output. *(Distinct from the required hidden
  `.watch-video.json` cleanup ownership marker in §5.6, which is internal, not
  agent-facing.)*
- **Long-video chunking / progress meter** — quality-of-life, not blocking.

## 12. Out of scope (hard exclusions)

- **No cloud transcription/OCR *backend* ever** — the pipeline never calls a
  third-party transcription or OCR *service* (unlike `bradautomates/claude-video`,
  which uses Groq/OpenAI Whisper). It always runs the local faster-whisper +
  tesseract pipeline. *(Distinct from where that local pipeline runs: on the
  claude.ai web surface it executes inside Anthropic's sandbox — the explicit,
  warned, non-sensitive-videos-only exception governed by §2.3, not a cloud
  transcription backend.)*
- No rewrite of the pipeline; wrapper-only.
- No change to existing CLI defaults or output filenames (new additive outputs
  such as `timeline.md` are permitted — see §2.1).

## 13. Open risks & decisions

- **✅ DECIDED (2026-06-07) — claude.ai web vs the local-only guarantee.**
  The web surface executes in Anthropic's hosted sandbox, so any video sent
  there leaves the user's machine — at odds with §2.3 and the tool's reason for
  existing. **Resolution: ship web with a hard privacy warning** — the web
  surface is packaged for *non-sensitive / public videos only*; sensitive
  videos stay on Claude Code/Codex. The warning is mandatory in `SKILL.md` and
  `commands/watch.md` (§9). Web install/runtime feasibility remains best-effort
  (next bullet).
- **claude.ai web sandbox (if web is kept)** — install + model-persistence
  unverified (see §8); treated as best-effort.
- **OCR tuning regressions** — preprocessing could *reduce* accuracy on some
  frames; mitigate by keeping the frame image as ground truth and validating
  on a real Loom during implementation.
- **`uv` absence on a target surface** — setup.py installs it; if a sandbox
  forbids that, the surface falls to best-effort.
