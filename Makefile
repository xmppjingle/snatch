all: compile

doc:
	./rebar3 as doc edown

clean-devel: clean
	-rm -rf _build

clean:
	./rebar3 clean

compile:
	./rebar3 compile

test: eunit

eunit:
	-epmd -daemon
	./rebar3 do xref, eunit, cover
	./covertool \
		-cover _build/test/cover/eunit.coverdata \
		-appname snatch \
		-output cobertura.xml > /dev/null

shell:
	./rebar3 shell

test-docker:
	docker build -f Dockerfile.test -t snatch-test .
	docker run --rm snatch-test

.PHONY: doc test compile all shell eunit test-docker
