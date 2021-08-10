FROM debian:stable-slim
RUN apt update && apt install inotify-tools -y

WORKDIR /app
COPY . /app

ENTRYPOINT ["./monitor.sh"]

