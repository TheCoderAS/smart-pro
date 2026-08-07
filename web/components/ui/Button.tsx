"use client";

import { forwardRef } from "react";
import { cn } from "@/lib/utils";

const primaryClasses = [
  "group relative overflow-hidden inline-flex items-center justify-center",
  "px-7 py-4 border border-fg-faint",
  "text-sm font-mono tracking-eyebrow uppercase",
  "transition-[color,border-color,transform] duration-300 ease-smooth",
  "hover:border-accent active:scale-[0.97]",
];

function PrimaryInner({ children }: { children: React.ReactNode }) {
  return (
    <>
      <span
        aria-hidden
        className="absolute inset-0 bg-accent origin-left scale-x-0 group-hover:scale-x-100 transition-transform duration-500 ease-smooth"
      />
      <span className="relative z-10 group-hover:text-bg transition-colors duration-300">
        {children}
      </span>
    </>
  );
}

type CommonProps = {
  variant?: "primary" | "secondary";
  className?: string;
  children: React.ReactNode;
};

type ButtonProps = CommonProps &
  Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, "className" | "children"> & {
    href?: undefined;
  };

type AnchorProps = CommonProps &
  Omit<React.AnchorHTMLAttributes<HTMLAnchorElement>, "className" | "children"> & {
    href: string;
  };

type Props = ButtonProps | AnchorProps;

export const Button = forwardRef<HTMLButtonElement | HTMLAnchorElement, Props>(
  function Button({ variant = "primary", className, children, ...rest }, ref) {
    const isLink = "href" in rest && rest.href !== undefined;

    if (variant === "secondary") {
      const secondaryClass = cn(
        "group relative text-sm text-fg-muted hover:text-accent transition-colors duration-300 inline-flex items-center gap-2",
        className,
      );
      if (isLink) {
        return (
          <a
            ref={ref as React.Ref<HTMLAnchorElement>}
            className={secondaryClass}
            {...(rest as AnchorProps)}
          >
            <span className="link-underline">{children}</span>
          </a>
        );
      }
      return (
        <button
          ref={ref as React.Ref<HTMLButtonElement>}
          className={secondaryClass}
          {...(rest as ButtonProps)}
        >
          <span className="link-underline">{children}</span>
        </button>
      );
    }

    const classes = cn(...primaryClasses, className);

    if (isLink) {
      return (
        <a
          ref={ref as React.Ref<HTMLAnchorElement>}
          className={classes}
          {...(rest as AnchorProps)}
        >
          <PrimaryInner>{children}</PrimaryInner>
        </a>
      );
    }
    return (
      <button
        ref={ref as React.Ref<HTMLButtonElement>}
        className={classes}
        {...(rest as ButtonProps)}
      >
        <PrimaryInner>{children}</PrimaryInner>
      </button>
    );
  },
);
