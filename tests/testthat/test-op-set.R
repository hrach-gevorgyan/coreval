
test_that("contains_all compares row by row when a side is a collection", {
  # The reference has two paths: row-by-row when both sides are columns of
  # iterables, dataset-level otherwise. coreval only had the second, so a rule
  # whose comparator is one collection PER ROW - split_by gives PPSPEC rows a
  # list of specimens each - got a single verdict landed on row 1, and
  # CORE-000934 reported nothing at all.
  allowed <- c("LIVER", "KIDNEY", "LUNG")

  # Per-row: each row's own parts against the allowed set.
  ctx <- list(exists = TRUE, n = 3L, target = allowed,
              value = list(c("LIVER"), c("LIVER", "SPLEEN"), c("KIDNEY", "LUNG")))
  expect_equal(get_operator("contains_all")(ctx), c(TRUE, FALSE, TRUE))
  expect_equal(get_operator("not_contains_all")(ctx), c(FALSE, TRUE, FALSE))

  # Dataset-level shape is unchanged: one verdict, reported on the first row.
  flat <- list(exists = TRUE, n = 3L, target = allowed, value = c("LIVER", "KIDNEY"))
  expect_equal(get_operator("contains_all")(flat), c(TRUE, FALSE, FALSE))
  missing <- list(exists = TRUE, n = 3L, target = allowed, value = c("LIVER", "SPLEEN"))
  expect_equal(get_operator("not_contains_all")(missing), c(TRUE, FALSE, FALSE))
})

test_that("split_by gives each row its own list of parts", {
  dt <- data.table::data.table(PPSPEC = c("LIVER", "LIVER;KIDNEY", ""))
  b <- compute_operation(
    list(operator = "split_by", id = "$parts", name = "PPSPEC", delimiter = ";"),
    list(datasets = list(PP = list(data = dt))), "PP", list(data = dt)
  )
  expect_equal(b$kind, "per_row")
  expect_equal(b$value[[2]], c("LIVER", "KIDNEY"))
  expect_error(
    compute_operation(list(operator = "split_by", id = "$x", name = "PPSPEC"),
                      list(datasets = list()), "PP", list(data = dt)),
    "needs a delimiter"
  )
})
