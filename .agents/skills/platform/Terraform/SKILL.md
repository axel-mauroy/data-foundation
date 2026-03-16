---
name: Terraform
description: Infrastructure as Code (IaC) best practices for reproducible, scalable, and versioned MLOps environments.
---

# Terraform Best Practices Guide

Terraform allows you to define and provision infrastructure using a high-level configuration language (HCL). In MLOps, it ensures that your training clusters, feature stores, and end-points are identical across environments.

## 🏗️ Terraform & MLOps Best Practices

### 1. Code Formatting
Indent two spaces for each nesting level. When multiple arguments appear on consecutive lines at the same nesting level, align their equals signs. Place all arguments at the top of a block body, followed by nested blocks below, separated by one blank line. Meta-arguments (like `count`, `for_each`, `lifecycle`) should come first and be separated from other arguments by a blank line, and meta-argument blocks (like `lifecycle`) should come last.

Run `terraform fmt` before each commit — you can automate this via Git pre-commit hooks. Run `terraform validate` as a post-save check, pre-commit hook, or CI/CD pipeline step to catch syntax and type errors early.

### 2. File Structure & Naming
Use the following standard file naming conventions:
- `main.tf` — all resources and data sources
- `variables.tf` — all variable blocks (alphabetical order)
- `outputs.tf` — all output blocks (alphabetical order)
- `providers.tf` — all provider blocks
- `terraform.tf` — the single `terraform` block with `required_version` and `required_providers`
- `backend.tf` — backend configuration
- `locals.tf` — local values used across multiple files
- `override.tf` — override definitions (use sparingly)

As your codebase grows, split resources into logical group files such as `network.tf`, `storage.tf`, and `compute.tf`. It should always be immediately clear where a maintainer can find a specific resource.

### 3. Resource Naming & Tagging
Use descriptive nouns for resource names and separate words with underscores. Do not include the resource type in the identifier, since the resource address already includes it. Wrap both the resource type and name in double quotes.

For example, use `resource "aws_instance" "web_api" {}` instead of `resource aws_instance webAPI-aws-instance {}`.

**Tags/Labels:** Apply consistent labels (e.g., `model_name`, `env`, `cost_center`) to all resources for cost tracking and auditing.

### 4. Resource Ordering & Lifecycle
Define data sources before the resources that reference them so your code "builds on itself." Follow a consistent order for resource parameters: (1) `count` or `for_each`, (2) non-block parameters, (3) block parameters, (4) `lifecycle` block, (5) `depends_on`.

**Lifecycle & Safety:** Apply `lifecycle { prevent_destroy = true }` to critical production resources like the primary Feature Store or BigQuery datasets.

### 5. Variables
Always define a `type` and a `description` for every variable. If a variable is optional, define a reasonable `default`. For sensitive variables (passwords, private keys), set `sensitive = true`. Use input variable validation only when values have uniquely restrictive requirements. Follow this order for variable parameters: type → description → default → sensitive → validation blocks.

**Avoid hardcoding:** It is a security risk. Use `.tfvars` files and environment-specific variables instead.

### 6. Outputs
Provide a `description` for each output. Use the following order: description → value → sensitive (optional). Use descriptive nouns with underscores for names.

### 7. Local Values
Use local values sparingly, as overuse makes code harder to understand. If a local value is referenced in multiple files, define it in `locals.tf`. If it's specific to one file, define it at the top of that file.

### 8. Linting
Use a linter such as TFLint to enforce your organization's own coding best practices through static code analysis. Most linters ship with a default set of rules but also let you write your own.

### 9. Comments
Write code so it's self-explanatory. Use `#` for both single- and multi-line comments — the `//` and `/* */` syntaxes are not considered idiomatic.

### 10. Provider Configuration
Always include a default provider configuration (one without an `alias`). Define all providers in the same file. If you define multiple instances of a provider, define the default first, and for non-default providers define the `alias` as the first parameter.

### 11. Dynamic Resource Count (`count` & `for_each`)
Use `count` when resources are almost identical. Use `for_each` when arguments need distinct values that can't be derived from an integer. Use both sparingly — they simplify code but add complexity. If the effect isn't immediately obvious, add a comment for clarification.

### 12. Version Pinning
Pin provider versions using the `required_providers` block and set a minimum required Terraform binary version using `required_version`. For registry modules, use the `version` parameter in the `module` block to pin to a specific major and minor version.

### 13. Module Structure
Use modules to group together logically related resources to standardize resource creation. Store child/local modules in the `./modules/<module_name>` directory. Publish modules to a module registry (such as the HCP Terraform private registry) to easily version, share, and reuse them across your organization.

Module repository names published to the Terraform Registry must follow the three-part convention: `terraform-<PROVIDER>-<name>`.

**Common MLOps Modules:**
- **`vertex_ai`:** Standardize the creation of Endpoints, Datasets, and Pipeline schedules to provision Vertex AI effectively.
- **`iam`:** Manage least-privileged access for service accounts used by ML pipelines.
- **`networking`:** Configure VPC peering for high-performance, private connectivity between BigQuery and Vertex AI.

### 14. Repository Structure
Store each module in its own individual repository so it can be independently versioned. Organize infrastructure configuration into repositories that group together logically related resources. For multiple environments, use separate workspaces (with HCP Terraform) or separate directories (without it), each with its own state file and backend configuration.

### 15. Branching Strategy & CI/CD
Use GitHub Flow: create a new branch from `main`, write and push changes, open a pull request, review with your team, merge, and delete the branch. Your `main` branch should be the source of truth for all environments.

**Plan Review & CI/CD:** Always run `terraform plan` and store the output for review before applying changes in production. Use tools like GitHub Actions to automate the infrastructure rollout alongside your code changes.

### 16. State Management & Sharing
The state file is the source of truth for your infrastructure. **Always use a remote backend** (e.g., GCS bucket) with state locking to prevent concurrency issues and data loss.

Avoid sharing full state files when possible since state contains sensitive information. If using HCP Terraform or Terraform Enterprise, use the `tfe_outputs` data source to reference resources across workspaces. If not, use provider-specific data sources to query remote infrastructure rather than sharing state.

### 17. Secrets Management
Use dynamic provider credentials to avoid long-lived static credentials. If using Terraform Community Edition, configure provider credentials via environment variables or integrate with HashiCorp Vault (or **Google Secret Manager**) to handle API keys and credentials securely (no hardcoded secrets). For CI/CD pipelines, use your tool's built-in secrets management to pass credentials as environment variables.

### 18. `.gitignore`
Never commit: `terraform.tfstate`, backup state files, `.terraform.tfstate.lock.info`, the `.terraform/` directory, saved plan files (`-out` files), or `.tfvars` files with sensitive data. Always commit: all `.tf` code files, the `.terraform.lock.hcl` dependency lock file, a `.gitignore`, and a `README.md`.

### 19. Testing
Write Terraform tests for your modules and run them as a pre-merge check in pull requests or as a prerequisite step in your CI/CD pipeline. Tests validate the behavior and logic of your code, while features like variable validation, preconditions, and postconditions verify the deployed infrastructure.

### 20. Policy Enforcement (HCP Terraform)
Use policy enforcement to set guardrails for infrastructure operations. Policies can limit instance sizes, check for required tags, block deployments on certain days, and enforce security and cost configurations. Store policies in a separate VCS repository from your Terraform code.

### 21. Workspace & Project Structure
Keep the blast radius of operations small by managing resources in separate workspaces, grouping together only necessary and logically related resources. Use a consistent naming convention to identify and associate workspaces with specific infrastructure components. **Use Terraform Workspaces** to manage `dev`, `staging`, and `prod` with the same codebase.

Use project-level permissions and variable sets to apply credentials and settings to all workspaces in a project. Automate project, variable set, and team creation using the TFE provider. Designate a landing zone project as the base for creating all other projects and workspaces.

---

**Senior MLOps Architect Summary:**
Terraform eliminates "it works on my machine" infrastructure. It is the foundation for Blue-Green Deployments and disaster recovery, ensuring the MLOps lifecycle is automated from the ground up.
