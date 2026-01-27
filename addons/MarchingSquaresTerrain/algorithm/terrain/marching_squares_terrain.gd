@tool
extends Node3D
# Needs to be kept as a Node3D so that the 3d gizmo works. no 3d functionality is otherwise used, it is delegated to the chunks
class_name MarchingSquaresTerrain

const FileUtils = preload("res://addons/MarchingSquaresTerrain/resources/terrain_file_utils.gd")
const ChunkData = preload("res://addons/MarchingSquaresTerrain/resources/marching_squares_chunk_data.gd")

## External storage directory for chunk data files.
## Leave empty to use default: [SceneDir]/[SceneName]_TerrainData/[NodeName]/
@export var data_directory : String = "":
	set(value):
		data_directory = value
		# Trigger load when directory is changed in editor
		if Engine.is_editor_hint() and is_inside_tree() and not value.is_empty():
			call_deferred("_load_terrain_data")

## Internal flag to track if external storage has been initialized
@export_storage var _storage_initialized : bool = false

## Unique identifier for this terrain instance (auto-generated on first save)
## Used to create unique data directory paths, preventing collisions when
## nodes are deleted and recreated with the same name
@export_storage var _terrain_uid : String = ""

@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var dimensions : Vector3i = Vector3i(33, 32, 33): # Total amount of height values in X and Z direction, and total height range
	set(value):
		dimensions = value
		terrain_material.set_shader_parameter("chunk_size", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var cell_size : Vector2 = Vector2(2, 2): # XZ Unit size of each cell
	set(value):
		cell_size = value
		terrain_material.set_shader_parameter("cell_size", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_hard_textures : bool = false:
	set(value):
		use_hard_textures = value
		terrain_material.set_shader_parameter("use_hard_square_edges", value)
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_threshold : float = 0.0: # Determines on what part of the terrain's mesh are walls
	set(value):
		wall_threshold = value
		terrain_material.set_shader_parameter("wall_threshold", value)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("wall_threshold", value)
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var noise_hmap : Noise # used to generate smooth initial heights for more natrual looking terrain. if null, initial terrain will be flat
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_texture : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res"):
	set(value):
		ground_texture = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_rr", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if ground_texture:
				grass_mat.set_shader_parameter("use_base_color", false)
			else:
				grass_mat.set_shader_parameter("use_base_color", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
# Legacy wall texture properties - kept for backward compatibility with existing scenes
# These are no-ops: the unified 16-texture system is now used for both ground and walls
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_texture : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/wall_noise_texture.res"):
	set(value):
		wall_texture = value  # Store for persistence only - no shader effect
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_texture_2 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/wall_noise_texture.res"):
	set(value):
		wall_texture_2 = value  # Store for persistence only - no shader effect
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_texture_3 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/wall_noise_texture.res"):
	set(value):
		wall_texture_3 = value  # Store for persistence only - no shader effect
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_texture_4 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/wall_noise_texture.res"):
	set(value):
		wall_texture_4 = value  # Store for persistence only - no shader effect
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_texture_5 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/wall_noise_texture.res"):
	set(value):
		wall_texture_5 = value  # Store for persistence only - no shader effect
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_texture_6 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/wall_noise_texture.res"):
	set(value):
		wall_texture_6 = value  # Store for persistence only - no shader effect
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_color : Color = Color("647851ff"):
	set(value):
		ground_color = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("ground_albedo", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_base_color", value)
# Legacy wall color properties - kept for backward compatibility with existing scenes
# These are no-ops: walls now use the same color tinting as ground textures via the unified system
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_color : Color = Color("5e5645ff"):
	set(value):
		wall_color = value  # Store for persistence only - no shader effect
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_color_2 : Color = Color("665950ff"):
	set(value):
		wall_color_2 = value  # Store for persistence only - no shader effect
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_color_3 : Color = Color("595240ff"):
	set(value):
		wall_color_3 = value  # Store for persistence only - no shader effect
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_color_4 : Color = Color("615745ff"):
	set(value):
		wall_color_4 = value  # Store for persistence only - no shader effect
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_color_5 : Color = Color("5c5442ff"):
	set(value):
		wall_color_5 = value  # Store for persistence only - no shader effect
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var wall_color_6 : Color = Color("6b614cff"):
	set(value):
		wall_color_6 = value  # Store for persistence only - no shader effect

# Base grass settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var animation_fps : int = 0:
	set(value):
		animation_fps = clamp(value, 0, 30)
		var grass_mat := grass_mesh.material as ShaderMaterial
		grass_mat.set_shader_parameter("fps", clamp(value, 0, 30))
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_subdivisions := 3:
	set(value):
		grass_subdivisions = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.multimesh.instance_count = (dimensions.x-1) * (dimensions.z-1) * grass_subdivisions * grass_subdivisions
			chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_size := Vector2(1.0, 1.0):
	set(value):
		grass_size = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.multimesh.mesh.size = value
			chunk.grass_planter.multimesh.mesh.center_offset.y = value.y / 2
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ridge_threshold: float = 1.0:
	set(value):
		ridge_threshold = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ledge_threshold: float = 0.25:
	set(value):
		ledge_threshold = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var use_ridge_texture: bool = false:
	set(value):
		use_ridge_texture = value
		for chunk: MarchingSquaresTerrainChunk in chunks.values():
			chunk.regenerate_all_cells()

# Vertex painting texture settings
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_2 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res"):
	set(value):
		texture_2 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_rg", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_2:
				grass_mat.set_shader_parameter("use_base_color_2", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_2", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_3 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res"):
	set(value):
		texture_3 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_rb", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_3:
				grass_mat.set_shader_parameter("use_base_color_3", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_3", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_4 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res"):
	set(value):
		texture_4 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ra", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_4:
				grass_mat.set_shader_parameter("use_base_color_4", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_4", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_5 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res"):
	set(value):
		texture_5 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_gr", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_5:
				grass_mat.set_shader_parameter("use_base_color_5", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_5", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_6 : Texture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_terrain_noise.res"):
	set(value):
		texture_6 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_gg", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			if texture_6:
				grass_mat.set_shader_parameter("use_base_color_6", false)
			else:
				grass_mat.set_shader_parameter("use_base_color_6", true)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_7 : Texture2D:
	set(value):
		texture_7 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_gb", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_8 : Texture2D:
	set(value):
		texture_8 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ga", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_9 : Texture2D:
	set(value):
		texture_9 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_br", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_10 : Texture2D:
	set(value):
		texture_10 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_bg", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_11 : Texture2D:
	set(value):
		texture_11 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_bb", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_12 : Texture2D:
	set(value):
		texture_12 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ba", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_13 : Texture2D:
	set(value):
		texture_13 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ar", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_14 : Texture2D:
	set(value):
		texture_14 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ag", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_15 : Texture2D:
	set(value):
		texture_15 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("vc_tex_ab", value)
			for chunk: MarchingSquaresTerrainChunk in chunks.values():
				chunk.grass_planter.regenerate_all_cells()
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex2_has_grass : bool = true:
	set(value):
		tex2_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex3_has_grass : bool = true:
	set(value):
		tex3_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex4_has_grass : bool = true:
	set(value):
		tex4_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex5_has_grass : bool = true:
	set(value):
		tex5_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var tex6_has_grass : bool = true:
	set(value):
		tex6_has_grass = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("use_grass_tex_6", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_2 : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_2 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_3 : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_3 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_4 : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_4 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_5 : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_5 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var grass_sprite_tex_6 : CompressedTexture2D = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/grass_leaf_sprite.png"):
	set(value):
		grass_sprite_tex_6 = value
		if not is_batch_updating:
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_texture_6", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_color_2 : Color = Color("527b62ff"):
	set(value):
		ground_color_2 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("ground_albedo_2", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_color_3 : Color = Color("5f6c4bff"):
	set(value):
		ground_color_3 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("ground_albedo_3", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_color_4 : Color = Color("647941ff"):
	set(value):
		ground_color_4 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("ground_albedo_4", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_color_5 : Color = Color("4a7e5dff"):
	set(value):
		ground_color_5 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("ground_albedo_5", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var ground_color_6 : Color = Color("71725dff"):
	set(value):
		ground_color_6 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("ground_albedo_6", value)
			var grass_mat := grass_mesh.material as ShaderMaterial
			grass_mat.set_shader_parameter("grass_color_6", value)

# Per-texture UV scaling (applied in shader)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_1 : float = 1.0:
	set(value):
		texture_scale_1 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_1", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_2 : float = 1.0:
	set(value):
		texture_scale_2 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_2", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_3 : float = 1.0:
	set(value):
		texture_scale_3 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_3", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_4 : float = 1.0:
	set(value):
		texture_scale_4 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_4", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_5 : float = 1.0:
	set(value):
		texture_scale_5 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_5", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_6 : float = 1.0:
	set(value):
		texture_scale_6 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_6", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_7 : float = 1.0:
	set(value):
		texture_scale_7 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_7", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_8 : float = 1.0:
	set(value):
		texture_scale_8 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_8", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_9 : float = 1.0:
	set(value):
		texture_scale_9 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_9", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_10 : float = 1.0:
	set(value):
		texture_scale_10 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_10", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_11 : float = 1.0:
	set(value):
		texture_scale_11 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_11", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_12 : float = 1.0:
	set(value):
		texture_scale_12 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_12", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_13 : float = 1.0:
	set(value):
		texture_scale_13 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_13", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_14 : float = 1.0:
	set(value):
		texture_scale_14 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_14", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_15 : float = 1.0:
	set(value):
		texture_scale_15 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_15", value)
@export_custom(PROPERTY_HINT_NONE, "", PROPERTY_USAGE_STORAGE) var texture_scale_16 : float = 1.0:
	set(value):
		texture_scale_16 = value
		if not is_batch_updating:
			terrain_material.set_shader_parameter("texture_scale_16", value)

@export_storage var current_texture_preset : MarchingSquaresTexturePreset = null

# Default wall texture slot (0-15) used when no quick paint is active
# Default is 5 (Texture 6 in 1-indexed UI terms)
@export_storage var default_wall_texture_slot : int = 5

var void_texture := preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/void_texture.tres")
var placeholder_wind_texture := preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/wind_noise_texture.tres") # Change to your own texture

var terrain_material : ShaderMaterial = null
var grass_mesh : QuadMesh = null 

var is_batch_updating : bool = false

var chunks : Dictionary = {}


func _init() -> void:
	# Create unique copies of shared resources for this node instance
	# This prevents texture/material changes from affecting other MarchingSquaresTerrain nodes
	terrain_material = preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/mst_terrain_shader.tres").duplicate(true)
	var base_grass_mesh := preload("res://addons/MarchingSquaresTerrain/resources/plugin materials/mst_grass_mesh.tres")
	grass_mesh = base_grass_mesh.duplicate(true)
	grass_mesh.material = base_grass_mesh.material.duplicate(true)


func _enter_tree() -> void:
	call_deferred("_deferred_enter_tree")


func _deferred_enter_tree() -> void:
	if not Engine.is_editor_hint():
		return

	# Apply all persisted textures/colors to this terrain's unique shader materials
	# This is needed because _init() creates fresh duplicated materials that don't have
	# the terrain's saved texture values - only the base resource defaults
	force_batch_update()

	chunks.clear()
	for chunk in get_children():
		if chunk is MarchingSquaresTerrainChunk:
			chunks[chunk.chunk_coords] = chunk
			chunk.terrain_system = self
			chunk.grass_planter = null

	# Check for external data storage
	if _storage_initialized:
		# Load chunk data from external files
		_load_terrain_data()
	elif _needs_migration():
		# Existing scene with embedded data - migrate to external storage
		print("MarchingSquaresTerrain: Detected embedded data, will migrate on next save")
		# Mark all chunks as dirty so they will be saved externally
		for chunk_coords in chunks:
			var chunk : MarchingSquaresTerrainChunk = chunks[chunk_coords]
			chunk._data_dirty = true

	# Initialize all chunks (load external data or use embedded)
	for chunk_coords in chunks:
		var chunk : MarchingSquaresTerrainChunk = chunks[chunk_coords]
		chunk.initialize_terrain(true)


func has_chunk(x: int, z: int) -> bool:
	return chunks.has(Vector2i(x, z))


func add_new_chunk(chunk_x: int, chunk_z: int):
	var chunk_coords := Vector2i(chunk_x, chunk_z)
	var new_chunk := MarchingSquaresTerrainChunk.new()
	new_chunk.name = "Chunk "+str(chunk_coords)
	new_chunk.terrain_system = self
	add_chunk(chunk_coords, new_chunk, false)
	
	var chunk_left: MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x-1, chunk_z))
	if chunk_left:
		for z in range(0, dimensions.z):
			new_chunk.height_map[z][0] = chunk_left.height_map[z][dimensions.x - 1]
	
	var chunk_right: MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x+1, chunk_z))
	if chunk_right:
		for z in range(0, dimensions.z):
			chunk_right.height_map[z][dimensions.x - 1] = chunk_right.height_map[z][0]
	
	var chunk_up: MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z-1))
	if chunk_up:
		for x in range(0, dimensions.x):
			new_chunk.height_map[0][x] = chunk_up.height_map[dimensions.z - 1][x]
	
	var chunk_down: MarchingSquaresTerrainChunk = chunks.get(Vector2i(chunk_x, chunk_z+1))
	if chunk_down:
		for x in range(0, dimensions.x):
			new_chunk.height_map[dimensions.z - 1][x] = chunk_down.height_map[0][x]

	# Eagerly create data directory when first chunk is added
	# This prevents data loss if user creates terrain but doesn't save before closing
	var dir_path := get_data_directory()
	if not dir_path.is_empty():
		FileUtils.ensure_directory_exists(dir_path)

	new_chunk.regenerate_mesh()


func remove_chunk(x: int, z: int):
	var chunk_coords := Vector2i(x, z)
	var chunk: MarchingSquaresTerrainChunk = chunks[chunk_coords]
	chunks.erase(chunk_coords)  # Use chunk_coords, not chunk object
	chunk.free()


# Remove a chunk but still keep it in memory (so that undo can restore it)
func remove_chunk_from_tree(x: int, z: int):
	var chunk_coords := Vector2i(x, z)
	var chunk: MarchingSquaresTerrainChunk = chunks[chunk_coords]
	chunks.erase(chunk_coords)  # Use chunk_coords, not chunk object
	chunk._skip_save_on_exit = true  # Prevent mesh save during undo/redo
	remove_child(chunk)
	chunk.owner = null


func add_chunk(coords: Vector2i, chunk: MarchingSquaresTerrainChunk, regenerate_mesh: bool = true):
	chunks[coords] = chunk
	chunk.terrain_system = self
	chunk.chunk_coords = coords
	chunk._skip_save_on_exit = false  # Reset flag when chunk is re-added (undo restores chunk)
	
	add_child(chunk)
	
	# Use position instead of global_position to avoid "is_inside_tree()" errors
	# when multiple scenes with MarchingSquaresTerrain are open in editor tabs.
	# Since chunks are direct children of terrain, position equals global_position.
	chunk.position = Vector3(
		coords.x * ((dimensions.x - 1) * cell_size.x),
		0,
		coords.y * ((dimensions.z - 1) * cell_size.y)
	)
	
	_set_owner_recursive(chunk, EditorInterface.get_edited_scene_root())
	chunk.initialize_terrain(regenerate_mesh)
	print_verbose("Added new chunk to terrain system at ", chunk)


func _set_owner_recursive(node: Node, _owner: Node) -> void:
	node.owner = _owner
	for c in node.get_children():
		_set_owner_recursive(c, _owner)


# This function is mainly there to ensure the plugin works on startup in a new project
func _ensure_textures() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	if not grass_mat.get_shader_parameter("use_base_color") and terrain_material.get_shader_parameter("vc_tex_rr") == null:
		terrain_material.set_shader_parameter("vc_tex_rr", ground_texture)
	if grass_mat.get_shader_parameter("use_grass_tex_2") and terrain_material.get_shader_parameter("vc_tex_rg") == null:
		terrain_material.set_shader_parameter("vc_tex_rg", texture_2)
	if grass_mat.get_shader_parameter("use_grass_tex_3") and terrain_material.get_shader_parameter("vc_tex_rb") == null:
		terrain_material.set_shader_parameter("vc_tex_rb", texture_3)
	if grass_mat.get_shader_parameter("use_grass_tex_4") and terrain_material.get_shader_parameter("vc_tex_ra") == null:
		terrain_material.set_shader_parameter("vc_tex_ra", texture_4)
	if grass_mat.get_shader_parameter("use_grass_tex_5") and terrain_material.get_shader_parameter("vc_tex_gr") == null:
		terrain_material.set_shader_parameter("vc_tex_gr", texture_5)
	if grass_mat.get_shader_parameter("use_grass_tex_6") and terrain_material.get_shader_parameter("vc_tex_gg") == null:
		terrain_material.set_shader_parameter("vc_tex_gg", texture_6)
	if grass_mat.get_shader_parameter("wind_texture") == null:
		grass_mat.set_shader_parameter("wind_texture", placeholder_wind_texture)
	if wall_texture and terrain_material.get_shader_parameter("wall_tex_1") == null:
		terrain_material.set_shader_parameter("wall_tex_1", wall_texture)
	if grass_sprite and grass_mat.get_shader_parameter("grass_texture") == null:
		grass_mat.set_shader_parameter("grass_texture", grass_sprite)
	if grass_sprite_tex_2 and grass_mat.get_shader_parameter("grass_texture_2") == null:
		grass_mat.set_shader_parameter("grass_texture_2", grass_sprite_tex_2)
	if grass_sprite_tex_3 and grass_mat.get_shader_parameter("grass_texture_3") == null:
		grass_mat.set_shader_parameter("grass_texture_3", grass_sprite_tex_3)
	if grass_sprite_tex_4 and grass_mat.get_shader_parameter("grass_texture_4") == null:
		grass_mat.set_shader_parameter("grass_texture_4", grass_sprite_tex_4)
	if grass_sprite_tex_5 and grass_mat.get_shader_parameter("grass_texture_5") == null:
		grass_mat.set_shader_parameter("grass_texture_5", grass_sprite_tex_5)
	if grass_sprite_tex_6 and grass_mat.get_shader_parameter("grass_texture_6") == null:
		grass_mat.set_shader_parameter("grass_texture_6", grass_sprite_tex_6)
	if terrain_material.get_shader_parameter("vc_tex_aa") == null:
		terrain_material.set_shader_parameter("vc_tex_aa", void_texture)
	
	# Ensure wall albedo colors are set (required because setters don't run on load with defaults)
	terrain_material.set_shader_parameter("wall_albedo", wall_color)
	terrain_material.set_shader_parameter("wall_albedo_2", wall_color_2)
	terrain_material.set_shader_parameter("wall_albedo_3", wall_color_3)
	terrain_material.set_shader_parameter("wall_albedo_4", wall_color_4)
	terrain_material.set_shader_parameter("wall_albedo_5", wall_color_5)
	terrain_material.set_shader_parameter("wall_albedo_6", wall_color_6)


# Applies all shader parameters and regenerates grass once
# Call this after setting is_batch_updating = true and changing properties
func force_batch_update() -> void:
	var grass_mat := grass_mesh.material as ShaderMaterial
	
	# TERRAIN MATERIAL - Core parameters
	terrain_material.set_shader_parameter("cell_size", cell_size)
	
	# TERRAIN MATERIAL - Ground TExtures
	terrain_material.set_shader_parameter("vc_tex_rr", ground_texture)
	terrain_material.set_shader_parameter("vc_tex_rg", texture_2)
	terrain_material.set_shader_parameter("vc_tex_rb", texture_3)
	terrain_material.set_shader_parameter("vc_tex_ra", texture_4)
	terrain_material.set_shader_parameter("vc_tex_gr", texture_5)
	terrain_material.set_shader_parameter("vc_tex_gg", texture_6)
	terrain_material.set_shader_parameter("vc_tex_gb", texture_7)
	terrain_material.set_shader_parameter("vc_tex_ga", texture_8)
	terrain_material.set_shader_parameter("vc_tex_br", texture_9)
	terrain_material.set_shader_parameter("vc_tex_bg", texture_10)
	terrain_material.set_shader_parameter("vc_tex_bb", texture_11)
	terrain_material.set_shader_parameter("vc_tex_ba", texture_12)
	terrain_material.set_shader_parameter("vc_tex_ar", texture_13)
	terrain_material.set_shader_parameter("vc_tex_ag", texture_14)
	terrain_material.set_shader_parameter("vc_tex_ab", texture_15)

	# TERRAIN MATERIAL - Ground Colors (used for both floor and wall in unified system)
	terrain_material.set_shader_parameter("ground_albedo", ground_color)
	terrain_material.set_shader_parameter("ground_albedo_2", ground_color_2)
	terrain_material.set_shader_parameter("ground_albedo_3", ground_color_3)
	terrain_material.set_shader_parameter("ground_albedo_4", ground_color_4)
	terrain_material.set_shader_parameter("ground_albedo_5", ground_color_5)
	terrain_material.set_shader_parameter("ground_albedo_6", ground_color_6)

	# TERRAIN MATERIAL - Per-Texture UV Scales
	terrain_material.set_shader_parameter("texture_scale_1", texture_scale_1)
	terrain_material.set_shader_parameter("texture_scale_2", texture_scale_2)
	terrain_material.set_shader_parameter("texture_scale_3", texture_scale_3)
	terrain_material.set_shader_parameter("texture_scale_4", texture_scale_4)
	terrain_material.set_shader_parameter("texture_scale_5", texture_scale_5)
	terrain_material.set_shader_parameter("texture_scale_6", texture_scale_6)
	terrain_material.set_shader_parameter("texture_scale_7", texture_scale_7)
	terrain_material.set_shader_parameter("texture_scale_8", texture_scale_8)
	terrain_material.set_shader_parameter("texture_scale_9", texture_scale_9)
	terrain_material.set_shader_parameter("texture_scale_10", texture_scale_10)
	terrain_material.set_shader_parameter("texture_scale_11", texture_scale_11)
	terrain_material.set_shader_parameter("texture_scale_12", texture_scale_12)
	terrain_material.set_shader_parameter("texture_scale_13", texture_scale_13)
	terrain_material.set_shader_parameter("texture_scale_14", texture_scale_14)
	terrain_material.set_shader_parameter("texture_scale_15", texture_scale_15)
	terrain_material.set_shader_parameter("texture_scale_16", texture_scale_16)
	
	# GRASS MATERIAL - Grass Textures 
	grass_mat.set_shader_parameter("grass_texture", grass_sprite)
	grass_mat.set_shader_parameter("grass_texture_2", grass_sprite_tex_2)
	grass_mat.set_shader_parameter("grass_texture_3", grass_sprite_tex_3)
	grass_mat.set_shader_parameter("grass_texture_4", grass_sprite_tex_4)
	grass_mat.set_shader_parameter("grass_texture_5", grass_sprite_tex_5)
	grass_mat.set_shader_parameter("grass_texture_6", grass_sprite_tex_6)
	
	# GRASS MATERIAL - Grass Colors 
	grass_mat.set_shader_parameter("grass_base_color", ground_color)
	grass_mat.set_shader_parameter("grass_color_2", ground_color_2)
	grass_mat.set_shader_parameter("grass_color_3", ground_color_3)
	grass_mat.set_shader_parameter("grass_color_4", ground_color_4)
	grass_mat.set_shader_parameter("grass_color_5", ground_color_5)
	grass_mat.set_shader_parameter("grass_color_6", ground_color_6)
	
	# GRASS MATERIAL - Use Base Color Flags 
	grass_mat.set_shader_parameter("use_base_color", ground_texture == null)
	grass_mat.set_shader_parameter("use_base_color_2", texture_2 == null)
	grass_mat.set_shader_parameter("use_base_color_3", texture_3 == null)
	grass_mat.set_shader_parameter("use_base_color_4", texture_4 == null)
	grass_mat.set_shader_parameter("use_base_color_5", texture_5 == null)
	grass_mat.set_shader_parameter("use_base_color_6", texture_6 == null)
	
	# GRASS MATERIAL - Has Grass Flags 
	grass_mat.set_shader_parameter("use_grass_tex_2", tex2_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_3", tex3_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_4", tex4_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_5", tex5_has_grass)
	grass_mat.set_shader_parameter("use_grass_tex_6", tex6_has_grass)
	
	for chunk: MarchingSquaresTerrainChunk in chunks.values():
		chunk.grass_planter.regenerate_all_cells()


# Syncs and saves current UI texture values to the given preset resource
# Called by marching_squares_ui.gd when saving monitoring settings changes
func save_to_preset() -> void:
	if current_texture_preset == null:
		# Don't print an error here as not having a preset just means the user is making a new one
		return
	
	# Terrain textures
	current_texture_preset.new_textures.terrain_textures[0] = ground_texture
	current_texture_preset.new_textures.terrain_textures[1] = texture_2
	current_texture_preset.new_textures.terrain_textures[2] = texture_3
	current_texture_preset.new_textures.terrain_textures[3] = texture_4
	current_texture_preset.new_textures.terrain_textures[4] = texture_5
	current_texture_preset.new_textures.terrain_textures[5] = texture_6
	current_texture_preset.new_textures.terrain_textures[6] = texture_7
	current_texture_preset.new_textures.terrain_textures[7] = texture_8
	current_texture_preset.new_textures.terrain_textures[8] = texture_9
	current_texture_preset.new_textures.terrain_textures[9] = texture_10
	current_texture_preset.new_textures.terrain_textures[10] = texture_11
	current_texture_preset.new_textures.terrain_textures[11] = texture_12
	current_texture_preset.new_textures.terrain_textures[12] = texture_13
	current_texture_preset.new_textures.terrain_textures[13] = texture_14
	current_texture_preset.new_textures.terrain_textures[14] = texture_15
	
	# Grass sprites
	current_texture_preset.new_textures.grass_sprites[0] = grass_sprite
	current_texture_preset.new_textures.grass_sprites[1] = grass_sprite_tex_2
	current_texture_preset.new_textures.grass_sprites[2] = grass_sprite_tex_3
	current_texture_preset.new_textures.grass_sprites[3] = grass_sprite_tex_4
	current_texture_preset.new_textures.grass_sprites[4] = grass_sprite_tex_5
	current_texture_preset.new_textures.grass_sprites[5] = grass_sprite_tex_6
	
	# Grass colors
	current_texture_preset.new_textures.grass_colors[0] = ground_color
	current_texture_preset.new_textures.grass_colors[1] = ground_color_2
	current_texture_preset.new_textures.grass_colors[2] = ground_color_3
	current_texture_preset.new_textures.grass_colors[3] = ground_color_4
	current_texture_preset.new_textures.grass_colors[4] = ground_color_5
	current_texture_preset.new_textures.grass_colors[5] = ground_color_6
	
	# Has grass flags
	current_texture_preset.new_textures.has_grass[0] = tex2_has_grass
	current_texture_preset.new_textures.has_grass[1] = tex3_has_grass
	current_texture_preset.new_textures.has_grass[2] = tex4_has_grass
	current_texture_preset.new_textures.has_grass[3] = tex5_has_grass
	current_texture_preset.new_textures.has_grass[4] = tex6_has_grass


## Handle editor notifications for external data storage
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		if Engine.is_editor_hint():
			_save_all_chunks_externally()


## Generate a unique terrain ID (called once on first save)
func _generate_terrain_uid() -> void:
	# Generate a short, readable UID combining random + timestamp
	# Format: 8 hex chars (e.g., "a1b2c3d4")
	_terrain_uid = "%08x" % (randi() ^ int(Time.get_unix_time_from_system()))


## Get the resolved data directory path, creating it if needed
## Path format: [SceneDir]/[SceneName]_TerrainData/[NodeName]_[UID]/
func get_data_directory() -> String:
	var dir_path := data_directory

	# If empty, generate default path based on scene location with unique UID
	if dir_path.is_empty():
		var scene_root := get_tree().edited_scene_root if Engine.is_editor_hint() else get_tree().current_scene
		if not scene_root or scene_root.scene_file_path.is_empty():
			return ""

		# Generate UID if not set (first save)
		if _terrain_uid.is_empty():
			_generate_terrain_uid()

		var scene_path := scene_root.scene_file_path
		var scene_dir := scene_path.get_base_dir()
		var scene_name := scene_path.get_file().get_basename()
		# Include UID in path to prevent collisions when nodes are recreated with same name
		dir_path = scene_dir.path_join(scene_name + "_TerrainData").path_join(name + "_" + _terrain_uid) + "/"

	# Ensure path ends with /
	if not dir_path.is_empty() and not dir_path.ends_with("/"):
		dir_path += "/"

	return dir_path


## Save all dirty chunks to external .res files
## This saves individual resources and sets their resource_path to prevent scene embedding
func _save_all_chunks_externally() -> void:
	var dir_path := get_data_directory()
	if dir_path.is_empty():
		# No valid data directory - scene might not be saved yet
		return

	# Ensure directory exists
	if not FileUtils.ensure_directory_exists(dir_path):
		printerr("MarchingSquaresTerrain: Failed to create data directory: ", dir_path)
		return

	var saved_count := 0
	for chunk_coords in chunks:
		var chunk : MarchingSquaresTerrainChunk = chunks[chunk_coords]

		# Skip chunks being removed during undo/redo
		if chunk._skip_save_on_exit:
			continue

		# Determine if chunk needs saving:
		# 1. Chunk is marked dirty (terrain was edited)
		# 2. External files don't exist yet
		# 3. Any resource exists but lost its resource_path (regenerated)
		var needs_save := chunk._data_dirty
		if not needs_save and not _chunk_resources_exist(chunk_coords):
			needs_save = true
		# Check if mesh lost its external path (regenerated during terrain edit)
		if not needs_save and chunk.mesh and chunk.mesh.resource_path.is_empty():
			needs_save = true
		# Check if collision shape lost its external path
		if not needs_save:
			var collision_shape := chunk._get_collision_shape()
			if collision_shape and collision_shape.resource_path.is_empty():
				needs_save = true
		# Check if grass multimesh lost its external path
		if not needs_save and chunk.grass_planter and chunk.grass_planter.multimesh:
			if chunk.grass_planter.multimesh.resource_path.is_empty():
				needs_save = true

		if needs_save:
			_save_chunk_resources(chunk)
			chunk._data_dirty = false
			saved_count += 1

	if saved_count > 0:
		print_verbose("MarchingSquaresTerrain: Saved ", saved_count, " chunk(s) to ", dir_path)

	# Clean up orphaned chunk directories that no longer exist in scene
	_cleanup_orphaned_chunk_files()

	_storage_initialized = true


## Check if all resource files exist for a chunk
func _chunk_resources_exist(coords: Vector2i) -> bool:
	var dir_path := get_data_directory()
	var chunk_dir := dir_path + "chunk_%d_%d/" % [coords.x, coords.y]
	# At minimum, mesh.res should exist for a valid saved chunk
	return FileAccess.file_exists(chunk_dir + "mesh.res")


## Save a chunk's heavy resources (mesh, collision, multimesh) to external files
## This sets resource_path on each resource to prevent scene embedding
func _save_chunk_resources(chunk: MarchingSquaresTerrainChunk) -> void:
	var dir_path := get_data_directory()
	if dir_path.is_empty():
		printerr("MarchingSquaresTerrain: Cannot save chunk - no valid data directory")
		return

	var chunk_dir := dir_path + "chunk_%d_%d/" % [chunk.chunk_coords.x, chunk.chunk_coords.y]
	FileUtils.ensure_directory_exists(chunk_dir)

	# 1. Save mesh and SET resource_path (prevents scene embedding)
	if chunk.mesh:
		var mesh_path := chunk_dir + "mesh.res"
		var err := ResourceSaver.save(chunk.mesh, mesh_path, ResourceSaver.FLAG_COMPRESS)
		if err == OK:
			# Setting resource_path tells Godot to use ext_resource instead of embedding
			chunk.mesh.resource_path = mesh_path
		else:
			printerr("MarchingSquaresTerrain: Failed to save mesh to ", mesh_path)

	# 2. Save collision shape and SET its resource_path
	var collision_shape : ConcavePolygonShape3D = chunk._get_collision_shape()
	if collision_shape:
		var collision_path := chunk_dir + "collision.res"
		var err := ResourceSaver.save(collision_shape, collision_path, ResourceSaver.FLAG_COMPRESS)
		if err == OK:
			collision_shape.resource_path = collision_path
		else:
			printerr("MarchingSquaresTerrain: Failed to save collision to ", collision_path)

	# 3. Save grass multimesh and SET its resource_path
	if chunk.grass_planter and chunk.grass_planter.multimesh:
		var grass_path := chunk_dir + "grass_multimesh.res"
		var err := ResourceSaver.save(chunk.grass_planter.multimesh, grass_path, ResourceSaver.FLAG_COMPRESS)
		if err == OK:
			chunk.grass_planter.multimesh.resource_path = grass_path
		else:
			printerr("MarchingSquaresTerrain: Failed to save grass multimesh to ", grass_path)

	# 4. Save chunk metadata (height_map, color_maps, etc.) - these stay bundled
	var data : ChunkData = chunk.to_chunk_data()
	# Don't duplicate the heavy resources in metadata - they're saved separately
	data.mesh = null
	data.grass_multimesh = null
	data.collision_faces = PackedVector3Array()
	var metadata_path := chunk_dir + "metadata.res"
	var err := ResourceSaver.save(data, metadata_path, ResourceSaver.FLAG_COMPRESS)
	if err != OK:
		printerr("MarchingSquaresTerrain: Failed to save metadata to ", metadata_path)
	else:
		print_verbose("MarchingSquaresTerrain: Saved chunk ", chunk.chunk_coords, " to ", chunk_dir)


## Legacy function for backward compatibility - redirects to new resource-based save
func save_chunk_data(chunk: MarchingSquaresTerrainChunk) -> void:
	_save_chunk_resources(chunk)


## Clean up orphaned chunk directories that no longer exist in the scene
## Called automatically during save to prevent disk space accumulation
func _cleanup_orphaned_chunk_files() -> void:
	var dir_path := get_data_directory()
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
				if not chunks.has(coords):
					orphaned_dirs.append(dir_path + folder_name + "/")
		folder_name = dir.get_next()
	dir.list_dir_end()

	# Delete orphaned directories
	for orphaned_dir in orphaned_dirs:
		_delete_chunk_directory(orphaned_dir)
		print_verbose("MarchingSquaresTerrain: Cleaned up orphaned chunk at ", orphaned_dir)


## Delete a chunk directory and all its contents
func _delete_chunk_directory(chunk_dir: String) -> void:
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
				printerr("MarchingSquaresTerrain: Failed to delete file ", file_name, " in ", chunk_dir)
		file_name = dir.get_next()
	dir.list_dir_end()

	# Remove the directory itself
	var err := DirAccess.remove_absolute(chunk_dir.trim_suffix("/"))
	if err != OK:
		printerr("MarchingSquaresTerrain: Failed to delete directory ", chunk_dir)


## Load a single chunk's metadata from external .res file
func load_chunk_data(coords: Vector2i) -> ChunkData:
	var dir_path := get_data_directory()
	if dir_path.is_empty():
		return null

	var chunk_dir := dir_path + "chunk_%d_%d/" % [coords.x, coords.y]
	var metadata_path := chunk_dir + "metadata.res"

	if not FileAccess.file_exists(metadata_path):
		# Try legacy format for backward compatibility
		var legacy_path := FileUtils.get_chunk_file_path(dir_path, coords)
		if FileAccess.file_exists(legacy_path):
			var data = load(legacy_path)
			if data is ChunkData:
				return data
		return null

	var data = load(metadata_path)
	if data is ChunkData:
		return data
	else:
		printerr("MarchingSquaresTerrain: Invalid chunk data at ", metadata_path)
		return null


## Load all terrain data from external files
func _load_terrain_data() -> void:
	var dir_path := get_data_directory()
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
		var chunk_files := FileUtils.get_chunk_files_in_directory(dir_path)
		if not chunk_files.is_empty():
			print_verbose("MarchingSquaresTerrain: Loading ", chunk_files.size(), " chunk(s) from legacy format")
			for coords in chunk_files:
				_load_chunk_legacy(coords)
			_storage_initialized = true
		return

	print_verbose("MarchingSquaresTerrain: Loading ", chunk_dirs.size(), " chunk(s) from ", dir_path)

	for coords in chunk_dirs:
		_load_chunk_from_directory(coords)

	_storage_initialized = true


## Load a single chunk from its resource directory (new format)
func _load_chunk_from_directory(coords: Vector2i) -> void:
	var dir_path := get_data_directory()
	var chunk_dir := dir_path + "chunk_%d_%d/" % [coords.x, coords.y]

	# Get or create chunk
	var chunk : MarchingSquaresTerrainChunk = chunks.get(coords)
	if not chunk:
		# Chunk should already exist in scene - external storage doesn't create new chunks
		# This case handles when scene was saved without chunks (shouldn't happen normally)
		return

	# Load metadata first (height_map, color_maps, etc.)
	var metadata_path := chunk_dir + "metadata.res"
	if ResourceLoader.exists(metadata_path):
		var data : ChunkData = load(metadata_path)
		if data:
			chunk.from_chunk_data(data)

	# Load mesh (resource already has resource_path from file)
	var mesh_path := chunk_dir + "mesh.res"
	if ResourceLoader.exists(mesh_path):
		chunk.mesh = load(mesh_path)
		if chunk.mesh and terrain_material:
			chunk.mesh.surface_set_material(0, terrain_material)

	# Load collision
	var collision_path := chunk_dir + "collision.res"
	if ResourceLoader.exists(collision_path):
		var shape = load(collision_path)
		if shape is ConcavePolygonShape3D:
			chunk._apply_collision_shape(shape)

	# Load grass multimesh
	var grass_path := chunk_dir + "grass_multimesh.res"
	if ResourceLoader.exists(grass_path) and chunk.grass_planter:
		chunk.grass_planter.multimesh = load(grass_path)

	print_verbose("MarchingSquaresTerrain: Loaded chunk ", coords, " from ", chunk_dir)


## Load a single chunk from legacy single-file format
func _load_chunk_legacy(coords: Vector2i) -> void:
	var data : ChunkData = load_chunk_data(coords)
	if not data:
		return

	var chunk : MarchingSquaresTerrainChunk = chunks.get(coords)
	if chunk:
		chunk.from_chunk_data(data)


## Check if this terrain needs migration from embedded to external storage
func _needs_migration() -> bool:
	# If already initialized with external storage, no migration needed
	if _storage_initialized:
		return false

	# Check if any chunks have embedded data but no external files exist
	var dir_path := get_data_directory()
	if dir_path.is_empty():
		return false

	for chunk_coords in chunks:
		var chunk : MarchingSquaresTerrainChunk = chunks[chunk_coords]
		# If chunk has height_map data but no external resources, migration is needed
		if chunk.height_map and not chunk.height_map.is_empty():
			if not _chunk_resources_exist(chunk_coords):
				return true

	return false


## Migrate existing embedded data to external storage
func _migrate_to_external_storage() -> void:
	print("MarchingSquaresTerrain: Migrating to external storage...")

	# Mark all chunks as dirty to force save
	for chunk_coords in chunks:
		var chunk : MarchingSquaresTerrainChunk = chunks[chunk_coords]
		chunk._data_dirty = true

	# Save all chunks externally
	_save_all_chunks_externally()

	print("MarchingSquaresTerrain: Migration complete. External data saved to: ", get_data_directory())
