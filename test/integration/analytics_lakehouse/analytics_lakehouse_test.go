// Copyright 2023 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package multiple_buckets

import (
	"fmt"
	"log"
	"os"
	"testing"
	"time"

	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/bq"
	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/gcloud"
	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/tft"
	"github.com/GoogleCloudPlatform/cloud-foundation-toolkit/infra/blueprint-test/pkg/utils"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Retry if these errors are encountered.
var retryErrors = map[string]string{
	".*does not have enough resources available to fulfill the request.  Try a different zone,.*": "Compute zone resources currently unavailable.",
	".*Error 400: The subnetwork resource*":                                                       "Subnet is eventually drained",
}

func TestAnalyticsLakehouse(t *testing.T) {
	dwh := tft.NewTFBlueprintTest(t, tft.WithRetryableTerraformErrors(retryErrors, 60, time.Minute))

	dwh.DefineVerify(func(assert *assert.Assertions) {
		dwh.DefaultVerify(assert)

		projectID := dwh.GetTFSetupStringOutput("project_id")

		region := dwh.GetTFSetupStringOutput("region")

		verifyWorkflow := func(workflow string) (bool, error) {
			executions := gcloud.Runf(t, "workflows executions list %s --project %s --sort-by=startTime", workflow, projectID)
			state := executions.Get("0.state").String()
			if state == "FAILED" {
				id := executions.Get("0.name")
				gcloud.Runf(t, "workflows executions describe %s", id)
				t.FailNow()
			}
			if state == "SUCCEEDED" {
				return false, nil
			}
			return true, nil
		}

		// Assert copy-data workflow ran successfully
		verifyCopyDataWorkflow := func() (bool, error) {
			return verifyWorkflow("copy-data")
		}
		utils.Poll(t, verifyCopyDataWorkflow, 150, 5*time.Second)

		// Assert project-setup workflow ran successfully
		verifyProjectSetupWorkflow := func() (bool, error) {
			return verifyWorkflow("project-setup")
		}
		utils.Poll(t, verifyProjectSetupWorkflow, 150, 5*time.Second)

		// Assert BigQuery tables are not empty
		verifyTables := func() (bool, error) {
			data
		}

		tables := []string{
			"gcp_primary_raw.ga4_obfuscated_sample_ecommerce_images",
			"gcp_primary_raw.textocr_images",
			"gcp_primary_staging.new_york_taxi_trips_tlc_yellow_trips_2022",
			"gcp_primary_staging.thelook_ecommerce_distribution_centers",
			"gcp_primary_staging.thelook_ecommerce_events",
			"gcp_primary_staging.thelook_ecommerce_inventory_items",
			"gcp_primary_staging.thelook_ecommerce_order_items",
			"gcp_primary_staging.thelook_ecommerce_orders",
			"gcp_primary_staging.thelook_ecommerce_products",
			"gcp_primary_staging.thelook_ecommerce_users",
			"gcp_lakehouse_ds.agg_events_iceberg",
		}

		query_template := "SELECT count(*) AS count FROM `%[1]s.%[2]s`;"
		for _, table := range tables {
			query := fmt.Sprintf(query_template, projectID, table)
			op := bq.Runf(t, "--project_id=%[1]s query --nouse_legacy_sql %[2]s", projectID, query)

			count := op.Get("0.count").Int()
			assert.Greater(count, int64(0), table)
		}

		// Assert only one Dataproc cluster is available
		currentComputeInstances := gcloud.Runf(t, "dataproc clusters list --project=%s --region=%s", projectID, region).Array()
		assert.Equal(len(currentComputeInstances), 1, "More than one Dataproc cluster is available.")

		// Assert Dataproc cluster is stopped
		phsName := currentComputeInstances[0].Get("clusterName")
		cluster := gcloud.Runf(t, "dataproc clusters describe %s --project=%s", phsName, projectID)
		state := cluster.Get("status").Get("state").String()
		assert.Equal(state, "TERMINATED", "PHS is not in a stopped state")

	})

	dwh.DefineTeardown(func(assert *assert.Assertions) {

		projectID := dwh.GetTFSetupStringOutput("project_id")

		verifyNoVMs := func() (bool, error) {
			currentComputeInstances := gcloud.Runf(t, "compute instances list --project %s", projectID).Array()
			// There should only be 1 compute instance (Dataproc PHS). Wait to destroy if other instances exist.
			if len(currentComputeInstances) > 1 {
				return true, nil
			}
			return false, nil
		}
		utils.Poll(t, verifyNoVMs, 120, 30*time.Second)

		dwh.DefaultTeardown(assert)

	})
	dwh.Test()
}
