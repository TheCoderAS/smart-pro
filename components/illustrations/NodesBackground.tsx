"use client";

import { useEffect, useRef } from "react";

/**
 * Connected-nodes ambient background.
 *
 * Lightweight canvas mesh: ~35 nodes drift very slowly, lines connect any
 * pair within a distance threshold, line opacity fades with distance.
 * Sits absolutely behind hero content with low overall opacity so it
 * reads as live drafting paper, not "tech startup vibes".
 *
 * Performance discipline:
 *  - Single canvas, drawn with requestAnimationFrame.
 *  - Paused when the host element scrolls offscreen (IntersectionObserver).
 *  - Paused when the tab is hidden (visibilitychange).
 *  - Skipped entirely for `prefers-reduced-motion: reduce`.
 *  - DPR-aware so it stays crisp on retina displays without ballooning
 *    the offscreen buffer on low-end devices (capped at 2).
 */
export function NodesBackground() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    if (
      window.matchMedia &&
      window.matchMedia("(prefers-reduced-motion: reduce)").matches
    ) {
      return;
    }

    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    let width = 0;
    let height = 0;

    type Node = { x: number; y: number; vx: number; vy: number };
    let nodes: Node[] = [];

    const NODE_COUNT = 35;
    const CONNECT_DISTANCE = 160;
    const DRIFT = 0.12; // base velocity px / 16ms frame

    const seedNodes = () => {
      nodes = Array.from({ length: NODE_COUNT }, () => ({
        x: Math.random() * width,
        y: Math.random() * height,
        vx: (Math.random() - 0.5) * DRIFT * 2,
        vy: (Math.random() - 0.5) * DRIFT * 2,
      }));
    };

    const resize = () => {
      const rect = canvas.getBoundingClientRect();
      width = rect.width;
      height = rect.height;
      if (width === 0 || height === 0) return;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      if (nodes.length === 0) seedNodes();
    };

    resize();
    const ro = new ResizeObserver(resize);
    ro.observe(canvas);

    let raf = 0;
    let lastT = performance.now();
    let running = false;

    const step = (t: number) => {
      const dt = Math.min((t - lastT) / 16.67, 2);
      lastT = t;

      ctx.clearRect(0, 0, width, height);

      // Update positions; reflect off edges
      for (const n of nodes) {
        n.x += n.vx * dt;
        n.y += n.vy * dt;
        if (n.x < 0) {
          n.x = 0;
          n.vx *= -1;
        } else if (n.x > width) {
          n.x = width;
          n.vx *= -1;
        }
        if (n.y < 0) {
          n.y = 0;
          n.vy *= -1;
        } else if (n.y > height) {
          n.y = height;
          n.vy *= -1;
        }
      }

      // Connections — fg-muted (138 135 128) at distance-decayed alpha
      ctx.lineWidth = 1;
      for (let i = 0; i < nodes.length; i++) {
        const a = nodes[i];
        for (let j = i + 1; j < nodes.length; j++) {
          const b = nodes[j];
          const dx = a.x - b.x;
          const dy = a.y - b.y;
          const d2 = dx * dx + dy * dy;
          if (d2 < CONNECT_DISTANCE * CONNECT_DISTANCE) {
            const d = Math.sqrt(d2);
            const alpha = (1 - d / CONNECT_DISTANCE) * 0.18;
            ctx.strokeStyle = `rgba(138, 135, 128, ${alpha})`;
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
          }
        }
      }

      // Nodes — small, fg-muted dots
      ctx.fillStyle = "rgba(138, 135, 128, 0.55)";
      for (const n of nodes) {
        ctx.beginPath();
        ctx.arc(n.x, n.y, 1.4, 0, Math.PI * 2);
        ctx.fill();
      }

      if (running) raf = requestAnimationFrame(step);
    };

    const start = () => {
      if (running) return;
      running = true;
      lastT = performance.now();
      raf = requestAnimationFrame(step);
    };
    const stop = () => {
      running = false;
      if (raf) cancelAnimationFrame(raf);
    };

    // Pause when off-screen (long pages — hero exits viewport quickly)
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) start();
        else stop();
      },
      { threshold: 0 },
    );
    io.observe(canvas);

    // Pause when tab hidden
    const onVisibility = () => {
      if (document.hidden) stop();
      else if (canvas.getBoundingClientRect().bottom > 0) start();
    };
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      stop();
      ro.disconnect();
      io.disconnect();
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      aria-hidden
      className="absolute inset-0 w-full h-full pointer-events-none"
    />
  );
}
