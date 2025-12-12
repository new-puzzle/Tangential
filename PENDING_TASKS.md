# Tangential - Pending Tasks

## Current Status
✅ Gemini Live - Working (multi-turn)
✅ OpenAI Realtime - Working (multi-turn)
⚠️ Standard modes (Deepseek, Mistral, Gemini Flash, GPT-4o) - Working but limited

---

## HIGH PRIORITY

### 1. Long-Term Memory
**Status:** NOT IMPLEMENTED
**Issue:** Conversations are lost when session ends
**Solution needed:**
- Store conversation history in database (`database_service.dart` exists but not wired up)
- Load previous conversations on app start
- Option to continue previous conversation
- Summarize old conversations for context window limits

### 2. Clear Chat Function
**Status:** NOT IMPLEMENTED
**Issue:** No way to start fresh conversation without restarting app
**Solution needed:**
- Add "Clear Chat" button in UI
- Clear conversation history
- Reset AI context
- Maybe confirm dialog before clearing

### 3. Improve Standard Modes (Deepseek, Mistral, etc.)
**Status:** Working but has issues
**Current issues:**
- 15-second max recording time cuts off long questions
- VAD may cut off mid-sentence in noisy environments
**Possible improvements:**
- Increase max recording to 20-30 seconds
- Better silence detection (current: 0.6 seconds)
- Add manual "done speaking" button as alternative to VAD
- Show countdown timer so user knows limit

---

## MEDIUM PRIORITY

### 4. TTS Voice Customization
**Status:** Uses device default voice
**Issue:** Cannot change voice for standard modes
**Solution needed:**
- Add voice selection in Settings
- List available system TTS voices
- Save preference
- Note: Live modes (Gemini/OpenAI) have their own voices (Kore, Alloy)

### 5. System Prompt Customization
**Status:** Hardcoded personality
**Current personality:** Walking companion, tutor, health advisor (see `system_prompt.dart`)
**Solution needed:**
- Add ability to edit system prompt in Settings
- Preset personalities (Tutor, Health Coach, General Assistant, etc.)
- Save custom prompts

---

## LOW PRIORITY

### 6. Conversation History Screen
**Status:** UI exists (`history_screen.dart`) but may not be functional
**Solution needed:**
- Verify history screen works
- Link to database storage
- Allow resuming old conversations

### 7. Background Operation
**Status:** Unknown
**Issue:** App may stop when phone screen off
**Solution needed:**
- Test background audio
- `audio_service` package is included but may need configuration
- Keep-alive for walking use case

### 8. Voice Selection for Live Modes
**Status:** Hardcoded
**Current:** Gemini uses "Kore", OpenAI uses "Alloy"
**Solution needed:**
- Add voice picker in Settings
- Gemini voices: Kore, Puck, Charon, Fenrir, Aoede
- OpenAI voices: alloy, echo, fable, onyx, nova, shimmer

---

## EXISTING SYSTEM PROMPT (for reference)

Located in `lib/services/system_prompt.dart`:

```
You are Tangential, a warm and knowledgeable companion for walks.

ROLES:
- Health & wellness coach
- Scientific tutor
- Mental well-being supporter
- Learning companion
- Personal advisor

STYLE:
- Short responses (2-3 sentences)
- Natural conversation
- Socratic questioning
```

**To customize:** Edit `tangentialSystemPrompt` in `lib/services/system_prompt.dart`

---

## FILES TO REFERENCE

| Feature | File |
|---------|------|
| System Prompt | `lib/services/system_prompt.dart` |
| Conversation Logic | `lib/services/conversation_manager.dart` |
| VAD Settings | `lib/services/conversation_manager.dart` (lines 40-60) |
| TTS Service | `lib/services/tts_service.dart` |
| Database | `lib/storage/database_service.dart` |
| History Screen | `lib/screens/history_screen.dart` |
| Settings Screen | `lib/screens/settings_screen.dart` |

---

## QUICK FIXES (if needed)

### Increase Recording Time Limit
In `conversation_manager.dart`, change:
```dart
static const int _maxRecordingTicks = 75; // 15 seconds
```
To:
```dart
static const int _maxRecordingTicks = 150; // 30 seconds
```

### Change Silence Detection Duration
In `conversation_manager.dart`, change:
```dart
static const int _silenceThreshold = 3; // 0.6 seconds
```
To:
```dart
static const int _silenceThreshold = 5; // 1 second
```

---

*Last updated: December 12, 2025*

