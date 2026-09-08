import {musicIds} from './music-catalog.js';

export const STABLE_ID=/^(?!res:\/\/)[a-z][a-z0-9]*(?:_[a-z0-9]+)*$/;
export const ENUMS={preset:['encounter','small','medium'],profile:['flat','rolling_hills','valley'],surface:['grass','sand','dirt','stone'],vegetationProfile:['temperate_sparse','temperate_dense','none'],kind:['chest','door','lever','barrel','prop'],doorState:['open','closed'],side:['heroes','enemies'],ambientMusic:musicIds('ambient'),battleMusic:musicIds('battle')};
export const ARRAY_KEYS=['regions','vegetation','structures','hills','walls','actors','spawn_points','interactables','pickups','rivers','roads','bridges','objectives','encounters','doors'];
