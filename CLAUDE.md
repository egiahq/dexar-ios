# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Open `dexar.xcodeproj` in Xcode. Build: `Cmd+B`. Run on simulator: `Cmd+R`. No CLI build setup — Xcode only.

## App Overview

iOS focus-session coach app. Voice-driven Pomodoro loop: records goal → runs timed work blocks → asks review questions → generates session report. Stack: SwiftUI + ArgmaxOSS (WhisperKit, TTSKit) + MLX (Gemma 4 VLM). No SwiftData — artifacts persisted as JSON in Documents.

## Architecture

Three engines created once in `RootView` as `@State`, injected as dependencies:

- **`SpeechEngine`** — owns WhisperKit + TTSKit; drives `State` enum through record→transcribe→speak. Audio cues (pre-recorded `.wav` files in `Assets/SFX/`) play via `playCueAndWait(named:)`; falls back to TTS if cue missing.
- **`GemmaEngine`** — wraps MLX `VLMRegistry.gemma4_E2B_it_4bit`; `generate(prompt:)` / `generate(image:prompt:)` stream output into `output: String`. Loaded lazily after onboarding.
- **`SessionEngine`** — orchestrates the full session as a Swift `async` task (`sessionTask`). Owns the `Phase` enum that drives all UI. Calls `SpeechEngine` and `GemmaEngine`. Checkpoints in-progress sessions to `active_session_checkpoint.json`.

`PromptStore` loads `prompts.json` at startup — all spoken text and UI labels live there. `SessionStore` persists `SessionArtifact` records and the resume checkpoint.

### Session flow

`motivationSelection` → `preparingAudio` → `goalCapture` → `photoBaseline` → `sessionReady` → [`backgroundPrep` → `workActive` → `roundEnd` → `selfScore` → `breakTime` → `nextSessionCountdown`] × N loops → `qaPlayback` × 3 → `storing` → `sessionReport`

Low-motivation path (score ≤ 2): first loop shortened to 5 min with a starter-framing prompt; user can opt out after that loop.

### Dynamic voice line generation

After goal capture, `SessionEngine` fires a background `Task` calling `GemmaEngine` to generate 5 context-aware voice lines per prompt category (`photo_baseline`, `round_end`, `self_score`, `break_start`, `next_session`, `session_done`). These override the static `prompts.json` presets for that session.

## Models

- WhisperKit: `openai_whisper-small_216MB` (multilingual; large-v3 too slow in practice)
- TTSKit: `qwen3TTS_0_6b`
- Gemma: `gemma4_E2B_it_4bit` via `MLXLMCommon` / `MLXVLM`

All models download from HuggingFace on first run and are cached locally.

## Code Style

- No comments. Names must be self-documenting.
- No abstraction layers until pattern repeats 3+ times.
- No view model boilerplate for simple views — state directly in view.
- Minimalist UI: system fonts, system colors, generous whitespace. No decorative chrome.
- Pinterest-level visual quality: every screen must feel considered and calm.
- `withAnimation` on all data mutations.
- `#Preview` on every view.

## ArgmaxOSS Conventions

- `WhisperKit` and `TTSKit` are expensive to init — create once, reuse.
- Audio recorded at 16 kHz mono (WhisperKit's native rate) to avoid resampling overhead.
- `tts.play()` streams audio frame-by-frame; no need to save to disk.
