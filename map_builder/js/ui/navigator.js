import {getState} from '../state.js';
import {CONFIGS, SECTIONS, SETUP_PANELS, actionFor} from '../panels/entity-type-configs.js';
import {uiState, addAtCenter, addFormEntity, cancelTool, selectCollection, selectEntity, selectSetup, startTool} from '../interaction.js';

const esc = value => String(value ?? '')
  .replaceAll('&', '&amp;')
  .replaceAll('"', '&quot;')
  .replaceAll('<', '&lt;');

function isSelected(kind, key, id) {
  const selection = uiState.selection;
  return selection?.kind === kind && selection.key === key && (id === undefined || selection.id === id);
}

function setupSection() {
  return SETUP_PANELS.map(panel =>
    `<button type="button" class="nav-item ${isSelected('setup', panel.key) ? 'selected' : ''}" data-setup="${panel.key}">
      <span>${panel.label}</span>
    </button>`
  ).join('');
}

function collectionRow(key) {
  const config = CONFIGS[key];
  const entities = getState()[key] || [];
  const active = uiState.selection?.key === key;
  const items = entities.map(entity =>
    `<button type="button" class="entity-link ${isSelected('entity', key, entity.id) ? 'selected' : ''}" data-entity-key="${key}" data-entity-id="${esc(entity.id)}">
      <span class="entity-dot" aria-hidden="true"></span><span>${esc(entity.id)}</span>
    </button>`
  ).join('');
  const centerAction = config.creationMode === 'point'
    ? `<button type="button" class="icon-button" data-add-center="${key}" title="Add at map center" aria-label="Add ${config.singular} at map center">＋</button>`
    : '';
  return `<div class="collection ${active ? 'active' : ''}">
    <div class="collection-row">
      <button type="button" class="collection-select" data-collection="${key}">
        <span>${config.label}</span><span class="count">${entities.length}</span>
      </button>
      <button type="button" class="collection-action" data-create="${key}">${actionFor(key)}</button>
      ${centerAction}
    </div>
    <div class="entity-links">${items}</div>
  </div>`;
}

export function renderNavigator(root) {
  root.innerHTML = SECTIONS.map(section => {
    const content = section.id === 'setup'
      ? setupSection()
      : Object.keys(CONFIGS)
        .filter(key => CONFIGS[key].section === section.id)
        .map(collectionRow)
        .join('');
    return `<details class="nav-section" data-section="${section.id}" ${uiState.openSections.has(section.id) ? 'open' : ''}>
      <summary>${section.label}</summary>
      <div class="nav-section-content">${content}</div>
    </details>`;
  }).join('');
}

export function bindNavigator(root, repaint) {
  root.querySelectorAll('[data-section]').forEach(details => {
    details.ontoggle = () => {
      if (details.open) uiState.openSections.add(details.dataset.section);
      else uiState.openSections.delete(details.dataset.section);
    };
  });
  root.querySelectorAll('[data-setup]').forEach(button => {
    button.onclick = () => {
      cancelTool();
      selectSetup(button.dataset.setup);
      repaint();
    };
  });
  root.querySelectorAll('[data-collection]').forEach(button => {
    button.onclick = () => {
      cancelTool();
      selectCollection(button.dataset.collection);
      repaint();
    };
  });
  root.querySelectorAll('[data-entity-key]').forEach(button => {
    button.onclick = () => {
      cancelTool();
      selectEntity(button.dataset.entityKey, button.dataset.entityId);
      repaint();
    };
  });
  root.querySelectorAll('[data-create]').forEach(button => {
    button.onclick = () => {
      const key = button.dataset.create;
      if (CONFIGS[key].creationMode === 'form') addFormEntity(key);
      else startTool(key);
      repaint();
    };
  });
  root.querySelectorAll('[data-add-center]').forEach(button => {
    button.onclick = () => {
      addAtCenter(button.dataset.addCenter);
      repaint();
    };
  });
}
