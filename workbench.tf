/**
 * Copyright 2024 Google LLC
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

resource "google_project_service_identity" "workbench" {
  provider = google-beta
  project  = module.project-services.project_id
  service  = "aiplatform.googleapis.com"

  depends_on = [time_sleep.wait_after_apis_activate]
}

# Provisions a new Workbench instance.
resource "google_workbench_instance" "workbench_instance" {
  name     = "gcp-${var.use_case_short}-workbench-instance-${random_id.id.hex}"
  project  = module.project-services.project_id
  location = "${var.region}-a"

  gce_setup {
    machine_type = "e2-standard-4"

    vm_image {
      project = "cloud-notebooks-managed"
      name    = "workbench-instances-v20231108-py310"
    }

    network_interfaces {
      network  = google_compute_network.default_network.id
      subnet   = google_compute_subnetwork.subnet.id
      nic_type = "GVNIC"
    }

    disable_public_ip = false

    service_accounts {
      email = google_project_service_identity.workbench.email
    }

    metadata = {
      proxy-mode            = "service_account"
      idle-timeout-seconds  = "10800"
      report-event-health   = "true"
      disable-mixer         = "false"
      post-startup-script   = "gs://${google_storage_bucket.provisioning_bucket.name}/post_startup.sh"
      report-dns-resolution = "true"
    }

    enable_ip_forwarding = true
  }

  depends_on = [
    google_compute_subnetwork.subnet
  ]
}
