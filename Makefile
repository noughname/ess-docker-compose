.PHONY: help check-prereqs generate-secrets setup-env generate-synapse-config configure-synapse-db configure-mas configure-element create-dirs start-postgres wait-postgres start-all verify create-admin logs status stop clean backup update configure-all deploy

# Use bash as shell for all commands
SHELL := /bin/bash

# Default target
.DEFAULT_GOAL := help

# Colors for output
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[0;33m
RED := \033[0;31m
NC := \033[0m # No Color

##@ General

help: ## Display this help message
	@echo -e "$(CYAN)Matrix Server Setup Automation$(NC)"
	@echo -e ""
	@echo -e "$(YELLOW)Usage:$(NC) make [target]"
	@echo -e ""
	@awk 'BEGIN {FS = ":.*##"; printf "\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(CYAN)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(YELLOW)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Phase 1: Preparation

check-prereqs: ## Check prerequisites (Docker, Docker Compose, etc.)
	@echo -e "$(CYAN)Checking prerequisites...$(NC)"
	@bash scripts/check-prereqs.sh

generate-secrets: ## Generate all required secrets and save to secrets.env
	@echo -e "$(CYAN)Generating secrets...$(NC)"
	@bash scripts/generate-secrets.sh
	@echo -e "$(GREEN)✓ Secrets generated and saved to secrets.env$(NC)"
	@echo -e "$(YELLOW)⚠ Keep this file secure and add it to .gitignore!$(NC)"

setup-env: ## Copy .env template and guide secret insertion
	@echo -e "$(CYAN)Setting up environment file...$(NC)"
	@if [ ! -f .env ]; then \
		cp templates/.env.template .env; \
		echo -e "$(GREEN)✓ Created .env from template$(NC)"; \
		echo -e "$(YELLOW)Next steps:$(NC)"; \
		echo "  1. Run 'make generate-secrets' to generate secrets"; \
		echo "  2. Copy values from secrets.env to .env"; \
		echo "  3. Update MATRIX_DOMAIN and ELEMENT_DOMAIN in .env"; \
	else \
		echo -e "$(YELLOW)⚠ .env already exists, skipping...$(NC)"; \
	fi

setup-env-interactive: generate-secrets ## Interactive setup: generate secrets, copy to .env, and prompt for domains
	@bash scripts/setup-env-interactive.sh

##@ Phase 2: Configuration

generate-synapse-config: ## Generate Synapse homeserver.yaml
	@echo -e "$(CYAN)Generating Synapse configuration...$(NC)"
	@if [ ! -f .env ]; then \
		echo -e "$(RED)✗ .env file not found. Run 'make setup-env' first$(NC)"; \
		exit 1; \
	fi; \
	source .env && \
	if [ -z "$$MATRIX_DOMAIN" ] || [ "$$MATRIX_DOMAIN" = "CHANGE_ME" ]; then \
		echo -e "$(RED)✗ MATRIX_DOMAIN not set in .env$(NC)"; \
		exit 1; \
	fi; \
	if [ -f synapse/data/homeserver.yaml ]; then \
		echo -e "$(YELLOW)⚠ homeserver.yaml already exists, skipping generation$(NC)"; \
		echo -e "$(YELLOW)  To regenerate, remove synapse/data/homeserver.yaml first$(NC)"; \
	else \
		mkdir -p synapse/data && \
		docker run --rm \
			-v "$$(pwd)/synapse/data:/data" \
			-e SYNAPSE_SERVER_NAME=$$MATRIX_DOMAIN \
			-e SYNAPSE_REPORT_STATS=no \
			matrixdotorg/synapse:latest generate; \
		echo -e "$(GREEN)✓ Synapse configuration generated$(NC)"; \
	fi

configure-synapse-db: ## Update Synapse homeserver.yaml with PostgreSQL config
	@echo -e "$(CYAN)Configuring Synapse database...$(NC)"
	@bash scripts/configure-synapse-db.sh
	@echo -e "$(GREEN)✓ Synapse database configuration updated$(NC)"

configure-mas: ## Copy and configure MAS config with secrets
	@echo -e "$(CYAN)Configuring Matrix Authentication Service...$(NC)"
	@bash scripts/configure-mas.sh
	@echo -e "$(GREEN)✓ MAS configuration created$(NC)"
	@echo -e "$(YELLOW)⚠ You may need to manually add the EC private key to mas/config/config.yaml$(NC)"

configure-element: ## Copy and configure Element Web
	@echo -e "$(CYAN)Configuring Element Web...$(NC)"
	@bash scripts/configure-element.sh
	@echo -e "$(GREEN)✓ Element Web configuration created$(NC)"

configure-all: configure-synapse-db configure-mas configure-element ## Configure all services (Synapse, MAS, Element)
	@echo -e "$(GREEN)✓ All configurations completed$(NC)"

##@ Phase 3: Deployment

create-dirs: ## Create necessary data directories
	@echo -e "$(CYAN)Creating data directories...$(NC)"
	@mkdir -p postgres/data mas/data element-admin/data
	@echo -e "$(GREEN)✓ Data directories created$(NC)"

start-postgres: create-dirs ## Start PostgreSQL only
	@echo -e "$(CYAN)Starting PostgreSQL...$(NC)"
	@docker compose up -d postgres
	@echo -e "$(GREEN)✓ PostgreSQL started$(NC)"

wait-postgres: ## Wait for PostgreSQL to be ready
	@echo -e "$(CYAN)Waiting for PostgreSQL to be ready...$(NC)"
	@bash scripts/wait-for-postgres.sh
	@echo -e "$(GREEN)✓ PostgreSQL is ready$(NC)"

start-all: start-postgres wait-postgres ## Start all services
	@echo -e "$(CYAN)Starting all services...$(NC)"
	@docker compose up -d
	@echo -e "$(GREEN)✓ All services started$(NC)"
	@echo -e ""
	@echo -e "$(YELLOW)Monitoring startup (press Ctrl+C to exit logs view):$(NC)"
	@sleep 2
	@docker compose logs -f

deploy: create-dirs start-all ## Full deployment (create dirs, start postgres, wait, start all)
	@echo -e "$(GREEN)✓ Deployment complete!$(NC)"

##@ Phase 4: Verification & User Management

verify: ## Verify all services are running correctly
	@echo -e "$(CYAN)Verifying deployment...$(NC)"
	@bash scripts/verify-deployment.sh

create-admin: ## Create admin user interactively
	@echo -e "$(CYAN)Creating admin user...$(NC)"
	@docker compose exec mas mas-cli manage register-user admin --admin
	@echo -e "$(GREEN)✓ Admin user created$(NC)"

create-user: ## Create regular user interactively (Usage: make create-user USERNAME=john)
	@if [ -z "$(USERNAME)" ]; then \
		echo -e "$(RED)✗ USERNAME not specified$(NC)"; \
		echo -e "$(YELLOW)Usage: make create-user USERNAME=john$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(CYAN)Creating user: $(USERNAME)$(NC)"
	@docker compose exec mas mas-cli manage register-user $(USERNAME)
	@echo -e "$(GREEN)✓ User $(USERNAME) created$(NC)"

list-users: ## List all registered users
	@echo -e "$(CYAN)Listing users...$(NC)"
	@docker compose exec mas mas-cli manage list-users

##@ Monitoring & Maintenance

status: ## Show status of all services
	@echo -e "$(CYAN)Service Status:$(NC)"
	@docker compose ps

logs: ## Show logs (Usage: make logs SERVICE=synapse or make logs for all)
	@if [ -z "$(SERVICE)" ]; then \
		docker compose logs -f; \
	else \
		docker compose logs -f $(SERVICE); \
	fi

logs-errors: ## Show only error logs
	@echo -e "$(CYAN)Searching for errors in logs...$(NC)"
	@docker compose logs --tail=100 | grep -i error || echo -e "$(GREEN)No errors found$(NC)"

restart: ## Restart all services (Usage: make restart SERVICE=synapse or make restart for all)
	@if [ -z "$(SERVICE)" ]; then \
		echo -e "$(CYAN)Restarting all services...$(NC)"; \
		docker compose restart; \
	else \
		echo -e "$(CYAN)Restarting $(SERVICE)...$(NC)"; \
		docker compose restart $(SERVICE); \
	fi
	@echo -e "$(GREEN)✓ Restart complete$(NC)"

##@ Backup & Recovery

backup: ## Backup database and configurations
	@echo -e "$(CYAN)Creating backup...$(NC)"
	@mkdir -p backups
	@BACKUP_NAME="matrix-backup-$$(date +%Y%m%d-%H%M%S)"; \
	echo -e "$(CYAN)Backing up database...$(NC)"; \
	docker compose exec -T postgres pg_dump -U synapse synapse > "backups/$$BACKUP_NAME.sql"; \
	echo -e "$(CYAN)Backing up data directories and configs...$(NC)"; \
	tar -czf "backups/$$BACKUP_NAME.tar.gz" \
		postgres/data \
		synapse/data \
		mas/data \
		.env \
		mas/config \
		element/config \
		2>/dev/null || true; \
	echo -e "$(GREEN)✓ Backup created: backups/$$BACKUP_NAME.*$(NC)"

restore-db: ## Restore database from backup (Usage: make restore-db BACKUP=backups/matrix-backup-20260219.sql)
	@if [ -z "$(BACKUP)" ]; then \
		echo -e "$(RED)✗ BACKUP file not specified$(NC)"; \
		echo -e "$(YELLOW)Usage: make restore-db BACKUP=backups/matrix-backup-20260219.sql$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(YELLOW)⚠ WARNING: This will restore the database from $(BACKUP)$(NC)"
	@echo -e "$(YELLOW)Press Ctrl+C to cancel, or Enter to continue...$(NC)"
	@read
	@echo -e "$(CYAN)Restoring database...$(NC)"
	@docker compose exec -T postgres psql -U synapse synapse < $(BACKUP)
	@echo -e "$(GREEN)✓ Database restored$(NC)"

##@ Updates & Cleanup

update: ## Update Docker images to latest versions
	@echo -e "$(CYAN)Pulling latest Docker images...$(NC)"
	@docker compose pull
	@echo -e "$(CYAN)Recreating containers with new images...$(NC)"
	@docker compose up -d
	@echo -e "$(GREEN)✓ Services updated$(NC)"
	@echo -e "$(YELLOW)Check logs for any issues: make logs$(NC)"

stop: ## Stop all services
	@echo -e "$(CYAN)Stopping all services...$(NC)"
	@docker compose down
	@echo -e "$(GREEN)✓ All services stopped$(NC)"

clean: ## Remove all containers and volumes (⚠ DESTRUCTIVE)
	@echo -e "$(RED)⚠ WARNING: This will remove all containers and volumes$(NC)"
	@echo -e "$(RED)⚠ All data will be lost unless backed up!$(NC)"
	@echo -e "$(YELLOW)Type 'yes' to confirm:$(NC) "
	@read confirm && [ "$$confirm" = "yes" ] || (echo -e "$(GREEN)Aborted$(NC)" && exit 1)
	@echo -e "$(CYAN)Removing containers and volumes...$(NC)"
	@docker compose down -v
	@echo -e "$(GREEN)✓ Cleanup complete$(NC)"

clean-generated: ## Remove all generated configuration files and data directories (⚠ DESTRUCTIVE)
	@echo -e "$(RED)⚠ WARNING: This will remove all generated files and directories:$(NC)"
	@echo -e "$(YELLOW)  - .env and secrets.env$(NC)"
	@echo -e "$(YELLOW)  - synapse/data/ (including homeserver.yaml and signing keys)$(NC)"
	@echo -e "$(YELLOW)  - mas/config/ and mas/data/$(NC)"
	@echo -e "$(YELLOW)  - element/config/$(NC)"
	@echo -e "$(YELLOW)  - postgres/data/ and element-admin/data/$(NC)"
	@echo -e "$(YELLOW)  - backups/ directory$(NC)"
	@echo -e "$(YELLOW)  - All backup files (.env.backup.*, *.yaml.backup.*)$(NC)"
	@echo -e ""
	@echo -e "$(RED)⚠ You will need to run setup again from scratch!$(NC)"
	@echo -e "$(YELLOW)Type 'yes' to confirm:$(NC) "
	@read confirm && [ "$$confirm" = "yes" ] || (echo -e "$(GREEN)Aborted$(NC)" && exit 1)
	@echo -e "$(CYAN)Removing generated files and directories...$(NC)"
	@rm -f .env secrets.env
	@rm -f .env.backup.* secrets.env.backup.*
	@sudo rm -rf synapse/data/
	@sudo rm -rf mas/config/ mas/data/
	@sudo rm -rf element/config/
	@sudo rm -rf element-admin/data/
	@sudo rm -rf postgres/data/
	@sudo rm -rf backups/
	@echo -e "$(GREEN)✓ All generated files removed$(NC)"
	@echo -e ""
	@echo -e "$(YELLOW)To start fresh, run:$(NC)"
	@echo -e "  1. $(CYAN)make quick-setup$(NC)"
	@echo -e "  2. $(CYAN)make full-setup$(NC)"
	@echo -e "  3. $(CYAN)make deploy$(NC)"

clean-all: stop clean clean-generated ## Stop services, remove containers/volumes, and delete all generated files (⚠ VERY DESTRUCTIVE)
	@echo -e ""
	@echo -e "$(GREEN)✓ Complete cleanup finished!$(NC)"
	@echo -e "$(YELLOW)All services stopped, containers removed, and files deleted.$(NC)"

##@ Quick Setup Workflows

quick-setup: check-prereqs generate-secrets ## Quick setup: prereqs, secrets, env config, and Synapse setup
	@echo -e ""
	@echo -e "$(CYAN)Configuring environment interactively...$(NC)"
	@bash scripts/setup-env-interactive.sh
	@echo -e ""
	@echo -e "$(CYAN)Generating Synapse configuration...$(NC)"
	@$(MAKE) generate-synapse-config
	@echo -e ""
	@echo -e "$(CYAN)Configuring Synapse database...$(NC)"
	@$(MAKE) configure-synapse-db
	@echo -e ""
	@echo -e "$(GREEN)✓ Quick setup complete!$(NC)"
	@echo -e ""
	@echo -e "$(YELLOW)Next steps:$(NC)"
	@echo -e "  1. Configure other services: $(CYAN)make configure-mas configure-element$(NC)"
	@echo -e "  2. Or run full setup: $(CYAN)make full-setup$(NC)"
	@echo -e "  3. Then deploy: $(CYAN)make deploy$(NC)"

full-setup: generate-synapse-config configure-all ## Full configuration: generate configs and configure all services
	@echo -e ""
	@echo -e "$(GREEN)✓ Full configuration complete!$(NC)"
	@echo -e ""
	@echo -e "$(YELLOW)Next steps:$(NC)"
	@echo -e "  1. Review configurations in mas/config/ and synapse/data/"
	@echo -e "  2. Run: $(CYAN)make deploy$(NC)"
	@echo -e "  3. Run: $(CYAN)make verify$(NC)"
	@echo -e "  4. Run: $(CYAN)make create-admin$(NC)"

full-deploy: deploy verify ## Full deployment: start services and verify
	@echo -e ""
	@echo -e "$(GREEN)✓ Full deployment complete!$(NC)"
	@echo -e ""
	@echo -e "$(YELLOW)Next steps:$(NC)"
	@echo -e "  1. Create admin user: $(CYAN)make create-admin$(NC)"
	@echo -e "  2. Access Element at: $(CYAN)https://$$ELEMENT_DOMAIN$(NC)"

##@ Development & Testing

shell-synapse: ## Open shell in Synapse container
	@docker compose exec synapse /bin/bash

shell-mas: ## Open shell in MAS container
	@docker compose exec mas /bin/sh

shell-postgres: ## Open psql shell in PostgreSQL
	@docker compose exec postgres psql -U synapse synapse

test-federation: ## Test federation setup
	@echo -e "$(CYAN)Testing federation configuration...$(NC)"
	@if [ ! -f .env ]; then \
		echo -e "$(RED)✗ .env file not found$(NC)"; \
		exit 1; \
	fi; \
	source .env && \
	echo -e "$(CYAN)Testing /.well-known/matrix/server...$(NC)" && \
	curl -s "https://$$MATRIX_DOMAIN/.well-known/matrix/server" | jq . || echo -e "$(RED)✗ Failed$(NC)"; \
	echo "" && \
	echo -e "$(CYAN)Testing /_matrix/client/versions...$(NC)" && \
	curl -s "https://$$MATRIX_DOMAIN/_matrix/client/versions" | jq . || echo -e "$(RED)✗ Failed$(NC)"
