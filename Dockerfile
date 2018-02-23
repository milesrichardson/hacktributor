FROM alpine:latest

RUN apk add --no-cache bash curl git

RUN mkdir -p /hacktributor

COPY feel_good_about_myself.sh /hacktributor/feel_good_about_myself.sh

WORKDIR /hacktributor

ENTRYPOINT ["/bin/bash", "/hacktributor/feel_good_about_myself.sh"]
