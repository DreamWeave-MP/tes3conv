# tes3conv benchmarks

`bench/bench.jsl` times the package through its public API: a document read into record tables,
record tables written as a document, both conversions held and streamed, and the two orders
tes3conv puts things in. Its inputs are `@tes3`'s every-type plugin with its golden documents
(80 records, 49 KB as a plugin, 103 KB as indented JSON), a cell of 4,096 references placed at
f32s that take eight or nine digits (1.26 MB indented, 614 KB compact), and a list of 8,192
records with only what orders them. Each workload is warmed up, sized to a batch of about a tenth
of a second, and reported as the median of seven batches, with a full collection between them.
Every call's result is checked against a count, a byte total, or a checksum of the order it made.

```sh
jess run --package jpk/tes3conv --package-path jpk --capability filesystem.read \
  jpk/tes3conv/bench/bench.jsl [filter]
```

## The move onto l3i 2.0, base against head

- Machine: Intel Core i7-10870H @ 2.20 GHz, 16 threads, shared with other work while this ran.
- Date: 2026-10-12.
- Binary: the verified release build of Jess 0.1.0 on l3i 2.0.1 (Luau 0.742), the same one for
  both sides, and the same `@tes3` beside both, which took one commit during the first of the
  five rounds.
- Base: `8f98522`, the package before the move, with this bench. Head: `d2aa0da`.
- Protocol: the whole bench run against base, then head, five times over, back to back under one
  lock; each cell is the median of its five runs. A difference under 5 percent is called no
  change.

| Workload | Base | Head | Base / head |
|---|---:|---:|---:|
| decode all_types.json | 2.152 ms | 1.227 ms | 1.75x |
| decode all_types.compact.json | 1.873 ms | 930.6 µs | 2.01x |
| decode all_types.json, cells and dialogue lazy | 1.090 ms | 754.1 µs | 1.45x |
| decode a cell of 4096 references | 35.881 ms | 19.855 ms | 1.81x |
| decode a cell of 4096 references, compact | 28.716 ms | 13.921 ms | 2.06x |
| encode all_types | 485.5 µs | 487.7 µs | no change |
| encode all_types, compact | 465.3 µs | 464.1 µs | no change |
| encode a cell of 4096 references | 15.527 ms | 14.308 ms | 1.09x |
| encode a cell of 4096 references, compact | 14.417 ms | 13.357 ms | 1.08x |
| records of all_types.esp | 448.4 µs | 423.8 µs | 1.06x |
| transcribe all_types.esp | 1.166 ms | 1.146 ms | no change |
| transcribeTo from all_types.json | 5.422 ms | 2.749 ms | 1.97x |
| transcribeTo from a cell of 4096 references | 75.975 ms | 41.152 ms | 1.85x |
| compile all_types | 926.9 µs | 871.2 µs | 1.06x |
| compile a cell of 4096 references | 12.365 ms | 7.009 ms | 1.76x |
| compileTo from all_types.json | 5.735 ms | 3.030 ms | 1.89x |
| compileTo from all_types.esp | 1.490 ms | 1.465 ms | no change |
| compileTo from a cell of 4096 references | 73.789 ms | 35.141 ms | 2.10x |
| sort 8192 records | 9.323 ms | 3.145 ms | 2.96x |
| sortPermutation of 8192 records | 9.124 ms | 2.868 ms | 3.18x |
| sortReferences, 4096 in order | 4.510 ms | 253.7 µs | 17.78x |
| sortReferences, 4096 shuffled | 5.723 ms | 554.7 µs | 10.32x |
| sortReferences, 256 lists of 16 in order | 1.570 ms | 304.7 µs | 5.15x |
| sortReferences, 256 lists of 16 shuffled | 1.738 ms | 544.7 µs | 3.19x |
| deepCopy and equal over all_types | 226.4 µs | 224.2 µs | no change |
| replaceNoCase over all_types.json | 254.3 µs | 241.3 µs | no change |

What moved, and why. None of it is the dialect's syntax: the comprehensions, the reducer, and the
record patterns this package took are in code that runs once a module or once a plan, and measure
as nothing. Reading a document is about twice as fast because the parser stopped calling the
pattern matcher for things a byte says: whitespace is stepped over in a loop, a string with no
backslash before its closing quote is taken by a plain search for the quote, and a number of up to
fifteen digits is worked out from its digits, a decimal by one division that rounds as `tonumber`
does. The streamed conversions of a document gain that and more, because finding where each
record is went from a pattern search per bracket and quote to a byte loop over a buffer that steps
over strings with `@dream/bytes`' `find`. The orders are the data plane: a record's place is one
f64, its id ranked first by a sort of the distinct ids, and a reference's place is one f64
outright, each sorted by one stable `@dream/data` `argsort` in place of `table.sort` with a
comparator; a list of references already in order, which is what a plugin and a tes3conv document
hold, is found to be in one pass and not sorted at all. That, and telling a cell's references are
settled from the same places, is what the cell rows of `encode` and `compile` gained. The
`sortReferences` rows include the bench's own copy of the list and its checksum.

What did not move: writing JSON, which already went digit by digit into one buffer, and every
row that starts from a plugin, where the time is `@tes3`'s decoding and that writer. The every-type
rows of `encode` came out even. The 6 percent on `records` and on `compile all_types` is at the
edge of what this machine could tell apart while it was shared, and `records` had rounds on both
sides of even: neither is claimed. `replaceNoCase`, whose code is as it was, read 5 percent ahead
the same way.

## One change at a time

Each change made for speed against the commit before it, on the rows it touches: three rounds
back to back under one lock, the median of the three, same binary and day. Between one of these
runs and the next the machine's load moved the same code by up to 5 percent, so they don't
multiply out to the table above any closer than that.

| Change | Rows | Before / after |
|---|---|---:|
| `e8433a4`, a document's records found a byte at a time in a buffer | `transcribeTo` and `compileTo` from a document | 1.24x to 1.28x |
| `4ca85a9`, whitespace, plain strings, colons, and whole numbers read without a pattern | `decode` of all_types | 1.64x, 1.90x compact, 1.43x lazy |
| | `decode` of the cell | 1.35x, 1.40x compact |
| `693145c`, a decimal divided out of its digits | `decode` of all_types | 1.10x, 1.12x compact, lazy no change |
| | `decode` of the cell | 1.36x, 1.53x compact |
| `6d39e60`, records ordered by `argsort` | `sort`, `sortPermutation` | 2.94x, 3.11x |
| `c8b5b0c`, references ordered by `argsort`, a list in order left alone | `sortReferences` | 16.98x and 9.87x on 4,096, 5.00x and 3.07x on lists of 16 |
| | `compile` and `compileTo` of the cell | 1.45x, 1.13x |
| `23514a4`, a cell's references told to be settled from their places | `encode` of the cell | 1.17x, both forms |
| | `compile`, `transcribeTo`, `compileTo` of the cell | 1.23x, 1.10x, 1.09x |

## Which modules are native, and why

Jess compiles to machine code only what is marked (`--!native` on a module, `@native` on one
function), and every load pays for what is marked. A module carries `--!native` when a row below
spends its time there and the module is small (12 KB or less); a larger module carries `@native`
on the functions the row spends its time in, and nothing else.

Measured 2026-10-15 with `jess 0.1.0`, the verified release build of jess `07c38cb` on l3i
2.0.3, on the i7-10870H, the one-minute load 1.02 and 1.46 at the start of the two
sessions. In each session the bench ran alternately on this package and on a copy of it with
every module marked, three fresh runs of `bench/bench.jsl` each, every run's row the median of
its batches; a column is the median of the three, and a ratio is against the all-marked runs of
the same session. Which functions a row spends its time in comes from `jess run --profile` of
that row alone, unmarked. The load cost is a fresh `jess run --package <this package>
--package-path jpk` of a script that only requires `@tes3conv`, the two sides alternating, the
median of five each after one warm-up.

| Requiring `@tes3conv` | All marked | This state |
| --- | ---: | ---: |
| Unmarked | 0.108 s | 0.096 s |
| Final | 0.124 s | 0.119 s |

| Row | All marked (ms) | Unmarked / all marked | Final (ms) | Final / all marked |
| --- | ---: | ---: | ---: | ---: |
| decode all_types.json | 1.288 | **2.174×** | 1.303 | 1.012× |
| decode all_types.compact.json | 0.9660 | **2.036×** | 0.9911 | 1.026× |
| decode all_types.json, cells and dialogue lazy | 0.7955 | **2.082×** | 0.8288 | 1.042× |
| decode a cell of 4096 references | 20.52 | **2.786×** | 20.37 | 0.993× |
| decode a cell of 4096 references, compact | 14.54 | **2.567×** | 14.11 | 0.971× |
| encode all_types | 0.5037 | **2.155×** | 0.5070 | 1.007× |
| encode all_types, compact | 0.4744 | **2.165×** | 0.4842 | 1.021× |
| encode a cell of 4096 references | 15.10 | **3.011×** | 15.75 | 1.043× |
| encode a cell of 4096 references, compact | 13.91 | **3.148×** | 14.43 | 1.037× |
| records of all_types.esp | 0.5344 | 1.025× | 0.5401 | 1.011× |
| transcribe all_types.esp | 1.321 | **1.481×** | 1.379 | 1.043× |
| transcribeTo from all_types.json | 3.013 | **2.772×** | 2.956 | 0.981× |
| transcribeTo from a cell of 4096 references | 43.14 | **3.812×** | 42.79 | 0.992× |
| compile all_types | 1.093 | 1.018× | 1.097 | 1.003× |
| compile a cell of 4096 references | 9.173 | **1.125×** | 9.608 | 1.047× |
| compileTo from all_types.json | 3.408 | **2.445×** | 3.264 | 0.958× |
| compileTo from all_types.esp | 1.873 | 1.048× | 1.858 | 0.992× |
| compileTo from a cell of 4096 references | 38.38 | **3.624×** | 38.56 | 1.005× |
| sort 8192 records | 3.610 | **1.621×** | 3.578 | 0.991× |
| sortPermutation of 8192 records | 3.083 | **1.626×** | 3.071 | 0.996× |
| sortReferences, 4096 in order | 0.3736 | **2.660×** | 0.3665 | 0.981× |
| sortReferences, 4096 shuffled | 0.6962 | **2.213×** | 0.7004 | 1.006× |
| sortReferences, 256 lists of 16 in order | 0.4530 | **2.434×** | 0.4621 | 1.020× |
| sortReferences, 256 lists of 16 shuffled | 0.7200 | **2.141×** | 0.6937 | 0.963× |
| deepCopy and equal over all_types | 0.2525 | **1.560×** | 0.2544 | 1.008× |
| replaceNoCase over all_types.json | 0.2767 | 1.006× | 0.2941 | **1.063×** |

What carries the directive (every module and function here is one a row spends its time in,
unmarked):

- Whole: `encode`, `records`.
- `init`, by function: `skip`, `readString`, `value`, `tes3conv.sortReferences`, `spans`.
- Unmarked: `cli`, `commands`, `main`, `schema`.

Marked by function first, encoding, transcribing, and compiling stayed 1.05x to 1.10x slower than
all marked, and a real conversion is a whole plugin, seconds long, where that ratio outweighs what
a load saves; so `encode` and `records` are marked whole. `cli` and `main` parse a command line
once a run and are never marked. The one row still above 5%, `replaceNoCase` over a JSON text
(1.063x, of a 0.3 ms call), is inside this protocol's noise: two all-marked copies of
dream-archive, measured the same way, put 10 of 109 rows more than 5% apart, the 95th percentile
at 1.074x.
