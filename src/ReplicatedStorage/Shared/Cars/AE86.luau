--!strict
-- AE86: the hand-built car the user dropped into the Main place, read out of it and
-- written down here as plain text, so every lane, every place file and a published game
-- build the same car (docs/game/features/drift-model.md "Art and sound").
--
-- WHY THIS IS A LUAU TABLE AND NOT AN .rbxm
-- Place files are not in git, so a car that lives only in `places\DR-Main.rbxl` is a car
-- the game does not have. A model file would have to sit under `src/` to be synced by
-- Lync (`assets/` is not in `default.project.json`'s tree), and a binary blob under `src/`
-- cannot be read, reviewed or diffed. This is the same geometry as text: every part, its
-- place, its size, its mesh and its material. `Shared/CarModel` builds it.
--
-- WHAT WAS THROWN AWAY, ON THE USER'S INSTRUCTION ("ditch all the scripts attached to it")
-- The original is an A-Chassis vehicle: 54 scripts, a VehicleSeat, a BodyVelocity, four
-- BodyForces, three BodyThrusts, 27 Sounds, 14 ParticleEmitters, ClickDetectors, GUIs and
-- 62 invisible chassis, axle, suspension and weight parts. None of it is here. What is
-- here is the 98 parts that are visible and nothing else -- no script, no sound, no
-- constraint, no joint, no mover. The car is kinematic and `Render` is the only thing that
-- moves it (docs/game/DECISIONS.md, 2026-11-03).
--
-- FRAMES
-- `shell` is in the car's own frame: the origin sits at the centre of the four wheel
-- hubs, on the hub plane, with the car's nose down -Z. `wheels` are each in their own hub
-- frame, same axes, origin at the hub centre, with the hub part's own steer and spin
-- dropped -- so a rebuilt wheel starts dead straight and `Render` owns its angle.
--
-- UNITS are the model's own studs. `CarModel` scales them onto `Config.Drift`.
--
-- PART FIELDS: n name, c ClassName, p position, r rotation matrix (absent = identity),
-- s Size, col Color, m Material, tr Transparency, rf Reflectance, sh CastShadow,
-- mesh MeshId, tex TextureID, ds DoubleSided, shape Part.Shape, kids child instances
-- (sa SurfaceAppearance, tex Texture, dec Decal, sm SpecialMesh, mesh Cylinder/BlockMesh).
--
-- THE MESH AND TEXTURE IDS ARE A THIRD PARTY'S UPLOADS. They are a real manufacturer's
-- car. See `assets/car-ae86/MANIFEST.md` before this ships to anyone.

export type PartData = {
	n: string,
	c: string,
	p: { number },
	r: { number }?,
	s: { number },
	col: { number },
	m: string,
	tr: number?,
	rf: number?,
	sh: boolean?,
	mesh: string?,
	tex: string?,
	ds: boolean?,
	shape: string?,
	kids: { { [string]: any } }?,
}

local AE86 = {}

-- Measured off the model itself, in its own studs (T-020). `CarModel` divides the config's
-- numbers by these to get the scale, so the config stays the truth and this stays a record
-- of what was read.
AE86.measured = {
	wheelbase = 9.0215, -- front hub plane to rear hub plane
	trackFront = 5.0661,
	trackRear = 5.1871,
	track = 5.1266, -- the mean, which is what the scale uses
	wheelDiameter = 2.1919,
	wheelWidth = 0.9133,
	bodyLength = 15.6138, -- the visible shell's bounding box
	bodyWidth = 6.8354,
	bodyHeight = 4.4267,
	bodyLowest = -0.6032, -- the shell's lowest point, below the hub plane
}

-- 82 visible parts, in the car's frame.
AE86.shell = {
	{n="TOY_TRUENO_LIGHTS_LODA.002",c="MeshPart",p={0.045,1.4313,0.283},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.5376,0.7246,15.0888},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942015",ds=true,kids={{k="sa",cm="rbxassetid://10786941955",nm="",mm="",rm="rbxassetid://10786941992",am="Overlay"}}},
	{n="TOY_TRUENO_LIGHTS_LODA.001",c="MeshPart",p={0.045,1.4728,0.2786},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.5302,0.9265,15.0748},col={0.6392,0.6353,0.6471},m="Concrete",mesh="rbxassetid://10786942018",ds=true,kids={{k="sa",cm="rbxassetid://10786941955",nm="rbxassetid://10786941962",mm="",rm="rbxassetid://10786941992",am="Overlay"}}},
	{n="TOY_TRUENO_SHIFTGAITER_CPIT",c="MeshPart",p={0.0454,0.8541,-1.0805},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={0.5266,0.6407,0.7756},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942235",ds=true,kids={{k="sa",cm="rbxassetid://10786949500",nm="rbxassetid://10786949412",mm="",rm="rbxassetid://10786949393",am="Overlay"}}},
	{n="TOY_TRUENO_WIPERS_LODA",c="MeshPart",p={-0.2323,2.2943,-2.8636},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={4.4399,0.3565,0.7729},col={0.0667,0.0667,0.0667},m="Metal",mesh="rbxassetid://10786941845",ds=true},
	{n="TOY_TRUENO_INTERIOR2_CPIT.001",c="MeshPart",p={0.0445,1.099,1.6862},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.2001,2.6237,10.0411},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942260",ds=true,kids={{k="sa",cm="rbxassetid://10786950205",nm="rbxassetid://10786948804",mm="",rm="rbxassetid://10786950205",am="Overlay"}}},
	{n="TOY_TRUENO_INTERIOR2_CPIT.002",c="MeshPart",p={0.0448,1.754,0.8249},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.2977,3.7135,8.0106},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942277",ds=true,kids={{k="sa",cm="rbxassetid://10786949351",nm="rbxassetid://10786949411",mm="",rm="rbxassetid://10786949349",am="Overlay"}}},
	{n="TOY_TRUENO_INTERIOR2_CPIT.003",c="MeshPart",p={0.0452,1.3557,-0.5286},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.2102,2.8289,5.2471},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942282",ds=true,kids={{k="sa",cm="rbxassetid://10786948779",nm="rbxassetid://10786950217",mm="",rm="rbxassetid://10786949349",am="Overlay"}}},
	{n="TOY_TRUENO_INTERIOR2_CPIT.004",c="MeshPart",p={0.0446,3.5757,1.5455},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={3.4728,0.2864,3.8895},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942313",ds=true,kids={{k="sa",cm="rbxassetid://10786950938",nm="rbxassetid://10786948807",mm="",rm="rbxassetid://10786950187",am="Overlay"}}},
	{n="TOY_TRUENO_INTERIOR2_CPIT.005",c="MeshPart",p={0.0445,1.8141,1.7304},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.5525,3.6762,10.1282},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942335",ds=true,kids={{k="sa",cm="rbxassetid://10786948793",nm="rbxassetid://10786949411",mm="",rm="rbxassetid://10786949349",am="Overlay"}}},
	{n="TOY_TRUENO_INTERIOR2_CPIT.006",c="MeshPart",p={0.0446,0.5465,1.6663},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={4.964,0.694,4.5032},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942328",ds=true,kids={{k="sa",cm="rbxassetid://10786948792",nm="rbxassetid://10786950191",mm="",rm="rbxassetid://10786950187",am="Overlay"}}},
	{n="Paint",c="MeshPart",p={0.045,2.2813,0.2036},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={6.1347,3.0843,14.9249},col={0.9725,0.9725,0.9725},m="SmoothPlastic",mesh="rbxassetid://10786941880",ds=true},
	{n="TOY_TRUENO_BODY_LODA",c="MeshPart",p={0.0429,1.8381,7.4653},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.4241,0.1961,0.5338},col={0.0667,0.0667,0.0667},m="Metal",mesh="rbxassetid://10786939809",ds=true},
	{n="TOY_TRUENO_BODY_LODA.004",c="MeshPart",p={0.0449,0.728,0.6665},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={6.2266,2.1372,14.275},col={0.0667,0.0667,0.0667},m="SmoothPlastic",mesh="rbxassetid://10786941875",ds=true},
	{n="TOY_TRUENO_BODY_LODA.002",c="MeshPart",p={0.0445,2.8676,1.8845},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.4934,1.4845,9.5242},col={0.0667,0.0667,0.0667},m="Metal",tr=0.75,mesh="rbxassetid://10786941840",ds=true},
	{n="TOY_TRUENO_BODY_LODA.005",c="MeshPart",p={0.0444,1.6695,2.3335},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={6.8322,4.0018,10.9123},col={0.0667,0.0667,0.0667},m="Concrete",mesh="rbxassetid://10786941884",ds=true},
	{n="TOY_TRUENO_CHASSIS_LODA.001",c="MeshPart",p={0.045,1.537,0.2595},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={6.807,4.2482,15.0366},col={0.6392,0.6353,0.6471},m="Concrete",mesh="rbxassetid://10786942031",ds=true,kids={{k="sa",cm="rbxassetid://10786940468",nm="rbxassetid://10786940572",mm="",rm="rbxassetid://10786940798",am="Overlay"}}},
	{n="TOY_TRUENO_CHASSIS_LODA",c="MeshPart",p={0.0446,1.1476,1.5377},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={6.1485,2.0865,12.3774},col={0.6392,0.6353,0.6471},m="Metal",tr=0.02,mesh="rbxassetid://10786940727",ds=true,kids={{k="sa",cm="rbxassetid://10786939862",nm="rbxassetid://10786940376",mm="",rm="rbxassetid://10786940375",am="Transparency"}}},
	{n="TOY_TRUENO_DISPLAY_CPIT",c="MeshPart",p={0.3986,2.0158,-2.0289},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={1.5215,0.1997,0.0896},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942156",ds=true,kids={{k="sa",cm="rbxassetid://10786949347",nm="",mm="",rm="rbxassetid://10786949349",am="Overlay"}}},
	{n="TOY_TRUENO_INTANIM_CPIT.001",c="MeshPart",p={0.8994,2.6619,-0.8771},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={2.4027,1.7651,0.8865},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942258",ds=true,kids={{k="sa",cm="rbxassetid://10786949500",nm="rbxassetid://10786949412",mm="",rm="rbxassetid://10786949393",am="Overlay"}}},
	{n="TOY_TRUENO_INTANIM_CPIT",c="MeshPart",p={0.0622,3.2749,-0.607},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={0.6978,0.2273,0.2321},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942192",ds=true,kids={{k="sa",cm="rbxassetid://10786950179",nm="",mm="",rm="rbxassetid://10786950213",am="Overlay"}}},
	{n="TOY_TRUENO_GEARSHIFT_CPIT",c="MeshPart",p={0.0453,1.3119,-0.9185},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={0.1575,0.2994,0.1556},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942185",ds=true,kids={{k="sa",cm="rbxassetid://10786949500",nm="rbxassetid://10786949412",mm="",rm="rbxassetid://10786949393",am="Overlay"}}},
	{n="TOY_TRUENO_INTERIOR1_CPIT",c="MeshPart",p={0.9437,1.746,-1.6679},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={2.7633,1.0248,0.7347},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942200",ds=true,kids={{k="sa",cm="rbxassetid://10786949500",nm="rbxassetid://10786949412",mm="",rm="rbxassetid://10786949393",am="Overlay"}}},
	{n="TOY_TRUENO_INTERIOR1_CPIT.002",c="MeshPart",p={0.0448,1.2625,0.8767},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.4232,1.7976,5.178},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942262",ds=true,kids={{k="sa",cm="rbxassetid://10786949500",nm="rbxassetid://10786949412",mm="",rm="rbxassetid://10786949393",am="Overlay"}}},
	{n="TOY_TRUENO_INTERIOR1_CPIT.001",c="MeshPart",p={0.0445,1.7031,1.824},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.4934,3.8471,9.8832},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942283",ds=true,kids={{k="sa",cm="rbxassetid://10786949500",nm="rbxassetid://10786949412",mm="",rm="rbxassetid://10786949393",am="Overlay"}}},
	{n="TOY_TRUENO_INTERIOR2_CPIT",c="MeshPart",p={0.0447,1.066,1.1685},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.194,1.593,6.4628},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942206",ds=true,kids={{k="sa",cm="rbxassetid://10786950185",nm="rbxassetid://10786950191",mm="",rm="rbxassetid://10786950187",am="Overlay"}}},
	{n="MeshPart",c="MeshPart",p={-1.5443,0.0864,-7.2242},r={1,0.000068,-0.000285,0,0.972452,0.2331,0.000293,-0.2331,0.972452},s={0.5815,0.3409,0.2598},col={0.0667,0.0667,0.0667},m="SmoothPlastic",mesh="rbxassetid://2292441794",ds=true},
	{n="MeshPart",c="MeshPart",p={-1.5443,0.0602,-7.3374},r={1,0.000058,-0.000287,0,0.97991,0.19944,0.000293,-0.19944,0.97991},s={0.5815,0.3409,0.05},col={1,0.6902,0},m="Metal",mesh="rbxassetid://2292443668",ds=true},
	{n="MeshPart",c="MeshPart",p={1.5378,0.0765,-7.2216},r={1,0.000076,-0.000283,0,0.965956,0.258706,0.000293,-0.258706,0.965956},s={0.5813,0.3408,0.2598},col={0.0667,0.0667,0.0667},m="SmoothPlastic",mesh="rbxassetid://2292430862",ds=true},
	{n="MeshPart",c="MeshPart",p={1.538,0.0461,-7.3338},r={1,0.000066,-0.000285,0,0.974317,0.225177,0.000293,-0.225177,0.974317},s={0.5815,0.3409,0.05},col={1,0.6902,0},m="Metal",mesh="rbxassetid://2292447031",ds=true},
	{n="TOY_TRUENO_BUMPER_F_LODA.001",c="MeshPart",p={0.0472,0.9373,-7.3263},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={3.0862,0.6617,0.4405},col={0.0667,0.0667,0.0667},m="SmoothPlastic",mesh="rbxassetid://10786941876",ds=true},
	{n="Paint",c="MeshPart",p={0.0469,0.7502,-6.4824},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.9582,0.1604,2.0906},col={0.9725,0.9725,0.9725},m="Concrete",mesh="rbxassetid://10786941907",ds=true},
	{n="TOY_TRUENO_BUMPER_F_LODA.004",c="MeshPart",p={0.0472,0.7347,-7.4761},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={4.2578,0.1939,0.0629},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://10786941958",ds=true,kids={{k="sa",cm="rbxassetid://10786941955",nm="",mm="",rm="rbxassetid://10786941992",am="Overlay"}}},
	{n="TOY_TRUENO_BUMPER_F_LODA.005",c="MeshPart",p={0.0473,0.736,-7.5578},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={0.7203,0.1002,0.0096},col={0.6392,0.6353,0.6471},m="Metal",tr=0.02,mesh="rbxassetid://10786941954",ds=true,kids={{k="sa",cm="rbxassetid://10786939862",nm="rbxassetid://10786940376",mm="",rm="rbxassetid://10786940375",am="Transparency"}}},
	{n="TOY_TRUENO_BUMPER_F_LODA",c="MeshPart",p={0.0469,0.3738,-6.3802},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={6.0122,1.3568,2.4454},col={0.0667,0.0667,0.0667},m="SmoothPlastic",mesh="rbxassetid://10786939822",ds=true},
	{n="TOY_TRUENO_BUMPER_F_LODA.003",c="MeshPart",p={0.0469,0.482,-6.3546},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={5.9385,1.5722,2.3942},col={0.6392,0.6353,0.6471},m="Concrete",mesh="rbxassetid://10786941918",ds=true,kids={{k="sa",cm="rbxassetid://10786941955",nm="rbxassetid://10786941962",mm="",rm="rbxassetid://10786941992",am="Overlay"}}},
	{n="TOY_TRUENO_NEEDLE_WATER_CPIT",c="MeshPart",p={1.8551,1.9048,-1.9852},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={0.0466,0.0682,0.0378},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://10786942228",ds=true,kids={{k="sa",cm="rbxassetid://10786949500",nm="rbxassetid://10786949412",mm="",rm="rbxassetid://10786949393",am="Overlay"}}},
	{n="TOY_TRUENO_NEEDLE_FUEL_CPIT",c="MeshPart",p={0.7302,1.9052,-1.9844},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={0.0467,0.0682,0.0378},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://10786942207",ds=true,kids={{k="sa",cm="rbxassetid://10786949500",nm="rbxassetid://10786949412",mm="",rm="rbxassetid://10786949393",am="Overlay"}}},
	{n="TOY_TRUENO_NEEDLE_OILP_CPIT",c="MeshPart",p={1.6967,1.9047,-1.984},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={0.0477,0.0677,0.0378},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://10786942208",ds=true,kids={{k="sa",cm="rbxassetid://10786949500",nm="rbxassetid://10786949412",mm="",rm="rbxassetid://10786949393",am="Overlay"}}},
	{n="Paint",c="MeshPart",p={0.0431,0.8051,6.6629},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={6.0839,0.1826,2.6868},col={0.9725,0.9725,0.9725},m="SmoothPlastic",mesh="rbxassetid://10786941975",ds=true},
	{n="TOY_TRUENO_BUMPER_R_LODA.002",c="MeshPart",p={0.0431,0.3121,6.7518},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={6.0297,0.8784,2.5089},col={0.0667,0.0667,0.0667},m="SmoothPlastic",mesh="rbxassetid://10786941993",ds=true},
	{n="TOY_TRUENO_BUMPER_R_LODA.003",c="MeshPart",p={0.0431,0.1456,6.6409},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={6.0195,1.4976,2.6429},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942000",ds=true,kids={{k="sa",cm="rbxassetid://10786939845",nm="",mm="",rm="rbxassetid://10786939850",am="Overlay"}}},
	{n="Choke",c="Part",p={1.0857,1.7331,-4.4304},r={0.933765,-0.357721,-0.011263,0.354616,0.920492,0.164139,-0.048349,-0.157261,0.986377},s={0.052,0.974,0.332},col={0.6392,0.6353,0.6471},m="Metal",shape="Cylinder",kids={{k="dec",t="rbxassetid://5413428932",f="Right",tr=0,c={1,1,1}}}},
	{n="MeshPart",c="MeshPart",p={0.3597,0.6299,-4.545},r={0.996202,-0.087119,-0.00029,0.086331,0.98674,0.137445,-0.011688,-0.136947,0.990514},s={1.6708,1.101,2.1439},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://5692273340",tex="rbxassetid://1021818616"},
	{n="MeshPart",c="MeshPart",p={-0.0262,1.3027,-4.6982},r={0.000331,-0.341952,0.939722,-0.137453,0.930783,0.338747,-0.990513,-0.129278,-0.046694},s={2.2096,0.6848,1.1549},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://5594502442",tex="rbxassetid://1021818616"},
	{n="MeshPart",c="MeshPart",p={-0.2715,0.5857,-4.948},r={0.972197,-0.234183,-0.000308,0.232,0.962957,0.137442,-0.03189,-0.133691,0.990514},s={0.2786,0.3189,0.5371},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://1021861534",tex="rbxassetid://1021818616"},
	{n="MeshPart",c="MeshPart",p={-0.3962,0.4305,-4.7665},r={0.972197,-0.234183,-0.000308,0.232,0.962957,0.137442,-0.03189,-0.133691,0.990514},s={0.3176,0.3113,0.2153},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://1021860643",tex="rbxassetid://1021818616"},
	{n="Transmission",c="MeshPart",p={0.3001,0.6393,-2.6972},r={0.904612,-0.426121,0.010317,0.42225,0.899176,0.114833,-0.05821,-0.099522,0.993336},s={1.476,0.97,1.5427},col={0.2902,0.2784,0.2863},m="Metal",rf=0.07,mesh="rbxassetid://3208425159",ds=true},
	{n="Choke",c="Part",p={1.0636,1.6371,-4.9419},r={0.933765,-0.357721,-0.011263,0.354616,0.920492,0.164139,-0.048349,-0.157261,0.986377},s={0.052,0.974,0.332},col={0.6392,0.6353,0.6471},m="Metal",shape="Cylinder",kids={{k="dec",t="rbxassetid://5413428932",f="Right",tr=0,c={1,1,1}}}},
	{n="MeshPart",c="MeshPart",p={-0.3802,0.3207,-5.5525},r={0.904581,-0.426259,0.006687,0.422378,0.898251,0.121415,-0.05776,-0.107004,0.992584},s={0.4112,0.4229,0.3457},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://1021995704",tex="rbxassetid://1021818616"},
	{n="MeshPart",c="MeshPart",p={0.9421,1.1025,-4.4105},r={0.980126,-0.198395,-0.000344,0.196553,0.970791,0.137594,-0.026963,-0.134926,0.990493},s={0.956,1.8257,2.1741},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://5603113193",tex="rbxassetid://1021818616"},
	{n="MeshPart",c="MeshPart",p={-0.0952,0.495,-4.5651},r={1.000004,0.00004,-0.00029,-0.000001,0.990509,0.137446,0.000293,-0.137445,0.990514},s={2.6835,1.8369,2.1278},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://5674933019",tex="rbxassetid://1021818616"},
	{n="Choke",c="Part",p={1.0998,1.8075,-4.0269},r={0.933765,-0.357721,-0.011263,0.354616,0.920492,0.164139,-0.048349,-0.157261,0.986377},s={0.052,0.974,0.332},col={0.6392,0.6353,0.6471},m="Metal",shape="Cylinder",kids={{k="dec",t="rbxassetid://5413428932",f="Right",tr=0,c={1,1,1}}}},
	{n="Choke",c="Part",p={1.0611,1.5882,-5.3494},r={0.933765,-0.357721,-0.011263,0.354616,0.920492,0.164139,-0.048349,-0.157261,0.986377},s={0.052,0.974,0.332},col={0.6392,0.6353,0.6471},m="Metal",shape="Cylinder",kids={{k="dec",t="rbxassetid://5413428932",f="Right",tr=0,c={1,1,1}}}},
	{n="Meshes/itb rdo",c="MeshPart",p={0.7845,1.5784,-4.6568},r={0.93356,-0.356546,0.036724,0.348437,0.926778,0.140266,-0.084046,-0.11815,0.989437},s={0.7536,0.4863,1.7394},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://6215060282",tex="rbxassetid://5988414653",ds=true},
	{n="part",c="MeshPart",p={-0.5484,0.5486,-4.0996},r={0.011263,-0.357721,0.933765,-0.164139,0.920492,0.354616,-0.986377,-0.157261,-0.048349},s={2.3692,1.3279,1.0519},col={0.6392,0.6353,0.6471},m="Metal",rf=0.1,mesh="rbxassetid://6048777826"},
	{n="timing belt cover",c="MeshPart",p={-0.0875,1.4547,-5.8396},r={-0.933765,-0.357721,0.011263,-0.354616,0.920492,-0.164139,0.048349,-0.157261,-0.986377},s={1.0127,0.4552,0.1585},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://4400495546",tex="rbxassetid://4400495975",kids={{k="tex",t="rbxassetid://2675785344",f="Left",tr=0.35,c={1,1,1},su=2,sv=2,ou=0,ov=0},{k="tex",t="rbxassetid://2675785344",f="Top",tr=0.35,c={1,1,1},su=2,sv=2,ou=0,ov=0},{k="tex",t="rbxassetid://2675785344",f="Front",tr=0.35,c={1,1,1},su=2,sv=2,ou=0,ov=0},{k="tex",t="rbxassetid://2675785344",f="Back",tr=0.35,c={1,1,1},su=2,sv=2,ou=0,ov=0},{k="tex",t="rbxassetid://2675785344",f="Right",tr=0.35,c={1,1,1},su=2,sv=2,ou=0,ov=0}}},
	{n="Main thing",c="MeshPart",p={-0.1117,1.6607,-4.7147},r={-0.933765,-0.357786,0.00895,-0.354616,0.921534,-0.158185,0.048349,-0.150881,-0.987373},s={1.0843,0.3893,2.19},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://4400495007",tex="rbxassetid://4400495392",kids={{k="tex",t="rbxassetid://2675785344",f="Left",tr=0.35,c={1,1,1},su=2,sv=2,ou=0,ov=0},{k="tex",t="rbxassetid://2675785344",f="Top",tr=0.35,c={1,1,1},su=2,sv=2,ou=0,ov=0},{k="tex",t="rbxassetid://2675785344",f="Front",tr=0.35,c={1,1,1},su=2,sv=2,ou=0,ov=0},{k="tex",t="rbxassetid://2675785344",f="Back",tr=0.35,c={1,1,1},su=2,sv=2,ou=0,ov=0},{k="tex",t="rbxassetid://2675785344",f="Right",tr=0.35,c={1,1,1},su=2,sv=2,ou=0,ov=0}}},
	{n="Lettering",c="MeshPart",p={0.0652,0.1071,-7.3735},r={-0.998831,0.04709,0.010962,0.009456,0.412612,-0.910856,-0.047416,-0.909686,-0.412574},s={1.0929,0.2368,0.4827},col={0.1529,0.2745,0.1765},m="Metal",mesh="rbxassetid://5158490045",ds=true},
	{n="Screw",c="MeshPart",p={-0.3323,0.3286,-7.4096},r={0.998831,0.025266,-0.041222,-0.009456,0.938209,0.345935,0.047416,-0.34514,0.93735},s={0.0432,0.0448,0.033},col={1,1,1},m="SmoothPlastic",mesh="rbxassetid://12156615709",tex="rbxassetid://5158395387",ds=true},
	{n="Screw",c="MeshPart",p={0.4678,0.3268,-7.3657},r={0.998831,0.025266,-0.041222,-0.009456,0.938209,0.345935,0.047416,-0.34514,0.93735},s={0.0432,0.0448,0.033},col={1,1,1},m="SmoothPlastic",mesh="rbxassetid://12156615709",tex="rbxassetid://5158395387",ds=true},
	{n="AntiTheft Screw",c="MeshPart",p={0.4673,0.3258,-7.3726},r={0.998831,0.025266,-0.041222,-0.009456,0.938209,0.345935,0.047416,-0.34514,0.93735},s={0.0994,0.1009,0.0572},col={1,1,1},m="SmoothPlastic",mesh="rbxassetid://12156622875",tex="rbxassetid://5158395387",ds=true},
	{n="Plate",c="MeshPart",p={0.0651,0.1048,-7.3688},r={0.998831,0.025266,-0.041222,-0.009456,0.938209,0.345935,0.047416,-0.34514,0.93735},s={1.2538,0.5958,0.2066},col={0.0667,0.0667,0.0667},m="SmoothPlastic",mesh="rbxassetid://12156658152",tex="rbxassetid://5158395387",ds=true},
	{n="Lettering",c="MeshPart",p={0.0636,1.367,7.6666},r={0.999145,-0.038452,-0.015207,0.009238,0.56605,-0.824319,0.040305,0.823472,0.565921},s={1.0929,0.2368,0.4827},col={0.1529,0.2745,0.1765},m="Metal",mesh="rbxassetid://5158490045",ds=true},
	{n="Screw",c="MeshPart",p={0.4629,1.588,7.6615},r={-0.999145,-0.016178,0.038053,-0.009238,0.98436,0.175929,-0.040305,0.175426,-0.983666},s={0.0432,0.0448,0.033},col={1,1,1},m="SmoothPlastic",mesh="rbxassetid://12156615709",tex="rbxassetid://5158395387",ds=true},
	{n="Screw",c="MeshPart",p={-0.3374,1.5852,7.6223},r={-0.999145,-0.016178,0.038053,-0.009238,0.98436,0.175929,-0.040305,0.175426,-0.983666},s={0.0432,0.0448,0.033},col={1,1,1},m="SmoothPlastic",mesh="rbxassetid://12156615709",tex="rbxassetid://5158395387",ds=true},
	{n="AntiTheft Screw",c="MeshPart",p={-0.3369,1.5854,7.6293},r={-0.999145,-0.016178,0.038053,-0.009238,0.98436,0.175929,-0.040305,0.175426,-0.983666},s={0.0994,0.1009,0.0572},col={1,1,1},m="SmoothPlastic",mesh="rbxassetid://12156622875",tex="rbxassetid://5158395387",ds=true},
	{n="Plate",c="MeshPart",p={0.0637,1.3638,7.6624},r={-0.999145,-0.016178,0.038053,-0.009238,0.98436,0.175929,-0.040305,0.175426,-0.983666},s={1.2538,0.5958,0.2066},col={0.0667,0.0667,0.0667},m="SmoothPlastic",mesh="rbxassetid://12156658152",tex="rbxassetid://5158395387",ds=true},
	{n="MeshPart",c="MeshPart",p={1.3489,1.9008,-0.9011},r={-1,0.000062,0.000275,0.00004,0.997122,-0.075811,-0.000279,-0.075811,-0.997122},s={1.6472,1.5634,0.6677},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://696842916",tex="rbxassetid://696829111"},
	{n="TOY_TRUENO_POPUP_1_LODA",c="MeshPart",p={-1.8547,0.9731,-6.8575},r={1.000001,0,-0.000293,0,1,0,0.000293,0,1},s={0.7031,0.175,0.5289},col={0.6392,0.6353,0.6471},m="Glass",tr=0.02,sh=false,mesh="rbxassetid://10786941433",kids={{k="sa",cm="rbxassetid://10786941478",nm="rbxassetid://10786941643",mm="",rm="rbxassetid://10786941616",am="Transparency"}}},
	{n="TOY_TRUENO_POPUP_1_LODA.001",c="MeshPart",p={-1.8638,1.1232,-7.2486},r={1.000001,0,-0.000293,0,1,0,0.000293,0,1},s={0.9541,0.2553,0.1799},col={0.0667,0.0667,0.0667},m="SmoothPlastic",mesh="rbxassetid://10786942014"},
	{n="TOY_TRUENO_POPUP_1_LODA.002",c="MeshPart",p={-1.8684,1.176,-6.8769},r={1.000001,0,-0.000293,0,1,0,0.000293,0,1},s={1.0006,0.6656,0.8141},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942019",kids={{k="sa",cm="rbxassetid://10786941955",nm="rbxassetid://10786941962",mm="",rm="rbxassetid://10786941992",am="Overlay"}}},
	{n="Paint",c="MeshPart",p={-1.8736,1.3957,-6.947},r={1.000001,0,-0.000293,0,1,0,0.000293,0,1},s={0.9925,0.3109,0.6248},col={0.9725,0.9725,0.9725},m="SmoothPlastic",mesh="rbxassetid://10786942025"},
	{n="TOY_TRUENO_POPUP_1_LODA.004",c="MeshPart",p={-1.8548,0.9654,-6.8575},r={1.000001,0,-0.000293,0,1,0,0.000293,0,1},s={0.7385,0.1957,0.5665},col={0.9725,0.9725,0.9725},m="Glass",tr=0.1,sh=false,mesh="rbxassetid://10786942030"},
	{n="TOY_TRUENO_POPUP_2_LODA",c="MeshPart",p={1.9488,0.9731,-6.8563},r={1.000001,0,-0.000292,0,1.000001,0,0.000292,0,1.000001},s={0.703,0.175,0.5289},col={0.9725,0.9725,0.9725},m="Glass",tr=0.1,sh=false,mesh="rbxassetid://10786941589"},
	{n="TOY_TRUENO_POPUP_2_LODA.001",c="MeshPart",p={1.9581,1.1232,-7.2475},r={1.000001,0,-0.000292,0,1.000001,0,0.000292,0,1.000001},s={0.9541,0.2553,0.1799},col={0.0667,0.0667,0.0667},m="SmoothPlastic",mesh="rbxassetid://10786942038"},
	{n="TOY_TRUENO_POPUP_2_LODA.002",c="MeshPart",p={1.9625,1.176,-6.8758},r={1.000001,0,-0.000292,0,1.000001,0,0.000292,0,1.000001},s={1.0006,0.6656,0.8141},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786942070",kids={{k="sa",cm="rbxassetid://10786941955",nm="rbxassetid://10786941962",mm="",rm="rbxassetid://10786941992",am="Overlay"}}},
	{n="Paint",c="MeshPart",p={1.9677,1.3956,-6.9458},r={1.000001,0,-0.000292,0,1.000001,0,0.000292,0,1.000001},s={0.9925,0.3109,0.6248},col={0.9725,0.9725,0.9725},m="SmoothPlastic",mesh="rbxassetid://10786942069"},
	{n="TOY_TRUENO_POPUP_2_LODA.004",c="MeshPart",p={1.9489,0.9654,-6.8564},r={1.000001,0,-0.000292,0,1.000001,0,0.000292,0,1.000001},s={0.7385,0.1957,0.5665},col={0.6392,0.6353,0.6471},m="Glass",tr=0.02,sh=false,mesh="rbxassetid://10786942066",kids={{k="sa",cm="rbxassetid://10786941889",nm="",mm="",rm="rbxassetid://10786941897",am="Transparency"}}},
	{n="Paint",c="MeshPart",p={0.0465,1.7821,-4.9965},r={1,0,-0.000293,0,1.000001,0,0.000293,0,1},s={5.0906,1.0333,4.5974},col={0.9725,0.9725,0.9725},m="SmoothPlastic",mesh="rbxassetid://10786939815"},
	{n="TOY_TRUENO_BONNET_LODA.001",c="MeshPart",p={0.0465,1.7754,-4.9964},r={1,0,-0.000293,0,1.000001,0,0.000293,0,1},s={5.0906,1.0199,4.5971},col={0.6392,0.6353,0.6471},m="Plastic",mesh="rbxassetid://10786941879",kids={{k="sa",cm="rbxassetid://10786940468",nm="rbxassetid://10786940572",mm="",rm="rbxassetid://10786940798",am="Overlay"}}},
	{n="Needle",c="MeshPart",p={1.017,1.9787,-1.9646},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={0.2507,0.1225,0.0518},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://10786942214",ds=true,kids={{k="sa",cm="rbxassetid://10786949500",nm="rbxassetid://10786949412",mm="",rm="rbxassetid://10786949393",am="Overlay"}}},
	{n="Needle",c="MeshPart",p={1.4999,1.9853,-1.9656},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={0.2574,0.1091,0.0494},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://10786942221",ds=true,kids={{k="sa",cm="rbxassetid://10786949500",nm="rbxassetid://10786949412",mm="",rm="rbxassetid://10786949393",am="Overlay"}}},
}

-- The four wheels, each in its own hub frame: +X is the car's right, the axle runs along
-- X, and the hub centre is the origin. `Render` gives each one its steer and its spin.
AE86.wheels = {
	FL = {
		{n="Rim",c="MeshPart",p={-0.0121,0,0},r={-1,-0.000293,0.000012,0.000012,0.000017,1,-0.000293,1,-0.000017},s={0.9407,1.6978,1.6978},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://2254775296",tex="rbxassetid://3044336267",ds=true},
		{n="Tire",c="MeshPart",p={-0.0121,0,0},r={0,-1,0.000293,-1,0,0,0,-0.000293,-1},s={2.1919,0.9133,2.1919},col={0.6392,0.6353,0.6471},m="Concrete",mesh="rbxassetid://5211564152",tex="rbxassetid://5211564225",ds=true},
		{n="break assembly",c="MeshPart",p={0.2773,0.0011,0.0313},r={-1,0,0.000293,0,1,0,-0.000293,0,-1},s={0.4101,1.0382,1.1012},col={0.1961,0.1961,0.1961},m="Concrete",mesh="rbxassetid://3545852658",tex="rbxassetid://1539341292",ds=true},
		{n="break disc",c="MeshPart",p={0.2122,0.0011,-0.0003},r={-1,0,0.000293,0,1,0,-0.000293,0,-1},s={0.0969,0.9762,0.9762},col={0.6392,0.6353,0.6471},m="Concrete",rf=0.15,mesh="rbxassetid://3545844190",tex="rbxassetid://3545846201",ds=true},
	},
	FR = {
		{n="break disc",c="MeshPart",p={-0.2123,0.0011,-0.0005},r={1,0,-0.000292,0,1,0,0.000292,0,1},s={0.0969,0.9762,0.9762},col={0.6392,0.6353,0.6471},m="Concrete",rf=0.15,mesh="rbxassetid://3545844190",tex="rbxassetid://3545846201",ds=true},
		{n="break assembly",c="MeshPart",p={-0.2775,0.0011,-0.032},r={1,0,-0.000292,0,1,0,0.000292,0,1},s={0.4101,1.0382,1.1012},col={0.1961,0.1961,0.1961},m="Concrete",mesh="rbxassetid://3545852658",tex="rbxassetid://1539341292",ds=true},
		{n="Rim",c="MeshPart",p={0.0122,0,0},r={1,0.000293,-0.000012,0.000012,0.000017,1,0.000293,-1,0.000017},s={0.9407,1.6978,1.6978},col={0.9725,0.9725,0.9725},m="Metal",mesh="rbxassetid://2254775296",tex="rbxassetid://3044336267",ds=true},
		{n="Tire",c="MeshPart",p={0.0122,0,0},r={0,1,-0.000293,-1,0,0,0,0.000293,1},s={2.1919,0.9133,2.1919},col={0.6392,0.6353,0.6471},m="Concrete",mesh="rbxassetid://5211564152",tex="rbxassetid://5211564225",ds=true},
	},
	RL = {
		{n="break disc",c="MeshPart",p={0.2123,0.0011,-0.0001},r={-1,0,0.000292,0,1,0,-0.000292,0,-1},s={0.0969,0.9762,0.9762},col={0.6392,0.6353,0.6471},m="Concrete",rf=0.15,mesh="rbxassetid://3545844190",tex="rbxassetid://3545846201",ds=true},
		{n="break assembly",c="MeshPart",p={0.2775,0.0011,0.0315},r={-1,0,0.000292,0,1,0,-0.000292,0,-1},s={0.4101,1.0382,1.1012},col={0.1961,0.1961,0.1961},m="Concrete",mesh="rbxassetid://3545852658",tex="rbxassetid://1539341292",ds=true},
		{n="Rim",c="MeshPart",p={-0.0122,0,0},r={-1,-0.000292,0.000012,0.000012,0.000017,1,-0.000292,1,-0.000017},s={0.9407,1.6978,1.6978},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://2254775296",tex="rbxassetid://3044336267",ds=true},
		{n="Tire",c="MeshPart",p={-0.0122,0,0},r={0,-1,0.000292,-1,0,0,0,-0.000292,-1},s={2.1919,0.9133,2.1919},col={0.6392,0.6353,0.6471},m="Concrete",mesh="rbxassetid://5211564152",tex="rbxassetid://5211564225",ds=true},
	},
	RR = {
		{n="break disc",c="MeshPart",p={-0.2122,0.0011,-0.0003},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={0.0969,0.9762,0.9762},col={0.6392,0.6353,0.6471},m="Concrete",rf=0.15,mesh="rbxassetid://3545844190",tex="rbxassetid://3545846201",ds=true},
		{n="break assembly",c="MeshPart",p={-0.2774,0.0011,-0.0318},r={1,0,-0.000293,0,1,0,0.000293,0,1},s={0.4101,1.0382,1.1012},col={0.1961,0.1961,0.1961},m="Concrete",mesh="rbxassetid://3545852658",tex="rbxassetid://1539341292",ds=true},
		{n="Rim",c="MeshPart",p={0.0121,0,0},r={1,0.000293,-0.000012,0.000012,0.000017,1,0.000293,-1,0.000017},s={0.9407,1.6978,1.6978},col={0.6392,0.6353,0.6471},m="Metal",mesh="rbxassetid://2254775296",tex="rbxassetid://3044336267",ds=true},
		{n="Tire",c="MeshPart",p={0.0121,0,0},r={0,1,-0.000293,-1,0,0,0,0.000293,1},s={2.1919,0.9133,2.1919},col={0.6392,0.6353,0.6471},m="Concrete",mesh="rbxassetid://5211564152",tex="rbxassetid://5211564225",ds=true},
	},
}

return AE86
