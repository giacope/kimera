# q10_catch_throw_outline

`Outline.section` keeps a process-wide stack, leaves early via `catch(:skip_section)` / `throw` from
`skip!`, and pops in an `ensure`. Several examples only assert from inside the block, so a section left
open is often noticed only by a later example, such as `top_level_spec.rb`, which pushes nothing itself
and just checks that the stack is empty. Whether such a leak is caught depends on what runs afterwards.
