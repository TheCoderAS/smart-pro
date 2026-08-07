"use client";

import { motion } from "framer-motion";
import { SMOOTH } from "@/lib/motion";
import { RevealText } from "@/components/ui/RevealText";

export function InstallersHero() {
  return (
    <section className="relative pt-40 pb-[clamp(4rem,10vw,8rem)]">
      <div className="max-w-content mx-auto px-6 lg:px-24">
        <motion.div
          initial={{ opacity: 0, y: 8, filter: "blur(6px)" }}
          animate={{ opacity: 1, y: 0, filter: "blur(0px)" }}
          transition={{ delay: 0.2, duration: 0.8, ease: SMOOTH }}
          className="eyebrow"
        >
          For the professional on the ladder
        </motion.div>

        <RevealText
          as="h1"
          onMount
          delay={0.5}
          className="font-display text-hero mt-8 max-w-4xl"
        >
          The smart switch your customer won&apos;t return.
        </RevealText>

        <motion.p
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 1.4, duration: 0.6, ease: SMOOTH }}
          className="text-body-lg text-fg-muted mt-10 max-w-2xl leading-relaxed"
        >
          Every electrician knows the rhythm. The customer wants smart switches.
          The wholesaler has three brands. None of them last. The callbacks
          come, and your reputation is the one on the line. We are trying to
          fix that.
        </motion.p>
      </div>
    </section>
  );
}
