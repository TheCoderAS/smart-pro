"use client";

import { motion, type Variants } from "framer-motion";
import { SMOOTH, VIEWPORT_ONCE, wordReveal } from "@/lib/motion";
import { cn } from "@/lib/utils";

type Props = {
  children: string;
  as?: "h1" | "h2" | "h3" | "p" | "span";
  className?: string;
  delay?: number;
  stagger?: number;
  /** When true, animate on mount instead of in-view */
  onMount?: boolean;
};

export function RevealText({
  children,
  as = "h2",
  className,
  delay = 0,
  stagger = 0.06,
  onMount = false,
}: Props) {
  const words = children.split(" ");
  const MotionTag = motion[as] as typeof motion.h2;

  const containerVariants: Variants = {
    hidden: {},
    visible: {
      transition: {
        staggerChildren: stagger,
        delayChildren: delay,
      },
    },
  };

  const containerProps = onMount
    ? {
        initial: "hidden" as const,
        animate: "visible" as const,
      }
    : {
        initial: "hidden" as const,
        whileInView: "visible" as const,
        viewport: VIEWPORT_ONCE,
      };

  return (
    <MotionTag
      {...containerProps}
      variants={containerVariants}
      className={cn(className)}
      aria-label={children}
    >
      {words.map((word, i) => (
        <span key={i} className="inline-block overflow-hidden" aria-hidden>
          <motion.span
            className="inline-block"
            variants={wordReveal}
            transition={{ duration: 0.9, ease: SMOOTH }}
          >
            {word}
            {i < words.length - 1 ? " " : ""}
          </motion.span>
        </span>
      ))}
    </MotionTag>
  );
}
