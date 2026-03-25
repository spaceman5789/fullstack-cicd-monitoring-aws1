# Full-Stack Deploy: Terraform + GitLab CI/CD + Monitoring

> Полная автоматизация от коммита до production на AWS с мониторингом и алертами.

Этот проект демонстрирует **end-to-end DevOps-пайплайн**: инфраструктура разворачивается через Terraform, код доставляется через GitLab CI/CD, а Prometheus + Grafana + AlertManager следят за здоровьем системы 24/7.

---

## Что делает этот проект

1. **Ты пушишь код** → GitLab автоматически прогоняет тесты, линтеры и сканеры безопасности
2. **Создаёшь Merge Request** → GitLab показывает `terraform plan` прямо в комментарии — какие ресурсы изменятся
3. **Мержишь в main** → собирается Docker-образ, пушится в ECR, Terraform обновляет инфраструктуру, приложение катится на staging автоматически
4. **Нажимаешь кнопку** → деплой на production (ручной триггер — защита от случайного выката)
5. **Мониторинг** → Grafana-дашборды показывают latency, error rate, CPU/memory. Если что-то сломалось — алерт на почту и в Slack

**Ноль ручных действий** между коммитом и production (кроме финального подтверждения).

---

## Архитектура

```
                    ┌───────────────────────────────────────────────────┐
                    │                  AWS VPC 10.0.0.0/16              │
                    │                                                   │
                    │   Public Subnets                                  │
                    │   ┌─────────────┐       ┌──────────────────┐     │
  Internet ────────►│   │     ALB     │       │  Monitoring EC2  │     │
                    │   │   (HTTP:80) │       │                  │     │
                    │   └──────┬──────┘       │  Prometheus:9090 │     │
                    │          │              │  Grafana:3000    │     │
                    │          │              │  AlertManager:9093│     │
                    │          │              └──────────────────┘     │
                    │          ▼                                        │
                    │   Private App Subnets                             │
                    │   ┌─────────────────────────────┐                │
                    │   │   EC2 Auto Scaling Group     │                │
                    │   │                              │                │
                    │   │  ┌──────────┐ ┌──────────┐  │                │
                    │   │  │ App EC2  │ │ App EC2  │  │                │
                    │   │  │  :8000   │ │  :8000   │  │                │
                    │   │  └──────────┘ └──────────┘  │                │
                    │   └──────────────┬──────────────┘                │
                    │                  │                                │
                    │          NAT Gateway (outbound internet)          │
                    │                  │                                │
                    │                  ▼                                │
                    │   Private DB Subnets                              │
                    │   ┌─────────────────────────────┐                │
                    │   │    RDS PostgreSQL 16         │                │
                    │   │    (db.t3.small, encrypted)  │                │
                    │   └─────────────────────────────┘                │
                    └───────────────────────────────────────────────────┘
```

### Как трафик проходит через систему

```
Пользователь → ALB (порт 80) → EC2 инстанс (порт 8000) → RDS PostgreSQL (порт 5432)
```

- **ALB** принимает HTTP-запросы из интернета и распределяет их между EC2 инстансами
- **EC2 инстансы** находятся в приватной подсети — к ним нельзя подключиться напрямую из интернета
- **RDS** тоже в приватной подсети — доступ только от EC2 инстансов приложения
- **NAT Gateway** позволяет приватным инстансам выходить в интернет (для обновлений и скачивания Docker-образов)

### Безопасность (Security Groups)

```
ALB SG:  принимает HTTP/HTTPS от 0.0.0.0/0 (весь интернет)
     ↓
App SG:  принимает порт 8000 ТОЛЬКО от ALB SG
     ↓
RDS SG:  принимает порт 5432 ТОЛЬКО от App SG
```

Каждый уровень доступен только с предыдущего. Базу данных невозможно достать из интернета.

---

## CI/CD Pipeline (GitLab)

### При создании Merge Request

GitLab запускает проверки **до того, как код попадёт в main**:

| Job | Что делает | Зачем |
|-----|-----------|-------|
| `lint` | Проверка кода линтером ruff | Единый стиль кода |
| `dockerfile-lint` | Проверка Dockerfile (hadolint) | Best practices в Docker |
| `terraform-validate` | `terraform fmt` + `validate` | Корректность Terraform-кода |
| `tfsec` | Сканирование Terraform на уязвимости | Безопасность инфраструктуры |
| `test` | Pytest + coverage report | Код работает, покрытие видно в MR |
| `docker-build` | Сборка Docker-образа | Dockerfile собирается без ошибок |
| `trivy-scan` | Сканирование образа на CVE | Нет критических уязвимостей |
| `terraform-plan` | Plan + комментарий в MR | Видно, что изменится в AWS |

### При мерже в main

```
test → build-push-ecr → terraform-apply-staging → deploy-staging → [terraform-apply-prod] → [deploy-prod] → notify
                                                                    └── manual trigger ──┘
```

| Job | Что делает | Автоматически? |
|-----|-----------|---------------|
| `build-push-ecr` | Собирает Docker-образ, пушит в ECR (теги: SHA, latest, branch) | Да |
| `terraform-apply-staging` | Применяет Terraform для staging-окружения | Да |
| `deploy-staging` | Катит новую версию на staging через ASG instance refresh | Да |
| `terraform-apply-prod` | Применяет Terraform для production | **Нет — кнопка** |
| `deploy-prod` | Катит на production | **Нет — кнопка** |
| `notify-success/failure` | Шлёт уведомление в SNS | Да |

### Визуально

```
┌──────────┐   ┌──────┐   ┌───────┐   ┌─────────────────────┐   ┌────────┐
│ validate │──►│ test │──►│ build │──►│ deploy              │──►│ notify │
│          │   │      │   │       │   │                     │   │        │
│ lint     │   │pytest│   │docker │   │ staging (auto)      │   │ SNS    │
│ hadolint │   │trivy │   │push   │   │ production (manual) │   │ email  │
│ tf valid │   │build │   │to ECR │   │                     │   │ slack  │
│ tfsec    │   │plan  │   │       │   │                     │   │        │
└──────────┘   └──────┘   └───────┘   └─────────────────────┘   └────────┘
```

---

## Приложение

REST API на **FastAPI** (Python 3.12) с CRUD-операциями и встроенными Prometheus-метриками.

### Эндпоинты

| Метод | URL | Описание |
|-------|-----|----------|
| GET | `/` | Информация о сервисе (версия, окружение) |
| GET | `/health` | Liveness probe — всегда 200, если процесс жив |
| GET | `/ready` | Readiness probe — проверяет подключение к БД |
| GET | `/api/items` | Список всех записей |
| POST | `/api/items` | Создать запись `{"name": "...", "description": "..."}` |
| GET | `/api/items/{id}` | Получить запись по ID |
| DELETE | `/api/items/{id}` | Удалить запись |
| GET | `/metrics` | Prometheus-метрики |

### Метрики, которые собирает приложение

| Метрика | Тип | Что измеряет |
|---------|-----|-------------|
| `http_requests_total` | Counter | Общее количество запросов (по методу, эндпоинту, статус-коду) |
| `http_request_duration_seconds` | Histogram | Время ответа (p50, p95, p99) |
| `http_active_requests` | Gauge | Сколько запросов обрабатывается прямо сейчас |
| `db_connection_errors_total` | Counter | Ошибки подключения к БД |
| `app_info` | Gauge | Версия и окружение приложения |

### Docker-образ

- **Multi-stage build** — сборочные зависимости не попадают в финальный образ
- **Non-root user** — контейнер запускается от `appuser`, а не от root
- **HEALTHCHECK** — Docker сам проверяет, жив ли контейнер
- Базовый образ: `python:3.12-slim`

---

## Terraform — инфраструктура как код

Вся AWS-инфраструктура описана в **8 модулях**. Каждый модуль отвечает за свой слой:

### Модули

| Модуль | Что создаёт | Ключевые ресурсы |
|--------|-----------|-----------------|
| **vpc** | Сеть | VPC, 6 подсетей (2 public + 2 app + 2 db), Internet Gateway, NAT Gateway, Route Tables |
| **ec2** | Вычисления | Launch Template, Auto Scaling Group (min 1 / max 4), IAM Role (ECR pull + Secrets Manager + CloudWatch) |
| **rds** | База данных | PostgreSQL 16, Secrets Manager (пароль), DB Subnet Group, 7-дневные бэкапы |
| **ecr** | Реестр образов | ECR Repository, Lifecycle Policy (хранит 10 последних образов) |
| **alb** | Балансировщик | ALB, Target Group, HTTP Listener, Health Check (/health) |
| **monitoring** | Мониторинг | EC2 инстанс с Docker Compose (Prometheus + Grafana + AlertManager + node-exporter) |
| **cloudwatch** | Логи и алармы | Log Group, 6 метрик-алармов (ALB 5xx, ALB latency, ASG CPU, RDS CPU, RDS connections, RDS storage) |
| **sns** | Уведомления | SNS Topic, Email-подписка, Lambda для Slack |

### Окружения

```
terraform/environments/
├── staging/terraform.tfvars    # 1 × t3.micro, db.t3.micro, 20 GB
└── prod/terraform.tfvars       # 2 × t3.small, db.t3.small, 50 GB
```

### Terraform State

- Хранится в **S3** (зашифрован, версионирован)
- Блокировка через **DynamoDB** — два человека не смогут применить `terraform apply` одновременно

---

## Мониторинг и алерты

### Стек мониторинга

На отдельном EC2 инстансе крутятся 4 контейнера:

```
┌─────────────────────────────────────────────────────┐
│               Monitoring EC2 Instance                │
│                                                      │
│  ┌──────────────┐  ┌──────────────┐                 │
│  │  Prometheus   │  │   Grafana    │                 │
│  │  :9090        │  │   :3000      │                 │
│  │              ◄├──┤  (dashboards)│                 │
│  │  scrapes:     │  └──────────────┘                 │
│  │  - app:8000   │                                   │
│  │  - node:9100  │  ┌──────────────┐                 │
│  │               │  │ AlertManager │                 │
│  │              ─├──►  :9093       │                 │
│  └──────────────┘  └──────────────┘                 │
│                                                      │
│  ┌──────────────┐                                    │
│  │node-exporter │  Собирает CPU, RAM, disk           │
│  │  :9100       │  с самого хоста                    │
│  └──────────────┘                                    │
└─────────────────────────────────────────────────────┘
```

**Prometheus** каждые 15 секунд опрашивает:
- Все EC2-инстансы приложения (auto-discovery по тегу `Name`) — метрики приложения
- node-exporter на каждом инстансе — метрики системы (CPU, RAM, диск, сеть)

### Grafana Dashboards (экспортированные JSON)

**Application Overview** — здоровье приложения:
- Request Rate (запросы/сек по эндпоинтам)
- Error Rate (% ошибок 4xx и 5xx)
- Latency p50 / p95 / p99 (время ответа)
- Active Requests (запросы в обработке прямо сейчас)
- DB Connection Errors (ошибки подключения к БД)
- Requests by Status Code (круговая диаграмма)

**System Metrics** — здоровье серверов:
- CPU Usage % (по каждому инстансу)
- Memory Usage % (по каждому инстансу)
- Disk Usage % (gauge)
- Network I/O (входящий/исходящий трафик)
- System Load (1m / 5m / 15m)
- Open File Descriptors

### Алерты

Двойная система алертинга — Prometheus + CloudWatch:

**Prometheus → AlertManager:**

| Алерт | Порог | Severity |
|-------|-------|----------|
| High Error Rate | 5xx > 5% за 2 мин | Critical |
| High Latency p95 | > 1 сек за 3 мин | Warning |
| High Latency p99 | > 2.5 сек за 3 мин | Critical |
| Instance Down | up == 0 за 1 мин | Critical |
| High CPU | > 80% за 5 мин | Warning |
| High Memory | > 85% за 5 мин | Warning |
| Disk Space Low | > 85% за 5 мин | Warning |

**CloudWatch → SNS → Email/Slack:**

| Алерт | Порог |
|-------|-------|
| ALB 5xx Count | > 10 за 5 мин |
| ALB Latency p95 | > 2 сек за 15 мин |
| ASG CPU | > 80% за 15 мин |
| RDS CPU | > 80% за 15 мин |
| RDS Connections | > 80 |
| RDS Free Storage | < 2 GB |

---

## Структура проекта

```
.
├── .gitlab-ci.yml                  # GitLab CI/CD: 5 стадий, 13 джобов
│
├── app/                            # Приложение
│   ├── src/main.py                 #   FastAPI + Prometheus-метрики (220 строк)
│   ├── tests/test_main.py          #   10 unit-тестов (pytest)
│   ├── Dockerfile                  #   Multi-stage, non-root, HEALTHCHECK
│   ├── requirements.txt            #   fastapi, uvicorn, psycopg2, prometheus-client
│   └── requirements-dev.txt        #   pytest, httpx, coverage
│
├── terraform/                      # Инфраструктура (Terraform)
│   ├── main.tf                     #   Корневой модуль + Security Groups
│   ├── variables.tf                #   Все переменные
│   ├── outputs.tf                  #   VPC ID, ALB DNS, Grafana URL и т.д.
│   ├── providers.tf                #   AWS provider + default tags
│   ├── backend.tf                  #   S3 remote state + DynamoDB lock
│   ├── modules/
│   │   ├── vpc/                    #   Сеть (VPC, подсети, NAT, IGW)
│   │   ├── ec2/                    #   Compute (ASG, Launch Template, IAM, user_data)
│   │   ├── rds/                    #   БД (PostgreSQL, Secrets Manager)
│   │   ├── ecr/                    #   Docker-реестр (lifecycle policy)
│   │   ├── alb/                    #   Балансировщик (Target Group, Listener)
│   │   ├── monitoring/             #   Мониторинг-сервер (Docker Compose внутри)
│   │   ├── cloudwatch/             #   Логи + 6 алармов
│   │   └── sns/                    #   Email + Slack Lambda
│   └── environments/
│       ├── staging/terraform.tfvars
│       └── prod/terraform.tfvars
│
├── monitoring/                     # Конфиги мониторинга
│   ├── prometheus/
│   │   ├── prometheus.yml          #   Scrape-конфиг (app + node-exporter)
│   │   └── alerts.yml              #   7 alert rules
│   ├── grafana/
│   │   ├── dashboards/
│   │   │   ├── app-overview.json   #   Дашборд приложения (7 панелей)
│   │   │   └── system-metrics.json #   Дашборд системы (7 панелей)
│   │   └── provisioning/           #   Auto-provisioning datasource + dashboards
│   └── alertmanager/
│       └── alertmanager.yml        #   Routing rules
│
├── scripts/                        # Операционные скрипты
│   ├── deploy.sh                   #   Rolling deploy через ASG instance refresh
│   ├── rollback.sh                 #   Откат к предыдущей версии Launch Template
│   ├── health-check.sh             #   Проверка всех компонентов (ALB, TG, RDS, CW)
│   └── setup-monitoring.sh         #   Загрузка конфигов на мониторинг-сервер
│
├── docs/                           # Документация
│   ├── runbook.md                  #   Инструкции по эксплуатации (деплой, откат, инциденты)
│   ├── cost-breakdown.md           #   Разбивка стоимости по ресурсам
│   └── adr/                        #   Architecture Decision Records
│       ├── 001-gitlab-cicd.md      #     Почему GitLab CI, а не Jenkins/GitHub Actions
│       ├── 002-monitoring-stack.md #     Почему Prometheus+Grafana, а не только CloudWatch
│       └── 003-vpc-network-design.md #   Почему 3-tier VPC с двумя AZ
│
├── docker-compose.yml              # Локальная разработка (app + PG + Prometheus + Grafana)
├── Makefile                        # Короткие команды (make dev, make test, make deploy)
├── .env.example                    # Шаблон переменных окружения
└── .gitignore
```

---

## Быстрый старт

### Локальная разработка

```bash
# 1. Скопировать переменные окружения
cp .env.example .env

# 2. Поднять всё одной командой
make dev

# 3. Открыть в браузере:
#    Приложение:   http://localhost:8000
#    Grafana:      http://localhost:3000  (логин: admin / пароль: admin)
#    Prometheus:   http://localhost:9090
#    AlertManager: http://localhost:9093

# 4. Проверить API
curl http://localhost:8000/health
curl http://localhost:8000/api/items
curl -X POST http://localhost:8000/api/items -H "Content-Type: application/json" -d '{"name":"test"}'
```

### Запуск тестов

```bash
make test    # pytest + coverage
make lint    # ruff (линтер)
```

### Деплой на AWS

**Что нужно заранее:**
1. AWS аккаунт с IAM-пользователем (права на EC2, RDS, ECR, ALB, VPC, CloudWatch, SNS, Secrets Manager, S3, DynamoDB)
2. S3 bucket для Terraform state (`fullstack-deploy-tfstate`)
3. DynamoDB table для блокировок (`terraform-lock`)
4. GitLab-репозиторий с настроенными CI/CD Variables

```bash
# Ручной деплой (без CI/CD):

# 1. Посмотреть план изменений
make plan

# 2. Применить инфраструктуру
make apply

# 3. Собрать и запушить Docker-образ в ECR
make push

# 4. Выкатить приложение (rolling update через ASG)
make deploy

# 5. Проверить, что всё работает
make health
```

### Настройка GitLab CI/CD Variables

В GitLab: **Settings → CI/CD → Variables** (отметить masked + protected):

| Переменная | Описание | Пример |
|-----------|----------|--------|
| `AWS_ACCESS_KEY_ID` | IAM access key | `AKIA...` |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key (masked) | `wJal...` |
| `ALERT_EMAIL` | Email для алертов | `alerts@example.com` |
| `SLACK_WEBHOOK_URL` | Slack webhook (опционально) | `https://hooks.slack.com/...` |
| `SNS_TOPIC_ARN` | ARN SNS-топика для уведомлений | `arn:aws:sns:eu-north-1:...` |
| `GITLAB_API_TOKEN` | Для комментариев в MR | `glpat-...` |

---

## Стоимость AWS-ресурсов

| Окружение | Стоимость в месяц | Основные расходы |
|-----------|-------------------|-----------------|
| **Staging** | ~$90 | NAT Gateway ($35), ALB ($18), RDS ($15), EC2 ($8) |
| **Production** | ~$136 | NAT Gateway ($35), EC2 x2 ($30), RDS ($28), ALB ($18) |

Подробная разбивка: [docs/cost-breakdown.md](docs/cost-breakdown.md)

---

## Полезные команды (Makefile)

| Команда | Что делает |
|---------|-----------|
| `make dev` | Поднять локальное окружение (app + DB + мониторинг) |
| `make down` | Остановить |
| `make test` | Запустить тесты |
| `make lint` | Проверить код линтером |
| `make build` | Собрать Docker-образ |
| `make plan` | Terraform plan |
| `make apply` | Terraform apply |
| `make deploy` | Rolling deploy на AWS |
| `make rollback` | Откатить на предыдущую версию |
| `make health` | Проверить здоровье всех компонентов |
| `make clean` | Удалить все контейнеры, volumes, образы |

---

## Технологии

| Категория | Технологии |
|-----------|-----------|
| **Приложение** | Python 3.12, FastAPI, Uvicorn, psycopg2, prometheus-client |
| **Тестирование** | pytest, pytest-cov, httpx, ruff |
| **Контейнеризация** | Docker (multi-stage), Docker Compose |
| **CI/CD** | GitLab CI/CD (5 stages, 13 jobs), Docker-in-Docker |
| **Инфраструктура** | Terraform 1.7+ (8 модулей), AWS (EC2, ALB, RDS, ECR, VPC, S3) |
| **Мониторинг** | Prometheus, Grafana 10, AlertManager, node-exporter |
| **Логи и алармы** | CloudWatch Logs, CloudWatch Alarms |
| **Уведомления** | SNS, Lambda (Slack webhook) |
| **Безопасность** | Secrets Manager, tfsec, Trivy, hadolint, Security Groups |

---

## Документация

| Документ | Описание |
|----------|----------|
| [docs/runbook.md](docs/runbook.md) | Инструкции по эксплуатации: деплой, откат, инциденты, troubleshooting |
| [docs/cost-breakdown.md](docs/cost-breakdown.md) | Разбивка стоимости AWS-ресурсов для staging и production |
| [docs/adr/001-gitlab-cicd.md](docs/adr/001-gitlab-cicd.md) | ADR: почему выбран GitLab CI/CD |
| [docs/adr/002-monitoring-stack.md](docs/adr/002-monitoring-stack.md) | ADR: почему Prometheus + Grafana + CloudWatch |
| [docs/adr/003-vpc-network-design.md](docs/adr/003-vpc-network-design.md) | ADR: почему 3-tier VPC с двумя AZ |

---

## Связанные проекты

Этот проект объединяет и развивает три предыдущих:

| # | Проект | Что демонстрирует | Что взято в проект 6 |
|---|--------|-------------------|---------------------|
| 3 | [aws-infrastructure-terraform](https://github.com/spaceman5789/aws-infrastructure-terraform) | Terraform-модули (VPC, EC2, RDS) | Модульная структура, Security Groups, remote state |
| 4 | [gitlab-ci-ec2-deploy](https://github.com/spaceman5789/gitlab-ci-ec2-deploy) | GitLab CI/CD пайплайн | Multi-stage pipeline, Docker build, deploy через SSH |
| 5 | [multi-service-observability-stack](https://github.com/spaceman5789/multi-service-observability-stack) | Prometheus + Grafana мониторинг | Scrape-конфиги, Grafana dashboards, alert rules |
| **6** | **Этот проект** | **Всё вместе** | Terraform + GitLab CI/CD + мониторинг + CloudWatch + SNS |
