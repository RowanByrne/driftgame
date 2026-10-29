# Data system

> **Stub: the user is designing it.**
>
> **What it is:** our own custom dashboard, built for rapid iteration and shared by every game. It runs off the game's custom events (ANALYTICS.md), pulled as soon as they happen. That gets around the delay of Roblox's own processing, so we see how an update performs within minutes of launch instead of waiting for the Creator Hub dashboards.
>
> **Decided so far:**
> - Built on the custom events the analytics helper already sends.
> - Anonymized, so the data can be stored locally.
> - The specific dashboards and views come later, designed around the decisions we need to make fast.
> - The Creator Hub stays for what only Roblox has: the Error Report, Performance and alerts (DASHBOARDS.md).
> - Earlier decisions: no external backend, and no Open Cloud API.
>
> **Still open:**
> - How events get from live servers to the local store within minutes.
> - Where "locally" is (the RoDev folder, the game's folder, a PC), and how much of it goes in git.
> - What anonymized means in practice: what, if anything, ties events from the same player together.
> - The first views to build, and which decisions each one serves (a post-release view would fit POST-RELEASE.md).
