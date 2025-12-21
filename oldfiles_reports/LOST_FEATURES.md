# Tangential App - Lost Features & Current State

## What Happened

Over multiple sessions spanning approximately 25+ hours, numerous features were developed but **never committed to git**. On the final session, these uncommitted changes were lost when git operations overwrote local files.

## Features That Were Lost (Never Committed)

### 1. AI Personality System
- Multiple preset personalities (Coach, Friend, Mentor, Scientific Tutor)
- Custom system prompt editor in Settings UI
- User's detailed walking/audio-first system prompt
- Personality selection dropdown

### 2. Voice Selection
- Gemini Live voice selection (was set to "Fenrir")
- OpenAI Realtime voice selection (was set to "Onyx")
- Voice selection dropdowns in Settings UI

### 3. Pocket Mode Improvements
- Enhanced screen off/on handling
- Robust audio streaming continuation
- Better wake lock management
- Testing and tuning for wireless earbuds

### 4. Other Lost Features
- Improved VAD (Voice Activity Detection) tuning for noisy environments
- Better error handling and recovery
- Various bug fixes and refinements
- UI improvements that were working

## Current State (What Exists in Git)

- Basic pocket mode (wake lock + minimal screen callbacks)
- Basic generic system prompt
- SafeArea fix for text box visibility
- Increased audio buffer for playback
- Core conversation functionality (may have issues)

## Pending Tasks (If Continuing)

1. **Pocket Mode** - Needs proper testing and fixes for screen-off operation
2. **System Prompts** - Need to recreate personality presets and custom prompt editor
3. **Voice Selection** - Need to add Gemini/OpenAI voice dropdowns to settings
4. **Audio Quality** - Choppy playback still reported with OpenAI Realtime
5. **Text Input** - Text-only mode needs architectural work
6. **Long-term Memory** - Never implemented
7. **History Playback** - Audio recording storage not implemented

## Lesson Learned

**Always commit and push working code immediately after verification.**

---

*User may choose to delete this app after significant time and effort was lost.*

