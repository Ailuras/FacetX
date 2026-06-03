.PHONY: build run check dmg clean logs

build:
	@scripts/build.sh

run:
	@scripts/restart.sh

check:
	@scripts/check.sh

dmg: build
	@scripts/package-dmg.sh

clean:
	@scripts/clean.sh

logs:
	@scripts/log.sh
