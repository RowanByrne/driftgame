# Workstation

Where the projects live, and how to set up a PC to work on them.

## The RoDev folder

Every game sits in one **RoDev folder**, next to the template and the shared tools:

```
RoDev\
  _tools\      tools every game shares (Lync)
  template\    the template; duplicate it to start a game (NEW-PROJECT.md)
  <Game>\      one folder per game (CLAUDE.md "Project layout")
```

The RoDev folder can live anywhere: in your user folder (`C:\Users\<you>\RoDev`), on a second drive, or on a portable drive carried between PCs. Everything in the template uses paths relative to it, so it can move.

- **Not in a synced folder.** Don't put it anywhere OneDrive, Dropbox or Google Drive syncs; Windows often syncs Desktop and Documents to OneDrive. Sync tools lock and copy files while git and Studio are writing them, which can corrupt the repo and place files. Back up by copying instead ("Backups").
- **Quote paths.** A user folder's name can contain spaces, so quote paths in commands and scripts.
- **On a portable drive**, also read "On a portable drive" below.

## Setting up a PC (once)

1. **Install:**
   - **Git for Windows**, 2.48 or newer (`git --version`), for relative lane paths. Its credential manager asks you to sign in to GitHub on the first push.
   - **Roblox Studio**, signed in as an account that can edit the game (or its group).
   - **The Claude desktop app.**
   - **The tools in `MODELS.md`** that the game uses: the Codex desktop app, signed in, for the image tool; Blender with the Blender MCP for 3D assets; the audio tool's API key, set as a user environment variable (never in the repo); for ElevenLabs, link it in Rocco's Connections.
2. **Register the Roblox Studio MCP in Claude Code as `Roblox_Studio`** (its key under `mcpServers` in `%USERPROFILE%\.claude.json`), then quit and reopen the Claude app. The agent files allow Studio tools by that exact name; under any other name, workers get none.
3. **Lync:** put `lync.exe` in `RoDev\_tools\lync\`, once per RoDev folder. Every game in it uses that copy (`tools\serve.bat` looks there first, then on PATH). Its Studio plugin installs itself on the first serve; restart Studio after.
4. **Lanes for this PC:** the first time this PC works on a game, it gets a row in that game's `PROJECT.md` "Workstations": how many lanes it opens, measured or picked by the user (LANES.md "How many lanes").

## Starting a session

1. **Open Claude** in `<Game>\repo`.
2. **Say "refresh"** to sync with GitHub (CONDUCTOR.md).
3. **Start Lync** (`tools\serve-all.bat`) and open the Main place and this PC's lane places (`PROJECT.md` "Workstations") from `<Game>\places\`.

## Before you stop

1. **Studio:** stop any playtest, save every place, and close Studio, so the place files are fully written.
2. **Lync:** close the server windows.
3. **Git:** commit and push (say "refresh"). Nothing that belongs in git should exist only in the RoDev folder.

## On a portable drive

- **The letter can change between PCs.** That's fine; optionally give the drive the same letter on every PC (Disk Management, Change Drive Letter and Paths), so Studio's recent files and git's trusted paths stay the same.
- **Trust the drive in git.** Git may refuse files created on another PC ("detected dubious ownership"). Run the command it prints, or trust the whole folder once per letter: `git config --global --add safe.directory "<letter>:/RoDev/*"`.
- **After a letter change**, Studio's recent list may point at the old letter: open places from `<Game>\places\`.
- **Eject before unplugging** (Safely Remove Hardware), after "Before you stop". Pulling it mid-write can corrupt a place file or the repo.

## Backups

- **GitHub has everything in git:** code, docs, live records, approved art.
- **Everything else is only in the RoDev folder:** each game's `places\`, `art\` and `backups\`, and `_tools\`. Copy them somewhere else (another drive, or cloud storage as a copy rather than a live-synced folder) regularly, and always before risky work. Losing the folder, or the drive it's on, loses whatever was never copied.
- **`backups\` sits next to the game.** It protects against mistakes, not against losing the folder.
- **Claude's memory lives on each PC,** and also depends on the folder's path. Anything lasting goes in the repo (CLAUDE.md "Workstations").

## When something's wrong

| Problem | Fix |
|---|---|
| Git says "detected dubious ownership" | Run the `git config --global --add safe.directory ...` command it prints |
| Git reports a lane missing after the project folder moved | `git worktree repair` from `repo\` |
| Workers have no Studio tools | The Studio MCP isn't registered as `Roblox_Studio` (setup step 2) |
| A place doesn't update from Lync | Click **Resume** in Studio's Lync plugin; then probe the lane (LANES.md) |
| The image tool fails | The Codex app isn't installed or signed in on this PC. Say so; don't substitute (ART-PIPELINE.md) |
