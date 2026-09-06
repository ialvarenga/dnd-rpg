// Curated presentation cues available to MapSpec authors. Map files persist
// only `id`; labels, tags, and preview paths stay authoring metadata.
export const MUSIC_CATALOG = Object.freeze({
	ambient: Object.freeze([
		Object.freeze({id: 'ambient_light_1', label: 'Sunlit Canopy', tags: ['calm', 'daytime', 'forest'], preview: '../godot/assets/music/ambient-light-1.wav'}),
		Object.freeze({id: 'ambient_night_3', label: 'Moonlit Watch', tags: ['quiet', 'night', 'forest'], preview: '../godot/assets/music/ambient-night-3.wav'}),
	]),
	battle: Object.freeze([
		Object.freeze({id: 'battle_action_1', label: 'First Clash', tags: ['urgent', 'skirmish'], preview: '../godot/assets/music/battle-action-1.wav'}),
		Object.freeze({id: 'battle_action_2', label: 'Rising Stakes', tags: ['intense', 'combat'], preview: '../godot/assets/music/battle-action-2.wav'}),
	]),
});

export const musicIds = cueType => MUSIC_CATALOG[cueType].map(cue => cue.id);
