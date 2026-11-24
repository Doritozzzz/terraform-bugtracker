.DEFAULT_GOAL := help
.PHONY: help init fmt validate docs plan apply up up-all output stop start destroy recreate-db ps demo-deploy demo-talk \
        test-db kill-db start-db test-cache kill-cache start-cache kill-storage start-storage kill-web start-web kill revive status urls passwords test test-alerts demo dist

# Environment for the Terraform targets: dev (default) or prod, e.g. make up ENV=prod.
ENV ?= dev

TF     := terraform -chdir=environments/$(ENV)
# Every container Terraform creates is named bugtracker-<env>-<service>.
PREFIX := bugtracker-$(ENV)

help: ## List the available targets
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

# --------------------------------------------------------------- Terraform
# Same flow as a CI pipeline: plan saves the reviewed changes to tfplan and
# apply executes exactly that plan, never a new one.

init: ## Download providers and link modules (ENV=dev)
	$(TF) init -input=false

fmt: ## Format every .tf file
	terraform fmt -recursive

validate: init ## Check formatting and configuration (ENV=dev)
	terraform fmt -recursive -check
	$(TF) validate

# terraform-docs fills the inputs/outputs tables of every module README from the code.
TERRAFORM_DOCS_IMAGE := quay.io/terraform-docs/terraform-docs:0.25.1

docs: ## Regenerate the inputs/outputs tables of the module READMEs
	@for module in modules/*/; do \
	  docker run --rm -u "$$(id -u):$$(id -g)" -v "$(CURDIR):/repo" -w /repo $(TERRAFORM_DOCS_IMAGE) -c .terraform-docs.yml "$$module" | grep -v 'README.md updated successfully$$'; \
	done; true

plan: init ## Compute the changes and save them to tfplan (ENV=dev)
	$(TF) plan -input=false -out=tfplan

apply: ## Apply the saved tfplan and delete it (ENV=dev)
	$(TF) apply -input=false tfplan
	@rm -f environments/$(ENV)/tfplan

up: ## Plan and apply the environment (ENV=dev)
	@$(MAKE) --no-print-directory plan apply

up-all: ## Bring up dev and prod side by side
	@$(MAKE) --no-print-directory up ENV=dev
	@$(MAKE) --no-print-directory up ENV=prod

output: ## Show the environment outputs, such as the URL (ENV=dev)
	@$(TF) output

stop: ## Stop the containers; volumes and data are kept (ENV=dev)
	docker ps -q --filter name=^$(PREFIX)- | xargs -r docker stop

# docker start instead of terraform apply: with the container stopped, the
# provider no longer sees its published ports and would replace the load
# balancer instead of just starting it.
start: ## Start the stopped containers again (ENV=dev)
	docker ps -a -q --filter name=^$(PREFIX)- --filter status=exited | xargs -r docker start

destroy: ## Delete everything, data volumes included (ENV=dev)
	$(TF) destroy

recreate-db: init ## Replace the database container to prove the data survives (ENV=dev)
	$(TF) plan -input=false -replace=module.database.docker_container.postgres -out=tfplan
	@$(MAKE) --no-print-directory apply

# ---------------------------------------------------------- Demo helpers

ps: ## Show the containers and their health (ENV=dev)
	@docker ps -a --filter name=^$(PREFIX)- --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

test-db: ## Check PostgreSQL and count the incidents (ENV=dev)
	@docker exec $(PREFIX)-db sh -c 'pg_isready -h 127.0.0.1 -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" && psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" -tAc "SELECT count(*) FROM incidents"'

kill-db: ## Stop PostgreSQL to watch the status change (ENV=dev)
	docker stop $(PREFIX)-db

start-db: ## Start PostgreSQL again (ENV=dev)
	docker start $(PREFIX)-db

test-cache: ## Check that Redis answers PONG (ENV=prod)
	@docker exec $(PREFIX)-cache sh -c 'REDISCLI_AUTH="$$REDIS_PASSWORD" redis-cli -h 127.0.0.1 ping'

kill-cache: ## Stop Redis to watch the status change (ENV=prod)
	docker stop $(PREFIX)-cache

start-cache: ## Start Redis again (ENV=prod)
	docker start $(PREFIX)-cache

kill-storage: ## Stop MinIO: /images/ fails and the open page reports it (ENV=dev)
	docker stop $(PREFIX)-storage

start-storage: ## Start MinIO again (ENV=dev)
	docker start $(PREFIX)-storage

# docker stop, not a crash: the restart policy leaves a manually stopped
# container down, so the replica stays down until start-web.
kill-web: ## Stop web replica 2: the others keep serving; in prod it fires an alert (ENV=prod)
	docker stop $(PREFIX)-web-2

start-web: ## Start web replica 2 again (ENV=prod)
	docker start $(PREFIX)-web-2

# Any container of the environment by its short name, e.g. NAME=prometheus or
# NAME=web-3. Also docker stop, so it stays down until revive (and in prod its
# alert fires). An unknown or missing NAME lists the valid ones.
define check_name
	@docker inspect $(PREFIX)-$(NAME) >/dev/null 2>&1 || { \
	  echo "NAME must be one of: $$(docker ps -a --filter name=^$(PREFIX)- --format '{{.Names}}' | sed 's/^$(PREFIX)-//' | sort | paste -sd' ' -)"; \
	  exit 2; }
endef

kill: ## Stop any container by name, e.g. NAME=prometheus or NAME=web-3 (ENV=dev)
	$(check_name)
	docker stop $(PREFIX)-$(NAME)

revive: ## Start a container stopped with kill (NAME=..., ENV=dev)
	$(check_name)
	docker start $(PREFIX)-$(NAME)

# ------------------------------------------------------------------ both

status: ## Show /status of dev and prod
	@for env in dev prod; do \
	  url=$$(terraform -chdir=environments/$$env output -raw app_url 2>/dev/null); \
	  printf '%s: ' $$env; \
	  { [ -n "$$url" ] && curl -s -m 5 "$$url/status"; } || printf 'not running'; \
	  echo; \
	done

# Only the non-secret outputs, so the screen can be shown during a demo.
urls: ## Show the URLs and users of dev and prod (passwords: make passwords)
	@for env in dev prod; do \
	  echo "$$env:"; \
	  terraform -chdir=environments/$$env output 2>/dev/null | grep -v '<sensitive>' | sed 's/^/  /' | grep . || echo '  not deployed'; \
	done

passwords: ## Show the generated passwords of dev and prod
	@for env in dev prod; do \
	  for name in admin_password grafana_password storage_console_password; do \
	    value=$$(terraform -chdir=environments/$$env output -raw $$name 2>/dev/null) && echo "$$env $$name: $$value"; \
	  done; \
	done; true

# promtool ships with Prometheus; the same image the metrics-store module runs.
PROMETHEUS_IMAGE := prom/prometheus:v3.16.0

test-alerts: ## Check the alerting rules and run their unit tests
	@docker run --rm -v "$(CURDIR)/monitoring/alerts:/alerts:ro" -w /alerts --entrypoint promtool $(PROMETHEUS_IMAGE) check rules bugtracker.rules.yml
	@docker run --rm -v "$(CURDIR)/monitoring/alerts:/alerts:ro" -w /alerts --entrypoint promtool $(PROMETHEUS_IMAGE) test rules bugtracker.test.yml

test: ## Converge dev and prod and verify them end to end (FRESH=1: from nothing)
	@bash scripts/test.sh

demo: ## Guided 10-minute demo; step 1 destroys and deploys everything live
	@bash scripts/demo.sh

demo-deploy: ## Only step 1 of the demo: destroy and deploy both, waiting until done
	@bash scripts/demo.sh --to 1

demo-talk: ## The demo from step 2 (after make demo-deploy)
	@bash scripts/demo.sh --from 2

dist: ## Build dist/terraform-bugtracker.zip from the committed files
	@git diff --quiet HEAD || echo 'warning: uncommitted changes are not in the zip (git archive uses HEAD)'
	@mkdir -p dist
	git archive --format=zip --prefix=terraform-bugtracker/ -o dist/terraform-bugtracker.zip HEAD
	@echo 'built dist/terraform-bugtracker.zip'
