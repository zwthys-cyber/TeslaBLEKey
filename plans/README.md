# Motion implementation plans

| Plan | Title | Severity | Status |
| --- | --- | --- | --- |
| 001 | Build a continuous vehicle stage | HIGH | DONE |
| 002 | Make every vehicle action causal | HIGH | DONE |
| 003 | Recompose the control surface | MEDIUM | DONE |
| 004 | Centralize the motion language | MEDIUM | DONE |

Recommended order: 004 establishes tokens; 001 builds the shared stage; 003 lays out the final surface; 002 connects command state and feedback last. All plans are based on commit `d2a3b09` and must be implemented together for the confirmed full redesign.
