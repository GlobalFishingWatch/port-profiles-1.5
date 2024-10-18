## ---- echo = FALSE, output = "asis", comment = "", message = FALSE------------
library(magrittr)
rev <- paste0("v", packageVersion("precommit"))
cat(glue::glue("
repos:
-   repo: https://github.com/lorenzwalthert/precommit
    rev: {rev}
    hooks:
    -   id: lintr
        args: [--warn-only, --key=value]
"))

## ---- echo = FALSE, comment = ""----------------------------------------------
readLines(system.file("pre-commit-hooks.yaml", package = "precommit")) %>%
  gsub("^ *exclude *: *>", "    exclude: |", .) %>%
  yaml::yaml.load() %>%
  purrr::keep(~ .x$id == "spell-check") %>%
  magrittr::extract2(1) %>%
  magrittr::extract2("exclude") %>%
  cat(sep = "\n")

