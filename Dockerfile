ARG KONG_VERSION=2.0.4
FROM kong:$KONG_VERSION

USER root

# =~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~
# Some Required Tools
# https://github.com/department-of-veterans-affairs/health-apis-devops/blob/master/operations/application-base/Dockerfile
# =~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~

RUN apk update \
  && apk add bash \
  && apk add ca-certificates \
  && apk add curl \
  && apk add --update py-pip

# =~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~
# Install VA certs
# =~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~

RUN wget -P /tmp/ http://aia.pki.va.gov/PKI/AIA/VA/VA-Internal-S2-RCA1-v1.cer \
  && openssl x509 -inform der \
       -in /tmp/VA-Internal-S2-RCA1-v1.cer \
       -out /usr/local/share/ca-certificates/VA-Internal-S2-RCA1-v1.pem \
  && update-ca-certificates --fresh

# =~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~
# Install Amazon Web Service Command Line Interface
# =~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~

# When running docker container, user must set the following unset variables at runtime
ENV AWS_DEFAULT_REGION=unset
ENV AWS_BUCKET_NAME=unset

# aws-cli: Version 1
# Per the following: https://github.com/aws/aws-cli/issues/4685#issuecomment-556436861
# The aws-cli version 2 installer requires glibc and other libraries to install.
# Apline does not come with these packages preinstalled, so we must stay with v1.

RUN curl -so /tmp/awscli-bundle.zip https://s3.amazonaws.com/aws-cli/awscli-bundle.zip \
  && unzip -q /tmp/awscli-bundle.zip -d /tmp/ \
  && /tmp/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws \
  && aws --version

# =~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~
# Do Kong Things
# =~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~=~

# Copy in Kong configuration file, only used for local development due to sensitive plugin configuration
# COPY kong.yml /etc/kong/kong.yml

# Copies custom Kong plugins to image
COPY kong/plugins/ /usr/local/share/lua/5.1/kong/plugins/

COPY docker-entrypoint.sh /docker-entrypoint.sh

RUN chmod 777 /docker-entrypoint.sh && chmod 777 /opt/ && chmod 777 /etc/kong/

USER kong

ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 8000 8443 8001 8444

STOPSIGNAL SIGTERM

CMD ["kong", "docker-start"]
