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
ARCHES_NAMESPACE_FOR_DATA_EXPORT = os.getenv("ARCHES_NAMESPACE_FOR_DATA_EXPORT", "http://arches:8000/")
PUBLIC_SERVER_ADDRESS = os.getenv("PUBLIC_SERVER_ADDRESS", ARCHES_NAMESPACE_FOR_DATA_EXPORT)

CSRF_TRUSTED_ORIGINS = [f"https://{domain}" for domain in os.getenv("DOMAIN_NAMES", "").split()]
CELERY_BROKER_URL = os.getenv("CELERY_BROKER_URL", "amqp://{}:{}@{}".format(
    os.getenv("RABBITMQ_USER"),
    os.getenv("RABBITMQ_PASS"),
    os.getenv("RABBITMQ_HOST", "rabbitmq")
))  # RabbitMQ --> "amqp://guest:guest@localhost",  Redis --> "redis://localhost:6379/0"
RABBITMQ_USER = os.getenv("RABBITMQ_USER")
RABBITMQ_PASS = os.getenv("RABBITMQ_PASS")
RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
CASBIN_RELOAD_QUEUE = os.getenv("CASBIN_RELOAD_QUEUE", "reloadQueue")

for host in ELASTICSEARCH_HOSTS:
    host["scheme"] = "http"
    host["port"] = int(host["port"])
