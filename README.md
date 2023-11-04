# Arches F&T Container Toolkit

This is the toolkit for setting up and managing a new Arches instance.

## License

Some of the content here is from the AGPL-3.0 Arches project (specifically, adapted
forms of entrypoint.sh and init-unix.sql). Original content from F&T in this repository
can be considered to be under an MIT license.

## Vision

This is an alternative approach to container management than the documented
version in Arches core (with particular thanks to Open Context and Farallon Geographics!).

Historically, F&T has been working with an adapted form of the Arches 5 & 6 Dockerfile
to help streamline our Kubernetes project deployment flow, with least modification to the
Arches base. This means there are different design choices here than you might need if, for example,
you wish to run a docker-compose production instance -- for example, we:

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
