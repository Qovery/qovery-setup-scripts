# Qovery Setup Scripts

This repository contains the credential creation scripts used during the installation of a Qovery cluster manager.

## Description

This repository hosts the shell scripts used to configure the necessary credentials for deploying Qovery on different cloud providers:

- **GCP (Google Cloud Platform)**: Service account and IAM role creation script
- **Azure**: Service principal and custom role creation script

These scripts are automatically referenced and used during the Qovery cluster manager installation process.

## Repository Structure

```
.
├── scripts/
│   ├── create_credentials_azure.sh
│   └── create_credentials_gcp.sh
└── README.md
```

## Available Scripts

### GCP
`scripts/create_credentials_gcp.sh` - Configures permissions and service accounts for GCP

### Azure
`scripts/create_credentials_azure.sh` - Configures permissions and service principals for Azure

## Important Warning

**DO NOT RENAME THIS REPOSITORY**

This repository is referenced by a DNS record pointing to `get.qovery.com`. The internal GitHub link is used to fetch the scripts during installation.

If you absolutely must rename the repository:
1. Notify the team beforehand
2. Update the corresponding DNS record
3. Verify that all reference links are updated

## Usage

These scripts are automatically downloaded and executed during the installation of a cluster manager via the Qovery console. They are generally not intended to be run manually.

For more information about Qovery installation, please consult the [official documentation](https://docs.qovery.com).
