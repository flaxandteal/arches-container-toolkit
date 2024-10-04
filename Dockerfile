ARG ARCHES_BASE=flaxandteal/arches_base
FROM $ARCHES_BASE

RUN useradd arches
RUN chgrp arches ../entrypoint.sh && chmod g+rx ../entrypoint.sh
ARG ARCHES_PROJECT
ENV ARCHES_PROJECT $ARCHES_PROJECT
COPY docker/entrypoint.sh ${WEB_ROOT}/
RUN apt-get update && apt-get -y install python3-libxml2 git
RUN apt-get -y install build-essential python3-dev 
RUN . ../ENV/bin/activate \
    && pip install --upgrade pip setuptools \
    && pip install starlette-graphene3 \
    && pip install "lxml" starlette-context "google-auth<2.23" django-authorization casbin-django-orm-adapter \
    && pip install django-debug-toolbar django-debug-toolbar-force # only needed in debug
COPY . ${WEB_ROOT}/${ARCHES_PROJECT}/
RUN . ../ENV/bin/activate \
    && pip install cachetools websockets pika "protobuf>4.21,<5.0" \
    && (if [ -f ${WEB_ROOT}/${ARCHES_PROJECT}/requirements.txt ]; then pip install -r ${WEB_ROOT}/${ARCHES_PROJECT}/requirements.txt --no-binary :all:; fi)

RUN mkdir -p ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/uploadedfiles && chgrp -R arches ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/uploadedfiles && chmod -R g+rw ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/uploadedfiles

COPY docker/settings_docker.py ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/settings_local.py
# RUN echo "{}" > ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}/webpack-stats.json
RUN echo "{}" > ${WEB_ROOT}/${ARCHES_PROJECT}/webpack/webpack-stats.json

WORKDIR ${WEB_ROOT}/${ARCHES_PROJECT}/${ARCHES_PROJECT}
RUN mkdir -p /static_root && chown -R arches /static_root
WORKDIR ${WEB_ROOT}/${ARCHES_PROJECT}
RUN ../entrypoint.sh install_npm_components
RUN . ../ENV/bin/activate && python manage.py
ENTRYPOINT ../entrypoint.sh
CMD run_arches
USER 1000
