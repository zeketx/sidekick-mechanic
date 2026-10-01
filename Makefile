PYTHON ?= python3

.PHONY: eval metrics

eval:
	cd backend && $(PYTHON) -m eval --metrics

metrics:
	cd backend && $(PYTHON) -m eval.report
