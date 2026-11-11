# Copyright (c) 2020-2022 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at http://oss.oracle.com/licenses/upl.
# Static regional aliases: Oracle public OC1 catalog/Go SDK, reviewed 2026-11-11.
# Subscription-driven counts activate only selected READY regions. No nested Terraform.
# Sources: https://docs.oracle.com/en-us/iaas/Content/General/Concepts/regions.htm
# https://github.com/oracle/oci-go-sdk/blob/master/common/regions.go

provider "oci" {
  alias  = "af_casablanca_1"
  region = "af-casablanca-1"
}
module "af_casablanca_1" {
  count                       = contains(local.selected_regions, "af-casablanca-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.af_casablanca_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "af-casablanca-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "af_johannesburg_1"
  region = "af-johannesburg-1"
}
module "af_johannesburg_1" {
  count                       = contains(local.selected_regions, "af-johannesburg-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.af_johannesburg_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "af-johannesburg-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_batam_1"
  region = "ap-batam-1"
}
module "ap_batam_1" {
  count                       = contains(local.selected_regions, "ap-batam-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_batam_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-batam-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_chennai_1"
  region = "ap-chennai-1"
}
module "ap_chennai_1" {
  count                       = contains(local.selected_regions, "ap-chennai-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_chennai_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-chennai-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_chuncheon_1"
  region = "ap-chuncheon-1"
}
module "ap_chuncheon_1" {
  count                       = contains(local.selected_regions, "ap-chuncheon-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_chuncheon_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-chuncheon-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_delhi_1"
  region = "ap-delhi-1"
}
module "ap_delhi_1" {
  count                       = contains(local.selected_regions, "ap-delhi-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_delhi_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-delhi-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_hyderabad_1"
  region = "ap-hyderabad-1"
}
module "ap_hyderabad_1" {
  count                       = contains(local.selected_regions, "ap-hyderabad-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_hyderabad_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-hyderabad-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_kulai_2"
  region = "ap-kulai-2"
}
module "ap_kulai_2" {
  count                       = contains(local.selected_regions, "ap-kulai-2") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_kulai_2 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-kulai-2"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_melbourne_1"
  region = "ap-melbourne-1"
}
module "ap_melbourne_1" {
  count                       = contains(local.selected_regions, "ap-melbourne-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_melbourne_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-melbourne-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_mumbai_1"
  region = "ap-mumbai-1"
}
module "ap_mumbai_1" {
  count                       = contains(local.selected_regions, "ap-mumbai-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_mumbai_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-mumbai-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_osaka_1"
  region = "ap-osaka-1"
}
module "ap_osaka_1" {
  count                       = contains(local.selected_regions, "ap-osaka-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_osaka_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-osaka-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_seoul_1"
  region = "ap-seoul-1"
}
module "ap_seoul_1" {
  count                       = contains(local.selected_regions, "ap-seoul-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_seoul_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-seoul-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_singapore_1"
  region = "ap-singapore-1"
}
module "ap_singapore_1" {
  count                       = contains(local.selected_regions, "ap-singapore-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_singapore_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-singapore-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_singapore_2"
  region = "ap-singapore-2"
}
module "ap_singapore_2" {
  count                       = contains(local.selected_regions, "ap-singapore-2") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_singapore_2 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-singapore-2"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_sydney_1"
  region = "ap-sydney-1"
}
module "ap_sydney_1" {
  count                       = contains(local.selected_regions, "ap-sydney-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_sydney_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-sydney-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ap_tokyo_1"
  region = "ap-tokyo-1"
}
module "ap_tokyo_1" {
  count                       = contains(local.selected_regions, "ap-tokyo-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ap_tokyo_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ap-tokyo-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ca_montreal_1"
  region = "ca-montreal-1"
}
module "ca_montreal_1" {
  count                       = contains(local.selected_regions, "ca-montreal-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ca_montreal_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ca-montreal-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "ca_toronto_1"
  region = "ca-toronto-1"
}
module "ca_toronto_1" {
  count                       = contains(local.selected_regions, "ca-toronto-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.ca_toronto_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "ca-toronto-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "eu_amsterdam_1"
  region = "eu-amsterdam-1"
}
module "eu_amsterdam_1" {
  count                       = contains(local.selected_regions, "eu-amsterdam-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.eu_amsterdam_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "eu-amsterdam-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "eu_frankfurt_1"
  region = "eu-frankfurt-1"
}
module "eu_frankfurt_1" {
  count                       = contains(local.selected_regions, "eu-frankfurt-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.eu_frankfurt_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "eu-frankfurt-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "eu_madrid_1"
  region = "eu-madrid-1"
}
module "eu_madrid_1" {
  count                       = contains(local.selected_regions, "eu-madrid-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.eu_madrid_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "eu-madrid-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "eu_madrid_3"
  region = "eu-madrid-3"
}
module "eu_madrid_3" {
  count                       = contains(local.selected_regions, "eu-madrid-3") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.eu_madrid_3 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "eu-madrid-3"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "eu_marseille_1"
  region = "eu-marseille-1"
}
module "eu_marseille_1" {
  count                       = contains(local.selected_regions, "eu-marseille-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.eu_marseille_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "eu-marseille-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "eu_milan_1"
  region = "eu-milan-1"
}
module "eu_milan_1" {
  count                       = contains(local.selected_regions, "eu-milan-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.eu_milan_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "eu-milan-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "eu_paris_1"
  region = "eu-paris-1"
}
module "eu_paris_1" {
  count                       = contains(local.selected_regions, "eu-paris-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.eu_paris_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "eu-paris-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "eu_stockholm_1"
  region = "eu-stockholm-1"
}
module "eu_stockholm_1" {
  count                       = contains(local.selected_regions, "eu-stockholm-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.eu_stockholm_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "eu-stockholm-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "eu_turin_1"
  region = "eu-turin-1"
}
module "eu_turin_1" {
  count                       = contains(local.selected_regions, "eu-turin-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.eu_turin_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "eu-turin-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "eu_zurich_1"
  region = "eu-zurich-1"
}
module "eu_zurich_1" {
  count                       = contains(local.selected_regions, "eu-zurich-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.eu_zurich_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "eu-zurich-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "il_jerusalem_1"
  region = "il-jerusalem-1"
}
module "il_jerusalem_1" {
  count                       = contains(local.selected_regions, "il-jerusalem-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.il_jerusalem_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "il-jerusalem-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "me_abudhabi_1"
  region = "me-abudhabi-1"
}
module "me_abudhabi_1" {
  count                       = contains(local.selected_regions, "me-abudhabi-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.me_abudhabi_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "me-abudhabi-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "me_dubai_1"
  region = "me-dubai-1"
}
module "me_dubai_1" {
  count                       = contains(local.selected_regions, "me-dubai-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.me_dubai_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "me-dubai-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "me_jeddah_1"
  region = "me-jeddah-1"
}
module "me_jeddah_1" {
  count                       = contains(local.selected_regions, "me-jeddah-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.me_jeddah_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "me-jeddah-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "me_riyadh_1"
  region = "me-riyadh-1"
}
module "me_riyadh_1" {
  count                       = contains(local.selected_regions, "me-riyadh-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.me_riyadh_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "me-riyadh-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "mx_monterrey_1"
  region = "mx-monterrey-1"
}
module "mx_monterrey_1" {
  count                       = contains(local.selected_regions, "mx-monterrey-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.mx_monterrey_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "mx-monterrey-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "mx_queretaro_1"
  region = "mx-queretaro-1"
}
module "mx_queretaro_1" {
  count                       = contains(local.selected_regions, "mx-queretaro-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.mx_queretaro_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "mx-queretaro-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "sa_bogota_1"
  region = "sa-bogota-1"
}
module "sa_bogota_1" {
  count                       = contains(local.selected_regions, "sa-bogota-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.sa_bogota_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "sa-bogota-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "sa_santiago_1"
  region = "sa-santiago-1"
}
module "sa_santiago_1" {
  count                       = contains(local.selected_regions, "sa-santiago-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.sa_santiago_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "sa-santiago-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "sa_saopaulo_1"
  region = "sa-saopaulo-1"
}
module "sa_saopaulo_1" {
  count                       = contains(local.selected_regions, "sa-saopaulo-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.sa_saopaulo_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "sa-saopaulo-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "sa_valparaiso_1"
  region = "sa-valparaiso-1"
}
module "sa_valparaiso_1" {
  count                       = contains(local.selected_regions, "sa-valparaiso-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.sa_valparaiso_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "sa-valparaiso-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "sa_vinhedo_1"
  region = "sa-vinhedo-1"
}
module "sa_vinhedo_1" {
  count                       = contains(local.selected_regions, "sa-vinhedo-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.sa_vinhedo_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "sa-vinhedo-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "uk_cardiff_1"
  region = "uk-cardiff-1"
}
module "uk_cardiff_1" {
  count                       = contains(local.selected_regions, "uk-cardiff-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.uk_cardiff_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "uk-cardiff-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "uk_london_1"
  region = "uk-london-1"
}
module "uk_london_1" {
  count                       = contains(local.selected_regions, "uk-london-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.uk_london_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "uk-london-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "us_ashburn_1"
  region = "us-ashburn-1"
}
module "us_ashburn_1" {
  count                       = contains(local.selected_regions, "us-ashburn-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.us_ashburn_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "us-ashburn-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "us_chicago_1"
  region = "us-chicago-1"
}
module "us_chicago_1" {
  count                       = contains(local.selected_regions, "us-chicago-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.us_chicago_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "us-chicago-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "us_phoenix_1"
  region = "us-phoenix-1"
}
module "us_phoenix_1" {
  count                       = contains(local.selected_regions, "us-phoenix-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.us_phoenix_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "us-phoenix-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "us_saltlake_2"
  region = "us-saltlake-2"
}
module "us_saltlake_2" {
  count                       = contains(local.selected_regions, "us-saltlake-2") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.us_saltlake_2 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "us-saltlake-2"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

provider "oci" {
  alias  = "us_sanjose_1"
  region = "us-sanjose-1"
}
module "us_sanjose_1" {
  count                       = contains(local.selected_regions, "us-sanjose-1") ? 1 : 0
  source                      = "../../modules/regional-capacity-scan"
  providers                   = { oci = oci.us_sanjose_1 }
  tenancy_ocid                = var.tenancy_ocid
  region                      = "us-sanjose-1"
  compartment_id              = var.compartment_id
  shape_names                 = var.shape_names
  observation_id              = var.observation_id
  query_resource_availability = var.query_resource_availability
}

locals {
  supported_regions = toset(["af-casablanca-1", "af-johannesburg-1", "ap-batam-1", "ap-chennai-1", "ap-chuncheon-1", "ap-delhi-1", "ap-hyderabad-1", "ap-kulai-2", "ap-melbourne-1", "ap-mumbai-1", "ap-osaka-1", "ap-seoul-1", "ap-singapore-1", "ap-singapore-2", "ap-sydney-1", "ap-tokyo-1", "ca-montreal-1", "ca-toronto-1", "eu-amsterdam-1", "eu-frankfurt-1", "eu-madrid-1", "eu-madrid-3", "eu-marseille-1", "eu-milan-1", "eu-paris-1", "eu-stockholm-1", "eu-turin-1", "eu-zurich-1", "il-jerusalem-1", "me-abudhabi-1", "me-dubai-1", "me-jeddah-1", "me-riyadh-1", "mx-monterrey-1", "mx-queretaro-1", "sa-bogota-1", "sa-santiago-1", "sa-saopaulo-1", "sa-valparaiso-1", "sa-vinhedo-1", "uk-cardiff-1", "uk-london-1", "us-ashburn-1", "us-chicago-1", "us-phoenix-1", "us-saltlake-2", "us-sanjose-1"])
  regional_results = concat(
    [for scan in module.af_casablanca_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.af_johannesburg_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_batam_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_chennai_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_chuncheon_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_delhi_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_hyderabad_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_kulai_2 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_melbourne_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_mumbai_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_osaka_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_seoul_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_singapore_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_singapore_2 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_sydney_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ap_tokyo_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ca_montreal_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.ca_toronto_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.eu_amsterdam_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.eu_frankfurt_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.eu_madrid_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.eu_madrid_3 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.eu_marseille_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.eu_milan_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.eu_paris_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.eu_stockholm_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.eu_turin_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.eu_zurich_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.il_jerusalem_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.me_abudhabi_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.me_dubai_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.me_jeddah_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.me_riyadh_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.mx_monterrey_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.mx_queretaro_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.sa_bogota_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.sa_santiago_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.sa_saopaulo_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.sa_valparaiso_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.sa_vinhedo_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.uk_cardiff_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.uk_london_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.us_ashburn_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.us_chicago_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.us_phoenix_1 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.us_saltlake_2 : { capacity = scan.result, inventory = scan.inventory }],
    [for scan in module.us_sanjose_1 : { capacity = scan.result, inventory = scan.inventory }],
  )
}
