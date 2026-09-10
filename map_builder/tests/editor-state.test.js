import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

import {ARRAY_KEYS} from '../js/schema-constants.js';
import {CONFIGS, SECTIONS, toolFor} from '../js/panels/entity-type-configs.js';
import {
  addEntity,
  createInitialMap,
  findEntity,
  getState,
  removeEntity,
  replaceState,
  resetState,
  updateEntity,
} from '../js/state.js';
import {
  addDraftPoint,
  cancelTool,
  finishShape,
  placeAt,
  resetUiState,
  setSelectMode,
  startTool,
  uiState,
} from '../js/interaction.js';
import {
  getDocumentState,
  markClean,
  markDirty,
  markNew,
  resetDocumentState,
} from '../js/document-state.js';
import {validateFullMap} from '../js/full-validation.js';
import {validateMapSpec} from '../js/validation.js';

test('every MapSpec collection belongs to exactly one named section and has a creation mode', () => {
  assert.deepEqual(Object.keys(CONFIGS).sort(), [...ARRAY_KEYS].sort());
  const sectionIds = new Set(SECTIONS.map(section => section.id));
  for (const config of Object.values(CONFIGS)) {
    assert.ok(sectionIds.has(config.section));
    assert.ok(['point', 'polygon', 'path', 'wall', 'form'].includes(config.creationMode));
  }
  assert.equal(toolFor('dialogs'), null);
  assert.equal(toolFor('vegetation'), 'place:vegetation');
  assert.equal(toolFor('regions'), 'draw-polygon:regions');
});

test('initial map options preserve the MapSpec v1 defaults', () => {
  const map = createInitialMap({id: 'sunken_road', preset: 'small', width_m: 48, height_m: 32, seed: 19});
  assert.equal(map.version, '1.0');
  assert.deepEqual(map.map, {
    id: 'sunken_road',
    preset: 'small',
    seed: 19,
    bounds: {width_m: 48, height_m: 32},
  });
  assert.equal(map.terrain.surface, 'grass');
  assert.equal(map.music.ambient, 'ambient_light_1');
});

test('entity updates and removals resolve stable IDs instead of array indexes', () => {
  resetState();
  addEntity('spawn_points', {id: 'spawn_1', position: [4, 4]});
  addEntity('spawn_points', {id: 'spawn_2', position: [8, 8]});
  updateEntity('spawn_points', 'spawn_2', {id: 'north_spawn', position: [10, 12]});
  removeEntity('spawn_points', 'spawn_1');
  assert.deepEqual(findEntity('spawn_points', 'north_spawn').position, [10, 12]);
  assert.equal(getState().spawn_points.length, 1);
});

test('point placement remains active and selects the latest entity when finished', () => {
  resetState();
  resetUiState();
  startTool('actors');
  const first = placeAt('actors', [5, 6]);
  const second = placeAt('actors', [8, 9]);
  assert.equal(uiState.activeTool, 'place:actors');
  assert.equal(first.id, 'actor_1');
  assert.equal(second.id, 'actor_2');
  assert.equal(getState().actors.length, 2);
  setSelectMode();
  assert.equal(uiState.activeTool, 'select');
  assert.deepEqual(uiState.selection, {kind: 'entity', key: 'actors', id: 'actor_2'});
});

test('shape completion creates one selected shape and cancellation discards a draft', () => {
  resetState();
  resetUiState();
  startTool('regions');
  addDraftPoint([0, 0]);
  addDraftPoint([12, 0]);
  addDraftPoint([12, 12]);
  const region = finishShape();
  assert.equal(region.id, 'region_1');
  assert.equal(region.polygon.length, 3);
  assert.deepEqual(uiState.selection, {kind: 'entity', key: 'regions', id: 'region_1'});

  startTool('roads');
  addDraftPoint([1, 1]);
  cancelTool();
  assert.equal(uiState.activeTool, 'select');
  assert.deepEqual(uiState.draftShapePoints, []);
  assert.equal(getState().roads, undefined);
});

test('document status transitions between new, dirty, and persisted snapshots', () => {
  resetDocumentState();
  markNew('sunken_road');
  assert.deepEqual(getDocumentState(), {
    dirty: true,
    displayName: 'sunken_road.json',
    persisted: false,
  });
  markClean('saved_map.json');
  assert.equal(getDocumentState().dirty, false);
  markDirty();
  assert.equal(getDocumentState().dirty, true);
  assert.equal(getDocumentState().displayName, 'saved_map.json');
});

test('full validation combines schema and collision errors', () => {
  const map = createInitialMap();
  map.vegetation = [
    {id: 'tree_1', asset: 'tree_oak_01', position: [10, 10]},
    {id: 'tree_2', asset: 'tree_oak_01', position: [10, 10]},
  ];
  const result = validateFullMap(map);
  assert.ok(result.errors.some(issue => issue.message.includes('overlaps tree_1')));

  replaceState(createInitialMap());
});

test('dialog coin costs require a positive integer and cannot be combined with a check', () => {
  const map = createInitialMap();
  map.dialogs = [{
    id: 'toll', root: 'greeting', nodes: [{
      id: 'greeting', text: 'Pay the toll.', options: [{
        text: 'Pay', coin_cost: 10, outcome: {effect: 'end'},
      }],
    }],
  }];
  assert.deepEqual(validateMapSpec(map).errors, []);

  map.dialogs[0].nodes[0].options[0].coin_cost = 0;
  assert.ok(validateMapSpec(map).errors.some(issue => issue.path.endsWith('/coin_cost')));

  map.dialogs[0].nodes[0].options[0] = {
    text: 'Pay and bluff', coin_cost: 1,
    check: {ability: 'charisma', dc: 10},
    outcome: {effect: 'end'}, failure_outcome: {effect: 'end'},
  };
  assert.ok(validateMapSpec(map).errors.some(issue => issue.message.includes('cannot also require a check')));
});

test('Save is visible before browser capability detection', async () => {
  const html = await readFile(new URL('../index.html', import.meta.url), 'utf8');
  const saveButton = html.match(/<button id="save"[^>]*>/)?.[0];
  assert.ok(saveButton);
  assert.doesNotMatch(saveButton, /\bhidden\b/);
});
