#!/usr/bin/env python3
"""
Script to install an Arches app from a GitHub repository.
This script clones the repository, extracts package information from pyproject.toml,
and updates the project's settings.py, pyproject.toml, and urls.py files.
"""

import argparse
import os
import re
import subprocess
import sys


def run_command(cmd, cwd=None):
    """Run a shell command and return the result."""
    try:
        result = subprocess.run(
            cmd, shell=True, cwd=cwd, capture_output=True, text=True, check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError as e:
        print(f"Error running command '{cmd}': {e}")
        print(f"stderr: {e.stderr}")
        sys.exit(1)


def extract_repo_name(url):
    """Extract repository name from GitHub URL."""
    if url.endswith(".git"):
        url = url[:-4]
    return os.path.basename(url)


def create_apps_dir(apps_dir):
    """Create the arches_apps directory if it doesn't exist."""
    if not os.path.exists(apps_dir):
        os.makedirs(apps_dir)
        print(f"Created {apps_dir} directory")
    else:
        print(f"{apps_dir} already exists")


def clone_repository(url, target_dir, branch=None):
    """Clone the repository to the target directory."""
    if os.path.exists(target_dir):
        print(f"Repository already exists at {target_dir}, exiting...")
        sys.exit(0)

    branch_flag = f" --branch {branch}" if branch else ""
    print(
        f"Cloning repository into {target_dir}"
        + (f" (branch: {branch})" if branch else "")
    )
    run_command(f"git clone{branch_flag} {url} {target_dir}")
    print(f"Cloned repository into {target_dir}")


def parse_pyproject_toml(repo_dir):
    """Parse pyproject.toml and extract package name and optional dependencies."""
    pyproject_path = os.path.join(repo_dir, "pyproject.toml")

    if not os.path.exists(pyproject_path):
        print(f"Error: pyproject.toml not found in {repo_dir}")
        sys.exit(1)

    try:
        with open(pyproject_path, "r") as f:
            content = f.read()

        # Extract package name
        name_match = re.search(
            r'^name\s*=\s*["\']([^"\']+)["\']', content, re.MULTILINE
        )
        if not name_match:
            print("Error: Could not extract package name from pyproject.toml")
            sys.exit(1)

        package_name = name_match.group(1).replace("-", "_")

        # Extract optional dependencies keys
        optional_deps_keys = []
        optional_deps_section = re.search(
            r"\[project\.optional-dependencies\](.*?)(?=\n\[|\n\n|\Z)",
            content,
            re.DOTALL,
        )
        if optional_deps_section:
            deps_content = optional_deps_section.group(1)
            # Find all keys in the optional dependencies section
            key_matches = re.findall(
                r"^([a-zA-Z0-9_-]+)\s*=", deps_content, re.MULTILINE
            )
            optional_deps_keys = key_matches

        return package_name, optional_deps_keys
    except Exception as e:
        print(f"Error parsing pyproject.toml: {e}")
        sys.exit(1)


def update_installed_apps(settings_path, cloned_settings_path, package_name):
    """Update INSTALLED_APPS in the project settings.py by adding missing dependencies from cloned repo."""
    if not os.path.exists(settings_path):
        print(f"Error: settings.py not found at {settings_path}")
        return

    # Read project settings
    with open(settings_path, "r") as f:
        content = f.read()

    # Extract INSTALLED_APPS from cloned repo if it exists
    cloned_apps = set()
    if os.path.exists(cloned_settings_path):
        with open(cloned_settings_path, "r") as f:
            cloned_content = f.read()

        # Find INSTALLED_APPS = (...) with balanced parentheses
        lines = cloned_content.split("\n")
        in_installed_apps = False
        paren_count = 0

        for line in lines:
            if "INSTALLED_APPS" in line and "=" in line and "+=" not in line:
                in_installed_apps = True
                # Count opening parens/brackets in this line
                paren_count += line.count("(") + line.count("[")
                paren_count -= line.count(")") + line.count("]")

                # Extract apps from this line (skip if commented out)
                if not line.strip().startswith("#"):
                    app_matches = re.findall(r'["\']([^"\']+)["\']', line)
                    cloned_apps.update(
                        app.strip() for app in app_matches if app.strip()
                    )

                if paren_count == 0:
                    break
            elif in_installed_apps:
                # Count parens/brackets
                paren_count += line.count("(") + line.count("[")
                paren_count -= line.count(")") + line.count("]")

                # Extract apps from this line (skip if commented out)
                if not line.strip().startswith("#"):
                    app_matches = re.findall(r'["\']([^"\']+)["\']', line)
                    cloned_apps.update(
                        app.strip() for app in app_matches if app.strip()
                    )

                if paren_count == 0:
                    break

    # Always add the main package
    cloned_apps.add(package_name)

    # Extract current INSTALLED_APPS from project (both = and += sections)
    current_apps = set()
    lines = content.split("\n")

    # Parse INSTALLED_APPS = (...) section
    in_main_apps = False
    paren_count = 0
    for line in lines:
        if "INSTALLED_APPS" in line and "=" in line and "+=" not in line:
            in_main_apps = True
            paren_count += line.count("(") + line.count("[")
            paren_count -= line.count(")") + line.count("]")

            # Extract apps from this line (skip if commented out)
            if not line.strip().startswith("#"):
                app_matches = re.findall(r'["\']([^"\']+)["\']', line)
                current_apps.update(app.strip() for app in app_matches if app.strip())

            if paren_count == 0:
                break
        elif in_main_apps:
            paren_count += line.count("(") + line.count("[")
            paren_count -= line.count(")") + line.count("]")

            # Extract apps from this line (skip if commented out)
            if not line.strip().startswith("#"):
                app_matches = re.findall(r'["\']([^"\']+)["\']', line)
                current_apps.update(app.strip() for app in app_matches if app.strip())

            if paren_count == 0:
                break

    # Parse INSTALLED_APPS += (...) section
    in_plus_apps = False
    paren_count = 0
    for line in lines:
        if "INSTALLED_APPS" in line and "+=" in line:
            in_plus_apps = True
            paren_count += line.count("(") + line.count("[")
            paren_count -= line.count(")") + line.count("]")

            # Extract apps from this line (skip if commented out)
            if not line.strip().startswith("#"):
                app_matches = re.findall(r'["\']([^"\']+)["\']', line)
                current_apps.update(app.strip() for app in app_matches if app.strip())

            if paren_count == 0:
                break
        elif in_plus_apps:
            paren_count += line.count("(") + line.count("[")
            paren_count -= line.count(")") + line.count("]")

            # Extract apps from this line (skip if commented out)
            if not line.strip().startswith("#"):
                app_matches = re.findall(r'["\']([^"\']+)["\']', line)
                current_apps.update(app.strip() for app in app_matches if app.strip())

            if paren_count == 0:
                break

    # Find missing apps that need to be added
    missing_apps = cloned_apps - current_apps

    if not missing_apps:
        print(f"All required apps are already installed (including {package_name})")
        return

    print(f"Adding missing apps: {', '.join(sorted(missing_apps))}")

    # Find the INSTALLED_APPS += section and add missing apps
    plus_start_idx = None
    plus_end_idx = None

    for i, line in enumerate(lines):
        if "INSTALLED_APPS" in line and "+=" in line:
            plus_start_idx = i
            paren_count = (
                line.count("(") + line.count("[") - line.count(")") - line.count("]")
            )

            if paren_count == 0:
                plus_end_idx = i
                break
            else:
                # Find the closing paren/bracket
                for j in range(i + 1, len(lines)):
                    paren_count += lines[j].count("(") + lines[j].count("[")
                    paren_count -= lines[j].count(")") + lines[j].count("]")
                    if paren_count == 0:
                        plus_end_idx = j
                        break
            break

    if plus_start_idx is not None and plus_end_idx is not None:
        # Insert missing apps before the closing parenthesis
        new_lines = lines[:plus_end_idx]
        for app in sorted(missing_apps):
            new_lines.append(f'    "{app}",')
        new_lines.extend(lines[plus_end_idx:])

        # Write back to file
        with open(settings_path, "w") as f:
            f.write("\n".join(new_lines))

        print(
            f"Added {len(missing_apps)} apps to INSTALLED_APPS += section in {settings_path}"
        )
    else:
        print("Warning: Could not find INSTALLED_APPS += section to add missing apps")


def update_pyproject_dependencies(pyproject_path, package_name, optional_deps_keys):
    """Update dependencies in the project pyproject.toml."""
    if not os.path.exists(pyproject_path):
        print(f"Error: pyproject.toml not found at {pyproject_path}")
        return

    try:
        with open(pyproject_path, "r") as f:
            content = f.read()

        # Find the dependencies section
        deps_match = re.search(r"dependencies\s*=\s*\[(.*?)\]", content, re.DOTALL)
        if not deps_match:
            print("Error: Could not find dependencies section in pyproject.toml")
            return

        current_deps_text = deps_match.group(1)

        # Create dependency string
        if optional_deps_keys:
            # Use the first optional dependency key
            dep_string = f"{package_name}[{optional_deps_keys[0]}]"
        else:
            dep_string = package_name

        # Check if already in dependencies
        if dep_string in current_deps_text or package_name in current_deps_text:
            print(f"{dep_string} already in dependencies")
            return

        # Parse existing dependencies to properly format
        if current_deps_text.strip():
            # Split into lines and clean up
            lines = current_deps_text.split("\n")
            existing_deps = []

            for line in lines:
                line = line.strip()
                if line and not line.startswith("#"):
                    # Remove trailing comma and quotes, extract dependency name
                    dep_line = line.rstrip(",").strip()
                    if dep_line.startswith('"') and dep_line.endswith('"'):
                        existing_deps.append(dep_line)
                    elif dep_line.startswith("'") and dep_line.endswith("'"):
                        existing_deps.append(dep_line)
                    elif dep_line and not dep_line.startswith("#"):
                        # Add quotes if missing
                        existing_deps.append(f'"{dep_line}"')

            # Add the new dependency
            existing_deps.append(f'"{dep_string}"')

            # Format with proper indentation and commas
            new_deps_text = "\n    " + ",\n    ".join(existing_deps) + "\n"
        else:
            # No existing dependencies
            new_deps_text = f'\n    "{dep_string}"\n'

        new_dependencies = f"dependencies = [{new_deps_text}]"
        new_content = re.sub(
            r"dependencies\s*=\s*\[.*?\]", new_dependencies, content, flags=re.DOTALL
        )

        with open(pyproject_path, "w") as f:
            f.write(new_content)

        print(f"Added {dep_string} to dependencies in {pyproject_path}")

    except Exception as e:
        print(f"Error updating pyproject.toml: {e}")


def update_urls_py(urls_path, package_name):
    """Update urls.py to include the new package URLs."""
    if not os.path.exists(urls_path):
        print(f"Error: urls.py not found at {urls_path}")
        return

    with open(urls_path, "r") as f:
        content = f.read()

    # Check if the URL pattern already exists
    url_pattern = f"urlpatterns.append(path('', include('{package_name}.urls')))"
    if url_pattern in content:
        print(f"URL pattern for {package_name} already exists in urls.py")
        return

    # Find the line with arches.urls and add after it
    arches_pattern = r"urlpatterns\.append\(path\('', include\('arches\.urls'\)\)\)"
    if re.search(arches_pattern, content):
        new_content = re.sub(
            arches_pattern,
            f"urlpatterns.append(path('', include('arches.urls')))\n{url_pattern}",
            content,
        )

        with open(urls_path, "w") as f:
            f.write(new_content)

        print(f"Added URL pattern for {package_name} to {urls_path}")
    else:
        print("Could not find arches.urls pattern in urls.py")


def main():
    parser = argparse.ArgumentParser(
        description="Install an Arches app from a GitHub repository"
    )
    parser.add_argument("url", help="GitHub repository URL")
    parser.add_argument("--branch", "-b", default=None, help="Git branch to clone")
    parser.add_argument("--project-root", default=".", help="Project root directory")

    args = parser.parse_args()

    # Determine project structure
    project_root = os.path.abspath(args.project_root)
    apps_dir = os.path.join(os.path.dirname(project_root), "arches_apps")

    # Find the Arches project directory (contains __init__.py)
    project_dirs = [
        d
        for d in os.listdir(project_root)
        if os.path.isdir(os.path.join(project_root, d))
        and os.path.exists(os.path.join(project_root, d, "__init__.py"))
    ]

    if not project_dirs:
        print(
            "Error: Could not find Arches project directory (no directory with __init__.py found)"
        )
        sys.exit(1)

    arches_project = project_dirs[0]

    # Extract repository name
    repo_name = extract_repo_name(args.url)
    repo_dir = os.path.join(apps_dir, repo_name)

    # Create apps directory
    create_apps_dir(apps_dir)

    # Clone repository
    clone_repository(args.url, repo_dir, args.branch)

    # Parse pyproject.toml
    package_name, optional_deps_keys = parse_pyproject_toml(repo_dir)

    # Update project files
    settings_path = os.path.join(project_root, arches_project, "settings.py")
    cloned_settings_path = os.path.join(repo_dir, package_name, "settings.py")
    pyproject_path = os.path.join(project_root, "pyproject.toml")
    urls_path = os.path.join(project_root, arches_project, "urls.py")

    update_installed_apps(settings_path, cloned_settings_path, package_name)
    update_pyproject_dependencies(pyproject_path, package_name, optional_deps_keys)
    update_urls_py(urls_path, package_name)

    print(f"Successfully installed {package_name} from {args.url}")


if __name__ == "__main__":
    main()
