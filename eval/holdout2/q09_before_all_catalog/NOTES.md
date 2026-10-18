# q09_before_all_catalog

The success path of the parser (building each `Item`, tag normalisation, the euro/cent arithmetic, the
keyword_init `Struct`'s blank-stock default) runs only inside a `before(:all)` hook, outside any example;
examples assert on what it built. Examples in `parse_errors_spec.rb` reach the same methods only up to a
`raise`. The hook sets a class-level `Item.default_stock` that is never reset, and examples mutate the
shared `@catalog` (restock, add).
