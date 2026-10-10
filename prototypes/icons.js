// Small, local SVG set so this review does not depend on a CDN.
globalThis.renderPrototypeIcons = function(root) {
  const paths = {
    'moon-star': '<path d="M20.8 13A8.5 8.5 0 0 1 11 3.2 8.5 8.5 0 1 0 20.8 13Z"/><path d="m18 2 .6 2.4L21 5l-2.4.6L18 8l-.6-2.4L15 5l2.4-.6Z"/>',
    'activity': '<path d="M2 12h4l3-8 5 16 3-8h5"/>',
    'settings-2': '<path d="M3 6h5m4 0h9M3 12h11m4 0h3M3 18h2m4 0h12"/><circle cx="10" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="7" cy="18" r="2"/>',
    'sliders-horizontal': '<path d="M3 6h5m4 0h9M3 12h11m4 0h3M3 18h2m4 0h12"/><circle cx="10" cy="6" r="2"/><circle cx="16" cy="12" r="2"/><circle cx="7" cy="18" r="2"/>',
    'music-2': '<path d="M10 17V4l10-2v13M10 7l10-2"/><ellipse cx="7" cy="18" rx="3" ry="2"/><ellipse cx="17" cy="16" rx="3" ry="2"/>',
    'chevron-right': '<path d="m9 5 7 7-7 7"/>',
    'chevron-down': '<path d="m5 9 7 7 7-7"/>',
    'pause': '<path d="M8 5v14M16 5v14"/>',
    'bell': '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/>',
    'bell-ring': '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4M3 3 1 6M21 3l2 3"/>',
    'history': '<path d="M3 11a9 9 0 1 1 2.5 7M3 4v7h7m2-5v6l4 2"/>',
    'check': '<path d="m4 12 5 5L20 6"/>',
    'shield-check': '<path d="M12 2 3 6v6c0 5 9 10 9 10s9-5 9-10V6Z"/><path d="m8 12 3 3 5-6"/>',
    'plus': '<path d="M12 4v16M4 12h16"/>',
    'pencil': '<path d="m4 16-1 5 5-1L20 8l-4-4Z"/><path d="m14 6 4 4"/>',
    'send': '<path d="m22 2-7 20-4-9-9-4Z"/><path d="m11 13 11-11"/>',
    'globe': '<circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c5 5 5 13 0 18-5-5-5-13 0-18Z"/>',
    'terminal': '<rect x="2" y="4" width="20" height="16" rx="3"/><path d="m6 9 3 3-3 3m6 0h5"/>',
    'coffee': '<path d="M4 8h13v8a4 4 0 0 1-4 4H8a4 4 0 0 1-4-4Zm13 1h2a3 3 0 0 1 0 6h-2M7 2v3m4-3v3m4-3v3M2 22h18"/>',
    'volume-2': '<path d="m11 4-6 5H2v6h3l6 5Zm4 4a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
    'cpu': '<rect x="5" y="5" width="14" height="14" rx="2"/><rect x="9" y="9" width="6" height="6"/><path d="M9 2v3m6-3v3M9 19v3m6-3v3M2 9h3m-3 6h3m14-6h3m-3 6h3"/>',
    'monitor': '<rect x="2" y="3" width="20" height="14" rx="2"/><path d="M12 17v4m-4 0h8"/>',
    'screen-share': '<path d="M13 4H4a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2v-3M12 18v4m-4 0h8m1-20 5 5-5 5m-5-5h10"/>',
    'play': '<path d="m7 3 14 9-14 9Z"/>',
    'refresh-cw': '<path d="M21 4v6h-6M3 20v-6h6M4 8a9 9 0 0 1 15-3l2 5M3 14l2 5a9 9 0 0 0 15-3"/>',
    'webhook': '<circle cx="6" cy="17" r="4"/><circle cx="18" cy="17" r="4"/><circle cx="12" cy="5" r="3"/><path d="m10 7-4 10m8-10 4 10M6 17h12"/>',
    'messages-square': '<path d="M3 3h14v11H7l-4 4Zm14 5h4v13l-4-3h-7v-4"/>',
    'hash': '<path d="M10 3 8 21M17 3l-2 18M4 8h17M3 16h17"/>',
    'mail': '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m2 6 10 7L22 6"/>',
    'app-window': '<rect x="2" y="3" width="20" height="18" rx="3"/><path d="M2 8h20M6 5h.01M9 5h.01"/>',
    'key-round': '<circle cx="8" cy="8" r="5"/><path d="m12 12 9 9m-3-3 3-3m-6 0 3-3"/>',
    'monitor-off': '<path d="M21 14V5a2 2 0 0 0-2-2H7M3 7v8a2 2 0 0 0 2 2h14M12 17v4m-4 0h8M2 2l20 20"/>',
    'lock-keyhole': '<rect x="4" y="10" width="16" height="12" rx="2"/><path d="M8 10V6a4 4 0 0 1 8 0v4m-4 5v3"/>',
    'circle-x': '<circle cx="12" cy="12" r="9"/><path d="m9 9 6 6m0-6-6 6"/>',
    'ellipsis': '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    'user-round': '<circle cx="12" cy="7" r="4"/><path d="M4 22v-3a8 8 0 0 1 16 0v3"/>',
    'search': '<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>'
  };
  root.querySelectorAll('i[data-lucide]').forEach(element => {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke', 'currentColor'); svg.setAttribute('stroke-width', '1.65');
    svg.setAttribute('stroke-linecap', 'round'); svg.setAttribute('stroke-linejoin', 'round');
    svg.setAttribute('width', '16'); svg.setAttribute('height', '16'); svg.setAttribute('aria-hidden', 'true');
    svg.innerHTML = paths[element.dataset.lucide] || paths['app-window'];
    element.replaceWith(svg);
  });
};
