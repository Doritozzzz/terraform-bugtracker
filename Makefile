.DEFAULT_GOAL := help
.DELETE_ON_ERROR:
.PHONY: help init fmt validate plan apply up-dev output stop start destroy recreate-db ps test-db kill-db start-db \
	    setup-env build up-prod down-prod clean-prod test-cache kill-cache start-cache status test demo dist

# Environment for the Terraform targets. Only dev is managed by Terraform so far.
ENV ?= dev

TF     := terraform -chdir=environments/$(ENV)
# Every container Terraform creates is named bugtracker-<env>-<service>.
PREFIX := bugtracker-$(ENV)

dc = docker compose -f docker-compose.$(1).yml --env-file .env.$(1)

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

plan: init ## Compute the changes and save them to tfplan (ENV=dev)
	$(TF) plan -input=false -out=tfplan

apply: ## Apply the saved tfplan and delete it (ENV=dev)
	$(TF) apply -input=false tfplan
	@rm -f environments/$(ENV)/tfplan

up-dev: ## Plan and apply the dev environment
	@$(MAKE) --no-print-directory plan apply ENV=dev

output: ## Show the environment outputs, such as the URL (ENV=dev)
	@$(TF) output

stop: ## Stop the containers; volumes and data are kept (ENV=dev)
	docker ps -q --filter name=^$(PREFIX)- | xargs -r docker stop

# docker start instead of terraform apply: with the container stopped, the
# provider no longer sees its published ports and would replace the load
# balancer instead of just starting it.
start: ## Start the stopped containers again (ENV=dev)
	docker ps -aq --filter name=^$(PREFIX)- --filter status=exited | xargs -r docker start

destroy: ## Delete everything, data volumes included (ENV=dev)
	$(TF) destroy

recreate-db: init ## Replace the database container to prove the data survives (ENV=dev)
	$(TF) plan -input=false -replace=module.database.docker_container.postgres -out=tfplan
	@$(MAKE) --no-print-directory apply

ps: ## Show the containers and their health (ENV=dev)
	@docker ps -a --filter name=^$(PREFIX)- --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

test-db: ## Check PostgreSQL and count the incidents (ENV=dev)
	@docker exec $(PREFIX)-db sh -c 'pg_isready -h 127.0.0.1 -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" && psql -U "$$POSTGRES_USER" -d "$$POSTGRES_DB" -tAc "SELECT count(*) FROM incidents"'

kill-db: ## Stop PostgreSQL to watch the status change (ENV=dev)
	docker stop $(PREFIX)-db

start-db: ## Start PostgreSQL again (ENV=dev)
	docker start $(PREFIX)-db

# ------------------------------------------- Docker Compose (prod, until migrated)

setup-env: .env.prod ## Create .env.prod with random secrets (mode 600)
	@chmod 600 .env.prod
	@echo "environment file ready"

# Created only when it does not exist. The template is an order-only
# prerequisite: PostgreSQL stores its password in the data volume on first
# start, so regenerating a secret would lock the web out.
.env.prod: | .env.prod.example
	@( umask 077; \
	  while IFS= read -r line; do \
	    case "$$line" in *=CHANGE_ME) line="$${line%CHANGE_ME}$$(openssl rand -hex 24)";; esac; \
	    printf '%s\n' "$$line"; \
	  done < .env.prod.example > $@ )
	@chmod 600 $@
	@echo "created $@"

build: .env.prod ## Build the prod web image
	$(call dc,prod) build

up-prod: .env.prod ## Start the prod environment (web + db + cache)
	$(call dc,prod) up -d --build --wait
	@echo "prod ready: http://127.0.0.1:$$(sed -n 's/^WEB_PORT=//p' .env.prod)"

down-prod: .env.prod ## Stop prod (containers and networks removed, data kept)
	$(call dc,prod) down

clean-prod: .env.prod ## Like down-prod, and also delete the data volume and built image
	$(call dc,prod) down -v --rmi local

test-cache: .env.prod ## Check that Redis answers PONG (prod)
	@$(call dc,prod) exec -T cache sh -c 'REDISCLI_AUTH="$$REDIS_PASSWORD" redis-cli -h 127.0.0.1 ping'

kill-cache: .env.prod ## Stop Redis to watch the status change (prod)
	$(call dc,prod) stop cache

start-cache: .env.prod ## Start Redis again (prod)
	$(call dc,prod) start cache

# ------------------------------------------------------------------ both

status: ## Show /status of every running environment
	@printf 'dev: '; curl -s -m 5 "$$($(TF) output -raw app_url 2>/dev/null)/status" || printf 'not running'; echo
	@port=$$(sed -n 's/^WEB_PORT=//p' .env.prod 2>/dev/null); \
	  printf 'prod: '; [ -n "$$port" ] && curl -s -m 5 "http://127.0.0.1:$$port/status" || printf 'not running'; echo

test: ## Run every verification from scratch (P1 suite, being migrated)
	@bash scripts/test.sh

demo: ## Run the guided demonstration (P1 version, being migrated)
	@bash scripts/demo.sh

dist: .env.prod ## Build dist/terraform-bugtracker.zip: committed files plus the local .env.prod
	@git diff --quiet HEAD || echo 'warning: uncommitted changes are not in the zip (git archive uses HEAD)'
	@rm -rf dist && mkdir -p dist/terraform-bugtracker
	git archive HEAD | tar -x -C dist/terraform-bugtracker
	cp .env.prod dist/terraform-bugtracker/
	chmod 600 dist/terraform-bugtracker/.env.prod
	cd dist && python3 -m zipfile -c terraform-bugtracker.zip terraform-bugtracker
	@rm -rf dist/terraform-bugtracker
	@echo 'built dist/terraform-bugtracker.zip'
