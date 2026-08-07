import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        // Use the rgb-channels form so `/<alpha>` opacity modifiers work.
        bg: "rgb(var(--bg-rgb) / <alpha-value>)",
        "bg-elevated": "rgb(var(--bg-elevated-rgb) / <alpha-value>)",
        "bg-subtle": "rgb(var(--bg-subtle-rgb) / <alpha-value>)",
        fg: "rgb(var(--fg-rgb) / <alpha-value>)",
        "fg-muted": "rgb(var(--fg-muted-rgb) / <alpha-value>)",
        "fg-faint": "rgb(var(--fg-faint-rgb) / <alpha-value>)",
        accent: "rgb(var(--accent-rgb) / <alpha-value>)",
        "accent-glow": "var(--accent-glow)",
      },
      fontFamily: {
        display: ["var(--font-display)", "Georgia", "serif"],
        sans: ["var(--font-geist-sans)", "system-ui", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "monospace"],
      },
      fontSize: {
        // Mins lowered so long words ("infrastructure") fit on a 375px viewport.
        hero: "clamp(2.5rem, 9vw, 8rem)",
        h1: "clamp(1.875rem, 6vw, 5rem)",
        h2: "clamp(1.5rem, 3vw, 2.5rem)",
        "body-lg": "clamp(1.0625rem, 1.5vw, 1.5rem)",
      },
      letterSpacing: {
        display: "-0.02em",
        eyebrow: "0.15em",
      },
      lineHeight: {
        display: "1.02",
      },
      transitionTimingFunction: {
        smooth: "cubic-bezier(0.22, 1, 0.36, 1)",
      },
      maxWidth: {
        content: "1280px",
      },
    },
  },
  plugins: [],
};

export default config;
