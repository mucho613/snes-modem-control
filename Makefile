.PHONY: all smoke check bootstrap

all:
	cargo xtask rom

smoke:
	cargo xtask rom --smoke

check:
	cargo xtask check

bootstrap:
	cargo xtask bootstrap
