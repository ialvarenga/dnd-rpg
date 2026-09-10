import {getState, addEntity} from './state.js';
import {defaultEntity} from './panels/list-panel-factory.js';
import {CONFIGS, toolFor} from './panels/entity-type-configs.js';
import {screenToWorld} from './svg-preview.js';

export const uiState = {
  activeTool: 'select',
  selection: {kind: 'setup', key: 'map'},
  draftShapePoints: [],
  placementDefaults: {},
  lastCreated: null,
  openSections: new Set(['setup', 'environment']),
};

export function selectSetup(key) {
  uiState.selection = {kind: 'setup', key};
}

export function selectCollection(key) {
  uiState.selection = {kind: 'collection', key};
}

export function selectEntity(key, id) {
  uiState.selection = {kind: 'entity', key, id};
  uiState.openSections.add(CONFIGS[key].section);
}

function makePlacementTemplate(key) {
  const bounds = getState().map.bounds;
  const entity = defaultEntity(key, [bounds.width_m / 2, bounds.height_m / 2]);
  delete entity.id;
  delete entity.position;
  delete entity.polygon;
  delete entity.control_points;
  return entity;
}

export function getPlacementTemplate(key) {
  uiState.placementDefaults[key] ??= makePlacementTemplate(key);
  return uiState.placementDefaults[key];
}

export function setPlacementTemplate(key, value) {
  uiState.placementDefaults[key] = value;
}

export function startTool(key) {
  const tool = toolFor(key);
  if (!tool) return false;
  uiState.activeTool = tool;
  uiState.draftShapePoints = [];
  uiState.lastCreated = null;
  getPlacementTemplate(key);
  uiState.selection = {kind: 'tool', key};
  uiState.openSections.add(CONFIGS[key].section);
  return true;
}

export function setSelectMode() {
  const key = toolKey();
  uiState.activeTool = 'select';
  uiState.draftShapePoints = [];
  if (uiState.lastCreated) {
    selectEntity(uiState.lastCreated.key, uiState.lastCreated.id);
  } else if (key) {
    selectCollection(key);
  }
}

export function cancelTool() {
  const key = toolKey();
  uiState.activeTool = 'select';
  uiState.draftShapePoints = [];
  if (uiState.lastCreated) selectEntity(uiState.lastCreated.key, uiState.lastCreated.id);
  else if (key) selectCollection(key);
}

export function toolKey() {
  return uiState.activeTool.includes(':') ? uiState.activeTool.split(':')[1] : null;
}

export function addAtCenter(key) {
  const bounds = getState().map.bounds;
  const entity = defaultEntity(key, [bounds.width_m / 2, bounds.height_m / 2]);
  addEntity(key, entity);
  uiState.activeTool = 'select';
  uiState.lastCreated = {key, id: entity.id};
  selectEntity(key, entity.id);
  return entity;
}

export function addFormEntity(key) {
  const entity = defaultEntity(key);
  addEntity(key, entity);
  uiState.activeTool = 'select';
  uiState.lastCreated = {key, id: entity.id};
  selectEntity(key, entity.id);
  return entity;
}

export function placeAt(key, position) {
  const template = structuredClone(getPlacementTemplate(key));
  const entity = {...defaultEntity(key, position), ...template, position};
  addEntity(key, entity);
  uiState.lastCreated = {key, id: entity.id};
  return entity;
}

export function addDraftPoint(position) {
  const previous = uiState.draftShapePoints.at(-1);
  if (!previous || previous[0] !== position[0] || previous[1] !== position[1]) {
    uiState.draftShapePoints.push(position);
  }
}

export function canFinishShape() {
  const key = toolKey();
  if (!key) return false;
  return uiState.draftShapePoints.length >= (key === 'regions' ? 3 : 2);
}

export function finishShape() {
  const key = toolKey();
  if (!key || !canFinishShape()) return null;
  const config = CONFIGS[key];
  const template = structuredClone(getPlacementTemplate(key));
  const entity = {...defaultEntity(key), ...template};
  const points = uiState.draftShapePoints.slice(0, config.creationMode === 'wall' ? 2 : undefined);
  entity[config.creationMode === 'polygon' ? 'polygon' : 'control_points'] = points;
  addEntity(key, entity);
  uiState.lastCreated = {key, id: entity.id};
  uiState.activeTool = 'select';
  uiState.draftShapePoints = [];
  selectEntity(key, entity.id);
  return entity;
}

export function handlePreview(event) {
  const svg = event.currentTarget;
  const target = event.target.closest?.('[data-array-key]');
  if (uiState.activeTool === 'select') {
    if (target) selectEntity(target.dataset.arrayKey, target.dataset.entityId);
    else uiState.selection = null;
    return;
  }

  const key = toolKey();
  const point = screenToWorld(svg, event, getState().map.bounds);
  if (uiState.activeTool.startsWith('place:')) {
    placeAt(key, point);
    return;
  }

  if (uiState.activeTool.startsWith('draw-')) {
    addDraftPoint(point);
    if (CONFIGS[key].creationMode === 'wall' && uiState.draftShapePoints.length === 2) {
      finishShape();
    } else if (event.detail === 2) {
      finishShape();
    }
  }
}

export function resetUiState() {
  uiState.activeTool = 'select';
  uiState.selection = {kind: 'setup', key: 'map'};
  uiState.draftShapePoints = [];
  uiState.placementDefaults = {};
  uiState.lastCreated = null;
  uiState.openSections = new Set(['setup', 'environment']);
}
