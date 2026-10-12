# tes3conv benchmarks

`bench/bench.luau` times the package through its public API: a document read into record tables,
record tables written as a document, both conversions held and streamed, and the two orders
tes3conv puts things in. Its inputs are `@tes3`'s every-type plugin with its golden documents
(80 records, 49 KB as a plugin, 103 KB as indented JSON), a cell of 4,096 references placed at
f32s that take eight or nine digits (1.26 MB indented, 614 KB compact), and a list of 8,192
records with only what orders them. Each workload is warmed up, sized to a batch of about a tenth of a second, and
reported as the median of seven batches, with a full collection between them. Every call's result
is checked against a count, a byte total, or a checksum of the order it made.

```sh
jess run --package jpk/tes3conv --package-path jpk --capability filesystem.read \
  jpk/tes3conv/bench/bench.luau [filter]
```

## The move onto l3i 2.0, base against head

- Machine: Intel Core i7-10870H @ 2.20 GHz, 16 threads, shared with other work while this ran.
- Date: 2026-10-12.
- Binary: the verified release build of Jess 0.1.0 on l3i 2.0.0 (Luau 0.742), the same one for
  both sides, and the same `@tes3` beside both.
- Base: `8f98522`, the package before the move, with this bench. Head: `23514a4`.
- Protocol: the whole bench run against base, then head, five times over, back to back under one
  lock; each cell is the median of its five runs. A difference under 5 percent is called no
  change.

| Workload | Base | Head | Base / head |
|---|---:|---:|---:|
| decode all_types.json | 2.265 ms | 1.201 ms | 1.89x |
| decode all_types.compact.json | 1.977 ms | 911.4 µs | 2.17x |
| decode all_types.json, cells and dialogue lazy | 1.159 ms | 749.2 µs | 1.55x |
| decode a cell of 4096 references | 37.656 ms | 19.847 ms | 1.90x |
| decode a cell of 4096 references, compact | 30.521 ms | 13.704 ms | 2.23x |
| encode all_types | 513.2 µs | 479.9 µs | 1.07x |
| encode all_types, compact | 488.6 µs | 454.8 µs | 1.07x |
| encode a cell of 4096 references | 16.320 ms | 14.367 ms | 1.14x |
| encode a cell of 4096 references, compact | 15.147 ms | 13.125 ms | 1.15x |
| records of all_types.esp | 463.6 µs | 427.7 µs | 1.08x |
| transcribe all_types.esp | 1.198 ms | 1.145 ms | no change |
| transcribeTo from all_types.json | 5.713 ms | 2.774 ms | 2.06x |
| transcribeTo from a cell of 4096 references | 79.415 ms | 40.890 ms | 1.94x |
| compile all_types | 928.1 µs | 845.3 µs | 1.10x |
| compile a cell of 4096 references | 13.261 ms | 7.093 ms | 1.87x |
| compileTo from all_types.json | 5.997 ms | 3.012 ms | 1.99x |
| compileTo from all_types.esp | 1.518 ms | 1.439 ms | 1.05x |
| compileTo from a cell of 4096 references | 77.743 ms | 34.836 ms | 2.23x |
| sort 8192 records | 9.711 ms | 3.197 ms | 3.04x |
| sortPermutation of 8192 records | 9.518 ms | 2.852 ms | 3.34x |
| sortReferences, 4096 in order | 4.678 ms | 256.0 µs | 18.27x |
| sortReferences, 4096 shuffled | 5.945 ms | 552.7 µs | 10.76x |
| sortReferences, 256 lists of 16 in order | 1.642 ms | 310.7 µs | 5.28x |
| sortReferences, 256 lists of 16 shuffled | 1.822 ms | 560.0 µs | 3.25x |
| deepCopy and equal over all_types | 233.5 µs | 223.9 µs | no change |
| replaceNoCase over all_types.json | 250.0 µs | 250.4 µs | no change |

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
row that starts from a plugin, where the time is `@tes3`'s decoding and that writer. The gains of
5 to 10 percent on the every-type rows are at the edge of what this machine could tell apart
while it was shared.
