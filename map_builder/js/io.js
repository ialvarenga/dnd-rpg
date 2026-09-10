import {validateMapSpec} from './validation.js';
import {validateFullMap} from './full-validation.js';
import {getState} from './state.js';
import {pickAndReadMapFile, pickSaveLocation, writeToHandle} from './fs-access.js';

let fileHandle = null;

function parseMap(text) {
  try {
    const data = JSON.parse(text);
    return {data, result: validateMapSpec(data)};
  } catch (error) {
    return {
      data: null,
      result: {errors: [{path: '/', message: `invalid JSON: ${error.message}`}], warnings: []},
    };
  }
}

export function clearFileTarget() {
  fileHandle = null;
}

export async function importMapFile(file) {
  const parsed = parseMap(await file.text());
  if (!parsed.result.errors.length) fileHandle = null;
  return {...parsed, name: file.name};
}

export async function importMapFromPicker() {
  const {handle, text} = await pickAndReadMapFile();
  const parsed = parseMap(text);
  if (!parsed.result.errors.length) fileHandle = handle;
  return {...parsed, name: handle.name};
}

function downloadableJson() {
  return JSON.stringify(getState(), null, 2);
}

export function exportMap(show) {
  const result = validateFullMap(getState());
  show(result);
  if (result.errors.length) return false;
  const anchor = document.createElement('a');
  anchor.href = URL.createObjectURL(new Blob([downloadableJson()], {type: 'application/json'}));
  anchor.download = `${getState().map.id || 'map'}.json`;
  anchor.click();
  URL.revokeObjectURL(anchor.href);
  return true;
}

export async function saveMap(show) {
  const result = validateFullMap(getState());
  show(result);
  if (result.errors.length) return null;
  if (!fileHandle) fileHandle = await pickSaveLocation(`${getState().map.id || 'map'}.json`);
  await writeToHandle(fileHandle, downloadableJson());
  return fileHandle.name;
}

export async function saveMapAs(show) {
  const result = validateFullMap(getState());
  show(result);
  if (result.errors.length) return null;
  fileHandle = await pickSaveLocation(`${getState().map.id || 'map'}.json`);
  await writeToHandle(fileHandle, downloadableJson());
  return fileHandle.name;
}
