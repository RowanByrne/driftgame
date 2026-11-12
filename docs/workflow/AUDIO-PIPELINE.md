# Audio pipeline

How sound effects, music, ambience and voice get found or made, approved and into the game. The user sets the sound direction in `docs/game/AUDIO.md` and picks every sound; the agent finds or generates candidates, records them, uploads them and wires them in. It works like the art pipeline (`ART-PIPELINE.md`).

## Where audio lives

| What | Where | In git |
|---|---|---|
| Every candidate, found or generated | `..\art\generated\<topic>\` | No |
| Working files: DAW projects, stems, long recordings, masters over 5 MB | `..\art\source\<topic>\` | No |
| Approved masters, up to 5 MB a file | `assets/audio/<topic>/` | Yes |
| The record: source, license, prompt, hash, status, asset id | `assets/audio/<topic>/MANIFEST.md` | Yes |
| The sound direction, every sound in the game, and credits | `docs/game/AUDIO.md` | Yes |

A topic is named for its role, like `sfx-sword`, `ui-clicks`, `music-lobby` or `amb-forest`.

## Where sounds come from

Try them in this order. Checked October 2026: terms change, so read a source's license page before using it for the first time, and update this doc when something has moved.

### 1. The Creator Store

Over 100,000 licensed sound effects and music tracks from Roblox's audio partners (APM, Pro Sound Effects, Monstercat, DistroKid and others), free in any experience, with nothing to upload. The `asset-scout` agent finds them.
- Store music is for use on Roblox only.
- A track that's delisted or taken off sale can't be added to new experiences; one already in the game keeps working.
- Groups can't acquire Store audio: use it by id.

### 2. Free libraries that allow games

Uploaded as the game's own audio (Making a sound, step 5).

| Source | License | Use it for |
|---|---|---|
| Kenney (kenney.nl) | CC0 | Anything |
| Freesound (freesound.org) | Set per sound: CC0, CC BY or CC BY-NC | CC0 sounds, or CC BY with a credit. Never BY-NC |
| Sonniss GDC bundles (sonniss.com/gameaudiogdc) | Royalty-free, no credit | High-quality effects. Never share the files themselves |
| OpenGameArt (opengameart.org) | Set per file | CC0 or OGA-BY only |
| ZapSplat (zapsplat.com) | Free tier needs a credit; paid needs none | Effects |
| Incompetech (incompetech.com) | CC BY, or a paid license without credit | Music, with a credit |

**Not for games:** BBC Sound Effects (personal and educational use only), the YouTube Audio Library (licensed for videos), Mixkit's music (its license excludes video games), anything marked NC (non-commercial), and any commercial song.

### 3. Generated with AI

The audio tools in `MODELS.md` make sounds to the brief. What each can do, as of October 2026:

| Tool | Makes | How the agent uses it | Rights |
|---|---|---|---|
| ElevenLabs Sound Effects | Effects from 0.1 to 30 s, including seamless loops | API, or ElevenLabs' MCP server | Commercial use from the paid Starter plan; the free plan has none |
| ElevenLabs Music | Music up to 5 minutes, instrumental or with vocals | API, on paid plans | Self-serve plans cover indie games (its music terms set revenue limits); read them before the first track |
| Stable Audio 3.0 | Effects, and music up to about 6 minutes | API, or the open models run on the PC | Commercial use while revenue is under $1M a year; trained on licensed audio |
| Adobe Firefly (Generate Music, Generate Sound Effects) | Instrumental music and effects | No API: the user makes them in the browser, then the agent takes over from step 2 | Sold as commercially safe |

**Avoid:**
- **Suno.** Lawsuits are pending, and Roblox's copyright filter has blocked Suno tracks. A blocked file stays blocked.
- **Udio.** Downloads are switched off.
- **Meta's MusicGen and AudioGen.** The model weights are non-commercial.
- **Google Lyria.** The Gemini API terms bar products likely to be used by under-18s. Ask the user before using it for a Roblox game.

### 4. Voice

- **Text-to-speech in game:** Roblox's `AudioTextToSpeech` speaks lines live (English voices, up to 300 characters a line).
- **Text-to-speech as a file:** Open Cloud's `GenerateSpeechAsset` makes an audio asset, and it counts toward the upload limit.
- **Character voices:** ElevenLabs' voices, on a plan with commercial use.

Recorded voices need the speaker's written OK, kept with the manifest.

## Making a sound

1. **Brief.** What it's for, when it plays, how long it is, one-shot or loop, in the world (3D) or not (UI and music), and the style from `docs/game/AUDIO.md`.
2. **Candidates.** Make 2 to 4 per brief: Creator Store ids from `asset-scout`, library files, or generated ones. Build every generation prompt from the game's pillars and the section of `docs/game/AUDIO.md` for that kind of sound. Save files in `..\art\generated\<topic>\`. Log each one in the topic's manifest:
   - the file, or the Store id;
   - where it came from, and its license; for a generated one, the tool, the plan, and the exact prompt;
   - its SHA-256;
   - status `candidate`.
3. **Show the user.** Ask in Rocco's Workboard with every candidate as an option the user can play:

   ```
   ..\..\_tools\rocco\rocco.ps1 ask T-012 -Question "Pick the sword swing" -Options "Short whoosh","Blade swing" -Audio a.ogg,b.ogg
   ```

   That's in PowerShell from `repo\`; from a lane it's `..\..\..\_tools\rocco\rocco.ps1`. See Rocco's README (`..\..\_tools\rocco\README.md`, "Commands"). Without Rocco, list the files for the user to play. **Never use a sound the user hasn't picked.** Record the pick, and the user's words, in the manifest.
4. **Approve.** Copy the picked file **unchanged** into `assets/audio/<topic>/`; a master over 5 MB stays in `..\art\source\<topic>\`. Its status becomes `approved`; the others become `rejected`. A Creator Store pick has no file: record its id.
5. **Upload.** Uploading is the agent's job: never ask the user to upload a file. Use the Studio MCP's `open_cloud_invoke`, which runs as the user signed in to Studio and needs no API key:
   - **The call:** `POST /assets/v1/assets`, scopes `asset:read` and `asset:write`, the file as `fileContent`, and `request` as `{ assetType: "Audio", displayName, description, creationContext: { creator: { userId } } }` (`groupId` for a group). It returns an operation: ask `GET /assets/v1/operations/{id}` until `done`; the asset id is in its `response`.
   - **The creator:** the owner in PROJECT.md. Until that's filled in, the user signed in to Studio (`StudioService:GetUserId()` in the Edit datamodel), and record who uploaded it (ART-PIPELINE.md "Ownership and permissions").
   - **When it's refused:** make the same call to `https://apis.roblox.com` with `ROBLOX_API_KEY` (RELEASING.md "Roblox Open Cloud"). If that's refused too, or there's no key, ask the user only for the missing permission (WORKSTATION.md "Setting up a PC", step 2), then upload it yourself.
   - **Files:** .ogg, .mp3, .wav or .flac, under 20 MB and 7 minutes, 48 kHz or lower.
   - **Limit:** uploads are free, up to 2,000 per 30 days on an ID-verified account (100 without).
   - **Moderation:** every upload is checked, copyright included. Only the uploader hears it until it passes.
   - **Privacy:** new audio is private. Grant it to this experience only (ART-PIPELINE.md "Ownership and permissions"). Never make library or generated sounds public: several licenses forbid sharing the files.

   Record the asset id in the manifest.
6. **Wire it in.** Put the id in the sounds registry (CODING.md), never scattered through scripts, at the level the mix in `docs/game/AUDIO.md` sets. Check it in a playtest with sound on (TESTING.md, `__studio_audio`): it plays when it should, loops without a click, and sits right against the music and the other sounds.
7. **Commit** the master, its manifest, the registry change, and the sound's row in `docs/game/AUDIO.md` together.

## Getting it right

- **Mono for sounds in the world, stereo for music and UI.** A sound placed in the world plays from one point anyway.
- **Loops:** cut at a zero crossing so the end meets the start, then turn looping on. To loop only part of a file, such as after an intro, use `AudioPlayer.LoopRegion`.
- **Loudness:** Roblox sets no target. Keep the masters at a similar loudness, then set each sound's level in the game rather than re-exporting it.
- **Variations:** a sound that repeats a lot, like footsteps, hits or coins, gets 2 to 4 variations, picked at random or with a small pitch shift.

## Rules

- **The direction is the user's.** The agent proposes pillars, references and styles; the user decides them.
- **Every sound has a record:** where it came from and its license, and for generated audio the tool, plan and exact prompt. A sound without a record doesn't ship.
- **Generated audio needs a plan that allows commercial use**, on the account that made it. Most free plans don't.
- **No one else's music.** Never name a real song, artist or game in a generation prompt. Uploads are fingerprinted: a match blocks the upload, and a takedown claim can strike the account (PLATFORM-RISKS.md).
- **Credits:** a sound whose license asks for one gets a line in `docs/game/AUDIO.md` "Credits", and the game shows it, in a credits screen or on the game page.
- **Never invent an asset id.**
- **API keys stay on the PC,** in its environment, never in the repo. ElevenLabs is linked in Rocco's Connections, which keeps the key as `ELEVENLABS_API_KEY`.
- **If a tool can't run on this PC, say so.** Don't switch to a source the user hasn't approved.
