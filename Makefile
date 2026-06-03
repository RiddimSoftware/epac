.PHONY: perf-sim perf-device

perf-sim:
	$(MAKE) -C ios perf-sim

perf-device:
	$(MAKE) -C ios perf-device
