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

module "project-services" {
  source                      = "terraform-google-modules/project-factory/google//modules/project_services"
  version                     = "14.4.0"
  disable_services_on_destroy = false

  project_id  = var.project_id
  enable_apis = var.enable_apis

  activate_apis = [
    "artifactregistry.googleapis.com",
    "biglake.googleapis.com",
    "bigquery.googleapis.com",
    "bigqueryconnection.googleapis.com",
    "bigquerydatapolicy.googleapis.com",
    "bigquerydatatransfer.googleapis.com",
    "bigquerymigration.googleapis.com",
    "bigqueryreservation.googleapis.com",
    "bigquerystorage.googleapis.com",
    "cloudapis.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudfunctions.googleapis.com",
    "compute.googleapis.com",
    "config.googleapis.com",
    "datacatalog.googleapis.com",
    "datalineage.googleapis.com",
    "dataplex.googleapis.com",
    "dataproc.googleapis.com",
    "iam.googleapis.com",
    "serviceusage.googleapis.com",
    "storage-api.googleapis.com",
    "storage.googleapis.com",
    "workflows.googleapis.com",
    "notebooks.googleapis.com",
  ]

  activate_api_identities = [
    {
      api = "aiplatform.googleapis.com"
      roles = [
        "roles/compute.osAdminLogin",
        "roles/dataproc.admin",
        "roles/iam.serviceAccountUser",
        "roles/storage.objectAdmin",
      ]
    },
    {
      api = "bigqueryconnection.googleapis.com"
      roles = [
        "roles/biglake.admin",
        "roles/storage.objectViewer",
      ]
    },
    {
      api = "dataplex.googleapis.com"
      roles = [
        "roles/dataplex.serviceAgent"
      ]
    },
    {
      api = "dataproc.googleapis.com"
      roles = [
        "roles/biglake.admin",
        "roles/bigquery.connectionAdmin",
        "roles/bigquery.dataOwner",
        "roles/bigquery.user",
        "roles/dataproc.worker",
        "roles/storage.objectAdmin",
      ]
    },
    {
      api = "workflows.googleapis.com"
      roles = [
        "roles/bigquery.admin",
        "roles/bigquery.connectionAdmin",
        "roles/bigquery.dataOwner",
        "roles/bigquery.jobUser",
        "roles/bigquery.resourceAdmin",
        "roles/dataproc.admin",
        "roles/dataplex.admin",
        "roles/iam.serviceAccountTokenCreator",
        "roles/iam.serviceAccountUser",
        "roles/logging.logWriter",
        "roles/workflows.admin",
        "roles/storage.admin",
      ]
    }
  ]
}

resource "time_sleep" "wait_after_apis_activate" {
  depends_on      = [module.project-services]
  create_duration = "30s"
}

#random id
resource "random_id" "id" {
  byte_length = 4
}
