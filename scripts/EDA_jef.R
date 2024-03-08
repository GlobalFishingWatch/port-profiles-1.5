install.packages("tidyverse")
library(tidyverse)

conakry_max <- read.csv("data/conakry_max.csv", header = T, sep = ",") %>% as_tibble()

conakry_max %>% group_by(visit_id) %>% summarise(n = n())
conakry_max %>% group_by(ssvid) %>% summarise(n = n()) %>% View()

conakry_max$start_timestamp <- dmy_hm(conakry_max$start_timestamp)
conakry_max$end_timestamp <- dmy_hm(conakry_max$end_timestamp)
