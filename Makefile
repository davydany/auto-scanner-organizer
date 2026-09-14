SCANCORE := packages/ScanCore

.PHONY: init test lint format check teardown

init:
	brew bundle --file=Brewfile

test:
	swift test --package-path $(SCANCORE)

lint:
	swiftlint lint --strict

format:
	swiftformat $(SCANCORE)

check: lint test

teardown:
	rm -rf $(SCANCORE)/.build
