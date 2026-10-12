--!strict
--!native
--[[
@tes3conv: tes3conv's JSON plugins as jess record tables, and record tables
written into a plugin the way tes3conv writes them.

  decode(text, options?)  the records of a tes3conv JSON document, header first
  read(path, options?)    the same, from a file
  realize(record)         a record decode() left unread, read now (in place); returns it
  prepare(record)         the record as tes3conv's encoder would write it, ready for core.encode
  plugin(records)         a new raw-preserving package plugin holding the records, header first
  records(plugin)         a package plugin's records as the tables tes3conv would have read
  encode(records, options?)       the records as tes3conv's JSON text, byte for byte
  write(path, records, options?)  the same, into a file
  transcribe(plugin, options?)    a plugin as that text, one record at a time
  transcribeTo(source, sink, options?)  a plugin or a document as that text, streamed
  compile(records, fileName?)     the plugin tes3conv writes from the records into that file
  compileTo(source, sink, fileName?)    a plugin or a document as that plugin, streamed

Records come out as `plugin:decode(index)` spells them: a `type` field holding the type name, and
camelCase field names (`speaker_id` is `speakerId`). Values are left as tes3conv wrote them: flags
are strings ("PERSISTENT | DELETED"), enums their names.

`options.lazy` names record types to leave unread: `{ Cell = true, Landscape = true }` reads only
those records' `type`, and `realize` reads the rest when it's wanted. A Morrowind.json is mostly
cells and landscape, so a tool that only needs its objects and dialogue reads it five times
faster. `options.rawKeys = true` keeps keys as the document spells them, for reading reports.

tes3conv 0.4.1 writes every string NUL-terminated and leaves out an object count of 1 on a
plugin's own references. jess writes the text fields Morrowind.esm leaves unterminated as they
are, and keeps every count, so `prepare` adds the terminators and drops the counts tes3conv
would: what `plugin` builds is byte for byte what tes3conv would compile from the same JSON.

`encode` is the other direction's text: `encode(records(plugin))` is byte for byte what
`tes3conv plugin.esp plugin.json` writes, and with `options.compact` what `tes3conv -c` writes.
Fields come out in tes3conv's order, floats as it spells an f32 (`3.0`, `1e+16`), a cell's
references one per master and index in the order it sorts them, and nothing ends the text:
tes3conv writes no final newline. Records are written in the order given, as `plugin` writes
them, with camelCase keys, as `decode` gives them without `rawKeys`. Values are written as they
are spelled: tes3conv, which reads a document into numbers before it writes one, would respell
flags given in another order (`DELETED | PERSISTENT`), and `encode` doesn't.

`compile` is everything `tes3conv plugin.json <fileName>` does to a document's records on the way
to a plugin: it sorts them, keeps one reference per master and index in each cell, and writes a
header that counts the records after it and has the file type an `.esp` or `.esm` name stands
for, whatever the document's header said. `plugin` is the part of that which writes. Records
with no header aren't compiled; tes3conv writes them as they are, a plugin with none.

Everything above works on values in memory, and a master's records as tables are several times
the master. `transcribeTo` and `compileTo` are the same two conversions for a whole file, which
never hold them: the source is a plugin or a document, each record is read, written, and let go,
and the output is handed to a sink a chunk of at most a megabyte at a time. A document is its
text, or a `Text`, which reads it a stretch at a time from wherever it is, so that it need not be
held either. What they hold is a plugin's bytes, whole (`@tes3` opens a plugin from all of it),
or a quarter megabyte of a document at a time; where each record is and the id tes3conv's order
goes by; one record's tables; and one chunk. Their output is byte for byte `encode`'s and
`compile(...):save()`'s.
]]

local Encode = require '@self/encode'
local bytes = require '@dream/bytes'
local tes3 = require '@self/records'
local core = require '@tes3'

type Table = tes3.Table
type Value = tes3.Value
type Records = tes3.Records

export type Options = { lazy: { [string]: boolean }?, rawKeys: boolean? }

--- `compact` leaves out the indentation, as `tes3conv --compact` does.
export type EncodeOptions = { compact: boolean? }

--- Takes the next `length` bytes of what `transcribeTo` or `compileTo` writes: the first `length`
--- of `chunk`, which is written over once the sink returns.
export type Sink = Encode.Sink

--- Text too long to hold, read a stretch at a time: its length in bytes, and the `length` bytes
--- after its first `offset`. A file's contents, or anything else that can be read in the middle.
export type Text = { size: number, read: (offset: number, length: number) -> string }

local tes3conv = {}

-- What the character after a JSON backslash stands for.
local Escapes: { [string]: string } = {
  ['n'] = '\n',
  ['r'] = '\r',
  ['t'] = '\t',
  ['b'] = '\b',
  ['f'] = '\f',
  ['/'] = '/',
  ['\\'] = '\\',
  ['"'] = '"',
}

local camelCache: { [string]: string } = {}

-- omwaddon::symbol::camel_case: `_` before a lowercase letter becomes that letter uppercased,
-- except at the start.
local function camel(key: string): string
  local cached = camelCache[key]

  if cached then return cached end

  local spelled = string.sub(key, 1, 1) .. string.gsub(string.sub(key, 2), '_(%l)', string.upper)
  camelCache[key] = spelled
  return spelled
end

local function unescape(escape: string, hex: string): string
  if escape == 'u' then return utf8.char(tonumber(hex, 16) :: number) end

  return (Escapes[escape] or escape) .. hex
end

local pending: { [Table]: { text: string, start: number, rawKeys: boolean } } = {}
setmetatable(pending, { __mode = 'k' })

-- A JSON value starting at `position` of `text`, and the position after it.
local function parse(text: string, position: number, rawKeys: boolean): (Value, number)
  local value: (position: number) -> (Value, number)

  -- The first backslash from `slashFrom` on, once one has been looked for there: a string that
  -- closes before it is the text between its quotes, and most of a document's are.
  local slashFrom, slash = 1, 0

  --- `string.find(text, '%S', position)`: where the text goes on after its whitespace, which
  --- between two values is spaces and line ends, found without a pattern.
  local function skip(position: number): number
    if not position then return string.find(text, '%S', position) :: number end

    local byte = string.byte(text, position)

    while byte == 32 or byte == 10 do
      position += 1
      byte = string.byte(text, position)
    end

    if byte and byte > 32 then return position end

    return string.find(text, '%S', position) :: number
  end

  local function readString(position: number): (string, number)
    local first = position + 1
    local quote = string.find(text, '"', first, true)

    if quote then
      if first < slashFrom or first > slash then
        slashFrom = first
        slash = string.find(text, '\\', first, true) or math.huge
      end

      if slash > quote then return string.sub(text, first, quote - 1), quote + 1 end
    end

    local stop = string.find(text, '["\\]', first) :: number

    if string.byte(text, stop) == 34 then return string.sub(text, first, stop - 1), stop + 1 end

    while string.byte(text, stop) == 92 do
      stop = string.find(text, '["\\]', stop + 2) :: number
    end

    local raw = string.sub(text, first, stop - 1)
    return (string.gsub(raw, '\\(.)(%x?%x?%x?%x?)', unescape)), stop + 1
  end

  function value(position: number): (Value, number)
    position = skip(position)
    local byte = string.byte(text, position)

    if byte == 123 then
      local object: Table = {}
      position = skip(position + 1)

      if string.byte(text, position) == 125 then return object, position + 1 end

      while true do
        local key: string, item: Value
        key, position = readString(position)

        if string.byte(text, position) ~= 58 then
          position = string.find(text, ':', position, true) :: number
        end

        item, position = value(position + 1)
        object[if rawKeys then key else camel(key)] = item
        position = skip(position)

        if string.byte(text, position) ~= 44 then return object, position + 1 end

        position = skip(position + 1)
      end
    elseif byte == 91 then
      local list: Table = {}
      local count = 0
      position = skip(position + 1)

      if string.byte(text, position) == 93 then return list, position + 1 end

      while true do
        local item: Value
        item, position = value(position)
        count += 1
        list[count] = item
        position = skip(position)

        if string.byte(text, position) ~= 44 then return list, position + 1 end

        position += 1
      end
    elseif byte == 34 then
      return readString(position)
    elseif byte == 116 then
      return true, position + 4
    elseif byte == 102 then
      return false, position + 5
    elseif byte == 110 then
      return jess.null, position + 4
    end

    -- A whole number of up to fifteen digits is worked out from its digits, exactly. Anything
    -- else that starts a number is read as text, and so is what is looked for past the text's
    -- end, where `position` is nil.
    if position and (byte == 45 or (byte >= 48 and byte <= 57)) then
      local negative = byte == 45
      local at = if negative then position + 1 else position
      local digit = if negative then string.byte(text, at) else byte
      local whole = 0

      while digit and digit >= 48 and digit <= 57 do
        whole = whole * 10 + (digit - 48)
        at += 1
        digit = string.byte(text, at)
      end

      local count = at - position - (if negative then 1 else 0)
      local fraction = digit == 46 or digit == 101 or digit == 69 or digit == 45 or digit == 43

      if digit and not fraction and count > 0 and count <= 15 then
        return if negative then -whole else whole, at
      end
    end

    local stop = string.find(text, '[^-+.%deE]', position) :: number
    return tonumber(string.sub(text, position, stop - 1)) :: number, stop
  end

  return value(position)
end

-- A JSON document (any value), with keys camelCase unless `rawKeys`.
function tes3conv.json(text: string, rawKeys: boolean?): Value
  return (parse(text, 1, rawKeys == true))
end

function tes3conv.decode(text: string, options: Options?): Records
  local lazy = options and options.lazy or {}
  local rawKeys = options ~= nil and options.rawKeys == true
  local records: Records = {}
  local position = string.find(text, '[', 1, true)

  if not position then error 'a tes3conv plugin is a JSON array of records' end

  -- tes3conv indents a record's fields four spaces, so "\n  }" closes a top-level record and
  -- nothing inside it. Records of a lazy type are found by that and read later.
  while true do
    local first = string.find(text, '[{%]]', position + 1) :: number

    if string.byte(text, first) == 93 then break end

    local kind = string.match(text, '^{%s*"type":%s*"(%w+)"', first)

    if kind and lazy[kind] then
      local stop = string.find(text, '\n  }', first, true)

      if not stop then
        error 'a lazily read tes3conv record must be indented as tes3conv writes it'
      end

      local stub: Table = { type = kind }
      pending[stub] = { text = text, start = first, rawKeys = rawKeys }
      table.insert(records, stub)
      position = stop + 4
    else
      local record: Value
      record, position = parse(text, first, rawKeys)
      table.insert(records, record :: Table)
    end

    position = string.find(text, '%S', position) :: number

    if string.byte(text, position) ~= 44 then break end
  end

  return records
end

function tes3conv.read(path: string, options: Options?): Records
  local text = jess.fs.read(path)

  if not text then error(`'{path}' doesn't exist`) end

  return tes3conv.decode(text, options)
end

function tes3conv.isLazy(record: Table): boolean return pending[record] ~= nil end

function tes3conv.realize(record: Table): Table
  local source = pending[record]

  if not source then return record end

  pending[record] = nil
  local full = parse(source.text, source.start, source.rawKeys) :: Table

  for key, item in full do
    record[key] = item
  end

  return record
end

-- The fields jess writes exactly as they are and tes3conv terminates with a NUL.
local ExactText: { [string]: string } = {
  Book = 'text',
  Class = 'description',
  DialogueInfo = 'scriptText',
  MagicEffect = 'description',
  Race = 'description',
  Script = 'text',
  Skill = 'description',
}

local function terminated(text: Value?): Value?
  if type(text) == 'string' and text ~= '' and string.byte(text, -1) ~= 0 then
    return text .. '\0'
  end

  return text
end

function tes3conv.prepare(record: Table): Table
  local kind = record.type
  local field = ExactText[kind :: string]

  if field then
    local text = record[field]
    local written = terminated(text)

    if written ~= text then
      record = table.clone(record)
      record[field] = written :: Value
    end
  elseif kind == 'GameSetting' then
    local setting = record.value :: Table

    if setting.type == 'String' then
      local written = terminated(setting.data)

      if written ~= setting.data then
        record = table.clone(record)
        local copy = table.clone(setting)
        copy.data = written :: Value
        record.value = copy
      end
    end
  elseif kind == 'Cell' then
    local references = record.references :: { Table }?

    if references then
      local copied: { Table } = table.clone(references)

      for index, reference in copied do
        if reference.objectCount ~= 1 or reference.mastIndex ~= 0 then continue end

        local trimmed = table.clone(reference)
        trimmed.objectCount = nil
        copied[index] = trimmed
      end

      tes3conv.sortReferences(copied)
      record = table.clone(record)
      record.references = copied
    end
  end

  return record
end

-- tes3's `Reference::persistent`: moved references and doors with destinations always are.
local function persistent(reference: Table): boolean
  return reference.movedCell ~= nil or reference.destination ~= nil or reference.temporary ~= true
end

tes3conv.isPersistent = persistent

-- Whether `left` goes before `right` in the order tes3 writes references.
local function before(left: Table, right: Table): boolean
  local leftPersistent, rightPersistent = persistent(left), persistent(right)

  if leftPersistent ~= rightPersistent then return leftPersistent end

  local leftMaster, rightMaster = left.mastIndex :: number, right.mastIndex :: number
  leftMaster = if leftMaster == 0 then math.huge else leftMaster
  rightMaster = if rightMaster == 0 then math.huge else rightMaster

  if leftMaster ~= rightMaster then return leftMaster < rightMaster end

  return (left.refrIndex :: number) < (right.refrIndex :: number)
end

-- References in the order tes3 writes them: persistent first, then the masters' by master and
-- index, then the plugin's own by index. The package encoder writes them in this order too.
function tes3conv.sortReferences(references: { Table }) table.sort(references, before) end

-- tes3conv sorts a plugin's records before it writes them (see `sort`).
function tes3conv.sort(records: Records): Records
  local sorted = table.clone(records)
  tes3.sortObjects(sorted)
  return sorted
end

-- A new plugin holding `records`, in their order: pass them through `sort` first for what
-- `tes3conv plugin.json plugin.esp` would write.
function tes3conv.plugin(records: Records): core.Plugin
  assert(records[1] and records[1].type == 'Header', 'tes3conv.plugin: records must start with a Header')
  local plugin = core.new()
  plugin:replaceBytes(0, plugin:encode((records[1] :: unknown) :: core.Value))

  for index = 2, #records do
    local record = tes3conv.prepare(records[index])
    plugin:insert(plugin:count(), plugin:encode((record :: unknown) :: core.Value))
  end

  return plugin
end

-- tes3's string loader stops at the first NUL; jess keeps the exact fields whole.
local function truncated(text: Value?): Value?
  if type(text) == 'string' then
    local nul = string.find(text, '\0', 1, true)

    if nul then return string.sub(text, 1, nul - 1) end
  end

  return text
end

-- The record at `index` of a plugin as tes3conv would have read it.
local function recordAt(plugin: core.Plugin, index: number): Table
  local decoded = plugin:decode(index)
  if not decoded then
    error(`record {index} ({plugin:tag(index)}) has a record type tes3conv can't read`)
  end

  local value = (decoded :: unknown) :: Table
  local field = ExactText[value.type :: string]

  if field then
    value[field] = truncated(value[field]) :: Value
  elseif value.type == 'GameSetting' then
    local setting = value.value :: Table

    if setting.type == 'String' then setting.data = truncated(setting.data) :: Value end
  end

  return value
end

-- A plugin's records as `tes3conv plugin.esp plugin.json` reads them, sorted as it sorts them,
-- and each record's bytes in the same order.
function tes3conv.recordsWithBytes(plugin: core.Plugin): (Records, { string })
  local records: Records, bytes: { string } = {}, {}

  for index = 0, plugin:count() - 1 do
    table.insert(records, recordAt(plugin, index))
    table.insert(bytes, buffer.tostring(plugin:bytes(index)))
  end

  local sortedRecords: Records, sortedBytes: { string } = {}, {}

  for position, from in tes3.sortPermutation(records) do
    sortedRecords[position] = records[from]
    sortedBytes[position] = bytes[from]
  end

  return sortedRecords, sortedBytes
end

function tes3conv.records(plugin: core.Plugin): Records return (tes3conv.recordsWithBytes(plugin)) end

-- A cell as tes3conv holds it once read: its references keyed by master and index, so the last
-- given with a pair is the one kept, in the order it writes them. The cell itself when its
-- references already are, as a plugin's are.
local function settled(cell: Table): Table
  local references = cell.references :: { Table }?

  if not references then return cell end

  local unique: { Table } = {}
  local positions: { [number]: number } = {}
  local tidy = true

  for index, reference in references do
    local master, own = reference.mastIndex, reference.refrIndex

    if type(master) ~= 'number' or type(own) ~= 'number' then
      error(`a reference of cell '{cell.name}' has no mast_index or refr_index`, 0)
    end

    local key = master * 16777216 + own
    local position = positions[key]

    if position then
      tidy = false
    else
      position = #unique + 1
      positions[key] = position
    end

    unique[position] = reference

    if index > 1 and not before(references[index - 1], reference) then tidy = false end
  end

  if tidy then return cell end

  table.sort(unique, before)
  local copy = table.clone(cell)
  copy.references = unique
  return copy
end

-- A sink that keeps what it is handed, and the pieces it has kept so far.
local function keeper(): (Sink, { string })
  local chunks: { string } = {}

  return function(chunk: buffer, length: number)
    table.insert(chunks, buffer.readstring(chunk, 0, length))
  end,
    chunks
end

-- The pieces a `keeper` kept as one string, put together in a buffer of its exact size: joining
-- a master's worth any other way leaves several times the text behind in buffers outgrown on
-- the way.
local function joined(chunks: { string }): string
  if #chunks == 1 then return chunks[1] end

  local size = 0

  for _, chunk in chunks do
    size += #chunk
  end

  local whole = buffer.create(size)
  local position = 0

  for _, chunk in chunks do
    buffer.writestring(whole, position, chunk)
    position += #chunk
  end

  return buffer.tostring(whole)
end

-- The records as tes3conv's JSON text, in their order: `records` gives a plugin's as tes3conv
-- writes them, and `sort` puts any others in that order. A record `decode` left unread is read.
function tes3conv.encode(records: Records, options: EncodeOptions?): string
  local sink, chunks = keeper()
  Encode.open(sink)
  Encode.begin(options ~= nil and options.compact == true)

  for _, record in records do
    tes3conv.realize(record)
    Encode.record(if record.type == 'Cell' then settled(record) else record)
  end

  Encode.finish()
  Encode.close()
  return joined(chunks)
end

function tes3conv.write(path: string, records: Records, options: EncodeOptions?)
  jess.fs.write(path, tes3conv.encode(records, options))
end

-- The record types whose place in tes3conv's order depends on nothing they hold (see
-- `tes3.sortPermutation`). They are most of a master's bytes.
local Unkeyed: { [string]: boolean } = {
  Header = true,
  Cell = true,
  Landscape = true,
  PathGrid = true,
  Dialogue = true,
  DialogueInfo = true,
}

-- Records to convert without holding them: how many there are, what places each in tes3conv's
-- order (`keys`, in the order they were found), and a read of the one at a position.
type Source = { count: number, keys: Records, read: (position: number) -> Table }

-- What of a record places it in tes3conv's order.
local function key(record: Table): Table
  if Unkeyed[record.type :: string] then return { type = record.type } end

  return {
    type = record.type,
    id = record.id,
    index = record.index,
    effectId = record.effectId,
    skillId = record.skillId,
  }
end

local function pluginSource(plugin: core.Plugin): Source
  local count = plugin:count()
  local keys: Records = table.create(count)

  for index = 0, count - 1 do
    local kind = core.typeName(plugin:tag(index))
    keys[index + 1] = if kind and Unkeyed[kind] then { type = kind } else key(recordAt(plugin, index))
  end

  return {
    count = count,
    keys = keys,
    read = function(position: number): Table return recordAt(plugin, position - 1) end,
  }
end

-- How much of a document is looked through at a time.
local Window = 262144

local function inMemory(text: string): Text
  return {
    size = #text,
    read = function(offset: number, length: number): string
      return string.sub(text, offset + 1, offset + length)
    end,
  }
end

-- Where each record of a document is: the offset of its `{`, and its length. The document is
-- stepped through a window at a time, looking only at its strings and brackets: nothing is
-- read into tables, and no more than a window is held. Outside a string it is stepped through
-- a byte at a time; a string, which a landscape's or a script's can be most of a window, is
-- stepped over by where the next quote and the next backslash are, each looked for once.
local function spans(document: Text): ({ number }, { number })
  local starts: { number }, lengths: { number } = {}, {}
  local depth, offset = 0, 0
  local quoted, escaped, closed = false, false, false

  while offset < document.size and not closed do
    local window = buffer.fromstring(document.read(offset, Window))
    local size = buffer.len(window)
    local position = 0
    local quote, slash = -1, -1

    -- A backslash that ended the last window escapes the character that starts this one.
    if escaped then
      position = 1
      escaped = false
    end

    while position < size do
      if quoted then
        if quote < position then quote = bytes.find(window, '"', position) or size end

        if slash < position then slash = bytes.find(window, '\\', position) or size end

        local at = math.min(quote, slash)
        if at == size then break end

        quoted = at == slash
        escaped = quoted and at == size - 1
        position = if quoted then at + 2 else at + 1
        continue
      end

      local byte = buffer.readu8(window, position)
      position += 1

      if byte ~= 34 and byte ~= 91 and byte ~= 93 and byte ~= 123 and byte ~= 125 then
        -- Outside the records there is only the array's own punctuation.
        if depth >= 2 or byte == 32 or (byte >= 9 and byte <= 13) then continue end

        if depth == 0 then error('a tes3conv plugin is a JSON array of records', 0) end

        if byte ~= 44 then
          error(`the document has something that isn't a record where record {#starts + 1} would be`, 0)
        end

        continue
      end

      if depth == 0 and byte ~= 91 then error('a tes3conv plugin is a JSON array of records', 0) end

      if byte == 34 then
        if depth < 2 then error(`record {#starts + 1} of the document isn't an object`, 0) end

        quoted = true
      elseif byte == 123 or byte == 91 then
        if depth == 1 then
          if byte ~= 123 then error(`record {#starts + 1} of the document isn't an object`, 0) end

          table.insert(starts, offset + position - 1)
        end

        depth += 1
      else
        depth -= 1

        if depth == 1 then
          lengths[#starts] = offset + position - starts[#starts]
        elseif depth <= 0 then
          closed = true
          break
        end
      end
    end

    offset += size

    if size == 0 then break end
  end

  if closed then return starts, lengths end

  if depth >= 2 then error(`the document ends inside record {#starts}`, 0) end

  error(
    if depth == 0
      then 'a tes3conv plugin is a JSON array of records'
      else 'the document ends without closing its array',
    0
  )
end

-- A document's records, unread: where each is in the text is all that is kept of them, with
-- the keys that order them. A record's tables are made from its own stretch of the text when
-- it is wanted, and let go.
local function documentSource(document: Text): Source
  local starts, lengths = spans(document)
  local keys: Records = table.create(#starts)

  for ordinal, start in starts do
    local length = lengths[ordinal]
    local kind = string.match(document.read(start, math.min(length, 64)), '^{%s*"type":%s*"(%w+)"')

    if kind and Unkeyed[kind] then
      keys[ordinal] = { type = kind }
      continue
    end

    local record = parse(document.read(start, length), 1, false) :: Table

    if type(record.type) ~= 'string' then error(`record {ordinal} of the document has no type`, 0) end

    keys[ordinal] = key(record)
  end

  return {
    count = #starts,
    keys = keys,
    read = function(place: number): Table
      return parse(document.read(starts[place], lengths[place]), 1, false) :: Table
    end,
  }
end

local function sourceOf(source: core.Plugin | string | Text): Source
  if type(source) == 'string' then return documentSource(inMemory(source)) end

  -- A plugin has no `read` of its own; a text is its size and its `read`.
  local fields = (source :: unknown) :: { [string]: unknown }

  if type(rawget(fields, 'read')) == 'function' then return documentSource(source :: Text) end

  return pluginSource(source :: core.Plugin)
end

-- Writes a plugin, or a tes3conv document, as the JSON text tes3conv writes for it, handing it to
-- `sink` a chunk at a time, and returns how many records it wrote. A document is its text, or a
-- `Text` that reads it a stretch at a time, which need never be held whole. Each record is read,
-- written, and let go: what is held is the source, the keys that order its records, and one
-- chunk. The chunk is at most a megabyte, and is only the bytes the sink is told of until the
-- sink returns.
function tes3conv.transcribeTo(
  source: core.Plugin | string | Text,
  sink: Sink,
  options: EncodeOptions?
): number
  local from = sourceOf(source)
  Encode.open(sink)
  Encode.begin(options ~= nil and options.compact == true)

  for _, position in tes3.sortPermutation(from.keys) do
    local record = from.read(position)
    Encode.record(if record.type == 'Cell' then settled(record) else record)
  end

  Encode.finish()
  Encode.close()
  return from.count
end

-- A plugin as the JSON text `tes3conv plugin.esp plugin.json` writes: `encode(records(plugin))`
-- without holding every record at once, though the whole text is held to be returned.
function tes3conv.transcribe(plugin: core.Plugin, options: EncodeOptions?): string
  local sink, chunks = keeper()
  tes3conv.transcribeTo(plugin, sink, options)
  return joined(chunks)
end

-- The file type tes3 gives the header of a plugin it saves under a name with this extension.
local FileTypes: { [string]: string } = { esp = 'Esp', esm = 'Esm' }

-- The header tes3conv writes in place of `header` over `count` records, itself among them,
-- into a file of this name: one that counts the records after it and has the file type an
-- `.esp` or `.esm` name stands for.
local function headed(header: Table, count: number, fileName: string?): Table
  local copy = table.clone(header)
  local extension = string.match(string.lower(fileName or ''), '%.([^./\\]+)$')
  copy.numObjects = count - 1
  copy.fileType = FileTypes[extension or ''] or copy.fileType
  return copy
end

-- The plugin `tes3conv plugin.json <fileName>` writes from a document's records. Without a file
-- name, or with one that is neither an `.esp` nor an `.esm`, the header keeps its file type.
function tes3conv.compile(records: Records, fileName: string?): core.Plugin
  local sorted = tes3conv.sort(records)
  local first = sorted[1]

  if first and first.type == 'Header' then
    sorted[1] = headed(tes3conv.realize(first), #sorted, fileName)
  end

  for index = 2, #sorted do
    local record = tes3conv.realize(sorted[index])

    if record.type == 'Cell' then sorted[index] = settled(record) end
  end

  return tes3conv.plugin(sorted)
end

-- Writes the plugin `compile` builds, from a plugin or from a tes3conv document (its text, or a
-- `Text`), handing its bytes to `sink` a chunk at a time, and returns how many records it wrote:
-- what `compile(...):save()` holds, without holding it. A document's records are read from it
-- one at a time, written, and let go.
function tes3conv.compileTo(
  source: core.Plugin | string | Text,
  sink: Sink,
  fileName: string?
): number
  local from = sourceOf(source)
  local order = tes3.sortPermutation(from.keys)
  local first = order[1]

  if not first or from.keys[first].type ~= 'Header' then
    error('tes3conv.compileTo: records must start with a Header', 0)
  end

  Encode.open(sink)

  for place, position in order do
    local record = from.read(position)

    if place == 1 then
      record = headed(record, from.count, fileName)
    else
      record = tes3conv.prepare(if record.type == 'Cell' then settled(record) else record)
    end

    Encode.bytes(core.encode((record :: unknown) :: core.Value))
  end

  Encode.close()
  return from.count
end

return tes3conv
