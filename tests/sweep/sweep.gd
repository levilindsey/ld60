extends Node
## Loads every .gd, .tscn and .tres under `res://src/` and reports each one
## that fails. The import and the boot parse only what the main scene
## reaches, so without this an error in a script nothing loads yet passes
## `scripts/check.ps1`.
##
## `scripts/check.ps1` runs it after the boot. By hand, from the repo root
## (PowerShell):
##   godot --headless --path . res://tests/sweep/sweep.tscn
##
## It prints one `SWEEP FAIL: <path>: <reason>` line per failed file, then
## `SWEEP SUMMARY: <n> loaded, <m> failed`. Godot logs the cause (with the
## file and line) as `SCRIPT ERROR:` and `ERROR:` lines before those.
## Exit code 0 means every file loaded.


const _ROOT_PATH := "res://src"
const _EXTENSIONS: Array[String] = ["gd", "tscn", "tres"]


func _ready() -> void:
	var paths: Array[String] = []
	_collect_paths(_ROOT_PATH, paths)
	paths.sort()
	var failure_count := 0
	if paths.is_empty():
		failure_count += 1
		print("SWEEP FAIL: %s: no scripts or scenes found" % _ROOT_PATH)
	for path in paths:
		var reason := _get_failure(path)
		if not reason.is_empty():
			failure_count += 1
			print("SWEEP FAIL: %s: %s" % [path, reason])
	print(
		"SWEEP SUMMARY: %d loaded, %d failed"
		% [paths.size() - failure_count, failure_count]
	)
	get_tree().quit(0 if failure_count == 0 else 1)


func _collect_paths(directory: String, paths: Array[String]) -> void:
	for file_name in DirAccess.get_files_at(directory):
		if _EXTENSIONS.has(file_name.get_extension()):
			paths.append(directory.path_join(file_name))
	for directory_name in DirAccess.get_directories_at(directory):
		_collect_paths(directory.path_join(directory_name), paths)


## Returns why the file fails to load, or an empty string if it loads.
func _get_failure(path: String) -> String:
	var resource := ResourceLoader.load(path)
	if resource == null:
		return "did not load"
	var script := resource as Script
	if script != null and not script.can_instantiate():
		return "does not compile"
	var scene := resource as PackedScene
	if scene != null and not scene.can_instantiate():
		return "cannot be instantiated"
	return ""
