import {getState,setMapField,setMusicField} from '../state.js';
import {ENUMS} from '../schema-constants.js';
import {MUSIC_CATALOG} from '../music-catalog.js';

let previewPlayer = null;

const input=(label,key,value,type='text')=>`<label>${label}<input data-map="${key}" type="${type}" value="${value??''}"></label>`;
const musicSelect=(label,key,value,cues)=>`<label>${label}<select data-music="${key}">${cues.map(cue=>`<option value="${cue.id}" ${cue.id===value?'selected':''}>${cue.label} — ${cue.tags.join(', ')}</option>`).join('')}</select></label>`;
const musicPreview=(cueType,value)=>{
	const cue=MUSIC_CATALOG[cueType].find(entry=>entry.id===value);
	return cue?`<button type="button" class="music-preview" data-music-preview="${cue.preview}" data-music-label="${cue.label}">Preview ${cue.label}</button>`:'';
};

export function mapPanel(){
	const state=getState(),m=state.map,music=state.music||{ambient:'ambient_light_1',battle:'battle_action_1'};
	return `<fieldset><legend>Map</legend>${input('Map ID','id',m.id)}<label>Preset<select data-map="preset">${ENUMS.preset.map(x=>`<option ${x===m.preset?'selected':''}>${x}</option>`).join('')}</select></label><div class="row">${input('Seed','seed',m.seed,'number')}${input('Width (m)','width_m',m.bounds.width_m,'number')}</div>${input('Height (m)','height_m',m.bounds.height_m,'number')}${input('Asset catalog version','asset_catalog_version',m.asset_catalog_version||'')}${input('Generator version','generator_version',m.generator_version||'')}</fieldset><fieldset><legend>Music</legend><p class="music-help">Choose curated cues; exported maps retain only their stable IDs.</p>${musicSelect('Ambient music','ambient',music.ambient,MUSIC_CATALOG.ambient)}${musicPreview('ambient',music.ambient)}${musicSelect('Battle music','battle',music.battle,MUSIC_CATALOG.battle)}${musicPreview('battle',music.battle)}</fieldset>`;
}

export function bindMap(root){
	root.querySelectorAll('[data-map]').forEach(e=>e.onchange=()=>setMapField(e.dataset.map,e.type==='number'?Number(e.value):e.value));
	root.querySelectorAll('[data-music]').forEach(e=>e.onchange=()=>setMusicField(e.dataset.music,e.value));
	root.querySelectorAll('[data-music-preview]').forEach(button=>button.onclick=()=>playPreview(button));
}

function playPreview(button){
	const source=button.dataset.musicPreview;
	const resolvedSource=new URL(source,window.location.href).href;
	if(previewPlayer?.src===resolvedSource&&!previewPlayer.paused){
		previewPlayer.pause();
		button.textContent=`Preview ${button.dataset.musicLabel}`;
		return;
	}
	if(previewPlayer)previewPlayer.pause();
	previewPlayer=new Audio(source);
	previewPlayer.onended=()=>button.textContent=`Preview ${button.dataset.musicLabel}`;
	previewPlayer.play().then(()=>button.textContent='Stop preview').catch(()=>button.textContent='Preview unavailable');
}
