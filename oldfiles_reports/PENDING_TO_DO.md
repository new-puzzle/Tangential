## Native Audio Feature - Status

### ✅ Implementation Complete

| Component | Status | File |
|-----------|--------|------|
| Kotlin AudioCaptureService | ✅ Done | `android/.../AudioCaptureService.kt` |
| Platform Channels in MainActivity | ✅ Done | `android/.../MainActivity.kt` |
| Flutter NativeAudioService | ✅ Done | `lib/services/native_audio_service.dart` |
| Toggle in AppState | ✅ Done | `lib/providers/app_state.dart` |
| Toggle in Settings UI | ✅ Done | `lib/screens/settings_screen.dart` |
| Integration in ConversationManager | ✅ Done | `lib/services/conversation_manager.dart` |
| Linter errors | ✅ None | All clean |

---

## Pending: Manual Testing Required

### Must-do (manual verification)
- [ ] Build and install: `flutter build apk --debug` then install on Android device
- [ ] Settings → Audio → enable **"Use Native Audio (Experimental)"**
- [ ] Test **Gemini Live** (16kHz input): speak 5–10 turns indoors and outdoors
- [ ] Test **OpenAI Realtime** (24kHz input): speak 5–10 turns indoors and outdoors
- [ ] While screen is OFF (pocket mode), verify conversation continues
- [ ] Flip the toggle OFF and confirm behavior matches the old `record`-based path (no regression)

### Nice-to-have / follow-ups
- [ ] Persist toggle across app restarts (currently in-memory only)
- [ ] Consider adding `AutomaticGainControl` explicitly if needed

---

## What Native Audio Does

When toggle is **ON**:
- Uses Android `VOICE_COMMUNICATION` audio source
- Enables hardware `NoiseSuppressor` (filters background noise)
- Enables hardware `AcousticEchoCanceler` (removes AI voice from mic)
- Should work better in noisy outdoor environments

When toggle is **OFF**:
- Uses existing `record` Flutter package (unchanged behavior)
- No noise filtering
- Works well indoors / quiet environments
