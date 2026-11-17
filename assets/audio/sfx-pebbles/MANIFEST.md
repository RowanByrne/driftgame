# sfx-pebbles

The sound of **little stones kicked up by the tyres** clicking and clacking into the wheel wells and
the underside of the car while it drives off the road, on gravel, dirt and grass (T-292).

## Brief

The user (2026-11-17): "clicky clacky sounds of like little rocks and shit that are getting kicked
around the wheelwells when driving offroad - pebbles smacking into the wheelwell or the bottom of the
car. it's an offroad driving sound we are missing right now. we can find one that's good as is or
build one out of other smaller sounds."

3D, on the car's body, mono in effect. Plays whenever the wheels roll on grass, gravel or dirt (not
only when sliding, unlike the off-road skid), denser and louder with speed and more again when
sliding; gravel loudest, grass least; silent on tarmac and stopped. From `AUDIO.md`: weighty, clean,
never harsh; realistic, dry and close; no long tails. Its level is the existing "Off-road drift"
slider (`SoundLevels` category `OffRoad`).

## Candidates (2026-11-17)

Every source is **Creator Store** audio by Pro Sound Effects, free in any experience, used **by id**:
nothing would be uploaded for A to D. The store files and the previews are outside git in
`..\art\generated\sfx-pebbles\` (store files in `raw\`). Store files were taken from Studio's own
download cache after preloading each id in `DR-Lane2` (the Open Cloud asset-delivery scope is not
granted to this PC's key).

**The previews** (10.5 s each) play each candidate the way the game would drive it, over one scripted
drive: 0.8 s on tarmac (silent), then gravel from 30 to 120 studs/s with a slide at 5 to 7 s, then
grass at 100 studs/s, then tarmac again (silent). Surface changes crossfade over 0.25 s. Each is
level-matched on the gravel stretch (RMS, capped at a -0.4 dBFS peak), so they compare at about equal
loudness. Rendered by a throwaway script (numpy, soundfile), not kept. The loops are low-cut at about
300 Hz (in game an `EqualizerSoundEffect`), which strips their rumble, and in B the recorded engine.

| | What | Source ids | Preview SHA-256 | Status |
|---|---|---|---|---|
| A | **Gravel crunch loop**: a tyre rolling over gravel, recorded outside, no engine. One loop, its volume and playback speed following road speed | `9126157118` "Vehicle Gravel Tire Pass By Constant No Engine 2", region 6.5 to 17.5 s | `6C499F509DEF4334B9FA2BC3B373ED3D07602184FD0B21BFE3A185A5FFC8ADEF` | rejected (in game as D's crunch) |
| B | **Over rocks, from inside**: tyres crunching over rocks recorded inside a car, so the stones hitting the floor pan are in it. Has the recording car's engine, low-cut out | `9126157444` "Vehicle Gravel Tires Crunch Constant Over Rocks 1", region 1.5 to 12.5 s | `96F7FA41A99FF6DE15C6ABBC6260439C1968BB9C876A14D38E643A8447A2705C` | rejected |
| C | **Pebble ticks**: built in code from 40 single stone hits (35 pebble ticks, 5 heavier clacks) cut from store one-shots, fired at random, each at a random pitch (0.85 to 1.2x) and volume; how many a second follows speed, surface and slide (up to about 45 a second sliding fast on gravel). Never loops | `9117266254`, `9117266257`, `9117266265`, `9117266497` ("Pebble Drop Roll Stone Impact On Concrete 1 to 4"); `9118624159`, `9118624415`, `9118624423`, `9118624649`, `9118624847` ("Rock Impacts 1, 2, 3, 6, 8") | `6698F9E2684FD130D8BD85DD0AD6D8CE320C274EF4B3F80C5654F65CDB2B911B` | rejected (in game as D's ticks) |
| D | **Ticks over crunch**: C on top of A, with A 9 dB under the ticks | as A and C | `9256A6B176E5A89AB04C6F139B13AF1CB458DAF9850431E2EB5076B5AF193939` | approved, then **sent back** (round 2) |

Store file SHA-256 (in `raw\`):

| Store id | SHA-256 |
|---|---|
| `9126157118` | `74F95FAD7148CC50D07D6BC78826AEC937B7F2D59D863A177FF180BC83799619` |
| `9126157444` | `FFDC4271F7FB9505ACEC19B3C69709B41D5A259287DF58CB15CEC19D11DF4190` |
| `9117266254` | `1D46C3A396DBD21D6EF1687E9749C917E7AD85E52215CA949A6F4D600C9B64A0` |
| `9117266257` | `D8728D6C76F115C857FBADD163A24B80775E8BFB1A6E40A4E75A628718AEADEE` |
| `9117266265` | `F3FC2D7FCAA2D8F41EE78C96726614D4FD8DC95135A5446852754D4D73B871AA` |
| `9117266497` | `55FABEFC94D258D25C4518C19447A651B9F9572FD809DC785337ABF536CB93E8` |
| `9118624159` | `06B1A4349BEFAABC7BDFD70AF5F193E11D42A9524797DB1684BDCE6F34AF9375` |
| `9118624415` | `CE1917F60E3C1FE097364602B1C0EF1BAA927A62FD6E372EAB761FB90350D8BE` |
| `9118624423` | `450E89A9E9341AAA570ED2061DB92C6DC709582360D0A0D0F1344A756A3B938C` |
| `9118624649` | `AC6FFA266492ABEAFE2B62917C250EE8216F8BD3DCEC17295C425D24C85C8D72` |
| `9118624847` | `6B025985E390CBEAF0ED40DC2CD97005F27637F07CA3D9422C643CE44AA7C435` |

## The pick

**D, "Ticks + crunch", picked by ear by the user on 2026-11-17** (their answer on the card: "D:
Ticks + crunch"). A, B and C are rejected as picks; A and C live on as D's two layers. Every source
is Creator Store audio used by id, so there is no master in git and nothing was uploaded: the ids,
the 40 slices and every number are in `src/ReplicatedStorage/Shared/Config/Pebbles.luau`, played by
`Drift/PebbleSound`.

**In game against the preview:** the same stream and the same crunch, with three differences. The
crunch's low cut is Roblox's `EqualizerSoundEffect` (`LowGain` -30 dB under its fixed 400 Hz band)
rather than the preview's 300 Hz filter. Each slice ends at the quietest point before the next onset
in its file (every end 29 dB or more under its peak) instead of the preview's short fade. And a
tick's instance volume is held at Roblox's 10: the quietest slices (gain over 7.1) can't be brought
all the way up to the others' peak.

## Level

Measured on the store files (numpy, the same throwaway script). At full speed on gravel, not
sliding, the ticks stream at about **-26.5 dBFS** RMS at `TickVolume` 1.4, and the crunch at
**-35.5 dBFS** at `BedVolume` 0.62 (the loop region, low-cut, is -31.3 dBFS at volume 1). Together
that's about **-26 dBFS**: 8.5 dB under the engine bed (-17.4 dBFS) and under the off-road skid's
loudest moment (-18.8 dBFS). A full slide raises the ticks' rate 1.8x and the crunch 1.5x, to about
-23.5 dBFS together, still under both. Grass is 0.4 of gravel in both rate and loudness (about
-42 dBFS of ticks at full speed); dirt is 0.75.

## Round 2: stones on metal (2026-11-17)

**D was sent back by the user** after trying it in a lane: "eh not quite good enough. need rocks on
metal sound, this is like pebbles on pebbles". The ticks must be stones hitting sheet metal (the
wheel-well liner, the floor pan): hollow, tinny, resonant. The engine, gating, levels and the crunch
under the ticks stay as built; only the hits change.

New hits, all **Creator Store**, Pro Sound Effects, by id, store files in
`..\art\generated\sfx-pebbles\raw\metal\`:

| Store id | Name | Used as | SHA-256 |
|---|---|---|---|
| `9116698689` | "Metal Impacts 13": stabbing an interior vehicle floor, ringing | clank | `BA5F541EC8DD531A8477AFE4643048C01F5C8427AEBEA300BF12518474547E9B` |
| `9116698012` | "Metal Impacts 5": the same floor, clanking | clank | `14D374D6C3DC6C033A16B9995924AA79754B80ADB3D20DD23782EFD2B4D4C071` |
| `9116695441` | "Metal Impacts 4": the same floor, a duller hit | clank | `E65556E389D543A454A054B9141C1709A3885F7CD5F44C23DE5EB6A44BD97327` |
| `9116695715` | "Metal Impacts 6": the same floor, a light hit | ping | `8B8592CFD2C515977B9F948CF896DCD96BD52C87DB1C4E5FFC7287DF02AE2A65` |
| `9116701254` | "Metal Impacts 2": thin sheet metal, "bullet hitting vehicle body" | ping | `593472D545637095189F092A6CD406A1AC351D7157D7639263E647516E0D0048` |
| `9125464752`, `9125464768` | "Corrugated Roof Pounding Impacts On Thin Metal 2, 6": hollow clanking | clank | `414183C1A60E5AFA56E34CD112262F59BB091F0D06358B9DEEDEF9964623DB0C`, `C15A8EA72D4764A050C7CA1A438ACD44C4DFE937745053346D0F046B7D4B1539` |
| `9125596462` | "Hammer Soft Taps On Metal Roof Sharp Clinks 2" | ping | `9381485D2D2FE3DADE27EAD88955B89AD991185A470B8036E10B407B49CA61DD` |
| `9113106424`, `9113107643`, `9113107729` | "Ammo Shell Drop 2, 5, 7": small metal clinks | ping (F only) | `4B494F97C5597C1A381B24A424273DE5094676105F6BFC213137027FA027ED8B`, `2DDA649F367391A1B896848B5A4C13F7C935C9B3C28C8AC1A82124A3011CB711`, `38A213135293EDCDF9BBE32F0B61747FECE9C42667DF03A8A10066BF3BE0DDF9` |

Each hit is cut from its onset to where it has rung down 30 dB (pings at most 0.15 to 0.23 s, clanks
0.25 to 0.36 s); a slice that is still ringing louder than -10 dB there is dropped. Its last 50 ms
fade out (in game, the voice's volume ramps down over its last 50 ms), because a metal ring cut dead
clicks. The stream is up to **18 hits a second** at full speed on gravel (was 26: a ringing clank
is longer than a pebble tick), the same random pitch (0.85 to 1.2x) and loudness, over the same crunch
9 dB under. Previews: the same 10.5 s drive as round 1, level-matched on the gravel stretch.

| | What | Hits | Preview SHA-256 | Status |
|---|---|---|---|---|
| E | **Floor-pan clanks**: mostly the vehicle-floor and corrugated thin-metal clanks (half the hits), with a few light floor and body pings | 5 pings, 12 clanks | `68A15627A9F4D3EA9D5D40AFF3C8CC01176BE08E1B3EFB3C2E354B9638FF7778` | candidate |
| F | **Tinny pings**: mostly small sharp metal clinks (hammer taps on a metal roof, shell clinks, the body hit), one in five a floor-pan clank | 16 pings, 12 clanks | `96072051D4D585800ADD3438487983067088D0F4ED4715F8F11819F534F7FE51` | candidate |
| G | **Stones on steel, made by us**: 24 pings and 8 heavier clanks synthesized in code (`synth_hits.py`): a sub-millisecond stone contact burst exciting 14 damped inharmonic panel modes (900 to 7,500 Hz for pings, 180 to 3,500 Hz plus a 95 to 170 Hz box thunk for clanks), with a little grit. One in five a clank. Ours, no licence; **would need one upload** if picked | 24 pings, 8 clanks | `028E23404866DEF6FA572A7643F95832AFAAB085B1BF501CA01096714B475780` (sheet `93D21DE53B0E6705993F9FF948613DCF8D5014F42C93B51E6FCADD84A2386930`) | candidate |

## Looked at and left out

- **"Vehicle Gravel Tire Pass By Constant No Engine 1"** (`9126156741`): the same session as A, a
  little brighter and steadier; A was kept as the one to show.
- **"Vehicle Gravel Tire On Rocks Pass Bys"** (`9120381303` and its siblings): pass-bys, swelling in
  and out over 11 s, so no steady stretch to loop.
- **"1982 Diesel Dump Truck 1"** (`9112735339`): interior on a dirt road with ticking, but a truck's
  engine and cab rattle throughout.
- **One-shots too thuddy for a tick:** "Sand Impacts 7" (`9118768545`), "Dirt Impact 3"
  (`9114087322`), "Rocks Tumble ... Grit Scattering 13" (`9125884515`), "Metal Impacts 14"
  (`9116693332`, one big muted metal hit).
- **A synthesized tick set** (ours, which would need an upload): not made for this round; the store
  hits are real recordings and need nothing uploaded.
