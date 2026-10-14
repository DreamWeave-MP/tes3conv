--!strict
--!native
-- `transcribeTo` and `compileTo`: the two conversions a whole file gets, which hold neither the
-- records nor the output. Their output is held here to `encode`'s and `compile`'s for every
-- fixture, and to what tes3conv 0.4.1 wrote for documents too long for one chunk, one window, or
-- one buffer; the lengths and digests below are of the program's own files.
local bytes = require '@dream/bytes'
local tes3 = require '@tes3'
local tes3conv = require '@tes3conv'
local test = require '@jess/test'
local expect = test.expect
local suite = test.new()

type Record = { [string | number]: any }
type Pin = { size: number, digest: string }

local Compact = { compact = true }

-- The most a sink is handed at once, and the most a `Text` is asked for.
local Chunk, Window = 1048576, 262144

-- What tes3conv wrote for `statics()`: indented, compact, and compiled to `statics.esp`.
local StaticsPretty: Pin = {
  size = 3800175,
  digest = '2b549678428a308fe863ba159b12658d2355b1a7636e8ad63562a8d8b4b888da',
}

local StaticsCompact: Pin = {
  size = 2600120,
  digest = '9877de72f091b2c82dd84b5139c1b23f4138320013c637e3e2c5fc91f180ed2d',
}

local StaticsPlugin: Pin = {
  size = 2040324,
  digest = '4c10ea06513bdd5bff304e4c12d7b334cca5ce374360595c9b431abbaca3b04f',
}

-- And for `long()`, whose one string is longer than a chunk.
local LongPretty: Pin = {
  size = 1200403,
  digest = 'f7ad4286baf5e6fb4acc071d25ebe1eef08b1360d1e263b5173346e97fbb99f1',
}

local LongCompact: Pin = {
  size = 1200267,
  digest = 'b0b3d2c20be96dea0bfc3d89567df4bb322dec2c0ed5b100c8c52a4a645f82df',
}

local LongPlugin: Pin = {
  size = 1200412,
  digest = 'a3054a80f58e13b6360fc1cb2fdecf71f1b8251569e485b0b4d100d02838b420',
}

local Header = '{"type":"Header","flags":"","version":1.3,"file_type":"Esp","author":"","description":"","num_objects":0,"masters":[]}'

-- The fixtures: every plugin and every document the suite has.
local Plugins = { 'assets/all_types.esp', 'golden/sample.esp', 'golden/sample.esm' }

local Documents = {
  'golden/all_types.json',
  'golden/all_types.compact.json',
  'golden/sample.json',
  'golden/sample.pretty.json',
  'golden/sample.compact.json',
  'golden/sample.esp.compact.json',
}

-- Documents `transcribeTo` and `compileTo` refuse, and what they say of each.
local Malformed: { { text: string, message: string } } = {
  { text = '', message = 'a tes3conv plugin is a JSON array of records' },
  { text = '   ', message = 'a tes3conv plugin is a JSON array of records' },
  { text = '{}', message = 'a tes3conv plugin is a JSON array of records' },
  { text = 'null', message = 'a tes3conv plugin is a JSON array of records' },
  { text = '"[]"', message = 'a tes3conv plugin is a JSON array of records' },
  { text = '[', message = 'the document ends without closing its array' },
  { text = `[{Header}`, message = 'the document ends without closing its array' },
  { text = `[{Header},`, message = 'the document ends without closing its array' },
  { text = '[{', message = 'the document ends inside record 1' },
  { text = `[{Header},\{"type":"Static","id":"x`, message = 'the document ends inside record 2' },
  { text = '[1]', message = 'something that isn\'t a record where record 1 would be' },
  { text = `[{Header} true]`, message = 'something that isn\'t a record where record 2 would be' },
  { text = '["x"]', message = 'record 1 of the document isn\'t an object' },
  { text = `[{Header},[1]]`, message = 'record 2 of the document isn\'t an object' },
  { text = '[{"id":"x"}]', message = 'record 1 of the document has no type' },
  { text = '[{"type":7}]', message = 'record 1 of the document has no type' },
}

--- Where this file is, from its chunk name: the folder the suite and its assets are in.
local function here(): string
  local source = debug.info(1, 's')
  local path = if string.sub(source, 1, 1) == '@' or string.sub(source, 1, 1) == '='
    then string.sub(source, 2)
    else source
  return string.match(path, '^(.*)/[^/]*$') or '.'
end

local function file(name: string): string
  return buffer.tostring(assert(jess.fs.readBuffer(`{here()}/{name}`), `{name} is missing`))
end

--- Holds `actual` to `expected` by length and digest before the bytes, so a miss says something
--- shorter than both.
local function same(actual: string, expected: string)
  expect(#actual).toBe(#expected)
  expect(bytes.sha256(actual)).toBe(bytes.sha256(expected))
  expect(actual == expected).toBe(true)
end

local function pinned(actual: string, pin: Pin)
  expect(#actual).toBe(pin.size)
  expect(bytes.sha256(actual)).toBe(pin.digest)
end

local function saved(plugin: tes3.Plugin): string return buffer.tostring(plugin:save()) end

--- What a conversion hands its sink, whole, with the length of each chunk and how many records
--- it said it wrote.
local function streamed(run: (sink: tes3conv.Sink) -> number): (string, { number }, number)
  local chunks: { string }, lengths: { number } = {}, {}
  local count = run(function(chunk: buffer, length: number)
    table.insert(chunks, buffer.readstring(chunk, 0, length))
    table.insert(lengths, length)
  end)
  return table.concat(chunks), lengths, count
end

local function json(source: tes3.Plugin | string | tes3conv.Text, options: tes3conv.EncodeOptions?): string
  return (streamed(function(sink) return tes3conv.transcribeTo(source, sink, options) end))
end

local function plugin(source: tes3.Plugin | string | tes3conv.Text, name: string?): string
  return (streamed(function(sink) return tes3conv.compileTo(source, sink, name) end))
end

--- `text` as something read a stretch at a time, and the longest stretch it was asked for.
local function stretches(text: string): (tes3conv.Text, () -> number)
  local longest = 0
  local source: tes3conv.Text = {
    size = #text,
    read = function(offset: number, length: number): string
      longest = math.max(longest, length)
      return string.sub(text, offset + 1, offset + length)
    end,
  }

  return source, function(): number return longest end
end

--- Forty thousand statics, last first, under a header that comes after them all: 2.6 megabytes,
--- as the text tes3conv was given.
local function statics(): string
  local records = {}

  for index = 40000, 1, -1 do
    table.insert(
      records,
      string.format('{"type":"Static","flags":"","id":"s%05d","mesh":"m\\\\%05d.nif"}', index, index)
    )
  end

  table.insert(records, Header)
  return `[{table.concat(records, ',')}]`
end

--- A header, a setting whose text is longer than a chunk, and a static, as tes3conv was given
--- them: the text ends in an escaped quote and an escaped line break.
local function long(): string
  local text = string.rep('abcdefghij', 120000) .. '\\"end\\n'
  local counted = string.gsub(Header, '"num_objects":0', '"num_objects":2')
  local setting = `\{"type":"GameSetting","flags":"","id":"sLong","value":\{"type":"String","data":"{text}"}}`
  return `[{counted},{setting},\{"type":"Static","flags":"","id":"after","mesh":"a.nif"}]`
end

suite.describe('fixtures', function()
  for _, name in Plugins do
    suite.it(`streams {name} as the text encode writes, indented and compact`, function()
      local opened = tes3.open(file(name))
      local records = tes3conv.records(opened)
      same(json(opened), tes3conv.encode(records))
      same(json(opened, Compact), tes3conv.encode(records, Compact))
      same(json(opened, { compact = false }), tes3conv.transcribe(opened))
    end)

    suite.it(`streams {name} as the plugin compile builds`, function()
      local opened = tes3.open(file(name))
      local records = tes3conv.records(opened)

      for _, target in { 'out.esp', 'out.esm', 'out.omwaddon' } do
        same(plugin(opened, target), saved(tes3conv.compile(records, target)))
      end

      same(plugin(opened), saved(tes3conv.compile(records)))
    end)
  end

  for _, name in Documents do
    suite.it(`streams {name} as the text encode writes, indented and compact`, function()
      local text = file(name)
      local records = tes3conv.sort(tes3conv.decode(text))
      same(json(text), tes3conv.encode(records))
      same(json(text, Compact), tes3conv.encode(records, Compact))
      local source = stretches(text)
      same(json(source), tes3conv.encode(records))
      same(json(source, Compact), tes3conv.encode(records, Compact))
    end)

    suite.it(`streams {name} as the plugin compile builds`, function()
      local text = file(name)
      local records = tes3conv.decode(text)

      for _, target in { 'out.esp', 'out.esm', 'out.omwaddon' } do
        same(plugin(text, target), saved(tes3conv.compile(records, target)))
      end

      same(plugin(text), saved(tes3conv.compile(records)))
      same(plugin((stretches(text)), 'out.esp'), saved(tes3conv.compile(records, 'out.esp')))
    end)
  end

  suite.it('streams the fixtures to what tes3conv wrote for them', function()
    local every = tes3.open(file 'assets/all_types.esp')
    same(json(every), file 'golden/all_types.json')
    same(json(every, Compact), file 'golden/all_types.compact.json')
    same(plugin(file 'golden/all_types.json', 'all_types.esp'), file 'assets/all_types.esp')
    same(plugin(file 'golden/all_types.compact.json', 'all_types.esp'), file 'assets/all_types.esp')
    same(plugin(every, 'all_types.esp'), file 'assets/all_types.esp')
    same(json(file 'golden/sample.json'), file 'golden/sample.pretty.json')
    same(json(file 'golden/sample.json', Compact), file 'golden/sample.compact.json')
    same(plugin(file 'golden/sample.json', 'sample.esp'), file 'golden/sample.esp')
    same(plugin(file 'golden/sample.json', 'sample.esm'), file 'golden/sample.esm')
    same(json(tes3.open(file 'golden/sample.esp'), Compact), file 'golden/sample.esp.compact.json')
  end)

  suite.it('says how many records it wrote', function()
    local _, _, written = streamed(function(sink)
      return tes3conv.transcribeTo(tes3.open(file 'assets/all_types.esp'), sink)
    end)

    expect(written).toBe(80)
    local _, _, compiled = streamed(function(sink)
      return tes3conv.compileTo(file 'golden/sample.json', sink, 'sample.esp')
    end)

    expect(compiled).toBe(12)
    local text, _, none = streamed(function(sink) return tes3conv.transcribeTo('[]', sink) end)
    expect(none).toBe(0)
    expect(text).toBe '[]'
  end)
end)

suite.describe('chunks', function()
  suite.it('hands a document longer than a chunk over in chunks, as tes3conv wrote it', function()
    local text = statics()
    local pretty, lengths, count = streamed(function(sink) return tes3conv.transcribeTo(text, sink) end)
    pinned(pretty, StaticsPretty)
    expect(count).toBe(40001)
    expect(#lengths).toBe(4)

    for _, length in lengths do
      expect(length <= Chunk).toBe(true)
      expect(length > 0).toBe(true)
    end

    pinned(json(text, Compact), StaticsCompact)
  end)

  suite.it('hands a plugin longer than a chunk over in chunks, as tes3conv wrote it', function()
    local compiled, lengths, count = streamed(function(sink)
      return tes3conv.compileTo(statics(), sink, 'statics.esp')
    end)

    pinned(compiled, StaticsPlugin)
    expect(count).toBe(40001)
    expect(#lengths).toBe(2)
    expect(lengths[1] <= Chunk).toBe(true)
  end)

  suite.it('holds no more than encode does of what it was given in order', function()
    local sorted = tes3conv.sort(tes3conv.decode(statics()))
    pinned(tes3conv.encode(sorted), StaticsPretty)
    pinned(tes3conv.encode(sorted, Compact), StaticsCompact)
    pinned(saved(tes3conv.compile(sorted, 'statics.esp')), StaticsPlugin)
  end)

  suite.it('writes a string longer than a chunk, as tes3conv wrote it', function()
    local text = long()
    pinned(json(text), LongPretty)
    pinned(json(text, Compact), LongCompact)
    pinned(plugin(text, 'long.esp'), LongPlugin)
    pinned(json(tes3.open(plugin(text, 'long.esp')), Compact), LongCompact)
    pinned(tes3conv.encode(tes3conv.decode(text)), LongPretty)
  end)

  suite.it('reads a document a window at a time, and no record twice as long as it is', function()
    local text = statics()
    local source, longest = stretches(text)
    pinned(json(source, Compact), StaticsCompact)
    expect(longest()).toBe(Window)
    pinned(plugin(source, 'statics.esp'), StaticsPlugin)
    expect(longest()).toBe(Window)
  end)

  suite.it('reads a record longer than a window whole, and only that one', function()
    local source, longest = stretches(long())
    pinned(plugin(source, 'long.esp'), LongPlugin)
    expect(longest() > 1200000).toBe(true)
    expect(longest() < 1200200).toBe(true)
  end)
end)

suite.describe('windows', function()
  suite.it('finds records whose strings and escapes fall across a window\'s edge', function()
    local before = `[{Header},\{"type":"GameSetting","flags":"","id":"sEdge","value":\{"type":"String","data":"`
    local after = 'tail"}},{"type":"Static","flags":"","id":"after\\\\","mesh":"a\\"b.nif"}]'

    -- Each escape in turn sits on the window's last byte, a byte either side of it, and with
    -- the closing quote, the comma, and the next record's brace there instead.
    for _, escape in { '\\"', '\\\\', '\\n', '\\u00e9', '\\\\\\"' } do
      for shift = -8, 8 do
        local padding = string.rep('x', Window - #before - 1 + shift)
        local text = `{before}{padding}{escape}{after}`
        local records = tes3conv.decode(text)
        expect(#records).toBe(3)
        same(plugin(text, 'edge.esp'), saved(tes3conv.compile(records, 'edge.esp')))
        same(json(text, Compact), tes3conv.encode(tes3conv.sort(records), Compact))
      end
    end
  end)

  suite.it('finds a record that starts or ends on a window\'s edge', function()
    for shift = -3, 3 do
      local padding = string.rep(' ', Window - #Header - 2 + shift)
      local text = `[{Header},{padding}\{"type":"Static","flags":"","id":"edge","mesh":"e.nif"}]`
      same(json(text, Compact), `[{Header},\{"type":"Static","flags":"","id":"edge","mesh":"e.nif"}]`)
      local static = '{"type":"Static","flags":"","id":"edge","mesh":"e.nif"}'
      local filler = string.rep(' ', Window - #Header - #static - 3 + shift)
      local ending = `[{Header},{filler}{static}  ,  {static}]`
      same(json(ending, Compact), `[{Header},{static},{static}]`)
    end
  end)
end)

suite.describe('refusals', function()
  suite.it('refuses a document that isn\'t an array of records, and says where', function()
    for _, case in Malformed do
      expect(function() json(case.text) end).toThrow(case.message)
      expect(function() plugin(case.text, 'x.esp') end).toThrow(case.message)
    end
  end)

  suite.it('compiles nothing without a header', function()
    local static = '[{"type":"Static","flags":"","id":"zeta","mesh":"z.nif"}]'
    expect(function() plugin(static, 'x.esp') end).toThrow 'tes3conv.compileTo: records must start with a Header'
    expect(function() plugin('[]', 'x.esp') end).toThrow 'tes3conv.compileTo: records must start with a Header'
    local headless = tes3.open(file 'golden/sample.esp')
    headless:delete(0)
    expect(function() plugin(headless, 'x.esp') end).toThrow 'tes3conv.compileTo: records must start with a Header'
  end)

  suite.it('stops where its sink does, and starts over cleanly', function()
    local text = file 'golden/sample.json'
    expect(function() tes3conv.transcribeTo(text, function() error('disk full', 0) end) end).toThrow 'disk full'
    same(json(text), file 'golden/sample.pretty.json')
    expect(function() json '[{"type":"Starship"}]' end).toThrow '\'Starship\' isn\'t a record type tes3conv writes'
    same(plugin(text, 'sample.esp'), file 'golden/sample.esp')
  end)

  suite.it('refuses a plugin record tes3conv can\'t read', function()
    local unknown = 'ZZZZ' .. string.pack('<I4I4I4', 0, 0, 0)
    local opened = tes3.open(file 'golden/sample.esp' .. unknown)
    expect(function() json(opened) end).toThrow '(ZZZZ) has a record type tes3conv can\'t read'
  end)
end)

return suite
