"use client";

import { useRef } from "react";
import { motion, useScroll, useTransform } from "framer-motion";

/**
 * Architecture diagram — dark-themed adaptation of the supplied
 * unisync_architecture.svg. Shows two switchboards (Living Room, Bedroom),
 * each with one Master + one Extension on a local bus, joined by a dashed
 * mesh arc. Used inside the Product section.
 *
 * Colour mapping from the source SVG → site palette:
 *   #1F4E79 (navy primary)    → var(--fg-muted) for strokes, var(--accent) for ON states
 *   #5A6573 (gray secondary)  → var(--fg-faint)
 *   #0F1419 (text)            → var(--fg)
 *   #D1D5DB (faint border)    → var(--fg-faint) at low opacity
 *   #FAF8F3 (cream bg)        → transparent (let section bg show through)
 */
export function ArchitectureDiagram() {
  const ref = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ["start end", "end start"],
  });
  const y = useTransform(scrollYProgress, [0, 1], [40, -40]);

  return (
    <motion.div
      ref={ref}
      style={{ y }}
      className="w-full"
      role="img"
      aria-label="Architecture diagram: two switchboards, each with one Master and one Extension on a local bus, linked by a wireless mesh."
    >
      <svg
        viewBox="0 0 1200 600"
        fill="none"
        className="w-full h-auto"
      >
        {/* Mesh arc — drawn first so it sits behind */}
        <path
          d="M 280 165 Q 600 50 920 165"
          stroke="var(--accent)"
          strokeWidth="1.5"
          strokeDasharray="6 6"
          fill="none"
          opacity="0.5"
        />

        {/* Mesh dots along the arc */}
        <circle cx="380" cy="115" r="2.5" fill="var(--accent)" opacity="0.3" />
        <circle cx="500" cy="80" r="2.5" fill="var(--accent)" opacity="0.5" />
        <circle cx="600" cy="68" r="2.5" fill="var(--accent)" opacity="0.7" />
        <circle cx="700" cy="80" r="2.5" fill="var(--accent)" opacity="0.5" />
        <circle cx="820" cy="115" r="2.5" fill="var(--accent)" opacity="0.3" />

        {/* MESH label pill */}
        <g transform="translate(600, 70)">
          <rect
            x="-40"
            y="-16"
            width="80"
            height="26"
            rx="13"
            fill="none"
            stroke="var(--accent)"
            strokeWidth="1"
          />
          <text
            x="0"
            y="2"
            textAnchor="middle"
            dominantBaseline="central"
            fill="var(--accent)"
            fontSize="12"
            fontWeight="600"
            letterSpacing="0.5"
            fontFamily="var(--font-mono), monospace"
          >
            MESH
          </text>
        </g>

        {/* Switchboard A — Living Room */}
        <Switchboard
          x={100}
          y={180}
          roomLabel="LIVING ROOM"
          masterLedOn={true}
        />

        {/* Switchboard B — Bedroom */}
        <Switchboard
          x={740}
          y={180}
          roomLabel="BEDROOM"
          masterLedOn={true}
          extensionLedOn={true}
        />

        {/* Bottom three-line legend */}
        <g transform="translate(600, 460)" textAnchor="middle">
          <text
            y="0"
            fill="var(--fg)"
            fontSize="16"
            fontWeight="500"
            fontFamily="var(--font-display), serif"
          >
            One Master per switchboard.
          </text>
          <text
            y="24"
            fill="var(--fg)"
            fontSize="16"
            fontWeight="500"
            fontFamily="var(--font-display), serif"
          >
            Up to 5 Extensions on a local bus.
          </text>
          <text
            y="48"
            fill="var(--fg)"
            fontSize="16"
            fontWeight="500"
            fontFamily="var(--font-display), serif"
          >
            Multiple switchboards meshed across the home.
          </text>
        </g>

        {/* Bottom legend swatches */}
        <g
          transform="translate(350, 540)"
          fontSize="11"
          fill="var(--fg-muted)"
          fontFamily="var(--font-mono), monospace"
        >
          <circle cx="0" cy="0" r="5" fill="var(--accent)" />
          <text x="12" y="4">switch ON</text>

          <circle
            cx="100"
            cy="0"
            r="5"
            fill="none"
            stroke="var(--fg-faint)"
            strokeWidth="1"
          />
          <text x="112" y="4">switch OFF</text>

          <line
            x1="220"
            y1="0"
            x2="240"
            y2="0"
            stroke="var(--accent)"
            strokeWidth="1.5"
            strokeDasharray="4 4"
            opacity="0.55"
          />
          <text x="248" y="4">mesh link</text>

          <line
            x1="350"
            y1="0"
            x2="370"
            y2="0"
            stroke="var(--fg-muted)"
            strokeWidth="2"
          />
          <text x="378" y="4">bus cable</text>
        </g>
      </svg>
    </motion.div>
  );
}

function Switchboard({
  x,
  y,
  roomLabel,
  masterLedOn,
  extensionLedOn = false,
}: {
  x: number;
  y: number;
  roomLabel: string;
  masterLedOn: boolean;
  extensionLedOn?: boolean;
}) {
  return (
    <g transform={`translate(${x}, ${y})`}>
      {/* Room label */}
      <text
        x="180"
        y="-12"
        textAnchor="middle"
        fill="var(--fg-muted)"
        fontSize="12"
        fontWeight="400"
        letterSpacing="1.5"
        fontFamily="var(--font-mono), monospace"
      >
        {roomLabel}
      </text>

      {/* Switchboard outline */}
      <rect
        x="0"
        y="0"
        width="360"
        height="200"
        rx="10"
        fill="none"
        stroke="var(--fg-faint)"
        strokeWidth="1"
      />

      {/* Master module */}
      <g transform="translate(20, 25)">
        <rect
          x="0"
          y="0"
          width="120"
          height="150"
          rx="6"
          fill="none"
          stroke="var(--fg-muted)"
          strokeWidth="1.5"
        />
        {/* Switch pad ON */}
        <circle cx="60" cy="40" r="14" fill={masterLedOn ? "var(--accent)" : "none"} stroke={masterLedOn ? "none" : "var(--fg-faint)"} strokeWidth="1" />
        {/* Switch pad OFF */}
        <circle cx="60" cy="80" r="14" fill="none" stroke="var(--fg-faint)" strokeWidth="1" />
        {/* Wi-Fi waves icon */}
        <g
          transform="translate(15, 15)"
          fill="none"
          stroke="var(--fg-muted)"
          strokeWidth="1.3"
          strokeLinecap="round"
        >
          <path d="M 0 6 Q 6 -2 12 6" />
          <path d="M 2 8 Q 6 2 10 8" />
          <circle cx="6" cy="9" r="1" fill="var(--fg-muted)" />
        </g>
        <text
          x="60"
          y="135"
          textAnchor="middle"
          fill="var(--fg)"
          fontSize="11"
          fontWeight="600"
          letterSpacing="1"
          fontFamily="var(--font-mono), monospace"
        >
          MASTER
        </text>
      </g>

      {/* Bus cable */}
      <line
        x1="140"
        y1="100"
        x2="180"
        y2="100"
        stroke="var(--fg-muted)"
        strokeWidth="2"
        strokeLinecap="round"
      />
      <text
        x="160"
        y="92"
        textAnchor="middle"
        fill="var(--fg-muted)"
        fontSize="9"
        fontWeight="500"
        letterSpacing="0.5"
        fontFamily="var(--font-mono), monospace"
      >
        BUS
      </text>

      {/* Extension module */}
      <g transform="translate(180, 25)">
        <rect
          x="0"
          y="0"
          width="120"
          height="150"
          rx="6"
          fill="none"
          stroke="var(--fg-faint)"
          strokeWidth="1"
        />
        <circle cx="60" cy="40" r="14" fill={extensionLedOn ? "var(--accent)" : "none"} stroke={extensionLedOn ? "none" : "var(--fg-faint)"} strokeWidth="1" />
        <circle cx="60" cy="80" r="14" fill="none" stroke="var(--fg-faint)" strokeWidth="1" />
        <text
          x="60"
          y="135"
          textAnchor="middle"
          fill="var(--fg)"
          fontSize="11"
          fontWeight="600"
          letterSpacing="1"
          fontFamily="var(--font-mono), monospace"
        >
          EXTENSION
        </text>
      </g>

      {/* "up to 5" hint dots */}
      <g transform="translate(310, 90)" fill="var(--fg-faint)">
        <circle cx="0" cy="0" r="2" />
        <circle cx="10" cy="0" r="2" />
        <circle cx="20" cy="0" r="2" />
        <text
          x="35"
          y="3"
          fontSize="10"
          fontWeight="400"
          fill="var(--fg-muted)"
          fontFamily="var(--font-mono), monospace"
        >
          up to 5
        </text>
      </g>
    </g>
  );
}
