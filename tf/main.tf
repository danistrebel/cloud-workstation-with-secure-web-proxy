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
    "dns.googleapis.com",
  ]
}

module "vpc" {
  source     = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/net-vpc?ref=v33.0.0"
  project_id = module.project.id
  name       = "demo-network"
  subnets = [
    {
      ip_cidr_range = var.cidr_workstations_subnet
      name          = "dev-workstations"
      region        = var.region
    },
    {
      ip_cidr_range = var.cidr_egress_proxy_subnet
      name          = "egress-proxy"
      region        = var.region
    },
  ]
  subnets_proxy_only = [
    {
      ip_cidr_range = var.cidr_regional_proxy_subnet
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
    common_name  = "${var.swp_subdomain}.${var.swp_domain}"
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
  addresses    = [var.ip_secure_web_proxy]
  certificates = [google_certificate_manager_certificate.swp-self-signed.id]
  ports        = [80, 443]
  policy_rules = {
    url_lists = {
      url-list-1 = {
        url_list = "google"
        values   = ["www.google.com", "google.com"]
        priority = 1002
      }
      apt-list = {
        url_list = "apt"
        values   = [
            "security.ubuntu.com", 
            "archive.ubuntu.com",
        ]
        priority = 1003
      }
    }
  }
}

module "swp-dns" {
  source     = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/dns?ref=v33.0.0"
  project_id = module.project.id
  name       = "swp-zone"
  zone_config = {
    domain = "${var.swp_domain}."
    private = {
      client_networks = [module.vpc.self_link]
    }
  }
  recordsets = {
    "A ${var.swp_subdomain}"    = { ttl = 600, records = [var.ip_secure_web_proxy] }
  }
}

module "workstation" {
  source     = "github.com/terraform-google-modules/cloud-foundation-fabric//modules/workstation-cluster?ref=v33.0.0"
  project_id = module.project.id
  id         = "my-workstation-cluster"
  location   = var.region
  network_config = {
    network    = module.vpc.id
    subnetwork = module.vpc.subnets["${var.region}/dev-workstations"].id
  }
  private_cluster_config = {
    enable_private_endpoint = false
  }
  workstation_configs = {
    my-workstation-config = {
      gce_instance = {
        machine_type                = "e2-standard-4"
        disable_public_ip_addresses = true
        shielded_instance_config = {
          enable_secure_boot          = true
          enable_vtpm                 = true
          enable_integrity_monitoring = true
        }
      }

      container = {
        image = "europe-west1-docker.pkg.dev/cloud-workstations-images/predefined/code-oss:latest"
        env = {
          HTTP_PROXY = "http://${var.swp_subdomain}.${var.swp_domain}:80"
          http_proxy = "http://${var.swp_subdomain}.${var.swp_domain}:80"
          HTTPS_PROXY = "https://${var.swp_subdomain}.${var.swp_domain}:443"
          https_proxy = "https://${var.swp_subdomain}.${var.swp_domain}:443"
        }
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