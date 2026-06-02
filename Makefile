MIX  := mix
NPM  := npm
ELIXIR_BIN := $(HOME)/.asdf/installs/elixir/1.18.3/bin

export PATH := $(ELIXIR_BIN):$(PATH)

.PHONY: build build-elixir build-ui test lint typecheck format clean setup server

## Build everything (Elixir + UI)
build: build-elixir build-ui

## Compile Elixir project
build-elixir:
	$(MIX) compile

## Bundle frontend assets (Vue / Vite → priv/static)
build-ui:
	cd assets && $(NPM) install && $(NPM) run build

## Run the full test suite (mock provider, no API keys)
test:
	$(MIX) test

## Run only a single test file or module
test-file:
	$(MIX) test $(FILE)

## Lint: check Elixir formatting (dry-run)
lint:
	$(MIX) format --check-formatted

## Fix Elixir formatting in-place
format:
	$(MIX) format

## TypeScript typecheck (Vue)
typecheck:
	cd assets && npx vue-tsc --noEmit

## Start dev server
server:
	$(MIX) phx.server

## Build UI + start server (most common dev workflow)
dev: build-ui
	$(MIX) phx.server

## Install deps and create DB
setup:
	$(MIX) deps.get
	$(MIX) ecto.create

## Full pre-commit check (compile, no warnings, deps clean, format, test)
precommit:
	$(MIX) compile --warnings-as-errors
	$(MIX) deps.unlock --unused
	$(MIX) format --check-formatted
	$(MIX) test

## Quick build + typecheck + test loop
check: lint typecheck test

## Clean build artifacts
clean:
	$(MIX) clean
	rm -rf assets/node_modules