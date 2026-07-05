Added the following user-visible functionality:

  * Made the `Zee3.Solver` public
  * Standardize passing `Smt2` values instead of string
    into `Zee3.Solver`
  * Add the `Zee3.Smt2.from_ex/1` macro to create SMT2
    values from elixir code (this is expecially is useful
    to generate simple data for testing)

Refactores the infrastructure code in the `Zee3.program/2` macro.