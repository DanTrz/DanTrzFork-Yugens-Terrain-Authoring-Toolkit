@tool
class_name MSTDataHandler
extends RefCounted
## Central handler for all external terrain data storage operations.


const ChunkData = preload("uid://bf23lqlv5tm2c")



# DIRECTORY MANAGEMENT
## Generate a unique terrain ID (called once on first save)
## Format: 8 hex chars (e.g., "a1b2c3d4")
static func generate_terrain_uid() -> String:
	return "%08x" % (randi() ^ int(Time.get_unix_time_from_system()))


## Ensure directory exists, create if needed
## Returns true on success
static func ensure_directory_exists(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return true

	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		printerr("MSTDataHandler: Failed to create directory: ", path, " Error: ", err)
		return false

	return true


## Get the resolved data directory path for a terrain node
## Path format: [SceneDir]/[SceneName]_TerrainData/[NodeName]_[UID]/
static func get_data_directory(terrain: MarchingSquaresTerrain) -> String:
	var dir_path := terrain.data_directory

	# If empty, generate default path based on scene location with unique UID
	if dir_path.is_empty():
		var tree := terrain.get_tree()
		if not tree:
			return ""  # Node not in scene tree yet
		var scene_root := tree.edited_scene_root if Engine.is_editor_hint() else tree.current_scene
		if not scene_root or scene_root.scene_file_path.is_empty():
			return ""

		# Generate UID if not set (first save)
		if terrain._terrain_uid.is_empty():
			terrain._terrain_uid = generate_terrain_uid()

		var scene_path := scene_root.scene_file_path
		var scene_dir := scene_path.get_base_dir()
		var scene_name := scene_path.get_file().get_basename()
		# Include UID in path to prevent collisions when nodes are recreated with same name
		dir_path = scene_dir.path_join(scene_name + "_TerrainData").path_join(terrain.name + "_" + terrain._terrain_uid) + "/"

	# Ensure path ends with /
	if not dir_path.is_empty() and not dir_path.ends_with("/"):
		dir_path += "/"

	return dir_path


# SAVE OPERATIONS
## Save all dirty chunks to external .res files
## This saves individual resources and sets their resource_path to prevent scene embedding
static func save_all_chunks(terrain: MarchingSquaresTerrain) -> void:
	var dir_path := get_data_directory(terrain)
	if dir_path.is_empty():
		# No valid data directory - scene might not be saved yet
		return

	# Ensure directory exists
	if not ensure_directory_exists(dir_path):
		printerr("MSTDataHandler: Failed to create data directory: ", dir_path)
		return

	var saved_count := 0
	for chunk_coords in terrain.chunks:
		var chunk = terrain.chunks[chunk_coords]  # Untyped to avoid cyclic reference

		# Skip chunks being removed during undo/redo
		if chunk._skip_save_on_exit:
			continue

		# Determine if chunk needs saving:
		# 1. Chunk is marked dirty (terrain was edited)
		# 2. Metadata doesn't exist yet
		var needs_save : bool = chunk._data_dirty
		if not needs_save and not metadata_exists(terrain, chunk_coords):
			needs_save = true

		if needs_save:
			save_chunk_resources(terrain, chunk)
			chunk._data_dirty = false
			saved_count += 1

	if saved_count > 0:
		print_verbose("MSTDataHandler: Saved ", saved_count, " chunk(s) to ", dir_path)

	# Clean up orphaned chunk directories that no longer exist in scene
	cleanup_orphaned_chunk_files(terrain)

	terrain._storage_initialized = true


## Save chunk data with hybrid storage
static func save_chunk_resources(terrain: MarchingSquaresTerrain, chunk) -> void:
	var dir_path := get_data_directory(terrain)
	if dir_path.is_empty():
		printerr("MSTDataHandler: Cannot save chunk - no valid data directory")
		return

	var chunk_name := "chunk_%d_%d" % [chunk.chunk_coords.x, chunk.chunk_coords.y]
	var chunk_dir := dir_path + chunk_name + "/"
	ensure_directory_exists(chunk_dir)

	# Save metadata / source data only (mesh, collision, grass regenerated on load)
	var data : ChunkData = MSTDataHandler.export_chunk_data(chunk)
	data.mesh = null
	data.grass_multimesh = null
	data.collision_faces = PackedVector3Array()
	var metadata_path := chunk_dir + "metadata.res"
	var err := ResourceSaver.save(data, metadata_path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		printerr("MSTDataHandler: Failed to save metadata to ", metadata_path)

	print_verbose("MSTDataHandler: Saved chunk ", chunk.chunk_coords)


# LOAD OPERATIONS
## Load all terrain data from external files
static func load_terrain_data(terrain: MarchingSquaresTerrain) -> void:
	var dir_path := get_data_directory(terrain)
	if dir_path.is_empty():
		return

	# Scan for chunk directories (new format: chunk_X_Y/)
	var dir := DirAccess.open(dir_path)
	if not dir:
		return

	var chunk_dirs : Array[Vector2i] = []
	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and folder_name.begins_with("chunk_"):
			# Parse chunk coordinates from folder name: chunk_X_Y
			var parts := folder_name.trim_prefix("chunk_").split("_")
			if parts.size() == 2:
				var coords := Vector2i(int(parts[0]), int(parts[1]))
				chunk_dirs.append(coords)
		folder_name = dir.get_next()
	dir.list_dir_end()

	# Fall back to legacy format if no chunk directories found
	if chunk_dirs.is_empty():
		var chunk_files := get_chunk_files_in_directory(dir_path)
		if not chunk_files.is_empty():
			print_verbose("MSTDataHandler: Loading ", chunk_files.size(), " chunk(s) from legacy format")
			for coords in chunk_files:
				load_chunk_legacy(terrain, coords)
			terrain._storage_initialized = true
		return

	print_verbose("MSTDataHandler: Loading ", chunk_dirs.size(), " chunk(s) from ", dir_path)

	for coords in chunk_dirs:
		load_chunk_from_directory(terrain, coords)

	terrain._storage_initialized = true


## Load a single chunk's source data from metadata file
## Mesh, collision, and grass are regenerated separately
static func load_chunk_from_directory(terrain: MarchingSquaresTerrain, coords: Vector2i) -> void:
	var dir_path := get_data_directory(terrain)
	var chunk_name := "chunk_%d_%d" % [coords.x, coords.y]
	var chunk_dir := dir_path + chunk_name + "/"

	var chunk = terrain.chunks.get(coords)
	if not chunk:
		return

	# Load metadata source data only
	var metadata_path := chunk_dir + "metadata.res"
	if ResourceLoader.exists(metadata_path):
		var data : ChunkData = load(metadata_path)
		if data:
			import_chunk_data(chunk, data)

	print_verbose("MSTDataHandler: Loaded chunk ", coords)


## Load a single chunk from legacy single-file format
static func load_chunk_legacy(terrain: MarchingSquaresTerrain, coords: Vector2i) -> void:
	var data : ChunkData = load_chunk_metadata(terrain, coords)
	if not data:
		return

	var chunk = terrain.chunks.get(coords)  # Untyped to avoid cyclic reference
	if chunk:
		import_chunk_data(chunk, data)


## Load a single chunk's metadata from external .res file
static func load_chunk_metadata(terrain: MarchingSquaresTerrain, coords: Vector2i) -> ChunkData:
	var dir_path := get_data_directory(terrain)
	if dir_path.is_empty():
		return null

	var chunk_dir := dir_path + "chunk_%d_%d/" % [coords.x, coords.y]
	var metadata_path := chunk_dir + "metadata.res"

	if not FileAccess.file_exists(metadata_path):
		# Try legacy format for backward compatibility
		var legacy_path := get_chunk_file_path(dir_path, coords)
		if FileAccess.file_exists(legacy_path):
			var data = load(legacy_path)
			if data is ChunkData:
				return data
		return null

	var data = load(metadata_path)
	if data is ChunkData:
		return data
	else:
		printerr("MSTDataHandler: Invalid chunk data at ", metadata_path)
		return null


# CLEANUP OPERATION
## Clean up orphaned chunk directories that no longer exist in the scene
## Called automatically during save to prevent disk issues
static func cleanup_orphaned_chunk_files(terrain: MarchingSquaresTerrain) -> void:
	var dir_path := get_data_directory(terrain)
	if dir_path.is_empty():
		return

	var dir := DirAccess.open(dir_path)
	if not dir:
		return

	var orphaned_dirs : Array[String] = []

	dir.list_dir_begin()
	var folder_name := dir.get_next()
	while folder_name != "":
		if dir.current_is_dir() and folder_name.begins_with("chunk_"):
			# Parse chunk coordinates from folder name: chunk_X_Y
			var parts := folder_name.trim_prefix("chunk_").split("_")
			if parts.size() == 2:
				var coords := Vector2i(int(parts[0]), int(parts[1]))
				# If chunk doesn't exist in scene, mark for deletion
				if not terrain.chunks.has(coords):
					orphaned_dirs.append(dir_path + folder_name + "/")
		folder_name = dir.get_next()
	dir.list_dir_end()

	# Delete orphaned directories
	for orphaned_dir in orphaned_dirs:
		delete_chunk_directory(orphaned_dir)
		print_verbose("MSTDataHandler: Cleaned up orphaned chunk at ", orphaned_dir)


## Delete a chunk directory and all its contents
static func delete_chunk_directory(chunk_dir: String) -> void:
	var dir := DirAccess.open(chunk_dir)
	if not dir:
		return

	# Delete all files in directory
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir():
			var err := dir.remove(file_name)
			if err != OK:
				printerr("MSTDataHandler: Failed to delete file ", file_name, " in ", chunk_dir)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Remove the directory itself
	var err := DirAccess.remove_absolute(chunk_dir.trim_suffix("/"))
	if err != OK:
		printerr("MSTDataHandler: Failed to delete directory ", chunk_dir)


# UTILITY OPERATIONS
## Check if metadata.res exists for a chunk
static func metadata_exists(terrain: MarchingSquaresTerrain, coords: Vector2i) -> bool:
	var dir_path := get_data_directory(terrain)
	var chunk_dir := dir_path + "chunk_%d_%d/" % [coords.x, coords.y]
	return FileAccess.file_exists(chunk_dir + "metadata.res")


## Check if chunk resources exist (checks metadata)
static func chunk_resources_exist(terrain: MarchingSquaresTerrain, coords: Vector2i) -> bool:
	return metadata_exists(terrain, coords)


## Check if this terrain needs migration from embedded to external storage
static func needs_migration(terrain: MarchingSquaresTerrain) -> bool:
	# If already initialized with external storage, no migration needed
	if terrain._storage_initialized:
		return false

	# Check if any chunks have embedded data but no external files exist
	var dir_path := get_data_directory(terrain)
	if dir_path.is_empty():
		return false

	for chunk_coords in terrain.chunks:
		var chunk = terrain.chunks[chunk_coords]  
		if chunk.height_map and not chunk.height_map.is_empty():
			if not chunk_resources_exist(terrain, chunk_coords):
				return true

	return false


## Migrate existing embedded data to external storage
static func migrate_to_external_storage(terrain: MarchingSquaresTerrain) -> void:
	print("MSTDataHandler: Migrating to external storage...")

	# Mark all chunks as dirty to force save
	for chunk_coords in terrain.chunks:
		var chunk = terrain.chunks[chunk_coords]  # Untyped to avoid cyclic reference
		chunk._data_dirty = true

	save_all_chunks(terrain)

	print("MSTDataHandler: Migration complete. External data saved to: ", get_data_directory(terrain))


# DATA SERIALIZATION (from marching_squares_terrain_chunk.gd)
## Convert chunk state to MarchingSquaresChunkData for external storage
static func export_chunk_data(chunk) -> ChunkData:
	var data := ChunkData.new()
	data.chunk_coords = chunk.chunk_coords
	data.merge_mode = chunk.merge_mode

	# Source data (deep copy for arrays)
	data.height_map = chunk.height_map.duplicate(true)
	# Convert to compact v2 format (1 byte per cell instead of 16)
	var cell_count : int = chunk.color_map_0.size()
	data.ground_texture_idx.resize(cell_count)
	data.wall_texture_idx.resize(cell_count)
	data.grass_mask.resize(cell_count)

	for i in cell_count:
		data.ground_texture_idx[i] = _colors_to_texture_idx(chunk.color_map_0[i], chunk.color_map_1[i])
		data.wall_texture_idx[i] = _colors_to_texture_idx(chunk.wall_color_map_0[i], chunk.wall_color_map_1[i])
		data.grass_mask[i] = 1 if chunk.grass_mask_map[i].r > 0.5 else 0

	# Clear legacy arrays (not needed in v2)
	data.color_map_0 = PackedColorArray()
	data.color_map_1 = PackedColorArray()
	data.wall_color_map_0 = PackedColorArray()
	data.wall_color_map_1 = PackedColorArray()
	data.grass_mask_map = PackedColorArray()

	# Generated data
	data.mesh = chunk.mesh

	# Extract collision shape faces
	for child in chunk.get_children():
		if child is StaticBody3D:
			for shape_child in child.get_children():
				if shape_child is CollisionShape3D and shape_child.shape is ConcavePolygonShape3D:
					data.set_collision_from_shape(shape_child.shape)
					break

	# Grass multimesh
	if chunk.grass_planter and chunk.grass_planter.multimesh:
		data.grass_multimesh = chunk.grass_planter.multimesh

	return data


## Restore chunk state from MarchingSquaresChunkData (loaded from external file)
static func import_chunk_data(chunk, data: ChunkData) -> void:
	if not data:
		printerr("MSTDataHandler: import_chunk_data called with null data")
		return

	chunk.chunk_coords = data.chunk_coords
	chunk.merge_mode = data.merge_mode
	chunk.height_map = data.height_map.duplicate(true)

	# Check format version
	var is_v2 : bool = not data.ground_texture_idx.is_empty()

	if is_v2:
		# V2 compact format: expand bytes to Colors
		var cell_count : int = data.ground_texture_idx.size()
		chunk.color_map_0.resize(cell_count)
		chunk.color_map_1.resize(cell_count)
		chunk.wall_color_map_0.resize(cell_count)
		chunk.wall_color_map_1.resize(cell_count)
		chunk.grass_mask_map.resize(cell_count)

		for i in cell_count:
			var ground_colors : Array = _texture_idx_to_colors(data.ground_texture_idx[i])
			chunk.color_map_0[i] = ground_colors[0]
			chunk.color_map_1[i] = ground_colors[1]

			var wall_colors : Array = _texture_idx_to_colors(data.wall_texture_idx[i])
			chunk.wall_color_map_0[i] = wall_colors[0]
			chunk.wall_color_map_1[i] = wall_colors[1]

			chunk.grass_mask_map[i] = Color(1, 0, 0, 0) if data.grass_mask[i] > 0 else Color(0, 0, 0, 0)

		chunk._data_dirty = true  # Force re-save to update any migrated data
	else:
		# V1 legacy format: direct copy
		chunk.color_map_0 = data.color_map_0.duplicate()
		chunk.color_map_1 = data.color_map_1.duplicate()
		chunk.wall_color_map_0 = data.wall_color_map_0.duplicate()
		chunk.wall_color_map_1 = data.wall_color_map_1.duplicate()
		chunk.grass_mask_map = data.grass_mask_map.duplicate()
		chunk._data_dirty = true  # Force re-save in v2 format

	# cell_geometry is regenerated during mesh generation


## Get the current collision shape from a chunk (if any)
static func get_collision_shape(chunk) -> ConcavePolygonShape3D:
	for child in chunk.get_children():
		if child is StaticBody3D:
			for shape_child in child.get_children():
				if shape_child is CollisionShape3D and shape_child.shape is ConcavePolygonShape3D:
					return shape_child.shape
	return null


## Apply collision shape from external data to a chunk
static func apply_collision_shape(chunk, shape: ConcavePolygonShape3D) -> void:
	# Remove existing collision bodies - reset owner first to prevent dangling references
	for child in chunk.get_children():
		if child is StaticBody3D:
			child.owner = null
			for shape_child in child.get_children():
				if shape_child is CollisionShape3D:
					shape_child.owner = null
			child.free()

	if not shape:
		return

	var body := StaticBody3D.new()
	body.collision_layer = 17  # ground (1) + terrain (16)
	var col_shape := CollisionShape3D.new()
	col_shape.shape = shape
	body.add_child(col_shape)
	chunk.add_child(body)

	# Set owner for scene persistence (editor only) #TODO: We might not need to set owner here? Like I did in TileMapLayer3D
	if Engine.is_editor_hint():
		var scene_root = EditorInterface.get_edited_scene_root()
		if scene_root:
			body.owner = scene_root
			col_shape.owner = scene_root


# HLEPRR FUNCTIONS
## Convert chunk coordinates to filename (legacy format)
static func coords_to_filename(coords: Vector2i) -> String:
	return "terrain_chunk_%d_%d.res" % [coords.x, coords.y]


## Parse filename to extract chunk coordinates (legacy format)
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


## Get all chunk files in a directory (legacy format)
static func get_chunk_files_in_directory(dir_path: String) -> Dictionary:
	var result := {}

	if not DirAccess.dir_exists_absolute(dir_path):
		return result

	var dir := DirAccess.open(dir_path)
	if not dir:
		printerr("MSTDataHandler: Failed to open directory: ", dir_path)
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


## Get full path for a chunk file (legacy format)
static func get_chunk_file_path(dir_path: String, coords: Vector2i) -> String:
	return dir_path.path_join(coords_to_filename(coords))


# COLOR CONVERSION HELPERS
## Convert Color pair to texture index (0-15)
static func _colors_to_texture_idx(c0: Color, c1: Color) -> int:
	var c0_idx := 0
	var c0_max := c0.r
	if c0.g > c0_max: c0_max = c0.g; c0_idx = 1
	if c0.b > c0_max: c0_max = c0.b; c0_idx = 2
	if c0.a > c0_max: c0_idx = 3

	var c1_idx := 0
	var c1_max := c1.r
	if c1.g > c1_max: c1_max = c1.g; c1_idx = 1
	if c1.b > c1_max: c1_max = c1.b; c1_idx = 2
	if c1.a > c1_max: c1_idx = 3

	return c0_idx * 4 + c1_idx


## Convert texture index (0-15) to Color pair
static func _texture_idx_to_colors(idx: int) -> Array:
	var c0 := Color(0, 0, 0, 0)
	var c1 := Color(0, 0, 0, 0)
	var c0_ch := idx / 4
	var c1_ch := idx % 4
	match c0_ch:
		0: c0.r = 1.0
		1: c0.g = 1.0
		2: c0.b = 1.0
		3: c0.a = 1.0
	match c1_ch:
		0: c1.r = 1.0
		1: c1.g = 1.0
		2: c1.b = 1.0
		3: c1.a = 1.0
	return [c0, c1]
