FROM node:20-alpine3.20

WORKDIR /tmp

COPY start.sh ./

EXPOSE 8080

RUN apk update && apk add --no-cache bash openssl curl tar gcompat &&\
    chmod +x start.sh

# x-tunnel-img.playingapi.tech
CMD ["./start.sh"]
