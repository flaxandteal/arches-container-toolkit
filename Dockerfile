ARG ARCHES_BASE=ghcr.io/flaxandteal/arches-base:docker-8.1.0-release
FROM $ARCHES_BASE

ARG ARCHES_PROJECT
ENV ARCHES_PROJECT $ARCHES_PROJECT
COPY docker/entrypoint.sh ${WEB_ROOT}/
RUN chgrp 1000 ../entrypoint.sh && chmod g+rx ../entrypoint.sh
RUN apt-get update && apt-get -y install --no-install-recommends \
    python3-libxml2 git build-essential python3-dev xmlsec1 \
    && rm -rf /var/lib/apt/lists/*
RUN . ../ENV/bin/activate \
    && pip install --upgrade pip setuptools \
    && pip install starlette-graphene3 "lxml" starlette-context "google-auth<2.23" \
       django-authorization casbin-django-orm-adapter \
       django-debug-toolbar django-debug-toolbar-force
COPY . ${WEB_ROOT}/${ARCHES_PROJECT}/
ARG EDITABLE_BASE=false
RUN . ../ENV/bin/activate \
    && pip install cachetools websockets pika "protobuf>4.21,<5.0" \
    && if [ "$EDITABLE_BASE" = "True" ]; then \
        pip install -e ${WEB_ROOT}/arches; \
    else \
        pip install ${WEB_ROOT}/arches; \
    fi \
    && (if [ -f ${WEB_ROOT}/${ARCHES_PROJECT}/requirements.txt ]; then pip install -r ${WEB_ROOT}/${ARCHES_PROJECT}/requirements.txt; fi) \
    && (if [ -f ${WEB_ROOT}/${ARCHES_PROJECT}/pyproject.toml ]; then (cd ${WEB_ROOT}/${ARCHES_PROJECT} && pip install -e .); fi) \
    && if [ "$EDITABLE_BASE" = "True" ]; then \
        pip install -e ${WEB_ROOT}/arches; \
    fi

ARG USE_LOCAL_APPS=false
COPY arches_app[s]/ ${WEB_ROOT}/arches_apps/
RUN if [ "$USE_LOCAL_APPS" = "true" ]; then \
        . ../ENV/bin/activate && \
        for d in ${WEB_ROOT}/arches_apps/*/; do \
            pip install --no-deps -e "$d" || true; \
        done; \
    fi

RUN mkdir -p ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/uploadedfiles && chgrp -R 1000 ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/uploadedfiles && chmod -R g+rw ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/uploadedfiles

COPY docker/settings_docker.py ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/settings_local.py
RUN echo '{"status": "", "assets": {}, "chunks": {}, "publicPath": "/static/"}' > ${WEB_ROOT}/${ARCHES_PROJECT}/webpack/webpack-stats.json

WORKDIR ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}
RUN mkdir -p /static_root && chown -R 1000 /static_root
RUN mkdir -p ${WEB_ROOT}/${ARCHES_PROJECT}/frontend_configuration && chown -R 1000 ${WEB_ROOT}/${ARCHES_PROJECT}/frontend_configuration
WORKDIR ${WEB_ROOT}/${ARCHES_PROJECT}
RUN ../entrypoint.sh install_npm_components
RUN if [ "$USE_LOCAL_APPS" = "true" ]; then \
        ../entrypoint.sh run_npm_build_development; \
    fi
ENTRYPOINT ["../entrypoint.sh"]
CMD ["run_arches"]
USER 1000
