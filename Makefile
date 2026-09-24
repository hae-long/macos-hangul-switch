.PHONY: test lint verify

test:
	/bin/bash tests/run.bash

lint:
	/bin/bash -n install.sh uninstall.sh status.sh scripts/*.bash tests/*.bash

verify: lint test
