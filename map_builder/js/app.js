import {subscribe,getState} from './state.js';import {mapPanel,bindMap} from './panels/map-panel.js';import {terrainPanel,bindTerrain} from './panels/terrain-panel.js';import {playerPanel,bindPlayer} from './panels/player-panel.js';import {CONFIGS} from './panels/entity-type-configs.js';import {listPanel,bindList} from './panels/list-panel-factory.js';import {render} from './svg-preview.js';import {uiState,setTool,handlePreview,finishShape} from './interaction.js';import {validateMapSpec} from './validation.js';import {validateCollisions} from './collision-validation.js';import {exportMap,importMap,importMapFromPicker,saveMap,saveMapAs} from './io.js';import {supported as fsAccessSupported} from './fs-access.js';
const panels=document.querySelector('#panels'),svg=document.querySelector('#preview'),toolbar=document.querySelector('#toolbar'),actions=document.querySelector('#shape-actions'),validation=document.querySelector('#validation');const tools=['select',...Object.keys(CONFIGS).filter(key=>!['regions','rivers','roads','walls'].includes(key)).map(key=>`place:${key}`),'draw-polygon:regions','draw-path:rivers','draw-path:roads','draw-wall:walls'];toolbar.innerHTML=tools.map(tool=>`<button class="tool" data-tool="${tool}">${tool==='draw-wall:walls'?'Draw Wall':tool==='select'?'Select':tool.replace('place:','Place ').replace('draw-polygon:','Draw ').replace('draw-path:','Draw ')}</button>`).join('');
function result(){const schema=validateMapSpec(getState());return{...schema,errors:[...schema.errors,...validateCollisions(getState())]}}function show(current=result()){validation.innerHTML=current.errors.length?`<strong class="error">${current.errors.length} error(s) — export blocked</strong><br>${current.errors.map(issue=>`<span class="error">${issue.path||'/'}: ${issue.message}</span>`).join('<br>')}`:`<strong class="ok">Valid MapSpec</strong>${current.warnings.map(issue=>`<br><span class="warning">${issue.path}: ${issue.message}</span>`).join('')}`}
function paint(){panels.innerHTML=mapPanel()+terrainPanel()+playerPanel()+Object.keys(CONFIGS).map(key=>listPanel(key,uiState.selectedEntity)).join('');bindMap(panels);bindTerrain(panels);bindPlayer(panels);Object.keys(CONFIGS).forEach(key=>bindList(panels,key,uiState.selectedEntity));render(svg,getState(),uiState);toolbar.querySelectorAll('.tool').forEach(button=>button.classList.toggle('active',button.dataset.tool===uiState.activeTool));actions.innerHTML=uiState.activeTool.startsWith('draw-')?`<button id="finish" ${uiState.draftShapePoints.length<(uiState.activeTool.endsWith('regions')?3:2)?'disabled':''}>Finish shape (${uiState.draftShapePoints.length} points)</button>`:'';actions.querySelector('#finish')?.addEventListener('click',()=>finishShape(paint));show()}subscribe(paint);toolbar.onclick=event=>{if(event.target.dataset.tool){setTool(event.target.dataset.tool);paint()}};svg.addEventListener('click',event=>handlePreview(event,paint));document.querySelector('#export').onclick=()=>{const current=result();show(current);if(!current.errors.length)exportMap(show)};document.querySelector('#import-file').onchange=event=>{if(event.target.files[0])importMap(event.target.files[0],show);event.target.value=''};
const importFallback=document.querySelector('#import-fallback'),importPicker=document.querySelector('#import-picker'),saveButton=document.querySelector('#save'),saveAsButton=document.querySelector('#save-as');
function flash(button,label){button.textContent='Saved!';setTimeout(()=>button.textContent=label,1500)}
if(fsAccessSupported){
  importFallback.hidden=true;importPicker.hidden=false;saveButton.hidden=false;saveAsButton.hidden=false;
  importPicker.onclick=async()=>{
    try{await importMapFromPicker(show)}catch(e){if(e.name!=='AbortError')show({errors:[{path:'/',message:`import failed: ${e.message}`}],warnings:[]})}
  };
  saveButton.onclick=async()=>{
    saveButton.disabled=true;
    try{if(await saveMap(show))flash(saveButton,'Save')}
    catch(e){if(e.name!=='AbortError')show({errors:[{path:'/',message:`save failed: ${e.message}`}],warnings:[]})}
    finally{saveButton.disabled=false}
  };
  saveAsButton.onclick=async()=>{
    saveAsButton.disabled=true;
    try{if(await saveMapAs(show))flash(saveButton,'Save')}
    catch(e){if(e.name!=='AbortError')show({errors:[{path:'/',message:`save failed: ${e.message}`}],warnings:[]})}
    finally{saveAsButton.disabled=false}
  };
}
paint();
