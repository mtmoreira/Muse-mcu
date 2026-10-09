# Muse MCU — top-level Makefile (R2)
# `make acceptance` runs every mandatory gate; nonzero on failure/incompleteness.
# `make smoke` runs the labeled fast subset.

.PHONY: acceptance smoke firmware

firmware:
	@for a in hello uart_rx_test spi_test timer_gpio_test pingpong rtos_regtest rtos_queue rtos_sema rtos_notify rtos_timer rtos_isr rtos_blocktim preempt_test app_demo; do \
	  $(MAKE) -C fw APP=$$a || exit 1; \
	done

acceptance: firmware
	python3 tools/run_acceptance.py

smoke:
	python3 tools/run_acceptance.py --smoke
