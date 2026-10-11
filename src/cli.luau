--!strict
--!native
--[[
@tes3conv/cli: tes3conv's command line, over @tes3conv/commands.

  parse(argv) -> (command, nil) | (nil, message)
  render(result) -> text
  status(result) -> exit status
  run(argv) -> exit status

  tes3conv [-c] [-o] <INPUT> [OUTPUT]

The arguments and flags are tes3conv 0.4.1's. `parse` reads an argument list into the request
`commands.convert` takes without touching a file, or says what it couldn't read. A flag is
spelled `--name` or `-n`, flags can share a dash (`-co`), each can be given once, and `--` ends
them. `render` is what the program prints for a result: the JSON of a conversion that named no
output, and nothing for one that did, since tes3conv says nothing when it has written a file.
`run` does the rest: it parses, converts, and writes, handing the JSON to standard output a chunk
at a time rather than holding it.

Where this command line differs from the original's:

  - `-` as INPUT, standard input, is refused by name: Jess gives a script nothing that reads it.
  - Exit statuses are Jess's: 8 where the original gives 2 (an unknown or repeated flag, a
    missing or extra argument, a file of a kind it doesn't convert, an input that isn't there)
    and 9 where it gives 1 (an input that isn't a plugin or a document, a record that can't be
    converted, a backup or an output that can't be written). An output whose folder is missing
    is 8 here and 1 there.
  - Messages are this package's, as `tes3conv: <message>` on standard error; with no arguments
    the usage is printed there, as the original prints its help.
  - An input that starts with neither `TES3` nor `[` is refused. The original takes any file
    starting with `T` for a plugin and reads what it can of it.

Everything `@tes3conv` says of its own differences holds here too.
]]

local commands = require '@tes3conv/commands'
local process = require '@dream/process'

export type Command = { command: 'help' } | { command: 'convert', request: commands.ConvertRequest }

local Exit = table.freeze { ok = 0, invalidInput = 8, runtime = 9 }

local Usage = [[
tes3conv 0.4.1 for Jess: convert TES3 plugins (.esp) into JSON files (.json), and vice-versa.

Usage: tes3conv [OPTIONS] <INPUT> [OUTPUT]
       tes3conv "test.esp" "test.json"

Arguments:
  <INPUT>   Sets the input file: a plugin or a JSON document, whichever its first bytes say.
  [OUTPUT]  Sets the output file: JSON under a .json name, a plugin under an .esp, .esm, or
            .omwaddon name. Omit to print JSON to standard output.

Options:
  -c, --compact    Compact json output (skip indentation).
  -o, --overwrite  Overwrite output without making backups.
  -h, --help       Print help

Without --overwrite, a file already at OUTPUT is first copied to <name>.000.<extension>, or the
first of .001 to .999 that is free.

Not part of this port: - as INPUT, which reads standard input.

Exit status: 0 done, 8 the command line can't be used, 9 the conversion failed.]]

--- The flags, by their long names, and the request field each sets.
local Flags: { [string]: string } = { compact = 'compact', overwrite = 'overwrite' }

--- The flags' short forms, by the letter each is.
local Short: { [string]: string } = { ['c'] = 'compact', ['o'] = 'overwrite', ['h'] = 'help' }

local function out(text: string) process.write('stdout', `{text}\n`) end

local function err(text: string) process.write('stderr', `{text}\n`) end

local function usage(message: string): number
  err(`tes3conv: {message}`)
  return Exit.invalidInput
end

local function parse(argv: { string }): (Command?, string?)
  local request: commands.ConvertRequest = { input = '' }
  local given: { [string]: boolean } = {}
  local positional: { string } = {}
  local flagsEnded = false

  --- Sets what the flag named `name` stands for, or says why it can't be.
  local function take(name: string, spelling: string): string?
    local field = Flags[name]
    if not field then return `unknown option '{spelling}'` end

    if given[field] then return `{spelling} can be given only once` end

    given[field] = true

    if field == 'compact' then
      request.compact = true
    else
      request.overwrite = true
    end

    return nil
  end

  for _, argument in argv do
    if flagsEnded or argument == '-' or string.sub(argument, 1, 1) ~= '-' then
      table.insert(positional, argument)
    elseif argument == '--' then
      flagsEnded = true
    elseif string.sub(argument, 1, 2) == '--' then
      local name, value = string.match(argument, '^%-%-([^=]*)=(.*)$')

      if name == 'help' or argument == '--help' then return { command = 'help' :: 'help' }, nil end

      if name and Flags[name] then return nil, `--{name} takes no value, not '{value}'` end

      local refusal = take(string.sub(argument, 3), argument)
      if refusal then return nil, refusal end
    else
      for position = 2, #argument do
        local letter = string.sub(argument, position, position)
        local name = Short[letter]

        if name == 'help' then return { command = 'help' :: 'help' }, nil end

        local refusal = take(name or '', `-{letter}`)
        if refusal then return nil, refusal end
      end
    end
  end

  if #positional == 0 then return nil, 'an input file is required' end

  if #positional > 2 then return nil, `unexpected argument '{positional[3]}'` end

  if positional[1] == '-' then
    return nil,
      'reading standard input (- as the input) is not part of this port: Jess gives a script nothing that reads it; name a file'
  end

  request.input = positional[1]

  -- The original takes an empty OUTPUT for none.
  if positional[2] and positional[2] ~= '' then request.output = positional[2] end

  return { command = 'convert' :: 'convert', request = request }, nil
end

--- What the program prints for a result: the converted JSON when it was kept for that, and
--- nothing when it went to a file or a sink.
local function render(result: commands.ConvertResult): string return result.bytes or '' end

--- A conversion that came back was done.
local function status(_result: commands.ConvertResult): number return Exit.ok end

local function run(argv: { string }): number
  -- The original prints its help on standard error when it is given nothing.
  if #argv == 0 then
    err(Usage)
    return Exit.invalidInput
  end

  local command, message = parse(argv)
  if not command then return usage(message :: string) end

  if command.command == 'help' then
    out(Usage)
    return Exit.ok
  end

  local request = table.clone(command.request)
  local refusal = commands.check(request)
  if refusal then return usage(refusal) end

  if not request.output then
    request.sink = function(chunk: buffer, length: number)
      local wrote, unwritten = process.write('stdout', buffer.readstring(chunk, 0, length))
      if not wrote then error(`standard output can't be written: {unwritten}`, 0) end
    end
  end

  -- `convert` raises when the request can't be carried out: an input that is neither a plugin
  -- nor a document, a record that can't be converted, a backup or an output that can't be
  -- written.
  local converted, result = pcall(commands.convert, request)

  if not converted then
    err(`tes3conv: {result}`)
    return Exit.runtime
  end

  local text = render(result)
  if text ~= '' then process.write('stdout', text) end

  return status(result)
end

return table.freeze {
  Exit = Exit,
  parse = parse,
  render = render,
  run = run,
  status = status,
}
