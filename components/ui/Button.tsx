"use client";

import { forwardRef } from "react";
import { cn } from "@/lib/utils";

type Props = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary";
};

export const Button = forwardRef<HTMLButtonElement, Props>(function Button(
  { variant = "primary", className, children, ...rest },
  ref,
) {
  if (variant === "secondary") {
    return (
      <button
        ref={ref}
        className={cn(
          "group relative text-sm text-fg-muted hover:text-accent transition-colors duration-300 inline-flex items-center gap-2",
          className,
        )}
        {...rest}
      >
        <span className="link-underline">{children}</span>
      </button>
    );
  }

  return (
    <button
      ref={ref}
      className={cn(
        "group relative overflow-hidden inline-flex items-center justify-center",
        "px-7 py-4 border border-fg-faint",
        "text-sm font-mono tracking-eyebrow uppercase",
        "transition-[color,border-color,transform] duration-300 ease-smooth",
        "hover:border-accent active:scale-[0.97]",
        className,
      )}
      {...rest}
    >
      <span
        aria-hidden
        className="absolute inset-0 bg-accent origin-left scale-x-0 group-hover:scale-x-100 transition-transform duration-500 ease-smooth"
      />
      <span className="relative z-10 group-hover:text-bg transition-colors duration-300">
        {children}
      </span>
    </button>
  );
});
