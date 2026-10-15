SHELL := /usr/bin/env bash

PODMAN_VERSION ?= v6.1.4
PODMAN_IMAGE_NAME ?= mgoltzsche/podman
PODMAN_IMAGE ?= $(PODMAN_IMAGE_NAME):latest
PODMAN_IMAGE_TARGET ?= podmanall
PODMAN_MINIMAL_IMAGE ?= $(PODMAN_IMAGE)-minimal
PODMAN_REMOTE_IMAGE ?= $(PODMAN_IMAGE)-remote
PODMAN_TAR_IMAGE ?= $(PODMAN_IMAGE)-tar
PODMAN_SSH_IMAGE ?= mgoltzsche/podman-ssh
PODMAN_BUILD_OPTS ?= -t $(PODMAN_IMAGE)
PODMAN_MINIMAL_BUILD_OPTS ?= -t $(PODMAN_MINIMAL_IMAGE)
PODMAN_REMOTE_BUILD_OPTS ?= -t $(PODMAN_REMOTE_IMAGE)

GPG_IMAGE = gpg-signer

BUILD_DIR ?= ./build
INSTALL_ROOT ?= $(HOME)/.local/podman
DOCKER ?= docker
export DOCKER

PLATFORM ?= linux/amd64
ARCH := $(shell echo "$(PLATFORM)" | sed -E 's!linux/([^/]+).*!\1!')
ASSET_NAME := podman-linux-$(ARCH)
ASSET_DIR := $(BUILD_DIR)/$(ASSET_NAME)

BUILDX_BUILDER ?= podman-builder
BUILDX_OUTPUT ?= type=docker
BUILDX_OPTS ?= --builder=$(BUILDX_BUILDER) --output=$(BUILDX_OUTPUT) --platform=$(PLATFORM)

.PHONY: images podman podman-minimal podman-remote podman-tar-image podman-ssh \
        create-builder delete-builder test test-local-rootful test-local-rootless \
        test-minimal-image test-remote storage-dir clean-storage-dir install tar \
        signed-tar verify-signature gpg run clean run-server run-client

images: podman podman-remote podman-minimal podman-tar-image

podman: create-builder
	$(DOCKER) buildx build $(BUILDX_OPTS) --force-rm \
		--build-arg PODMAN_VERSION=$(PODMAN_VERSION) \
		$(PODMAN_BUILD_OPTS) --target $(PODMAN_IMAGE_TARGET) .

podman-tar-image: create-builder
	$(DOCKER) buildx build $(BUILDX_OPTS) --force-rm \
		--build-arg PODMAN_VERSION=$(PODMAN_VERSION) \
		-t $(PODMAN_TAR_IMAGE) --target tar-archive .

podman-minimal: create-builder
	$(MAKE) podman \
		PODMAN_IMAGE_TARGET=rootlesspodmanminimal \
		PODMAN_BUILD_OPTS="$(PODMAN_MINIMAL_BUILD_OPTS)" \
		BUILDX_OPTS="$(BUILDX_OPTS)"

podman-remote: create-builder
	$(DOCKER) buildx build $(BUILDX_OPTS) --force-rm \
		--build-arg PODMAN_VERSION=$(PODMAN_VERSION) \
		$(PODMAN_REMOTE_BUILD_OPTS) -f Dockerfile-remote .

podman-ssh: podman
	$(DOCKER) buildx build $(BUILDX_OPTS) --force-rm \
		-t $(PODMAN_SSH_IMAGE) -f Dockerfile-ssh \
		--build-arg BASEIMAGE=$(PODMAN_IMAGE) .

create-builder:
	$(DOCKER) buildx inspect $(BUILDX_BUILDER) >/dev/null 2>&1 || \
		$(DOCKER) buildx create --name=$(BUILDX_BUILDER) >/dev/null

delete-builder:
	$(DOCKER) buildx rm $(BUILDX_BUILDER)

test: test-local-rootful test-local-rootless test-minimal-image test-remote

test-local-rootful: podman storage-dir
	IMAGE=$(PODMAN_IMAGE) ./test/test-local-rootful.sh

test-local-rootless: podman storage-dir
	IMAGE=$(PODMAN_IMAGE) TEST_PREDICATE=FULL ./test/test-local-rootless.sh

test-minimal-image: podman-minimal storage-dir
	IMAGE=$(PODMAN_MINIMAL_IMAGE) TEST_PREDICATE=MINIMAL \
		SKIP_PORTMAPPING_TEST=true ./test/test-local-rootless.sh

test-remote: podman podman-remote storage-dir
	PODMAN_IMAGE=$(PODMAN_IMAGE) \
	PODMAN_REMOTE_IMAGE=$(PODMAN_REMOTE_IMAGE) \
		./test/test-remote.sh

storage-dir: clean-storage-dir
	mkdir -p test/storage/root
	mkdir -pm 1777 test/storage/user

clean-storage-dir:
	$(DOCKER) run --rm -v "$(CURDIR)/test:/test" alpine:3.24 rm -rf /test/storage

install: .podman-from-container
	mkdir -p "$(INSTALL_ROOT)"
	cp -a "$(ASSET_DIR)/usr" "$(ASSET_DIR)/etc" "$(INSTALL_ROOT)/"
	cp -a rootless.bash podman-env.bash README.md "$(INSTALL_ROOT)/"

tar: .podman-from-container
	rm -f "$(BUILD_DIR)/$(ASSET_NAME).tar.gz"
	tar -C "$(BUILD_DIR)" -czvf "$(BUILD_DIR)/$(ASSET_NAME).tar.gz" "$(ASSET_NAME)"

.podman-from-container: podman-tar-image
	rm -rf "$(ASSET_DIR)"
	mkdir -p "$(ASSET_DIR)/etc" "$(ASSET_DIR)/usr/local"
	set -e; \
	CONTAINER="$$($(DOCKER) create $(PODMAN_TAR_IMAGE))"; \
	trap '$(DOCKER) rm -f "$$CONTAINER" >/dev/null' EXIT; \
	$(DOCKER) cp "$$CONTAINER:/etc/containers" "$(ASSET_DIR)/etc/"; \
	for directory in bin lib libexec share; do \
		$(DOCKER) cp "$$CONTAINER:/usr/local/$$directory" "$(ASSET_DIR)/usr/local/"; \
	done
	cp rootless.bash podman-env.bash README.md "$(ASSET_DIR)/"
	mkdir -p "$(ASSET_DIR)/usr/local/lib/systemd/user-generators" \
		"$(ASSET_DIR)/usr/local/lib/systemd/system-generators"
	ln -s ../../../libexec/podman/quadlet \
		"$(ASSET_DIR)/usr/local/lib/systemd/user-generators/podman-user-generator"
	ln -s ../../../libexec/podman/quadlet \
		"$(ASSET_DIR)/usr/local/lib/systemd/system-generators/podman-system-generator"

signed-tar: tar .gpg
	@echo Running gpg signing container with GPG_SIGN_KEY and GPG_SIGN_KEY_PASSPHRASE
	export GPG_SIGN_KEY
	export GPG_SIGN_KEY_PASSPHRASE
	@$(DOCKER) run --rm -v "$(CURDIR)/build:/build" \
		-e GPG_SIGN_KEY="$$GPG_SIGN_KEY" \
		-e GPG_SIGN_KEY_PASSPHRASE="$$GPG_SIGN_KEY_PASSPHRASE" \
		$(GPG_IMAGE) /bin/sh -c ' \
			set -e; \
			[ "$$GPG_SIGN_KEY" -a "$$GPG_SIGN_KEY_PASSPHRASE" ] || \
				(echo Missing GPG_SIGN_KEY or GPG_SIGN_KEY_PASSPHRASE >&2; false); \
			echo "$$GPG_SIGN_KEY" | gpg --batch --import -; \
			rm -f /build/$(ASSET_NAME).tar.gz.asc; \
			echo "$$GPG_SIGN_KEY_PASSPHRASE" | \
				(set -x; gpg --pinentry-mode loopback --command-fd 0 -a \
				-o /build/$(ASSET_NAME).tar.gz.asc --detach-sign \
				/build/$(ASSET_NAME).tar.gz)'

verify-signature:
	( \
		for _ in $$(seq 1 10); do \
			TMPDIR=$$(mktemp -d); \
			export GNUPGHOME=$$TMPDIR; \
			gpg --keyserver hkps://keyserver.ubuntu.com \
				--recv-keys 0CCF102C4F95D89E583FF1D4F8B5AF50344BB503 && \
			gpg --batch --verify "$(BUILD_DIR)/$(ASSET_NAME).tar.gz.asc" \
				"$(BUILD_DIR)/$(ASSET_NAME).tar.gz" && \
			rm -rf $$TMPDIR && exit 0 || \
			rm -rf $$TMPDIR; sleep 1; \
		done; \
		exit 1; \
	)

.gpg: create-builder
	$(DOCKER) buildx build $(BUILDX_OPTS) --force-rm -t $(GPG_IMAGE) --target gpg .

run: podman
	$(DOCKER) run -ti --rm --privileged \
		-v "$(CURDIR)/test/storage/user:/podman/.local/share/containers/storage" \
		$(PODMAN_IMAGE) /bin/sh

clean: clean-storage-dir
	rm -rf "$(BUILD_DIR)"

run-server: podman-ssh
	$(DOCKER) run --rm --privileged --network=host \
		-v "$(CURDIR)/test/storage/user:/podman/.local/share/containers/storage" \
		-v "$(CURDIR)/test:/build" \
		-w /build \
		"$(PODMAN_SSH_IMAGE)" \
		sh -c 'set -x; \
			ssh-keygen -b 2048 -t rsa -N "" -f /podman/.ssh/ssh_host_rsa_key; \
			ssh-keygen -b 521 -t ecdsa -N "" -f /podman/.ssh/ssh_host_ecdsa_key; \
			[ -f /build/storage/user/client_rsa ] || \
				ssh-keygen -b 2048 -t rsa -N "" -f /build/storage/user/client_rsa; \
			cat /build/storage/user/client_rsa.pub > /podman/.ssh/authorized_keys; \
			/usr/sbin/sshd -eD -f ~/.ssh/sshd_config & \
			mkdir /tmp/podman; \
			podman system service -t 0 unix:///tmp/podman/podman.sock'

run-client: podman-remote
	$(DOCKER) run --rm -it --network=host \
		-v "$(CURDIR)/test:/build" \
		-w /build \
		-e PODMAN_URL=ssh://podman@127.0.0.1:2222/tmp/podman/podman.sock?secure=True \
		-e CONTAINER_SSHKEY=/build/storage/user/client_rsa \
		"$(PODMAN_REMOTE_IMAGE)" \
		/bin/sh -c 'set -ex; podman --url=$$PODMAN_URL --log-level=info build /build/test'
