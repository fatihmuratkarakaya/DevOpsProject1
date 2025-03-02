# Kubernetes DevOps Environment

This project sets up a local Kubernetes environment with CI/CD capabilities and database services. It includes automated deployment of Jenkins, PostgreSQL, and Redis, all configured for data persistence and external access.

## Overview

The system architecture consists of:

- **Kubernetes Cluster**: Local cluster using KIND, provisioned via Terraform
- **CI/CD**: Jenkins with automated pipelines for database deployments
- **Databases**:
  - PostgreSQL for persistent data storage with daily backups
  - Redis for data caching
- **Security**: Secret management using Kubernetes Secrets

## Prerequisites

- Ubuntu-based system (physical or virtual machine)
- sudo access
- Internet connection

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/fatihmuratkarakaya/DevOpsProject1.git
   cd DevOpsProject1
   ```

2. Run the setup script:
   ```bash
   ./scripts/setup.sh
   ```

3. Access services:
   - Jenkins: http://localhost:30000 (credentials provided after setup)
   - PostgreSQL: localhost:30001
   - Redis: localhost:30002

## Detailed Installation

The setup script performs these steps automatically:

1. Installs all dependencies (Docker, kubectl, Helm, KIND, Terraform)
2. Creates a Kubernetes cluster using KIND via Terraform
3. Configures Kubernetes RBAC permissions
4. Sets up secure secrets for database credentials
5. Deploys Jenkins with preconfigured pipelines
6. Deploys PostgreSQL and Redis via Jenkins pipelines

## Accessing Services

### Jenkins

- **URL**: http://localhost:30000
- **Username**: admin
- **Password**: Displayed after installation completes

### PostgreSQL

- **Host**: localhost
- **Port**: 30001
- **Username**: postgres
- **Password**: Stored securely in Kubernetes secrets

To verify Postgresql functionality:
```bash
./scripts/check_postgresql.sh
```

### Redis

- **Host**: localhost
- **Port**: 30002
- **Password**: Stored securely in Kubernetes secrets

To verify Redis functionality:
```bash
./scripts/check_redis.sh
```

## Features

- **Data Persistence**: Both PostgreSQL and Redis store data persistently
- **Automatic Backups**: PostgreSQL performs daily backups
- **External Access**: All services are accessible from outside the Kubernetes cluster
- **Secure Secrets**: Passwords are generated randomly and stored securely
- **Reproducible Setup**: Entire environment can be recreated consistently

## Directory Structure

```
kubernetes-devops/
├── scripts/
│   ├── setup.sh                     # Main setup script
│   ├── install_dependencies.sh      # Script to install required software
│   ├── check_postgresql.sh          # Script to test PostgreSQL
│   ├── check_redis.sh               # Script to test Redis
│   └── secrets-reference.sh         # Reference file for secrets
├── terraform/
│   ├── main.tf                      # KIND cluster configuration
│   ├── variables.tf                 # Terraform variables
│   ├── outputs.tf                   # Terraform outputs
│   └── providers.tf                 # Provider configurations
├── helm/
│   └── jenkins-values.yaml          # Jenkins Helm values
├── Jenkinsfile                      # Pipeline for PostgreSQL deployment
├── Jenkinsfile-redis                # Pipeline for Redis deployment
└── README.md                        # This documentation
```

## Troubleshooting

### Common Issues

- **Port conflicts**: If ports 30000-30002 are already in use, modify the port mappings in terraform/main.tf
- **Resource limitations**: Ensure your system has sufficient resources (min 4GB RAM, 2 CPU cores)
- **Connection issues**: Verify that Docker is running and KIND ports are correctly mapped

### Logs

- **Kubernetes**: `kubectl logs -n <namespace> <pod-name>`
- **Jenkins**: Available through the Jenkins UI or `kubectl logs -n jenkins jenkins-0`
- **PostgreSQL**: `kubectl logs -n postgresql postgresql-0`
- **Redis**: `kubectl logs -n redis redis-master-0`

## Security Considerations

- Default credentials are generated randomly during installation
- All passwords are stored as Kubernetes Secrets
- For production use, consider additional security measures like:
  - Network policies
  - Resource quotas
  - Regular credential rotation

## License

This project is licensed under the Apache 2.0 License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
