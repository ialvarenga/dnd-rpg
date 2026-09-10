import {getState, setTerrainField} from '../state.js';
import {ENUMS} from '../schema-constants.js';

export function terrainPanel() {
  const terrain = getState().terrain;
  const select = (label, key, values) =>
    `<label>${label}<select data-terrain="${key}">${values.map(value =>
      `<option ${value === terrain[key] ? 'selected' : ''}>${value}</option>`
    ).join('')}</select></label>`;
  return `<div class="inspector-heading"><p class="eyebrow">Setup</p><h2>Terrain</h2></div>
    ${select('Profile', 'profile', ENUMS.profile)}
    ${select('Surface', 'surface', ENUMS.surface)}
    <details class="advanced-fields">
      <summary>Version metadata</summary>
      <label>Generator version<input data-terrain="generator_version" value="${terrain.generator_version || ''}"></label>
    </details>`;
}

export function bindTerrain(root) {
  root.querySelectorAll('[data-terrain]').forEach(element => {
    element.onchange = () => setTerrainField(element.dataset.terrain, element.value);
  });
}
