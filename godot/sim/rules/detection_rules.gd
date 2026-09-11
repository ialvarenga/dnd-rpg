class_name DetectionRules
extends RefCounted

const DETECTION_RANGE_METERS := 12.0


static func passive_perception(actor: ActorState) -> int:
	return actor.passive_perception()


static func can_detect(observer: ActorState, subject: ActorState, los: LosProvider, range_meters: float = DETECTION_RANGE_METERS) -> bool:
	if observer == null or subject == null or not observer.is_conscious() or observer.disposition != &"hostile":
		return false
	if observer.side == subject.side or observer.position.distance_to(subject.position) > range_meters:
		return false
	if subject.hidden_from.has(observer.id):
		return false
	return los.has_line_of_sight(observer.position, subject.position)


## Opponents that can contest Sneak, ordered by actor id. AI and Resolver both
## receive only this authoritative visibility vocabulary.
static func observers(state: BattleState, subject: ActorState, los: LosProvider, range_meters: float = DETECTION_RANGE_METERS) -> Array[ActorState]:
	var result: Array[ActorState] = []
	var ids: Array = state.actors.keys()
	ids.sort()
	for actor_id in ids:
		var observer := state.actors[actor_id] as ActorState
		if observer.id != subject.id and observer.side != subject.side and observer.is_conscious() and observer.disposition == &"hostile" and observer.position.distance_to(subject.position) <= range_meters and los.has_line_of_sight(observer.position, subject.position):
			result.append(observer)
	return result


static func detected_by(observer: ActorState, stealth_total: int) -> bool:
	return passive_perception(observer) >= stealth_total
