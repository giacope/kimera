# q05_sorted_versions

`SemVer#<=>` (via `Comparable`) runs at load time: `Releases::SUPPORTED` is sorted and frozen, and
`OLDEST`/`NEWEST` are taken with `min`/`max`, all while `lib/releases.rb` is required. A change to `<=>` or
`compare_pre` only reorders those constants when the file is loaded again; `sort`, `min`, `max`, `between?`
and `clamp` call `<=>` from C. `bump` with an unknown part and some `compare_pre` edges are left untested.
