import {getState} from '../state.js';
import {CONFIGS} from '../panels/entity-type-configs.js';

const esc = value => String(value ?? '')
  .replaceAll('&', '&amp;')
  .replaceAll('"', '&quot;')
  .replaceAll('<', '&lt;');

function targetForPath(path) {
  const match = path.match(/^\/([^/]+)(?:\/(\d+))?/);
  if (!match) return null;
  const [, key, indexText] = match;
  if (CONFIGS[key] && indexText !== undefined) {
    const entity = getState()[key]?.[Number(indexText)];
    return entity ? {kind: 'entity', key, id: entity.id} : {kind: 'collection', key};
  }
  if (['map', 'terrain', 'music', 'player'].includes(key)) return {kind: 'setup', key};
  if (CONFIGS[key]) return {kind: 'collection', key};
  return null;
}

function issueButton(issue, severity) {
  const target = targetForPath(issue.path || '/');
  const data = target
    ? `data-target-kind="${target.kind}" data-target-key="${target.key}" ${target.id ? `data-target-id="${esc(target.id)}"` : ''}`
    : '';
  return `<button type="button" class="validation-issue ${severity}" ${data}>
    <span class="issue-path">${esc(issue.path || '/')}</span>
    <span>${esc(issue.message)}</span>
  </button>`;
}

export function renderValidation(root, result) {
  if (!result.errors.length && !result.warnings.length) {
    root.innerHTML = '<div class="validation-summary ok"><strong>Map valid</strong><span>No validation issues</span></div>';
    return;
  }
  root.innerHTML = `<details ${result.errors.length ? 'open' : ''}>
    <summary class="validation-summary ${result.errors.length ? 'error' : 'warning'}">
      <strong>${result.errors.length ? `${result.errors.length} blocking error${result.errors.length === 1 ? '' : 's'}` : 'Map valid'}</strong>
      <span>${result.warnings.length} warning${result.warnings.length === 1 ? '' : 's'}</span>
    </summary>
    <div class="validation-list">
      ${result.errors.map(issue => issueButton(issue, 'error')).join('')}
      ${result.warnings.map(issue => issueButton(issue, 'warning')).join('')}
    </div>
  </details>`;
}

export function bindValidation(root, selectTarget) {
  root.querySelectorAll('[data-target-kind]').forEach(button => {
    button.onclick = () => selectTarget({
      kind: button.dataset.targetKind,
      key: button.dataset.targetKey,
      id: button.dataset.targetId,
    });
  });
}
