import os
from arches.settings import ELASTICSEARCH_HOSTS, DATABASES
from arches.settings_docker import *
ALLOWED_HOSTS = ['localhost', '*'] # get_env_variable("DOMAIN_NAMES").split()

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {"console": {"format": "%(asctime)s %(name)-12s %(levelname)-8s %(message)s",},},
    "handlers": {
        "console": {"level": "WARNING", "class": "logging.StreamHandler", "formatter": "console"},
    },
    "loggers": {"arches": {"handlers": ["console"], "level": "WARNING", "propagate": True}},
}

MOBILE_OAUTH_CLIENT_ID = os.getenv("MOBILE_OAUTH_CLIENT_ID")
STATIC_URL = os.getenv("STATIC_URL") or "/static/"
STATIC_ROOT = os.getenv("STATIC_ROOT") or "/static_root"
COMPRESS_OFFLINE = os.getenv("COMPRESS_OFFLINE")
COMPRESS_OFFLINE = COMPRESS_OFFLINE and COMPRESS_OFFLINE.lower() == "true"
COMPRESS_ENABLED = os.getenv("COMPRESS_ENABLED")
COMPRESS_ENABLED = COMPRESS_ENABLED and COMPRESS_ENABLED.lower() == "true"

# Cover both forms, the first being deprecated
ARCHES_NAMESPACE_FOR_DATA_EXPORT = "http://arches:8000/"
PUBLIC_SERVER_ADDRESS = "http://arches:8000/"

for host in ELASTICSEARCH_HOSTS:
    host["scheme"] = "http"
    host["port"] = int(host["port"])
