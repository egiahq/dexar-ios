# Dexar iOS

Dexar is a local-first, voice-driven focus coach and Pomodoro application built in SwiftUI. It uses on-device machine learning (WhisperKit, Gemma VLM) to help users declare goals, capture progress photos, reflect on their work, and analyze productivity.

## Scientific Foundations

Dexar is built on established cognitive and behavioral principles:

- **Implementation Intentions:** Declaring goals aloud primes cognitive preparation.
- **Ultradian Rhythm:** Structuring work into focused intervals followed by deliberate rest.
- **Output-Based Monitoring:** Staged photo capture provides visual evidence of progress.
- **Structured Self-Assessment:** Metacognitive reflection beats external metrics or gamified reward loops.
- **Attention Restoration:** Rest breaks are fully decoupled from digital distractions.

## Core Features

- **Vocal Goal Declaration:** Declare goals aloud before starting. On-device WhisperKit transcribes and persists them.
- **Visual Progress Tracking:** Capture baseline, in-between round, and final photos of your workspace.
- **Metacognitive Reflection:** Guided QA and self-scoring at the end of each work round.
- **Zero-Latency Design:** Critical interface components run instantly, with ML models deferred to avoid blocking user flow.
- **Local-First & Private:** All speech recognition, vision, and text processing run offline on the device.
- **Session Auto-Recovery:** Automatic state serialization allows sessions to resume seamlessly after restarts.

## System Architecture

The application relies on three core engines:

1. **`SpeechEngine`:** Coordinates microphone hardware, manages audio cues, and handles WhisperKit transcription.
2. **`GemmaEngine`:** Leverages MLX Swift to execute local VLM operations for comparing workspace states.
3. **`SessionEngine`:** Drives the Pomodoro state machine, checkpoints session states, and handles file persistence.

## Tech Stack

- **User Interface:** SwiftUI
- **Audio & Transcription:** AVAudioFoundation, WhisperKit
- **On-Device Inference:** MLX Swift, CoreML
- **Persistence:** Local file system storage

## Getting Started

1. Open `dexar.xcodeproj` in Xcode.
2. Connect your iOS device or select a simulator target.
3. Build and run.
4. Grant microphone and camera permissions on launch.
