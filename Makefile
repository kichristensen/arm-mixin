MIXIN = azure
PKG = github.com/deislabs/porter-$(MIXIN)
SHELL = bash

COMMIT ?= $(shell git rev-parse --short HEAD)
VERSION ?= $(shell git describe --tags 2> /dev/null || echo v0)
PERMALINK ?= $(shell git name-rev --name-only --tags --no-undefined HEAD &> /dev/null && echo latest || echo canary)

LDFLAGS = -w -X $(PKG)/pkg.Version=$(VERSION) -X $(PKG)/pkg.Commit=$(COMMIT)
XBUILD = CGO_ENABLED=0 go build -a -tags netgo -ldflags '$(LDFLAGS)'
BINDIR = bin/mixins/$(MIXIN)

CLIENT_PLATFORM = $(shell go env GOOS)
CLIENT_ARCH = $(shell go env GOARCH)
RUNTIME_PLATFORM = linux
RUNTIME_ARCH = amd64
SUPPORTED_CLIENT_PLATFORMS = linux darwin windows
SUPPORTED_CLIENT_ARCHES = amd64 386

ifeq ($(CLIENT_PLATFORM),windows)
FILE_EXT=.exe
else ifeq ($(RUNTIME_PLATFORM),windows)
FILE_EXT=.exe
else
FILE_EXT=
endif

REGISTRY ?= $(USER)

build: build-client build-runtime build-templates

build-runtime:
	mkdir -p $(BINDIR)
	GOARCH=$(RUNTIME_ARCH) GOOS=$(RUNTIME_PLATFORM) go build -ldflags '$(LDFLAGS)' -o $(BINDIR)/$(MIXIN)-runtime$(FILE_EXT) ./cmd/$(MIXIN)

build-client:
	mkdir -p $(BINDIR)
	go build -ldflags '$(LDFLAGS)' -o $(BINDIR)/$(MIXIN)$(FILE_EXT) ./cmd/$(MIXIN)

HAS_PACKR2 := $(shell command -v packr2)

build-templates:
ifndef HAS_PACKR2
	go get -u github.com/gobuffalo/packr/packr
endif
	cd pkg/azure/arm && packr2 build

xbuild-all: xbuild-runtime $(addprefix xbuild-for-,$(SUPPORTED_CLIENT_PLATFORMS))

xbuild-for-%:
	$(MAKE) CLIENT_PLATFORM=$* xbuild-client

xbuild-runtime:
	GOARCH=$(RUNTIME_ARCH) GOOS=$(RUNTIME_PLATFORM) $(XBUILD) -o $(BINDIR)/$(VERSION)/$(MIXIN)-runtime-$(RUNTIME_PLATFORM)-$(RUNTIME_ARCH)$(FILE_EXT) ./cmd/$(MIXIN)

xbuild-client: $(BINDIR)/$(VERSION)/$(MIXIN)-$(CLIENT_PLATFORM)-$(CLIENT_ARCH)$(FILE_EXT)
$(BINDIR)/$(VERSION)/$(MIXIN)-$(CLIENT_PLATFORM)-$(CLIENT_ARCH)$(FILE_EXT):
	mkdir -p $(dir $@)
	GOOS=$(CLIENT_PLATFORM) GOARCH=$(CLIENT_ARCH) $(XBUILD) -o $@ ./cmd/$(MIXIN)

test: test-unit test-templates
	$(BINDIR)/$(MIXIN)$(FILE_EXT) version

test-unit: build
	go test ./...

HAS_JSONPP := $(shell command -v jsonpp)

test-templates:
ifndef HAS_JSONPP
	go get github.com/jmhodges/jsonpp
endif
	@for template in $$(ls pkg/azure/arm/templates); do \
		echo "ensuring valid json: $$template" ; \
		cat pkg/azure/arm/templates/$$template | json_pp > /dev/null ; \
	done

publish:
	# AZURE_STORAGE_CONNECTION_STRING will be used for auth in the following commands
	if [[ "$(PERMALINK)" == "latest" ]]; then \
	az storage blob upload-batch -d porter/mixins/$(MIXIN)/$(VERSION) -s $(BINDIR)/$(VERSION); \
	fi
	az storage blob upload-batch -d porter/mixins/$(MIXIN)/$(PERMALINK) -s $(BINDIR)/$(VERSION)

clean:
	-rm -fr bin/
