import type { Variants } from "framer-motion";

export const SMOOTH: [number, number, number, number] = [0.22, 1, 0.36, 1];

export const fadeUp: Variants = {
  hidden: { opacity: 0, y: 16 },
  visible: {
    opacity: 1,
    y: 0,
    transition: { duration: 0.8, ease: SMOOTH },
  },
};

export const fadeIn: Variants = {
  hidden: { opacity: 0 },
  visible: {
    opacity: 1,
    transition: { duration: 0.8, ease: SMOOTH },
  },
};

export const staggerContainer = (stagger = 0.08, delayChildren = 0): Variants => ({
  hidden: {},
  visible: {
    transition: {
      staggerChildren: stagger,
      delayChildren,
    },
  },
});

export const wordReveal: Variants = {
  hidden: { opacity: 0, y: 24, filter: "blur(8px)" },
  visible: {
    opacity: 1,
    y: 0,
    filter: "blur(0px)",
    transition: { duration: 0.9, ease: SMOOTH },
  },
};

/**
 * Viewport config for scroll-triggered reveals.
 *
 * `once: false` means animations replay each time the element enters the
 * viewport — scroll down past a section, scroll back up, you'll see it
 * fade in again. The `-100px` margin shrinks the trigger zone so partial
 * scrolls don't cause flicker; the element animates back to its hidden
 * state only after it's fully out of view + 100px of buffer.
 *
 * Use this for whileInView animations. Hero entrance uses initial/animate
 * on mount instead, which is unaffected.
 */
export const VIEWPORT_REPEAT = { once: false, margin: "-100px" } as const;
