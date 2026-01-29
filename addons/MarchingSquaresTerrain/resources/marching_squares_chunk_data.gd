@tool
class_name MarchingSquaresChunkData
extends Resource

## Metadata
@export var chunk_coords: Vector2i = Vector2i.ZERO
@export var merge_mode: int = 1  # MarchingSquaresTerrainChunk.Mode.POLYHEDRON
@export var version: int = 2  # v2 = compact byte storage


## Source data - V2 COMPACT FORMAT (1 byte per cell instead of 16)
@export var height_map: Array = []
@export var ground_texture_idx: PackedByteArray = PackedByteArray()  # Texture 0-15 per cell
@export var wall_texture_idx: PackedByteArray = PackedByteArray()    # Texture 0-15 per cell
@export var grass_mask: PackedByteArray = PackedByteArray()          # 0 or 1 per cell


## V1 LEGACY FORMAT (kept for backward compatibility)
@export var color_map_0: PackedColorArray = PackedColorArray()
@export var color_map_1: PackedColorArray = PackedColorArray()
@export var wall_color_map_0: PackedColorArray = PackedColorArray()
@export var wall_color_map_1: PackedColorArray = PackedColorArray()
@export var grass_mask_map: PackedColorArray = PackedColorArray()


## Generated data (cached for fast loading)
@export var mesh: ArrayMesh = null
@export var collision_faces: PackedVector3Array = PackedVector3Array()  # For ConcavePolygonShape3D
@export var grass_multimesh: MultiMesh = null


## Kept for backward compatibility when loading old files #TODO: Remove (we likely will never need this	in the new model)
@export var cell_geometry: Dictionary = {}


## Create collision shape from stored faces
func get_collision_shape() -> ConcavePolygonShape3D:
	if collision_faces.is_empty():
		return null
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(collision_faces)
	return shape


## Store collision faces from existing shape
func set_collision_from_shape(shape: ConcavePolygonShape3D) -> void:
	if shape:
		collision_faces = shape.get_faces()
	else:
		collision_faces = PackedVector3Array()


## Check if this chunk data has valid content
func is_valid() -> bool:
	return not height_map.is_empty()


## Clear all data
func clear() -> void:
	height_map = []
	ground_texture_idx = PackedByteArray()
	wall_texture_idx = PackedByteArray()
	grass_mask = PackedByteArray()
	color_map_0 = PackedColorArray()
	color_map_1 = PackedColorArray()
	wall_color_map_0 = PackedColorArray()
	wall_color_map_1 = PackedColorArray()
	grass_mask_map = PackedColorArray()
	mesh = null
	collision_faces = PackedVector3Array()
	grass_multimesh = null
	cell_geometry = {}


## Check if using v2 compact format
func is_v2_format() -> bool:
	return not ground_texture_idx.is_empty()


## Convert Color pair to texture index (0-15)
static func colors_to_texture_idx(c0: Color, c1: Color) -> int:
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
static func texture_idx_to_colors(idx: int) -> Array:
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
