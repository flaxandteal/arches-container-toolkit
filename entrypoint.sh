#!/bin/bash

HELP_TEXT="

Arguments:
	run_arches: Default. Run the Arches server
	run_tests: Run unit tests
	setup_arches: Delete any existing Arches database and set up a fresh one
	-h or help: Display help text
"

display_help() {
	echo "${HELP_TEXT}"
}



CUSTOM_SCRIPT_FOLDER=${CUSTOM_SCRIPT_FOLDER:-/docker/entrypoint}
if [[ -z ${ARCHES_PROJECT} ]]; then
	APP_FOLDER=${ARCHES_ROOT}
	PACKAGE_JSON_FOLDER=${ARCHES_ROOT}/arches/install
else
	APP_FOLDER=${WEB_ROOT}/${ARCHES_PROJECT}
	# due to https://github.com/archesproject/arches/issues/4841, changes were made to npm install
	# and module deployment. Using the arches install directory for npm.
	# PTW PACKAGE_JSON_FOLDER=${ARCHES_ROOT}/arches/install
	PACKAGE_JSON_FOLDER=${WEB_ROOT}/${ARCHES_PROJECT}
fi

# Read modules folder from npm config file
# Get string after '--install.modules-folder' -> get first word of the result 
# -> remove line endlings -> trim quotes -> trim leading ./
NPM_MODULES_FOLDER=${PACKAGE_JSON_FOLDER}/node_modules

export DJANGO_PORT=${DJANGO_PORT:-8000}
STATIC_ROOT=${STATIC_ROOT:-/static_root}

export ALLOW_BOOTSTRAP=${ALLOW_BOOTSTRAP:-}


cd_web_root() {
	cd ${WEB_ROOT}
	echo "Current work directory: ${WEB_ROOT}"
}

cd_arches_root() {
	cd ${ARCHES_ROOT}
	echo "Current work directory: ${ARCHES_ROOT}"
}

cd_app_folder() {
	cd ${APP_FOLDER}
	echo "Current work directory: ${APP_FOLDER}"
}

cd_npm_folder() {
	cd ${PACKAGE_JSON_FOLDER}
	echo "Current work directory: ${PACKAGE_JSON_FOLDER}"
}

activate_virtualenv() {
	. ${WEB_ROOT}/ENV/bin/activate
}




#### Install

init_arches() {
	if db_exists; then
		echo "Database ${PGDBNAME} already exists, skipping initialization."
		echo ""
	else
		if [[ "${ALLOW_BOOTSTRAP}" == "True" ]]; then
			echo "Database ${PGDBNAME} does not exists yet, starting setup..."
			setup_arches
		else
			echo "Database ${PGDBNAME} does not exist yet, exiting until you 'entrypoint.sh bootstrap'..."
			sleep 1;
			exit 1;
		fi
	fi
}

bootstrap() {
	init_arches_project

	init_npm_components

	setup_arches

	run_npm_build_development

}


# Run a manage.py subcommand, aborting the whole run if it fails. Without this
# a failed setup step is invisible: the database ends up migrated but empty,
# which looks like a working install until you notice there are no system
# settings and no graphs.
run_manage() {
	echo "Running: python manage.py $*"
	cd_app_folder
	if ! python ${APP_FOLDER}/manage.py "$@"; then
		echo ""
		echo "*** FAILED: manage.py $* ***"
		echo "*** Aborting so a half-built database is not mistaken for a good one ***"
		exit 1
	fi
}

psql_maintenance() {
	psql --host=${PGHOST} --port=${PGPORT} --user=${PGUSERNAME} --dbname=postgres -v ON_ERROR_STOP=1 -c "$1"
}

# Do the destructive part from psql rather than from inside Django.
#
# setup_db performs the whole rebuild in a single Django process: it terminates
# every backend on the database, drops and recreates it, then carries on using
# the ORM and finally calls migrate. Anything an app sets up at startup or on
# first import therefore straddles the rebuild, and there are two ways that
# bites:
#
#   * an AppConfig.ready() that opens a connection (casbin_adapter does) has
#     that connection killed by the terminate, so the next ORM call raises
#     InterfaceError rather than the ProgrammingError arches guards against;
#   * importing a permission framework can register models belonging to an app
#     with no migrations, and the in-process migrate then dies with
#     InvalidBasesError.
#
# Dropping the database before any Django process starts means nothing can be
# holding a connection, and running each remaining step as its own manage.py
# invocation means no step can poison the next one.
recreate_database() {
	local template=${PGDBTEMPLATE:-template_postgis}
	echo "Dropping and recreating database ${PGDBNAME} from template ${template}..."
	psql_maintenance "DROP DATABASE IF EXISTS ${PGDBNAME} WITH (FORCE);"
	psql_maintenance "CREATE DATABASE ${PGDBNAME} WITH OWNER = ${PGUSERNAME} ENCODING = 'UTF8' TEMPLATE = ${template};"
}

# The step-by-step equivalent of 'manage.py setup_db --force'.
setup_db() {
	recreate_database

	local system_settings_dir system_settings_local
	# Read from Django rather than hardcoding, so this follows whatever arches
	# install and project settings are actually in use.
	system_settings_dir=$(cd ${APP_FOLDER} && python -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', '${ARCHES_PROJECT:-arches}.settings')
from django.conf import settings
print(os.path.join(settings.ROOT_DIR, 'db', 'system_settings'))
" | tail -n 1)
	system_settings_local=$(cd ${APP_FOLDER} && python -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', '${ARCHES_PROJECT:-arches}.settings')
from django.conf import settings
print(settings.SYSTEM_SETTINGS_LOCAL_PATH)
" | tail -n 1)

	run_manage migrate
	run_manage createcachetable
	run_manage es delete_indexes
	run_manage es setup_indexes
	run_manage packages -o import_graphs -s "${system_settings_dir}/Arches_System_Settings_Model.json"
	run_manage graph publish
	run_manage packages -o import_business_data -s "${system_settings_dir}/Arches_System_Settings.json" -ow overwrite

	if [[ -f "${system_settings_local}" ]]; then
		run_manage packages -o import_business_data -s "${system_settings_local}" -ow overwrite
	fi
}

# Setup Postgresql and Elasticsearch
setup_arches() {

	cd_arches_root

	echo "" && echo ""
	echo "*** Initializing database ***"
	echo ""
	echo "*** Any existing Arches database will be deleted ***"
	echo "" && echo ""

	echo "5" && sleep 10 && echo "4" && sleep 1 && echo "3" && sleep 1 && echo "2" && sleep 1 &&	echo "1" &&	sleep 1 && echo "0" && echo ""

	setup_db


	if [[ "${INSTALL_DEFAULT_GRAPHS}" == "True" ]]; then
		# Import graphs
		if ! graphs_exist; then
			echo "Running: python manage.py packages -o import_graphs"
			python ${APP_FOLDER}/manage.py packages -o import_graphs
		else
			echo "Graphs already exist in the database. Skipping 'import_graphs'."
		fi
	fi


	if [[ "${INSTALL_DEFAULT_CONCEPTS}" == "True" ]]; then
		# Import concepts
		if ! concepts_exist; then
			import_reference_data arches/db/schemes/arches_concept_scheme.rdf
		else
			echo "Concepts already exist in the database."
			echo "Skipping 'arches_concept_scheme.rdf'."
			echo "Skipping 'cvast_concept_scheme.rdf'."
		fi

		# Import collections
		if ! collections_exist; then
			import_reference_data arches/db/schemes/arches_concept_collections.rdf
		else
			echo "Collections already exist in the database."
			echo "Skipping 'import_reference_data arches_concept_collections.rdf'."
		fi
	fi

	run_migrations

	if [[ "${INSTALL_PACKAGE}" == "True" ]]; then
		run_manage es setup_indexes
		# Import graphs
		run_manage packages -o load_package -s ${ARCHES_PROJECT}/pkg/ -y
		run_manage es index_database
	fi
}

wait_for_db() {
	echo "Waiting for database and Elasticsearch..."

	# Poll both services in parallel
	(
		while ! psql --host=${PGHOST} --port=${PGPORT} --user=${PGUSERNAME} --dbname=postgres -c "select 1" &>/dev/null; do
			sleep 1
		done
		echo "Database server is up"
	) &

	(
		while ! curl -sf "http://${ESHOST}:${ESPORT}/_cluster/health?wait_for_status=yellow&timeout=60s" &>/dev/null; do
			sleep 1
		done
		echo "Elasticsearch is up"
	) &

	wait
	echo "All services are ready"
}

db_exists() {
	echo "Checking if database "${PGDBNAME}" exists..."
	count=`psql --host=${PGHOST} --port=${PGPORT} --user=${PGUSERNAME} --dbname=postgres -Atc "SELECT COUNT(*) FROM pg_catalog.pg_database WHERE datname='${PGDBNAME}'"`

	# Check if returned value is a number and not some error message
	re='^[0-9]+$'
	if ! [[ ${count} =~ $re ]] ; then
	   echo "Error: Something went wrong when checking if database "${PGDBNAME}" exists..." >&2;
	   echo "Exiting..."
	   exit 1
	fi

	# Return 0 (= true) if database exists
	if [[ ${count} > 0 ]]; then
		return 0
	else
		return 1
	fi
}

set_dev_mode() {
	echo ""
	echo ""
	echo "----- SETTING DEV MODE -----"
	echo ""
	cd_arches_root
	python ${ARCHES_ROOT}/setup.py develop
}


# npm
init_npm_components() {
	# If the image has webpack output pre-baked into media/build, node_modules is
	# not needed at runtime (django-webpack-loader resolves everything through
	# webpack-stats.json -> media/build). Skip the reinstall.
	local media_build="${PACKAGE_JSON_FOLDER}/${ARCHES_PROJECT}/media/build"
	if [[ -d "${media_build}" ]] && [[ -n "$(ls -A "${media_build}" 2>/dev/null)" ]]; then
		return 0
	fi
	if [[ "${SKIP_NPM_INSTALL:-false}" == "true" ]]; then
		return 0
	fi
	if [[ ! -d ${NPM_MODULES_FOLDER} ]] || [[ ! "$(ls ${NPM_MODULES_FOLDER})" ]]; then
		echo "npm modules do not exist, installing..."
		install_npm_components
	fi
}

# This is also done in Dockerfile, but that does not include user's custom Arches app package.json
# Also, the packages folder may have been overlaid by a Docker volume.
install_npm_components() {
	echo ""
	echo ""
	echo "----- INSTALLING NPM COMPONENTS -----"
	echo ""
	cd_npm_folder
	npm install
}

update_npm_components() {
	echo ""
	echo ""
	echo "----- UPDATING NPM COMPONENTS -----"
	echo ""
	cd_npm_folder
	npm update
}

#### Main commands
run_arches_graphql() {

	if [[ "${DJANGO_MODE}" == "DEV" ]]; then
		set_dev_mode
	fi

	run_graphql_server
}

run_graphql_server() {
	echo ""
	echo ""
	echo "----- *** RUNNING GRAPHQL SERVER *** -----"
	echo ""
	cd_app_folder
	
        uvicorn --host 0.0.0.0 --port 8000 ${ARCHES_PROJECT}.graph.asgi:app
}

run_npm_start() {
	echo ""
	echo ""
	echo "----- RUNNING NPM SERVER -----"
	echo ""
	cd_app_folder
	npm start
}

run_npm_build_production() {
	echo ""
	echo ""
	echo "----- RUNNING NPM BUILD PRODUCTION -----"
	echo ""
	cd_app_folder
	# Terser needs more headroom than Node's default heap. Overridable, so a
	# constrained runner can lower it rather than meeting the OOM killer.
	NODE_OPTIONS="${NODE_OPTIONS:---max_old_space_size=8192}" npm run build_production
}

run_npm_build_development() {
	echo ""
	echo ""
	echo "----- RUNNING NPM BUILD DEVELOPMENT -----"
	echo ""
	cd_app_folder
	npm run build_development
}


#### Misc

init_arches_project() {
	if [[ ! -z ${ARCHES_PROJECT} ]]; then
		echo "Checking if Arches project "${ARCHES_PROJECT}" exists..."
		if [[ ! -d ${APP_FOLDER} ]] || [[ ! "$(ls ${APP_FOLDER})" ]]; then
			echo ""
			echo "----- Custom Arches project '${ARCHES_PROJECT}' does not exist. -----"
			echo "----- Creating '${ARCHES_PROJECT}'... -----"
			echo ""

			cd_web_root
			[[ -d ${APP_FOLDER} ]] || mkdir ${APP_FOLDER}

			arches-project create ${ARCHES_PROJECT} --directory ${ARCHES_PROJECT}

			exit_code=$?
			if [[ ${exit_code} != 0 ]]; then
				echo "Something went wrong when creating your Arches project: ${ARCHES_PROJECT}."
				echo "Exiting..."
				exit ${exit_code}
			fi

			copy_settings_local
		else
			echo "Custom Arches project '${ARCHES_PROJECT}' already exists."
		fi
	fi
}


graphs_exist() {
	row_count=$(psql -h ${PGHOST} -p ${PGPORT} -U postgres -d ${PGDBNAME} -Atc "SELECT COUNT(*) FROM public.graphs")
	if [[ ${row_count} -le 3 ]]; then
		return 1
	else
		return 0
	fi
}

concepts_exist() {
	row_count=$(psql -h ${PGHOST} -p ${PGPORT} -U postgres -d ${PGDBNAME} -Atc "SELECT COUNT(*) FROM public.concepts WHERE nodetype = 'Concept'")
	if [[ ${row_count} -le 2 ]]; then
		return 1
	else
		return 0
	fi
}

collections_exist() {
	row_count=$(psql -h ${PGHOST} -p ${PGPORT} -U postgres -d ${PGDBNAME} -Atc "SELECT COUNT(*) FROM public.concepts WHERE nodetype = 'Collection'")
	if [[ ${row_count} -le 1 ]]; then
		return 1
	else
		return 0
	fi
}

import_reference_data() {
	# Import example concept schemes
	local rdf_file="$1"
	echo "Running: python manage.py packages -o import_reference_data -s \"${rdf_file}\""
	python ${APP_FOLDER}/manage.py packages -o import_reference_data -s "${rdf_file}"
}

copy_settings_local() {
	# The settings_local.py in ${ARCHES_ROOT}/arches/ gets ignored if running manage.py from a custom Arches project instead of Arches core app
	echo "Copying ${ARCHES_ROOT}/arches/settings_local.py to ${APP_FOLDER}/${ARCHES_PROJECT}/settings_local.py..."
	cp ${ARCHES_ROOT}/arches/settings_local.py ${APP_FOLDER}/${ARCHES_PROJECT}/settings_local.py
}

# Allows users to add scripts that are run on startup (after this entrypoint)
run_custom_scripts() {
	for file in ${CUSTOM_SCRIPT_FOLDER}/*; do
		if [[ -f ${file} ]]; then
			echo ""
			echo ""
			echo "----- RUNNING CUSTUM SCRIPT: ${file} -----"
			echo ""
			source ${file}
		fi
	done
}




#### Run

run_migrations() {
	echo ""
	echo ""
	echo "----- RUNNING DATABASE MIGRATIONS -----"
	echo ""
	cd_app_folder
	python manage.py migrate
	echo $?
	echo "[output code]"
	
	echo "Running: python manage.py createcachetable"
	python manage.py createcachetable
}

collect_static(){
	echo ""
	echo ""
	echo "----- NOT COLLECTING DJANGO STATIC FILES AS FROZEN -----"
	echo ""
	# cd_app_folder
	# python manage.py collectstatic --noinput
}

collect_static_real(){
	echo ""
	echo ""
	echo "----- COLLECT DJANGO STATIC FILES -----"
	echo ""
	cd_app_folder
	python manage.py collectstatic --noinput
}

# Used at static-image build time. If arches-base pre-baked the bulky core
# static (ARCHES_BASE_STATIC), seed STATIC_ROOT from it and only collect the
# cheap project delta. Older bases lack it: fall back to a full collect so the
# build never fails. See issue report 2026-05-19.
collect_static_baked(){
	cd_app_folder
	if [[ -n "${ARCHES_BASE_STATIC:-}" && -d "${ARCHES_BASE_STATIC}" ]]; then
		echo "----- COLLECT STATIC: seeding from baked base + project delta -----"
		mkdir -p "${STATIC_ROOT}"
		cp -a "${ARCHES_BASE_STATIC}/." "${STATIC_ROOT}/"
		# Skip the slow project node_modules walk (already covered by the
		# baked core set); -i can't exclude that prefixed root, so move it.
		[[ -d node_modules ]] && mv node_modules node_modules.full
	else
		echo "----- COLLECT STATIC: no baked base, full fallback collect -----"
	fi
	python manage.py collectstatic --noinput
}


run_django_server() {
	echo ""
	echo ""
	echo "----- *** RUNNING DJANGO DEVELOPMENT SERVER *** -----"
	echo ""
	cd_app_folder
	if [[ ${DJANGO_REMOTE_DEBUG} != "True" ]]; then
	    echo "Running Django with livereload."
		exec python manage.py runserver 0.0.0.0:${DJANGO_PORT}
	else
        echo "Running Django with options --noreload --nothreading for remote debugging."
		exec python manage.py runserver --noreload --nothreading 0.0.0.0:${DJANGO_PORT}
	fi
}

run_celery_worker() {
	echo ""
	echo ""
	echo "----- *** RUNNING CELERY WORKER *** -----"
	echo ""
	cd_app_folder
	exec python manage.py celery start
}

run_api_server() {
	echo ""
	echo ""
	echo "----- *** RUNNING API SERVER *** -----"
	echo ""
	cd_app_folder

	if [[ ! -z ${ARCHES_PROJECT} ]]; then
        DJANGO_SETTINGS_MODULE=${ARCHES_PROJECT}.settings gunicorn arches_orm.graphql.django_asgi:app \
            --config ${ARCHES_ROOT}/docker/gunicorn_config.py \
	    -k uvicorn.workers.UvicornWorker
	fi
}


run_gunicorn_server() {
	echo ""
	echo ""
	echo "----- *** RUNNING GUNICORN PRODUCTION SERVER *** -----"
	echo ""
	cd_app_folder
	
	if [[ ! -z ${ARCHES_PROJECT} ]]; then
        gunicorn ${ARCHES_PROJECT}.wsgi:application \
            --config ${ARCHES_ROOT}/docker/gunicorn_config.py
	else
        gunicorn arches.wsgi:application \
            --config ${ARCHES_ROOT}/docker/gunicorn_config.py
    fi
}

install_arches_apps() {
	echo "Installing local apps in editable mode..."

	ARCHES_APPS_DIR="${WEB_ROOT}/arches_apps"

	# Ensure the expected directory exists (mounted by docker-compose)
	if [[ ! -d "${ARCHES_APPS_DIR}" ]]; then
		echo "No arches_app directory found, mounted apps will not be installed"
		return 0
	fi

	# If directory exists but is empty, warn and skip installation.
	shopt -s nullglob
	apps=("${ARCHES_APPS_DIR}"/*)
	shopt -u nullglob
	if [[ ${#apps[@]} -eq 0 ]]; then
		echo "Warning: '${ARCHES_APPS_DIR}' is empty — nothing to install."
		return 0
	fi

	for d in "${ARCHES_APPS_DIR}"/*; do
		if [[ -d "$d" ]]; then
			# These apps are bind-mounted from the host, so they are owned by the
			# host UID rather than the container user. Git's "dubious ownership"
			# guard then blocks the VCS-versioning build backend from reading the
			# version, failing the editable build. Mark each app safe first.
			git config --global --add safe.directory "$d" || true
			# Try a full editable install first so the app's third-party deps
			# (e.g. jinja2, docxtpl for certificate-generator) get installed.
			# The already-installed arches satisfies every app's constraint, so
			# pip leaves it alone. Fall back to --no-deps only if resolution
			# fails (e.g. an unsatisfiable arches-* pin).
			pip install -e "$d" || pip install --no-deps -e "$d" || true
			echo "Installed $d"
		fi
	done
}

#### Main commands
run_arches() {

	init_arches

	init_npm_components

	if [[ "${DJANGO_MODE}" == "DEV" ]]; then
		if [[ "${USE_LOCAL_APPS}" == "true" ]]; then
			install_arches_apps
		fi
	fi

	run_custom_scripts

	if [[ "${DJANGO_MODE}" == "DEV" ]]; then
		run_django_server
	elif [[ "${DJANGO_MODE}" == "STATIC" ]]; then
		collect_static_real
	elif [[ "${DJANGO_MODE}" == "PROD" ]]; then
		run_gunicorn_server
	fi
}


run_tests() {
	set_dev_mode
	echo ""
	echo ""
	echo "----- RUNNING ARCHES TESTS -----"
	echo ""
	cd_arches_root
	PYTHONPATH=. python manage.py test tests --pattern="*.py" --settings="quartz.test.test_settings" --exe
	if [ $? -ne 0 ]; then
        echo "Error: Not all tests ran succesfully."
		echo "Exiting..."
        exit 1
	fi
}




### Starting point ###

activate_virtualenv

# Use -gt 1 to consume two arguments per pass in the loop (e.g. each
# argument has a corresponding value to go with it).
# Use -gt 0 to consume one or more arguments per pass in the loop (e.g.
# some arguments don't have a corresponding value to go with it, such as --help ).

# If no arguments are supplied, assume the server needs to be run
if [[ $#  -eq 0 ]]; then
	wait_for_db
	run_arches
fi

# Else, process arguments
echo "Full command: $@"
while [[ $# -gt 0 ]]
do
	key="$1"
	echo "Command: ${key}"

	case ${key} in
		bootstrap)
			wait_for_db
			bootstrap
		;;
		run_arches)
			wait_for_db
			run_arches
		;;
		run_api)
			wait_for_db
			run_api_server
		;;
		run_celery)
			wait_for_db
			run_celery_worker
		;;
		setup_arches)
			wait_for_db
			setup_arches
		;;
		run_arches_graphql)
			wait_for_db
			run_arches_graphql
		;;
		run_tests)
			wait_for_db
			run_tests
		;;
		run_migrations)
			wait_for_db
			run_migrations
		;;
		install_npm_components)
			install_npm_components
		;;
		install_arches_apps)
			install_arches_apps
		;;
		run_npm_build_development)
			run_npm_build_development
		;;
		run_npm_build_production)
			run_npm_build_production
		;;
		collect_static_baked)
			collect_static_baked
		;;
		run_npm_start)
			run_npm_start
		;;
		help|-h)
			display_help
		;;
		*)
            cd_app_folder
			"$@"
			exit 0
		;;
	esac
	shift # next argument or value
done
