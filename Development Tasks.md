# Development Tasks

## Recommended architecture

The website should feel like one site to visitors, even though it contains several applications.

```text
Visitor
  |
  v
Home page: biography, political writing, applications
  |
  v
Shared login and user account
  |
  +--> CNAIM application frontend --> CNAIM API --> CNAIM R engine
  |
  +--> Future application frontend --> Future application API
  |
  +--> Future application frontend --> Future application API
```

### In plain language

- There should be one website domain, such as `example.com`.
- The home page, navigation, login screen, user account page, and common visual style should be shared.
- A user logs in once and then sees the applications they are allowed to use.
- Each application should open as its own area of the website, for example `example.com/apps/cnaim`.
- The CNAIM R package remains the calculation engine. It should be placed behind a small authenticated API rather than exposed directly to the internet.
- The frontend must never contain database passwords, AWS credentials, or unrestricted R code.
- The backend APIs should be private or protected by the shared login token. Users should never connect directly to the R process or database.

## Repository recommendation

Use your existing static-pages repository as the shared frontend repository. Do not create a second frontend repository for this stage.

```text
existing-static-site-repo/
  home/
  authentication/
  shared-navigation/
  shared-design-system/
  apps/
    cnaim/
    future-app-1/
```

This is easier to understand and keeps login, navigation, permissions, and styling consistent. Each app remains in its own folder with clear boundaries.

Use separate backend repositories when an app has its own API or calculation engine:

```text
CNAIM/                 # Existing R algorithm package
cnaim-api/             # Authenticated API around CNAIM
future-app-1-api/      # Backend for another application
existing-static-site-repo/ # Shared frontend and homepage
infrastructure/        # Optional AWS deployment configuration
```

A separate frontend repository for every app is possible, but it adds complexity: several deployments, duplicated login integration, duplicated navigation, and more work to keep the user experience consistent. It becomes worthwhile only when different apps have separate teams, very different technologies, or completely independent release schedules.

## Content approach

Start with the biography and political writing as content managed in the frontend repository, using Markdown or structured content files. This is simple, version-controlled, and inexpensive.

Add a headless CMS later if non-technical editing is needed. The applications and user data should not be stored in the public frontend repository.

## Access and security model

- Use one identity provider, such as Amazon Cognito, for user accounts and passwords.
- Use HTTPS everywhere.
- Give each user an authenticated access token after login.
- Require that token for every protected API request.
- Define permissions such as administrator, editor, and app user.
- Check permissions on the server as well as hiding or showing links in the frontend.
- Run APIs and databases in private AWS network resources where practical.
- Store secrets in AWS Secrets Manager, never in frontend code or Git.
- Record which user created or changed each asset survey and calculation.

## Delivery plan

### Phase 1: Confirm the existing engine

- [x] Install R and the CNAIM dependencies in a development environment.
- [x] Install the local CNAIM package.
- [x] Run the CNAIM test suite.
- [x] Document the supported CNAIM input fields and output values.
- [x] Decide which CNAIM calculations the first application will support.

#### Phase 1 Task 5 proposal: first application scope

The first application should support one complete transformer survey workflow before adding other asset types. This keeps the first version understandable and gives us one end-to-end process to test.

The first version should support:

1. A survey form for an 11 kV to 400 V distribution transformer.
2. Current probability of failure and current health score using `pof_transformer_11_20kv()`.
3. A clear result showing `pof` and `chs`.
4. Saving the survey inputs and the returned PoF result for the authorised user.

The first survey form should focus on an 11 kV to 400 V distribution transformer. In CNAIM, this asset is represented by the `6.6/11kV Transformer (GM)` category. It should use the fields documented in the `CNAIM Survey Data Reference` section at the end of this document, with CNAIM defaults available where the surveyor does not have a measurement.

Do not include consequence of failure, risk-matrix coordinates, risk-matrix visualisation, future probability-of-failure simulations, Weibull modelling, custom reference data, or other asset families in the first release. Those can be added after the first PoF workflow has been tested with real survey data.

### Phase 2: Define the application contract

#### Confirmed scope boundary for the next phase

The next phase will define the API contract for PoF only. The API will accept survey data for the 11 kV to 400 V distribution transformer and return the current probability of failure (`pof`) and current health score (`chs`). It will not accept or return consequence-of-failure or risk-matrix data yet.

- [x] Design the JSON format sent from the frontend to the CNAIM API.
- [x] Design the JSON format returned by the CNAIM API.
- [x] Define validation rules for every survey field.
- [x] Define consistent error messages for invalid or incomplete surveys.
- [x] Decide which data must be saved and which results can be recalculated.


#### Phase 2 Task 1: Fixed PoF API request definition

**HTTP call:** `POST /api/v1/pof/transformers`

The frontend sends one JSON object for each surveyed 11 kV to 400 V transformer. The following is the fixed request definition for the first release:

| JSON path | Data type | Required? | Default when omitted or `null` |
| --- | --- | --- | --- |
| `schema_version` | String | Yes | None; the API rejects the request |
| `asset_id` | String | Yes | None; the API rejects the request |
| `asset_type` | String | Yes | None; the API rejects the request unless it is `6.6/11kV Transformer (GM)` |
| `survey.utilisation_pct` | Number | No | R value `Default` |
| `survey.placement` | String | No | R value `Default` |
| `survey.altitude_m` | Number | No | R value `Default` |
| `survey.distance_from_coast_km` | Number | No | R value `Default` |
| `survey.corrosion_category_index` | Integer | No | R value `Default` |
| `survey.age` | Number | Yes | None; the API rejects the request |
| `survey.partial_discharge` | String | No | R value `Default` |
| `survey.oil_acidity` | Number | No | R value `Default` |
| `survey.temperature_reading` | String | No | R value `Default` |
| `survey.observed_condition` | String | No | R value `Default` |
| `survey.reliability_factor` | Number | No | R value `Default` |
| `survey.moisture` | Number | No | R value `Default` |
| `survey.bd_strength` | Number | No | R value `Default` |

For numeric fields, the JSON type is `Number` when a measurement is available and `null` when it is not. The API converts missing or `null` optional fields to the literal R value `Default`. This means `Default` is an internal R-package value, not a string that the frontend needs to send.

Fixed request example:

```json
{
  "schema_version": "1.0",
  "asset_id": "Transformer_11kV_400V_001",
  "asset_type": "6.6/11kV Transformer (GM)",
  "survey": {
    "utilisation_pct": 55,
    "placement": "Indoor",
    "altitude_m": 75,
    "distance_from_coast_km": 20,
    "corrosion_category_index": 2,
    "age": 25,
    "partial_discharge": "Low",
    "oil_acidity": 0.1,
    "temperature_reading": "Normal",
    "observed_condition": null,
    "reliability_factor": null,
    "moisture": null,
    "bd_strength": null
  }
}
```

The API maps `asset_type` to the `hv_transformer_type` argument used by `pof_transformer_11_20kv()`. The advanced `gb_ref_given` argument must not be accepted from the frontend. The API should reject unknown fields, unsupported categories, invalid numbers, missing `asset_id`, missing `asset_type`, missing `survey`, or missing `survey.age`. Authentication details belong in the HTTP request, not in this JSON body.

#### Phase 2 Task 2: Fixed PoF API response definition

**Successful response:** HTTP `200 OK` from `POST /api/v1/pof/transformers`

The API returns one JSON object containing the original asset identity and the two PoF results produced by `pof_transformer_11_20kv()`:

| JSON path | Data type | Meaning | Unit or format |
| --- | --- | --- | --- |
| `schema_version` | String | Response contract version | For example `1.0` |
| `asset_id` | String | Surveyed asset identifier | Matches the request |
| `asset_type` | String | CNAIM asset category | `6.6/11kV Transformer (GM)` |
| `result.pof` | Number | Current probability of failure | Per annum; multiply by 100 for a percentage |
| `result.chs` | Number | Current health score | CNAIM health-score value |
| `calculation.engine` | String | Calculation engine name | `CNAIM` |
| `calculation.engine_version` | String | Installed CNAIM package version | For example `2.1.4` |

Fixed response example:

```json
{
  "schema_version": "1.0",
  "asset_id": "Transformer_11kV_400V_001",
  "asset_type": "6.6/11kV Transformer (GM)",
  "result": {
    "pof": 0.0002950815,
    "chs": 1.273101
  },
  "calculation": {
    "engine": "CNAIM",
    "engine_version": "2.1.4"
  }
}
```

The response must not include consequence-of-failure values, risk-matrix coordinates, passwords, access tokens, or raw internal R objects. Error responses will be defined separately in the validation and error-handling tasks.

#### Phase 2 Task 3: PoF request validation rules

The API must validate the request before calling R. Invalid values should produce a client error and must not be silently changed into a default.

| JSON path | Validation rule |
| --- | --- |
| `schema_version` | Must be the string `1.0`. |
| `asset_id` | Must be a non-empty string identifying the asset. |
| `asset_type` | Must exactly equal `6.6/11kV Transformer (GM)` in the first release. |
| `survey` | Must be an object. Unknown fields are rejected. |
| `survey.utilisation_pct` | If supplied, must be a number from 0 to 100. |
| `survey.placement` | If supplied, must be `Indoor`, `Outdoor`, or `Default`. |
| `survey.altitude_m` | If supplied, must be a number greater than or equal to 0. |
| `survey.distance_from_coast_km` | If supplied, must be a number greater than or equal to 0. |
| `survey.corrosion_category_index` | If supplied, must be an integer from 1 to 5. |
| `survey.age` | Required; must be a number greater than or equal to 0. |
| `survey.partial_discharge` | If supplied, must be `Low`, `Medium`, `High (Not Confirmed)`, `High (Confirmed)`, or `Default`. |
| `survey.oil_acidity` | If supplied, must be a number greater than or equal to 0. |
| `survey.temperature_reading` | If supplied, must be `Normal`, `Moderately High`, `Very High`, or `Default`. |
| `survey.observed_condition` | If supplied, must be a documented CNAIM condition category or `Default`. |
| `survey.reliability_factor` | If supplied, must be a finite number greater than or equal to 0. |
| `survey.moisture` | If supplied, must be a number greater than or equal to 0. |
| `survey.bd_strength` | If supplied, must be a number greater than or equal to 0. |

For every optional field, omitted and `null` have the same meaning: convert to the R value `Default`. The required fields `schema_version`, `asset_id`, `asset_type`, `survey`, and `survey.age` must be present and non-null. The API must also reject `NaN`, infinite numbers, negative measurements, unsupported text categories, and a request body that is not valid JSON.

#### Phase 2 Task 4: PoF API error responses

The API should use one consistent error format so the frontend can show a useful message to the surveyor and developers can diagnose the problem. Error responses must not expose passwords, access tokens, stack traces, or internal R details.

| HTTP status | Error code | Use when |
| --- | --- | --- |
| `400 Bad Request` | `INVALID_JSON` | The request body is not valid JSON. |
| `400 Bad Request` | `INVALID_REQUEST` | A required top-level field is missing or has the wrong type. |
| `400 Bad Request` | `INVALID_FIELD` | A survey field has an invalid number, range, or text value. |
| `400 Bad Request` | `UNSUPPORTED_FIELD` | The request contains a field not in the fixed API contract. |
| `401 Unauthorized` | `AUTHENTICATION_REQUIRED` | No valid login token was supplied. |
| `403 Forbidden` | `ACCESS_DENIED` | The user is authenticated but is not allowed to use the CNAIM app. |
| `404 Not Found` | `ENDPOINT_NOT_FOUND` | The requested API path does not exist. |
| `409 Conflict` | `DUPLICATE_ASSET` | The `asset_id` conflicts with an existing asset where duplicates are not allowed. |
| `422 Unprocessable Entity` | `CALCULATION_INPUT_ERROR` | The request passed basic validation but cannot be processed by the CNAIM calculation. |
| `500 Internal Server Error` | `CALCULATION_FAILED` | An unexpected server-side calculation or infrastructure error occurred. |

Fixed error response format:

```json
{
  "schema_version": "1.0",
  "error": {
    "code": "INVALID_FIELD",
    "message": "survey.utilisation_pct must be a number from 0 to 100.",
    "field": "survey.utilisation_pct",
    "request_id": "req_01HZZZZZZZZZZZZZZZZZZZZZZZ"
  }
}
```

The `message` should be safe to show to the user. The optional `field` identifies the form field that needs attention. The `request_id` allows support staff to find the server log entry without returning technical details to the browser. Error messages should not reveal whether a password, token, database record, or other protected resource exists.

#### Phase 2 Task 5: Data to save and data to recalculate

For the first PoF release, the system should save enough information to show the survey history and reproduce the result later.

Save for each submitted survey:

- The authenticated user ID and organisation ID, if organisations are enabled.
- The asset ID and CNAIM asset type.
- The complete normalised survey input, including fields converted to R's `Default` value.
- The original submission time and the last update time.
- The returned `pof` and `chs` result snapshot.
- The API schema version, CNAIM package version, and calculation request ID.
- The survey status, such as `draft`, `submitted`, or `superseded`.

Do not save passwords, access tokens, or unnecessary sensitive information in the survey record.

The API may recalculate `pof` and `chs` when the user explicitly requests a new calculation, when a draft is submitted, or when a later CNAIM engine version is being evaluated. A recalculation must create a new result snapshot rather than silently overwriting the previous result. This preserves the historical result and makes changes between CNAIM versions visible.

The first release should not calculate consequence of failure, risk-matrix values, or future simulations. Those calculations can be added later with their own versioned result records.



### Phase 3: Build the CNAIM backend API

- [x] Create a small Plumber API around approved CNAIM functions.
- [x] Expose only named, validated operations; never accept arbitrary R code.
- [x] Add API health and version endpoints.
- [x] Add automated API tests using representative asset data.
- [x] Add Docker packaging for the R API.
- [x] Add structured logging without recording passwords or unnecessary personal data.
- [x] Rebuild and fully test the Docker API and structured logging.

#### Phase 3 Task 1 implementation note

Install only Plumber and its required dependencies for this API. Do not install every optional dependency from unrelated R packages, because that creates a large native-compilation chain and can cause timeouts without being needed by the PoF endpoint.

#### Phase 3 Task 2 implementation note

The current API exposes only the named `POST /api/v1/pof/transformers` operation and the `GET /health` probe. The PoF endpoint accepts the fixed transformer request, validates its fields, maps it to `pof_transformer_11_20kv()`, and returns only the agreed `pof` and `chs` values. It does not accept arbitrary R code, arbitrary function names, or out-of-scope consequence and risk calculations.

#### Phase 3 Task 3 implementation note

Task 3 will provide two operational endpoints: `GET /health` for a simple availability check and `GET /version` for the API schema and CNAIM package versions. These endpoints do not perform asset calculations.

#### Phase 3 Task 4 implementation note

Automated API tests should exercise the endpoints over HTTP rather than calling the R functions directly. The minimum test set is: health returns `200`, version returns the API and engine versions, a representative transformer survey returns `200` with numeric `pof` and `chs`, and invalid or unsupported fields return the documented `400` error response.

The automated smoke test is located at `tests/api-smoke-test.sh`. It starts a temporary local API on port `8001`, runs the HTTP checks, and stops the temporary server when finished.

#### Phase 3 Task 5 implementation note

Docker packaging should contain only the CNAIM package, the Plumber API, and the dependencies required by the API. The container should listen on port `8000`; authentication, private networking, and production secrets remain deployment concerns for later tasks.

The Docker image was built and tested successfully. The package verification, container startup, health, version, PoF, and invalid-field tests all passed.

#### Phase 3 Task 6 implementation note

Structured logging should record request IDs, endpoint, HTTP method, response status, duration, and safe error codes. It must not record passwords, access tokens, complete survey payloads, or unnecessary personal information.

#### Phase 3 Task 7 implementation note

The Docker verification script is located at `tests/docker-api-test.sh`. From the repository root, run `chmod +x tests/docker-api-test.sh && tests/docker-api-test.sh`. It rebuilds the image without cache, verifies `plumber` and `CNAIM` inside the image, starts the container, tests health, version, PoF, and validation errors, then checks Docker logs for request metadata and confirms survey data is not logged. This task remains open until that command passes and is manually confirmed.

### Phase 4: Deploy the CNAIM API to AWS development

The static website is already live on AWS, so this phase deploys the CNAIM Docker API separately as a development backend. The goal is to give the existing frontend a stable live API to call while the CNAIM screens are being built.

- [x] Create a non-root IAM deployment identity for development.
- [x] Choose the AWS development region and naming convention.
- [x] Create an Amazon ECR repository for the CNAIM API image.
- [x] Build the current Docker image and push it to ECR.
- [ ] Run the image in Amazon ECS Express Mode for development, backed by AWS Fargate.
- [ ] Keep the API private where possible, behind API Gateway or an internal load balancer.
- [ ] Configure the development API hostname and HTTPS.
- [ ] Configure CORS to allow requests from the existing live website domain.
- [ ] Configure health checks for `/health` and version checks for `/version`.
- [ ] Test the deployed PoF endpoint with the existing Postman/curl test payload.
- [ ] Confirm logs are available and do not contain survey payloads, tokens, or passwords.

#### Phase 4 Task 1 implementation note

Use `eu-west-2` (Europe/London) as the initial AWS development region. This is a development default for the UK-focused CNAIM project and must be confirmed against the existing static website's AWS regin before resources are created.

Use lowercase, hyphen-separated names with the environment between the project and resource name:

| Resource | Name |
| --- | --- |
| ECR repository | `cnaim-dev-api` |
| ECS cluster | `cnaim-dev` |
| ECS service | `cnaim-dev-api` |
| Container name | `cnaim-api` |
| CloudWatch log group | `/cnaim/dev/api` |
| Development API hostname | `api-dev.<existing-site-domain>` |

Tag resources with `Project=CNAIM`, `Environment=development`, and `ManagedBy=manual` until infrastructure as code is introduced. Do not create AWS resources or send sensitive survey data until the region and account are confirmed.

AWS App Runner is not an option for this new deployment because AWS stopped accepting new App Runner customers on April 30, 2026. Use Amazon ECS Express Mode for the initial managed container deployment. It provides a simplified ECS setup while retaining an upgrade path to standard ECS services and Fargate networking when the application needs private networking, authentication, or more detailed operational controls.

#### Phase 4 progress note

The development region is `eu-west-2` (Europe/London), and the account was verified in AWS CloudShell. The ECR repository `cnaim-dev-api` was created successfully with immutable image tags and default AES-256 encryption. The repository is currently empty; the next deployment step is to build the Docker image and push a versioned tag such as `v0.1.0`.

The initial CloudShell check used the AWS root identity. Root must not be used for routine deployment. Create and use a non-root IAM deployment identity before pushing images or creating ECS resources. Do not create long-lived root access keys.

The image `cnaim-dev-api:v0.1.0` was built from the `cnaim-api` repository (CNAIM commit `7418b6b149d5886a130f8e66de6a51f822e60f7c`) and pushed to `158074571041.dkr.ecr.eu-west-2.amazonaws.com/cnaim-dev-api:v0.1.0`, digest `sha256:13a453c4c2a2d71651b3b6904fd3a223d0fc7705c26161e94b12ecbc479bdcf2`. The next step is to run this image in Amazon ECS Express Mode.

#### Phase 4 IAM deployment identity checklist

1. Sign in to the AWS Console as root only to create the initial non-root identity, then stop using root for deployment.
2. Prefer an IAM Identity Center user and a development permission set when IAM Identity Center is available. For a standalone development account, an IAM user named `cnaim-deployer-dev` can be used temporarily.
3. Grant only the permissions required for ECR image upload and ECS Express Mode deployment. The deployment identity may also need `iam:PassRole` for the ECS task-execution and infrastructure roles created by Express Mode.
4. Require multi-factor authentication and do not create root access keys.
5. Configure CloudShell or the local AWS CLI to use the non-root identity, then confirm `aws sts get-caller-identity` no longer reports `:root`.
6. Review and reduce the deployment permissions after the development service is running. Use a separate, narrower runtime role for the ECS service.

#### Phase 4 scope boundary

This phase deploys the existing PoF-only CNAIM API for development testing. It does not add the frontend survey form, production database, or production authentication yet. Do not send sensitive real-world survey data until authentication and private networking are implemented.

### Phase 5: Connect the existing frontend to the development API

- [ ] Build or confirm the shared layout, navigation, account menu, and error pages in the existing frontend repository.
- [ ] Add the application launcher and an `/apps/cnaim` placeholder route.
- [ ] Choose and configure the shared login provider.
- [ ] Build the login, logout, password reset, and session-expiry flows.
- [ ] Build application permissions and the logged-in app launcher.
- [ ] Add a development API base URL configuration to the existing frontend repository.
- [ ] Add a frontend health/version check for the deployed CNAIM API.
- [ ] Add the `/apps/cnaim` placeholder route and verify it can call the development API.
- [ ] Confirm CORS, HTTPS, error handling, and API version mismatches from the live website.

### Phase 6: Build the CNAIM survey workflow

- [ ] Create the asset survey form.
- [ ] Group fields into understandable sections for field surveys.
- [ ] Add client-side validation for immediate feedback.
- [ ] Repeat all important validation on the API.
- [ ] Add draft, submit, and review states.
- [ ] Display probability of failure, consequences, and risk clearly.
- [ ] Add risk matrix visualisation where useful.
- [ ] Add export functionality if required.

### Phase 7: Add persistence and audit history

- [ ] Choose the production database, preferably PostgreSQL on Amazon RDS.
- [ ] Create tables for users, organisations, assets, surveys, calculations, and audit events.
- [ ] Store the CNAIM package and calculation version with every result.
- [ ] Add database backups and a restore test.
- [ ] Add ownership and organisation-level access rules.

### Phase 8: Deploy protected application services to AWS

- [ ] Create separate development, staging, and production environments.
- [ ] Create an Amazon Cognito user pool.
- [ ] Promote the tested development API image through staging to production.
- [ ] Configure the production API on ECS Fargate or another private container service.
- [ ] Place API Gateway in front of the production API.
- [ ] Configure token validation, CORS, rate limits, and request logging.
- [ ] Connect the deployed frontend to the authenticated production API.
- [ ] Configure secrets, monitoring, alarms, and backups.

### Phase 9: Security and launch checks

- [ ] Confirm the API cannot be reached without authentication.
- [ ] Confirm users cannot access apps outside their permissions.
- [ ] Confirm database credentials are not present in frontend files.
- [ ] Test password reset, session expiry, and account removal.
- [ ] Test invalid, extreme, and missing survey values.
- [ ] Test concurrent users and API rate limits.
- [ ] Review personal-data retention and privacy requirements.
- [ ] Create an operational runbook for deployments and recovery.

## Initial milestone

The first useful milestone is not the full public website. It is a protected vertical slice:

1. A user logs in.
2. The user opens the CNAIM app.
3. The user completes one transformer survey.
4. The frontend sends validated data to the API.
5. The API runs the CNAIM calculation.
6. The result is returned and displayed.
7. The survey and calculation can be retrieved by the authorised user.

Complete the tasks from top to bottom and tick each box as it is delivered.



### Local R usage reference

The CNAIM backend is currently an R package, not an HTTP API. Use these commands to run and test it locally.

# USEFUL INFORMATION
## CNAIM upstream and deployment repository strategy

Keep the existing `SteMulv/CNAIM` fork as a lightly customised integration fork of the open-source CNAIM package. It already has the correct Git remotes:

```text
origin   https://github.com/SteMulv/CNAIM       # our fork
upstream https://github.com/Utiligize/CNAIM.git # open-source CNAIM
```

Do not maintain a second duplicate checkout of the original project solely for tracking. Fetching the `upstream` remote provides that tracking. Keep CNAIM package changes small, isolated, and suitable for an upstream pull request where possible.

Place the Plumber API, Docker image, API tests, and AWS deployment configuration in a separate private `cnaim-api` repository. That repository should depend on an explicit CNAIM release tag or commit SHA, not a moving branch. Each deployed API image must record both its own immutable image tag and the exact CNAIM revision included in the image.

To bring open-source CNAIM changes into the fork after checking the release notes and tests:

```bash
git fetch upstream --tags
git switch master
git merge --ff-only upstream/master
git push origin master
```

Then update the pinned CNAIM revision in `cnaim-api`, run the CNAIM package, API, and Docker tests, and deploy a new immutable development image tag. For an algorithm defect, make the fix in the CNAIM fork and submit it upstream; for an API or deployment defect, fix `cnaim-api` only. An urgent unreleased CNAIM fix can be pinned to a specific commit in the fork until it is accepted and released upstream.

## Working with teh R app in codespaces
### Launch an interactive R session from Bash

From the repository root, run:

```bash
R
```

When the R prompt (`>`) appears, load the package and run a calculation:

```r
library(CNAIM)

result <- pof_transformer_11_20kv(age = 55)
print(result)

result$pof
result$chs
```

The transformer function returns a one-row data frame containing the probability of failure (`pof`) and current health score (`chs`). Leave R with `q()` and answer `n` if asked whether to save the workspace.

### Run R code directly from Bash

Run a calculation without opening an interactive R session:

```bash
R -q -e 'library(CNAIM); print(pof_transformer_11_20kv(age = 55))'
```

Run the package test suite from Bash:

```bash
R -q -e 'testthat::test_local("tests/testthat", reporter="summary")'
```

The test suite should complete without failures. Warnings may still be reported; review them separately before treating them as defects.

### Run the automated API smoke test manually

The API smoke test is located at `tests/api-smoke-test.sh`. From the repository root, run:

```bash
tests/api-smoke-test.sh
```

The script starts a temporary Plumber server on `http://127.0.0.1:8001`, tests `/health`, `/version`, a valid PoF request, and an invalid request containing an unsupported field, then stops the temporary server automatically. A successful run ends with:

```text
API smoke tests passed
```

To use another local port, provide it as the first argument:

```bash
tests/api-smoke-test.sh 8002
```

### Start the local Plumber API for Postman

From the repository root, start the API with:

```bash
R -q -e 'pr <- plumber::plumb("plumber.R"); pr$run(host="127.0.0.1", port=8000)'
```

Keep this terminal running while testing. The API will be available at `http://127.0.0.1:8000`, and its interactive Swagger documentation will be available at `http://127.0.0.1:8000/__docs__/`.

In Postman, test the PoF endpoint with:

- Method: `POST`
- URL: `http://127.0.0.1:8000/api/v1/pof/transformers`
- Header: `Content-Type: application/json`
- Body: `raw` JSON using the fixed request example in the Phase 2 API contract

For a quick Bash test, use:

```bash
curl -X POST http://127.0.0.1:8000/api/v1/pof/transformers \
  -H 'Content-Type: application/json' \
  --data '{"schema_version":"1.0","asset_id":"Transformer_11kV_400V_001","asset_type":"6.6/11kV Transformer (GM)","survey":{"age":25}}'
```

The successful response contains `result.pof` and `result.chs`. Stop the API with `Ctrl+C` in the terminal where it is running.

## CNAIM Survey Data Reference

This section is a plain-language reference for the information a person will enter when surveying an asset, and the results the CNAIM engine will return. It is kept at the end of this document so it can be used as a lookup guide while building the API and frontend forms.

The package supports several asset families, and each function has its own exact fields. The first practical interface should target an 11 kV to 400 V distribution transformer. The frontend can show that plain-language description, while the API should use the CNAIM category `6.6/11kV Transformer (GM)` and the exact field names below.

### Transformer probability of failure

Function: `pof_transformer_11_20kv()`

| Field | Meaning | Typical value or allowed values |
| --- | --- | --- |
| `hv_transformer_type` | Transformer category | Use `6.6/11kV Transformer (GM)` for the 11 kV to 400 V example |
| `utilisation_pct` | Maximum utilisation | Numeric percentage or `Default` |
| `placement` | Indoor/outdoor placement | Category or `Default` |
| `altitude_m` | Site altitude | Numeric metres or `Default` |
| `distance_from_coast_km` | Distance from coast | Numeric kilometres or `Default` |
| `corrosion_category_index` | Corrosion exposure | Integer 1 to 5 or `Default` |
| `age` | Current asset age | Numeric years; required |
| `partial_discharge` | Partial-discharge condition | `Low`, `Medium`, `High (Not Confirmed)`, `High (Confirmed)`, or `Default` |
| `oil_acidity` | Oil acidity | Numeric value or `Default` |
| `temperature_reading` | Temperature condition | `Normal`, `Moderately High`, `Very High`, or `Default` |
| `observed_condition` | Physical condition | CNAIM condition category or `Default` |
| `reliability_factor` | Reliability adjustment | Numeric value or `Default` |
| `moisture` | Oil moisture | Numeric ppm or `Default` |
| `bd_strength` | Oil breakdown strength | Numeric kV or `Default` |

The advanced `gb_ref_given` option allows custom reference data and should not be exposed in the first survey form.

The function returns a one-row data frame:

| Output | Meaning | Unit |
| --- | --- | --- |
| `pof` | Current probability of failure | Per annum; multiply by 100 for a percentage |
| `chs` | Current health score | CNAIM health-score value |

### Transformer consequence of failure

Function: `cof_transformer_11kv()`

| Field | Meaning | Typical value or allowed values |
| --- | --- | --- |
| `kva` | Rated capacity | Numeric kVA |
| `type` | Access/type category | For example `Type B` |
| `type_risk` | Risk to the public | `Low`, `Medium`, or `High` |
| `location_risk` | Location or trespass risk | CNAIM risk category |
| `prox_water` | Proximity to water | Numeric metres |
| `bunded` | Whether the transformer is bunded | `Yes` or `No` |
| `no_customers` | Customers supplied | Numeric count |
| `kva_per_customer` | Average demand per customer | Numeric kVA |

This function returns one numeric monetary value: total consequence of failure. It combines financial, safety, environmental, and network-performance consequences.

### Risk calculation

`risk_calculation()` takes a matrix structure, asset ID, current health score, consequence of failure, and asset type. It returns a one-row data frame containing:

| Output | Meaning |
| --- | --- |
| `id` | Supplied asset identifier |
| `point_x` | Normalised probability-of-failure position |
| `point_y` | Normalised consequence-of-failure position |

Example:

```r
matrix_data <- risk_matrix_structure(cols = 5, rows = 4, value = NA)
risk_point <- risk_calculation(
  matrix_dimensions = matrix_data,
  id = "Transformer_11kV_400V",
  chs = pof_result$chs,
  cof = cof_result,
  asset_type = "6.6/11kV Transformer (GM)"
)
```

The package also supports cables, submarine cables, switchgear, overhead-line assets, poles, towers, boards, buildings, pillars, relays, RTUs, meters, and service lines. Their exact fields and allowed values must be taken from each function's documentation before adding them to the frontend; transformer fields should not be assumed to apply to every asset family.

