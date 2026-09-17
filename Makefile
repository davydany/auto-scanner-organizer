SCANCORE := packages/ScanCore

.PHONY: init test test-live lint format check teardown cli

init:
	brew bundle --file=Brewfile

test:
	swift test --package-path $(SCANCORE)

test-live:
	SCANCORE_LIVE=1 swift test --package-path $(SCANCORE) --filter LiveTests

lint:
	swiftlint lint --strict

format:
	swiftformat $(SCANCORE)

check: lint test

teardown:
	rm -rf $(SCANCORE)/.build

cli:
	swift run --package-path $(SCANCORE) scan-organizer $(ARGS)
