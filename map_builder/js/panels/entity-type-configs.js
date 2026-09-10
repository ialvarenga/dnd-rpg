export const SECTIONS = [
  {id: 'setup', label: 'Setup'},
  {id: 'environment', label: 'Environment'},
  {id: 'layout', label: 'Layout'},
  {id: 'gameplay', label: 'Gameplay'},
  {id: 'narrative', label: 'Narrative'},
];

export const SETUP_PANELS = [
  {key: 'map', label: 'Map'},
  {key: 'terrain', label: 'Terrain'},
  {key: 'music', label: 'Music'},
  {key: 'player', label: 'Player'},
];

export const CONFIGS = {
  regions: {label: 'Regions', singular: 'Region', section: 'environment', creationMode: 'polygon', shape: 'polygon'},
  hills: {label: 'Hills', singular: 'Hill', section: 'environment', creationMode: 'point', assetType: 'terrain_feature', defaultAsset: 'forest_hill_4x4x4'},
  vegetation: {label: 'Vegetation', singular: 'Vegetation', section: 'environment', creationMode: 'point', assetType: 'vegetation', defaultAsset: 'tree_oak_01'},
  rivers: {label: 'Rivers', singular: 'River', section: 'environment', creationMode: 'path', shape: 'path'},
  roads: {label: 'Roads', singular: 'Road', section: 'layout', creationMode: 'path', shape: 'path'},
  structures: {label: 'Structures', singular: 'Structure', section: 'layout', creationMode: 'point', assetType: 'structure', defaultAsset: 'wall_dungeon_01'},
  walls: {label: 'Walls', singular: 'Wall', section: 'layout', creationMode: 'wall', shape: 'wall', assetType: 'structure', defaultAsset: 'wall_dungeon_01'},
  bridges: {label: 'Bridges', singular: 'Bridge', section: 'layout', creationMode: 'point', assetType: 'bridge', bridge: true, defaultAsset: 'bridge_wood_01'},
  doors: {label: 'Doors', singular: 'Door', section: 'layout', creationMode: 'point', door: true},
  spawn_points: {label: 'Spawn points', singular: 'Spawn point', section: 'gameplay', creationMode: 'point'},
  actors: {label: 'Actors', singular: 'Actor', section: 'gameplay', creationMode: 'point', assetType: 'character', assetField: 'archetype', side: true, defaultAsset: 'character_knight_01'},
  encounters: {label: 'Encounters', singular: 'Encounter', section: 'gameplay', creationMode: 'point', encounter: true},
  objectives: {label: 'Objectives', singular: 'Objective', section: 'gameplay', creationMode: 'point'},
  interactables: {label: 'Interactables', singular: 'Interactable', section: 'gameplay', creationMode: 'point', assetType: 'prop', kind: true, defaultAsset: 'chest_wood_01'},
  pickups: {label: 'Pickups', singular: 'Pickup', section: 'gameplay', creationMode: 'point', assetType: 'pickup', item: true, defaultAsset: 'healing_potion_pickup_01'},
  dialogs: {label: 'Dialogs', singular: 'Dialog', section: 'narrative', creationMode: 'form', dialog: true},
};

export function toolFor(key) {
  const mode = CONFIGS[key].creationMode;
  if (mode === 'point') return `place:${key}`;
  if (mode === 'polygon') return `draw-polygon:${key}`;
  if (mode === 'path') return `draw-path:${key}`;
  if (mode === 'wall') return `draw-wall:${key}`;
  return null;
}

export function actionFor(key) {
  const mode = CONFIGS[key].creationMode;
  if (mode === 'point') return 'Place';
  if (mode === 'form') return 'Add';
  return 'Draw';
}
