library(CNAIM)
library(jsonlite)

pof_schema_version <- "1.0"
pof_asset_type <- "6.6/11kV Transformer (GM)"
allowed_origins <- c(
  "https://www.stevenmulvenna.com",
  "https://stevenmulvenna.com",
  "http://localhost:3000"
)

#* Restrict browser access to the known frontend origins and handle preflight requests.
#* @filter cors
function(req, res) {
  origin <- req$HTTP_ORIGIN
  if (!is.null(origin) && origin %in% allowed_origins) {
    res$setHeader("Access-Control-Allow-Origin", origin)
    res$setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Request-ID")
    res$setHeader("Vary", "Origin")
  }

  if (identical(req$REQUEST_METHOD, "OPTIONS")) {
    res$status <- 204
    return(list())
  }

  plumber::forward()
}

request_id_for <- function(req = NULL) {
  supplied_id <- if (!is.null(req)) req$HTTP_X_REQUEST_ID else NULL
  if (is.character(supplied_id) && length(supplied_id) == 1L && nzchar(supplied_id)) {
    return(supplied_id)
  }
  paste0("local-", format(Sys.time(), "%Y%m%d%H%M%OS3"))
}

log_request <- function(request_id, method, path, status, started_at, error_code = NULL) {
  log_entry <- list(
    timestamp = format(Sys.time(), tz = "UTC", usetz = TRUE),
    request_id = request_id,
    method = method,
    path = path,
    status = status,
    duration_ms = round((proc.time()[["elapsed"]] - started_at) * 1000, 2),
    error_code = error_code
  )
  tryCatch(
    cat(jsonlite::toJSON(log_entry, auto_unbox = TRUE, null = "null"), "\n", file = stdout()),
    error = function(error) invisible(NULL)
  )
}

pof_error <- function(code, message, field = NULL, status = 400, request_id = NULL) {
  response <- list(
    schema_version = pof_schema_version,
    error = list(
      code = code,
      message = message,
      field = field,
      request_id = if (is.null(request_id)) request_id_for() else request_id
    )
  )
  list(status = status, body = response)
}

is_scalar_number <- function(value) {
  is.numeric(value) && length(value) == 1L && is.finite(value)
}

normalise_optional <- function(value) {
  if (is.null(value)) "Default" else value
}

validate_request <- function(payload, request_id = NULL) {
  if (!is.list(payload)) {
    return(pof_error("INVALID_REQUEST", "Request body must be a JSON object.", request_id = request_id))
  }
  allowed_top_level_fields <- c("schema_version", "asset_id", "asset_type", "survey")
  unknown_top_level_fields <- setdiff(names(payload), allowed_top_level_fields)
  if (length(unknown_top_level_fields) > 0L) {
    field <- unknown_top_level_fields[[1L]]
    return(pof_error("UNSUPPORTED_FIELD", paste("Unsupported request field:", field), field, request_id = request_id))
  }
  if (!identical(payload$schema_version, pof_schema_version)) {
    return(pof_error("INVALID_REQUEST", "schema_version must be the string 1.0.", "schema_version", request_id = request_id))
  }
  if (!is.character(payload$asset_id) || length(payload$asset_id) != 1L || !nzchar(trimws(payload$asset_id))) {
    return(pof_error("INVALID_REQUEST", "asset_id must be a non-empty string.", "asset_id", request_id = request_id))
  }
  if (!identical(payload$asset_type, pof_asset_type)) {
    return(pof_error("INVALID_FIELD", "asset_type is not supported in this release.", "asset_type", request_id = request_id))
  }
  if (!is.list(payload$survey)) {
    return(pof_error("INVALID_REQUEST", "survey must be a JSON object.", "survey", request_id = request_id))
  }

  allowed_fields <- c(
    "utilisation_pct", "placement", "altitude_m", "distance_from_coast_km",
    "corrosion_category_index", "age", "partial_discharge", "oil_acidity",
    "temperature_reading", "observed_condition", "reliability_factor",
    "moisture", "bd_strength"
  )
  unknown_fields <- setdiff(names(payload$survey), allowed_fields)
  if (length(unknown_fields) > 0L) {
    return(pof_error("UNSUPPORTED_FIELD", paste("Unsupported survey field:", unknown_fields[[1L]]), paste0("survey.", unknown_fields[[1L]]), request_id = request_id))
  }
  if (is.null(payload$survey$age) || !is_scalar_number(payload$survey$age) || payload$survey$age < 0) {
    return(pof_error("INVALID_FIELD", "survey.age must be a number greater than or equal to 0.", "survey.age", request_id = request_id))
  }

  numeric_rules <- list(
    utilisation_pct = c(0, 100),
    altitude_m = c(0, Inf),
    distance_from_coast_km = c(0, Inf),
    oil_acidity = c(0, Inf),
    reliability_factor = c(0, Inf),
    moisture = c(0, Inf),
    bd_strength = c(0, Inf)
  )
  for (field in names(numeric_rules)) {
    value <- payload$survey[[field]]
    if (!is.null(value) && (!is_scalar_number(value) || value < numeric_rules[[field]][[1L]] || value > numeric_rules[[field]][[2L]])) {
      return(pof_error("INVALID_FIELD", paste0("survey.", field, " has an invalid number."), paste0("survey.", field), request_id = request_id))
    }
  }

  if (!is.null(payload$survey$corrosion_category_index) &&
      (!is.numeric(payload$survey$corrosion_category_index) ||
       length(payload$survey$corrosion_category_index) != 1L ||
       !is.finite(payload$survey$corrosion_category_index) ||
       payload$survey$corrosion_category_index %% 1 != 0 ||
       payload$survey$corrosion_category_index < 1 ||
       payload$survey$corrosion_category_index > 5)) {
    return(pof_error("INVALID_FIELD", "survey.corrosion_category_index must be an integer from 1 to 5.", "survey.corrosion_category_index", request_id = request_id))
  }

  allowed_values <- list(
    placement = c("Indoor", "Outdoor", "Default"),
    partial_discharge = c("Low", "Medium", "High (Not Confirmed)", "High (Confirmed)", "Default"),
    temperature_reading = c("Normal", "Moderately High", "Very High", "Default"),
    observed_condition = c("No deterioration", "Superficial/minor deterioration", "Slight deterioration", "Some Deterioration", "Substantial Deterioration", "Default")
  )
  for (field in names(allowed_values)) {
    value <- payload$survey[[field]]
    if (!is.null(value) && (!is.character(value) || length(value) != 1L || !(value %in% allowed_values[[field]]))) {
      return(pof_error("INVALID_FIELD", paste0("survey.", field, " has an unsupported value."), paste0("survey.", field), request_id = request_id))
    }
  }
  NULL
}

#* Health check for local development and deployment probes.
#* @get /health
#* @serializer json list(auto_unbox = TRUE)
function(req, res) {
  started_at <- proc.time()[["elapsed"]]
  request_id <- request_id_for(req)
  log_request(request_id, "GET", "/health", 200, started_at)
  list(status = "ok", service = "cnaim-pof-api")
}

#* Return API and CNAIM package version information.
#* @get /version
#* @serializer json list(auto_unbox = TRUE)
function(req, res) {
  started_at <- proc.time()[["elapsed"]]
  request_id <- request_id_for(req)
  log_request(request_id, "GET", "/version", 200, started_at)
  list(
    api_schema_version = pof_schema_version,
    service = "cnaim-pof-api",
    engine = "CNAIM",
    engine_version = as.character(packageVersion("CNAIM"))
  )
}

#* Calculate PoF and current health score for an 11 kV to 400 V transformer.
#* @post /api/v1/pof/transformers
#* @serializer json list(auto_unbox = TRUE)
function(req, res) {
  started_at <- proc.time()[["elapsed"]]
  request_id <- request_id_for(req)
  payload <- tryCatch(
    jsonlite::fromJSON(req$postBody, simplifyVector = FALSE),
    error = function(error) NULL
  )
  validation_error <- validate_request(payload, request_id)
  if (!is.null(validation_error)) {
    res$status <- validation_error$status
    log_request(request_id, "POST", "/api/v1/pof/transformers", validation_error$status, started_at, validation_error$body$error$code)
    return(validation_error$body)
  }

  survey <- payload$survey
  result <- tryCatch(
    pof_transformer_11_20kv(
      hv_transformer_type = payload$asset_type,
      utilisation_pct = normalise_optional(survey$utilisation_pct),
      placement = normalise_optional(survey$placement),
      altitude_m = normalise_optional(survey$altitude_m),
      distance_from_coast_km = normalise_optional(survey$distance_from_coast_km),
      corrosion_category_index = normalise_optional(survey$corrosion_category_index),
      age = survey$age,
      partial_discharge = normalise_optional(survey$partial_discharge),
      oil_acidity = normalise_optional(survey$oil_acidity),
      temperature_reading = normalise_optional(survey$temperature_reading),
      observed_condition = normalise_optional(survey$observed_condition),
      reliability_factor = normalise_optional(survey$reliability_factor),
      moisture = normalise_optional(survey$moisture),
      bd_strength = normalise_optional(survey$bd_strength)
    ),
    error = function(error) error
  )
  if (inherits(result, "error")) {
    res$status <- 422
    log_request(request_id, "POST", "/api/v1/pof/transformers", 422, started_at, "CALCULATION_INPUT_ERROR")
    return(pof_error("CALCULATION_INPUT_ERROR", "The survey could not be processed by CNAIM.", status = 422, request_id = request_id)$body)
  }

  log_request(request_id, "POST", "/api/v1/pof/transformers", 200, started_at)
  list(
    schema_version = pof_schema_version,
    asset_id = payload$asset_id,
    asset_type = payload$asset_type,
    result = list(pof = unname(result$pof[[1L]]), chs = unname(result$chs[[1L]])),
    calculation = list(engine = "CNAIM", engine_version = as.character(packageVersion("CNAIM")))
  )
}
