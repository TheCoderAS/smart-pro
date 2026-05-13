# [BRAND] Pre-MVP Website — One-Shot Agent Build Brief

> **For the agent reading this:** you are building a complete, deployable, production-grade marketing site end-to-end in a single working session. This brief gives you everything: the strategy, the content, the visual direction, the technical stack, the file structure, the animations, and the success criteria. You should not ask clarifying questions before building. Where this brief leaves room for creative judgement, exercise it boldly — but stay inside the constraints. Bias toward shipping.

---

## 1. Project at a glance

| Field | Value |
|---|---|
| Project name | `[BRAND]` (placeholder — use `[BRAND]` as the literal token throughout; the human will find-and-replace later) |
| Stage | Pre-MVP, pre-seed |
| Primary goal | Attract pre-seed investors and high-quality recruits |
| Secondary goal | Build a segmented waitlist of homeowners and electricians |
| Reveal level | **Stealth-ish** — vision and principles only; no specs, BOM, prices, dates, or technical jargon |
| Aesthetic | Stealth visual (dark, mysterious, premium) with rich, intentional animation |
| Stack | Next.js 14+ (App Router) + Tailwind CSS + Framer Motion + TypeScript |
| Deliverable | Fully built repo, locally runnable with `npm install && npm run dev`, ready to deploy to Vercel |
| Out of scope | CMS, backend, real form submission backend (use a stubbed API route), blog, multi-language |

---

## 2. Strategic frame — read this before writing a single line of code

`[BRAND]` makes smart electrical switches for Indian homes. The technical insight (one smart hub per switchboard, simple snap-on extensions for the rest; mesh across the home; works fully without internet) is the company's moat. **None of that vocabulary appears on the site.** Investors and recruits will get a deck or a conversation; this site exists to make them *want* the deck or the conversation.

The site is doing two jobs at once:

1. **Convince a sophisticated investor in 30 seconds** that the founders have taste, have thought hard, and are building something with category-defining ambition.
2. **Earn an email from a homeowner or electrician** who knows nothing about hardware architecture but recognises the problem the moment it's named.

Both audiences are served by the same content if the writing is good. Investors read further. Consumers convert at the first CTA. Do not split into two flows.

### What "stealth-ish + rich animation" means in practice

Stealth here is **tonal**, not literal. The site should feel like a luxury watchmaker's teaser site or the pre-launch site of a well-funded hardware company (think early Humane, Rabbit before it shipped, or pre-launch Nothing). It is dark, deliberate, confident, and quiet — but it is not empty or boring. The animations carry the weight that product imagery would normally carry. Every motion is intentional; nothing moves just because it can.

**This is the single most important aesthetic call:** restraint at rest, drama in motion. The page should look almost still at first glance, then reveal itself through interaction.

---

## 3. Information architecture

A single scrolling page with five sections, plus three thin sub-routes. Do not build a multi-page site. The flow is linear and the user should be able to consume the whole thing in under 90 seconds.

### Main page (`/`) — sections in order

1. **Hero**
2. **The Problem**
3. **The Approach**
4. **Who It's For** (three tracks)
5. **Team & Contact**

### Sub-routes (lightweight)

- `/installers` — landing page for electricians, deeper "what's in it for me"
- `/press` — boilerplate, logos, founder bios, contact email
- `/privacy` and `/terms` — standard legal boilerplate (use generic templates; mark with a `TODO: replace with lawyer-reviewed version` comment)

### Global elements

- Fixed thin top nav (logo wordmark left, three nav anchors center, "Get Early Access" CTA right). Becomes more opaque on scroll.
- Footer with logo, four link columns (Product, Company, Resources, Legal), small print, social icons.

---

## 4. Content — write it exactly like this

Tone: confident, calm, slightly literary. Sentences are short. No exclamation marks anywhere. No emoji. No buzzwords ("revolutionary", "disrupt", "next-gen", "AI-powered"). The word "smart" is allowed but used sparingly — preferably no more than three times on the whole page.

### 4.1 Hero

**Eyebrow** (small, monospace, top of section):
> A new kind of electrical switch. Coming to India, 2026.

**Headline** (massive, the centerpiece of the page):
> The wall should be smarter than the bulb.

**Subhead** (one line, supporting):
> We are rebuilding the most-touched object in your home, from the inside out.

**Primary CTA:** `Request early access`
**Secondary CTA:** `For investors →` (subtle, text-only, links to mailto or a quiet anchor)

### 4.2 The Problem

**Section eyebrow:** `01 — The problem`

**Section headline:**
> Smart switches today are neither.

**Body** (three short paragraphs, displayed as a vertical list with generous spacing):

> The expensive ones cost as much as a phone, for a switch. The cheap ones stop working when a Chinese server goes dark.

> Both require an electrician for a day, a re-wiring of the board, and a bet that the company that sold it to you will still exist in three years.

> Most of them, in most homes, end up on a manual override within a month. Not because the technology failed. Because the product was never made for the way people actually live.

### 4.3 The Approach

**Section eyebrow:** `02 — Our approach`

**Section headline:**
> Built like infrastructure. Priced like a switch.

**Body** (one paragraph, then four principle cards):

> We started with a question no incumbent has answered: what if a smart switch felt exactly like a normal switch — and a normal switch was the smart one?

Four principles (each is a card with a small numeric label, a 2–4 word title, and a 1–2 sentence body):

| # | Title | Body |
|---|---|---|
| i | Local first | If your internet dies, your lights do not. Everything that matters works without us. |
| ii | Open by default | Your switches should work with whatever app, voice, or system you already use. Not just ours. |
| iii | Built for installers | The person fitting it to your wall is our customer too. We design for the ladder, not just the couch. |
| iv | Honest hardware | Mains voltage deserves engineering discipline, not consumer-electronics corner-cutting. We over-build, on purpose. |

### 4.4 Who It's For

**Section eyebrow:** `03 — Built for`

**Section headline:**
> Three people. One product.

Three vertical cards, each a separate hover-reactive panel.

**Card 1 — Homeowners**
> Subtitle: For the home you're actually building
> Body: Whether you're renovating one room or wiring a new flat, the system that runs your lights should not feel like a project. It should feel like furniture.
> CTA: `Join the waitlist →`

**Card 2 — Electricians**
> Subtitle: For the professional on the ladder
> Body: Fits the boards you already install. Trains in a day. Earns more per fit. We build the product; you build the network.
> CTA: `Become a partner →` (links to `/installers`)

**Card 3 — Builders & Developers**
> Subtitle: For the people specifying tomorrow's homes
> Body: A standardised, certifiable, repairable switching system designed for the realities of Indian construction at scale.
> CTA: `Talk to us →` (mailto link)

### 4.5 Team & Contact

**Section eyebrow:** `04 — The team`

**Section headline:**
> Built by people who have done this before.

**Body** (one paragraph):
> We are a small team of hardware, firmware, and design people based in [CITY — placeholder]. We have shipped products to millions of homes, certified electronics in three regions, and spent more time than we will admit talking to electricians about why their last smart switch ended up in a drawer.

**Three founder placeholder cards** — each with: monogram avatar (use first initial in serif type on a coloured circle), name placeholder (`[Founder Name]`), role placeholder (`[Role]`), one-line bio placeholder.

**Closing block:**
> Headline: `Want to talk?`
> Three contact lines (each a discreet email link):
> - For early access: `hello@[brand].com`
> - For investors: `investors@[brand].com`
> - For press: `press@[brand].com`

### 4.6 Footer

- Wordmark + tagline: `The wall should be smarter than the bulb.`
- Four columns:
  - **Product:** Overview, Installers, Early access
  - **Company:** Team, Press, Careers (link to `mailto:careers@[brand].com`)
  - **Resources:** FAQ (anchor), Updates (waitlist), Investors (mailto)
  - **Legal:** Privacy, Terms
- Bottom line: `© 2026 [BRAND]. Made in India.` (lowercase the period after India for stylistic consistency — `Made in India` with no period)
- Small social icons: Twitter/X, LinkedIn (placeholder hrefs)

---

## 5. Visual design system

### 5.1 The big aesthetic decision

**Direction:** Late-night editorial meets industrial precision. Imagine the print catalogue of a Japanese product company, photographed at 2am, redesigned for the web. Generous negative space. Heavy use of fine rules and small mono labels. One single accent colour, used like punctuation.

### 5.2 Colour palette

Use CSS custom properties. **Dark by default, no light mode toggle in v1.**

```
--bg:            #0A0A0B   /* near-black, faintly warm */
--bg-elevated:   #111113   /* card backgrounds, nav-on-scroll */
--bg-subtle:     #16161A   /* hover surfaces */
--fg:            #F4F2EE   /* primary text, off-white with warmth */
--fg-muted:      #8A8780   /* secondary text, captions */
--fg-faint:      #44423E   /* tertiary, fine rules, dividers */
--accent:        #D97757   /* warm copper — used SPARINGLY */
--accent-glow:   rgba(217, 119, 87, 0.15)  /* for glows and washes */
--grain-opacity: 0.04      /* subtle film grain overlay opacity */
```

**Rules of accent use:**
- Accent appears on: primary CTA, the active nav indicator, one ornamental element per section, link hover states.
- Accent NEVER appears on: body text, headlines, large fills.
- The site, scrolled top to bottom, should contain visible accent on maybe 5–7 elements total. Less is more.

### 5.3 Typography

Pick fonts that are **not** Inter, Roboto, or Space Grotesk. Use these specifically:

- **Display (headlines):** `Fraunces` (serif, variable, free on Google Fonts). Optical size 144 for largest, 72 for section headers. Slightly soft, modern serif with character.
- **Body & UI:** `Geist Sans` (free, Vercel). Clean but not generic.
- **Mono (eyebrows, labels, numerics):** `JetBrains Mono` (free). Used at small sizes for eyebrow labels and section numbering.

Type scale (responsive, use clamp):

```
--text-hero:    clamp(3.5rem, 9vw, 8rem)     /* hero headline */
--text-h1:      clamp(2.5rem, 6vw, 5rem)     /* section headlines */
--text-h2:      clamp(1.75rem, 3vw, 2.5rem)  /* card titles */
--text-body-lg: clamp(1.125rem, 1.5vw, 1.5rem)  /* lead paragraphs */
--text-body:    1rem                          /* regular body */
--text-sm:      0.875rem                      /* captions */
--text-xs:      0.75rem                       /* eyebrows */
```

Tracking:
- Display: -0.02em (tight)
- Body: 0 (default)
- Mono eyebrows: 0.15em (wide), uppercase

Line height:
- Display: 1.0–1.05
- Body: 1.6

### 5.4 Spacing and rhythm

8px base. Section vertical padding minimum `clamp(6rem, 12vw, 12rem)` top and bottom. **Be generous.** This is a site that should breathe.

### 5.5 Layout

Max content width: 1280px. Inner content gutter on desktop: 96px each side. On mobile: 24px.

Use a 12-column grid for sections that need it. Most sections use asymmetric layouts — headline on one side, body on the other, with intentional misalignment to a strict baseline.

Fine 1px rules (`--fg-faint`) separate sections horizontally where appropriate. Never use boxy borders around cards — favour open layouts with whitespace as the boundary.

### 5.6 Imagery

**Zero photographs. Zero stock imagery. Zero icon libraries.** The site has no product yet, and stock looks fake.

What you will create instead:

- **One signature SVG illustration in the hero**: an abstract, line-art representation of a switchboard with subtle indication of "master and extension" architecture — geometric, mostly negative space, ~70% of viewport height. Render this as inline SVG with animatable paths. The drawing should look like a precise technical schematic from a beautiful product manual. No labels or text on the illustration.
- **Geometric ornaments:** thin lines, dots, small circles arranged in patterns at section transitions.
- **Numeric typography** as decoration — large faded section numbers (`01`, `02`, `03`) as background elements behind section content.
- **A subtle film grain overlay** across the whole page (CSS noise texture or tiny tiled SVG noise).

### 5.7 Background atmosphere

The body background is not flat. Layer the following:

1. Base colour `--bg`.
2. A very subtle radial gradient from top-left, fading from `var(--accent-glow)` to transparent — barely visible, sets a "light source" mood.
3. The film grain overlay on top.
4. A faint vertical line pattern (every 96px, 1px wide, `--fg-faint` at 30% opacity) visible only at large viewport widths — a gridline reference, like architectural drafting paper.

---

## 6. Motion design

This section gets the most ink because animations are the centerpiece. Every motion choice listed here is required.

### 6.1 Motion principles

- **Restraint at rest, drama in motion.** Nothing animates idly. The page should feel almost still when not being interacted with.
- **Slow is sophisticated.** Default durations 400–800ms. Hero entrance animations 1000–1600ms. Never use bouncy easing.
- **Easing:** use a custom cubic-bezier — `cubic-bezier(0.22, 1, 0.36, 1)` (a smooth, decelerating curve). Define as a Framer Motion variant called `smooth`.
- **Stagger, don't pile on.** When multiple elements enter, stagger them by 60–120ms. The eye should be able to follow the order.
- **Respect `prefers-reduced-motion`.** Disable all entrance and decorative animations for users who request it; keep only essential transitions (hover state changes, modal opens).

### 6.2 Hero entrance sequence (on page load)

This is the showcase moment. Choreograph it carefully:

```
T+0ms      Background grain and vertical-line pattern fade in (1200ms)
T+200ms    Top nav fades down from -16px (800ms)
T+400ms    Eyebrow line types in character-by-character (~600ms total)
           OR fades up with a slight blur clearing (whichever is cleaner)
T+800ms    Hero headline reveals — split into words, each word fades up
           and de-blurs with 80ms stagger. The whole headline takes ~1200ms to complete.
T+1600ms   Subhead fades in (600ms)
T+2000ms   CTAs fade in, primary first, secondary 100ms behind (600ms each)
T+2200ms   Signature SVG illustration begins line-drawing animation:
           paths are stroke-dashed and animate stroke-dashoffset from full to 0
           over 2400ms. Lines appear to be drawn by hand.
```

### 6.3 Scroll-triggered reveals

Every section animates in when it enters the viewport. Use Framer Motion's `whileInView` with `viewport={{ once: true, margin: "-100px" }}`.

**Standard section reveal:**
- Section eyebrow fades up with a slight upward translate (16px → 0) over 800ms.
- Section headline reveals word by word, with the same blur-clear + fade-up effect as the hero, 60ms stagger.
- Body content fades up with a 200ms delay after the headline.
- Any decorative element (like the giant background section number) fades in last, very slowly (1200ms).

### 6.4 The big numeric section markers

Each section is labeled with a giant faded number in the background (`01`, `02`, `03`, `04`). These should:

- Be `clamp(12rem, 25vw, 24rem)` tall.
- Be positioned absolutely in the section, off to one side, partially clipped by the section edge.
- Use Fraunces in light weight, colour `--fg-faint` at 20% opacity.
- **Parallax-scroll slower than the rest of the page** (translateY on scroll, ~0.3x the scroll velocity). This is a key motion signature.

### 6.5 The signature SVG illustration

Build one custom SVG inline in the hero. Design parameters:

- A composition of clean geometric lines representing an abstract switchboard — but read more as architectural drafting than as a literal switch.
- 8–14 stroked paths, all using `stroke="currentColor"`, no fills.
- One small filled circle in the composition, in `--accent` — the only colour in the illustration. Treat it like a single LED indicator. It pulses gently (opacity 1.0 → 0.5 → 1.0 over 3s, infinite).
- On page load, paths animate by stroke-dashoffset over 2400ms in a deliberate order (start with the outermost, work inward).
- On scroll, the entire illustration parallaxes upward slightly (translateY on scroll, ~0.15x scroll velocity).

### 6.6 Hover and micro-interactions

- **Primary CTA button:** on hover, the button background fills from left to right with accent colour over 400ms; text colour shifts from `--fg` to `--bg`. On click, brief 80ms scale down to 0.97.
- **Text links:** underline on hover, but the underline animates in from left to right over 300ms (use a pseudo-element with transform-origin).
- **Persona cards (homeowners/electricians/builders):** on hover, the card subtly lifts (translateY -4px) and a thin accent line draws across the top of the card (animating from 0 to full width over 500ms).
- **Nav links:** on hover, a small accent dot appears next to them (scale 0 → 1, 300ms).
- **Cursor:** consider a custom cursor — small dot following the cursor with a slight delay (using requestAnimationFrame lerp). This is optional; only include if it does not feel gimmicky in your final build. If unsure, skip it.

### 6.7 Scroll-based progress

A 1px-thin accent-coloured progress bar fixed at the top of the viewport, growing from 0% to 100% as the user scrolls the page. Subtle but premium.

### 6.8 Waitlist form interaction

When the user clicks the primary CTA, do not navigate. Open a focused modal with:

- A backdrop that fades in (800ms) with a slight backdrop blur.
- The modal scales up from 0.96 to 1.0 while fading in (500ms).
- A single email input with a label that floats up when focused.
- A radio group: "I'm a... Homeowner / Electrician / Builder / Investor / Other"
- A submit button styled identically to the primary CTA.
- On submit: form fades out, replaced by a confirmation message (`Thank you. We'll be in touch when there's something worth saying.`) with a checkmark icon that draws itself in.

The form posts to a stubbed Next.js API route at `/api/waitlist` that logs to the server console and returns 200. Mark this clearly with a `TODO: connect to real backend` comment.

---

## 7. Technical specification

### 7.1 Stack and versions

- Next.js 14 or 15, App Router, TypeScript
- React 18+
- Tailwind CSS 3.4+ (configure custom theme tokens matching section 5.2)
- Framer Motion (latest)
- `clsx` and `tailwind-merge` for class composition
- Lucide React for any tiny utility icons (chevrons, X for modal close). **Do not** use Lucide for decorative icons; build those as inline SVG.
- No CMS, no headless backend, no auth.

Fonts loaded via `next/font/google` for performance.

### 7.2 File and folder structure

```
[brand]-site/
├── app/
│   ├── layout.tsx                  # Root layout, fonts, global background
│   ├── page.tsx                    # Main single-page composition
│   ├── installers/page.tsx         # /installers
│   ├── press/page.tsx              # /press
│   ├── privacy/page.tsx            # /privacy
│   ├── terms/page.tsx              # /terms
│   ├── api/waitlist/route.ts       # Stubbed waitlist endpoint
│   └── globals.css                 # CSS variables, base styles, grain texture
├── components/
│   ├── layout/
│   │   ├── Nav.tsx
│   │   ├── Footer.tsx
│   │   └── ScrollProgress.tsx
│   ├── sections/
│   │   ├── Hero.tsx
│   │   ├── Problem.tsx
│   │   ├── Approach.tsx
│   │   ├── Audiences.tsx
│   │   └── Team.tsx
│   ├── ui/
│   │   ├── Button.tsx
│   │   ├── EyebrowLabel.tsx
│   │   ├── SectionNumber.tsx       # The giant parallax background number
│   │   ├── RevealText.tsx          # Word-by-word reveal animation
│   │   ├── WaitlistModal.tsx
│   │   └── GrainOverlay.tsx
│   └── illustrations/
│       └── HeroSchematic.tsx       # The signature SVG with line-draw animation
├── lib/
│   ├── motion.ts                   # Shared Framer Motion variants & easings
│   └── utils.ts                    # cn() helper, etc.
├── public/
│   └── fonts/                      # If self-hosting any fonts
├── tailwind.config.ts
├── next.config.js
├── tsconfig.json
├── package.json
└── README.md                       # See section 9 for required README contents
```

### 7.3 Tailwind config requirements

Extend the theme to expose:
- Custom colours mapped to the CSS variables (`bg`, `bg-elevated`, `fg`, `fg-muted`, `fg-faint`, `accent`, etc.)
- Custom fonts (`display`, `sans`, `mono`)
- Custom easing utility (`ease-smooth`)
- Custom font sizes from the type scale

### 7.4 Performance and quality bars

- Lighthouse Performance ≥ 90 on desktop, ≥ 85 on mobile.
- Lighthouse Accessibility ≥ 95.
- No layout shift on font load (use `font-display: swap` with size-adjust).
- All animations run on `transform` and `opacity` only — no animating `width`, `height`, `top`, `left`.
- Images: only the SVG illustration, inlined. No external image requests.
- Total bundle size on initial load: under 200KB gzipped (excluding fonts).

### 7.5 Responsive breakpoints

- Mobile: 0–767px (default, build for this first)
- Tablet: 768–1023px
- Desktop: 1024–1439px
- Large desktop: 1440px+

The hero must look intentional on a 375px iPhone screen. The huge background section numbers should scale down dramatically on mobile (clamp handles this).

### 7.6 Accessibility

- All interactive elements reachable by keyboard.
- Focus rings: visible 2px solid `--accent` outline with 4px offset.
- Modal traps focus while open, returns focus to trigger on close, closes on Escape.
- All images and SVGs have proper `aria-hidden` (decorative) or `aria-label` (meaningful).
- Heading hierarchy is strict: one `h1` on the page (the hero headline), then `h2` per section, then `h3` for cards.
- Colour contrast: body text on background passes WCAG AA at minimum.

### 7.7 SEO and metadata

In `app/layout.tsx` set:
- `<title>[BRAND] — The wall should be smarter than the bulb.</title>`
- Meta description: `[BRAND] is rebuilding the most-touched object in your home, from the inside out. A new kind of electrical switch, coming to India in 2026.`
- Open Graph tags (image is a `TODO: add og-image.jpg` placeholder)
- Twitter card metadata, same content
- `robots: index, follow`
- Canonical URL placeholder `https://[brand].com`

---

## 8. Sub-routes — quick specs

### `/installers`

A focused page for electricians. Same dark aesthetic, but with slightly more warmth (one extra accent ornament). Sections:

1. **Hero:** `The smart switch your customer won't return.` Body: one paragraph on the problem electricians face — sketchy products, callbacks, lost reputation.
2. **What's in it for you:** three cards (Earn more per fit · Trains in a day · Backed by support that picks up). No specific numbers (stealth).
3. **What we're looking for:** one paragraph on the partner profile.
4. **CTA:** A single form — name, city, years of experience, phone, message. Submits to `/api/installer-interest` (stubbed).

### `/press`

Single-screen page. Sections:

1. Boilerplate paragraph (`[BRAND] is a pre-launch hardware company based in India...`)
2. Founder placeholders (same three cards as on the main page, slightly expanded)
3. Brand assets: logo wordmark in three formats (links to placeholder downloads — mark as TODO)
4. Press contact email

### `/privacy` and `/terms`

Generic boilerplate templates. Wrap in the same layout. Mark clearly with a comment:
```
// TODO: replace with content reviewed by counsel before public launch
```

---

## 9. README requirements

Generate a `README.md` at the project root with:

1. One-paragraph project description.
2. Setup commands (`pnpm install`, `pnpm dev`).
3. List of placeholder values that the human must replace before going live:
   - `[BRAND]` (everywhere) — the actual product/company name
   - `[CITY]` — founders' city
   - Founder names, roles, bios in `Team.tsx`
   - Email domains in mailto links
   - OG image at `/public/og-image.jpg`
   - Brand asset downloads on `/press`
   - Legal copy on `/privacy` and `/terms`
   - Social media URLs in `Footer.tsx`
4. Deployment instructions for Vercel (one paragraph).
5. A "Design notes" section: one paragraph explaining the aesthetic intent, so a future contributor doesn't accidentally introduce a stock photo or use the accent colour for body text.

---

## 10. Definition of done

The agent's work is complete when **all** of the following are true:

- [ ] `pnpm install && pnpm dev` runs the site at `localhost:3000` with no errors or warnings in the console.
- [ ] The main page renders all five sections with all copy from section 4 of this brief, verbatim.
- [ ] All animations from section 6 are implemented and work.
- [ ] The hero SVG illustration is custom-drawn (not pulled from a library) and line-draws on load.
- [ ] The waitlist modal opens, accepts input, posts to the stubbed API, and shows the confirmation state.
- [ ] All four sub-routes render without errors.
- [ ] Site is fully responsive at 375px, 768px, 1024px, and 1440px+.
- [ ] Lighthouse scores meet the thresholds in section 7.4.
- [ ] `prefers-reduced-motion` is respected.
- [ ] All `TODO` placeholders are in a single, findable format (`// TODO:` or `{/* TODO: */}`) and listed in the README.
- [ ] The accent colour `#D97757` appears on no more than ~7 elements when scrolling the whole page.
- [ ] There are no console errors, no missing keys in lists, no hydration warnings.
- [ ] No stock photos. No emoji. No exclamation marks. No purple gradients.
- [ ] A `README.md` exists matching section 9.

---

## 11. Anti-patterns to avoid

The agent must not, under any circumstances, produce any of the following:

1. A purple-to-pink gradient hero. This is the single most overused AI-generated aesthetic.
2. The fonts Inter, Roboto, Space Grotesk, or Arial.
3. Stock photography of "happy families" or "smart homes."
4. Lucide icons used as decoration (small utility only).
5. Animations that wobble, bounce, or spring exuberantly. Easing is always smooth and decelerating.
6. A "Trusted by" logo row (we have no logos).
7. A pricing section.
8. A roadmap or "what's next" timeline.
9. Specific dates anywhere on the public site (use "2026" only, never a month).
10. Any mention of: ESP32, RS-485, mesh, channels, 16A, BIS, Matter, Wi-Fi, BLE, Thread, or any other technical term from internal documents.
11. The phrases "revolutionary," "disrupting," "next-generation," "AI-powered," "seamless," "intuitive," or "unleash."
12. A cookie consent banner (out of scope for v1; add a `TODO` in the README).
13. Multiple accent colours. There is one accent. That is the rule.

---

## 12. Working style guidance for the agent

- Build the layout shell first (nav, footer, page scaffolding), then sections in order top to bottom.
- Make the page look right at rest before adding animations. Static design first, motion second.
- Implement the hero entrance sequence as the last polish step; it benefits from being orchestrated against finished content.
- If you find yourself wanting to add a feature not in this brief, do not. The discipline is the point.
- If a constraint in this brief is impossible (e.g., a font fails to load), note it as a `TODO` in the README and pick the closest alternative inside the spirit of the brief.
- Commit code in logical chunks if using git; otherwise produce the full file tree in one pass.

---

*End of brief. Build it.*
