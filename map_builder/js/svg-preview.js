import {footprint, sizeOf} from './asset-catalog.js';

const REGION_TINT = {
  temperate_sparse: '#6b9d4e',
  temperate_dense: '#1e642e',
  old_growth: '#14512c',
  meadow: '#9cb551',
  rocky_scrub: '#7d7f5e',
  thicket: '#2f7a3a',
};

const SVG_NAMESPACE = 'http://www.w3.org/2000/svg';
const SURFACE_COLORS = {grass: '#557b43', sand: '#b89a5a', dirt: '#8a6747', stone: '#717470'};

function element(tag, attributes = {}) {
  const node = document.createElementNS(SVG_NAMESPACE, tag);
  Object.entries(attributes).forEach(([key, value]) => node.setAttribute(key, value));
  return node;
}

const point = (value, bounds, scale) => `${value[0] * scale},${(bounds.height_m - value[1]) * scale}`;

export function render(svg, state, ui) {
  const bounds = state.map.bounds;
  const scale = ui.pxPerMeter || 9;
  svg.replaceChildren();
  svg.setAttribute('viewBox', `0 0 ${bounds.width_m * scale} ${bounds.height_m * scale}`);
  svg.setAttribute('width', bounds.width_m * scale);
  svg.setAttribute('height', bounds.height_m * scale);
  svg.append(element('rect', {
    width: bounds.width_m * scale,
    height: bounds.height_m * scale,
    fill: SURFACE_COLORS[state.terrain?.surface] || SURFACE_COLORS.grass,
  }));

  const addSelectable = (node, key, id, index) => {
    node.classList.add('point');
    node.dataset.arrayKey = key;
    node.dataset.entityId = id;
    node.dataset.index = index;
    if (ui.selection?.kind === 'entity' && ui.selection.key === key && ui.selection.id === id) {
      node.classList.add('selected-shape');
    }
    svg.append(node);
  };

  (state.regions || []).forEach((region, index) => {
    const color = REGION_TINT[region.vegetation?.profile] || '#92935c';
    addSelectable(element('polygon', {
      points: (region.polygon || []).map(value => point(value, bounds, scale)).join(' '),
      fill: color,
      'fill-opacity': '.35',
      stroke: color,
    }), 'regions', region.id, index);
    (region.polygon || []).forEach((value, pointIndex) => {
      const x = value[0] * scale;
      const y = (bounds.height_m - value[1]) * scale;
      svg.append(element('circle', {cx: x, cy: y, r: 5, fill: '#fff', stroke: color, 'stroke-width': 2}));
      const label = element('text', {
        x: x + 7,
        y: y - 7,
        fill: '#fff',
        'font-size': 12,
        'font-weight': 'bold',
        'paint-order': 'stroke',
        stroke: '#1a251b',
        'stroke-width': 3,
      });
      label.textContent = String(pointIndex + 1);
      svg.append(label);
    });
  });

  for (const [key, color] of [['rivers', '#49a9df'], ['roads', '#c7a35e'], ['walls', '#646464']]) {
    (state[key] || []).forEach((path, index) => {
      addSelectable(element('polyline', {
        points: (path.control_points || []).map(value => point(value, bounds, scale)).join(' '),
        fill: 'none',
        stroke: color,
        'stroke-width': (path.width_m || 1) * scale,
        'stroke-linecap': key === 'walls' ? 'square' : 'round',
        'stroke-linejoin': 'round',
      }), key, path.id, index);
    });
  }

  const markers = {
    vegetation: ['circle', '#216b2d'],
    structures: ['rect', '#646464'],
    hills: ['rect', '#8a7357'],
    actors: ['circle', '#cf5151'],
    spawn_points: ['polygon', '#3e9ee8'],
    interactables: ['circle', '#ba78dc'],
    pickups: ['circle', '#4fd18a'],
    bridges: ['rect', '#d6b160'],
    objectives: ['path', '#f4e05b'],
    doors: ['rect', '#87573b'],
    encounters: ['circle', 'none'],
  };

  Object.entries(markers).forEach(([key, [tag, color]]) => {
    (state[key] || []).forEach((item, index) => {
      const x = item.position?.[0] * scale;
      const y = (bounds.height_m - item.position?.[1]) * scale;
      const radius = footprint(item.asset || item.archetype) * scale;
      const size = key === 'hills' ? sizeOf(item.asset) : null;
      const attributes = {
        fill: color,
        stroke: key === 'encounters' ? '#ffd05a' : '#171717',
        'stroke-width': 2,
      };
      if (size) {
        svg.append(element('rect', {
          x: x - size[0] * scale / 2,
          y: y - size[1] * scale / 2,
          width: size[0] * scale,
          height: size[1] * scale,
          class: 'asset-footprint',
          transform: `rotate(${-(item.rotation_deg || 0)} ${x} ${y})`,
        }));
      } else if (radius > 0) {
        svg.append(element('circle', {cx: x, cy: y, r: radius, class: 'asset-footprint'}));
      }
      if (tag === 'circle') Object.assign(attributes, {cx: x, cy: y, r: key === 'encounters' ? 10 : 6});
      if (tag === 'rect') Object.assign(attributes, {x: x - 6, y: y - 6, width: 12, height: 12});
      if (tag === 'polygon') attributes.points = `${x},${y - 7} ${x - 7},${y + 6} ${x + 7},${y + 6}`;
      if (tag === 'path') {
        attributes.d = `M ${x} ${y - 8} L ${x + 7} ${y - 4} L ${x + 3} ${y + 7} L ${x - 5} ${y + 7} L ${x - 7} ${y - 4} Z`;
      }
      if (key === 'encounters') attributes['stroke-dasharray'] = '4 3';
      addSelectable(element(tag, attributes), key, item.id, index);
      if (key === 'hills') {
        // Summit height decides who can jump it, so terraces show it at a glance.
        const modelHeight = Number(String(item.asset || '').split('x').pop());
        const height = item.height_m ?? modelHeight;
        if (Number.isFinite(height)) {
          const label = element('text', {x: x + 8, y: y - 8, fill: '#f3e6cf', 'font-size': 11, 'pointer-events': 'none'});
          label.textContent = `${height} m${item.jumpable ? ' ⤓' : ''}`;
          svg.append(label);
        }
      }
    });
  });

  if (state.player?.character_asset) {
    const star = element('text', {x: 10, y: bounds.height_m * scale - 10, fill: '#ffe274', 'font-size': 18});
    star.textContent = '★';
    svg.append(star);
  }
  if (ui.draftShapePoints.length) {
    svg.append(element('polyline', {
      points: ui.draftShapePoints.map(value => point(value, bounds, scale)).join(' '),
      class: 'draft',
    }));
  }
}

export function screenToWorld(svg, event, bounds) {
  const rectangle = svg.getBoundingClientRect();
  const round = value => Math.round(value * 100) / 100;
  return [
    round(Math.max(0, Math.min(bounds.width_m, (event.clientX - rectangle.left) / rectangle.width * bounds.width_m))),
    round(Math.max(0, Math.min(bounds.height_m, bounds.height_m - (event.clientY - rectangle.top) / rectangle.height * bounds.height_m))),
  ];
}
