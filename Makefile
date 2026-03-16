.PHONY: build fmt test test-integration test-all pg-start pg-stop clean

all: clean fmt build test-all info

build:
	moon build --target native

fmt:
	moon fmt

info:
	moon info

test:
	moon test --target native -p bikallem/pgsql

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
