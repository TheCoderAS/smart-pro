"use client";

import { useEffect, useRef } from "react";

/**
 * Full-page connected-nodes mesh. Drifting particles, with the nearest
 * node to the cursor pulled toward the pointer and rendered as the
 * "main" — accent-coloured, larger, with its connections to neighbours
 * highlighted. This dramatises the product story (one master node
 * connected to the user, propagating to nearby extensions).
 *
 * Performance discipline:
 *  - Single canvas, single RAF loop.
 *  - `position: fixed` covers the viewport regardless of scroll, but the
 *    loop pauses when the tab is hidden (visibilitychange).
 *  - Skipped entirely for `prefers-reduced-motion: reduce`.
 *  - O(N^2) connection scan, but N is small (~55 nodes ≈ 1.5k checks).
 *  - DPR capped at 2 so retina doesn't blow up the offscreen buffer.
 *  - Re-seeds when the viewport changes size meaningfully.
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

    // Tuning
    const NODE_COUNT = 55;
    const CONNECT_DISTANCE = 170;
    const DRIFT = 0.18; // base px / 16ms
    const NODE_RADIUS = 1.5;
    const MAIN_RADIUS = 4;
    const MAIN_LERP = 0.18; // 0 = no follow, 1 = instant snap
    const POINTER_REACH = 220; // only "activate" if pointer is within this distance of any node

    type Node = { x: number; y: number; vx: number; vy: number };
    let nodes: Node[] = [];

    const pointer = { x: -10000, y: -10000, active: false };
    // Visual position of the main node — lerps toward pointer, away from its drift position when pointer is active.
    let mainIdx = 0;
    let mainX = 0;
    let mainY = 0;

    const seed = () => {
      nodes = Array.from({ length: NODE_COUNT }, () => ({
        x: Math.random() * width,
        y: Math.random() * height,
        vx: (Math.random() - 0.5) * DRIFT * 2,
        vy: (Math.random() - 0.5) * DRIFT * 2,
      }));
      // Initial main coords match a random node's position so the first frame doesn't snap.
      mainX = nodes[0].x;
      mainY = nodes[0].y;
    };

    const resize = () => {
      const w = window.innerWidth;
      const h = window.innerHeight;
      const reseed = nodes.length === 0;
      width = w;
      height = h;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      if (reseed) seed();
    };

    resize();
    window.addEventListener("resize", resize);

    const onPointerMove = (e: PointerEvent) => {
      pointer.x = e.clientX;
      pointer.y = e.clientY;
      pointer.active = true;
    };
    const onPointerOut = (e: PointerEvent) => {
      // Only deactivate when the pointer leaves the window entirely, not on element exits inside the page.
      if (e.relatedTarget === null) {
        pointer.active = false;
      }
    };
    window.addEventListener("pointermove", onPointerMove);
    window.addEventListener("pointerout", onPointerOut);

    let raf = 0;
    let lastT = performance.now();
    let running = true;

    const step = (t: number) => {
      const dt = Math.min((t - lastT) / 16.67, 2);
      lastT = t;

      ctx.clearRect(0, 0, width, height);

      // Update drifting positions
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

      // Pick "main": nearest free-drifting node to the pointer.
      // Re-evaluated every frame so the main hands off naturally as the cursor crosses regions.
      let pointerReached = false;
      if (pointer.active) {
        let best = -1;
        let bestD = Infinity;
        for (let i = 0; i < nodes.length; i++) {
          const dx = nodes[i].x - pointer.x;
          const dy = nodes[i].y - pointer.y;
          const d2 = dx * dx + dy * dy;
          if (d2 < bestD) {
            bestD = d2;
            best = i;
          }
        }
        if (best >= 0 && bestD < POINTER_REACH * POINTER_REACH) {
          mainIdx = best;
          pointerReached = true;
        }
      }

      // Lerp main visual position toward the pointer (when active and reachable) or toward its drift position otherwise.
      const main = nodes[mainIdx];
      const targetX = pointerReached ? pointer.x : main.x;
      const targetY = pointerReached ? pointer.y : main.y;
      mainX += (targetX - mainX) * MAIN_LERP;
      mainY += (targetY - mainY) * MAIN_LERP;

      // Override the chosen node's coordinates for this frame's connection math
      // so its lines emanate from the visual (cursor-following) position.
      const savedMainX = main.x;
      const savedMainY = main.y;
      main.x = mainX;
      main.y = mainY;

      // Draw connections
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
            const isMainConn = i === mainIdx || j === mainIdx;
            if (isMainConn) {
              // Accent (217 119 87), brighter — the main propagating to its mesh peers.
              const alpha = (1 - d / CONNECT_DISTANCE) * 0.55;
              ctx.strokeStyle = `rgba(217, 119, 87, ${alpha})`;
              ctx.lineWidth = 1.2;
            } else {
              // Faint warm-gray mesh, intentionally quiet so text reads cleanly on top.
              const alpha = (1 - d / CONNECT_DISTANCE) * 0.14;
              ctx.strokeStyle = `rgba(138, 135, 128, ${alpha})`;
              ctx.lineWidth = 1;
            }
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
          }
        }
      }

      // Draw regular nodes
      ctx.fillStyle = "rgba(138, 135, 128, 0.55)";
      for (let i = 0; i < nodes.length; i++) {
        if (i === mainIdx) continue;
        const n = nodes[i];
        ctx.beginPath();
        ctx.arc(n.x, n.y, NODE_RADIUS, 0, Math.PI * 2);
        ctx.fill();
      }

      // Draw the main node (accent, larger, with a softer outer ring)
      ctx.fillStyle = "rgba(217, 119, 87, 0.95)";
      ctx.beginPath();
      ctx.arc(main.x, main.y, MAIN_RADIUS, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = "rgba(217, 119, 87, 0.35)";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.arc(main.x, main.y, MAIN_RADIUS + 5, 0, Math.PI * 2);
      ctx.stroke();

      // Restore the underlying drift position so the node continues to flow when no longer "main".
      main.x = savedMainX;
      main.y = savedMainY;

      if (running) raf = requestAnimationFrame(step);
    };

    raf = requestAnimationFrame(step);

    const onVisibility = () => {
      if (document.hidden) {
        running = false;
        if (raf) cancelAnimationFrame(raf);
      } else if (!running) {
        running = true;
        lastT = performance.now();
        raf = requestAnimationFrame(step);
      }
    };
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      running = false;
      if (raf) cancelAnimationFrame(raf);
      window.removeEventListener("resize", resize);
      window.removeEventListener("pointermove", onPointerMove);
      window.removeEventListener("pointerout", onPointerOut);
      document.removeEventListener("visibilitychange", onVisibility);
    };
  }, []);

  return (
    <canvas
      ref={canvasRef}
      aria-hidden
      className="fixed inset-0 w-full h-full pointer-events-none"
      style={{ zIndex: 0 }}
    />
  );
}
