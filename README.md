# OpenGlasses

Voice-powered AI assistant for Ray-Ban Meta smart glasses using Claude AI and on-device wake word detection.

## Overview

OpenGlasses transforms your Ray-Ban Meta smart glasses into a hands-free AI assistant. Say "Hey Claude" to activate voice recognition, ask questions, and receive responses directly through your glasses' speakers. Built with SwiftUI and leveraging Meta's Wearables SDK, this app provides a seamless AR-enhanced experience.

## Features

### Core Capabilities
- **Wake Word Detection**: On-device "Hey Claude" activation using custom wake word model
- **Voice Transcription**: Speech-to-text powered by Apple's Speech framework
- **Multi-Provider LLM Support**: Switch between Anthropic Claude, OpenAI GPT, Google Gemini, Groq, and custom OpenAI-compatible APIs
- **Location Context**: GPS-based location automatically included in prompts for locally relevant answers
- **Audio Playback**: Natural-sounding responses via text-to-speech through glasses speakers
- **Camera Integration**: Voice-activated photo capture ("take a picture")
- **Background Operation**: Wake word detection continues while app is backgrounded

### Voice Commands
- **"Hey Claude"** - Activate the assistant
- **"Stop" / "Cancel"** - Interrupt playback, continue conversation
- **"Goodbye" / "Thanks Claude"** - End conversation, return to wake word mode
- **"Take a picture"** - Capture photo from glasses camera

### Smart Conversation Flow
- Automatic conversation continuation after responses
- Silence timeout detection to end natural conversations
- Background audio session management for uninterrupted operation

## Requirements

- iOS 26.0+ (iOS 18.0+ technically, configured for 26)
- Xcode 16.0+
- Ray-Ban Meta smart glasses (paired via Meta View app)
- Anthropic API key ([get one here](https://console.anthropic.com/))
- Meta Developer account for Wearables SDK access

## Installation

### 1. Clone the Repository

```bash
git clone https://github.com/straff2002/OpenGlasses.git
cd OpenGlasses
```

### 2. Configure API Keys

Edit `OpenGlasses/Sources/Utils/Config.swift`:

```swift
struct Config {
    static let anthropicAPIKey = "YOUR_ANTHROPIC_API_KEY_HERE"
}
```

### 3. Set Up Meta Wearables SDK

Use your own Meta app credentials and keep all identifiers aligned.

#### Meta Setup Values (copy/paste template)

Replace the placeholders below with your own values:

```text
TEAM_ID=<YOUR_APPLE_TEAM_ID>
BUNDLE_ID=<YOUR_UNIQUE_BUNDLE_ID>
META_APP_ID=<YOUR_META_APP_ID>
CLIENT_TOKEN=<YOUR_META_CLIENT_TOKEN>
UNIVERSAL_LINK=https://<YOUR_DOMAIN>/<YOUR_PATH>

URL_SCHEME=mwdat-${META_APP_ID}
AASA_APP_ID=${TEAM_ID}.${BUNDLE_ID}
```

#### Where each value goes

1. **Meta dashboard (iOS app details)**
  - Team ID → `TEAM_ID`
  - Bundle ID → `BUNDLE_ID`
  - Universal Link → `UNIVERSAL_LINK`

2. **`project.yml`**
  - `settings.base.PRODUCT_BUNDLE_IDENTIFIER` → `BUNDLE_ID`
  - `info.properties.MWDAT.MetaAppID` → `META_APP_ID`
  - `info.properties.MWDAT.ClientToken` → `CLIENT_TOKEN`
  - `info.properties.MWDAT.TeamID` → `$(DEVELOPMENT_TEAM)` (or `TEAM_ID`)
  - `info.properties.MWDAT.AppLinkURLScheme` → `URL_SCHEME`
  - `info.properties.CFBundleURLTypes[].CFBundleURLSchemes[]` → `URL_SCHEME`

3. **Xcode Signing**
  - Target → Signing & Capabilities → Team = `TEAM_ID`
  - Bundle Identifier = `BUNDLE_ID` (Debug + Release)

4. **Universal Links (`.well-known/apple-app-site-association`)**
  - `applinks.details[].appID` → `AASA_APP_ID`

5. **`OpenGlasses/Info.plist` (generated/final check)**
  - `MWDAT.MetaAppID` = `META_APP_ID`
  - `MWDAT.ClientToken` = `CLIENT_TOKEN`
  - `MWDAT.TeamID` = `TEAM_ID` (or resolves from `$(DEVELOPMENT_TEAM)`)
  - `MWDAT.AppLinkURLScheme` = `URL_SCHEME`
  - `CFBundleURLSchemes` contains `URL_SCHEME`

#### Notes
- Bundle IDs must be globally unique in Apple Developer (for example, add a suffix like `.skunk0`).
- If Meta Wearables is running in Developer Mode for local testing, Meta may not require full app-review configuration.
- If auth loops at registration state 1→2, one or more values above are usually misaligned.

### 4. Build and Run

```bash
# Open in Xcode
open OpenGlasses.xcodeproj

# Or use Swift Package Manager
swift build
```

**Note**: First launch will trigger Meta AI app for glasses pairing authorization.

## Project Structure

```
OpenGlasses/
├── Sources/
│   ├── App/
│   │   ├── OpenGlassesApp.swift    # Main app entry & state management
│   │   └── ContentView.swift        # SwiftUI interface
│   ├── Services/
│   │   ├── ClaudeAPIService.swift   # Anthropic API integration
│   │   ├── GlassesConnectionService.swift  # Meta SDK connection
│   │   ├── WakeWordService.swift    # Wake word detection
│   │   ├── TranscriptionService.swift  # Apple Speech integration
│   │   ├── TextToSpeechService.swift   # Audio playback
│   │   └── CameraService.swift      # Photo capture
│   ├── Utils/
│   │   └── Config.swift             # API keys & configuration
│   └── Resources/
│       └── (audio assets)
├── Package.swift                     # Swift Package Manager config
├── project.yml                       # XcodeGen project definition
└── README.md
```

## Architecture

### Audio Pipeline
1. **Wake Word Detection**: Continuous background monitoring using on-device ML
2. **Speech Recognition**: Apple Speech framework transcribes audio
3. **API Communication**: Transcribed text sent to Claude API
4. **Response Synthesis**: Text-to-speech converts Claude's response
5. **Audio Routing**: Playback through glasses speakers via Bluetooth

### State Management
- `AppState` manages conversation flow and service coordination
- Services communicate via closures/callbacks to maintain loose coupling
- Shared audio engine between wake word and transcription for efficiency

### Background Operation
- Audio session configured for background playback
- Wake word listener persists when app is backgrounded
- Automatic recovery when returning to foreground

## Dependencies

Managed via Swift Package Manager:

- **meta-wearables-dat-ios** (0.4.0+) - Meta's Device Access Toolkit
  - MWDATCore - Device connection & communication
  - MWDATCamera - Camera access

## Configuration Details

### Info.plist Permissions
- `NSMicrophoneUsageDescription` - Wake word & voice commands
- `NSSpeechRecognitionUsageDescription` - Transcription
- `NSPhotoLibraryAddUsageDescription` - Photo saving
- `NSBluetoothAlwaysUsageDescription` - Glasses connection

### Background Modes
- `audio` - Keep audio session active
- `bluetooth-central` - Maintain BLE connection

### Bundle Configuration
- Bundle ID: `com.openglasses.OpenGlasses.skunk0`
- Display Name: OpenGlasses
- Version: 1.2 (Build 3)

## Usage

### First Time Setup
1. Launch app on iPhone
2. Allow microphone and Bluetooth permissions
3. Meta AI app will open for glasses authorization
4. Return to OpenGlasses - connection auto-establishes

### Daily Use
1. Wear your Ray-Ban Meta glasses
2. Launch OpenGlasses (auto-connects in background)
3. Say "Hey Claude" to activate
4. Ask your question naturally
5. Hear response through glasses
6. Continue conversation or say "goodbye"

### Troubleshooting
- **Wake word not detecting**: Tap "Test Microphone" to restart listener
- **No audio through glasses**: Check Bluetooth routing in iOS settings
- **Connection issues**: Press "Connect to Glasses" to re-authorize
- **"Internal error" when connecting**: You need to enable Developer Mode in the Meta AI app. Go to Meta AI → Settings → About → tap the version number **5 times** → toggle Developer Mode on. This is required for all third-party MWDAT apps.

## Development Notes

### Key Implementation Details
- Wake word model runs continuously at low CPU cost
- Transcription triggered only after wake word detection
- Audio engine shared between services to prevent route conflicts
- Conversation state prevents rapid wake word re-triggering
- Silence detection after responses enables natural turn-taking

### Future Enhancements
- [ ] Custom wake word training
- [ ] Multi-turn conversation context
- [ ] Vision API integration for image analysis
- [ ] Offline Claude caching
- [ ] Custom TTS voice selection
- [ ] Gesture controls via glasses sensors

## Contributing

This is a Skunk0 project from Skunkworks NZ. Feel free to fork and adapt for your own use.

## License

MIT License - see LICENSE file for details

## Credits

Built by [Skunk0](https://github.com/straff2002) at Skunkworks NZ

Powered by:
- [Anthropic Claude](https://www.anthropic.com/) - AI Assistant
- [Meta Wearables SDK](https://developers.facebook.com/docs/wearables/) - Glasses Integration
- [Apple Speech Framework](https://developer.apple.com/documentation/speech) - Speech Recognition

---

**Note**: This is an independent project and is not affiliated with Meta or Anthropic.
