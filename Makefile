.PHONY: build fmt test test-integration test-all pg-start pg-stop clean

build:
	moon build --target native	

fmt:
	moon fmt	

test:
	moon test --target native internal/protocol/

test-integration: pg-start
	moon test --target native tests/ ; status=$$? ; \
	$(MAKE) pg-stop ; exit $$status

test-all: test test-integration

pg-start:
	./tests/setup-pg.sh start

pg-stop:
	./tests/setup-pg.sh stop

clean:
	./tests/setup-pg.sh clean
