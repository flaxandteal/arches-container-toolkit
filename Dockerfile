ARG ARCHES_BASE=ghcr.io/flaxandteal/arches-base:v8.2.0a8-v1
FROM $ARCHES_BASE

ARG ARCHES_PROJECT
ENV ARCHES_PROJECT $ARCHES_PROJECT
COPY ${ARCHES_PROJECT}/docker/entrypoint.sh ${WEB_ROOT}/
RUN chgrp 1000 ../entrypoint.sh && chmod g+rx ../entrypoint.sh
RUN apt-get update && apt-get -y install --no-install-recommends \
    python3-libxml2 git build-essential python3-dev xmlsec1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
RUN . ../ENV/bin/activate \
    && pip install --no-cache-dir --upgrade pip setuptools \
    && pip install --no-cache-dir starlette-graphene3 "lxml" starlette-context "google-auth<2.23" \
       django-authorization casbin-django-orm-adapter \
       django-debug-toolbar django-debug-toolbar-force
COPY ${ARCHES_PROJECT}/ ${WEB_ROOT}/${ARCHES_PROJECT}/
ARG EDITABLE_BASE=false
RUN . ../ENV/bin/activate \
    && pip install --no-cache-dir cachetools websockets pika "protobuf>4.21,<5.0" \
    && if [ "$EDITABLE_BASE" = "True" ]; then \
        pip install --no-cache-dir -e ${WEB_ROOT}/arches; \
    else \
        pip install --no-cache-dir ${WEB_ROOT}/arches; \
    fi \
    && (if [ -f ${WEB_ROOT}/${ARCHES_PROJECT}/pyproject.toml ]; then (cd ${WEB_ROOT}/${ARCHES_PROJECT} && pip install --no-cache-dir -e .); fi) \
    && if [ "$EDITABLE_BASE" = "True" ]; then \
        pip install --no-cache-dir --no-deps -e ${WEB_ROOT}/arches; \
    fi

ARG USE_LOCAL_APPS=false
COPY arches_app[s]/ ${WEB_ROOT}/arches_apps/
RUN if [ "$USE_LOCAL_APPS" = "true" ]; then \
        . ../ENV/bin/activate && \
        for d in ${WEB_ROOT}/arches_apps/*/; do \
            git config --global --add safe.directory "$d" || true; \
            pip install --no-cache-dir -e "$d" || pip install --no-cache-dir --no-deps -e "$d" || true; \
        done; \
    fi

RUN mkdir -p ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/uploadedfiles && chgrp -R 1000 ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/uploadedfiles && chmod -R g+rw ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/uploadedfiles

COPY ${ARCHES_PROJECT}/docker/settings_docker.py ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/settings_local.py
RUN echo '{"status": "", "assets": {}, "chunks": {}, "publicPath": "/static/"}' > ${WEB_ROOT}/${ARCHES_PROJECT}/webpack/webpack-stats.json
RUN printf '{"extends": "./%s/tsconfig.json"}' "${ARCHES_PROJECT}" > ${WEB_ROOT}/tsconfig.json

WORKDIR ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}
RUN mkdir -p /static_root && chown -R 1000 /static_root
RUN mkdir -p ${WEB_ROOT}/${ARCHES_PROJECT}/frontend_configuration && chown -R 1000 ${WEB_ROOT}/${ARCHES_PROJECT}/frontend_configuration
WORKDIR ${WEB_ROOT}/${ARCHES_PROJECT}
RUN ../entrypoint.sh install_npm_components \
    && npm cache clean --force \
    && rm -rf /root/.npm /tmp/*
RUN if [ "$USE_LOCAL_APPS" = "true" ]; then \
        ../entrypoint.sh run_npm_build_development; \
    fi

# Strip caches and node_modules. webpack output lives in media/build and is
# served via webpack-stats.json; nothing at runtime reads node_modules. In local
# dev the host bind-mount overlays the project dir so the host's node_modules
# is used; the entrypoint's init_npm_components reinstalls only if media/build
# is absent (i.e. fresh local checkout).
RUN rm -rf ${WEB_ROOT}/${ARCHES_PROJECT}/node_modules \
           /root/.cache/pip /root/.npm /tmp/* \
    && find ${WEB_ROOT} -type d -name __pycache__ -prune -exec rm -rf {} + || true

ENTRYPOINT ["../entrypoint.sh"]
CMD ["run_arches"]
USER 1000
