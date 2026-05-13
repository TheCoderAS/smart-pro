import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        bg: "var(--bg)",
        "bg-elevated": "var(--bg-elevated)",
        "bg-subtle": "var(--bg-subtle)",
        fg: "var(--fg)",
        "fg-muted": "var(--fg-muted)",
        "fg-faint": "var(--fg-faint)",
        accent: "var(--accent)",
        "accent-glow": "var(--accent-glow)",
      },
      fontFamily: {
        display: ["var(--font-display)", "Georgia", "serif"],
        sans: ["var(--font-geist-sans)", "system-ui", "sans-serif"],
        mono: ["var(--font-mono)", "ui-monospace", "monospace"],
      },
      fontSize: {
        hero: "clamp(3.5rem, 9vw, 8rem)",
        h1: "clamp(2.5rem, 6vw, 5rem)",
        h2: "clamp(1.75rem, 3vw, 2.5rem)",
        "body-lg": "clamp(1.125rem, 1.5vw, 1.5rem)",
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
