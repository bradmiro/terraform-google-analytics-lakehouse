/**
 * Copyright 2023 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

resource "google_project_service_identity" "dataproc" {
  provider = google-beta
  project  = module.project-services.project_id
  service  = "dataproc.googleapis.com"

  depends_on = [time_sleep.wait_after_apis_activate]
}

# Workflow to copy data from prod GCS bucket to private buckets
# NOTE: google_storage_bucket.<bucket>.name omits the `gs://` prefix.
# You can use google_storage_bucket.<bucket>.url to include the prefix.
resource "google_workflows_workflow" "copy_data" {
  name            = "copy-data"
  project         = module.project-services.project_id
  region          = var.region
  description     = "Copies data and performs project setup"
  service_account = google_service_account.workflows_sa.email
  source_contents = templatefile("${path.module}/src/yaml/copy-data.yaml", {
    public_data_bucket    = var.public_data_bucket,
    textocr_images_bucket = google_storage_bucket.textocr_images_bucket.name,
    ga4_images_bucket     = google_storage_bucket.ga4_images_bucket.name,
    tables_bucket         = google_storage_bucket.tables_bucket.name,
    dataplex_bucket       = google_storage_bucket.dataplex_bucket.name,
    images_zone_name      = google_dataplex_zone.gcp_primary_raw.name,
    tables_zone_name      = google_dataplex_zone.gcp_primary_staging.name,
    lake_name             = google_dataplex_lake.gcp_primary.name
  })
}

# Workflow to set up project resources
# Note: google_storage_bucket.<bucket>.name omits the `gs://` prefix.
# You can use google_storage_bucket.<bucket>.url to include the prefix.
resource "google_workflows_workflow" "project_setup" {
  name            = "project-setup"
  project         = module.project-services.project_id
  region          = var.region
  description     = "Copies data and performs project setup"
  service_account = google_service_account.workflows_sa.email
  source_contents = templatefile("${path.module}/src/yaml/project-setup.yaml", {
    data_analyst_user         = "None"
    marketing_user            = "None"
    dataproc_service_account  = google_project_service_identity.dataproc.email,
    provisioner_bucket        = google_storage_bucket.provisioning_bucket.name,
    warehouse_bucket          = google_storage_bucket.warehouse_bucket.name,
    temp_bucket               = google_storage_bucket.warehouse_bucket.name,
    dataplex_asset_tables_id  = google_dataplex_asset.gcp_primary_tables.id,
    dataplex_asset_textocr_id = google_dataplex_asset.gcp_primary_textocr.id,
    dataplex_asset_ga4_id     = google_dataplex_asset.gcp_primary_ga4_obfuscated_sample_ecommerce.id
  })
}

# execute workflows after all resources are created
# # get a token to execute the workflows
data "google_client_config" "current" {
}

# # execute the copy data workflow
data "http" "call_workflows_copy_data" {
  url    = "https://workflowexecutions.googleapis.com/v1/projects/${module.project-services.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.copy_data.name}/executions"
  method = "POST"
  request_headers = {
    Accept = "application/json"
  Authorization = "Bearer ${data.google_client_config.current.access_token}" }
  depends_on = [
    google_storage_bucket.textocr_images_bucket,
    google_storage_bucket.ga4_images_bucket,
    google_storage_bucket.tables_bucket,
    time_sleep.wait_after_apis_activate
  ]
}

resource "time_sleep" "wait_after_copy_data" {
  create_duration = "30s"
  depends_on = [
    data.http.call_workflows_copy_data
  ]
}

# execute the other project setup workflow
data "http" "call_workflows_project_setup" {
  url    = "https://workflowexecutions.googleapis.com/v1/projects/${module.project-services.project_id}/locations/${var.region}/workflows/${google_workflows_workflow.project_setup.name}/executions"
  method = "POST"
  request_headers = {
    Accept = "application/json"
  Authorization = "Bearer ${data.google_client_config.current.access_token}" }
  depends_on = [
    google_bigquery_dataset.gcp_lakehouse_ds,
    google_bigquery_connection.gcp_lakehouse_connection,
    google_dataplex_asset.gcp_primary_ga4_obfuscated_sample_ecommerce,
    google_dataplex_asset.gcp_primary_tables,
    google_dataplex_asset.gcp_primary_textocr,
    google_storage_bucket.provisioning_bucket,
    google_storage_bucket.warehouse_bucket,
    time_sleep.wait_after_copy_data
  ]
}

# Wait for the project setup workflow to finish. This step should take about
# 12 minutes total. Completing this is not a blocker to begin exploring the
# deployment, but we pause for five minutes to give some resources time to
# spin up.
resource "time_sleep" "wait_after_all_workflows" {
  create_duration = "300s"

  depends_on = [
    data.http.call_workflows_project_setup,
  ]
}
