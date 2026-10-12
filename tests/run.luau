--!strict
--!native
-- tes3conv's own cases: its JSON read into record tables, and record tables through `@tes3`
-- plugins and back, on a document and plugins small enough to read and on `@tes3`'s every-type
-- plugin (`assets/all_types.esp`, copied from its suite).
local tes3 = require '@tes3'
local tes3conv = require '@tes3conv'
local test = require '@jess/test'
local expect = test.expect
local suite = test.new()

type Record = { [string | number]: any }

local Document = [[
[
  {
    "type": "Header",
    "flags": "",
    "version": 1.3,
    "file_type": "Esp",
    "author": "",
    "description": "",
    "num_objects": 3,
    "masters": []
  },
  {
    "type": "GameSetting",
    "flags": "",
    "id": "sQuote",
    "value": {
      "type": "String",
      "data": "say \"hi\"\né"
    }
  },
  {
    "type": "Class",
    "flags": "",
    "id": "Pilot",
    "name": "Pilot",
    "data": {
      "attribute1": "Speed",
      "attribute2": "Agility",
      "specialization": "Stealth",
      "major1": "Acrobatics",
      "minor1": "Athletics",
      "major2": "Alchemy",
      "minor2": "Alteration",
      "major3": "Armorer",
      "minor3": "Axe",
      "major4": "Block",
      "minor4": "BluntWeapon",
      "major5": "Conjuration",
      "minor5": "Destruction",
      "flags": "",
      "services": ""
    },
    "description": "Flies."
  },
  {
    "type": "Cell",
    "flags": "",
    "name": "Hangar",
    "data": {
      "flags": "IS_INTERIOR",
      "grid": [
        0,
        0
      ]
    },
    "references": []
  }
]
]]

local function u32(value: number): string return string.pack('<I4', value) end

local function subrecord(tag: string, payload: string): string
  return tag .. u32(#payload) .. payload
end

local function record(tag: string, payload: string): string
  return tag .. u32(#payload) .. u32(0) .. u32(0) .. payload
end

--- A TES3 record for an authorless plugin that says it holds `count` records.
local function headerBytes(count: number): string
  return record(
    'TES3',
    subrecord('HEDR', string.pack('<f', 1.3) .. u32(0) .. string.rep('\0', 288) .. u32(count))
  )
end

--- The header `headerBytes` reads as: 1.3 is not an f32, so its version reads back rounded.
local function header(count: number): Record
  return {
    type = 'Header',
    flags = '',
    version = string.unpack('<f', string.pack('<f', 1.3)),
    fileType = 'Esp',
    author = '',
    description = '',
    numObjects = count,
    masters = {},
  }
end

local function static(id: string, mesh: string): string
  return record('STAT', subrecord('NAME', id .. '\0') .. subrecord('MODL', mesh .. '\0'))
end

local function reference(fields: Record): Record
  local value: Record = {
    id = 'crate',
    mastIndex = 0,
    refrIndex = 1,
    temporary = true,
    translation = { 0, 0, 0 },
    rotation = { 0, 0, 0 },
  }

  for key, item in fields do
    value[key] = item
  end

  return value
end

local function saved(plugin: tes3.Plugin): string return buffer.tostring(plugin:save()) end

local function recordTags(plugin: tes3.Plugin): { string }
  local out = {}
  for index = 0, plugin:count() - 1 do
    table.insert(out, plugin:tag(index))
  end

  return out
end

local function subrecordTags(plugin: tes3.Plugin, index: number): { string }
  local out = {}
  for _, sub in plugin:subrecords(index) do
    table.insert(out, sub.tag)
  end

  return out
end

--- The bytes of a record's first subrecord with `tag`.
local function payload(plugin: tes3.Plugin, index: number, tag: string): string?
  local source = plugin:span(index)
  for _, sub in plugin:subrecords(index) do
    if sub.tag == tag then return buffer.readstring(source, sub.payload, sub.size) end
  end

  return nil
end

local function ids(references: { Record }): { string }
  local out = {}
  for _, item in references do
    table.insert(out, item.id)
  end

  return out
end

--- Where this file is, from its chunk name: the folder the suite and its assets are in.
local function here(): string
  local source = debug.info(1, 's')
  local path = if string.sub(source, 1, 1) == '@' or string.sub(source, 1, 1) == '='
    then string.sub(source, 2)
    else source
  return string.match(path, '^(.*)/[^/]*$') or '.'
end

suite.describe('json', function()
  suite.it('reads any JSON value, keys camelCase', function()
    local value = tes3conv.json [[
      {
        "speaker_id": "pilot",
        "_private_key": 1,
        "level_2": [true, false, null, -2.5, 1e3],
        "nested_table": { "file_type": "Esp" },
        "empty": {},
        "list": []
      }
    ]]

    expect(value).toEqual {
      speakerId = 'pilot',
      _privateKey = 1,
      level_2 = { true, false, jess.null, -2.5, 1000 },
      nestedTable = { fileType = 'Esp' },
      empty = {},
      list = {},
    }
  end)

  suite.it('keeps keys as the document spells them when asked', function()
    local value = tes3conv.json('{"file_type": {"num_objects": 3}}', true)
    expect(value).toEqual { file_type = { num_objects = 3 } }
  end)

  suite.it('unescapes strings, hex digits after an escape included', function()
    expect(tes3conv.json [["a\"b\\c\/d\r\n\t\u00e9\u0416"]]).toBe 'a"b\\c/d\r\n\t\u{e9}\u{416}'
    expect(tes3conv.json [["\nface\tbed"]]).toBe '\nface\tbed'
  end)
end)

suite.describe('documents', function()
  suite.it('reads keys camelCase and strings unescaped', function()
    local records = tes3conv.decode(Document)
    expect(#records).toBe(4)
    expect(records[1].fileType).toBe 'Esp'
    expect(records[2].value.data).toBe 'say "hi"\n\u{e9}'
  end)

  suite.it('leaves lazy types unread until realized', function()
    local records = tes3conv.decode(Document, { lazy = { Cell = true } })
    local cell = records[4]
    expect(tes3conv.isLazy(cell)).toBe(true)
    expect(cell.name).toBeNil()
    tes3conv.realize(cell)
    expect(cell.name).toBe 'Hangar'
    expect(tes3conv.isLazy(cell)).toBe(false)
  end)

  suite.it('finds the end of a lazy record past its nested tables', function()
    local eager = tes3conv.decode(Document)
    local records = tes3conv.decode(Document, { lazy = { Class = true } })
    expect(#records).toBe(4)
    expect(records[3]).toEqual { type = 'Class' }
    expect(records[4]).toEqual(eager[4])
    expect(tes3conv.realize(records[3])).toBe(records[3])
    expect(records[3]).toEqual(eager[3])
    expect(tes3conv.realize(eager[3])).toBe(eager[3])
  end)

  suite.it('keeps the document\'s keys when asked, in lazy records too', function()
    local records: { Record } =
      tes3conv.decode(Document, { rawKeys = true, lazy = { Header = true } })
    expect(records[1]).toEqual { type = 'Header' }
    tes3conv.realize(records[1])
    expect(records[1].file_type).toBe 'Esp'
    expect(records[1].num_objects).toBe(3)
    expect(records[1].fileType).toBeNil()
  end)

  suite.it('reads an empty document, and refuses one that isn\'t an array', function()
    expect(tes3conv.decode '[]').toEqual {}
    expect(function() tes3conv.decode '{}' end).toThrow 'a tes3conv plugin is a JSON array of records'
  end)

  suite.it('refuses a lazy record tes3conv didn\'t indent', function()
    local flat = '[{"type": "Cell", "name": "Hangar"}]'
    expect((tes3conv.decode(flat)[1] :: Record).name).toBe 'Hangar'
    expect(function() tes3conv.decode(flat, { lazy = { Cell = true } }) end).toThrow 'a lazily read tes3conv record must be indented as tes3conv writes it'
  end)

  suite.it('reads a document from a file', function()
    local scratch = assert(rawget(_G, 'scratchRoot') :: string?, 'the case needs a scratchRoot')
    local path = jess.fs.join(scratch, 'tes3conv-document.json')
    jess.fs.write(path, Document)
    expect(tes3conv.read(path)).toEqual(tes3conv.decode(Document))
    expect(tes3conv.read(path, { lazy = { Cell = true } })[4]).toEqual { type = 'Cell' }
    expect(function() tes3conv.read(jess.fs.join(scratch, 'tes3conv-missing.json')) end).toThrow 'tes3conv-missing.json\' doesn\'t exist'
  end)
end)

suite.describe('prepare', function()
  suite.it(
    'terminates the text tes3conv terminates, and drops a plugin\'s own counts of one',
    function()
      local records = tes3conv.decode(Document)
      expect(tes3conv.prepare(records[3]).description).toBe 'Flies.\0'
      expect(records[3].description).toBe 'Flies.'
      local cell = {
        type = 'Cell',
        references = {
          { mastIndex = 0, refrIndex = 2, id = 'b', temporary = true, objectCount = 1 },
          { mastIndex = 1, refrIndex = 9, id = 'a', temporary = true, objectCount = 1 },
          { mastIndex = 0, refrIndex = 1, id = 'p', temporary = false },
        },
      }
      local prepared = tes3conv.prepare(cell)
      local order = {}

      for _, reference in prepared.references do
        table.insert(order, `{reference.id}:{reference.objectCount}`)
      end

      expect(order).toEqual { 'p:nil', 'a:1', 'b:nil' }
    end
  )

  suite.it('terminates each type\'s exact text, once', function()
    local exact = {
      Book = 'text',
      Class = 'description',
      DialogueInfo = 'scriptText',
      MagicEffect = 'description',
      Race = 'description',
      Script = 'text',
      Skill = 'description',
    }

    for kind, field in exact do
      local written: Record = { type = kind, [field] = 'words' }
      local prepared = tes3conv.prepare(written)
      expect(prepared[field]).toBe 'words\0'
      expect(written[field]).toBe 'words'
      expect(tes3conv.prepare(prepared)).toBe(prepared)
      local empty: Record = { type = kind, [field] = '' }
      expect(tes3conv.prepare(empty)).toBe(empty)
    end
  end)

  suite.it('terminates a string game setting and leaves the rest alone', function()
    local setting: Record =
      { type = 'GameSetting', id = 'sName', value = { type = 'String', data = 'Name' } }
    expect(tes3conv.prepare(setting).value).toEqual { type = 'String', data = 'Name\0' }
    expect(setting.value.data).toBe 'Name'
    local number: Record =
      { type = 'GameSetting', id = 'fJump', value = { type = 'Float', data = 1.5 } }
    expect(tes3conv.prepare(number)).toBe(number)
    local marker: Record = { type = 'Static', id = 'marker', mesh = 'm.nif' }
    expect(tes3conv.prepare(marker)).toBe(marker)
    local bare: Record = { type = 'Cell', name = 'Hangar' }
    expect(tes3conv.prepare(bare)).toBe(bare)
  end)

  suite.it('keeps the counts tes3conv writes, and the references it was given', function()
    local references = {
      reference { id = 'stack', refrIndex = 1, objectCount = 5 },
      reference { id = 'theirs', mastIndex = 2, refrIndex = 1, objectCount = 1 },
      reference { id = 'own', refrIndex = 2, objectCount = 1 },
    }
    local cell: Record = { type = 'Cell', references = references }
    local prepared = tes3conv.prepare(cell)
    local order = {}

    for _, item in prepared.references do
      table.insert(order, `{item.id}:{item.objectCount}`)
    end

    expect(order).toEqual { 'theirs:1', 'stack:5', 'own:nil' }
    expect(cell.references).toBe(references)
    expect(ids(references)).toEqual { 'stack', 'theirs', 'own' }
    expect(references[3].objectCount).toBe(1)
  end)
end)

suite.describe('references', function()
  suite.it('counts moved references and doors with destinations as persistent', function()
    expect(tes3conv.isPersistent { temporary = true }).toBe(false)
    expect(tes3conv.isPersistent { temporary = false }).toBe(true)
    expect(tes3conv.isPersistent {}).toBe(true)
    expect(tes3conv.isPersistent { temporary = true, movedCell = { 1, 2 } }).toBe(true)
    expect(tes3conv.isPersistent { temporary = true, destination = { cell = 'Hangar' } }).toBe(true)
  end)

  suite.it('sorts persistent first, then the masters\', then the plugin\'s own', function()
    local references = {
      reference { id = 'own 2', refrIndex = 2 },
      reference { id = 'second master', mastIndex = 2, refrIndex = 5 },
      reference { id = 'first master', mastIndex = 1, refrIndex = 9 },
      reference { id = 'own 1', refrIndex = 1 },
      reference { id = 'kept', refrIndex = 7, temporary = false },
      reference { id = 'kept master', mastIndex = 1, refrIndex = 3, temporary = false },
      reference { id = 'door', refrIndex = 4, destination = { cell = 'Hangar' } },
    }
    tes3conv.sortReferences(references)
    expect(ids(references)).toEqual {
      'kept master',
      'door',
      'kept',
      'first master',
      'second master',
      'own 1',
      'own 2',
    }
  end)

  --- Whether `left` goes before `right`: persistent first, then a master's before the plugin's
  --- own, by master and then by index.
  local function before(left: Record, right: Record): boolean
    local leftKept, rightKept = tes3conv.isPersistent(left), tes3conv.isPersistent(right)
    if leftKept ~= rightKept then return leftKept end

    local leftMaster = if left.mastIndex == 0 then math.huge else left.mastIndex
    local rightMaster = if right.mastIndex == 0 then math.huge else right.mastIndex
    if leftMaster ~= rightMaster then return leftMaster < rightMaster end

    return left.refrIndex < right.refrIndex
  end

  local random = 0x2545f491

  local function pick(limit: number): number
    random = bit32.bxor(random, bit32.lshift(random, 13))
    random = bit32.bxor(random, bit32.rshift(random, 17))
    random = bit32.bxor(random, bit32.lshift(random, 5))
    return random % limit + 1
  end

  --- `count` references, no two with one master and index unless `twins`, in no order. With
  --- `strange`, some have a master or an index no plugin holds.
  local function scattered(count: number, twins: boolean, strange: boolean): { Record }
    local odd = { 1.5, -1, 16777216, 16777215, 1099511627776, -0.25, 33554432 }
    local list: { Record } = {}

    for position = 1, count do
      local fields: Record = {
        id = `reference {position}`,
        mastIndex = pick(4) - 1,
        refrIndex = if twins then pick(count // 2 + 1) else position,
      }

      if pick(3) == 1 then fields.temporary = false end

      if pick(9) == 1 then fields.movedCell = { 1, 2 } end

      if pick(9) == 1 then fields.destination = { cell = 'Hangar' } end

      if strange and pick(4) == 1 then fields.mastIndex = odd[pick(#odd)] end

      if strange and pick(4) == 1 then fields.refrIndex = odd[pick(#odd)] + position end

      list[position] = reference(fields)
    end

    for position = count, 2, -1 do
      local other = pick(position)
      list[position], list[other] = list[other], list[position]
    end

    return list
  end

  --- Holds `sortReferences` to what comparing the list pair by pair makes of it.
  local function held(list: { Record })
    local compared = table.clone(list)
    table.sort(compared, before)
    local sorted = table.clone(list)
    tes3conv.sortReferences(sorted)
    expect(ids(sorted)).toEqual(ids(compared))

    -- And again from the order that came to: left as it is, unless two references tie.
    local again, expected = table.clone(compared), table.clone(compared)
    table.sort(expected, before)
    tes3conv.sortReferences(again)
    expect(ids(again)).toEqual(ids(expected))
  end

  suite.it('sorts a list of any length as comparing its references pair by pair does', function()
    for _, count in { 0, 1, 2, 3, 7, 16, 17, 100, 700, 5000 } do
      held(scattered(count, false, false))
    end
  end)

  suite.it('sorts a list turned around', function()
    local list = scattered(300, false, false)
    table.sort(list, before)
    local turned: { Record } = {}

    for position = #list, 1, -1 do
      table.insert(turned, list[position])
    end

    tes3conv.sortReferences(turned)
    expect(ids(turned)).toEqual(ids(list))
  end)

  suite.it('sorts references that share a master and index as comparing them does', function()
    for _, count in { 2, 3, 16, 100, 700 } do
      held(scattered(count, true, false))
    end
  end)

  suite.it('sorts references with a master or an index no plugin holds as comparing them does', function()
    for _, count in { 2, 3, 16, 100, 700 } do
      held(scattered(count, false, true))
      held(scattered(count, true, true))
    end
  end)
end)

suite.describe('plugins', function()
  suite.it('writes what it reads, and reads it back sorted', function()
    local records = tes3conv.decode(Document)
    local plugin = tes3conv.plugin(records)
    local back = tes3conv.records(plugin)
    expect(back[2].type).toBe 'GameSetting'
    expect(back[3].description).toBe 'Flies.'
    expect(back[2].value.data).toBe 'say "hi"\n\u{e9}'
  end)

  suite.it('refuses records that don\'t start with a header', function()
    local records = tes3conv.decode(Document)
    expect(function() tes3conv.plugin {} end).toThrow 'tes3conv.plugin: records must start with a Header'
    expect(function() tes3conv.plugin { records[2], records[1] } end).toThrow 'tes3conv.plugin: records must start with a Header'
  end)

  suite.it('writes records in the order given, and sorted when asked', function()
    local records = tes3conv.decode(Document)
    local given = { records[1], records[4], records[3], records[2] }
    expect(recordTags(tes3conv.plugin(given))).toEqual { 'TES3', 'CELL', 'CLAS', 'GMST' }
    local sorted = tes3conv.sort(given)
    expect(recordTags(tes3conv.plugin(sorted))).toEqual { 'TES3', 'GMST', 'CLAS', 'CELL' }
    expect(given[2]).toBe(records[4])
  end)

  suite.it('writes text terminated, in the plugin\'s code page', function()
    local plugin = tes3.open(saved(tes3conv.plugin(tes3conv.decode(Document))))
    expect(plugin:header().recordCount).toBe(3)
    expect(subrecordTags(plugin, 1)).toEqual { 'NAME', 'STRV' }
    expect(payload(plugin, 1, 'STRV')).toBe 'say "hi"\n\xE9\0'
    expect(payload(plugin, 2, 'DESC')).toBe 'Flies.\0'
    expect((plugin:decode(2) :: any).description).toBe 'Flies.\0'
  end)

  suite.it('leaves the count off a plugin\'s own single reference', function()
    local cell: Record = {
      type = 'Cell',
      flags = '',
      name = 'Hangar',
      data = { flags = 'IS_INTERIOR', grid = { 0, 0 } },
      references = {
        reference { refrIndex = 1, objectCount = 1 },
        reference { refrIndex = 2, objectCount = 5 },
      },
    }
    local plugin = tes3conv.plugin { header(1), cell }
    expect(subrecordTags(plugin, 1)).toEqual {
      'NAME',
      'DATA',
      'NAM0',
      'FRMR',
      'NAME',
      'DATA',
      'FRMR',
      'NAME',
      'NAM9',
      'DATA',
    }
    local back: Record = tes3conv.records(plugin)[2]
    expect(back.references[1].objectCount).toBeNil()
    expect(back.references[2].objectCount).toBe(5)
  end)

  suite.it('reads records and their bytes in tes3conv\'s order', function()
    local marker, anchor = static('marker', 'm.nif'), static('anchor', 'a.nif')
    local setting = record('GMST', subrecord('NAME', 'sQuote\0') .. subrecord('STRV', 'hi\0'))
    local plugin = tes3.open(headerBytes(3) .. marker .. anchor .. setting)
    local records, bytes = tes3conv.recordsWithBytes(plugin)
    expect(records).toEqual {
      header(3),
      { type = 'GameSetting', flags = '', id = 'sQuote', value = { type = 'String', data = 'hi' } },
      { type = 'Static', flags = '', id = 'anchor', mesh = 'a.nif' },
      { type = 'Static', flags = '', id = 'marker', mesh = 'm.nif' },
    }

    expect(bytes).toEqual { headerBytes(3), setting, anchor, marker }
    expect(tes3conv.records(plugin)).toEqual(records)
    expect(recordTags(plugin)).toEqual { 'TES3', 'STAT', 'STAT', 'GMST' }
  end)

  suite.it('cuts the text tes3conv terminates at its first NUL', function()
    local book = record(
      'BOOK',
      subrecord('NAME', 'book\0')
        .. subrecord('BKDT', string.pack('<fIIiI', 1, 2, 1, 20, 3))
        .. subrecord('TEXT', 'one\0two')
    )
    local setting = record('GMST', subrecord('NAME', 'sName\0') .. subrecord('STRV', 'hi\0there'))
    local plugin = tes3.open(headerBytes(2) .. setting .. book)
    expect((plugin:decode(1) :: any).value.data).toBe 'hi\0there'
    expect((plugin:decode(2) :: any).text).toBe 'one\0two'
    local records: { Record } = tes3conv.records(plugin)
    expect(records[2].value.data).toBe 'hi'
    expect(records[3].text).toBe 'one'
  end)

  suite.it('refuses a record type tes3conv can\'t read', function()
    local plugin = tes3.open(headerBytes(1) .. record('ZZZZ', subrecord('NAME', 'unknown')))
    expect(function() tes3conv.records(plugin) end).toThrow 'record 1 (ZZZZ) has a record type tes3conv can\'t read'
  end)
end)

suite.describe('round trips', function()
  suite.it('reads back the document it wrote', function()
    local records: { Record } = tes3conv.sort(tes3conv.decode(Document))
    local plugin = tes3conv.plugin(records)
    local back = tes3conv.records(plugin)
    records[1] = header(3)
    expect(back).toEqual(records)
    expect(saved(tes3conv.plugin(back))).toBe(saved(plugin))
  end)

  suite.it('rebuilds a plugin from its records, byte for byte', function()
    local marker, anchor = static('marker', 'm.nif'), static('anchor', 'a.nif')
    local setting = record('GMST', subrecord('NAME', 'sQuote\0') .. subrecord('STRV', 'hi\0'))
    local sorted = headerBytes(3) .. setting .. anchor .. marker
    expect(saved(tes3conv.plugin(tes3conv.records(tes3.open(sorted))))).toBe(sorted)
    local shuffled = headerBytes(3) .. marker .. setting .. anchor
    expect(saved(tes3conv.plugin(tes3conv.records(tes3.open(shuffled))))).toBe(sorted)
  end)

  suite.it('rebuilds a default record of every type', function()
    local defaults: { Record } = { tes3.default 'Header' :: any }
    for _, spec in tes3.recordTypes do
      if spec.name ~= 'Header' then table.insert(defaults, tes3.default(spec.name) :: any) end
    end

    local sorted = tes3conv.sort(defaults)
    local plugin = tes3conv.plugin(sorted)
    expect(plugin:count()).toBe(#tes3.recordTypes)
    local back = tes3conv.records(plugin)
    expect(back).toEqual(sorted)
    expect(saved(tes3conv.plugin(back))).toBe(saved(plugin))
  end)

  suite.it('rebuilds the every-type plugin byte for byte', function()
    local source = buffer.tostring(assert(jess.fs.readBuffer(`{here()}/assets/all_types.esp`)))
    local records, bytes = tes3conv.recordsWithBytes(tes3.open(source))
    expect(#records).toBe(80)
    -- Compared as booleans: a mismatch would print both plugins whole.
    expect(table.concat(bytes) == source).toBe(true)
    expect(saved(tes3conv.plugin(records)) == source).toBe(true)
  end)
end)

return suite
