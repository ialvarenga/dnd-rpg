import {getState, findEntity, updateEntity, removeEntity} from '../state.js';
import {ENUMS} from '../schema-constants.js';
import {nextId} from '../id-generator.js';
import {families, firstId, search} from '../asset-catalog.js';
import {CONFIGS} from './entity-type-configs.js';

const esc = value => String(value ?? '')
  .replaceAll('&', '&amp;')
  .replaceAll('"', '&quot;')
  .replaceAll('<', '&lt;');

const positionFields = (value = [0, 0]) =>
  `<div class="row">
    <label>East (m)<input data-field="position.0" type="number" value="${value[0] ?? 0}"></label>
    <label>North (m)<input data-field="position.1" type="number" value="${value[1] ?? 0}"></label>
  </div>`;

const select = (label, field, value, items, optional = false) =>
  `<label>${label}<select data-field="${field}" ${optional ? 'data-optional' : ''}>
    ${optional ? '<option value="">— none —</option>' : ''}
    ${items.map(item => `<option value="${esc(item)}" ${item === value ? 'selected' : ''}>${esc(item)}</option>`).join('')}
  </select></label>`;

function referenceOptions(items, selected, optional) {
  const values = [...items];
  if (selected && !values.includes(selected)) values.push(selected);
  return `${optional ? '<option value="">— none —</option>' : ''}
    ${values.map(value => `<option value="${esc(value)}" ${value === selected ? 'selected' : ''}>
      ${esc(value)}${!items.includes(value) ? ' (missing)' : ''}
    </option>`).join('')}`;
}

function referenceSelect(label, field, selected, items, optional = false) {
  return `<label>${label}<select data-field="${field}" ${optional ? 'data-optional' : ''}>
    ${referenceOptions(items, selected, optional)}
  </select></label>`;
}

function multiReferenceSelect(label, field, selected = [], items = []) {
  const values = [...items];
  for (const value of selected) if (!values.includes(value)) values.push(value);
  const size = Math.min(7, Math.max(3, values.length));
  return `<label>${label}<select data-array-field="${field}" multiple size="${size}">
    ${values.map(value => `<option value="${esc(value)}" ${selected.includes(value) ? 'selected' : ''}>
      ${esc(value)}${!items.includes(value) ? ' (missing)' : ''}
    </option>`).join('')}
  </select><small>Use Ctrl/Cmd to select more than one.</small></label>`;
}

const points = (field, items = []) =>
  `<div class="points">
    <strong>${field === 'polygon' ? 'Polygon points' : 'Path points'}</strong>
    <small>Add at least ${field === 'polygon' ? 3 : 2} east/north points.</small>
    ${items.map((point, index) => `<div class="point-row">
      <span>${index + 1}</span>
      <label>X<input type="number" data-point="${field}.${index}.0" value="${point[0] ?? 0}"></label>
      <label>Y<input type="number" data-point="${field}.${index}.1" value="${point[1] ?? 0}"></label>
      <button type="button" class="icon-button" data-remove-point="${field}.${index}" aria-label="Remove point ${index + 1}">×</button>
    </div>`).join('')}
    <button type="button" class="secondary" data-add-point="${field}">Add point</button>
    <details class="advanced-fields"><summary>Raw coordinate JSON</summary>
      <textarea data-field="${field}" rows="5">${esc(JSON.stringify(items))}</textarea>
    </details>
  </div>`;

function assetOptions(type, value, query = '') {
  const matches = search(type, query);
  return families(type).map(family => {
    const options = matches.filter(asset => asset.family === family).map(asset =>
      `<option value="${asset.id}" ${asset.id === value ? 'selected' : ''}>
        ${esc(asset.label)} — ${asset.footprint_radius.toFixed(2)} m
      </option>`
    ).join('');
    return options ? `<optgroup label="${esc(family)}">${options}</optgroup>` : '';
  }).join('');
}

const assetPicker = (field, value, type) =>
  `<label>${field === 'archetype' ? 'Archetype' : 'Asset'}
    <input class="asset-filter" data-asset-filter="${type}" type="search" placeholder="Filter assets…">
    <select data-field="${field}" data-asset-type="${type}">${assetOptions(type, value)}</select>
  </label>`;

export function defaultEntity(key, position = [32, 32]) {
  const config = CONFIGS[key];
  const entity = {id: nextId(key)};
  if (config.shape === 'polygon') return {...entity, polygon: []};
  if (config.shape === 'path') return {...entity, control_points: [], width_m: 3};
  if (config.shape === 'wall') {
    return {...entity, asset: config.defaultAsset || 'wall_dungeon_01', control_points: []};
  }
  if (config.assetType) entity[config.assetField || 'asset'] = config.defaultAsset || firstId(config.assetType);
  if (config.kind) entity.kind = 'chest';
  if (config.side) {
    entity.side = 'enemies';
    entity.initial_disposition = 'hostile';
  }
  if (config.item) entity.item_id = 'healing_potion';
  if (config.bridge) Object.assign(entity, {position, river_id: 'river_1', road_id: 'road_1'});
  else if (config.door) Object.assign(entity, {position, initial_state: 'closed', required_state: 'open'});
  else if (config.encounter) Object.assign(entity, {position, actor_ids: []});
  else if (config.dialog) {
    Object.assign(entity, {
      root: 'greeting',
      nodes: [{id: 'greeting', text: 'They block the road.', options: [{text: 'Leave.', outcome: {effect: 'end'}}]}],
    });
  } else Object.assign(entity, {position});
  return entity;
}

function editableFields(key, entity, {identity = true, spatial = true} = {}) {
  const config = CONFIGS[key];
  const state = getState();
  let html = '';

  if (identity) html += `<label>ID<input data-field="id" value="${esc(entity.id)}"></label>`;
  if (config.assetType) {
    const assetField = config.assetField || 'asset';
    html += assetPicker(assetField, entity[assetField], config.assetType);
  }
  if (config.kind) html += select('Kind', 'kind', entity.kind, ENUMS.kind);
  if (config.side) {
    html += select('Side', 'side', entity.side ?? 'enemies', ENUMS.side);
    html += select('Initial disposition', 'initial_disposition', entity.initial_disposition ?? 'hostile', ENUMS.disposition);
    html += `<label>Stat block <small>ActorDefinition ID, optional</small><input data-field="stat_block" data-optional value="${esc(entity.stat_block ?? '')}"></label>`;
    html += referenceSelect('Dialog', 'dialog', entity.dialog, (state.dialogs || []).map(value => value.id), true);
  }
  if (config.item) html += `<label>Item ID<input data-field="item_id" value="${esc(entity.item_id)}"></label>`;

  if (spatial) {
    if (config.shape) {
      const field = config.shape === 'polygon' ? 'polygon' : 'control_points';
      html += points(field, entity[field] || []);
      if (config.shape === 'wall') html += '<p class="help">A wall uses exactly two points.</p>';
    } else if (!config.dialog) html += positionFields(entity.position);
  }

  if (config.dialog) {
    html += `<label>Root node ID<input data-field="root" value="${esc(entity.root)}"></label>
      <label>Nodes JSON <small>A check requires a failure_outcome.</small>
        <textarea data-field="nodes" rows="16">${esc(JSON.stringify(entity.nodes ?? [], null, 2))}</textarea>
      </label>`;
  }

  if (['vegetation', 'structures', 'hills', 'actors', 'interactables', 'pickups'].includes(key)) {
    html += `<label>Rotation (degrees, optional)<input data-field="rotation_deg" data-optional type="number" value="${entity.rotation_deg ?? ''}"></label>`;
  }
  if (key === 'hills') html += `<label><input data-field="navigable" type="checkbox" ${entity.navigable ? 'checked' : ''}> Generate reachable summit ramp</label>`;
  if (config.bridge) {
    html += referenceSelect('River', 'river_id', entity.river_id, (state.rivers || []).map(value => value.id));
    html += referenceSelect('Road', 'road_id', entity.road_id, (state.roads || []).map(value => value.id));
  }
  if (config.encounter) {
    html += multiReferenceSelect('Actors', 'actor_ids', entity.actor_ids || [], (state.actors || []).map(value => value.id));
    html += `<label>Trigger radius (m, optional)<input data-field="trigger_radius_m" data-optional type="number" value="${entity.trigger_radius_m ?? ''}"></label>`;
    html += `<label><input data-field="skip_surprised_round_one" type="checkbox" ${entity.skip_surprised_round_one ? 'checked' : ''}> Skip surprised actors in round 1</label>`;
  }
  if (key === 'objectives') {
    html += `<label>Radius (m, optional)<input data-field="radius_m" data-optional type="number" value="${entity.radius_m ?? ''}"></label>`;
    html += multiReferenceSelect('Required encounters', 'requires_encounter_ids', entity.requires_encounter_ids || [], (state.encounters || []).map(value => value.id));
  }
  if (key === 'interactables') {
    html += `<label>Contents <small>Comma-separated item IDs</small><input data-list-field="contents" value="${esc((entity.contents || []).join(', '))}"></label>`;
    if (entity.kind === 'explosive_barrel') html += `<label>Blast radius (m)<input data-field="blast_radius_m" type="number" min="0.1" max="12" value="${entity.blast_radius_m ?? 3.5}"></label><label>Damage die<input data-field="blast_damage_die" type="number" min="4" max="12" step="2" value="${entity.blast_damage_die ?? 6}"></label><label>Damage dice count<input data-field="blast_damage_dice_count" type="number" min="1" max="8" value="${entity.blast_damage_dice_count ?? 2}"></label>`;
  }
  if (config.door) {
    html += select('Initial state', 'initial_state', entity.initial_state, ENUMS.doorState);
    html += select('Required state', 'required_state', entity.required_state, ENUMS.doorState);
  }
  if (key === 'regions') {
    html += select('Vegetation profile', 'vegetation.profile', entity.vegetation?.profile, ENUMS.vegetationProfile, true);
    html += `<label>Vegetation density<input data-field="vegetation.density" data-optional type="number" min="0" max="1" step="0.05" value="${entity.vegetation?.density ?? ''}"></label>`;
    html += select('Weighted terrain', 'terrain_type', entity.terrain_type, ENUMS.terrainType, true);
    html += `<label>Movement cost multiplier<input data-field="movement_cost" data-optional type="number" min="1" max="4" step="0.25" value="${entity.movement_cost ?? ''}"></label>`;
  }
  if ((key === 'rivers' || key === 'roads')) {
    html += `<label>Width (m)<input data-field="width_m" type="number" min="0.1" max="24" value="${entity.width_m ?? 3}"></label>`;
    html += `<label>Movement cost multiplier<input data-field="movement_cost" data-optional type="number" min="1" max="4" step="0.25" value="${entity.movement_cost ?? ''}"></label>`;
  }
  return html;
}

export function collectionInspector(key) {
  const config = CONFIGS[key];
  const count = (getState()[key] || []).length;
  return `<div class="inspector-heading"><p class="eyebrow">${config.section}</p><h2>${config.label}</h2></div>
    <p class="help">${count} ${count === 1 ? config.singular.toLowerCase() : config.label.toLowerCase()} in this map. Choose an item in the navigator or use its creation controls.</p>`;
}

export function entityInspector(key, id) {
  const config = CONFIGS[key];
  const entity = findEntity(key, id);
  if (!entity) return collectionInspector(key);
  return `<div class="inspector-heading">
      <p class="eyebrow">${config.label}</p>
      <h2>${esc(entity.id)}</h2>
    </div>
    ${editableFields(key, entity)}
    <div class="danger-zone"><button type="button" class="danger" data-delete-entity>Delete ${config.singular}</button></div>`;
}

export function toolInspector(key, template) {
  const config = CONFIGS[key];
  const verb = config.creationMode === 'point' ? 'Place' : 'Draw';
  const help = config.creationMode === 'point'
    ? 'These settings are reused for every placement. Click the map repeatedly; press Escape when finished.'
    : 'Click the map to add points. Finish the shape with the canvas control or double-click the last point.';
  return `<div class="inspector-heading"><p class="eyebrow">Active tool</p><h2>${verb} ${config.singular}</h2></div>
    <p class="help">${help}</p>
    ${editableFields(key, template, {identity: false, spatial: false})}`;
}

function setNested(object, path, value) {
  const parts = path.split('.');
  let target = object;
  for (let index = 0; index < parts.length - 1; index += 1) {
    target = target[parts[index]] ??= {};
  }
  target[parts.at(-1)] = value;
}

function deleteNested(object, path) {
  const parts = path.split('.');
  const parents = [];
  let target = object;
  for (let index = 0; index < parts.length - 1; index += 1) {
    if (!target?.[parts[index]]) return;
    parents.push([target, parts[index]]);
    target = target[parts[index]];
  }
  delete target[parts.at(-1)];
  for (let index = parents.length - 1; index >= 0; index -= 1) {
    const [parent, key] = parents[index];
    if (Object.keys(parent[key]).length === 0) delete parent[key];
  }
}

function bindEditor(root, key, getValue, saveValue, {onRename, onDelete} = {}) {
  const save = (field, value) => {
    const current = getValue();
    if (!current) return;
    const next = structuredClone(current);
    if (value === undefined) deleteNested(next, field);
    else setNested(next, field, value);
    saveValue(next);
  };

  root.querySelectorAll('[data-asset-filter]').forEach(input => {
    input.oninput = () => {
      const field = root.querySelector('[data-field][data-asset-type]');
      const value = field.value;
      field.innerHTML = assetOptions(input.dataset.assetFilter, value, input.value);
      if (!field.value && field.options.length) field.value = field.options[0].value;
    };
  });
  root.querySelectorAll('[data-point]').forEach(input => {
    input.onchange = () => save(input.dataset.point, Number(input.value));
  });
  root.querySelectorAll('[data-add-point]').forEach(button => {
    button.onclick = () => {
      const field = button.dataset.addPoint;
      const next = structuredClone(getValue());
      next[field] ??= [];
      next[field].push([0, 0]);
      saveValue(next);
    };
  });
  root.querySelectorAll('[data-remove-point]').forEach(button => {
    button.onclick = () => {
      const [field, index] = button.dataset.removePoint.split('.');
      const next = structuredClone(getValue());
      next[field].splice(Number(index), 1);
      saveValue(next);
    };
  });
  root.querySelectorAll('[data-array-field]').forEach(input => {
    input.onchange = () => save(input.dataset.arrayField, [...input.selectedOptions].map(option => option.value));
  });
  root.querySelectorAll('[data-list-field]').forEach(input => {
    input.onchange = () => save(
      input.dataset.listField,
      input.value.split(',').map(value => value.trim()).filter(Boolean),
    );
  });
  root.querySelectorAll('[data-field]').forEach(input => {
    input.onchange = () => {
      const field = input.dataset.field;
      let value = input.value;
      if (input.type === 'checkbox') value = input.checked;
      if (input.type === 'number') value = value === '' ? undefined : Number(value);
      if (input.dataset.optional !== undefined && value === '') value = undefined;
      if (field === 'polygon' || field === 'control_points' || field === 'nodes') {
        try {
          value = JSON.parse(value);
        } catch {
          input.setAttribute('aria-invalid', 'true');
          return;
        }
      }
      if (field === 'vegetation.profile' && value === undefined) {
        const next = structuredClone(getValue());
        delete next.vegetation;
        saveValue(next);
        return;
      }
      if (field === 'id' && value !== getValue().id) onRename?.(value);
      save(field, value);
    };
  });
  const deleteButton = root.querySelector('[data-delete-entity]');
  if (deleteButton) {
    deleteButton.onclick = () => {
      const entity = getValue();
      if (entity && window.confirm(`Delete ${entity.id}? This cannot be undone.`)) onDelete?.();
    };
  }
}

export function bindEntityInspector(root, key, id, callbacks = {}) {
  bindEditor(
    root,
    key,
    () => findEntity(key, id),
    next => updateEntity(key, id, next),
    {
      onRename: callbacks.onRename,
      onDelete: () => {
        removeEntity(key, id);
        callbacks.onDelete?.();
      },
    },
  );
}

export function bindToolInspector(root, key, getTemplate, setTemplate) {
  bindEditor(root, key, getTemplate, setTemplate);
}
