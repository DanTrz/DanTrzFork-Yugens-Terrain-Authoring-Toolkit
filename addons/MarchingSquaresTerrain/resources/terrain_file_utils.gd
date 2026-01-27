@tool
class_name TerrainFileUtils
extends RefCounted
## Utility class for terrain file operations.
## Handles naming conventions and directory management for external chunk storage.


## Convert chunk coordinates to filename
static func coords_to_filename(coords: Vector2i) -> String:
	return "terrain_chunk_%d_%d.res" % [coords.x, coords.y]


## Parse filename to extract chunk coordinates
## Returns Vector2i.MAX on parse failure
static func filename_to_coords(filename: String) -> Vector2i:
	# Expected format: terrain_chunk_X_Y.res
	if not filename.begins_with("terrain_chunk_") or not filename.ends_with(".res"):
		return Vector2i.MAX

	var name_part := filename.trim_suffix(".res").trim_prefix("terrain_chunk_")
	var parts := name_part.split("_")

	if parts.size() != 2:
		return Vector2i.MAX

	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.MAX

	return Vector2i(int(parts[0]), int(parts[1]))


## Get all chunk files in a directory
## Returns dictionary of Vector2i -> file_path
static func get_chunk_files_in_directory(dir_path: String) -> Dictionary:
	var result := {}

	if not DirAccess.dir_exists_absolute(dir_path):
		return result

	var dir := DirAccess.open(dir_path)
	if not dir:
		printerr("TerrainFileUtils: Failed to open directory: ", dir_path)
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()

	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".res"):
			var coords := filename_to_coords(file_name)
			if coords != Vector2i.MAX:
				result[coords] = dir_path.path_join(file_name)
		file_name = dir.get_next()

	dir.list_dir_end()
	return result


## Ensure directory exists, create if needed
## Returns true on success
static func ensure_directory_exists(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return true

	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		printerr("TerrainFileUtils: Failed to create directory: ", path, " Error: ", err)
		return false

	return true


## Get the default data directory for a terrain node
## Format: [SceneDir]/[SceneName]_TerrainData/[NodeName]/
static func get_default_data_directory(terrain_node: Node3D) -> String:
	if not terrain_node:
		return ""

	var scene_root := terrain_node.get_tree().edited_scene_root if Engine.is_editor_hint() else terrain_node.get_tree().current_scene
	if not scene_root or scene_root.scene_file_path.is_empty():
		return ""

	var scene_path := scene_root.scene_file_path
	var scene_dir := scene_path.get_base_dir()
	var scene_name := scene_path.get_file().get_basename()
	var node_name := terrain_node.name

	return scene_dir.path_join(scene_name + "_TerrainData").path_join(node_name) + "/"


## Delete a chunk file
## Returns true on success
static func delete_chunk_file(dir_path: String, coords: Vector2i) -> bool:
	var file_path := dir_path.path_join(coords_to_filename(coords))

	if not FileAccess.file_exists(file_path):
		return true  # Already doesn't exist

	var err := DirAccess.remove_absolute(file_path)
	if err != OK:
		printerr("TerrainFileUtils: Failed to delete file: ", file_path, " Error: ", err)
		return false

	return true


## Check if a chunk file exists
static func chunk_file_exists(dir_path: String, coords: Vector2i) -> bool:
	var file_path := dir_path.path_join(coords_to_filename(coords))
	return FileAccess.file_exists(file_path)


## Get full path for a chunk file
static func get_chunk_file_path(dir_path: String, coords: Vector2i) -> String:
	return dir_path.path_join(coords_to_filename(coords))
