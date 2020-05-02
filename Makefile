PROJECT = i96751414
NAME = libtorrent-go
GO_PACKAGE = github.com/i96751414/$(NAME)
CC = cc
CXX = c++
PKG_CONFIG = pkg-config
DOCKER = docker
CROSS_COMPILER_TAG = latest
TAG = $(shell git describe --tags | cut -c2-)
ifeq ($(TAG),)
	TAG := dev
endif

PLATFORMS = \
	android-arm \
	android-arm64 \
	android-x64 \
	android-x86 \
	darwin-x64 \
	linux-arm \
	linux-armv7 \
	linux-arm64 \
	linux-x64 \
	linux-x86 \
	windows-x64 \
	windows-x86

BOOST_VERSION = 1.69.0
BOOST_VERSION_FILE = $(shell echo $(BOOST_VERSION) | sed s/\\./_/g)
BOOST_SHA256 = 8f32d4617390d1c2d16f26a27ab60d97807b35440d45891fa340fc2648b04406

OPENSSL_VERSION = 1.1.1b
OPENSSL_SHA256 = 5c557b023230413dfb0756f3137a13e6d726838ccd1430888ad15bfb2b43ea4b

SWIG_VERSION = ae0efd3d742ad083312fadbc652d4d66fdad6f4d  # master on 2020/03/05
SWIG_SHA256 = 1bf1a98e7c83c8928bf19b9f8489f2a26ec1c8fab8ffa3bd413037e1a4fe8421

GOLANG_VERSION = 1.14
GOLANG_SRC_SHA256 = 6d643e46ad565058c7a39dac01144172ef9bd476521f42148be59249e4b74389

GOLANG_BOOTSTRAP_VERSION = 1.4-bootstrap-20170531
GOLANG_BOOTSTRAP_SHA256 = 49f806f66762077861b7de7081f586995940772d29d4c45068c134441a743fa2

LIBTORRENT_VERSION = b9b54436b8b214420745e5ff722112316d7d85c7 # RC_1_2 (1.2.6)

ifeq ($(GOPATH),)
	GOPATH = $(shell go env GOPATH)
endif

include platform_host.mk

ifneq ($(CROSS_TRIPLE),)
	CC := $(CROSS_TRIPLE)-$(CC)
	CXX := $(CROSS_TRIPLE)-$(CXX)
endif

include platform_target.mk

ifeq ($(TARGET_ARCH), x86)
	GOARCH = 386
else ifeq ($(TARGET_ARCH), x64)
	GOARCH = amd64
else ifeq ($(TARGET_ARCH), arm)
	GOARCH = arm
	GOARM = 6
else ifeq ($(TARGET_ARCH), armv7)
	GOARCH = arm
	GOARM = 7
	PATH_SUFFIX = v7
	PKGDIR = -pkgdir $(GOPATH)/pkg/linux_armv7
else ifeq ($(TARGET_ARCH), arm64)
	GOARCH = arm64
	GOARM =
endif

ifeq ($(TARGET_OS), windows)
	GOOS = windows
else ifeq ($(TARGET_OS), darwin)
	GOOS = darwin
else ifeq ($(TARGET_OS), linux)
	GOOS = linux
else ifeq ($(TARGET_OS), android)
	GOOS = android
	ifeq ($(TARGET_ARCH), arm)
		GOARM = 7
	else
		GOARM =
	endif
	GO_LDFLAGS = -extldflags=-pie
endif

ifneq ($(CROSS_ROOT),)
	CROSS_CFLAGS = -I$(CROSS_ROOT)/include -I$(CROSS_ROOT)/$(CROSS_TRIPLE)/include
	CROSS_LDFLAGS = -L$(CROSS_ROOT)/lib
	PKG_CONFIG_PATH = $(CROSS_ROOT)/lib/pkgconfig
endif

ifeq ($(TARGET_OS), windows)
	CC_DEFINES += -DSWIGWIN
	CC_DEFINES += -D_WIN32_WINNT=0x0600
	ifeq ($(TARGET_ARCH), x64)
		CC_DEFINES += -DSWIGWORDSIZE32
	endif
else ifeq ($(TARGET_OS), linux)
	ifeq ($(TARGET_ARCH), arm64)
		CC_DEFINES += -DSWIGWORDSIZE64
	endif
else ifeq ($(TARGET_OS), darwin)
	CC = $(CROSS_ROOT)/bin/$(CROSS_TRIPLE)-clang
	CXX = $(CROSS_ROOT)/bin/$(CROSS_TRIPLE)-clang++
	CC_DEFINES += -DSWIGMAC
	CC_DEFINES += -DBOOST_HAS_PTHREADS
else ifeq ($(TARGET_OS), android)
	CC = $(CROSS_ROOT)/bin/$(CROSS_TRIPLE)-clang
	CXX = $(CROSS_ROOT)/bin/$(CROSS_TRIPLE)-clang++
	GO_LDFLAGS += -flto
	ifeq ($(TARGET_ARCH), arm64)
		CC_DEFINES += -DSWIGWORDSIZE64
	endif
endif

DOCKER_GOPATH = "/go"
DOCKER_WORKDIR = "$(DOCKER_GOPATH)/src/$(GO_PACKAGE)"
DOCKER_GOCACHE = "/tmp/.cache"

WORKDIR = "$(shell pwd)"
DEFINES = $(WORKDIR)/interfaces/defines.i
WORK = $(WORKDIR)/work
OUT_PATH = "$(GOPATH)/pkg/$(GOOS)_$(GOARCH)$(PATH_SUFFIX)"
OUT_LIBRARY = "$(OUT_PATH)/$(GO_PACKAGE).a"

USERGRP = "$(shell id -u):$(shell id -g)"

.PHONY: $(PLATFORMS)

all:
	for i in $(PLATFORMS); do \
		$(MAKE) $$i; \
	done

$(PLATFORMS):
ifeq ($@, all)
	$(MAKE) all
else
	$(DOCKER) run --rm \
	-u $(USERGRP) \
	-v "$(GOPATH)":$(DOCKER_GOPATH) \
	-v $(WORKDIR):$(DOCKER_WORKDIR) \
	-w $(DOCKER_WORKDIR) \
	-e GOCACHE=$(DOCKER_GOCACHE) \
	-e GOPATH=$(DOCKER_GOPATH) \
	$(PROJECT)/$(NAME)-$@:latest make re;
endif

debug:
ifeq ($(PLATFORM),)
	$(MAKE) debug PLATFORM=linux-x64
else
	$(DOCKER) run --rm \
	-u $(USERGRP) \
	-v "$(GOPATH)":$(DOCKER_GOPATH) \
	-v $(WORKDIR):$(DOCKER_WORKDIR) \
	-w $(DOCKER_WORKDIR) \
	-e GOCACHE=$(DOCKER_GOCACHE) \
	-e GOPATH=$(DOCKER_GOPATH) \
	$(PROJECT)/$(NAME)-$(PLATFORM):latest bash -c \
	'make re OPTS=-work; \
	cp -rf /tmp/go-build* $(DOCKER_WORKDIR)/work'
endif

defines:
	$(shell ( \
	echo $(CC_DEFINES) | sed -E 's/-D([a-zA-Z0-9_()]+)=?/\n#define \1 /g' && \
	$(CC) -dM -E - </dev/null | grep -E "__WORDSIZE|__x86_64|__x86_64__" | sed -E 's/#define[[:space:]]+([a-zA-Z0-9_()]+)(.*)/#ifndef \1\n#define \1\2\n#endif/g' \
	) > $(DEFINES))

build:
	CC=$(CC) CXX=$(CXX) \
	PKG_CONFIG_PATH=$(PKG_CONFIG_PATH) \
	CGO_ENABLED=1 \
	GOOS=$(GOOS) GOARCH=$(GOARCH) GOARM=$(GOARM) \
	PATH=.:$$PATH \
	go install $(OPTS) -v -ldflags '$(GO_LDFLAGS)' -x $(PKGDIR)

clean:
	rm -rf $(OUT_LIBRARY) $(DEFINES) $(WORK)

re: clean defines build

env:
	$(DOCKER) build \
		--build-arg BOOST_VERSION=$(BOOST_VERSION) \
		--build-arg BOOST_VERSION_FILE=$(BOOST_VERSION_FILE) \
		--build-arg BOOST_SHA256=$(BOOST_SHA256) \
		--build-arg OPENSSL_VERSION=$(OPENSSL_VERSION) \
		--build-arg OPENSSL_SHA256=$(OPENSSL_SHA256) \
		--build-arg SWIG_VERSION=$(SWIG_VERSION) \
		--build-arg SWIG_SHA256=$(SWIG_SHA256) \
		--build-arg GOLANG_VERSION=$(GOLANG_VERSION) \
		--build-arg GOLANG_SRC_SHA256=$(GOLANG_SRC_SHA256) \
		--build-arg GOLANG_BOOTSTRAP_VERSION=$(GOLANG_BOOTSTRAP_VERSION) \
		--build-arg GOLANG_BOOTSTRAP_SHA256=$(GOLANG_BOOTSTRAP_SHA256) \
		--build-arg LIBTORRENT_VERSION=$(LIBTORRENT_VERSION) \
		-t $(PROJECT)/$(NAME)-$(PLATFORM):$(TAG) \
		-t $(PROJECT)/$(NAME)-$(PLATFORM):latest \
		--build-arg IMAGE_TAG=$(CROSS_COMPILER_TAG) \
		-f docker/$(PLATFORM).Dockerfile docker

envs:
	for i in $(PLATFORMS); do \
		$(MAKE) env PLATFORM=$$i; \
	done

pull-all:
	for i in $(PLATFORMS); do \
		$(MAKE) pull PLATFORM=$$i; \
	done

pull:
	docker pull $(PROJECT)/$(NAME)-$(PLATFORM):latest

push:
	docker push $(PROJECT)/$(NAME)-$(PLATFORM)
