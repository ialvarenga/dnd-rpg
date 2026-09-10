import {getState, replaceState, resetState, subscribe} from './state.js';
import {mapPanel, musicPanel, bindMap, bindMusic} from './panels/map-panel.js';
import {terrainPanel, bindTerrain} from './panels/terrain-panel.js';
import {playerPanel, bindPlayer} from './panels/player-panel.js';
import {CONFIGS} from './panels/entity-type-configs.js';
import {
  collectionInspector,
  entityInspector,
  toolInspector,
  bindEntityInspector,
  bindToolInspector,
} from './panels/list-panel-factory.js';
import {render as renderMap} from './svg-preview.js';
import {
  uiState,
  cancelTool,
  canFinishShape,
  finishShape,
  getPlacementTemplate,
  handlePreview,
  resetUiState,
  selectCollection,
  selectEntity,
  selectSetup,
  setPlacementTemplate,
  setSelectMode,
  toolKey,
} from './interaction.js';
import {validateFullMap} from './full-validation.js';
import {STABLE_ID, ENUMS} from './schema-constants.js';
import {
  clearFileTarget,
  exportMap,
  importMapFile,
  importMapFromPicker,
  saveMap,
  saveMapAs,
} from './io.js';
import {supported as fsAccessSupported} from './fs-access.js';
import {
  getDocumentState,
  hasUnsavedChanges,
  markClean,
  markDirty,
  markNew,
  subscribeDocument,
} from './document-state.js';
import {renderNavigator, bindNavigator} from './ui/navigator.js';
import {renderValidation, bindValidation} from './ui/validation-panel.js';

const navigator = document.querySelector('#navigator');
const inspector = document.querySelector('#inspector');
const svg = document.querySelector('#preview');
const canvasToolbar = document.querySelector('#canvas-toolbar');
const validation = document.querySelector('#validation');
const documentStatus = document.querySelector('#document-status');
const newDialog = document.querySelector('#new-map-dialog');
const newForm = document.querySelector('#new-map-form');
const newErrors = document.querySelector('#new-map-errors');
const importButton = document.querySelector('#import');
const importFile = document.querySelector('#import-file');
const saveButton = document.querySelector('#save');
const saveAsButton = document.querySelector('#save-as');

function esc(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;');
}

function showInspectorOnCompactLayout() {
  if (window.innerWidth < 1100) {
    document.body.classList.remove('nav-open');
    document.body.classList.add('inspector-open');
  }
}

function renderDocumentStatus() {
  const state = getDocumentState();
  const name = document.createElement('span');
  name.className = 'name';
  name.textContent = `${state.displayName}${state.dirty ? ' — Unsaved' : ''}`;
  documentStatus.replaceChildren();
  if (state.dirty) {
    const dot = document.createElement('span');
    dot.className = 'dirty-dot';
    dot.title = 'Unsaved changes';
    documentStatus.append(dot);
  }
  documentStatus.append(name);
}

function selectTarget(target) {
  cancelTool();
  if (target.kind === 'entity') selectEntity(target.key, target.id);
  else if (target.kind === 'collection') selectCollection(target.key);
  else selectSetup(target.key);
  showInspectorOnCompactLayout();
  paint();
}

function showValidation(result) {
  renderValidation(validation, result);
  bindValidation(validation, selectTarget);
}

function renderInspector() {
  const selection = uiState.selection;
  if (!selection) {
    inspector.innerHTML = '<div class="inspector-heading"><p class="eyebrow">Inspector</p><h2>Nothing selected</h2></div><p class="help">Select an item on the map or in the navigator to edit it.</p>';
    return;
  }
  if (selection.kind === 'setup') {
    if (selection.key === 'map') {
      inspector.innerHTML = mapPanel();
      bindMap(inspector);
    } else if (selection.key === 'terrain') {
      inspector.innerHTML = terrainPanel();
      bindTerrain(inspector);
    } else if (selection.key === 'music') {
      inspector.innerHTML = musicPanel();
      bindMusic(inspector);
    } else {
      inspector.innerHTML = playerPanel();
      bindPlayer(inspector);
    }
    return;
  }
  if (selection.kind === 'collection') {
    inspector.innerHTML = collectionInspector(selection.key);
    return;
  }
  if (selection.kind === 'tool') {
    inspector.innerHTML = toolInspector(selection.key, getPlacementTemplate(selection.key));
    bindToolInspector(
      inspector,
      selection.key,
      () => getPlacementTemplate(selection.key),
      next => setPlacementTemplate(selection.key, next),
    );
    return;
  }
  inspector.innerHTML = entityInspector(selection.key, selection.id);
  bindEntityInspector(inspector, selection.key, selection.id, {
    onRename: nextId => { uiState.selection.id = nextId; },
    onDelete: () => {
      selectCollection(selection.key);
      paint();
    },
  });
}

function toolDescription() {
  const key = toolKey();
  if (!key) return {title: 'Select', detail: 'Choose an item to edit its properties'};
  const config = CONFIGS[key];
  if (config.creationMode === 'point') {
    return {title: `Place ${config.singular}`, detail: 'Click repeatedly on the map · Escape when done'};
  }
  return {
    title: `Draw ${config.singular}`,
    detail: `${uiState.draftShapePoints.length} point${uiState.draftShapePoints.length === 1 ? '' : 's'} · double-click or Finish`,
  };
}

function renderCanvasToolbar() {
  const description = toolDescription();
  const key = toolKey();
  const drawing = key && CONFIGS[key].creationMode !== 'point';
  canvasToolbar.innerHTML = `
    <button type="button" class="drawer-toggle" data-toggle-nav aria-label="Open map navigator">Sections</button>
    <button type="button" class="${uiState.activeTool === 'select' ? 'primary' : ''}" data-select-tool>Select</button>
    <div class="tool-status"><strong>${esc(description.title)}</strong><span>${esc(description.detail)}</span></div>
    ${drawing ? `<button type="button" data-finish-shape ${canFinishShape() ? '' : 'disabled'}>Finish</button>` : ''}
    ${key ? `<button type="button" class="secondary" data-cancel-tool>${drawing ? 'Cancel' : 'Done'}</button>` : ''}
    <button type="button" class="drawer-toggle" data-toggle-inspector aria-label="Open properties inspector">Properties</button>`;

  canvasToolbar.querySelector('[data-toggle-nav]')?.addEventListener('click', () => {
    document.body.classList.toggle('nav-open');
    document.body.classList.remove('inspector-open');
  });
  canvasToolbar.querySelector('[data-toggle-inspector]')?.addEventListener('click', () => {
    document.body.classList.toggle('inspector-open');
    document.body.classList.remove('nav-open');
  });
  canvasToolbar.querySelector('[data-select-tool]').onclick = () => {
    setSelectMode();
    paint();
  };
  canvasToolbar.querySelector('[data-cancel-tool]')?.addEventListener('click', () => {
    cancelTool();
    paint();
  });
  canvasToolbar.querySelector('[data-finish-shape]')?.addEventListener('click', () => {
    finishShape();
    paint();
  });
}

function paint() {
  renderNavigator(navigator);
  bindNavigator(navigator, () => {
    showInspectorOnCompactLayout();
    paint();
  });
  renderInspector();
  renderCanvasToolbar();
  renderMap(svg, getState(), uiState);
  showValidation(validateFullMap(getState()));
  renderDocumentStatus();
}

function confirmDiscard() {
  return !hasUnsavedChanges() || window.confirm('Discard unsaved map changes? This cannot be undone.');
}

function openNewMapDialog() {
  if (!confirmDiscard()) return;
  newForm.reset();
  newErrors.textContent = '';
  newDialog.showModal();
  newForm.elements.id.focus();
  newForm.elements.id.select();
}

function newMapOptions() {
  return {
    id: newForm.elements.id.value.trim(),
    preset: newForm.elements.preset.value,
    width_m: Number(newForm.elements.width_m.value),
    height_m: Number(newForm.elements.height_m.value),
    seed: Number(newForm.elements.seed.value),
  };
}

function validateNewMapOptions(options) {
  const errors = [];
  if (!STABLE_ID.test(options.id)) errors.push('Map ID must use lowercase letters, numbers, and underscores.');
  if (!ENUMS.preset.includes(options.preset)) errors.push('Choose a valid preset.');
  for (const [label, value] of [['Width', options.width_m], ['Height', options.height_m]]) {
    if (!Number.isFinite(value) || value <= 0 || value > 256) errors.push(`${label} must be between 1 and 256 metres.`);
  }
  if (!Number.isInteger(options.seed) || options.seed < 0 || options.seed > 2147483647) {
    errors.push('Seed must be a whole number from 0 to 2147483647.');
  }
  return errors;
}

async function acceptImport(result) {
  showValidation(result.result);
  if (result.result.errors.length) return;
  replaceState(result.data, 'import');
  resetUiState();
  markClean(result.name);
  paint();
}

async function runImport() {
  if (!confirmDiscard()) return;
  if (fsAccessSupported) {
    try {
      await acceptImport(await importMapFromPicker());
    } catch (error) {
      if (error.name !== 'AbortError') {
        showValidation({errors: [{path: '/', message: `import failed: ${error.message}`}], warnings: []});
      }
    }
  } else {
    importFile.click();
  }
}

function flash(button, label) {
  button.textContent = 'Saved!';
  window.setTimeout(() => { button.textContent = label; }, 1500);
}

subscribe((_state, change) => {
  if (change.type === 'edit') markDirty();
  paint();
});
subscribeDocument(renderDocumentStatus);

inspector.addEventListener('input', event => {
  const editable = event.target.matches('[data-map], [data-music], [data-terrain], [data-player], [data-field], [data-array-field], [data-list-field]');
  if (editable && !event.target.matches('[data-asset-filter]') && uiState.selection?.kind !== 'tool') markDirty();
});

document.querySelector('#new-map').onclick = openNewMapDialog;
newDialog.querySelector('[data-close-dialog]').onclick = () => newDialog.close();
newForm.onsubmit = event => {
  event.preventDefault();
  const options = newMapOptions();
  const errors = validateNewMapOptions(options);
  if (errors.length) {
    newErrors.textContent = errors.join(' ');
    return;
  }
  clearFileTarget();
  resetState(options);
  resetUiState();
  markNew(options.id);
  newDialog.close();
  paint();
};

importButton.onclick = runImport;
importFile.onchange = async event => {
  const [file] = event.target.files;
  if (file) await acceptImport(await importMapFile(file));
  event.target.value = '';
};

document.querySelector('#export').onclick = () => {
  if (exportMap(showValidation)) markClean(`${getState().map.id || 'map'}.json`);
};

if (fsAccessSupported) {
  saveAsButton.hidden = false;
  saveButton.onclick = async () => {
    saveButton.disabled = true;
    try {
      const name = await saveMap(showValidation);
      if (name) {
        markClean(name);
        flash(saveButton, 'Save');
      }
    } catch (error) {
      if (error.name !== 'AbortError') {
        showValidation({errors: [{path: '/', message: `save failed: ${error.message}`}], warnings: []});
      }
    } finally {
      saveButton.disabled = false;
    }
  };
  saveAsButton.onclick = async () => {
    saveAsButton.disabled = true;
    try {
      const name = await saveMapAs(showValidation);
      if (name) {
        markClean(name);
        flash(saveAsButton, 'Save As');
      }
    } catch (error) {
      if (error.name !== 'AbortError') {
        showValidation({errors: [{path: '/', message: `save failed: ${error.message}`}], warnings: []});
      }
    } finally {
      saveAsButton.disabled = false;
    }
  };
} else {
  saveButton.title = 'This browser cannot overwrite the imported file; Save downloads an updated JSON copy.';
  saveButton.setAttribute('aria-label', 'Save by downloading an updated JSON copy');
  saveButton.onclick = () => {
    if (exportMap(showValidation)) {
      markClean(`${getState().map.id || 'map'}.json`);
      flash(saveButton, 'Save');
    }
  };
}

svg.addEventListener('click', event => {
  handlePreview(event);
  if (uiState.activeTool === 'select' && uiState.selection?.kind === 'entity') showInspectorOnCompactLayout();
  paint();
});

document.addEventListener('keydown', event => {
  if (newDialog.open) return;
  if (event.key === 'Escape') {
    if (uiState.activeTool !== 'select') {
      cancelTool();
      paint();
    } else {
      document.body.classList.remove('nav-open', 'inspector-open');
    }
  } else if (event.key === 'Enter' && uiState.activeTool.startsWith('draw-') && canFinishShape()) {
    event.preventDefault();
    finishShape();
    paint();
  }
});

window.addEventListener('beforeunload', event => {
  if (hasUnsavedChanges()) {
    event.preventDefault();
    event.returnValue = '';
  }
});

paint();
