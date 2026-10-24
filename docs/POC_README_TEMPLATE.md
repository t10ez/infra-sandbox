# <poc-name>

<One sentence: what this builds and the question it answers.>

| | |
|---|---|
| Status | <Tested on floci / Tested on AWS / Design only> |
| Region | <region> |
| Services | <AWS services used> |
| Cost | <what it costs to run and what remains billable after teardown> |
| Date | <YYYY-MM-DD of the last test run> |

## Goal

<The question this POC answers, and what a good answer looks like. 2 to 4 lines.>

## Architecture

```mermaid
flowchart LR
    A["<component>"] --> B["<component>"]
```

## Flow

1. <Step, with the component that does it>
2. ...

<Add a sequenceDiagram when more than two parties exchange messages.>

<Failure paths: what happens when a step fails, and who retries.>

## Trade-offs and alternatives

One row per real decision. Say what was chosen, what was left out, and what the choice costs.

| Decision | Chosen | Alternatives | Trade-off |
|---|---|---|---|
| <what had to be decided> | <what this POC uses> | <other options> | <why chosen, and what it costs us> |

## Results

<Measured numbers with n, units and environment. A table. Mark anything estimated as estimated.>

## Findings and limitations

- **Found:** <things the test showed, including surprises>
- **Not tested:** <things this POC does not prove>
- **Unknown:** <open questions, with the cause marked unknown rather than guessed>

## Run

```bash
<deploy, test, teardown commands in order. Teardown is always the last step.>
```

## Files

| Path | Purpose |
|---|---|
| `terraform/` | <what it defines> |
| `scripts/` | <what they do> |
| `results/` | <raw data and generated reports> |

## Rules for this template

- Keep section order and names so POCs can be compared side by side.
- Numbers must be measured. If a number is an estimate or from memory, say so next to it.
- Every trade-off row names a cost. "Better" without a cost is not a trade-off.
- State what was not tested.
