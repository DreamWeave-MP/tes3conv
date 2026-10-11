--!strict
--!native
-- `@tes3conv/records`' own cases: the helpers the tools built on tes3conv-shaped records share,
-- on known values, and its tables against `@tes3`'s.
local records = require '@tes3conv/records'
local tes3 = require '@tes3'
local test = require '@jess/test'
local expect = test.expect
local suite = test.new()

type Record = records.Record

local function typed(kind: string, id: string?): Record return { type = kind, flags = '', id = id } end

local function cell(
  name: string,
  flags: string,
  east: number,
  north: number,
  region: string?
): Record
  return {
    type = 'Cell',
    name = name,
    region = region,
    data = { flags = flags, grid = { east, north } },
  }
end

--- What tells a record apart in a sorted list: the id or name it goes by, or else its type.
local function labels(list: records.Records): { string }
  local out = {}
  for _, record in list do
    local label = record.id or record.effectId or record.skillId or record.name or record.type
    table.insert(out, label :: string)
  end

  return out
end

local function count(map: { [string]: unknown }): number
  local total = 0
  for _ in map do
    total += 1
  end

  return total
end

suite.describe('tables', function()
  suite.it('names each type by the tag @tes3 gives it', function()
    local shared = 0

    for _, spec in tes3.recordTypes do
      -- tes3conv reads no OpenMW record types, so it has no name for LUAL.
      if spec.name == 'ScriptConfigList' then continue end

      shared += 1
      expect(records.Tags[spec.name]).toBe(spec.tag)
      expect(records.TypeNames[spec.tag]).toBe(spec.name)
    end

    expect(count(records.Tags)).toBe(shared)
    expect(count(records.TypeNames)).toBe(shared)
    expect(records.Tags.ScriptConfigList).toBeNil()
  end)

  suite.it('gives every type a place in tes3\'s order', function()
    for name in records.Tags do
      expect(type(records.SortOrder[name])).toBe 'number'
    end

    expect(records.SortOrder.Header).toBe(0)
    expect(records.SortOrder.GameSetting).toBe(1)
    expect(records.SortOrder.Sound).toBe(6)
    expect(records.SortOrder.Skill).toBe(7)
    expect(records.SortOrder.Cell).toBe(37)
    expect(records.SortOrder.Landscape).toBe(37)
    expect(records.SortOrder.PathGrid).toBe(37)
    expect(records.SortOrder.SoundGen).toBe(38)
    expect(records.SortOrder.Dialogue).toBe(39)
    expect(records.SortOrder.DialogueInfo).toBe(39)
  end)

  suite.it('numbers effects and skills as @tes3 does', function()
    expect(records.EffectIndex.None).toBe(-1)
    expect(records.EffectIndex.WaterBreathing).toBe(0)
    expect(records.EffectIndex.Levitate).toBe(10)
    expect(records.EffectIndex.TurnUndead).toBe(101)
    expect(records.EffectIndex.Summon05).toBe(142)
    expect(records.SkillIndex.None).toBe(-1)
    expect(records.SkillIndex.Block).toBe(0)
    expect(records.SkillIndex.Acrobatics).toBe(20)
    expect(records.SkillIndex.HandToHand).toBe(26)
    expect(records.EffectIndex).toEqual(tes3.schema.Enums.EffectId.values)
    expect(records.SkillIndex).toEqual(tes3.schema.Enums.SkillId.values)
  end)
end)

suite.describe('fields', function()
  suite.it('reads a string, and anything else as empty', function()
    expect(records.string 'Pilot').toBe 'Pilot'
    expect(records.string(nil)).toBe ''
    expect(records.string(7)).toBe ''
    expect(records.string(true)).toBe ''
    expect(records.string(jess.null)).toBe ''
    expect(records.string { 'Pilot' }).toBe ''
    expect(records.lower 'Tatooine Region').toBe 'tatooine region'
    expect(records.lower(nil)).toBe ''
  end)

  suite.it('finds a flag in a flags string', function()
    expect(records.hasFlag('PERSISTENT | DELETED', 'DELETED')).toBe(true)
    expect(records.hasFlag('PERSISTENT | DELETED', 'PERSISTENT')).toBe(true)
    expect(records.hasFlag('PERSISTENT', 'DELETED')).toBe(false)
    expect(records.hasFlag('', 'DELETED')).toBe(false)
    expect(records.hasFlag(nil, 'DELETED')).toBe(false)
    expect(records.hasFlag(1, 'DELETED')).toBe(false)
  end)

  suite.it('knows deleted records and interior cells', function()
    expect(records.isDeleted { type = 'Static', flags = 'DELETED' }).toBe(true)
    expect(records.isDeleted { type = 'Static', flags = 'PERSISTENT | DELETED' }).toBe(true)
    expect(records.isDeleted { type = 'Static', flags = '' }).toBe(false)
    expect(records.isDeleted { type = 'Static' }).toBe(false)
    expect(records.isInterior(cell('Hangar', 'IS_INTERIOR | HAS_WATER', 0, 0))).toBe(true)
    expect(records.isInterior(cell('', 'HAS_WATER', 3, 4))).toBe(false)
    expect(records.isInterior { type = 'Cell', name = 'Hangar' }).toBe(false)
  end)
end)

suite.describe('ids', function()
  suite.it('keys records the way tes3 does', function()
    expect(records.editorId(typed('Static', 'Marker'))).toBe 'Marker'
    expect(records.editorId(typed 'Static')).toBe ''
    expect(records.editorId { type = 'Header', id = 'ignored' }).toBe ''
    expect(records.editorId { type = 'Skill', skillId = 'Athletics' }).toBe 'Athletics'
    expect(records.editorId { type = 'MagicEffect', effectId = 'Levitate' }).toBe 'Levitate'
    expect(records.editorId { type = 'Landscape', grid = { -1, 2 } }).toBe 'LAND (-1, 2)'
  end)

  suite.it('keys interior cells by name and exterior cells by name and grid', function()
    expect(records.editorId(cell('Hangar', 'IS_INTERIOR', 0, 0))).toBe 'Hangar'
    expect(records.editorId(cell('', 'IS_INTERIOR', 0, 0, 'Tatooine Region'))).toBe ''
    expect(records.editorId(cell('Mos Eisley', '', -3, -2, 'Tatooine Region'))).toBe 'Mos Eisley (-3, -2)'
    expect(records.editorId(cell('', 'HAS_WATER', -11, 15, 'Tatooine Region'))).toBe 'Tatooine Region (-11, 15)'
    expect(records.editorId(cell('', '', 4, 5))).toBe 'Wilderness (4, 5)'
  end)

  suite.it('keys path grids by their cell and grid', function()
    local interior: Record = { type = 'PathGrid', cell = 'Hangar', data = { grid = { 0, 0 } } }
    local exterior: Record = { type = 'PathGrid', cell = '', data = { grid = { 7, -8 } } }
    expect(records.editorId(interior)).toBe 'Hangar (0, 0)'
    expect(records.editorId(exterior)).toBe 'Wilderness (7, -8)'
    expect(records.editorId { type = 'PathGrid', cell = 'Hangar' }).toBe 'Hangar (0, 0)'
  end)

  suite.it('gives the audits an id, or an effect\'s or skill\'s', function()
    expect(records.auditId(typed('Static', 'Marker'))).toBe 'Marker'
    expect(records.auditId { type = 'MagicEffect', effectId = 'Levitate' }).toBe 'Levitate'
    expect(records.auditId { type = 'Skill', skillId = 'Athletics' }).toBe 'Athletics'
    expect(records.auditId(cell('Hangar', 'IS_INTERIOR', 0, 0))).toBe ''
    expect(records.auditId { type = 'Landscape', grid = { -1, 2 } }).toBe ''
    expect(records.auditId { type = 'PathGrid', cell = 'Hangar' }).toBe ''
  end)
end)

suite.describe('sorting', function()
  suite.it('puts the header first, then types in tes3\'s order, ids in byte order', function()
    local list = {
      typed('Static', 'beta'),
      typed('Npc', 'alpha'),
      { type = 'Header', flags = '' },
      typed('GameSetting', 'sB'),
      typed('Static', 'Zeta'),
      typed('Static', 'alpha'),
      typed('GameSetting', 'fA'),
    }
    records.sortObjects(list)
    expect(labels(list)).toEqual { 'Header', 'fA', 'sB', 'Zeta', 'alpha', 'beta', 'alpha' }
    expect(list[7].type).toBe 'Npc'
  end)

  suite.it('sorts textures by index, and effects and skills by number', function()
    local list: records.Records = {
      { type = 'LandscapeTexture', id = 'sand', index = 1 },
      { type = 'LandscapeTexture', id = 'ash', index = 2 },
      { type = 'LandscapeTexture', id = 'mud', index = 0 },
      { type = 'MagicEffect', effectId = 'Levitate' },
      { type = 'MagicEffect', effectId = 'WaterBreathing' },
      { type = 'MagicEffect', effectId = 'Burden' },
      { type = 'Skill', skillId = 'Sneak' },
      { type = 'Skill', skillId = 'Acrobatics' },
      { type = 'Skill', skillId = 'Block' },
    }
    records.sortObjects(list)
    expect(labels(list)).toEqual {
      'Block',
      'Sneak',
      'Acrobatics',
      'WaterBreathing',
      'Burden',
      'Levitate',
      'mud',
      'sand',
      'ash',
    }
  end)

  suite.it('keeps cells, landscape, and path grids in their order, as topics and INFOs', function()
    local list: records.Records = {
      typed('DialogueInfo', 'second info'),
      cell('Zeta', 'IS_INTERIOR', 0, 0),
      typed('Dialogue', 'zeta topic'),
      { type = 'Landscape', name = 'land', grid = { 0, 0 } },
      typed('SoundGen', 'growl'),
      typed('DialogueInfo', 'first info'),
      { type = 'PathGrid', name = 'grid', cell = 'Zeta' },
      typed('Dialogue', 'alpha topic'),
      cell('Alpha', 'IS_INTERIOR', 0, 0),
    }
    records.sortObjects(list)
    expect(labels(list)).toEqual {
      'Zeta',
      'land',
      'grid',
      'Alpha',
      'growl',
      'second info',
      'zeta topic',
      'first info',
      'alpha topic',
    }
  end)

  suite.it('keeps equal records in their order, and types it doesn\'t know last', function()
    local first, second = typed('Static', 'twin'), typed('Static', 'twin')
    local topic = typed('Dialogue', 'topic')
    local list =
      { typed('ScriptConfigList', 'b'), typed('ScriptConfigList', 'a'), topic, first, second }
    records.sortObjects(list)
    expect(list[1]).toBe(first)
    expect(list[2]).toBe(second)
    expect(list[3]).toBe(topic)
    expect(labels(list)).toEqual { 'twin', 'twin', 'topic', 'a', 'b' }
  end)

  suite.it('gives the permutation sortObjects applies', function()
    local header: Record = { type = 'Header', flags = '' }
    local beta, alpha = typed('Static', 'beta'), typed('Static', 'alpha')
    local list = { beta, header, alpha }
    expect(records.sortPermutation(list)).toEqual { 2, 3, 1 }
    expect(list).toEqual { beta, header, alpha }
    expect(records.sortPermutation {}).toEqual {}
  end)
end)

suite.describe('copies', function()
  suite.it('copies a table\'s top level, or all of it', function()
    local record: Record = { type = 'Cell', name = 'Hangar', data = { grid = { 1, 2 } } }
    local shallow = records.copy(record)
    expect(shallow).toEqual(record)
    expect(rawequal(shallow, record)).toBe(false)
    expect(shallow.data).toBe(record.data)
    local deep = records.deepCopy(record)
    expect(deep).toEqual(record)
    expect(rawequal(deep.data, record.data)).toBe(false)
    local grid = (deep.data :: records.Table).grid :: records.Table
    grid[1] = 9
    expect(deep.data).toEqual { grid = { 9, 2 } }
    expect(record.data).toEqual { grid = { 1, 2 } }
  end)

  suite.it('compares values deeply', function()
    local placed: Record = { id = 'a', data = { grid = { 1, 2 } } }
    expect(records.equal(placed, { id = 'a', data = { grid = { 1, 2 } } })).toBe(true)
    expect(records.equal(placed, { id = 'a', data = { grid = { 1, 3 } } })).toBe(false)
    expect(records.equal({ id = 'a' }, { id = 'a', name = 'A' })).toBe(false)
    expect(records.equal({ id = 'a', name = 'A' }, { id = 'a' })).toBe(false)
    expect(records.equal('a', 'a')).toBe(true)
    expect(records.equal(1, '1')).toBe(false)
    expect(records.equal({}, '')).toBe(false)
    expect(records.equal(nil, nil)).toBe(true)
    expect(records.equal({}, nil)).toBe(false)
  end)
end)

suite.describe('text', function()
  suite.it('finds text whatever its case, literally', function()
    expect(records.containsNoCase('Begin SW_PilotScript', 'sw_pilotscript')).toBe(true)
    expect(records.containsNoCase('begin sw_pilotscript', 'SW_Pilot')).toBe(true)
    expect(records.containsNoCase('Begin SW_PilotScript', 'droid')).toBe(false)
    expect(records.containsNoCase('m.nif', 'M.NIF')).toBe(true)
    expect(records.containsNoCase('mxnif', 'm.nif')).toBe(false)
  end)

  suite.it('replaces every occurrence whatever its case, and counts them', function()
    local text, replaced = records.replaceNoCase('Balmora, BALMORA, balmora.', 'balmora', 'Mos')
    expect(text).toBe 'Mos, Mos, Mos.'
    expect(replaced).toBe(3)
    -- The pattern and the replacement are both literal.
    expect({ records.replaceNoCase('a.b, A.B, axb', 'a.b', '%1') }).toEqual { '%1, %1, axb', 2 }
    expect({ records.replaceNoCase('unchanged', 'missing', 'new') }).toEqual { 'unchanged', 0 }
    expect({ records.replaceNoCase('unchanged', '', 'new') }).toEqual { 'unchanged', 0 }
    expect({ records.replaceNoCase('aaa', 'aa', 'b') }).toEqual { 'ba', 1 }
  end)
end)

return suite
