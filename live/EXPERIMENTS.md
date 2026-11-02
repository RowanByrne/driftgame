# Experiments

This game's experiments, newest first: what was tested, what happened, and what was decided. How to run one is in docs/workflow/EXPERIMENTS.md.

| Experiment | Config key | Goal metric | Ran | Result | Decision |
|---|---|---|---|---|---|
| | | | | Significant / not significant / stopped | Control / variant |

Each experiment gets a section, in this form:

### <Experiment name>

- **Hypothesis:** what changes, what we expect to happen, and why.
- **Setup:** the config key, control and variant values, rollout, split, targeting, start and end dates.
- **Early harm:** anything flagged in the first 24 hours, and what was done.
- **Results:** the goal metric and any other significant changes, with their confidence intervals.
- **Decision:** what the user chose and why (also in `docs/game/DECISIONS.md`), and what changed in the configs.
- **Learned:** what this tells us for the next experiment.
