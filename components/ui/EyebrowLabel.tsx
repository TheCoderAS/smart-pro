import { cn } from "@/lib/utils";

export function EyebrowLabel({
  children,
  className,
  withMark = false,
}: {
  children: React.ReactNode;
  className?: string;
  /** Adds a small accent rule before the label — one ornament per section */
  withMark?: boolean;
}) {
  return (
    <div className={cn("eyebrow inline-flex items-center gap-3", className)}>
      {withMark && (
        <span
          aria-hidden
          className="inline-block w-6 h-px bg-accent"
        />
      )}
      <span>{children}</span>
    </div>
  );
}
