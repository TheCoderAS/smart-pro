# Unisync — Marketing Site

A dark, deliberately quiet marketing site for Unisync, a pre-launch smart-switch
company in Bangalore. Built per `docs/Website_Build_Brief_for_Agent.md` (the
visual / IA brief) and amended per Unisync's change request: rebrand to Unisync,
new Product section explaining the master + extension + mesh architecture, inline
waitlist form replacing the modal, contact email rewires, and the team section
removed until founder names are public.

Stack: Next.js 14 (App Router) + TypeScript + Tailwind CSS + Framer Motion.

## Setup

```bash
pnpm install
pnpm dev
```

The site runs at <http://localhost:3000>.

Other scripts:

```bash
pnpm build    # production build (also runs typechecking)
pnpm start    # serve the production build
pnpm lint     # next lint
```

## Page composition

```
/  (single-page narrative, scrolls top to bottom)
   Hero
   01 — The problem
   02 — The product           (architecture diagram + sub-bullets)
   03 — Our approach           (4 pillars: Networked / Local / Open / Installers)
   04 — Built for              (Homeowners / Electricians / Builders)
   Waitlist                    (id="waitlist", inline form + reach-us-directly)

/installers  — electrician-facing landing page
/press       — press kit
/privacy     — privacy boilerplate (TODO: legal review)
/terms       — terms boilerplate (TODO: legal review)
```

## Project structure

```
app/
├── layout.tsx                 # Root layout: fonts, nav, footer, motion config, SEO
├── page.tsx                   # Main page composition
├── installers/                # Sub-route
├── press/                     # Sub-route
├── privacy/                   # Sub-route (legal placeholder)
├── terms/                     # Sub-route (legal placeholder)
├── api/waitlist/              # Stubbed waitlist endpoint
├── api/installer-interest/    # Stubbed installer-interest endpoint
└── globals.css                # CSS variables, base styles, grain, gridlines
components/
├── layout/                    # Nav, Footer, ScrollProgress, ReducedMotionProvider
├── sections/                  # Hero, Problem, Product, Approach, Audiences, Waitlist
├── ui/                        # Button, EyebrowLabel, RevealText, SectionNumber
└── illustrations/             # HeroSchematic + ArchitectureDiagram (Product section)
lib/
├── motion.ts                  # Shared Framer Motion variants and easings
└── utils.ts                   # cn() helper
```

## Placeholders to replace before launch

Search the codebase (`grep -r "TODO" .`) and replace each of the following before going public:

- **`unisync.in` domain** — assumed-available throughout. If `.in` turns out
  to be unavailable when the domain is registered, fall back to `getunisync.in`
  or `unisync.app` and find/replace globally. Currently set in `app/layout.tsx`
  (`metadataBase`, canonical, `og:url`).
- **`aalokmamtasah@gmail.com`** — currently the single contact address
  everywhere. Replace with dedicated mailboxes (`hello@`, `investors@`,
  `press@`, `careers@`, `builders@`) once the domain is live and inboxes
  are set up. Search-and-replace, then split per intent. Subject prefixes
  (`?subject=Investors`, `?subject=Press`, etc.) on the "Or reach us
  directly" block let visitors self-identify in the meantime.
- **`/public/og-image.jpg`** — 1200×630 Open Graph / Twitter card image.
  Brief: off-white background, centred Unisync wordmark in navy, tagline
  ("The wall should be smarter than the bulb.") below in muted type, a soft
  product photo cropped to the right third.
- **Brand assets** linked from `/press` — replace the placeholder
  `wordmark.svg` at `public/brand/wordmark.svg` with the real wordmark
  (and add `wordmark.png` and `wordmark.pdf` so the "Coming soon" rows
  flip to live downloads).
- **Founders / team** — currently omitted from the homepage entirely. The
  `/press` page still uses `[Founder Name]` / `[Role]` placeholders for
  the founder cards; replace once names are public.
- **Legal copy** in `app/privacy/page.tsx` and `app/terms/page.tsx`
  (marked `// TODO: replace with content reviewed by counsel`).
- **Social URLs** in `components/layout/Footer.tsx` — currently
  `https://instagram.com/unisync.in`, `https://youtube.com/@unisync`,
  `https://linkedin.com/company/unisync` (placeholders; the `@unisync`
  handle on Instagram/X is squatted, so confirm what's actually
  reachable).
- **`/api/waitlist`** — currently logs `{ email, city, role }` to the
  server console and returns `{ ok: true }`. Wire up to a real backend
  (Resend, Loops, Airtable, Tally, Google Forms — whichever is fastest).
- **`/api/installer-interest`** — same shape, same TODO.
- **Cookie consent banner** — explicitly out of scope; evaluate before
  public launch.

## Deployment (Vercel)

Push the repo to GitHub and import it in the Vercel dashboard. Vercel
auto-detects Next.js — no config required. Set the production domain
(`unisync.in`), point DNS, and add any environment variables once the
waitlist and installer-interest endpoints are wired to a real backend.
Each push to the configured production branch triggers a deploy.

## Design notes

This site is intentionally quiet. The aesthetic is "late-night editorial
meets industrial precision": dark background, warm off-white type,
generous negative space, one warm-copper accent (`#D97757`) used like
punctuation — never on body text, never as a large fill. If you find
yourself wanting to add a second colour, a hero photo, a "Trusted by"
logo row, or a punchier "Get Started" button, stop. The discipline is the
point.

Animations are slow and decelerating (a single shared cubic-bezier
`(0.22, 1, 0.36, 1)`); nothing wobbles or bounces. New decorative
elements should be inline SVG built from straight lines and small
circles, in the spirit of `HeroSchematic` and `ArchitectureDiagram`.
The accent should appear on roughly 5–7 elements when the whole page is
scrolled — count before adding more.

CSS color tokens are defined in two forms in `app/globals.css`:
the hex form (`--accent`) for direct CSS use (e.g. `fill="var(--accent)"`)
and the rgb-channels form (`--accent-rgb`) consumed by Tailwind via
`rgb(var(--x-rgb) / <alpha-value>)` so opacity modifiers (`bg-bg/70`,
`text-fg-faint/20`) work correctly. Don't drop one form thinking it's
unused — both are needed.

Fonts are pinned: **Fraunces** (display), **Geist Sans** (body),
**JetBrains Mono** (eyebrows / labels). Do not substitute Inter, Roboto,
or Space Grotesk.
