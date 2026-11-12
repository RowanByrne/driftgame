# Feature: Admin console

**Status:** built (`T-159`, branch `agent/cmdr`). **Owner task:** `T-159`.

## Goal

The user, 2026-11-12: *"yes add cmdr and add a ton of useful debug commands"*. The kit's admin console (docs/workflow/CODING.md "Foundation kit"): Cmdr, vendored, with commands for driving and testing this game, so a tester or an agent gets to any place, time of day or state in one line instead of a drive or a bridge call.

## How it plays

1. **F2** opens and closes the console (Cmdr's default). It opens at the top of the screen with the text box focused; `help` lists every command by group, `help <command>` explains one, and Tab completes names and arguments.
2. Commands answer in the window. A refused or failed command says why in a line ("Not moved: ...", "You're not in a run.").
3. A player who isn't allowed never sees the window: F2 does nothing for them. If their client is tampered with to show it, every command is refused.

## Who can use it

- **In Studio:** everyone.
- **On a live server:** the game's owner (the user who owns it, or the owner, rank 255, of the group that owns it) and the user ids in `Config.Admin.UserIds` (`Shared/Config/Admin.luau`, empty to start). Only they can aim a command at another player.
- **Decided on the server, for every command:** `CmdrService`'s BeforeRun hook. The `CmdrAdmin` player attribute only tells the client whether to show the window; it grants nothing. Commands that act only on the player's own screen (the sky, the score panel, the readout, the camera) run on the client behind the same answer, which is all a client can be held to.
- **Rate-limited per UserId,** kept across rejoins: `Config.Admin.PerSecond` (8) commands a second and `PerMinute` (120) a minute. Past that: "Slow down: too many commands."

## Commands

Every command is open to whoever can use the console (above); there are no levels inside it.

**Targets (the user, 2026-11-12: "it should be `tp [playername] [location]`").** A command that acts on players takes them first, with Cmdr's `players` type: a name (or the start of one; Tab completes), `me` or `.`, `all` or `*`, `others` or `**`, or a comma list. Acting on another player is the same admin-only command, through the same server check and rate limit.
- **Required** (`<players>`) where more arguments follow that you'd always type: `tp`, `tp-to`, `car`, `score-set`. So `tp me road`, `tp Alex garage`, `car all slider`. Cmdr reads arguments in order, so an optional first argument followed by a required one can't be skipped.
- **Optional, defaulting to you** (`[players]`) where the targets are the only argument, or everything after them is optional: `respawn`, `start-run`, `end-run`, `unstuck`, `garage-out`, `get-out`, `get-in`, `speed`, `score-reset`. So `respawn` alone respawns you; `respawn all` respawns everyone. With a second argument the target has to be there: `speed me 90`, `start-run me 555`.
- **One player, optional** (`[player]`) for reading: `where`, `run-info`, `whoami`.
- **Your own screen only, no target:** `time`, `time-pause`, `time-resume`, `time-speed`, `readout`, `trajectory`, `zoom`, `horizon`, `score` (reading), `counts`, `stats`. They change or read one client's view, and reaching another player's screen for a look isn't worth a round trip.
- **The whole server, no target:** `seed`, `road-mode`, `barriers`.

"Client" below means the player's own client does it: your own when you target only yourself; otherwise the server sends each target's client a `DriftAction` and replies "Sent ... to names" (the effect shows on their screen).

| Group | Command (aliases) | What it does | Runs on |
|---|---|---|---|
| Run | `start-run [players] [seed]` (`startrun`) | Starts runs as the start button does (everyone joins the one road); with a seed, lays that road first (only when no road is up) | Server |
| Run | `end-run [players]` (`endrun`) | Ends runs, each back to the world they came from | Server |
| Run | `run-info [player]` (`runinfo`) | Road up or not, seed, mode, drivers, the player's piece and distance | Server |
| Run | `seed [n]` | Shows the seed; with `n`, lays the road again from that seed and puts everyone who was on it back at its start (no road up: starts one for you) | Server |
| Run | `road-mode [spline\|pieces]` (`roadmode`) | Shows or sets the next run's road; only between runs | Server |
| Run | `respawn [players]` | Puts cars back now, no cooldown: on the road in a run (never behind the closing barrier), else the world's spawn | Server |
| Teleport | `tp <players> <place> [studs]` | `road` joins the run or puts them back on it; `road <studs>` goes that far along the spline road (**Studio only**); `playground`, `track`, `garage` (drives in), `hill` (the test hill's top), any playground spot by name (`Spawn`, `OpenGround`, `PillarRun`, `DistrictGate`, `Boulevard`, `TightAlley`, `CircleCentre`, `RampBase`, `HillBase`, `HillTop`), or **another player's name** (beside their car; on their road if they're in a run). Leaving the road ends that player's run first | Server |
| Teleport | `tp-to <players> <x> <y> <z> [heading]` (`tpto`) | Puts cars at a point, facing a heading in degrees (0 faces -Z) | Server |
| Teleport | `where [player]` | Where the server believes a car is: point, world, piece and distance along the road | Server |
| Teleport | `unstuck [players]` (`flip`) | Rights cars where they are: stopped, level, 2 studs up. Yours keeps the heading your screen shows; anyone else's faces along the road in a run, otherwise -Z (the server doesn't know which way their car points) | Server (your pose from your client) |
| Teleport | `garage-out [players]` (`garageout`) | Drives out of the garage, as Drive out does | Server |
| Car | `car <players> [archetype]` | Switches archetype as the car button does; with none, lists the cars and who's in which | Server |
| Car | `get-out [players]` (`getout`) / `get-in [players]` (`getin`) | Out of / back into the car, through the same requests as the button and the prompt (the server can refuse: too fast, not near the door, still getting out) | Client, asks the server |
| Car | `speed [players] [studs/s]` | With no speed, shows your own; with one, sets it along each nose (-1000 to 1000) | Client |
| Car | `readout` | Toggles the debug readout (F3 does the same) | Your client |
| Car | `trajectory [on\|off]` | Toggles the projected line | Your client |
| Car | `zoom <notches>` | Zooms the car camera like the scroll wheel (+ nearer) | Your client |
| Score | `score` | Your score, multiplier, bar, best, in a run or not | Your client |
| Score | `score-set <players> <points> [multiplier]` (`scoreset`) | Sets the score and the rung | Client |
| Score | `score-reset [players]` (`scorereset`) | Back to 0 and x1, as a new run does | Client |
| Time | `time [when]` | Holds your sky at `noon`, `sunset`, `night`, `sunrise`, any keyframe by name (`morning`, `afternoon`, `golden-hour`, `dusk`, `dawn`), `midnight`, or an hour 0-24; with nothing, says where the cycle is | Your client |
| Time | `time-pause` / `time-resume` (`timepause`, `timeresume`) | Stops your sky where it is / puts it back on the server's clock | Your client |
| Time | `time-speed <times>` (`timespeed`) | Runs your cycle 0.1 to 100 times as fast | Your client |
| World | `horizon [on\|off]` | Shows or hides the run's mountains (only up on the spline road) | Your client |
| World | `barriers [on\|off]` | Guardrails down or up for everyone: the test hill's and the piece road's | Server |
| World | `counts` | Parts, mesh parts, models and instances, on your client and the server (and the server's biggest folders) | Both |
| World | `stats` | Your fps, worst frame, memory, ping, bandwidth; the server's heartbeat, physics, memory, uptime | Both |
| Admin | `whoami [player]` | Whether the server lets a player in, and why | Server |

**Cmdr's own commands kept:** `help`, its utilities (`alias`, `bind`, `run`, `history`, `echo`, `var`, `math`, `clear`...) and its debug group (`version`, `uptime`, `position`, `get-player-place-instance`). **Left out:** its admin group (`kick`, `ban`, `kill`, `teleport`, `respawn`...: they act on characters and Roblox's ban API, and this game's driver sits in a car), `fetch` (the server calling any URL), and `blink` and `thru` (they move the character off its seat).

## Left out

- **Gamepad and touch.** Only F2 opens it. Cmdr has no gamepad or touch way in, and a button for it would be new UI.
- **Server-wide time.** `time` and its friends change only your own sky: every client works the cycle out from the server's clock and nothing is sent. A server-wide time would need a replicated offset in `SkyController`.
- **`tp road <studs>` on a live server.** It reads the road's live generator and moves the window with `RoadService:DebugGenerator` and `DebugAdvanceTo`, which only work in Studio. On a live server it says so. It needs a public `RoadService:PoseAt(studs)` (or `AdvanceTo(n)`) to work there. It also needs the spline road; on the piece road it says so.
- **The distance in `where` and `run-info`** reads the same Studio-only generator: on a live server they give the piece and how far along it, not studs from the start.
- **Permission levels.** One list; everyone on it can run everything.

## Rules and numbers

`Shared/Config/Admin.luau`: `UserIds` (empty), `PerSecond` 8, `PerMinute` 120, `ActivationKeys` `{ F2 }`, `PlaceName` "Drift".

## UI

Cmdr's own window, untouched: a dark bar across the top of the screen, `DisplayOrder` Cmdr's own. It's a debug tool, outside `UI-INVENTORY.md`.

## Server and client

- **Cmdr's layout:** the library is in `ServerStorage.Cmdr`. `CmdrService` requires it, which moves `CmdrClient` into `ReplicatedStorage` and makes Cmdr's two remotes inside it. The game's commands and types are in `ServerScriptService.AdminConsole` (`Commands/<Group>/<name>` with `<name>Server` beside it, `Types/DriftTypes`, and `Ops`, the server helpers); Cmdr moves each command's definition to the client and keeps the `...Server` half on the server.
- **What moves a car:** only `CarService:Place`. Starting and ending runs go through `RoadService:StartRun` / `EndRun`, and the client is told with the same `RoadRun` answer the start button gets (`RunState`), so the run button and the score follow a console run.
- **Trust:** every server command's arguments are typed by Cmdr and checked again where they matter (`tp-to` refuses non-numbers and anything past a million studs; `unstuck` uses the client's pose only within 300 studs of where the server believes the car is). The only client-to-server path is Cmdr's `CmdrFunction`, behind the BeforeRun hook.

## Contracts

- **Remotes:** `ReplicatedStorage.CmdrClient.CmdrFunction` (RemoteFunction, client to server: `(text: string, options: { Data: any }?) -> string`; Cmdr refuses text over 10 000 characters; every command passes `CmdrService`'s BeforeRun hook: permission, then the rate limit) and `CmdrClient.CmdrEvent` (RemoteEvent, server to client: Cmdr's own events, `AddLine` and `Message`). Cmdr's, not `Net`'s.
- **Attribute:** `CmdrAdmin` (boolean) on each `Player`, set by `CmdrService` at join: whether the client shows the console. Grants nothing.
- **Cmdr event `DriftAction`** (on `CmdrEvent`, server to client): `(action, ...)` with `action` one of `getOut`, `getIn`, `speed`, `scoreSet`, `scoreReset`. Sent by `Ops.sendAction` only from a command that passed the server's hook, to each targeted player's client, which does it through `CmdrController:Act`.
- **Service APIs:** `CmdrService.allowed(userId, ctx) -> (boolean, why)` and `CmdrService.rate(entry, now, perSecond, perMinute) -> (boolean, entry)` (pure); `CmdrService:Allowed(player) -> (boolean, why)`; `CmdrController:Run(text) -> reply`, `Act(action, ...) -> reply`, `CmdrController.onlyMe(players) -> boolean`, `Show()`, `Hide()`.

## Analytics

None: a debug tool.

## Platform risks

None. Nothing a player buys, says or sees by default; the console is hidden from everyone but the owner and the listed admins.

## Art and sound

None.

## Testing

- **Unit test:** `Tests/AdminConsoleTests` (`DebugAdminConsoleTests "run"`): who a command acts on (left out or empty is the caller, non-players dropped, one line per target, one failing target reported rather than thrown, one `DriftAction` per target), the permission rule with made-up live contexts (a stranger refused; the owner, a listed admin and a group's owner let in; a group rank below 255 and a user whose id equals the group's refused; everyone in Studio), the rate limit, and with a playtest running, that every registered command has a group and a description and the skipped built-ins are absent.
- **Bridges:** server `CmdrService:DebugState()` (commands, counts of ran / refused / limited, the last 50 commands), `DebugRun(text, userId?)` (a server command through the hook), `DebugClearLimits()`; client `CmdrController:DebugState()` and `Run(text)` (exactly as typing it).
- **In a playtest:** run each command through `CmdrController:Run` and measure what it did (positions, `Lighting.ClockTime`, `RoadService` state, the score). `CmdrService:DebugRun` takes the server path, so a targeted client command goes out as a `DriftAction`; `CmdrController:DebugState().lastAction` shows what the target's client did with it.
- **Not yet tried with two real players:** the Studio tools start a one-player playtest. Targets were tested by full name, by the start of a name, with `me` and `all`, and by sending `DriftAction` through the server path.

## Open questions

- Should `time` set the whole server's time? That's a change to `SkyController` (a replicated offset).
- Should testers get a touch or gamepad way to open it?
