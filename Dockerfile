FROM alpine:3.6
RUN apk add --no-cache perl-digest-sha1 bash inotify-tools

WORKDIR /app
COPY . /app

ENTRYPOINT ["./monitor.sh"]