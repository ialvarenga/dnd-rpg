export const supported=typeof window.showOpenFilePicker==='function'&&typeof window.showSaveFilePicker==='function';

const jsonPickerOptions={types:[{description:'MapSpec JSON',accept:{'application/json':['.json']}}]};

async function ensurePermission(handle,mode='readwrite'){
  const opts={mode};
  if(await handle.queryPermission(opts)==='granted')return true;
  return await handle.requestPermission(opts)==='granted'
}

export async function pickAndReadMapFile(){
  const [handle]=await window.showOpenFilePicker(jsonPickerOptions);
  if(!await ensurePermission(handle))throw new Error('permission to read the file was denied');
  const text=await(await handle.getFile()).text();
  return {handle,text}
}

export async function pickSaveLocation(suggestedName){
  const handle=await window.showSaveFilePicker({...jsonPickerOptions,suggestedName});
  if(!await ensurePermission(handle))throw new Error('permission to write to the file was denied');
  return handle
}

export async function writeToHandle(handle,contents){
  if(!await ensurePermission(handle))throw new Error('permission to write to the file was denied');
  const writable=await handle.createWritable();
  await writable.write(contents);
  await writable.close()
}
