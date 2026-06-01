Add support for using the datalog engine that ships with Z3
(μZ - An Efficient Engine for Fixed-Points with Constraints)
by adding the `rule(...)`, `query(...)` and `query!(...)` functions.
This also required adding support for the new `Zee3.Sort.entity_id()`
sort and the `entity_id(...)` special function.