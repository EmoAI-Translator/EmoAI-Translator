# Frontend (Flutter)

A cross-platform Flutter application that records audio, sends it to the backend via WebSocket, and displays translated text and tts with detected emotions.

## Platform support
- Android
- Web

## Prerequisites
- Flutter SDK (tested on 3.x)
- Connected device or emulator / web browser

## Setup
```bash
cd frontend
flutter pub get
```

Ensure the backend is running and reachable; default WebSocket URL is `ws://localhost:8000/ws/speech`.

## Running
```bash
flutter run      # choose target device or browser
```

### Debug panel
Tap the menu icon (≡) in the top‑left corner to open configuration overlays. Enable **Show Debug Panel** to view
- current server URL/IP
- connection status
- last sent/received packets
- internal state variables
- **and** change the server URL at runtime (useful when testing against remote hosts). Click "Apply" after editing.

## Code highlights
- `main.dart` – primary UI and WebSocket logic
- `audio_control.dart` – abstraction over platform-specific recording/playback
- `audio_mobile.dart` / `audio_web.dart` – implementations for mobile and web
- `debug_module.dart` – debug overlay widget

## Architecture diagrams
Several PlantUML diagrams are included to illustrate system structure and interactions. You can view them with any PlantUML-compatible tool.

- `communication.puml` high-level component interaction between frontend and backend
- `sequence.puml` message flow for a typical speech/translation exchange
- `Structure.puml` shows project/module layout and dependencies

## Customization
- Languages, emotion colors, and UI layout can be adjusted in `main.dart`.
- WebSocket logic is encapsulated; you can point to any compatible backend by changing `wsUrl` or via the debug panel.

## Notes
- The app auto‑stops recording after a few seconds of silence.
- Translated text appears per speaker side; emotions color the message bubbles.

Feel free to experiment, file issues, or contribute improvements!