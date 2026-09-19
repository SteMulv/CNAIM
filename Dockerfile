FROM rocker/r-ver:4.3.3

WORKDIR /app

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libicu-dev \
    libsodium-dev \
    libuv1-dev \
    libssl-dev \
    libxml2-dev \
    pkg-config \
    zlib1g-dev \
  && rm -rf /var/lib/apt/lists/*

COPY DESCRIPTION NAMESPACE ./
COPY R ./R
COPY data ./data
COPY inst ./inst
COPY man ./man
COPY plumber.R ./plumber.R

RUN R -q -e 'install.packages(c("plyr", "dplyr", "jsonlite", "magrittr", "ggplot2", "stringr", "tibble", "r2d3", "plumber"), repos="https://cloud.r-project.org", dependencies=c("Depends", "Imports", "LinkingTo")); stopifnot(requireNamespace("plumber", quietly=TRUE))' \
  && R CMD INSTALL /app \
  && R -q -e 'stopifnot(requireNamespace("plumber", quietly=TRUE), requireNamespace("CNAIM", quietly=TRUE)); cat("Docker runtime packages verified\n")'

EXPOSE 8000

CMD ["R", "-q", "-e", "pr <- plumber::plumb(\"plumber.R\"); pr$run(host=\"0.0.0.0\", port=8000)"]
