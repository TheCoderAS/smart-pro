import type { Metadata } from "next";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";

export const metadata: Metadata = {
  title: "Press — Unisync",
  description: "Press resources, brand assets, and contact for Unisync.",
};

// TODO: replace founder placeholders with real names, roles, and bios
const FOUNDERS = [
  {
    initial: "A",
    name: "[Founder Name]",
    role: "[Role]",
    bio: "[Two- to three-line founder bio placeholder.]",
  },
  {
    initial: "B",
    name: "[Founder Name]",
    role: "[Role]",
    bio: "[Two- to three-line founder bio placeholder.]",
  },
  {
    initial: "C",
    name: "[Founder Name]",
    role: "[Role]",
    bio: "[Two- to three-line founder bio placeholder.]",
  },
];

// Real wordmark currently only exists as the placeholder SVG.
// TODO: add wordmark.png and wordmark.pdf to /public/brand and mark them ready
const ASSETS: Array<{ label: string; href: string; ready: boolean }> = [
  { label: "Wordmark — SVG", href: "/brand/wordmark.svg", ready: true },
  { label: "Wordmark — PNG", href: "/brand/wordmark.png", ready: false },
  { label: "Wordmark — PDF", href: "/brand/wordmark.pdf", ready: false },
];

export default function PressPage() {
  return (
    <div className="pt-40 pb-24">
      <div className="max-w-content mx-auto px-6 lg:px-24">
        <EyebrowLabel withMark>Press</EyebrowLabel>
        <h1 className="font-display text-h1 mt-6 mb-12 max-w-3xl">
          About Unisync.
        </h1>

        <p className="text-body-lg text-fg/90 leading-relaxed max-w-3xl">
          Unisync is a pre-launch hardware company based in India, rebuilding
          the most-touched object in the home. The company is developing a new
          kind of electrical switch, designed to fit the homes, the boards, and
          the people who actually install them. Founded in Bangalore in 2025.
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
            {ASSETS.map((a) =>
              a.ready ? (
                <li key={a.label}>
                  <a
                    href={a.href}
                    className="text-body-lg link-underline hover:text-accent transition-colors"
                  >
                    {a.label} ↓
                  </a>
                </li>
              ) : (
                <li
                  key={a.label}
                  className="text-body-lg text-fg-muted flex items-baseline gap-3"
                >
                  <span>{a.label}</span>
                  <span className="text-xs font-mono tracking-eyebrow uppercase text-fg-faint">
                    Coming soon
                  </span>
                </li>
              ),
            )}
          </ul>
        </section>

        <section className="mt-24 border-t border-fg-faint/40 pt-16">
          <EyebrowLabel>Press contact</EyebrowLabel>
          <a
            href="mailto:aalokmamtasah@gmail.com"
            className="block mt-6 text-body-lg link-underline hover:text-accent transition-colors"
          >
            aalokmamtasah@gmail.com
          </a>
        </section>
      </div>
    </div>
  );
}
