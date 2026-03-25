.PHONY: dev down logs test lint build push plan apply destroy health

# ── Local Development ────────────────────────────────────────────
dev:
	docker compose up --build -d
	@echo ""
	@echo "App:          http://localhost:8000"
	@echo "Grafana:      http://localhost:3000  (admin/admin)"
	@echo "Prometheus:   http://localhost:9090"
	@echo "AlertManager: http://localhost:9093"

down:
	docker compose down

logs:
	docker compose logs -f

logs-app:
	docker compose logs -f app

# ── Testing ──────────────────────────────────────────────────────
test:
	cd app && pip install -r requirements-dev.txt -q && pytest tests/ -v --cov=src

lint:
	pip install ruff -q && ruff check app/

# ── Docker ───────────────────────────────────────────────────────
build:
	docker build -t fullstack-deploy-api:latest ./app

push: build
	@echo "Tag and push to ECR:"
	@echo "  aws ecr get-login-password --region eu-north-1 | docker login --username AWS --password-stdin <ECR_URL>"
	@echo "  docker tag fullstack-deploy-api:latest <ECR_URL>:latest"
	@echo "  docker push <ECR_URL>:latest"

# ── Terraform ────────────────────────────────────────────────────
plan:
	cd terraform && terraform init && terraform plan -var-file=environments/prod/terraform.tfvars

apply:
	cd terraform && terraform init && terraform apply -var-file=environments/prod/terraform.tfvars

destroy:
	cd terraform && terraform destroy -var-file=environments/prod/terraform.tfvars

fmt:
	cd terraform && terraform fmt -recursive

validate:
	cd terraform && terraform init -backend=false && terraform validate

# ── Operations ───────────────────────────────────────────────────
health:
	./scripts/health-check.sh

deploy:
	./scripts/deploy.sh

rollback:
	./scripts/rollback.sh

# ── Cleanup ──────────────────────────────────────────────────────
clean:
	docker compose down -v --rmi all --remove-orphans
	@echo "All containers, volumes, and images removed"
