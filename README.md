# Arches F&T Container Toolkit

[This](This) is a toolkit for setting up and managing a new Arches instance.

**PLEASE NOTE: THIS IS AN UNOFFICIAL, ALTERNATIVE CONTAINER TOOLKIT FOR ARCHES**

You probably want [the standard tooling](https://arches.readthedocs.io/en/stable/installing/docker/).

## Usage

### I have no existing Arches project, but can use `arches-project` command

Install the `arches-project` tool as per the [Arches documentation](https://arches.readthedocs.io/en/stable/).
Note that it requires `yarn` as a dependency. Run:

```
  arches-project create MYPROJECTNAME
  cd MYPROJECTNAME
  # If you wish to use git, then run: git commit -a -m "initial commit"
  wget https://raw.githubusercontent.com/flaxandteal/arches-container-toolkit/main/Makefile
  
  # Bug: currently a code block needs manually added to urls.py at this point
  # see make help for details
  make build
  make run
```

See the notes below for further details.

### I have no existing Arches project nor have installed Arches locally

The below is experimental. You should make sure not to pick an Arches project name that
could conflict with a Python module (e.g. `test`).

```
  wget https://raw.githubusercontent.com/flaxandteal/arches-container-toolkit/main/Makefile
  make create ARCHES_PROJECT=myprojectname
  
  # Bug: currently a code block needs manually added to urls.py at this point
  # see make help for details
  make build
  make run
```

See the notes below for further details.

### I have an existing Arches project

Make sure you have `docker-compose` and either `git`, or `wget` and `tar` available.

Download only the `Makefile` to your project folder, i.e. the same directory as
`manage.py`, and run:

```
  # Bug: currently a code block needs manually added to urls.py at this point
  # see make help for details
  make build
  make run
```

The `make build` command will **wipe all data in the (container) Postgres database,
if one already exists**. Note that it will set up a `./docker` submodule or subfolder by default, to pull in
the rest of the toolkit, so please make sure you do not have any conflicting folder
in the same location (there is experimental functionality to change the target folder
name, but mileage may vary). **Please note** you will need at least 10% of your disk
space free (even thought it won't be used), so that Elasticsearch will run
and not panic (otherwise you will get strange errors).


You can clean up all containers _and all data in the containers_ by running:

```
  make clean
```

Note that, if you wish to scrub generated files, such as `webpack-stats.json`, you may
need to use `sudo git clean -xdf` but **note that command will remove ALL uncommitted
files and folders in your repository**.

## License

Some of the content here is from the AGPL-3.0 Arches project (specifically, adapted
forms of entrypoint.sh and init-unix.sql). Original content from F&T in this repository
can be considered to be under an MIT license.

## Vision

This is an alternative approach to container management than the documented
version in Arches core (with particular thanks to Open Context and Farallon Geographics!).

Historically, F&T has been working with an adapted form of the Arches 5 & 6 Dockerfile
to help streamline our Kubernetes project deployment flow, with least modification to the
Arches base. This means there are different design choices here than you might need if,
for example, you wish to run a docker-compose production instance -- for example, we:

 - build separate static and dynamic containers
 - expect SSL to be separately managed
 - only consider local development defaults (for secrets, etc.)
 - do not actively support non-Linux development environments (although not actively discouraging PRs to do so)
 - attempt to parametrize such that our Docker files can be reused unmodified across projects
 - drive towards minimal per-project configuration, with assumptions based on the standard Arches project layout
 - have a hard requirement that Github Actions are a supported deployment flow and production containers should be identical to development
 - want to make Cypress easy and consistent between local development and CI
 - support GitOps flow to Kubernetes, to enable fully declarative deployment of Arches instances (work in progress but close!)
 - are working towards [Twelve-Factor](https://12factor.net/) principles, even where it increases complexity locally

We are very keen to dovetail if possible and propose amendments or reduce our adaptations
where we can but, for now, that means we do need distinct tools. Particularly, if you
wish to use the F&T Kubernetes tooling, you may find these make life easier for you.

Note: F&T is only in the name to avoid confusion with the more official Arches Docker approaches.
Ideally, in the medium-term, we can contribute code to a merged single toolkit in the core tree and drop
this repo, or keep it split out but drop F&T from the name.

## Acknowledgement

This repository would not exist, or our other Arches-based projects, without the hard work
of the Arches community and, in this repository particularly, code written by Farallon Geographics
and Open Context.
