## ---- include = FALSE---------------------------------------------------------
knitr::opts_chunk$set(eval = FALSE)

## -----------------------------------------------------------------------------
#  install.packages("precommit")

## -----------------------------------------------------------------------------
#  # once in every git repo either
#  # * after cloning a repo that already uses pre-commit or
#  # * if you want introduce pre-commit to this repo
#  precommit::use_precommit()

## ---- echo = FALSE, eval = TRUE-----------------------------------------------
knitr::include_graphics(here::here("man/figures/screenshot.png"))

## -----------------------------------------------------------------------------
#  uninstall_precommit("repo") # just for the repo you are in.
#  uninstall_precommit("user") # remove the pre-commit conda executable.

