let documentState = {
  dirty: false,
  displayName: 'untitled_map.json',
  persisted: false,
};

const subscribers = new Set();

export function getDocumentState() {
  return documentState;
}

export const subscribeDocument = fn => (subscribers.add(fn), () => subscribers.delete(fn));

function update(changes) {
  documentState = {...documentState, ...changes};
  subscribers.forEach(fn => fn(documentState));
}

export function markDirty() {
  if (!documentState.dirty) update({dirty: true});
}

export function markClean(displayName = documentState.displayName) {
  update({dirty: false, displayName, persisted: true});
}

export function markNew(mapId) {
  update({dirty: true, displayName: `${mapId || 'untitled_map'}.json`, persisted: false});
}

export function resetDocumentState() {
  documentState = {dirty: false, displayName: 'untitled_map.json', persisted: false};
  subscribers.forEach(fn => fn(documentState));
}

export function hasUnsavedChanges() {
  return documentState.dirty;
}
