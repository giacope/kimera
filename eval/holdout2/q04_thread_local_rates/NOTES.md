# q04_thread_local_rates

Cross rates are memoised in `Thread.current[:fx_cache]` (fiber-local storage), which nothing clears
between examples; one example seeds the cache directly and leaves the entry behind. Whichever example
first asks for a pair computes it; every later example in the same thread/fiber reads the memo, so a
change to the rate arithmetic is only seen by the first example to touch that pair in a fresh process.
