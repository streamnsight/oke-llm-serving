// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/core"
	"github.com/oracle/oci-go-sdk/v65/identity"
	"github.com/oracle/oci-go-sdk/v65/limits"
	"strings"
	"testing"
)

type fakeAPI struct {
	zero, fail, unmapped bool
	reports              int
}

func (f *fakeAPI) subscriptions(context.Context, string) ([]identity.RegionSubscription, error) {
	return []identity.RegionSubscription{{RegionName: common.String("new-region-99"), Status: identity.RegionSubscriptionStatusReady}}, nil
}
func (f *fakeAPI) ads(context.Context, string) ([]identity.AvailabilityDomain, error) {
	return []identity.AvailabilityDomain{{Name: common.String("AD-1")}}, nil
}
func (f *fakeAPI) shapes(context.Context, string, string) ([]core.Shape, error) {
	return []core.Shape{{Shape: common.String("VM.GPU.A10.1"), Gpus: common.Int(1), QuotaNames: []string{"gpu-a10-count"}}, {Shape: common.String("VM.CPU"), Gpus: common.Int(0)}}, nil
}
func (f *fakeAPI) definitions(context.Context, string) ([]limits.LimitDefinitionSummary, error) {
	return []limits.LimitDefinitionSummary{{Name: common.String("gpu-a10-count"), IsResourceAvailabilitySupported: common.Bool(true)}}, nil
}
func (f *fakeAPI) values(context.Context, string) ([]limits.LimitValueSummary, error) {
	if f.unmapped {
		return []limits.LimitValueSummary{}, nil
	}
	v := int64(8)
	if f.zero {
		v = 0
	}
	return []limits.LimitValueSummary{{Name: common.String("gpu-a10-count"), ScopeType: limits.LimitValueSummaryScopeTypeAd, AvailabilityDomain: common.String("AD-1"), Value: &v}}, nil
}
func (f *fakeAPI) headroom(context.Context, string, limits.LimitValueSummary) (limits.ResourceAvailability, error) {
	if f.fail {
		return limits.ResourceAvailability{}, errors.New("denied")
	}
	return limits.ResourceAvailability{Available: common.Int64(8)}, nil
}
func (f *fakeAPI) capacity(context.Context, string, string, []string) (core.ComputeCapacityReport, error) {
	f.reports++
	return core.ComputeCapacityReport{ShapeAvailabilities: []core.CapacityReportShapeAvailability{{InstanceShape: common.String("VM.GPU.A10.1"), AvailableCount: common.Int64(2), AvailabilityStatus: core.CapacityReportShapeAvailabilityAvailabilityStatusAvailable}}}, nil
}
func testQuery() query {
	return query{Tenancy: "root", Compartment: "target", Region: "bootstrap", Headroom: true, Observation: "test"}
}
func TestDynamicRegionAndContract(t *testing.T) {
	f := &fakeAPI{}
	result, err := run(context.Background(), testQuery(), func(string) (api, error) { return f, nil })
	if err != nil {
		t.Fatal(err)
	}
	if result["assessed_regions"].([]string)[0] != "new-region-99" {
		t.Fatal(result)
	}
	regions := result["regions"].([]object)
	inv := regions[0]["inventory"].(object)
	if len(inv["availability_domains"].([]object)[0]["shapes"].([]object)) != 1 || f.reports != 1 {
		t.Fatal(inv)
	}
	if _, err = json.Marshal(result); err != nil {
		t.Fatal(err)
	}
}
func TestZeroLimitAndUnknownMappings(t *testing.T) {
	for _, unmapped := range []bool{false, true} {
		f := &fakeAPI{zero: true, unmapped: unmapped}
		q := testQuery()
		q.OnlyLimits = true
		result, err := scan(context.Background(), q, "future", f, nil)
		if err != nil {
			t.Fatal(err)
		}
		ad := result["capacity"].(object)["availability_domains"].([]object)[0]
		if !unmapped && (ad["status"] != "skipped_zero_limits" || f.reports != 0) {
			t.Fatal(ad)
		}
		if unmapped && (f.reports != 1 || len(result["inventory"].(object)["unmapped_shape_quota_names"].([]string)) != 1) {
			t.Fatal(result)
		}
	}
}
func TestAPIFailureIsNotCapacityZero(t *testing.T) {
	_, err := run(context.Background(), testQuery(), func(string) (api, error) { return &fakeAPI{fail: true}, nil })
	if err == nil || !strings.Contains(err.Error(), "denied") {
		t.Fatal(err)
	}
}
func TestRequestedRegionMustBeReady(t *testing.T) {
	_, _, err := selectedRegions([]identity.RegionSubscription{{RegionName: common.String("a"), Status: identity.RegionSubscriptionStatusInProgress}}, []string{"a"})
	if err == nil {
		t.Fatal("accepted unready subscription")
	}
}
func TestUnknownCapacityDoesNotClaimSufficiency(t *testing.T) {
	result, status := capacityAssessment(testQuery(), "r", "AD-1", []string{"missing", "bad"}, core.ComputeCapacityReport{ShapeAvailabilities: []core.CapacityReportShapeAvailability{{InstanceShape: common.String("bad"), AvailabilityStatus: core.CapacityReportShapeAvailabilityAvailabilityStatusAvailable}}})
	if status != "partial" || result["shapes"].([]object)[0]["reported_sufficient"] != nil {
		t.Fatal(result)
	}
}
func TestPaginationAndRepeatedTokens(t *testing.T) {
	calls := 0
	items, err := pages(func(page *string) ([]int, *string, error) {
		calls++
		if page == nil {
			return []int{1}, common.String("next"), nil
		}
		return []int{2}, nil, nil
	})
	if err != nil || len(items) != 2 || calls != 2 {
		t.Fatal(items, err)
	}
	_, err = pages(func(*string) ([]int, *string, error) { return nil, common.String("repeated"), nil })
	if err == nil {
		t.Fatal("accepted repeated token")
	}
}
func TestExternalProtocolValidation(t *testing.T) {
	_, err := decode(strings.NewReader(`{"tenancy_ocid":"root","region":"r","regions":"","shape_names":"[]","query_resource_availability":"true","only_shapes_with_limits":"false","gpu_catalog":"{}"}`))
	if err != nil {
		t.Fatal(err)
	}
	_, err = decode(strings.NewReader(`{"tenancy_ocid":"root","region":"r","regions":"not-json"}`))
	if err == nil {
		t.Fatal("accepted malformed scope")
	}
}
