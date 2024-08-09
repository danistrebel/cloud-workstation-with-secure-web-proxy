variable "project_id" {
  type = string
}

variable "region" {
  type = string
  default = "europe-west1"
}

variable "cidr_workstations_subnet" {
  type = string
  default = "10.0.0.0/22"
}

variable "cidr_egress_proxy_subnet" {
  type = string
  default = "10.220.0.0/24"
}

variable "cidr_regional_proxy_subnet" {
  type = string
  default = "10.198.0.0/23"
}

variable "ip_secure_web_proxy" {
  type = string
  default = "10.220.0.3"
}

variable "swp_domain" {
  type = string
  default = "example.internal"
}

variable "swp_subdomain" {
  type = string
  default = "proxy"
}