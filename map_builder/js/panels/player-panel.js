import {getState, setPlayerField} from '../state.js';
import {byType} from '../asset-catalog.js';

export function playerPanel() {
  const player = getState().player || {};
  return `<div class="inspector-heading"><p class="eyebrow">Setup</p><h2>Player</h2></div>
    <p class="help">Optional character asset used by the compiled-map player.</p>
    <label>Character asset
      <select data-player="character_asset">
        <option value="">— none —</option>
        ${byType('character').map(asset =>
          `<option value="${asset.id}" ${asset.id === player.character_asset ? 'selected' : ''}>${asset.id}</option>`
        ).join('')}
      </select>
    </label>`;
}

export function bindPlayer(root) {
  const element = root.querySelector('[data-player]');
  if (element) element.onchange = () => setPlayerField('character_asset', element.value);
}
