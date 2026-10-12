--!strict
--!native
-- TES3 record tables as tes3conv spells them, with jess's camelCase field names: the record
-- semantics the Morrowind tools ported from Rust share. Exported as `@tes3conv/records`.

local data = require '@dream/data'

export type Key = string | number
export type Value = boolean | number | string | JessNull | Table
export type Table = { [Key]: Value }
export type Record = Table
export type Records = { Record }

local Tags: { [string]: string } = {
  Header = 'TES3',
  GameSetting = 'GMST',
  GlobalVariable = 'GLOB',
  Class = 'CLAS',
  Faction = 'FACT',
  Race = 'RACE',
  Sound = 'SOUN',
  SoundGen = 'SNDG',
  Skill = 'SKIL',
  MagicEffect = 'MGEF',
  Script = 'SCPT',
  Region = 'REGN',
  Birthsign = 'BSGN',
  StartScript = 'SSCR',
  LandscapeTexture = 'LTEX',
  Spell = 'SPEL',
  Static = 'STAT',
  Door = 'DOOR',
  MiscItem = 'MISC',
  Weapon = 'WEAP',
  Container = 'CONT',
  Creature = 'CREA',
  Bodypart = 'BODY',
  Light = 'LIGH',
  Enchanting = 'ENCH',
  Npc = 'NPC_',
  Armor = 'ARMO',
  Clothing = 'CLOT',
  RepairItem = 'REPA',
  Activator = 'ACTI',
  Apparatus = 'APPA',
  Lockpick = 'LOCK',
  Probe = 'PROB',
  Ingredient = 'INGR',
  Book = 'BOOK',
  Alchemy = 'ALCH',
  LeveledItem = 'LEVI',
  LeveledCreature = 'LEVC',
  Cell = 'CELL',
  Landscape = 'LAND',
  PathGrid = 'PGRD',
  Dialogue = 'DIAL',
  DialogueInfo = 'INFO',
}

local TypeNames: { [string]: string } = {}

for name, tag in Tags do
  TypeNames[tag] = name
end

-- tes3's `sort_objects` order. CELL, LAND, and PGRD share a slot, as do DIAL and INFO.
local SortOrder: { [string]: number } = {
  Header = 0,
  GameSetting = 1,
  GlobalVariable = 2,
  Class = 3,
  Faction = 4,
  Race = 5,
  Sound = 6,
  Skill = 7,
  MagicEffect = 8,
  Script = 9,
  Region = 10,
  Birthsign = 11,
  StartScript = 12,
  LandscapeTexture = 13,
  Spell = 14,
  Static = 15,
  Door = 16,
  MiscItem = 17,
  Weapon = 18,
  Container = 19,
  Creature = 20,
  Bodypart = 21,
  Light = 22,
  Enchanting = 23,
  Npc = 24,
  Armor = 25,
  Clothing = 26,
  RepairItem = 27,
  Activator = 28,
  Apparatus = 29,
  Lockpick = 30,
  Probe = 31,
  Ingredient = 32,
  Book = 33,
  Alchemy = 34,
  LeveledItem = 35,
  LeveledCreature = 36,
  Cell = 37,
  Landscape = 37,
  PathGrid = 37,
  SoundGen = 38,
  Dialogue = 39,
  DialogueInfo = 39,
}

local EffectNames = {
  'WaterBreathing',
  'SwiftSwim',
  'WaterWalking',
  'Shield',
  'FireShield',
  'LightningShield',
  'FrostShield',
  'Burden',
  'Feather',
  'Jump',
  'Levitate',
  'SlowFall',
  'Lock',
  'Open',
  'FireDamage',
  'ShockDamage',
  'FrostDamage',
  'DrainAttribute',
  'DrainHealth',
  'DrainMagicka',
  'DrainFatigue',
  'DrainSkill',
  'DamageAttribute',
  'DamageHealth',
  'DamageMagicka',
  'DamageFatigue',
  'DamageSkill',
  'Poison',
  'WeaknessToFire',
  'WeaknessToFrost',
  'WeaknessToShock',
  'WeaknessToMagicka',
  'WeaknessToCommonDisease',
  'WeaknessToBlightDisease',
  'WeaknessToCorprus',
  'WeaknessToPoison',
  'WeaknessToNormalWeapons',
  'DisintegrateWeapon',
  'DisintegrateArmor',
  'Invisibility',
  'Chameleon',
  'Light',
  'Sanctuary',
  'NightEye',
  'Charm',
  'Paralyze',
  'Silence',
  'Blind',
  'Sound',
  'CalmHumanoid',
  'CalmCreature',
  'FrenzyHumanoid',
  'FrenzyCreature',
  'DemoralizeHumanoid',
  'DemoralizeCreature',
  'RallyHumanoid',
  'RallyCreature',
  'Dispel',
  'SoulTrap',
  'Telekinesis',
  'Mark',
  'Recall',
  'DivineIntervention',
  'AlmsiviIntervention',
  'DetectAnimal',
  'DetectEnchantment',
  'DetectKey',
  'SpellAbsorption',
  'Reflect',
  'CureCommonDisease',
  'CureBlightDisease',
  'CureCorprus',
  'CurePoison',
  'CureParalyzation',
  'RestoreAttribute',
  'RestoreHealth',
  'RestoreMagicka',
  'RestoreFatigue',
  'RestoreSkill',
  'FortifyAttribute',
  'FortifyHealth',
  'FortifyMagicka',
  'FortifyFatigue',
  'FortifySkill',
  'FortifyMagickaMultiplier',
  'AbsorbAttribute',
  'AbsorbHealth',
  'AbsorbMagicka',
  'AbsorbFatigue',
  'AbsorbSkill',
  'ResistFire',
  'ResistFrost',
  'ResistShock',
  'ResistMagicka',
  'ResistCommonDisease',
  'ResistBlightDisease',
  'ResistCorprus',
  'ResistPoison',
  'ResistNormalWeapons',
  'ResistParalysis',
  'RemoveCurse',
  'TurnUndead',
  'SummonScamp',
  'SummonClannfear',
  'SummonDaedroth',
  'SummonDremora',
  'SummonGhost',
  'SummonSkeleton',
  'SummonLeastBonewalker',
  'SummonGreaterBonewalker',
  'SummonBonelord',
  'SummonTwilight',
  'SummonHunger',
  'SummonGoldenSaint',
  'SummonFlameAtronach',
  'SummonFrostAtronach',
  'SummonStormAtronach',
  'FortifyAttackBonus',
  'CommandCreature',
  'CommandHumanoid',
  'BoundDagger',
  'BoundLongsword',
  'BoundMace',
  'BoundBattleAxe',
  'BoundSpear',
  'BoundLongbow',
  'ExtraSpell',
  'BoundCuirass',
  'BoundHelm',
  'BoundBoots',
  'BoundShield',
  'BoundGloves',
  'Corprus',
  'Vampirism',
  'SummonCenturionSphere',
  'SunDamage',
  'StuntedMagicka',
  'SummonFabricant',
  'SummonWolf',
  'SummonBear',
  'SummonBoneWolf',
  'Summon04',
  'Summon05',
}

local SkillNames = {
  'Block',
  'Armorer',
  'MediumArmor',
  'HeavyArmor',
  'BluntWeapon',
  'LongBlade',
  'Axe',
  'Spear',
  'Athletics',
  'Enchant',
  'Destruction',
  'Alteration',
  'Illusion',
  'Conjuration',
  'Mysticism',
  'Restoration',
  'Alchemy',
  'Unarmored',
  'Security',
  'Sneak',
  'Acrobatics',
  'LightArmor',
  'ShortBlade',
  'Marksman',
  'Mercantile',
  'Speechcraft',
  'HandToHand',
}

local EffectIndex: { [string]: number } = { None = -1 }
local SkillIndex: { [string]: number } = { None = -1 }

for index, name in EffectNames do
  EffectIndex[name] = index - 1
end

for index, name in SkillNames do
  SkillIndex[name] = index - 1
end

local tes3 = {
  Tags = Tags,
  TypeNames = TypeNames,
  SortOrder = SortOrder,
  EffectIndex = EffectIndex,
  SkillIndex = SkillIndex,
}

function tes3.string(value: Value?): string
  if type(value) == 'string' then return value end

  return ''
end

function tes3.lower(value: Value?): string return string.lower(tes3.string(value)) end

-- Whether a flags string ("PERSISTENT | DELETED") names a flag.
function tes3.hasFlag(flags: Value?, flag: string): boolean
  return type(flags) == 'string' and string.find(flags, flag, 1, true) ~= nil
end

function tes3.isDeleted(record: Record): boolean return tes3.hasFlag(record.flags, 'DELETED') end

function tes3.isInterior(cell: Record): boolean
  local data = cell.data :: Table?
  return data ~= nil and tes3.hasFlag(data.flags, 'IS_INTERIOR')
end

local function grid(name: string, value: Value?): string
  local pair = (value or {}) :: Table
  return `{name} ({math.floor(tonumber(pair[1]) or 0)}, {math.floor(tonumber(pair[2]) or 0)})`
end

-- tes3's `EditorId`: the id a record is keyed by. Interior cells are their names, exterior cells
-- their name (or region, or "Wilderness") and grid, path grids their cell and grid.
function tes3.editorId(record: Record): string
  local kind = record.type

  if kind == 'Header' then
    return ''
  elseif kind == 'Skill' then
    return tes3.string(record.skillId)
  elseif kind == 'MagicEffect' then
    return tes3.string(record.effectId)
  elseif kind == 'Cell' then
    local name = tes3.string(record.name)

    if tes3.isInterior(record) then return name end

    if name == '' then name = tes3.string(record.region) end

    if name == '' then name = 'Wilderness' end

    return grid(name, (record.data :: Table).grid)
  elseif kind == 'Landscape' then
    return grid('LAND', record.grid)
  elseif kind == 'PathGrid' then
    local name = tes3.string(record.cell)

    if name == '' then name = 'Wilderness' end

    return grid(name, ((record.data or {}) :: Table).grid)
  end

  return tes3.string(record.id)
end

-- The editor id the Python audits use: a record's `id`, or a magic effect's or skill's id. Cells,
-- path grids, and landscapes have none.
function tes3.auditId(record: Record): string
  local id = record.id

  if type(id) == 'string' then
    return id
  elseif record.type == 'MagicEffect' then
    return tes3.string(record.effectId)
  elseif record.type == 'Skill' then
    return tes3.string(record.skillId)
  end

  return ''
end

-- tes3's `sort_objects`, which tes3conv runs before it writes a plugin: the header, then records
-- by type, then each one's sort hint (a texture's index, an effect's or skill's number) and id.
-- Cells, landscape, and path grids keep their order among themselves, as topics and their
-- INFOs do. The sort is stable.
function tes3.sortObjects(records: Records)
  local sorted = [for from in tes3.sortPermutation(records) => records[from]]
  table.move(sorted, 1, #sorted, 1, records)
end

-- What one number places a record by, each part a whole number the next can't reach: its type's
-- place in the order, then the number a texture, an effect, or a skill sorts by, then where its
-- id falls among the ids. Together they stay below 2^53, where a double holds every whole number.
local HintLimit, HintSpan, RankSpan = 2097152, 4194304, 16777216

--- The positions of `records` in `sortObjects` order, found by comparing them pair by pair:
--- any table's, whatever its records hold.
local function comparedPermutation(records: Records): { number }
  type Entry = { order: number, hint: number, id: string, position: number }
  local entries: { Entry } = {}

  for position, record in records do
    local kind = record.type :: string
    local hint, id = 0, ''

    if kind == 'LandscapeTexture' then
      hint = tonumber(record.index) or 0
    elseif kind == 'MagicEffect' then
      hint = EffectIndex[tes3.string(record.effectId)] or -1
    elseif kind == 'Skill' then
      hint = SkillIndex[tes3.string(record.skillId)] or -1
    elseif SortOrder[kind] ~= 37 and SortOrder[kind] ~= 39 and kind ~= 'Header' then
      id = tes3.string(record.id)
    end

    table.insert(
      entries,
      { order = SortOrder[kind] or 41, hint = hint, id = id, position = position }
    )
  end

  table.sort(entries, function(left, right)
    if left.order ~= right.order then
      return left.order < right.order
    elseif left.hint ~= right.hint then
      return left.hint < right.hint
    elseif left.id ~= right.id then
      return left.id < right.id
    end

    return left.position < right.position
  end)

  local permutation = {}

  for position, entry in entries do
    permutation[position] = entry.position
  end

  return permutation
end

-- The positions of `records` in `sortObjects` order. Each record's place is written as one
-- number, the ids having been put in order among themselves first, and the numbers are sorted
-- at once, records with the same one staying in their order. A table that isn't a list, or a
-- texture whose index isn't a small whole number, is compared pair by pair instead.
function tes3.sortPermutation(records: Records): { number }
  local size = #records
  if size >= RankSpan then return comparedPermutation(records) end

  local keys = buffer.create(size * 8)
  local ids: { string } = table.create(size)
  local ranks: { [string]: number } = {}
  local distinct: { string } = {}
  local count = 0

  for position, record in records do
    local kind = record.type :: string
    local order = SortOrder[kind]
    local hint, id = 0, ''

    if kind == 'LandscapeTexture' then
      hint = tonumber(record.index) or 0
    elseif kind == 'MagicEffect' then
      hint = EffectIndex[tes3.string(record.effectId)] or -1
    elseif kind == 'Skill' then
      hint = SkillIndex[tes3.string(record.skillId)] or -1
    elseif order ~= 37 and order ~= 39 and kind ~= 'Header' then
      id = tes3.string(record.id)
    end

    count += 1

    if position ~= count or count > size or hint % 1 ~= 0 or hint < -1 or hint >= HintLimit then
      return comparedPermutation(records)
    end

    buffer.writef64(keys, (count - 1) * 8, ((order or 41) * HintSpan + hint + 1) * RankSpan)
    ids[count] = id

    if id ~= '' and not ranks[id] then
      ranks[id] = 0
      table.insert(distinct, id)
    end
  end

  if count ~= size then return comparedPermutation(records) end

  if count == 0 then return {} end

  table.sort(distinct)

  for rank, id in distinct do
    ranks[id] = rank
  end

  for position, id in ids do
    if id == '' then continue end

    local slot = (position - 1) * 8
    buffer.writef64(keys, slot, buffer.readf64(keys, slot) + ranks[id])
  end

  local sorted = buffer.create(count * 4)
  data.argsort(keys, 'f64', 0, count, sorted)
  return [for slot in range(0, count - 1) => buffer.readu32(sorted, slot * 4) + 1]
end

function tes3.copy(value: Table): Table return table.clone(value) end

-- A deep copy, for a record about to be edited when other lists still hold it.
function tes3.deepCopy(value: Table): Table
  local copy = table.clone(value)

  for key, item in copy do
    if type(item) == 'table' then copy[key] = tes3.deepCopy(item) end
  end

  return copy
end

local function equalValues(left: Value?, right: Value?): boolean
  if left == right then return true end

  if type(left) ~= 'table' or type(right) ~= 'table' then return false end

  for key, item in left do
    if not equalValues(item, right[key]) then return false end
  end

  for key in right do
    if left[key] == nil then return false end
  end

  return true
end

tes3.equal = equalValues

-- Whether `haystack` holds `needle`, ignoring ASCII case.
function tes3.containsNoCase(haystack: string, needle: string): boolean
  return string.find(string.lower(haystack), string.lower(needle), 1, true) ~= nil
end

-- Perl's `s/pattern/replacement/ig` for a literal pattern: every case-insensitive occurrence
-- of `pattern`, replaced by `replacement` as written. Returns the text and the count.
function tes3.replaceNoCase(text: string, pattern: string, replacement: string): (string, number)
  if pattern == '' then return text, 0 end

  local lowered, needle = string.lower(text), string.lower(pattern)
  local parts: { string } = {}
  local position, count = 1, 0

  while true do
    local first, last = string.find(lowered, needle, position, true)

    if not first then break end

    table.insert(parts, string.sub(text, position, first - 1))
    table.insert(parts, replacement)
    position = (last :: number) + 1
    count += 1
  end

  if count == 0 then return text, 0 end

  table.insert(parts, string.sub(text, position))
  return table.concat(parts), count
end

return tes3
