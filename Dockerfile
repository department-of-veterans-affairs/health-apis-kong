FROM kong:1.0.3

# https://github.com/department-of-veterans-affairs/health-apis-devops/blob/master/operations/application-base/Dockerfile
# necessary tools to run application
RUN apk update && apk add bash && apk add curl && apk add --update py-pip

# When running docker container, user must set the following unset variables at runtime
ENV AWS_ACCESS_KEY_ID=unset 
ENV AWS_SECRET_ACCESS_KEY=unset 
ENV AWS_DEFAULT_REGION=unset
ENV AWS_BUCKET_NAME=unset

ADD "https://s3.amazonaws.com/aws-cli/awscli-bundle.zip" /tmp/aws2/awscli-bundle.zip
RUN cd /tmp/aws2 && chmod 777 /tmp/aws2/awscli-bundle.zip && unzip /tmp/aws2/aws*.zip && /tmp/aws2/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws

# Copies custom Kong plugins to image
COPY kong/plugins/ /usr/local/share/lua/5.1/kong/plugins/

COPY docker-entrypoint.sh /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]

EXPOSE 8000 8443 8001 8444

STOPSIGNAL SIGTERM

CMD ["kong", "docker-start"]