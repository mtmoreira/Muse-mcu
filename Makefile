# Muse MCU — top-level Makefile (R2)
# `make acceptance` runs every mandatory gate; nonzero on failure/incompleteness.
# `make smoke` runs the labeled fast subset.

.PHONY: acceptance smoke firmware

firmware:
	bash fw/build.sh

acceptance: firmware
	bash tools/run_tests.sh

smoke:
	bash tools/run_tests.sh --smoke
