"use client";

import { useRef } from "react";
import { motion, useScroll, useTransform } from "framer-motion";
import { cn } from "@/lib/utils";

type Props = {
  number: string;
  side?: "left" | "right";
  className?: string;
};

export function SectionNumber({ number, side = "right", className }: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start end", "end start"],
  });
  // Parallax: number translates slower (0.3x) than scroll
  const y = useTransform(scrollYProgress, [0, 1], [120, -120]);

  return (
    <div
      ref={ref}
      aria-hidden
      className={cn(
        "pointer-events-none absolute top-1/2 -translate-y-1/2 select-none",
        // Smaller offset on mobile keeps the number from sitting on top of text.
        side === "left" ? "-left-6 md:-left-12 lg:-left-24" : "-right-6 md:-right-12 lg:-right-24",
        className,
      )}
    >
      <motion.div
        style={{ y }}
        className="font-display font-light text-fg-faint/30 leading-none"
      >
        <span
          // Min reduced from 12rem to 5rem so the number stays a faint background ornament
          // on a 375px viewport instead of dominating the section.
          style={{ fontSize: "clamp(5rem, 22vw, 24rem)" }}
          className="block"
        >
          {number}
        </span>
      </motion.div>
    </div>
  );
}
