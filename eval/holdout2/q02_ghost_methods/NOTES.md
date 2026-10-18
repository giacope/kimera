# q02_ghost_methods

`method_missing` / `respond_to_missing?` accessors that, on first use, `define_method` a real method on the
class. After the first example calls `settings.timeout`, every later call (in any example) bypasses
`method_missing`, `parse` and `coerce`'s dispatch setup, so only the example that happened to call an
accessor first exercises the ghost path; the class is permanently changed for the rest of the process.
