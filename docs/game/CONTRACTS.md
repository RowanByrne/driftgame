# Contracts

Everything code relies on across modules and tasks: data, remotes, tags, attributes, paths and service APIs. Code against this doc. A change to it goes in the same commit as the code, and a change other tasks build on goes in first, as its own small commit (docs/workflow/CONDUCTOR.md "Main"). Analytics events have their own contract in `EVENT-CATALOG.md`. Replace each prompt with the answer.

## Data

### Stores

> Every data store the game uses. Moving a store up a version starts everyone fresh (docs/workflow/LAUNCH.md "Launch wipe"), and each store needs a right-to-be-forgotten template keyed the same way.

| Store | Kind (standard or ordered) | Key | What it holds |
|---|---|---|---|
| `<CODE>_Player_v1` | standard | `u{UserId}` | Player profiles |

### Profile

**Schema version:** 1. A change to the profile ships with a migration, tested on saved data from the previous version (docs/workflow/CODING.md "Saving").

> Every profile key. Keys starting with `_` are server-only: they're saved, but never sent to the client.

| Key | Type | Default | Written by | Notes |
|---|---|---|---|---|
| | | | | |

### Settings

> The keys a player can change from the client, and how the server checks each value.

| Key | Type | Default | Allowed values |
|---|---|---|---|
| | | | |

### Migrations

| Version | Date | What changed |
|---|---|---|
| 1 | | First version |

## Remotes

> Every remote, named `<Feature><Action>` and created through `Shared/Net`. Every client-to-server remote lists the checks the server makes on it: types, ranges, rate limit.

| Name | Type | Direction | Owner | Payload and checks |
|---|---|---|---|---|
| | RemoteEvent / UnreliableRemoteEvent / RemoteFunction | Client → server / Server → client | | |

## Tags and attributes

> Every tag and attribute that other code reads. Studio-only attributes start with `__`.

| Tag or attribute | On | Set by | Used by |
|---|---|---|---|
| attr `__lync_port` | Workspace (Studio only) | Set by hand per place (docs/workflow/LANES.md) | Lync |
| attr `__test_profile` | Workspace (Studio only) | Set by hand in worker places | DataService (docs/workflow/TESTING.md) |
| attr `__agent_play` | Workspace (Studio only) | Agents, before each playtest | The quiet-playtest module (docs/workflow/TESTING.md) |
| attr `__studio_audio` | Workspace (Studio only) | Agents, for deliberate audio tests | The quiet-playtest module (docs/workflow/TESTING.md) |

## Paths

> Instance paths other code relies on, such as where the world is built or where a folder of models lives.

| Path | What's there | Made by |
|---|---|---|
| | | |

## Service APIs

> Signals and methods that one service or controller exposes for others, with their signatures. Internal methods don't belong here.

| Module | Member | Signature | What it does |
|---|---|---|---|
| | | | |

## Place settings

> Settings made in Studio, not in git, and set the same way in every place: the Main place, every lane, and the published game (docs/workflow/LANES.md "Add a lane").

- `Workspace.StreamingEnabled`: (on or off, as recorded in `ARCHITECTURE.md`)
