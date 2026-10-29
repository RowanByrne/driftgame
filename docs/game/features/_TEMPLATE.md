# Feature: <Feature name>

> Copy this file to `features/<feature-name>.md` for each feature, link it from `GDD.md` "Systems" (and `ROADMAP.md` if it's in the launch scope), and replace each prompt with the answer. Leave out sections that don't apply.

**Status:** Idea / specced / in progress / built / approved. **Owner task:** the current branch, if one is building it (`docs/CLAIMS.md`).

## Goal

> What the player gets from this and why it's in the game, in two or three sentences.

## How it plays

> What the player sees and does, step by step, including what happens when something goes wrong.

## Rules and numbers

> How it works, with the starting tuning values. The live values sit in config modules (CODING.md), or in Roblox configs if they'll change without a publish (docs/workflow/CONFIGS.md).

## UI

> The screens or HUD pieces it adds or changes, and how each looks in every supported layout (`UI-INVENTORY.md`). Programmer art until the UI phase.

## Server and client

> What the server decides and what the client shows. The server checks everything the client sends (CODING.md "Server rules").

## Contracts

> New or changed data keys, remotes, tags, attributes and service APIs. Add them to `CONTRACTS.md` in the same commit as the code.

## Analytics

> Its events and funnel steps, added to `EVENT-CATALOG.md`. The feature isn't done until they fire.

## Monetization

> Anything it sells or that a purchase changes (`MONETIZATION.md`). Built in the Monetization phase.

## Art and sound

> The models, images and sounds it needs, and whether each is placeholder or final (`ART-PIPELINE.md`).

## Testing

> How to prove it works by measuring: what to check in a playtest, the `Debug*` methods and `DebugState()` it adds, and any automated tests (TESTING.md).

## Open questions

> What still needs the user's decision. Once decided, log it in `DECISIONS.md` and update this spec.
