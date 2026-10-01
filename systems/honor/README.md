# Honor (Enech)

Brehon-law honor / reputation. Runtime API: `scripts/autoload/honor.gd`.

- Per-faction table + overall standing (0..100)
- Law / dialogue gates (data-side):
  - `can_choose_eraic()` — min honor to offer/accept éraic
  - `can_claim_sanctuary()` — Church or overall threshold
  - `available_law_options()` — list open options for dialogue UI later
- Significant honor swings emit rumors via the Rumors bus
