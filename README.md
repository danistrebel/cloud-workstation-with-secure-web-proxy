# Cloud Workstation with Secure Web Proxy

This TF config provides a sample setup for locking down egress from [Cloud Workstations](https://cloud.google.com/workstations) with a Secure Web Proxy (https://cloud.google.com/secure-web-proxy).

It sets up the following resources:

- VPC with Subnets for
    - Cloud Workstations
    - Secure Web Proxy
    - Regional Proxy Only Subnet

- Secure Web Proxy with example URL Lists

- Cloud DNS entries for the Secure Web Proxy

- Cloud Workstations with HTTP Proxy variables that point to the Secure Web Proxy.

![Complete Architecture Diagram](./images/full_architecture.png)

## Provisining

```sh
cd tf
terraform init
terraform apply --var project_id=$PROJECT_ID
```

## Clean Up

```sh
cd tf
terraform destroy --var project_id=$PROJECT_ID
```