# Configs

> **Stub, not written yet.**
> **Purpose:** How the game uses Roblox's experience configs to change values live, without publishing: feature flags and kill switches (checkout off), tuning, timed content, and values targeted at groups of players. Lists every config key, its default in code, who changes it, and its history.
>
> **Notes for writing it** (from Roblox's docs, 2026-10-29):
> - `ConfigService` is server-only. `GetConfigAsync()` returns a snapshot for everyone; `GetConfigForPlayerAsync(player)` applies targeting and experiments for one player. `snapshot:GetValue(key)` returns nil for a missing key, so every key needs a default in code.
> - Snapshots don't update by themselves: `UpdateAvailable` fires, then `Refresh()`; `GetValueChangedSignal(key)` follows one key.
> - Changes are staged first (visible in Studio play sessions only), then published to everyone in about 15 s to 1 min, or rolled out over 15 min. History lets you restore an earlier value. "Publish As" in Studio copies all configs to another experience.
> - Targeting attributes: country, language, new vs returning, source, when first played, in-experience payer and activity status, engagement, platform spender and activity status.
> - Limits: 1,000 active configs, 100 conditions per game, 20 per key, values up to 100,000 characters (string or JSON).
> - `GetConfigAsync()` throws only if it has never loaded; wrap it in `pcall` and fall back to the code defaults. `SetTestingValue` / `ClearTestingValue` override a value for one server or Studio session.
