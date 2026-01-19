# Voice Chat

> [!WARNING]
>
> This project is still under construction and may not be stable.
>
> The app has only been tested on macOS 26.2 and iOS 26.2. Running it on earlier versions or other devices may result in issues.

## Overview
Voice Chat is a SwiftUI app for macOS and iOS that combines:
- Text chat with a local/remote LLM server (OpenAI-compatible `v1/chat/completions` API).
- Voice output via a [GPT-SoVITS](https://github.com/RVC-Boss/GPT-SoVITS) API server.

You can use the Voice Mode to chat with AI in real-time.

## Requirements
- Xcode
- A chat server that supports OpenAI-compatible API (e.g. [LM Studio](https://lmstudio.ai) or [Ollama](https://ollama.com)).
- A [GPT-SoVITS](https://github.com/RVC-Boss/GPT-SoVITS) API (v2) server.

## Configuration
In the app’s Settings:
- **Chat Server**
  - Set **Chat API URL**
  - Set **Chat API Key** (optional)
  - Refresh and select a model
- **Voice Server**
  - Set **Server Address**
  - Configure a **Model Preset** (reference audio + weights paths) and apply it

## Tested Versions
- macOS 26.2
- iOS 26.2

## Acknowledgments
- [GPT-SoVITS](https://github.com/RVC-Boss/GPT-SoVITS)
- [swift-markdown](https://github.com/swiftlang/swift-markdown)
- [swift-cmark](https://github.com/swiftlang/swift-cmark)
- Open-source LLM tooling and communities that make this app possible.

## License
MIT — see `LICENSE`.
