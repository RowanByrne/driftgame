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
| A | **Gravel crunch loop**: a tyre rolling over gravel, recorded outside, no engine. One loop, its volume and playback speed following road speed | `9126157118` "Vehicle Gravel Tire Pass By Constant No Engine 2", region 6.5 to 17.5 s | `6C499F509DEF4334B9FA2BC3B373ED3D07602184FD0B21BFE3A185A5FFC8ADEF` | candidate |
| B | **Over rocks, from inside**: tyres crunching over rocks recorded inside a car, so the stones hitting the floor pan are in it. Has the recording car's engine, low-cut out | `9126157444` "Vehicle Gravel Tires Crunch Constant Over Rocks 1", region 1.5 to 12.5 s | `96F7FA41A99FF6DE15C6ABBC6260439C1968BB9C876A14D38E643A8447A2705C` | candidate |
| C | **Pebble ticks**: built in code from 40 single stone hits (35 pebble ticks, 5 heavier clacks) cut from store one-shots, fired at random, each at a random pitch (0.85 to 1.2x) and volume; how many a second follows speed, surface and slide (up to about 45 a second sliding fast on gravel). Never loops | `9117266254`, `9117266257`, `9117266265`, `9117266497` ("Pebble Drop Roll Stone Impact On Concrete 1 to 4"); `9118624159`, `9118624415`, `9118624423`, `9118624649`, `9118624847` ("Rock Impacts 1, 2, 3, 6, 8") | `6698F9E2684FD130D8BD85DD0AD6D8CE320C274EF4B3F80C5654F65CDB2B911B` | candidate |
| D | **Ticks over crunch**: C on top of A, with A 9 dB under the ticks | as A and C | `9256A6B176E5A89AB04C6F139B13AF1CB458DAF9850431E2EB5076B5AF193939` | candidate |

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
