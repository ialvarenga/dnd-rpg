export function createInitialMap(options = {}) {
  return {
    version: '1.0',
    map: {
      id: options.id ?? 'untitled_map',
      preset: options.preset ?? 'encounter',
      seed: options.seed ?? 0,
      bounds: {
        width_m: options.width_m ?? 64,
        height_m: options.height_m ?? 64,
      },
    },
    music: {ambient: 'ambient_light_1', battle: 'battle_action_1'},
    terrain: {profile: 'flat', surface: 'grass'},
  };
}

let mapSpec = createInitialMap();
const subscribers = new Set();

export const getState = () => mapSpec;
export const subscribe = fn => (subscribers.add(fn), () => subscribers.delete(fn));

function notify(type = 'edit') {
  subscribers.forEach(fn => fn(mapSpec, {type}));
}

export function replaceState(value, type = 'replace') {
  mapSpec = value;
  notify(type);
}

export function resetState(options = {}) {
  replaceState(createInitialMap(options), 'new');
}

export function mutate(fn) {
  fn(mapSpec);
  notify('edit');
}

export function setMapField(key, value) {
  mutate(state => {
    if (key === 'width_m' || key === 'height_m') state.map.bounds[key] = value;
    else if (value === '') delete state.map[key];
    else state.map[key] = value;
  });
}

export function setTerrainField(key, value) {
  mutate(state => {
    if (value === '') delete state.terrain[key];
    else state.terrain[key] = value;
  });
}

export function setPlayerField(key, value) {
  mutate(state => {
    if (value === '') {
      if (state.player) {
        delete state.player[key];
        if (!Object.keys(state.player).length) delete state.player;
      }
    } else {
      state.player ??= {};
      state.player[key] = value;
    }
  });
}

export function setMusicField(key, value) {
  mutate(state => {
    state.music ??= {ambient: 'ambient_light_1', battle: 'battle_action_1'};
    state.music[key] = value;
  });
}

export function addEntity(key, value) {
  mutate(state => {
    state[key] ??= [];
    state[key].push(value);
  });
}

export function findEntity(key, id) {
  return (mapSpec[key] || []).find(entity => entity.id === id);
}

export function findEntityIndex(key, id) {
  return (mapSpec[key] || []).findIndex(entity => entity.id === id);
}

export function updateEntity(key, id, value) {
  const index = findEntityIndex(key, id);
  if (index < 0) return false;
  mutate(state => { state[key][index] = value; });
  return true;
}

export function removeEntity(key, id) {
  const index = findEntityIndex(key, id);
  if (index < 0) return false;
  mutate(state => { state[key].splice(index, 1); });
  return true;
}
