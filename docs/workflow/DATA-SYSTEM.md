# Data system

> **Stub, not written yet.**
> **Purpose:** Our own data system for the important metrics, the same for every game. It is filled from the game's custom events (ANALYTICS.md), and it's where we read those metrics, instead of Roblox's Creator Hub dashboards.
>
> **To settle when we design it:**
> - Which metrics count as important: the pitch's numbers, retention, the economy, purchases, errors?
> - Where the data is stored and added up. Decided so far: no external backend, and no Open Cloud API.
> - How we read it: an in-game admin view, Studio, or exports into the repo.
> - How long data is kept, and privacy: what identifies a player, and how deletion requests reach it.
> - What stays in the Creator Hub (DASHBOARDS.md): likely the Error Report, Performance and alerts.
