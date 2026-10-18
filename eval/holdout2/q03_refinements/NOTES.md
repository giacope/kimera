# q03_refinements

`String`/`Integer` refinements defined in `refinements.rb` and activated with `using` in a different
file (`headline.rb`) and at the top of one spec file. Refined methods are invisible to `respond_to?`/`send`
and only resolve lexically in files that ran `using`, so re-evaluating the refinement body is the only way
to change what `headline.rb` sees. Slugs are de-duplicated through a process-wide `Hash.new(0)` counter.
