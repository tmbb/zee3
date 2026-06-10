# Zee3 Changelog

<!-- %% CHANGELOG_ENTRIES %% -->

## 0.5.0 - 2026-06-10

Added the following functionality:

  * Variadic `and` and variadic `or` operators (named `all/1` and `any/1`, respectively)
  * Add an implementation of finite sets based on existing theories (i.e. it doesn't
    define a new thoeory of objects that satisfy the axioms of set theory)


## 0.4.0 - 2026-06-01

Add support for using the datalog engine that ships with Z3
(μZ - An Efficient Engine for Fixed-Points with Constraints)
by adding the `rule(...)`, `query(...)` and `query!(...)` functions.
This also required adding support for the new `Zee3.Sort.entity_id()`
sort and the `entity_id(...)` special function.


## 0.3.0 - 2026-05-04

Add support for defining *real* Z33 functions using the `defzee3` macro from the `Zee3.Defzee3` module. These functions are real Z3 functions and not merely Elixir functions which expand into Z3 code.

See the tests for example usage of this function.


## 0.2.0 - 2026-05-02

First public release
