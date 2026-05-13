# [BRAND] — Pre-MVP Marketing Site

A dark, deliberately quiet marketing site for a pre-MVP smart-switch
company. Built per `docs/Website_Build_Brief_for_Agent.md`: single-page
narrative plus four thin sub-routes, custom motion choreography, no stock
imagery, one custom inline SVG schematic, single accent colour used
sparingly. Stack: Next.js 14 (App Router) + TypeScript + Tailwind CSS +
Framer Motion.

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

## Project structure

```
app/
├── layout.tsx                 # Root layout: fonts, nav, footer, modal provider, SEO
├── page.tsx                   # Main single-page composition
├── installers/                # Electrician-facing landing page
├── press/                     # Press kit
├── privacy/                   # Privacy boilerplate (TODO: legal review)
├── terms/                     # Terms boilerplate (TODO: legal review)
├── api/waitlist/              # Stubbed waitlist submission
├── api/installer-interest/    # Stubbed installer interest submission
└── globals.css                # CSS variables, base styles, grain texture, gridlines
components/
├── layout/                    # Nav, Footer, ScrollProgress
├── sections/                  # Hero, Problem, Approach, Audiences, Team
├── ui/                        # Button, EyebrowLabel, RevealText, SectionNumber, WaitlistModal
└── illustrations/HeroSchematic.tsx   # The signature inline SVG
lib/
├── motion.ts                  # Shared Framer Motion variants and easings
└── utils.ts                   # cn() helper
```

## Placeholders to replace before launch

Search the codebase (`grep -r "TODO" .` and `grep -rE "\[BRAND\]|\[CITY\]|\[Founder Name\]|\[Role\]" .`) and replace each of the following before going public:

- **`[BRAND]`** — every literal occurrence in copy, metadata, `<title>`,
  Open Graph tags, and the wordmark in `Nav.tsx` / `Footer.tsx`.
- **`[CITY]`** — the founders' city in `Team.tsx` and `press/page.tsx`.
- **Founder details** in `components/sections/Team.tsx` and
  `app/press/page.tsx`: real names, roles, bios, and monogram initials.
- **Email domains** in `mailto:` links across the site: replace `brand.com`
  with the real domain in `Hero.tsx`, `Audiences.tsx` (builders),
  `Team.tsx` (hello / investors / press), `Footer.tsx` (careers /
  investors), `WaitlistModal.tsx`, `privacy/page.tsx`, `terms/page.tsx`.
- **`/public/og-image.jpg`** — 1200×630 Open Graph / Twitter card image
  (referenced in `app/layout.tsx` metadata).
- **Brand assets** linked from `/press`: place real wordmark files at
  `/public/brand/wordmark.{svg,png,pdf}`.
- **Legal copy** in `app/privacy/page.tsx` and `app/terms/page.tsx`
  (marked with `// TODO: replace with content reviewed by counsel`).
- **Social URLs** in `components/layout/Footer.tsx` (X/Twitter, LinkedIn).
- **Canonical / metadataBase URL** in `app/layout.tsx` —
  currently `https://brand.com`.
- **`/api/waitlist` and `/api/installer-interest`** — both currently log
  to the server console and return `{ ok: true }`. Wire them up to a real
  backend (Resend, Loops, Airtable, a CRM, etc.). Marked
  `// TODO: connect to real backend`.
- **Cookie consent banner** — explicitly out of scope per the brief;
  evaluate before public launch.

## Deployment (Vercel)

Push the repo to GitHub and import it in the Vercel dashboard. Vercel auto-detects Next.js — no config required. Set the production domain, point DNS, and add any environment variables once the waitlist and installer-interest endpoints are wired to a real backend. Each push to the configured production branch triggers a deploy.

## Design notes

This site is intentionally quiet. The aesthetic is "late-night editorial
meets industrial precision": dark background, warm off-white type,
generous negative space, one warm-copper accent (`#D97757`) used like
punctuation — never on body text, never as a large fill. If you find
yourself wanting to add a second colour, a hero photo, a "Trusted by"
logo row, or a punchier "Get Started" button, stop. The discipline is the
point. Animations are slow and decelerating (a single shared cubic-bezier
`(0.22, 1, 0.36, 1)`); nothing wobbles or bounces. New decorative
elements should be inline SVG built from straight lines and small
circles, in the spirit of the existing `HeroSchematic`. The accent should
appear on roughly 5–7 elements when the whole page is scrolled — count
before adding more.

Fonts are pinned: **Fraunces** (display), **Geist Sans** (body), **JetBrains Mono** (eyebrows / labels). Do not substitute Inter, Roboto, or Space Grotesk.
