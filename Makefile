.PHONY: build fmt test test-integration test-all pg-start pg-stop clean

build:
	moon build --target native
	cd examples && moon build --target native

fmt:
	moon fmt
	cd examples && moon fmt

test:
	moon test --target native src/protocol/

test-integration: pg-start
	moon test --target native src/tests/ ; status=$$? ; \
	$(MAKE) pg-stop ; exit $$status

test-all: test test-integration

pg-start:
	./src/tests/setup-pg.sh start

pg-stop:
	./src/tests/setup-pg.sh stop

clean:
	./src/tests/setup-pg.sh clean
