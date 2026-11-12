// Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
// Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/oracle/oci-go-sdk/v65/common"
	"github.com/oracle/oci-go-sdk/v65/common/auth"
	"github.com/oracle/oci-go-sdk/v65/core"
	"github.com/oracle/oci-go-sdk/v65/identity"
	"github.com/oracle/oci-go-sdk/v65/limits"
)

type object = map[string]any

func value[T any](p *T) (z T) {
	if p != nil {
		return *p
	}
	return
}
func has(xs []string, s string) bool {
	for _, x := range xs {
		if x == s {
			return true
		}
	}
	return false
}
func unique(xs []string) []string {
	out := []string{}
	for _, x := range xs {
		if !has(out, x) {
			out = append(out, x)
		}
	}
	sort.Strings(out)
	return out
}

type query struct {
	Tenancy, Compartment, Region, Observation string
	Regions, Shapes                           []string
	Headroom, OnlyLimits                      bool
	Catalog                                   struct {
		Source string `json:"source"`
		Shapes map[string]struct {
			Memory float64 `json:"memory_bytes_per_gpu"`
		} `json:"shapes"`
	}
}

func decode(r io.Reader) (q query, err error) {
	var input map[string]string
	d := json.NewDecoder(io.LimitReader(r, 2<<20))
	if err = d.Decode(&input); err != nil {
		return q, fmt.Errorf("invalid external query: %w", err)
	}
	q.Tenancy = input["tenancy_ocid"]
	q.Compartment = input["compartment_id"]
	q.Region = input["region"]
	q.Observation = input["observation_id"]
	if q.Tenancy == "" || q.Region == "" {
		return q, errors.New("tenancy_ocid and bootstrap region are required")
	}
	if q.Compartment == "" {
		q.Compartment = q.Tenancy
	}
	for key, dest := range map[string]*[]string{"regions": &q.Regions, "shape_names": &q.Shapes} {
		if s := input[key]; s != "" {
			if err = json.Unmarshal([]byte(s), dest); err != nil {
				return q, fmt.Errorf("%s must be a JSON string array", key)
			}
		}
	}
	for key, dest := range map[string]*bool{"query_resource_availability": &q.Headroom, "only_shapes_with_limits": &q.OnlyLimits} {
		s := input[key]
		if s != "true" && s != "false" {
			return q, fmt.Errorf("%s must be true or false", key)
		}
		*dest = s == "true"
	}
	if err = json.Unmarshal([]byte(input["gpu_catalog"]), &q.Catalog); err != nil {
		return q, fmt.Errorf("invalid GPU catalog: %w", err)
	}
	q.Regions = unique(q.Regions)
	q.Shapes = unique(q.Shapes)
	return
}

type api interface {
	subscriptions(context.Context, string) ([]identity.RegionSubscription, error)
	ads(context.Context, string) ([]identity.AvailabilityDomain, error)
	shapes(context.Context, string, string) ([]core.Shape, error)
	definitions(context.Context, string) ([]limits.LimitDefinitionSummary, error)
	values(context.Context, string) ([]limits.LimitValueSummary, error)
	headroom(context.Context, string, limits.LimitValueSummary) (limits.ResourceAvailability, error)
	capacity(context.Context, string, string, []string) (core.ComputeCapacityReport, error)
}
type sdk struct {
	id      identity.IdentityClient
	compute core.ComputeClient
	limits  limits.LimitsClient
}

func newSDK(provider common.ConfigurationProvider, region string) (api, error) {
	id, err := identity.NewIdentityClientWithConfigurationProvider(provider)
	if err != nil {
		return nil, err
	}
	c, err := core.NewComputeClientWithConfigurationProvider(provider)
	if err != nil {
		return nil, err
	}
	l, err := limits.NewLimitsClientWithConfigurationProvider(provider)
	if err != nil {
		return nil, err
	}
	id.SetRegion(region)
	c.SetRegion(region)
	l.SetRegion(region)
	return &sdk{id, c, l}, nil
}
func (s *sdk) subscriptions(ctx context.Context, tenancy string) ([]identity.RegionSubscription, error) {
	r, e := s.id.ListRegionSubscriptions(ctx, identity.ListRegionSubscriptionsRequest{TenancyId: &tenancy})
	return r.Items, e
}
func (s *sdk) ads(ctx context.Context, tenancy string) ([]identity.AvailabilityDomain, error) {
	r, e := s.id.ListAvailabilityDomains(ctx, identity.ListAvailabilityDomainsRequest{CompartmentId: &tenancy})
	return r.Items, e
}

// All paginated APIs advance using the service token; an API failure aborts the snapshot.
func pages[T any](fetch func(*string) ([]T, *string, error)) ([]T, error) {
	out := []T{}
	var page *string
	seen := map[string]bool{}
	for {
		items, next, err := fetch(page)
		if err != nil {
			return nil, err
		}
		out = append(out, items...)
		if value(next) == "" {
			return out, nil
		}
		if seen[*next] {
			return nil, errors.New("pagination token repeated")
		}
		seen[*next] = true
		page = next
	}
}
func (s *sdk) shapes(ctx context.Context, compartment, ad string) ([]core.Shape, error) {
	return pages(func(page *string) ([]core.Shape, *string, error) {
		r, e := s.compute.ListShapes(ctx, core.ListShapesRequest{CompartmentId: &compartment, AvailabilityDomain: &ad, Page: page})
		return r.Items, r.OpcNextPage, e
	})
}
func (s *sdk) definitions(ctx context.Context, tenancy string) ([]limits.LimitDefinitionSummary, error) {
	return pages(func(page *string) ([]limits.LimitDefinitionSummary, *string, error) {
		r, e := s.limits.ListLimitDefinitions(ctx, limits.ListLimitDefinitionsRequest{CompartmentId: &tenancy, ServiceName: common.String("compute"), Page: page})
		return r.Items, r.OpcNextPage, e
	})
}
func (s *sdk) values(ctx context.Context, tenancy string) ([]limits.LimitValueSummary, error) {
	return pages(func(page *string) ([]limits.LimitValueSummary, *string, error) {
		r, e := s.limits.ListLimitValues(ctx, limits.ListLimitValuesRequest{CompartmentId: &tenancy, ServiceName: common.String("compute"), Page: page})
		return r.Items, r.OpcNextPage, e
	})
}
func (s *sdk) headroom(ctx context.Context, compartment string, v limits.LimitValueSummary) (limits.ResourceAvailability, error) {
	r := limits.GetResourceAvailabilityRequest{CompartmentId: &compartment, ServiceName: common.String("compute"), LimitName: v.Name}
	if string(v.ScopeType) == "AD" {
		r.AvailabilityDomain = v.AvailabilityDomain
	}
	out, e := s.limits.GetResourceAvailability(ctx, r)
	return out.ResourceAvailability, e
}
func (s *sdk) capacity(ctx context.Context, tenancy, ad string, names []string) (core.ComputeCapacityReport, error) {
	shapes := []core.CreateCapacityReportShapeAvailabilityDetails{}
	for _, name := range names {
		shapes = append(shapes, core.CreateCapacityReportShapeAvailabilityDetails{InstanceShape: common.String(name)})
	}
	r, e := s.compute.CreateComputeCapacityReport(ctx, core.CreateComputeCapacityReportRequest{CreateComputeCapacityReportDetails: core.CreateComputeCapacityReportDetails{CompartmentId: &tenancy, AvailabilityDomain: &ad, ShapeAvailabilities: shapes}})
	return r.ComputeCapacityReport, e
}
func selectedRegions(subs []identity.RegionSubscription, requested []string) (ready, selected []string, err error) {
	ready = []string{}
	for _, s := range subs {
		if string(s.Status) == "READY" {
			ready = append(ready, value(s.RegionName))
		}
	}
	ready = unique(ready)
	selected = ready
	if len(requested) > 0 {
		selected = unique(requested)
		for _, name := range selected {
			if !has(ready, name) {
				return nil, nil, fmt.Errorf("requested region %s is not a READY subscription", name)
			}
		}
	}
	if len(selected) == 0 {
		return nil, nil, errors.New("no READY subscribed regions selected")
	}
	return
}
func matches(v limits.LimitValueSummary, ad string) bool {
	return string(v.ScopeType) != "AD" || value(v.AvailabilityDomain) == ad
}
func limitKey(v limits.LimitValueSummary) string {
	return value(v.Name) + "/" + string(v.ScopeType) + "/" + value(v.AvailabilityDomain)
}
func unknown(reason string) object {
	return object{"status": "unknown", "reason": reason, "available": nil, "used": nil, "fractional_availability": nil, "fractional_usage": nil, "effective_quota_value": nil}
}
func scan(ctx context.Context, q query, region string, client api, subs []identity.RegionSubscription) (object, error) {
	ads, err := client.ads(ctx, q.Tenancy)
	if err != nil {
		return nil, err
	}
	sort.Slice(ads, func(i, j int) bool { return value(ads[i].Name) < value(ads[j].Name) })
	physicalByAD := map[string][]core.Shape{}
	quotaNames := []string{}
	inventoryADs := []object{}
	for _, ad := range ads {
		name := value(ad.Name)
		shapes, err := client.shapes(ctx, q.Compartment, name)
		if err != nil {
			return nil, err
		}
		rows := []object{}
		selected := []core.Shape{}
		sort.Slice(shapes, func(i, j int) bool { return value(shapes[i].Shape) < value(shapes[j].Shape) })
		for _, shape := range shapes {
			if value(shape.Gpus) <= 0 || (len(q.Shapes) > 0 && !has(q.Shapes, value(shape.Shape))) {
				continue
			}
			selected = append(selected, shape)
			quotaNames = append(quotaNames, shape.QuotaNames...)
			var memory, source any
			if gpu, ok := q.Catalog.Shapes[value(shape.Shape)]; ok && gpu.Memory > 0 {
				memory = gpu.Memory
				source = q.Catalog.Source
			}
			var gib any
			if memory != nil {
				gib = memory.(float64) / (1 << 30)
			}
			rows = append(rows, object{"shape": value(shape.Shape), "gpus": shape.Gpus, "gpu_description": shape.GpuDescription, "host_memory_gb": shape.MemoryInGBs, "ocpus": shape.Ocpus, "local_disks_total_size_in_gbs": shape.LocalDisksTotalSizeInGBs, "rdma_ports": shape.RdmaPorts, "rdma_bandwidth_in_gbps": shape.RdmaBandwidthInGbps, "quota_names": unique(shape.QuotaNames), "gpu_memory_gib": gib, "gpu_memory_bytes_per_gpu": memory, "gpu_memory_source": source, "nvlink_topology": nil})
		}
		physicalByAD[name] = selected
		if q.Compartment != q.Tenancy {
			physical, err := client.shapes(ctx, q.Tenancy, name)
			if err != nil {
				return nil, err
			}
			physicalByAD[name] = []core.Shape{}
			for _, shape := range physical {
				if value(shape.Gpus) > 0 && (len(q.Shapes) == 0 || has(q.Shapes, value(shape.Shape))) {
					physicalByAD[name] = append(physicalByAD[name], shape)
				}
			}
			sort.Slice(physicalByAD[name], func(i, j int) bool { return value(physicalByAD[name][i].Shape) < value(physicalByAD[name][j].Shape) })
		}
		inventoryADs = append(inventoryADs, object{"name": name, "shapes": rows})
	}
	quotaNames = unique(quotaNames)
	defs, err := client.definitions(ctx, q.Tenancy)
	if err != nil {
		return nil, err
	}
	definitions := map[string]limits.LimitDefinitionSummary{}
	for _, def := range defs {
		definitions[value(def.Name)] = def
	}
	values, err := client.values(ctx, q.Tenancy)
	if err != nil {
		return nil, err
	}
	filtered := []limits.LimitValueSummary{}
	for _, v := range values {
		if has(quotaNames, value(v.Name)) || (len(q.Shapes) == 0 && strings.Contains(strings.ToLower(value(v.Name)), "gpu")) {
			filtered = append(filtered, v)
		}
	}
	sort.Slice(filtered, func(i, j int) bool {
		a, b := has(quotaNames, value(filtered[i].Name)), has(quotaNames, value(filtered[j].Name))
		if a != b {
			return a
		}
		return limitKey(filtered[i]) < limitKey(filtered[j])
	})
	observations := []object{}
	mapped := []string{}
	used := 0
	complete := len(ads) > 0
	for _, v := range filtered {
		name := value(v.Name)
		mapped = append(mapped, name)
		def := definitions[name]
		reason := ""
		scope := string(v.ScopeType)
		switch {
		case !q.Headroom:
			reason = "Headroom queries disabled."
		case q.OnlyLimits && (!has(quotaNames, name) || (v.Value != nil && *v.Value == 0)):
			reason = "Skipped by only_shapes_with_limits."
		case !value(def.IsResourceAvailabilitySupported) || (scope != "AD" && scope != "REGION" && scope != "GLOBAL") || (scope == "AD" && value(v.AvailabilityDomain) == ""):
			reason = "Availability unsupported or scope unresolved."
		case used >= 1000:
			reason = "Query budget exhausted."
		}
		availability := unknown(reason)
		if reason == "" {
			r, err := client.headroom(ctx, q.Compartment, v)
			if err != nil {
				return nil, fmt.Errorf("headroom %s: %w", name, err)
			}
			used++
			status := "observed"
			if r.Available == nil && r.FractionalAvailability == nil {
				status = "unknown"
			}
			availability = object{"status": status, "reason": nil, "available": r.Available, "used": r.Used, "fractional_availability": r.FractionalAvailability, "fractional_usage": r.FractionalUsage, "effective_quota_value": r.EffectiveQuotaValue}
		}
		if availability["status"] != "observed" {
			complete = false
		}
		observations = append(observations, object{"name": name, "scope_type": scope, "availability_domain": v.AvailabilityDomain, "tenancy_limit": v.Value, "matched_shape_quota_name": has(quotaNames, name), "description": def.Description, "resource_availability": availability})
	}
	unmapped := []string{}
	for _, name := range quotaNames {
		if !has(mapped, name) {
			unmapped = append(unmapped, name)
			complete = false
		}
	}
	inventoryStatus := "complete"
	if !complete {
		inventoryStatus = "partial"
	}
	capacityADs := []object{}
	for _, ad := range ads {
		name := value(ad.Name)
		visible, assessed, skipped := []string{}, []string{}, []string{}
		for _, shape := range physicalByAD[name] {
			id := value(shape.Shape)
			visible = append(visible, id)
			zero := false
			for _, v := range filtered {
				if has(shape.QuotaNames, value(v.Name)) && matches(v, name) && v.Value != nil && *v.Value == 0 {
					zero = true
				}
			}
			if q.OnlyLimits && zero {
				skipped = append(skipped, id)
			} else {
				assessed = append(assessed, id)
			}
		}
		status := "no_gpu_shapes_listed"
		var assessment any
		if len(visible) > 0 && len(assessed) == 0 {
			status = "skipped_zero_limits"
		}
		if len(assessed) > 0 {
			report, err := client.capacity(ctx, q.Tenancy, name, assessed)
			if err != nil {
				return nil, fmt.Errorf("capacity report: %w", err)
			}
			assessment, status = capacityAssessment(q, region, name, assessed, report)
		}
		capacityADs = append(capacityADs, object{"name": name, "visible_gpu_shapes": visible, "assessed_gpu_shapes": assessed, "skipped_zero_limit_shapes": skipped, "assessment": assessment, "status": status})
	}
	inventory := object{"schema_version": "2.0", "region": region, "tenancy_id": q.Tenancy, "compartment_id": q.Compartment, "status": inventoryStatus, "availability_domains": inventoryADs, "limits": observations, "unmapped_shape_quota_names": unmapped, "headroom_queries_used": used, "warnings": []string{"GPU VRAM uses the sourced catalog; unknown topology remains unknown.", "Entitlement and physical capacity are separate observations."}}
	capacity := object{"schema_version": "1.0", "region": region, "assessment_enabled": true, "availability_domains": capacityADs}
	return object{"inventory": inventory, "capacity": capacity}, nil
}
func capacityAssessment(q query, region, ad string, names []string, report core.ComputeCapacityReport) (object, string) {
	rows := []object{}
	missing := []string{}
	status := "complete"
	for _, name := range names {
		found := false
		for _, r := range report.ShapeAvailabilities {
			if value(r.InstanceShape) != name {
				continue
			}
			found = true
			var sufficient any
			if string(r.AvailabilityStatus) == "OUT_OF_HOST_CAPACITY" {
				sufficient = false
			} else if string(r.AvailabilityStatus) == "AVAILABLE" && r.AvailableCount != nil && *r.AvailableCount >= 0 {
				sufficient = *r.AvailableCount >= 1
			}
			if sufficient == nil {
				status = "partial"
			}
			rows = append(rows, object{"shape": name, "fault_domain": r.FaultDomain, "availability_status": string(r.AvailabilityStatus), "available_instances": r.AvailableCount, "requested_instances": 1, "reported_sufficient": sufficient})
		}
		if !found {
			missing = append(missing, name)
			status = "partial"
		}
	}
	var observed any
	if report.TimeCreated != nil {
		observed = report.TimeCreated.Time.UTC().Format(time.RFC3339Nano)
	}
	return object{"schema_version": "2.0", "region": region, "availability_domain": ad, "fault_domain": nil, "report_compartment_id": q.Tenancy, "observation_id": q.Observation, "observed_at": observed, "status": status, "shapes": rows, "missing_shapes": missing, "warnings": []string{"Fresh diagnostic report, not a reservation or launch guarantee.", "Counts are instances; different shapes may share supply."}}, status
}
func run(ctx context.Context, q query, factory func(string) (api, error)) (object, error) {
	bootstrap, err := factory(q.Region)
	if err != nil {
		return nil, err
	}
	subs, err := bootstrap.subscriptions(ctx, q.Tenancy)
	if err != nil {
		return nil, err
	}
	ready, selected, err := selectedRegions(subs, q.Regions)
	if err != nil {
		return nil, err
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	results := make([]object, len(selected))
	var wg sync.WaitGroup
	sem := make(chan struct{}, 4)
	var first error
	var mu sync.Mutex
	for i, region := range selected {
		wg.Add(1)
		go func(i int, region string) {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
			case <-ctx.Done():
				return
			}
			defer func() { <-sem }()
			client, err := factory(region)
			var result object
			if err == nil {
				result, err = scan(ctx, q, region, client, subs)
			}
			mu.Lock()
			defer mu.Unlock()
			if err != nil {
				if first == nil {
					first = fmt.Errorf("region %s: %w", region, err)
					cancel()
				}
			} else {
				results[i] = result
			}
		}(i, region)
	}
	wg.Wait()
	if first != nil {
		return nil, first
	}
	if err = ctx.Err(); err != nil {
		return nil, err
	}
	return object{"schema_version": "1.0", "subscribed_regions": ready, "assessed_regions": selected, "regions": results}, nil
}

// Honor the same authentication mode variables as the native OCI provider.
func authenticationMode() (string, error) {
	mode := os.Getenv("TF_VAR_auth")
	if mode == "" {
		mode = os.Getenv("OCI_AUTH")
	}
	if mode == "" && os.Getenv("OCI_RESOURCE_PRINCIPAL_VERSION") != "" {
		mode = "ResourcePrincipal"
	}
	switch strings.ToLower(mode) {
	case "", "apikey":
		return "apikey", nil
	case "instanceprincipal", "resourceprincipal":
		return strings.ToLower(mode), nil
	default:
		return "", errors.New("unsupported discovery authentication mode; use APIKey, InstancePrincipal or ResourcePrincipal")
	}
}

func execute() error {
	q, err := decode(os.Stdin)
	if err != nil {
		return err
	}
	mode, err := authenticationMode()
	if err != nil {
		return err
	}
	var provider common.ConfigurationProvider
	switch mode {
	case "instanceprincipal":
		provider, err = auth.InstancePrincipalConfigurationProviderForRegion(common.StringToRegion(q.Region))
	case "resourceprincipal":
		provider, err = auth.ResourcePrincipalConfigurationProvider()
	default:
		provider = common.DefaultConfigProvider()
	}
	if err != nil {
		return fmt.Errorf("%s authentication: %w", mode, err)
	}
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	ctx, cancel := context.WithTimeout(ctx, 30*time.Minute)
	defer cancel()
	result, err := run(ctx, q, func(region string) (api, error) { return newSDK(provider, region) })
	if err != nil {
		return err
	}
	encoded, err := json.Marshal(result)
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(map[string]string{"result": string(encoded)})
}
func main() {
	if err := execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
