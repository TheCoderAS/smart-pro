"use client";

import { motion } from "framer-motion";
import { EyebrowLabel } from "@/components/ui/EyebrowLabel";
import { RevealText } from "@/components/ui/RevealText";
import { SMOOTH, VIEWPORT_ONCE } from "@/lib/motion";

const VALUES = [
  {
    title: "Earn more per fit",
    body: "A higher-margin product, paired with a partner programme designed around your work — not against it.",
  },
  {
    title: "Trains in a day",
    body: "If you can install a conventional switchboard, you can install this. The differences are deliberate, and they all simplify the job.",
  },
  {
    title: "Backed by support that picks up",
    body: "A real person on the line. Replacement units that arrive when they say they will. Documentation written by humans, for humans.",
  },
];

export function InstallersValue() {
  return (
    <section className="relative py-[clamp(4rem,10vw,8rem)] border-t border-fg-faint/40">
      <div className="max-w-content mx-auto px-6 lg:px-24">
        <div className="grid grid-cols-1 lg:grid-cols-12 gap-12">
          <div className="lg:col-span-4">
            <EyebrowLabel withMark>What&apos;s in it for you</EyebrowLabel>
          </div>
          <div className="lg:col-span-8">
            <RevealText as="h2" className="font-display text-h1 max-w-3xl">
              A product designed with you in the room.
            </RevealText>
          </div>
        </div>

        <motion.div
          initial="hidden"
          whileInView="visible"
          viewport={VIEWPORT_ONCE}
          variants={{
            hidden: {},
            visible: { transition: { staggerChildren: 0.12, delayChildren: 0.2 } },
          }}
          className="mt-20 grid grid-cols-1 md:grid-cols-3 gap-12"
        >
          {VALUES.map((v) => (
            <motion.div
              key={v.title}
              variants={{
                hidden: { opacity: 0, y: 20 },
                visible: {
                  opacity: 1,
                  y: 0,
                  transition: { duration: 0.8, ease: SMOOTH },
                },
              }}
            >
              <h3 className="font-display text-h2 mb-4">{v.title}</h3>
              <p className="text-fg-muted leading-relaxed max-w-md">{v.body}</p>
            </motion.div>
          ))}
        </motion.div>
      </div>
    </section>
  );
}
