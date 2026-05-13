import type { Metadata } from "next";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";

export const metadata: Metadata = {
  title: "Press — [BRAND]",
  description: "Press resources, brand assets, and contact for [BRAND].",
};

const FOUNDERS = [
  {
    initial: "A",
    // TODO: replace founder details
    name: "[Founder Name]",
    role: "[Role]",
    bio: "Two decades in connected-device hardware. Has shipped to millions of homes across three regions.",
  },
  {
    initial: "B",
    name: "[Founder Name]",
    role: "[Role]",
    bio: "Industrial design and brand. Previously led product at companies you have heard of.",
  },
  {
    initial: "C",
    name: "[Founder Name]",
    role: "[Role]",
    bio: "Operations, manufacturing, and the realities of moving atoms at scale.",
  },
];

const ASSETS = [
  // TODO: place real brand asset downloads in /public
  { label: "Wordmark — SVG", href: "/brand/wordmark.svg" },
  { label: "Wordmark — PNG", href: "/brand/wordmark.png" },
  { label: "Wordmark — PDF", href: "/brand/wordmark.pdf" },
];

export default function PressPage() {
  return (
    <div className="pt-40 pb-24">
      <div className="max-w-content mx-auto px-6 lg:px-24">
        <EyebrowLabel withMark>Press</EyebrowLabel>
        <h1 className="font-display text-h1 mt-6 mb-12 max-w-3xl">
          About [BRAND].
        </h1>

        <p className="text-body-lg text-fg/90 leading-relaxed max-w-3xl">
          [BRAND] is a pre-launch hardware company based in India, rebuilding
          the most-touched object in the home. The company is developing a new
          kind of electrical switch, designed to fit the homes, the boards, and
          the people who actually install them. Founded in [CITY] in 2025.
        </p>

        <section className="mt-24 border-t border-fg-faint/40 pt-16">
          <EyebrowLabel>Founders</EyebrowLabel>
          <div className="mt-10 grid grid-cols-1 md:grid-cols-3 gap-12">
            {FOUNDERS.map((f) => (
              <div key={f.initial}>
                <div
                  className="size-20 rounded-full flex items-center justify-center mb-6"
                  style={{ background: "var(--bg-subtle)" }}
                >
                  <span className="font-display text-3xl text-fg-muted">
                    {f.initial}
                  </span>
                </div>
                <div className="font-display text-h2 mb-1">{f.name}</div>
                <div className="eyebrow mb-4">{f.role}</div>
                <p className="text-fg-muted leading-relaxed text-sm max-w-xs">
                  {f.bio}
                </p>
              </div>
            ))}
          </div>
        </section>

        <section className="mt-24 border-t border-fg-faint/40 pt-16">
          <EyebrowLabel>Brand assets</EyebrowLabel>
          <ul className="mt-10 space-y-4">
            {ASSETS.map((a) => (
              <li key={a.label}>
                <a
                  href={a.href}
                  className="text-body-lg link-underline hover:text-accent transition-colors"
                >
                  {a.label} ↓
                </a>
              </li>
            ))}
          </ul>
        </section>

        <section className="mt-24 border-t border-fg-faint/40 pt-16">
          <EyebrowLabel>Press contact</EyebrowLabel>
          <a
            href="mailto:press@brand.com"
            className="block mt-6 text-body-lg link-underline hover:text-accent transition-colors"
          >
            press@brand.com
          </a>
        </section>
      </div>
    </div>
  );
}
