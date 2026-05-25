# Tallyvity

Tallyvity is an iOS voice-driven Pomodoro and focus companion. It uses on-device speech-to-text, text-to-speech, and vision-language models to structure focus sessions, support progress tracking, and facilitate honest self-reflection [11]. By relying entirely on local processing, the application guarantees user privacy and operates completely offline [11].

## Core Design and Mechanics

The application centers around a structured Pomodoro flow designed to encourage cognitive accountability [11]. At the start of a session, the user speaks their goal, which is transcribed in real-time [11]. If starting motivation is low, defined as 2 or lower on a 1-to-5 scale, the engine adapts by offering a low-commitment 5-minute starter block to lower task initiation anxiety [10, 43].

During active focus blocks, a minimalist circular timer remains on screen and prevents device sleep [16, 46]. When the block finishes, a brief recovery buffer is provided before the voice assistant guides the user through three brief reflective questions regarding what was accomplished, what obstacles arose, and what changes should be made next [9, 11]. The user rates their output using clear behavioral anchors [11]. At session completion, a local large language model generates a factual, neutral summary of the completed loops, highlighting the user's stated next steps without subjective praise or evaluative judgment [11].

## Technical Architecture

Tallyvity is built natively for Apple Silicon platforms using SwiftUI and native Swift frameworks [11]. 

* **Audio Processing:** WhisperKit handles speech-to-text transcription utilizing the `openai_whisper-small_216MB` model [11, 41]. Speech is recorded at 16 kHz mono to optimize processing efficiency [53].
* **Voice Synthesis:** TTSKit drives text-to-speech feedback via the `qwen3TTS_0_6b` model to speak the reflection questions and session reports [11, 36].
* **On-Device Inference:** Gemma 4 VLM (`gemma4_E2B_it_4bit`) operates locally under MLX to generate context-aware questions, synthesize comparative feedback between baseline and ending photos, and summarize session outcomes [11, 38].
* **State Management:** A custom state machine manages state transitions and persists active checkpoints to local JSON flat-files to recover session progress in the event of an unexpected application termination [11, 13].
* **System Integration:** Live Activities and Dynamic Island support are managed through ActivityKit to keep active session progress visible on the lock screen and system bezel [11, 26].

## Getting Started

Building and running the project requires macOS 14.0 or later, Xcode 16.0 or later, and a device or simulator running iOS 18.0 or later.

To start the project, open `tallyvity.xcodeproj` in Xcode and build or run the main target [5]. On the first launch, the application performs a one-time download of approximately 820 MB of cached files to initialize the WhisperKit and TTSKit models [137]. The 3.6 GB Gemma 4 VLM can be downloaded separately within the application diagnostics settings panel [95, 108].

## Directory Layout

* `tallyvity/` contains the main application files, Swift models, and SwiftUI interfaces.
* `TallyvityWidget/` contains code for the lock screen widget and Dynamic Island configurations.
* `voice_prompt_generator/` is an optional Python-based utility for developers to batch generate voice prompts.
* `docs/` and `specs/` contain model setup specifications, developer rules, and implementation records.
