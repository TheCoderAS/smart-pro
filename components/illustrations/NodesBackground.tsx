"use client";

import { useEffect, useRef } from "react";

/**
 * Full-page connected-nodes mesh that dramatises the product story:
 *  - Drifting peer nodes scattered across the viewport.
 *  - The cursor is the "user". A small accent marker tracks it.
 *  - The nearest physical node to the cursor is the "main". An accent
 *    line runs from cursor → main, and brighter accent lines fan out
 *    from main → its in-range peers.
 *  - Every node is guaranteed at least one connection — if no peer is
 *    within the threshold, a faint fallback line is drawn to its
 *    single nearest neighbour.
 *
 * Performance discipline:
 *  - Single canvas, single RAF loop.
 *  - `position: fixed` covers the viewport regardless of scroll.
 *  - `visibilitychange` pauses the loop when the tab is hidden.
 *  - Skipped entirely for `prefers-reduced-motion: reduce`.
 *  - DPR capped at 2.
 *  - O(N^2) scan on ~60 nodes ≈ 1.8k checks per frame.
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
    const NODE_COUNT = 60;
    const CONNECT_DISTANCE = 200;
    const DRIFT = 0.2;
    const NODE_RADIUS = 1.8;
    const MAIN_RADIUS = 4.5;
    const CURSOR_RADIUS = 3;
    const POINTER_REACH = 360; // cursor must be at least this close to *some* node to "activate"
    const ACCENT = "217, 119, 87";
    const MUTED = "138, 135, 128";

    type Node = { x: number; y: number; vx: number; vy: number };
    let nodes: Node[] = [];

    const pointer = { x: -10000, y: -10000, active: false };

    const seed = () => {
      nodes = Array.from({ length: NODE_COUNT }, () => ({
        x: Math.random() * width,
        y: Math.random() * height,
        vx: (Math.random() - 0.5) * DRIFT * 2,
        vy: (Math.random() - 0.5) * DRIFT * 2,
      }));
    };

    const resize = () => {
      width = window.innerWidth;
      height = window.innerHeight;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      if (nodes.length === 0) seed();
    };

    resize();
    window.addEventListener("resize", resize);

    const onPointerMove = (e: PointerEvent) => {
      pointer.x = e.clientX;
      pointer.y = e.clientY;
      pointer.active = true;
    };
    const onPointerOut = (e: PointerEvent) => {
      // Only deactivate when the cursor leaves the window entirely.
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

      // Drift positions
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

      // Find the main: nearest physical node to the pointer
      let mainIdx = -1;
      if (pointer.active) {
        let bestD = Infinity;
        for (let i = 0; i < nodes.length; i++) {
          const dx = nodes[i].x - pointer.x;
          const dy = nodes[i].y - pointer.y;
          const d2 = dx * dx + dy * dy;
          if (d2 < bestD) {
            bestD = d2;
            mainIdx = i;
          }
        }
        if (bestD > POINTER_REACH * POINTER_REACH) mainIdx = -1;
      }

      // Track which nodes have at least one in-range connection so we can
      // backfill isolated nodes with a fallback nearest-neighbour edge.
      const hasConnection = new Array<boolean>(nodes.length).fill(false);

      // First pass: all in-range pairs
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
              const alpha = (1 - d / CONNECT_DISTANCE) * 0.7;
              ctx.strokeStyle = `rgba(${ACCENT}, ${alpha})`;
              ctx.lineWidth = 1.3;
            } else {
              const alpha = (1 - d / CONNECT_DISTANCE) * 0.4;
              ctx.strokeStyle = `rgba(${MUTED}, ${alpha})`;
              ctx.lineWidth = 1;
            }
            ctx.beginPath();
            ctx.moveTo(a.x, a.y);
            ctx.lineTo(b.x, b.y);
            ctx.stroke();
            hasConnection[i] = true;
            hasConnection[j] = true;
          }
        }
      }

      // Second pass: every isolated node gets one fallback line to its nearest neighbour
      ctx.lineWidth = 1;
      for (let i = 0; i < nodes.length; i++) {
        if (hasConnection[i]) continue;
        const a = nodes[i];
        let nearestJ = -1;
        let nearestD2 = Infinity;
        for (let j = 0; j < nodes.length; j++) {
          if (j === i) continue;
          const dx = a.x - nodes[j].x;
          const dy = a.y - nodes[j].y;
          const d2 = dx * dx + dy * dy;
          if (d2 < nearestD2) {
            nearestD2 = d2;
            nearestJ = j;
          }
        }
        if (nearestJ >= 0) {
          ctx.strokeStyle = `rgba(${MUTED}, 0.22)`;
          ctx.beginPath();
          ctx.moveTo(a.x, a.y);
          ctx.lineTo(nodes[nearestJ].x, nodes[nearestJ].y);
          ctx.stroke();
          hasConnection[i] = true;
        }
      }

      // Cursor → main link (the "user is connected to the master node")
      if (pointer.active && mainIdx >= 0) {
        const m = nodes[mainIdx];
        ctx.strokeStyle = `rgba(${ACCENT}, 0.75)`;
        ctx.lineWidth = 1.4;
        ctx.beginPath();
        ctx.moveTo(pointer.x, pointer.y);
        ctx.lineTo(m.x, m.y);
        ctx.stroke();
      }

      // Peer nodes
      ctx.fillStyle = `rgba(${MUTED}, 0.85)`;
      for (let i = 0; i < nodes.length; i++) {
        if (i === mainIdx) continue;
        const n = nodes[i];
        ctx.beginPath();
        ctx.arc(n.x, n.y, NODE_RADIUS, 0, Math.PI * 2);
        ctx.fill();
      }

      // Main node — accent, larger, ringed
      if (mainIdx >= 0) {
        const m = nodes[mainIdx];
        ctx.fillStyle = `rgba(${ACCENT}, 0.95)`;
        ctx.beginPath();
        ctx.arc(m.x, m.y, MAIN_RADIUS, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = `rgba(${ACCENT}, 0.4)`;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(m.x, m.y, MAIN_RADIUS + 5, 0, Math.PI * 2);
        ctx.stroke();
      }

      // Cursor marker — the "user" node
      if (pointer.active) {
        ctx.fillStyle = `rgba(${ACCENT}, 0.9)`;
        ctx.beginPath();
        ctx.arc(pointer.x, pointer.y, CURSOR_RADIUS, 0, Math.PI * 2);
        ctx.fill();
        ctx.strokeStyle = `rgba(${ACCENT}, 0.3)`;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(pointer.x, pointer.y, CURSOR_RADIUS + 4, 0, Math.PI * 2);
        ctx.stroke();
      }

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
