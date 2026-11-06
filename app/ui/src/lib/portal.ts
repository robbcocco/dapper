/**
 * `use:portal` — re-parents the node under `<body>` so `position: fixed` overlays escape
 * ancestors that form a containing block (the bottom bar's `backdrop-filter`) and their
 * `overflow: hidden` clipping.
 */
export function portal(node: HTMLElement): { destroy: () => void } {
  document.body.appendChild(node);
  return { destroy: () => node.remove() };
}
