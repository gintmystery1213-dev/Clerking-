# CLER — Clinical Reasoning Simulator (Flutter)

Native **Android & iOS** app for offline clinical history-taking practice.

Port of the original Cloudflare Worker **ClerkAI / CLER** engine (zero-LLM, rule-based).

## Features

- 27 paediatric cases bundled offline
- Text normalisation (Nigerian pidgin, medical abbreviations, typos)
- Intent matching + clustering
- Patient personality / temperament
- Danger traps & penalties
- Hidden facts unlock
- Teaching pearls after scored intents
- Session scoring & must-ask checklist

## Requirements

- Flutter 3.16+ (stable)
- Android Studio / Xcode for device builds

## Setup (first time)

Platform folders need a one-time Flutter scaffold (keeps your `lib/` and `assets/`):

```bash
cd cler_app
flutter create . --project-name cler_app --org com.cler.app
flutter pub get
```

## Run

```bash
flutter run                 # Android / iOS device or emulator
flutter run -d chrome       # optional quick web check
```

### Android

```bash
flutter run -d android
# or release:
flutter build apk --release
flutter build appbundle --release
```

### iOS

```bash
flutter run -d ios
flutter build ipa
```

## Project structure

```
lib/
  core/
    engine.dart          # Pure reasoning engine (normalise, match, score)
    intent_patterns.dart # 63 intent patterns
  models/
  services/
    case_repository.dart # Loads cases from assets
    session_controller.dart
  screens/
    home_screen.dart
    case_list_screen.dart
    chat_screen.dart
    results_screen.dart
  main.dart
assets/knowledge/
  cases/peds_cases.json
  peds_knowledge_bank.json
```

## How chat works

1. Student types a question.
2. `processChat()` normalises text → checks danger → consistency → clusters → hidden facts → intent classification.
3. Matching intent returns `patient_text` (scoped for closed/open questions) + optional pearl + score.
4. Session tracks asked intents and total points.

## Notes

- Fully offline; no network required for core simulation.
- Original Worker also had Supabase + Cloudflare KV admin endpoints; those are not needed for the mobile offline experience.
- Add more disciplines by placing extra JSON under `assets/knowledge/cases/` and registering them in `pubspec.yaml`.


## Worker + Supabase connection

The app talks to:

| Service | Role |
|---------|------|
| **Cloudflare Worker** | `/cases`, `/chat`, `/scores`, `/leaderboard`, `/get-answer`, `/ask-question` |
| **Supabase** | Edge functions `get-answer` / `ask-question`; optional `scores` REST table |
| **On-device engine** | Full offline fallback (same rule engine) |

### Modes (Settings)

- **Auto** — Worker when reachable, else local engine  
- **Online** — always Worker (errors fall back to local)  
- **Offline** — never call network  

### Configure

1. Open **Worker & Supabase settings** on the home screen.  
2. Set your real Worker URL, e.g. `https://bigclerk.<your-subdomain>.workers.dev`  
3. Supabase URL + anon key are pre-filled from the original `wrangler.jsonc`.  
4. Tap **Test connection**.

Default credentials in code match the project’s public anon key and Supabase project.  
Replace the Worker URL with your deployed endpoint before production use.

### Score sync

On session end the app POSTs to Worker `/scores` and attempts Supabase REST `scores` (ignored if the table/RLS is missing).


## Vector embeddings

Matching uses a **hybrid**:

1. **Lexical / soft match** — phrases, keywords, synonyms, n-grams  
2. **LSA vectors** (offline) — TF–IDF projected with Truncated SVD into a dense space; query and intents use the same projection; ranked by cosine similarity  
3. **Neural vectors** (all-MiniLM-L6-v2, 384-d) — precomputed per intent in `assets/knowledge/intent_embeddings.json` for online / future on-device MiniLM

Clerks get **no question chips and no examiner mark-sheet leaks** — only patient answers.



## Live backends (already deployed)

| Service | Default in app |
|---------|----------------|
| Cloudflare Worker | `https://bigclerk.workers.dev` (override in Settings if your workers.dev URL differs) |
| Supabase project | `https://wxmgtugqiisnojqbezby.supabase.co` |
| Client key | Supabase **anon** JWT only |

Chat path: **local engine → Worker `/get-answer` (reply_bank) → Worker `/ask-question` (queue)**.  
Optional: enable “prefer online engine” to use Worker `/chat` first when online.

Configure under **Settings**; use **Test connection** to verify Worker + Supabase.

## On-device neural encoder (small + fast)

Asset: `assets/knowledge/models/minilm_static_96.zlib` (~230KB).

| Property | Value |
|----------|--------|
| Teacher | `paraphrase-MiniLM-L3-v2` (smallest MiniLM family) |
| Student | Static token table → mean pool → 96-d |
| Compression | PCA 384→96 + int8 quantize + zlib |
| Runtime | Pure Dart (no ONNX/TFLite binary) |
| Latency | Sub-millisecond on modern phones |

This is the practical size/quality tradeoff for offline clerking. Full transformer MiniLM (~20–80MB ONNX) can replace the student later if needed.


## Engine architecture (Phases 1–6)

| Phase | Module | Role |
|-------|--------|------|
| 0 | `case_schema.dart` | Validate case packs before run |
| 1 | `move_decision.dart` | Fuse **keyword + soft + vector** sensors |
| 2 | `ontology.dart` | Clinical phase + speech act |
| 3 | `dialogue_state.dart` | Topic stack, slots, findings, tests |
| 4 | `scorer.dart` + `safety.dart` | Deterministic points + danger |
| 5 | `quality_loop.dart` + `miss_log.dart` | Fixtures + unmatched mining |
| 6 | `on_device_encoder.dart` | Compact MiniLM-static vectors |

Keywords and similarity are **sensors**. `resolveMove()` is the decision layer.


## CI / GitHub Actions

Workflow: `.github/workflows/build.yml`

On push/PR to `main`: analyze, test, `flutter build apk --release`, upload APK artifact.
Optional iOS no-codesign build on macOS (main / manual dispatch).
If platform folders are missing, CI runs `flutter create .` without overwriting `lib/`.
