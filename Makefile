.PHONY: build test probe verify verify-app verify-packages verify-localizations site app app-release install-local dmg

build:
	swift build

test:
	swift test

# Single verification entry point. The three parts are independent, so CI runs them as parallel jobs and
# `make -j3 verify` does the same locally; plain `make verify` runs them one after another.
verify: verify-app verify-packages verify-localizations

verify-app:
	swift test

verify-packages:
	for package in Packages/*/; do swift test --package-path "$$package" || exit 1; done

verify-localizations:
	./scripts/check/localizations.sh
	./scripts/check/installer-strings.sh

# Preview the website at http://localhost:8000 (images come from docs/assets, as in the deployed build).
site:
	rm -rf site/assets && cp -R docs/assets site/assets
	python3 -m http.server 8000 --directory site

probe:
	swift run macpocket-probe system

app:
	./scripts/build/build-app.sh

app-release:
	./scripts/build/build-app.sh release

install-local:
	./scripts/build/install-local.sh

dmg: app-release
	./scripts/build/build-dmg.sh
