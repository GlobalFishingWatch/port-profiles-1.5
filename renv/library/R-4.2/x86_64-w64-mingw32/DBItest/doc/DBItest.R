## ----setup, include = FALSE---------------------------------------------------
knitr::opts_chunk$set(error = (getRversion() < "3.5"))

## ----make-context, error = !rlang::is_installed("RSQLite")--------------------
library(DBItest)

tweaks <- tweaks(
  constructor_relax_args = TRUE,
  placeholder_pattern = c("?", "$1", "$name", ":name"),
  date_cast = function(x) paste0("'", x, "'"),
  time_cast = function(x) paste0("'", x, "'"),
  timestamp_cast = function(x) paste0("'", x, "'"),
  logical_return = function(x) as.integer(x),
  date_typed = FALSE,
  time_typed = FALSE,
  timestamp_typed = FALSE
)

default_skip <- c("roundtrip_date", "roundtrip_timestamp")

invisible(make_context(
  new(
    "DBIConnector",
    .drv = RSQLite::SQLite(),
    .conn_args = list(dbname = tempfile("DBItest", fileext = ".sqlite"))
  ),
  tweaks = tweaks,
  default_skip = default_skip
))

## ----simple, error = !rlang::is_installed("RSQLite")--------------------------
DBItest::test_some("get_query_atomic")

## ----location, error = !rlang::is_installed("RSQLite")------------------------
testthat::with_reporter(
  c("location", "fail"),
  DBItest::test_some("get_query_atomic")
)

