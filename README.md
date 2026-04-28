# 1Claw App — Multi-Agent Platform

Native mobile/desktop app for interacting with multiple AI agent profiles simultaneously.

## Features

- **Metro-style card grid** — beautiful, colorful agent profile cards
- **Multi-agent chat** — switch between agents instantly
- **WebSocket real-time** — persistent connection with auto-reconnect
- **Dark/light theme** — built-in theme support
- **Server config** — customizable WebSocket and API URLs
- **Cross-platform** — iOS, Android, macOS, Windows

## Screenshots

```
┌─────────────┐     ┌─────────────┐
│ 🤖  ✍️      │     │  Chat with  │
│ AI    Writer│  →  │  AI Asst    │
│ 💻  🎨      │     │  Hello!     │
│ Coder Design│     │  Hi there!  │
└─────────────┘     └─────────────┘
  Home Screen         Chat Screen
```

## Quick Start

### Prerequisites
- Flutter SDK 3.x
- 1Claw Server running (see `1claw-server/`)

### Run
```bash
cd claw_app
flutter pub get
flutter run
```

### Build for platforms
```bash
# iOS
flutter build ios

# Android
flutter build apk

# macOS
flutter build macos

# Windows
flutter build windows
```

## Project Structure

```
lib/
├── main.dart                    — Entry point
├── app.dart                     — App with providers
├── config/
│   ├── constants.dart           — Colors, defaults
│   └── theme.dart               — Dark/light themes
├── models/
│   ├── agent_profile.dart       — Profile data model
│   ├── chat_message.dart        — Message model
│   └── ws_message.dart          — WS protocol model
├── services/
│   ├── websocket_service.dart   — WS client + reconnect
│   └── api_service.dart         — REST API client
├── providers/
│   ├── profiles_provider.dart   — Profile state
│   └── chat_provider.dart       — Chat state
├── screens/
│   ├── home_screen.dart         — Card grid
│   ├── chat_screen.dart         — Chat UI
│   └── settings_screen.dart     — Settings
└── widgets/
    ├── agent_card.dart          — Metro card
    ├── chat_bubble.dart         — Message bubble
    └── connection_indicator.dart— Status dot
```

## Architecture

```
Flutter App <-> WebSocket <-> Go Server <-> Hermes Agents
```

## Tech Stack

- **Flutter** — Cross-platform UI
- **Provider** — State management
- **web_socket_channel** — WebSocket client
- **http** — REST API client
