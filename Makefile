build:
	docker build . -t tccland --progress=plain

run:
	docker run --name tccland --rm -it tccland

debug:
	docker run -it \
		--pid=container:tccland \
		--net=container:tccland \
		--cap-add sys_admin \
		--cap-add sys_ptrace \
		invisiblethreat/docker-debug:latest
	# strace -p1 2>&1 | less