--!strict
--!native
--[[
The shape of tes3conv's JSON: for every record type, its fields in the order tes3conv writes
them, and which of their numbers are floats.

A record table has no order of its own and no way to tell the float 3 from the integer 3, and
tes3conv's text has both: its fields come out in the order its Rust structs declare them, and an
`f32` is always written with a fraction or an exponent (`3.0`) where an integer never is. That is
all this file holds. Everything else about a value is in the value: text is text, flags and enums
are already their names, a byte blob is already its base64, and a list of plain values (a grid, a
color, a master and its size) is written as it stands.

Fields are named as the JSON spells them (`speaker_id`); `key` is the same name as record tables
spell it (`speakerId`). A field a record doesn't have is left out, as tes3conv leaves out an
`Option` that is `None`.

A `blob` is text like any other, marked because it is long and never needs escaping: the base64
tes3conv writes for bytes it doesn't take apart (a script's bytecode, a landscape's heights).
]]

export type Field = { name: string, key: string, node: Node }

--- `plain`: text, a boolean, an integer, or lists of them. `float`: an f32. `blob`: base64.
--- `struct`: fields in order. `list`: items of one shape. `tagged`: a table whose `type` names
--- which fields it has.
export type Node = {
  kind: 'plain' | 'float' | 'blob' | 'struct' | 'list' | 'tagged',
  fields: { Field }?,
  item: Node?,
  variants: { [string]: Node }?,
}

local Plain: Node = table.freeze { kind = 'plain' :: 'plain' }
local Float: Node = table.freeze { kind = 'float' :: 'float' }
local Blob: Node = table.freeze { kind = 'blob' :: 'blob' }

--- omwaddon::symbol::camel_case, as `@tes3conv` reads keys: `_` before a lowercase letter becomes
--- that letter uppercased, except at the start.
local function camel(name: string): string
  return string.sub(name, 1, 1) .. string.gsub(string.sub(name, 2), '_(%l)', string.upper)
end

local function field(name: string, node: Node): Field
  return table.freeze { name = name, key = camel(name), node = node }
end

local function list(item: Node): Node return table.freeze { kind = 'list' :: 'list', item = item } end

local Floats = list(Float)

local function float(name: string): Field return field(name, Float) end

local function floats(name: string): Field return field(name, Floats) end

local function blob(name: string): Field return field(name, Blob) end

--- A struct of the fields given, in order: a name alone is a plain field.
local function struct(members: { string | Field }): Node
  local fields: { Field } =
    [for member in members => if type(member) == 'string' then field(member, Plain) else member]

  return table.freeze { kind = 'struct' :: 'struct', fields = table.freeze(fields) }
end

local function tagged(variants: { [string]: Node }): Node
  return table.freeze { kind = 'tagged' :: 'tagged', variants = table.freeze(variants) }
end

--- A number or a string under `data`, as tes3conv tags a value that can be either.
local Whole = struct { 'data' }
local Fraction = struct { float 'data' }

local Effects = list(struct {
  'magic_effect',
  'skill',
  'attribute',
  'range',
  'area',
  'duration',
  'min_magnitude',
  'max_magnitude',
})

local TravelDestination = struct { floats 'translation', floats 'rotation', 'cell' }
local AiData = struct { 'hello', 'fight', 'flee', 'alarm', 'services' }

local AiPackages = list(tagged {
  Travel = struct { floats 'location', 'reset' },
  Wander = struct {
    'distance',
    'duration',
    'game_hour',
    'idle2',
    'idle3',
    'idle4',
    'idle5',
    'idle6',
    'idle7',
    'idle8',
    'idle9',
    'reset',
  },
  Escort = struct { floats 'location', 'duration', 'target', 'reset', 'cell' },
  Follow = struct { floats 'location', 'duration', 'target', 'reset', 'cell' },
  Activate = struct { 'target', 'reset' },
})

local BipedObjects = list(struct { 'biped_object_type', 'male_bodypart', 'female_bodypart' })

local Reference = struct {
  'mast_index',
  'refr_index',
  'id',
  'temporary',
  floats 'translation',
  floats 'rotation',
  float 'scale',
  'moved_cell',
  'owner',
  'owner_global',
  'owner_faction',
  'owner_faction_rank',
  'charge_left',
  'health_left',
  'object_count',
  field('destination', TravelDestination),
  'lock_level',
  'key',
  'trap',
  'soul',
  'blocked',
  'deleted',
}

--- A tool's item: its weight, value, quality, and uses, in the order its type has them.
local function tool(members: { string | Field }): Node
  return struct { 'flags', 'id', 'name', 'script', 'mesh', 'icon', field('data', struct(members)) }
end

local Records: { [string]: Node } = {
  Header = struct {
    'flags',
    float 'version',
    'file_type',
    'author',
    'description',
    'num_objects',
    'masters',
  },
  GameSetting = struct {
    'flags',
    'id',
    field('value', tagged { Float = Fraction, Integer = Whole, String = Whole }),
  },
  GlobalVariable = struct {
    'flags',
    'id',
    field('value', tagged { Float = Fraction, Long = Whole, Short = Whole }),
  },
  Class = struct {
    'flags',
    'id',
    'name',
    'description',
    field(
      'data',
      struct {
        'attribute1',
        'attribute2',
        'specialization',
        'minor1',
        'major1',
        'minor2',
        'major2',
        'minor3',
        'major3',
        'minor4',
        'major4',
        'minor5',
        'major5',
        'flags',
        'services',
      }
    ),
  },
  Faction = struct {
    'flags',
    'id',
    'name',
    'rank_names',
    field('reactions', list(struct { 'faction', 'reaction' })),
    field(
      'data',
      struct {
        'favored_attributes',
        field(
          'requirements',
          list(struct { 'attributes', 'primary_skill', 'favored_skill', 'reputation' })
        ),
        'favored_skills',
        'flags',
      }
    ),
  },
  Race = struct {
    'flags',
    'id',
    'name',
    'spells',
    'description',
    field(
      'data',
      struct {
        field(
          'skill_bonuses',
          struct {
            'skill_0',
            'bonus_0',
            'skill_1',
            'bonus_1',
            'skill_2',
            'bonus_2',
            'skill_3',
            'bonus_3',
            'skill_4',
            'bonus_4',
            'skill_5',
            'bonus_5',
            'skill_6',
            'bonus_6',
          }
        ),
        'strength',
        'intelligence',
        'willpower',
        'agility',
        'speed',
        'endurance',
        'personality',
        'luck',
        floats 'height',
        floats 'weight',
        'flags',
      }
    ),
  },
  Sound = struct { 'flags', 'id', 'sound_path', field('data', struct { 'volume', 'range' }) },
  Skill = struct {
    'flags',
    'skill_id',
    field('data', struct { 'governing_attribute', 'specialization', floats 'actions' }),
    'description',
  },
  MagicEffect = struct {
    'flags',
    'effect_id',
    'icon',
    'texture',
    'bolt_sound',
    'cast_sound',
    'hit_sound',
    'area_sound',
    'cast_visual',
    'bolt_visual',
    'hit_visual',
    'area_visual',
    'description',
    field(
      'data',
      struct {
        'school',
        float 'base_cost',
        'flags',
        'color',
        float 'speed',
        float 'size',
        float 'size_cap',
      }
    ),
  },
  Script = struct {
    'flags',
    'id',
    field(
      'header',
      struct { 'num_shorts', 'num_longs', 'num_floats', 'bytecode_length', 'variables_length' }
    ),
    blob 'variables',
    blob 'bytecode',
    'text',
  },
  Region = struct {
    'flags',
    'id',
    'name',
    field(
      'weather_chances',
      struct {
        'clear',
        'cloudy',
        'foggy',
        'overcast',
        'rain',
        'thunder',
        'ash',
        'blight',
        'snow',
        'blizzard',
      }
    ),
    'sleep_creature',
    'map_color',
    'sounds',
  },
  Birthsign = struct { 'flags', 'id', 'name', 'texture', 'description', 'spells' },
  StartScript = struct { 'flags', 'id', 'script' },
  LandscapeTexture = struct { 'flags', 'id', 'index', 'file_name' },
  Spell = struct {
    'flags',
    'id',
    'name',
    field('effects', Effects),
    field('data', struct { 'spell_type', 'cost', 'flags' }),
  },
  Static = struct { 'flags', 'id', 'mesh' },
  Door = struct { 'flags', 'id', 'name', 'script', 'mesh', 'open_sound', 'close_sound' },
  MiscItem = tool { float 'weight', 'value', 'flags' },
  Weapon = struct {
    'flags',
    'id',
    'name',
    'script',
    'mesh',
    'icon',
    'enchanting',
    field(
      'data',
      struct {
        float 'weight',
        'value',
        'weapon_type',
        'health',
        float 'speed',
        float 'reach',
        'enchantment',
        'chop_min',
        'chop_max',
        'slash_min',
        'slash_max',
        'thrust_min',
        'thrust_max',
        'flags',
      }
    ),
  },
  Container = struct {
    'flags',
    'id',
    'name',
    'script',
    'mesh',
    float 'encumbrance',
    'container_flags',
    'inventory',
  },
  Creature = struct {
    'flags',
    'id',
    'name',
    'script',
    'mesh',
    'inventory',
    'spells',
    field('ai_data', AiData),
    field('ai_packages', AiPackages),
    field('travel_destinations', list(TravelDestination)),
    'sound',
    float 'scale',
    'creature_flags',
    'blood_type',
    field(
      'data',
      struct {
        'creature_type',
        'level',
        'strength',
        'intelligence',
        'willpower',
        'agility',
        'speed',
        'endurance',
        'personality',
        'luck',
        'health',
        'magicka',
        'fatigue',
        'soul',
        'combat',
        'magic',
        'stealth',
        'attack1',
        'attack2',
        'attack3',
        'gold',
      }
    ),
  },
  Bodypart = struct {
    'flags',
    'id',
    'race',
    'mesh',
    field('data', struct { 'part', 'vampire', 'flags', 'bodypart_type' }),
  },
  Light = struct {
    'flags',
    'id',
    'name',
    'script',
    'mesh',
    'icon',
    'sound',
    field('data', struct { float 'weight', 'value', 'time', 'radius', 'color', 'flags' }),
  },
  Enchanting = struct {
    'flags',
    'id',
    field('effects', Effects),
    field('data', struct { 'enchant_type', 'cost', 'max_charge', 'flags' }),
  },
  Npc = struct {
    'flags',
    'id',
    'name',
    'script',
    'mesh',
    'inventory',
    'spells',
    field('ai_data', AiData),
    field('ai_packages', AiPackages),
    field('travel_destinations', list(TravelDestination)),
    'race',
    'class',
    'faction',
    'head',
    'hair',
    'npc_flags',
    'blood_type',
    field(
      'data',
      struct {
        'level',
        field('stats', struct { 'attributes', 'skills', 'health', 'magicka', 'fatigue' }),
        'disposition',
        'reputation',
        'rank',
        'gold',
      }
    ),
  },
  Armor = struct {
    'flags',
    'id',
    'name',
    'script',
    'mesh',
    'icon',
    'enchanting',
    field('biped_objects', BipedObjects),
    field(
      'data',
      struct { 'armor_type', float 'weight', 'value', 'health', 'enchantment', 'armor_rating' }
    ),
  },
  Clothing = struct {
    'flags',
    'id',
    'name',
    'script',
    'mesh',
    'icon',
    'enchanting',
    field('biped_objects', BipedObjects),
    field('data', struct { 'clothing_type', float 'weight', 'value', 'enchantment' }),
  },
  RepairItem = tool { float 'weight', 'value', 'uses', float 'quality' },
  Activator = struct { 'flags', 'id', 'name', 'script', 'mesh' },
  Apparatus = tool { 'apparatus_type', float 'quality', float 'weight', 'value' },
  Lockpick = tool { float 'weight', 'value', float 'quality', 'uses' },
  Probe = tool { float 'weight', 'value', float 'quality', 'uses' },
  Ingredient = tool { float 'weight', 'value', 'effects', 'skills', 'attributes' },
  Book = struct {
    'flags',
    'id',
    'name',
    'script',
    'mesh',
    'icon',
    'enchanting',
    'text',
    field('data', struct { float 'weight', 'value', 'book_type', 'skill', 'enchantment' }),
  },
  Alchemy = struct {
    'flags',
    'id',
    'name',
    'script',
    'mesh',
    'icon',
    field('effects', Effects),
    field('data', struct { float 'weight', 'value', 'flags' }),
  },
  LeveledItem = struct { 'flags', 'id', 'leveled_item_flags', 'chance_none', 'items' },
  LeveledCreature = struct { 'flags', 'id', 'leveled_creature_flags', 'chance_none', 'creatures' },
  Cell = struct {
    'flags',
    'name',
    field('data', struct { 'flags', 'grid' }),
    'region',
    'map_color',
    float 'water_height',
    field(
      'atmosphere_data',
      struct { 'ambient_color', 'sunlight_color', 'fog_color', float 'fog_density' }
    ),
    field('references', list(Reference)),
  },
  Landscape = struct {
    'flags',
    'grid',
    'landscape_flags',
    field('vertex_normals', struct { blob 'data' }),
    field('vertex_heights', struct { float 'offset', blob 'data' }),
    field('world_map_data', struct { blob 'data' }),
    field('vertex_colors', struct { blob 'data' }),
    field('texture_indices', struct { blob 'data' }),
  },
  PathGrid = struct {
    'flags',
    'cell',
    field('data', struct { 'grid', 'granularity', 'point_count' }),
    field('points', list(struct { 'location', 'auto_generated', 'connection_count' })),
    blob 'connections',
  },
  SoundGen = struct { 'flags', 'id', 'sound_gen_type', 'creature', 'sound' },
  Dialogue = struct { 'flags', 'id', 'dialogue_type' },
  DialogueInfo = struct {
    'flags',
    'id',
    'prev_id',
    'next_id',
    field(
      'data',
      struct { 'dialogue_type', 'disposition', 'speaker_rank', 'speaker_sex', 'player_rank' }
    ),
    'speaker_id',
    'speaker_race',
    'speaker_class',
    'speaker_faction',
    'speaker_cell',
    'player_faction',
    'sound_path',
    'text',
    'quest_state',
    field(
      'filters',
      list(struct {
        'index',
        'filter_type',
        'function',
        'comparison',
        'id',
        field('value', tagged { Float = Fraction, Integer = Whole }),
      })
    ),
    'script_text',
  },
  -- OpenMW's script list, which the tes3conv this package follows was built to read too. Its
  -- flags come last.
  ScriptConfigList = struct {
    field(
      'scripts',
      list(struct {
        'path',
        blob 'init_data',
        'flags',
        'types',
        field('records', list(struct { 'attach', 'id', blob 'data' })),
        field('instances', list(struct { 'attach', 'mast_idx', 'ref_idx', blob 'data' })),
      })
    ),
    'flags',
  },
}

return table.freeze { Records = table.freeze(Records), camel = camel }
