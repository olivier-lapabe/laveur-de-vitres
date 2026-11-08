extends SceneTree
## Headless checks of the cleaning rules, run by CI:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exits with code 1 if a check fails.

## A spot high on the glass, with dust but no grease marks.
const CLEAN_SPOT := Vector2(0.5, 0.1)
## The middle of an adult handprint (2.45 m from the left, 1.35 m high).
const HANDPRINT := Vector2(0.766, 0.614)

var _failures := 0


func _initialize() -> void:
	# Nodes only get _ready once the tree runs, so start on the next idle step.
	_run.call_deferred()


func _run() -> void:
	_check_wet_glass_cleans_faster()
	_check_clean_hand_removes_grease()
	_check_dirty_hand_smears()
	_check_hand_gets_dirty()
	_check_aim_hits_the_crosshair()
	_check_dry_rubbing_stays_hard()
	_check_dry_rubbing_dirties_the_hand()
	print("Gameplay tests: %d failed" % _failures)
	quit(1 if _failures > 0 else 0)


func _new_glass() -> DirtyGlass:
	var storefront: Node3D = load("res://scenes/storefront.tscn").instantiate()
	root.add_child(storefront)
	return storefront.get_node("Glass") as DirtyGlass


func _rub_back_and_forth(glass: DirtyGlass, uv: Vector2, strokes: int, hand_dirt: float) -> void:
	for i in strokes:
		var offset := Vector2(0.01 if i % 2 == 0 else -0.01, 0.0)
		glass.rub(uv + offset, 0.02, hand_dirt)


func _check_wet_glass_cleans_faster() -> void:
	var glass := _new_glass()
	var dry := Vector2(0.25, 0.1)
	var wet := Vector2(0.75, 0.1)
	glass.spit(wet)
	_rub_back_and_forth(glass, dry, 10, 0.0)
	_rub_back_and_forth(glass, wet, 10, 0.0)
	var removed_wet := 1.0 - glass.dust_left_at(wet)
	var removed_dry := 1.0 - glass.dust_left_at(dry)
	_expect(removed_wet > removed_dry * 2.0 and removed_dry > 0.1,
		"dry rubbing works and spit makes it at least twice as effective (wet removed %.2f, dry %.2f)" % [removed_wet, removed_dry])


func _check_clean_hand_removes_grease() -> void:
	var glass := _new_glass()
	var before := glass.grease_at(HANDPRINT)
	glass.spit(HANDPRINT)
	_rub_back_and_forth(glass, HANDPRINT, 60, 0.0)
	var after := glass.grease_at(HANDPRINT)
	_expect(before > 0.3, "the handprint starts greasy (%.2f)" % before)
	_expect(after < before * 0.5, "a clean hand removes most of the grease (%.2f -> %.2f)" % [before, after])
	_expect(after > 0.0, "bare hands never leave the glass spotless (%.3f left)" % after)


func _check_dirty_hand_smears() -> void:
	var glass := _new_glass()
	var before := glass.grease_at(CLEAN_SPOT)
	_rub_back_and_forth(glass, CLEAN_SPOT, 20, 1.0)
	var after := glass.grease_at(CLEAN_SPOT)
	_expect(after > before + 0.08, "a dirty hand smears grease on clean glass (%.2f -> %.2f)" % [before, after])


func _check_hand_gets_dirty() -> void:
	var glass := _new_glass()
	glass.spit(HANDPRINT)
	var hand_dirt := 0.0
	for i in 100:
		hand_dirt = clampf(hand_dirt + glass.rub(HANDPRINT + Vector2(0.002 * (i % 10), 0.0), 0.02, hand_dirt), 0.0, 1.0)
	_expect(hand_dirt > 0.15 and hand_dirt < 0.6, "rubbing a greasy area dirties the hand, without saturating it at once (%.2f)" % hand_dirt)


## Many tiny rubs must add up to what one long rub does: rounding used to
## wear the dust away a little on every rub, however small.
func _check_dry_rubbing_stays_hard() -> void:
	var glass := _new_glass()
	var spot := Vector2(0.25, 0.1)
	for i in 400:
		glass.rub(spot, 0.0005, 0.0)
	_expect(glass.dust_left_at(spot) > 0.6, "400 tiny dry rubs only remove their share of dust (%.2f left)" % glass.dust_left_at(spot))


## Touching grime soils the hand even when rubbing dry glass removes little.
func _check_dry_rubbing_dirties_the_hand() -> void:
	var glass := _new_glass()
	var hand_dirt := 0.0
	for i in 150:
		hand_dirt = clampf(hand_dirt + glass.rub(Vector2(0.2 + 0.004 * (i % 50), 0.1), 0.02, hand_dirt), 0.0, 1.0)
	_expect(hand_dirt > 0.02 and hand_dirt < 0.3, "rubbing dry dusty glass soils the hand a little (%.2f)" % hand_dirt)


## The spit and the hand must land on the glass right under the crosshair.
func _check_aim_hits_the_crosshair() -> void:
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var player := main.get_node("Player") as WindowWasher
	player.position = Vector3(0.5, 0.15, 2.0)
	player.rotation = Vector3.ZERO
	player.get_node("Head").rotation = Vector3.ZERO
	var hit: Dictionary = player._glass_hit(Vector2.ZERO)
	# Eyes at 1.85 m, looking straight at the glass (centre 1.6 m high, 3.2 m by 2.2 m).
	var expected := Vector2(0.5 / 3.2 + 0.5, 0.5 - (1.85 - 1.6) / 2.2)
	_expect(not hit.is_empty() and (hit.uv as Vector2).distance_to(expected) < 0.01,
		"aiming hits the glass under the crosshair (got %s, expected %s)" % [hit.get("uv"), expected])
	main.queue_free()


func _expect(condition: bool, description: String) -> void:
	if condition:
		print("PASS ", description)
	else:
		_failures += 1
		print("FAIL ", description)
