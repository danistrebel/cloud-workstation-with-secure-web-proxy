module "project" {
  source         = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/project?ref=v33.0.0"
  name           = var.project_id
  project_create = false
  services = [
    "compute.googleapis.com",
    "networksecurity.googleapis.com",
    "networkservices.googleapis.com",
    "certificatemanager.googleapis.com",
    "workstations.googleapis.com",
  ]
}

module "vpc" {
  source     = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/net-vpc?ref=v33.0.0"
  project_id = module.project.id
  name       = "demo-network"
  subnets = [
    {
      ip_cidr_range = "10.0.0.0/22"
      name          = "dev-workstations"
      region        = var.region
    },
    {
      ip_cidr_range = "10.220.0.0/24"
      name          = "egress-proxy"
      region        = var.region
    },
  ]
  subnets_proxy_only = [
    {
      ip_cidr_range = "10.198.0.0/23"
      name          = "regional-proxy"
      region        = var.region
      active        = true
    },
  ]
}

resource "tls_private_key" "swp_private_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "swp_cert" {
  private_key_pem = tls_private_key.swp_private_key.private_key_pem
  subject {
    common_name  = "swp.example.internal"
    organization = "ACME Examples, Inc"
  }
  validity_period_hours = 24*365
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
  depends_on = [tls_private_key.swp_private_key]
}

module "certificate-manager" {
  source     = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/certificate-manager?ref=v33.0.0"
  project_id = module.project.id
}

// can be achieved via certificate-manager module once https://github.com/GoogleCloudPlatform/cloud-foundation-fabric/pull/2474 is added to release
resource "google_certificate_manager_certificate" "swp-self-signed" {
  name        = "swp-self-signed"
  project = module.project.id
  location    = var.region
  self_managed {
    pem_certificate = tls_self_signed_cert.swp_cert.cert_pem
    pem_private_key = tls_private_key.swp_private_key.private_key_pem
  }
  depends_on = [ module.certificate-manager ]
}

module "secure-web-proxy" {
  source       = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/net-swp?ref=v33.0.0"
  project_id   = module.project.id
  region       = var.region
  name         = "secure-web-proxy"
  network      = module.vpc.id
  subnetwork   = module.vpc.subnets["${var.region}/egress-proxy"].id
  addresses    = ["10.220.0.3"]
  certificates = [google_certificate_manager_certificate.swp-self-signed.id]
  ports        = [80, 443]
  policy_rules = {
    url_lists = {
      url-list-1 = {
        url_list = "google"
        values   = ["www.google.com", "google.com"]
        priority = 1002
      }
    }
  }
}

module "workstation-cluster" {
  source     = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/workstation-cluster?ref=v33.0.0"
  project_id = module.project.id
  id         = "my-workstation-cluster"
  location   = var.region
  network_config = {
    network    = module.vpc.id
    subnetwork = module.vpc.subnets["${var.region}/dev-workstations"].id
  }
  private_cluster_config = {
    enable_private_endpoint = true
  }
  workstation_configs = {
    my-workstation-config = {
      gce_instance = {
        disable_public_ip_addresses = true
      }
      workstations = {
        my-workstation = {
          labels = {
            team = "my-team"
          }
        }
      }
    }
  }
}