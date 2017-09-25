all: compile

clean-devel: clean
	-rm -rf _build

clean:
	./rebar3 clean

compile:
	./rebar3 compile

test:
	./rebar3 do eunit, cover
	./covertool \
		-cover _build/test/cover/eunit.coverdata \
		-appname snatch \
		-output cobertura.xml > /dev/null

shell:
	./rebar3 shell

.PHONY: test compile all shell
