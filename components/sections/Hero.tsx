"use client";

import { motion } from "framer-motion";
import { SMOOTH } from "@/lib/motion";
import { RevealText } from "@/components/ui/RevealText";
import { Button } from "@/components/ui/Button";
import { HeroSchematic } from "@/components/illustrations/HeroSchematic";

export function Hero() {
  return (
    <section className="relative pt-40 pb-[clamp(6rem,12vw,12rem)] overflow-hidden">
      <div className="max-w-content mx-auto px-6 lg:px-24">
        <motion.div
          initial={{ opacity: 0, y: 8, filter: "blur(6px)" }}
          animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
          transition={{ delay: 0.4, duration: 0.8, ease: SMOOTH }}
          className="eyebrow"
        >
          A new kind of electrical switch. Coming to India, 2026.
        </motion.div>

        <RevealText
          as="h1"
          onMount
          delay={0.8}
          stagger={0.08}
          className="font-display text-hero mt-8 max-w-5xl"
        >
          The wall should be smarter than the bulb.
        </RevealText>

        <motion.p
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 1.6, duration: 0.6, ease: SMOOTH }}
          className="text-body-lg text-fg-muted mt-10 max-w-2xl leading-relaxed"
        >
          We are rebuilding the most-touched object in your home, from the
          inside out.
        </motion.p>

        <div className="flex flex-wrap items-center gap-8 mt-12">
          <motion.div
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 2.0, duration: 0.6, ease: SMOOTH }}
          >
            <Button data-waitlist-trigger>Request early access</Button>
          </motion.div>
          <motion.a
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 2.1, duration: 0.6, ease: SMOOTH }}
            href="mailto:investors@brand.com"
            className="text-sm text-fg-muted hover:text-accent link-underline inline-flex items-center gap-2 transition-colors duration-300"
          >
            For investors <span aria-hidden>→</span>
          </motion.a>
        </div>

        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ delay: 2.2, duration: 0.6, ease: SMOOTH }}
          className="mt-24 lg:mt-32"
        >
          <HeroSchematic />
        </motion.div>
      </div>
    </section>
  );
}
