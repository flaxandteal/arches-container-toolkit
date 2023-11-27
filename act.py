#!/usr/bin/env python

"""
Arches F&T Container Toolkit
----------------------------

Helper script for setting up and managing containers.
It should have _no_ dependencies other than Python 3
standard libs and, within individual commands, the Arches Python
package since this is a listed step in Arches F&T
Container Toolkit installation.

It may use known Arches dependencies, but
should always try `import arches` first, to help
redirect users to installing Arches package, rather
than dependencies for this script.
"""

import argparse
import sys
import shutil
import subprocess
import os
from pathlib import Path

PROGRAM = "Arches F&T Container Toolkit"

class ArchesProject:
    @staticmethod
    def _get_arches_project_name(root: Path):
        project_name = None
        for submodule in root.glob("*/__init__.py"):
            if project_name:
                raise RuntimeError("There should be exactly one Python package in the project root!")
            project_name = str(submodule.parent.parts[-1])
        if not project_name:
            raise RuntimeError("Could not find a Python project in the project root!")
        return project_name

    def __init__(self, root):
        self.root = root
        self.name = self._get_arches_project_name(root)

        print("[ACT Python] Arches Project:", self.name)

    @property
    def package_folder(self):
        return self.root / self.name / "pkg"

    @property
    def ontologies_folder(self):
        return self.package_folder / "ontologies"

    def import_package(self, location, force=False):
        if self.package_folder.exists():
            if force:
                shutil.rmtree(self.package_folder)
            else:
                raise RuntimeError(f"A package has already been imported, please remove it from {self.package_folder} first!")
        print(f"Copying from {location} to {self.package_folder}")
        shutil.copytree(location, self.package_folder)
        do_import = input("Do you wish to do the installation to the database now? [y/N] ")
        if do_import == "y":
            self.load_package()

    def load_package(self, all_yes=False, load_business_data=True):
        if not self.package_folder.exists():
            raise RuntimeError(f"A package has not been imported, please provide one with import_package first!")
        print("Installing to DB with Makefile")
        if self.ontologies_folder.exists():
            self.run_manage_command(["load_ontology", "-s", self.ontologies_folder])
        self.run_manage_command(["packages", "-o", "load_package", "-s", self.package_folder] + (["-y"] if all_yes else []) + (["--no-business_data"] if not load_business_data else []))

    def wait_for_db(self):
        self.run_entrypoint_command(["wait_for_db"])

    def run_entrypoint_command(self, args):
        os.chdir(self.root)
        entrypoint_command = " ".join(map(str, args))
        subprocess.run([
            "make", "docker-compose",
            "CMD=\"run --entrypoint ../entrypoint.sh "
            f"arches_worker {entrypoint_command}\""
        ])

    def run_manage_command(self, args):
        os.chdir(self.root)
        manage_command = " ".join(map(str, args))
        subprocess.run([
            "make", "docker-compose",
            "CMD=\"run --entrypoint /bin/sh "
            "arches_worker -c "
            f"\\\". ../ENV/bin/activate; python manage.py {manage_command}\\\"\""
        ])


def run(args):
    parser = argparse.ArgumentParser(prog=PROGRAM)
    parser.add_argument('root', type=str, help='gives the location of the project root')
    subparsers = parser.add_subparsers(required=True)

    parser_ip = subparsers.add_parser('import_package', help='imports a package into the existing tree')
    parser_ip.add_argument('location', type=str, help='Folder containing package to import')
    parser_ip.add_argument('--force', action='store_true', help='Delete target package folder if it exists')
    def import_package(project, args):
        project.wait_for_db()
        project.import_package(Path(args.location), args.force)
    parser_ip.set_defaults(func=import_package)

    parser_lp = subparsers.add_parser('load_package', help='installs a package into the database')
    parser_lp.add_argument('--yes', action='store_true')
    def load_package(project, args):
        project.wait_for_db()
        project.load_package(all_yes=args.yes, load_business_data=not (os.getenv("NO_LOAD_BUSINESS_DATA", "") == "1"))
    parser_lp.set_defaults(func=load_package)

    args = parser.parse_args(args)
    project = ArchesProject(Path(args.root))
    args.func(project, args)

if __name__ == "__main__":

    run(sys.argv[1:])
