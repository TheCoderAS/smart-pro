"use client";

import { useEffect, useRef } from "react";

/**
 * Full-page connected-nodes mesh.
 *
 *  - Always places NODE_COUNT (60) nodes regardless of viewport. When
 *    the viewport is too small to comfortably fit them at the target
 *    spacing, the spacing shrinks rather than dropping nodes — the
 *    mesh density story stays the same on every device, only the gap
 *    adjusts. CONNECT_DISTANCE scales in lockstep with MIN_DISTANCE
 *    so the connectivity feel is preserved.
 *  - Nodes drift slowly across the viewport (gentle ambient motion).
 *    Initial placement uses Poisson-disc rejection sampling so no two
 *    nodes start within minDistance of each other; a per-frame
 *    repulsion keeps that constraint while they drift.
 *  - Motion is strictly planar (2D x/y); no depth dimension, no
 *    parallax, no scale-by-z effects.
 *  - Edges are rebuilt every frame: all pairs within connectDistance
 *    are candidates, sorted by distance and greedily added so no node
 *    exceeds MAX_DEGREE peer connections. Any node still isolated
 *    after that gets one fallback edge to its nearest neighbour, so
 *    every node always has ≥1 connection.
 *  - The cursor is the "user". The nearest node to the cursor is the
 *    "main". An accent line runs from cursor → main, independent of
 *    the MAX_DEGREE cap (the "+1 user connection"). The main is
 *    rendered larger and accent-coloured, and its peer edges are
 *    drawn in accent.
 *
 * Performance discipline:
 *  - Single canvas, single RAF loop.
 *  - `visibilitychange` pauses the loop when the tab is hidden.
 *  - Skipped entirely for `prefers-reduced-motion: reduce`.
 *  - DPR capped at 2.
 *  - Two O(N^2) passes per frame (repulsion + edge build) on N = 60.
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

    // Tuning targets
    const NODE_COUNT = 60;
    const MIN_DISTANCE_TARGET = 150; // ideal min-spacing on a big enough viewport
    const CONNECT_DISTANCE_RATIO = 260 / 150; // peer-edge threshold relative to min-spacing
    const MAX_DEGREE = 8; // max peer connections per node (cursor link is separate)
    const DRIFT = 0.08; // base velocity, px per ~16ms frame
    const NODE_RADIUS = 1.8;
    const MAIN_RADIUS = 4.5;
    const CURSOR_RADIUS = 3;
    const POINTER_REACH = 360;
    const ACCENT = "217, 119, 87";
    const MUTED = "138, 135, 128";

    // Runtime spacing — auto-shrunk on small viewports so all NODE_COUNT
    // nodes still fit. Recomputed in computeSpacing() on mount and resize.
    let minDistance = MIN_DISTANCE_TARGET;
    let connectDistance = MIN_DISTANCE_TARGET * CONNECT_DISTANCE_RATIO;

    type Node = { x: number; y: number; vx: number; vy: number };
    type Edge = { i: number; j: number; d: number };
    let nodes: Node[] = [];
    let edges: Edge[] = [];

    const pointer = { x: -10000, y: -10000, active: false };

    // Largest min-distance that still lets all NODE_COUNT nodes pack into
    // the current viewport, capped at the design target. Factor 1.3
    // accounts for real-world Poisson-disc packing inefficiency — the disc
    // sampler fills roughly half the area before getting stuck, so each
    // node empirically claims ~1.3 × d² of working area.
    const computeSpacing = () => {
      const dCap = Math.sqrt((width * height) / (NODE_COUNT * 1.3));
      minDistance = Math.min(MIN_DISTANCE_TARGET, dCap);
      connectDistance = minDistance * CONNECT_DISTANCE_RATIO;
    };

    // Poisson-disc rejection sampling — accept a candidate only if it's
    // ≥ minDistance from every already-placed node. Node count is fixed
    // at NODE_COUNT; the spacing is what flexes for small viewports.
    const seed = () => {
      computeSpacing();
      nodes = [];
      const minD2 = minDistance * minDistance;
      const maxAttempts = NODE_COUNT * 120;
      let attempts = 0;
      while (nodes.length < NODE_COUNT && attempts < maxAttempts) {
        attempts++;
        const x = Math.random() * width;
        const y = Math.random() * height;
        let ok = true;
        for (const n of nodes) {
          const dx = n.x - x;
          const dy = n.y - y;
          if (dx * dx + dy * dy < minD2) {
            ok = false;
            break;
          }
        }
        if (ok) {
          nodes.push({
            x,
            y,
            vx: (Math.random() - 0.5) * DRIFT * 2,
            vy: (Math.random() - 0.5) * DRIFT * 2,
          });
        }
      }
    };

    // Greedy edge construction, capped at MAX_DEGREE. Backfill guarantees ≥1 per node.
    const buildEdges = () => {
      const cd2 = connectDistance * connectDistance;
      const cands: Edge[] = [];
      for (let i = 0; i < nodes.length; i++) {
        for (let j = i + 1; j < nodes.length; j++) {
          const dx = nodes[i].x - nodes[j].x;
          const dy = nodes[i].y - nodes[j].y;
          const d2 = dx * dx + dy * dy;
          if (d2 < cd2) {
            cands.push({ i, j, d: Math.sqrt(d2) });
          }
        }
      }
      cands.sort((a, b) => a.d - b.d);

      const deg = new Array<number>(nodes.length).fill(0);
      edges = [];
      for (const c of cands) {
        if (deg[c.i] >= MAX_DEGREE) continue;
        if (deg[c.j] >= MAX_DEGREE) continue;
        edges.push(c);
        deg[c.i]++;
        deg[c.j]++;
      }

      // Backfill — any node still at degree 0 gets one edge to its absolute nearest neighbour.
      for (let i = 0; i < nodes.length; i++) {
        if (deg[i] > 0) continue;
        let nearestJ = -1;
        let nearestD = Infinity;
        for (let j = 0; j < nodes.length; j++) {
          if (j === i) continue;
          const dx = nodes[i].x - nodes[j].x;
          const dy = nodes[i].y - nodes[j].y;
          const d = Math.hypot(dx, dy);
          if (d < nearestD) {
            nearestD = d;
            nearestJ = j;
          }
        }
        if (nearestJ >= 0) {
          edges.push({ i, j: nearestJ, d: nearestD });
          deg[i]++;
          deg[nearestJ]++;
        }
      }
    };

    const resize = () => {
      const newW = window.innerWidth;
      const newH = window.innerHeight;
      const oldW = width;
      const oldH = height;
      width = newW;
      height = newH;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

      if (nodes.length === 0) {
        seed();
      } else if (oldW > 0 && oldH > 0) {
        const sx = newW / oldW;
        const sy = newH / oldH;
        for (const n of nodes) {
          n.x *= sx;
          n.y *= sy;
        }
        // Adapt spacing to the new viewport so connectivity and repulsion stay sensible.
        computeSpacing();
      }
    };

    const findMain = (): number => {
      if (!pointer.active) return -1;
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
      if (bestD > POINTER_REACH * POINTER_REACH) return -1;
      return best;
    };

    const draw = () => {
      ctx.clearRect(0, 0, width, height);
      const mainIdx = findMain();

      // Edges — alpha has a brightness floor so even the longest edges remain visible.
      for (const e of edges) {
        const a = nodes[e.i];
        const b = nodes[e.j];
        const near = 1 - e.d / connectDistance;
        const isMainEdge = e.i === mainIdx || e.j === mainIdx;
        if (isMainEdge) {
          const alpha = 0.55 + near * 0.35;
          ctx.strokeStyle = `rgba(${ACCENT}, ${alpha})`;
          ctx.lineWidth = 1.3;
        } else {
          const alpha = 0.35 + near * 0.25;
          ctx.strokeStyle = `rgba(${MUTED}, ${alpha})`;
          ctx.lineWidth = 1;
        }
        ctx.beginPath();
        ctx.moveTo(a.x, a.y);
        ctx.lineTo(b.x, b.y);
        ctx.stroke();
      }

      // Cursor → main link — outside the MAX_DEGREE cap (the "+1 user connection").
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

      // Main node
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

      // Cursor marker
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
    };

    let raf = 0;
    let lastT = performance.now();
    let running = true;

    const step = (t: number) => {
      const dt = Math.min((t - lastT) / 16.67, 2);
      lastT = t;

      // Drift
      for (const n of nodes) {
        n.x += n.vx * dt;
        n.y += n.vy * dt;
      }

      // Min-distance repulsion — any pair closer than minDistance is pushed
      // apart along the line between them. Push is capped per frame so
      // overlap resolves smoothly over several frames rather than snapping.
      const minD2 = minDistance * minDistance;
      const maxPush = minDistance * 0.1;
      for (let i = 0; i < nodes.length; i++) {
        for (let j = i + 1; j < nodes.length; j++) {
          const dx = nodes[i].x - nodes[j].x;
          const dy = nodes[i].y - nodes[j].y;
          const d2 = dx * dx + dy * dy;
          if (d2 < minD2 && d2 > 0.0001) {
            const d = Math.sqrt(d2);
            const overlap = minDistance - d;
            const push = Math.min(overlap * 0.5, maxPush);
            const nx = (dx / d) * push;
            const ny = (dy / d) * push;
            nodes[i].x += nx;
            nodes[i].y += ny;
            nodes[j].x -= nx;
            nodes[j].y -= ny;
          }
        }
      }

      // Viewport bounce — applied after repulsion so a pushed node can't escape the canvas.
      for (const n of nodes) {
        if (n.x < 0) {
          n.x = 0;
          n.vx = Math.abs(n.vx);
        } else if (n.x > width) {
          n.x = width;
          n.vx = -Math.abs(n.vx);
        }
        if (n.y < 0) {
          n.y = 0;
          n.vy = Math.abs(n.vy);
        } else if (n.y > height) {
          n.y = height;
          n.vy = -Math.abs(n.vy);
        }
      }

      buildEdges();
      draw();

      if (running) raf = requestAnimationFrame(step);
    };

    resize();
    raf = requestAnimationFrame(step);

    const onResize = () => resize();
    const onPointerMove = (e: PointerEvent) => {
      pointer.x = e.clientX;
      pointer.y = e.clientY;
      pointer.active = true;
    };
    const onPointerOut = (e: PointerEvent) => {
      if (e.relatedTarget === null) {
        pointer.active = false;
      }
    };
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

    window.addEventListener("resize", onResize);
    window.addEventListener("pointermove", onPointerMove);
    window.addEventListener("pointerout", onPointerOut);
    document.addEventListener("visibilitychange", onVisibility);

    return () => {
      running = false;
      if (raf) cancelAnimationFrame(raf);
      window.removeEventListener("resize", onResize);
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
