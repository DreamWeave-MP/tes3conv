# tes3conv benchmarks

`bench/bench.luau` times the package through its public API: a document read into record tables,
record tables written as a document, both conversions held and streamed, and the two orders
tes3conv puts things in. Its inputs are `@tes3`'s every-type plugin with its golden documents
(80 records, 49 KB as a plugin, 103 KB as indented JSON), a cell of 4,096 references placed at
f32s that take eight or nine digits (1.26 MB indented, 614 KB compact), and a list of 8,192
records with only what orders them. Each workload is warmed up, sized to a batch of about a tenth
of a second, and reported as the median of seven batches, with a full collection between them.
Every call's result is checked against a count, a byte total, or a checksum of the order it made.

```sh
jess run --package jpk/tes3conv --package-path jpk --capability filesystem.read \
  jpk/tes3conv/bench/bench.luau [filter]
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
