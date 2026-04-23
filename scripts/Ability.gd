class_name Ability
extends Resource

const TRIGGER_ACTIVE: int = 0
const TRIGGER_PASSIVE: int = 1

@export var ability_name: String = ""
@export var trigger: int = TRIGGER_ACTIVE
@export var effect_key: String = ""
@export var duration: float = 0.0
@export var cooldown: float = 0.0
