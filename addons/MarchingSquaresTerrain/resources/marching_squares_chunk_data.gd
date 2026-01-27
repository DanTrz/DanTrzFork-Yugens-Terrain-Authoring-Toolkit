@tool
class_name MarchingSquaresChunkData
extends Resource
## Container for all chunk data in a single external .res file.
## This resource stores both source data (for regeneration) and generated data (for fast loading).


## Metadata
@export var chunk_coords: Vector2i = Vector2i.ZERO
@export var merge_mode: int = 1  # MarchingSquaresTerrainChunk.Mode.POLYHEDRON
@export var version: int = 1  # For future format migrations


## Source data (used for regeneration if needed)
@export var height_map: Array = []
@export var color_map_0: PackedColorArray = PackedColorArray()
@export var color_map_1: PackedColorArray = PackedColorArray()
@export var wall_color_map_0: PackedColorArray = PackedColorArray()
@export var wall_color_map_1: PackedColorArray = PackedColorArray()
@export var grass_mask_map: PackedColorArray = PackedColorArray()


## Generated data (cached for fast loading)
@export var mesh: ArrayMesh = null
@export var collision_faces: PackedVector3Array = PackedVector3Array()  # For ConcavePolygonShape3D
@export var grass_multimesh: MultiMesh = null


## Cell geometry cache (optional - for grass regeneration without full mesh rebuild)
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
	color_map_0 = PackedColorArray()
	color_map_1 = PackedColorArray()
	wall_color_map_0 = PackedColorArray()
	wall_color_map_1 = PackedColorArray()
	grass_mask_map = PackedColorArray()
	mesh = null
	collision_faces = PackedVector3Array()
	grass_multimesh = null
	cell_geometry = {}
