# Architecture

This game's code as built: what each module does and where things are registered. The rules every game follows are in docs/workflow/CODING.md; what other code relies on (data, remotes, tags, attributes, events) is in `CONTRACTS.md` and `EVENT-CATALOG.md`. Started in the Foundation phase; update it in the same commit as the code it describes. Replace each prompt with the answer.

## Overview

> One paragraph: what runs on the server, what runs on the client, and how they talk.

## Services (server)

> Every module in `src/ServerScriptService/Services/`, one line each.

| Service | What it does | Main entry points (signatures in `CONTRACTS.md`) |
|---|---|---|
| | | |

## Controllers (client)

> Every module in `src/StarterPlayerScripts/Controllers/`, one line each.

| Controller | What it does | Main entry points (signatures in `CONTRACTS.md`) |
|---|---|---|
| | | |

## Shared modules

> The modules in `src/ReplicatedStorage/Shared/` that other code requires.

| Module | What it holds |
|---|---|
| | |

## Registries

Where each kind of thing is listed in code, so nothing gets scattered.

| What | Module |
|---|---|
| Remotes | `Shared/Net` (names in `CONTRACTS.md`) |
| Config and tuning | |
| Sounds | |
| Asset ids | |
| Analytics events | |
| Live config keys | (`live/CONFIGS.md`) |
| Timed releases | |
| Update log | (only if the game has one, `PROJECT.md`) |

## Studio tools

> What tests and agents can reach (docs/workflow/TESTING.md).

- **Debug bridge members:** each service's and controller's `Debug*` methods and what `DebugState()` returns.
- **Test profiles:** each `__test_profile` value and the starting state it gives.
- **Admin commands:** the admin console's commands and who can run them.

## Vendored libraries

| Library | Version | Source | Local patches |
|---|---|---|---|
| | | | |

## World and streaming

> Is the world built by code at runtime or by hand in Studio (docs/workflow/LANES.md "Hand-built content")? Is `StreamingEnabled` on or off, and why?
