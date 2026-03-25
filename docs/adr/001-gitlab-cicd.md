# ADR-001: GitLab CI/CD for Pipeline Automation

## Status
Accepted

## Context
We need a CI/CD platform to automate testing, building Docker images, pushing to ECR, and deploying to AWS EC2 instances. We need to choose between GitLab CI, GitHub Actions, Jenkins, and AWS CodePipeline.

## Decision
Use **GitLab CI/CD** as the CI/CD platform.

## Rationale

| Criteria | GitLab CI | GitHub Actions | Jenkins | CodePipeline |
|----------|-----------|---------------|---------|-------------|
| Built-in features | SCM + CI/CD + Registry + Environments | CI/CD only | CI/CD only | CI/CD only |
| Docker support | Native (DinD, Kaniko) | Good | Good (plugins) | Via CodeBuild |
| Environments & approval gates | Built-in | Limited | Plugins | Manual approval |
| Pipeline visualization | Excellent (DAG view) | Good | Plugin-dependent | Basic |
| YAML workflow | Yes (`.gitlab-ci.yml`) | Yes (multi-file) | Groovy | JSON/YAML |
| Self-hosted runners | Free, easy setup | Possible | Native | Managed only |

**Key factors:**
1. **Single platform** — SCM, CI/CD, container registry, and environments in one place
2. **Built-in environments** — staging/production with manual approval gates natively supported
3. **MR integration** — terraform plan results posted directly as MR notes
4. **Docker-in-Docker** — native support via `services: [docker:dind]`
5. **Cobertura coverage** — test coverage displayed directly in MR diffs
6. **Consistency** — aligns with project 4 (gitlab-ci-ec2-deploy), demonstrating progression from simple to complex pipelines

## Pipeline Design

```
5 stages, 13 jobs:

validate:  lint, dockerfile-lint, terraform-validate, tfsec
test:      test, docker-build, trivy-scan, terraform-plan (MR only)
build:     build-push-ecr (main only)
deploy:    terraform-apply-staging (auto) → deploy-staging (auto)
           terraform-apply-prod (manual) → deploy-prod (manual)
notify:    notify-success / notify-failure
```

## Consequences
- **Positive:** Unified platform, native environment support, MR-integrated terraform plans, coverage in diffs, progression from project 4
- **Negative:** Requires GitLab instance or SaaS subscription for advanced features (merge trains, DAST)
- **Trade-off:** 400 free CI/CD minutes/month on SaaS (vs GitHub's 2000), mitigated by self-hosted runners
