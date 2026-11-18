# Akina Race Tape rank artwork

**Status** Built for lane review in T-319.

## How it plays

The live score panel shows the current rank as original Akina lettering. Each rank has a distinct palette and animated effect. The painted word and meter fill from the same drift progress. The whole word is unfilled at zero and charged at full. A two-screen-pixel highlight follows the advancing ink between the two endpoints. Drift scoring reaches ×9. Seven additional ranks appear in Studio fixtures.

## Art and motion

The art registry records the 16 palettes, matched image pairs, frame periods, still frames and special faces. The approved PNGs, hashes, creator, asset IDs and measured Roblox bounds are in the [art manifest](../../../assets/score-ranks/MANIFEST.md). Lettering preserves its full registered canvas. The effect sheets follow the same center, scale and frame as their foreground prints.

BOOSTED’s dark matte separates its letters from the teal exhaust. FULL SEND’s scarred face tilts at the D as a spark moves through the word to the F. OVERDRIVE keeps the turbine seated inside the O and charges the blades at the letter boundary. Four paired flames burn behind the UNTOUGEABLE cutout. Reduced Motion holds each signature on its approved still and skips the entry, wall movement and embers.

## Studio review

Start an endless run to see the art against the road. Press **]** to play all 16 ranks, 1.45 seconds each. The tour shows an empty, charging and full word for each rank. Press **]** again to return early. Driving and scoring continue during the preview.

For a single rank, use Studio’s **Client** command bar during Play. The example selects FULL SEND at 50 percent. Change the rank from 1 to 16 and the charge from 0 to 1.

```luau
game.Players.LocalPlayer.PlayerScripts.DebugBridge:Invoke("ScoreController", "DebugRank", 10, .5)
```

`DebugFeedMotion(true)` holds the reduced-motion pose. `DebugFeedMotion(nil)` follows the player’s preference again. `DebugFixture(nil)` hands the HUD back to the current run. Named fixtures `rank01` through `rank16` each open at half charge.
