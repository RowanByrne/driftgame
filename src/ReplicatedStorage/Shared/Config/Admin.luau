--!strict
-- Admin: who may use the admin console (Cmdr) on a live server, and how often
-- (docs/game/features/admin-console.md, T-159).
--
-- WHO: everyone in Studio. On a live server, the game's owner (the user who owns it, or the
-- owner of the group that does) and the user ids below. `CmdrService` decides, on the
-- server, for every command; the client is only told whether to show the window.
--
-- This list replicates to every client like the rest of `Config`: it names who is an admin,
-- which is not a secret, and grants nothing on its own.

return {
	-- Admins on live servers besides the owner: numeric user ids, e.g. { 12345678 }.
	UserIds = {} :: { number },

	-- Commands a player may run in each one-second window, and in each minute. Keyed by
	-- UserId, so rejoining doesn't reset them. A refused command is answered, not dropped.
	PerSecond = 8,
	PerMinute = 120,

	-- The keys that open and close the console. Cmdr's own default.
	ActivationKeys = { Enum.KeyCode.F2 },

	-- The window's title.
	PlaceName = "Drift",
}
