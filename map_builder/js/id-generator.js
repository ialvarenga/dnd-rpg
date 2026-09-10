import {getState} from './state.js';

const BASE_NAMES = {
  regions: 'region',
  vegetation: 'tree',
  structures: 'structure',
  hills: 'hill',
  walls: 'wall',
  actors: 'actor',
  spawn_points: 'spawn',
  interactables: 'interactable',
  pickups: 'pickup',
  rivers: 'river',
  roads: 'road',
  bridges: 'bridge',
  objectives: 'objective',
  encounters: 'encounter',
  doors: 'door',
  dialogs: 'dialog',
};

export function nextId(key) {
  const base = BASE_NAMES[key] || 'entity';
  const used = new Set((getState()[key] || []).map(entity => entity.id));
  let number = 1;
  while (used.has(`${base}_${number}`)) number += 1;
  return `${base}_${number}`;
}
