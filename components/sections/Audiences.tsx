"use client";

import Link from "next/link";
import { motion } from "framer-motion";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";
import { RevealText } from "@/components/ui/RevealText";
import { SectionNumber } from "@/components/ui/SectionNumber";
import { SMOOTH, VIEWPORT_REPEAT } from "@/lib/motion";

type Card = {
  title: string;
  subtitle: string;
  body: string;
  cta: string;
  href: string;
};

const CARDS: Card[] = [
  {
    title: "Homeowners",
    subtitle: "For the home you're actually building",
    body: "Renovating one room or wiring a new flat — the system that runs your lights shouldn't feel like a project. It should feel like furniture.",
    cta: "Join the waitlist →",
    href: "#waitlist",
  },
  {
    title: "Electricians",
    subtitle: "For the professional on the ladder",
    body: "Fits the boards you already install. Trains in a day. Earns more per fit. We build the product; you build the network.",
    cta: "Become a partner →",
    href: "/installers",
  },
  {
    title: "Builders & Developers",
    subtitle: "For the people specifying tomorrow's homes",
    body: "Standardised. BIS-certified. Repairable in five minutes by anyone you already employ. Designed for Indian construction, at scale.",
    cta: "Talk to us →",
    href: "mailto:aalokmamtasah@gmail.com",
  },
];

function AudienceCard({ card }: { card: Card }) {
  const inner = (
    <>
      {/* Top accent line that draws on hover */}
      <span
        aria-hidden
        className="absolute left-0 top-0 h-px bg-accent w-full origin-left scale-x-0 group-hover:scale-x-100 transition-transform duration-500 ease-smooth"
      />
      <div className="eyebrow mb-6">{card.title}</div>
      <h3 className="font-display text-h2 mb-4 leading-display">
        {card.subtitle}
      </h3>
      <p className="text-fg-muted leading-relaxed mb-10">{card.body}</p>
      <span className="text-sm font-mono tracking-eyebrow uppercase link-underline group-hover:text-accent transition-colors duration-300">
        {card.cta}
      </span>
    </>
  );

  const className =
    "group relative block pt-6 px-2 transition-transform duration-500 ease-smooth hover:-translate-y-1";

  // Use a plain <a> for in-page anchors and mailto, Next <Link> for route navigation.
  if (card.href.startsWith("#") || card.href.startsWith("mailto:")) {
    return (
      <a href={card.href} className={className}>
        {inner}
      </a>
    );
  }
  return (
    <Link href={card.href} className={className}>
      {inner}
    </Link>
  );
}

export function Audiences() {
  return (
    <section
      id="audiences"
      className="relative py-[clamp(6rem,12vw,12rem)] border-t border-fg-faint/40 overflow-hidden"
    >
      <SectionNumber number="04" side="right" />

      <div className="relative max-w-content mx-auto px-6 lg:px-24">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12">
          <div className="lg:col-span-4">
            <motion.div
              initial={{ opacity: 0, y: 16 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={VIEWPORT_REPEAT}
              transition={{ duration: 0.8, ease: SMOOTH }}
            >
              <EyebrowLabel withMark>04 — Built for</EyebrowLabel>
            </motion.div>
          </div>
          <div className="lg:col-span-8">
            <RevealText as="h2" className="font-display text-h1 max-w-3xl">
              Three people. One product.
            </RevealText>
          </div>
        </div>

        <motion.div
          initial="hidden"
          whileInView="visible"
          viewport={VIEWPORT_REPEAT}
          variants={{
            hidden: {},
            visible: { transition: { staggerChildren: 0.12, delayChildren: 0.3 } },
          }}
          className="mt-24 grid grid-cols-1 md:grid-cols-3 gap-12 md:gap-8"
        >
          {CARDS.map((card) => (
            <motion.div
              key={card.title}
              variants={{
                hidden: { opacity: 0, y: 20 },
                visible: {
                  opacity: 1,
                  y: 0,
                  transition: { duration: 0.8, ease: SMOOTH },
                },
              }}
            >
              <AudienceCard card={card} />
            </motion.div>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
