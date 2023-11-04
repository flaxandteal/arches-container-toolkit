default: help

TOOLKIT_REPO = https://github.com/flaxandteal/arches-container-toolkit
TOOLKIT_FOLDER = docker
TOOLKIT_RELEASE = main
ARCHES_PROJECT = $(shell ls -1 */__init__.py | head -n 1 | sed 's/\/.*//g')
ARCHES_BASE = flaxandteal/arches_base
ARCHES_PROJECT_ROOT = $(shell pwd)/


.PHONY: docker
docker:
	@echo ARCHES_PROJECT is [$(ARCHES_PROJECT)]
	@echo $(wildcard $(TOOLKIT_FOLDER)/CONTAINER_TOOLS)
ifneq ("$(wildcard init-unix.sql)","")
	$(error It looks like you are running make in the tools directory itself - run 'make help' for information. Exiting:)
else ifeq ("$(wildcard manage.py)","")
	$(error It looks like you are not running make in the top-level project folder (where manage.py lives) - run 'make help' for information. Exiting:)
else ifneq ("$(wildcard $(TOOLKIT_FOLDER))","")
ifneq ("$(wildcard $(TOOLKIT_FOLDER)/CONTAINER_TOOLS)","")
	$(error It looks like your ./$(TOOLKIT_FOLDER) subfolder does not contain the Arches F&T Container Toolkit\
		you can try changing TOOLKIT_FOLDER in the Makefile to avoid a clash, but this is not a fully-supported use-case.)
endif
	@# It looks like the container tools are in place, so carry on.
else
	@echo "Did not find the Arches F&T Container Toolkit"
ifneq ("$(shell grep container-toolkit .gitmodules 2>/dev/null)","")
	@echo "Submodule present so updating it"
	git submodule update --init
endif
ifneq ("$(shell which git)", "")
ifeq ("$(shell git rev-parse --is-inside-work-tree 2>/dev/null)","true")
	@echo Fetching as a git submodule
	git submodule add --force $(TOOLKIT_REPO) $(TOOLKIT_FOLDER)
endif
endif
ifeq ("$(wildcard $(TOOLKIT_FOLDER))","")
	@echo No git or not a repo -- fetching as a tarball
	mkdir $(TOOLKIT_FOLDER)
	wget -q --content-disposition $(TOOLKIT_REPO)/tarball/$(TOOLKIT_RELEASE) -O $(TOOLKIT_FOLDER)/_toolkit.tgz
	@echo `export TD=$$(tar -vtzf $(TOOLKIT_FOLDER)/_toolkit.tgz --exclude='*/*' | awk '{print $$NF}' | head -n 1); tar -xzf $(TOOLKIT_FOLDER)/_toolkit.tgz; rm -rf $(TOOLKIT_FOLDER); echo Moving $$TD to $(TOOLKIT_FOLDER); mv $$TD $(TOOLKIT_FOLDER)`
endif
	@echo "Arches F&T Container Toolkit now in [$(TOOLKIT_FOLDER)]"
endif
	@if [ "$$(diff Makefile $(TOOLKIT_FOLDER)/Makefile)" != "" ]; then echo "Your Makefile in this directory does not match the one in directory [$(TOOLKIT_FOLDER)], do you need to update it by copy it over this one or vice versa?"; echo; fi

.PHONY: build
build: docker
	ARCHES_PROJECT_ROOT=$(ARCHES_PROJECT_ROOT) ARCHES_BASE=$(ARCHES_BASE) ARCHES_PROJECT=$(ARCHES_PROJECT) docker-compose -f docker/docker-compose.yml run --entrypoint /web_root/entrypoint.sh arches_worker bootstrap

.PHONY: run
run: docker
	ARCHES_PROJECT_ROOT=$(ARCHES_PROJECT_ROOT) ARCHES_BASE=$(ARCHES_BASE) ARCHES_PROJECT=$(ARCHES_PROJECT) docker-compose -f docker/docker-compose.yml up

.PHONY: clean
clean: docker
	@echo -n "This will remove all database and elasticsearch data, are you sure? [y/N] " && read confirmation && [ $${confirmation:-N} = y ]
	ARCHES_PROJECT_ROOT=$(ARCHES_PROJECT_ROOT) ARCHES_BASE=$(ARCHES_BASE) ARCHES_PROJECT=$(ARCHES_PROJECT) docker-compose -f docker/docker-compose.yml down -v --rmi all

.PHONY: help
help:
	@echo
	@echo "ARCHES F&T CONTAINER TOOLS"
	@echo "=========================="
	@echo
	@echo "This Makefile should be present in the top level directory of an Arches project, where manage.py lives. We make some"
	@echo "assumptions based on standard Arches project layout, as set up by 'arches-project create'. Running any other make"
	@echo "command should check whether there is a ./docker/ subfolder, and if not attempt to add the container tools as a submodule"
	@echo "if your project it versioned in git, or download a released copy to ./docker/ if not."
	@echo
	@echo "These are not directly compatible with the container approach in the Arches core tree (although we would like to align"
	@echo "progressively). If you are considering using these, take a look at ./docker/README.md."
	@echo
	@echo \(== ARCHES_PROJECT is [$(ARCHES_PROJECT)] ==\)
	@echo
	@echo "To set up a new project, ensure the ARCHES_PROJECT above is correct, then run 'make build', followed by 'make run'."
	@echo "If you do not see a project above or it is wrong, ensure that there is exactly one subfolder of this directory with an"
	@echo "__init__.py file."
	@echo
	@echo "Note that '$(ARCHES_PROJECT)/urls.py' must have (manually added) something similar to:"
	@echo "	if settings.DEBUG:"
	@echo "	    from django.contrib.staticfiles import views"
	@echo "	    from django.urls import re_path"
	@echo "	    urlpatterns += ["
	@echo "		re_path(r'^static/(?P<path>.*)\$', views.serve),"
	@echo "	    ]"
