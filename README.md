# FIA 203 Corporate Finance

Interactive walkthroughs and activities for FIA 203 Corporate Finance-I, IMT Hyderabad.
Open `index.html` for the list of topics. Every page is a single HTML file with no build step. Students enter their ID once per browser.

| Module | Page | File |
|---|---|---|
| Start here | The Big Picture | `big-picture.html` |
| 1. Time Value of Money | Activity: Reading Cash Flows | `tvm-reading-cash-flows.html` |
| 2. Bond and Stock Valuation | Bond Valuation, Stock Valuation | `bond-valuation.html`, `stock-valuation.html` |
| 3. Capital Budgeting | Capital Budgeting, Project Cash Flows | `capital-budgeting.html`, `project-cash-flows.html` |
| 4. Risk and Return | Risk and Return | `risk-and-return.html` |
| 5. Cost of Capital | Cost of Capital | `cost-of-capital.html` |

Which topics students can open is controlled from `admin.html` (instructor in charge only). Instructors see their own sections at `faculty.html`. Student progress is stored in Supabase; the schema is in `database/schema.sql`. `assets/js/config.js` holds only the public project URL and publishable key. Never add the secret key to this repository.

To publish with GitHub Pages: Settings → Pages → Source: "Deploy from a branch" → Branch: `main`, folder `/ (root)`.
