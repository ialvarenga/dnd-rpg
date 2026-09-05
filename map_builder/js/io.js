import {validateMapSpec} from './validation.js';import {replaceState,getState} from './state.js';import {pickAndReadMapFile,pickSaveLocation,writeToHandle} from './fs-access.js';

export function exportMap(show){const result=validateMapSpec(getState());show(result);if(result.errors.length)return;const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(getState(),null,2)],{type:'application/json'}));a.download=`${getState().map.id||'map'}.json`;a.click();URL.revokeObjectURL(a.href)}

export function importMap(file,show){fileHandle=null;const r=new FileReader();r.onload=()=>{try{const data=JSON.parse(r.result),result=validateMapSpec(data);show(result);if(!result.errors.length)replaceState(data)}catch(e){show({errors:[{path:'/',message:`invalid JSON: ${e.message}`}],warnings:[]})}};r.readAsText(file)}

let fileHandle=null;

export async function importMapFromPicker(show){
  const {handle,text}=await pickAndReadMapFile();
  try{
    const data=JSON.parse(text),result=validateMapSpec(data);
    show(result);
    if(!result.errors.length){replaceState(data);fileHandle=handle}
  }catch(e){show({errors:[{path:'/',message:`invalid JSON: ${e.message}`}],warnings:[]})}
}

export async function saveMap(show){
  const result=validateMapSpec(getState());
  show(result);
  if(result.errors.length)return false;
  if(!fileHandle)fileHandle=await pickSaveLocation(`${getState().map.id||'map'}.json`);
  await writeToHandle(fileHandle,JSON.stringify(getState(),null,2));
  return true
}

export async function saveMapAs(show){
  const result=validateMapSpec(getState());
  show(result);
  if(result.errors.length)return false;
  fileHandle=await pickSaveLocation(`${getState().map.id||'map'}.json`);
  await writeToHandle(fileHandle,JSON.stringify(getState(),null,2));
  return true
}
