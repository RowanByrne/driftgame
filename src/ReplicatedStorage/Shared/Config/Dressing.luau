--!strict
-- Config.Dressing: what stands beside a laid road (features/road-dressing.md, T-327).
-- The dressing layer (`Road/RoadDressing`) reads these; the road planner never does, so
-- changing one never changes the road.

return {
	-- CRASH BARRIERS: WHERE THEY STAND (T-306, moved here by T-327). The user, 2026-11-17:
	-- "only on the downhill sides ... longer sections protecting cliffs on corners. hairpins
	-- with big drops should have them too." Placed from the ground itself, never at random:
	-- the DROP beside the road is how far the mountain (`Road/Ground.h`) is below the grass's
	-- outer edge `Probe` studs past it (on the inside of a bend no further than `InsideReach`
	-- of the way to its centre, the drop scaled up to the same slope; nearer than `ProbeMin`
	-- the bend encloses that side and it has no drop). How a barrier looks, and how tall it is
	-- to the car, stays with the road's drawing (`Config.Spline.Terrain.KRail*`).
	Barrier = {
		Probe = 40, -- studs past the runoff's outer edge
		ProbeMin = 10, -- studs
		InsideReach = 0.8, -- of a bend's radius
		Sample = 4, -- studs between the points the drop is read at
		FallDrop = 8, -- studs: a rail only ever stands where the ground falls this much (the downhill side)
		CornerRadius = 340, -- studs: a CORNER is road tighter than this (medium bends and tighter)
		CornerDrop = 20, -- studs: a corner whose outside drops this much is railed the whole way round
		HairpinRadius = 130, -- studs: a TIGHT BEND, the double yellow's (every hairpin is one)
		HairpinDrop = 15, -- studs: either side of a tight bend dropping this much is railed through it
		CliffDrop = 40, -- studs: anywhere else, a drop this big is railed
		LeadIn = 40, -- studs of rail before a corner, a tight bend or a cliff
		RunOut = 60, -- studs after it (on into the next section)
		MinRun = 40, -- studs: no shorter piece of rail (except one carrying on across a section's end)
	},
}
