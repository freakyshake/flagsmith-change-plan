# demo shop

Sample app used by the flagsmith-change-plan demo. The flags referenced here, and what the plan should say about each:

| Flag | Where | Expected plan |
|---|---|---|
| `new_checkout` | `src/checkout.js`, `src/cart.js`, CI gate in `.github/workflows/deploy.yml` | **HIGH** when disabled in Production |
| `express_pay` | `src/checkout.js` | co-located with `new_checkout` |
| `search_v2` | `src/search.js` + segment override | **MEDIUM** (override keeps its own state) |
| `holiday_banner` | `src/banner.js` | **LOW** in Development |
| `pricing_copy` | `src/banner.js` (multivariate) | `set-weights` demo |
| `old_onboarding` | not referenced | **LOW** archive |
| `cta_copy` | running experiment | **BLOCKED** |
